#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$script_dir/lib/workspace_config.sh"
feature_dir=""; decision=""; run_id=""; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; force_evaluate=false; implementation_stage=""; implementation_run_id=""; config_path="$(default_workspace_config_path "$script_dir")"
while [[ $# -gt 0 ]]; do case "$1" in --feature-dir) feature_dir="$2"; shift 2;; --config) config_path="$2"; shift 2;; --decision) decision="$2"; shift 2;; --run-id) run_id="$2"; shift 2;; --now) now="$2"; shift 2;; --force-evaluate) force_evaluate=true; shift;; --implementation-stage) implementation_stage="$2"; shift 2;; --implementation-run-id) implementation_run_id="$2"; shift 2;; *) echo "unknown arg: $1" >&2; exit 24;; esac; done
[[ -n "$feature_dir" && -n "$decision" && -n "$run_id" ]] || { echo "feature directory, decision, and run ID are required" >&2; exit 24; }
mode="$(workspace_quality_mode "$config_path")"; if [[ "$mode" == off && "$force_evaluate" != true ]]; then echo "quality mode is off; use --force-evaluate to run" >&2; exit 24; fi
policy="$(workspace_quality_policy_path "$config_path" 2>/dev/null)" || { echo "quality policy is required" >&2; exit 24; }; validate_quality_policy "$policy" || exit 24
budget="$(jq -r '.budgets.repair_attempts' "$policy")"; attempt=0
[[ -n "$implementation_run_id" ]] || implementation_run_id="$run_id-implementation"
while true; do
  while IFS=$'\t' read -r repository_id base head subject; do
    [[ -n "$repository_id" ]] || continue
    [[ -n "$base" && "$base" != "null" && -n "$head" && "$head" != "null" ]] || {
      echo "scope refresh requires base and head for repository $repository_id" >&2
      exit 24
    }
    capture_head="$head"
    [[ "$subject" == worktree:* ]] && capture_head="WORKTREE"
    bash "$script_dir/capture-feature-scope.sh" --feature-dir "$feature_dir" --config "$config_path" --repository "$repository_id" --base "$base" --head "$capture_head" --now "$now" || exit 24
  done < <(jq -r '.repositories[]? | [.id,(.base // "null"),(.head // "null"),.subject] | @tsv' "$feature_dir/scope.json")
  bash "$script_dir/resolve-quality-gates.sh" --feature-dir "$feature_dir" --config "$config_path" --now "$now" || exit 24
  bash "$script_dir/run-quality-providers.sh" --feature-dir "$feature_dir" --config "$config_path" --decision "$decision" --run-id "$run_id-$attempt" || true
  while IFS= read -r verifier_provider; do
    while IFS= read -r repository_id; do
      [[ -n "$repository_id" ]] || continue
      verifier_run_id="$run_id-verifier-$attempt-$verifier_provider-$repository_id"
      bash "$script_dir/run-independent-verifier.sh" --feature-dir "$feature_dir" --config "$config_path" --provider "$verifier_provider" --repository "$repository_id" --implementation-run-id "$implementation_run_id" --run-id "$verifier_run_id" --now "$now" || true
    done < <(jq -r --arg provider "$verifier_provider" --slurpfile scope "$feature_dir/scope.json" '
      .providers[$provider] as $p |
      $scope[0].repositories[] as $repository |
      select((($p.repository_ids // []) | index($repository.id)) != null or ($p.repository_role? == $repository.role)) |
      $repository.id
    ' "$policy" | sort -u)
  done < <(jq -r --arg decision "$decision" --slurpfile plan "$feature_dir/state/gate-plan.json" '
    [.providers | to_entries[] | select(.value.kind=="verifier") | .key] as $verifiers |
    [$plan[0].gates[] | select(.applicability=="required" and (.decisions|index($decision))) | .providers[] | select(. as $id | $verifiers|index($id))] | unique[]
  ' "$policy")
  bash "$script_dir/evaluate-readiness.sh" --feature-dir "$feature_dir" --config "$config_path" --decision "$decision" --now "$now" || exit 24
  bash "$script_dir/render-quality-reports.sh" --feature-dir "$feature_dir" || exit 24
  status="$(jq -r .status "$feature_dir/state/readiness.json")"
  if [[ "$status" == ready || "$mode" == observe || "$mode" == off ]]; then exit 0; fi
  if jq -e '.human_action_required==true' "$feature_dir/state/repair-brief.json" >/dev/null || [[ "$status" == blocked ]]; then break; fi
  if [[ "$attempt" -ge "$budget" ]]; then exit 23; fi
  [[ -n "$implementation_stage" ]] || break
  bash "$script_dir/run-speckit-stage.sh" --feature-dir "$feature_dir" --stage "$implementation_stage" --config "$config_path" --run-id "$run_id-repair-$attempt" --repair-brief "$feature_dir/state/repair-brief.json" --sandbox workspace-write || exit 21
  implementation_run_id="$run_id-repair-$attempt"
  attempt=$((attempt+1))
done
case "$status" in incomplete) exit 20;; failed) exit 21;; blocked) exit 22;; *) exit 24;; esac
