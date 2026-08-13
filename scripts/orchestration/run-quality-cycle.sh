#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$script_dir/lib/workspace_config.sh"
feature_dir=""; decision=""; run_id=""; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; force_evaluate=false; implementation_stage=""; config_path="$(default_workspace_config_path "$script_dir")"
while [[ $# -gt 0 ]]; do case "$1" in --feature-dir) feature_dir="$2"; shift 2;; --config) config_path="$2"; shift 2;; --decision) decision="$2"; shift 2;; --run-id) run_id="$2"; shift 2;; --now) now="$2"; shift 2;; --force-evaluate) force_evaluate=true; shift;; --implementation-stage) implementation_stage="$2"; shift 2;; *) echo "unknown arg: $1" >&2; exit 24;; esac; done
[[ -n "$feature_dir" && -n "$decision" && -n "$run_id" ]] || { echo "feature directory, decision, and run ID are required" >&2; exit 24; }
mode="$(workspace_quality_mode "$config_path")"; if [[ "$mode" == off && "$force_evaluate" != true ]]; then echo "quality mode is off; use --force-evaluate to run" >&2; exit 24; fi
policy="$(workspace_quality_policy_path "$config_path" 2>/dev/null)" || { echo "quality policy is required" >&2; exit 24; }; validate_quality_policy "$policy" || exit 24
budget="$(jq -r '.budgets.repair_attempts' "$policy")"; attempt=0
while true; do
  bash "$script_dir/resolve-quality-gates.sh" --feature-dir "$feature_dir" --config "$config_path" --now "$now" || exit 24
  bash "$script_dir/run-quality-providers.sh" --feature-dir "$feature_dir" --config "$config_path" --decision "$decision" --run-id "$run_id-$attempt" || true
  bash "$script_dir/evaluate-readiness.sh" --feature-dir "$feature_dir" --config "$config_path" --decision "$decision" --now "$now" || exit 24
  bash "$script_dir/render-quality-reports.sh" --feature-dir "$feature_dir" || exit 24
  status="$(jq -r .status "$feature_dir/state/readiness.json")"
  if [[ "$status" == ready || "$mode" == observe || "$mode" == off ]]; then exit 0; fi
  if jq -e '.human_action_required==true' "$feature_dir/state/repair-brief.json" >/dev/null || [[ "$status" == blocked ]]; then break; fi
  if [[ "$attempt" -ge "$budget" ]]; then exit 23; fi
  [[ -n "$implementation_stage" ]] || break
  bash "$script_dir/run-speckit-stage.sh" --feature-dir "$feature_dir" --stage "$implementation_stage" --config "$config_path" --run-id "$run_id-repair-$attempt" --repair-brief "$feature_dir/state/repair-brief.json" --sandbox workspace-write || exit 21
  attempt=$((attempt+1))
done
case "$status" in incomplete) exit 20;; failed) exit 21;; blocked) exit 22;; *) exit 24;; esac
