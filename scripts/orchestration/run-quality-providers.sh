#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$script_dir/lib/workspace_config.sh"
feature_dir=""; decision=""; run_id=""; config_path="$(default_workspace_config_path "$script_dir")"
while [[ $# -gt 0 ]]; do case "$1" in --feature-dir) feature_dir="$2"; shift 2;; --config) config_path="$2"; shift 2;; --decision) decision="$2"; shift 2;; --run-id) run_id="$2"; shift 2;; *) echo "unknown arg: $1" >&2; exit 1;; esac; done
[[ -n "$feature_dir" && -n "$decision" && -n "$run_id" ]] || { echo "feature directory, decision, and run ID are required" >&2; exit 1; }
policy="$(workspace_quality_policy_path "$config_path")"; retries="$(jq -r '.budgets.provider_retries' "$policy")"
jq -r --arg decision "$decision" '.gates[]|select(.applicability=="required" and (.decisions|index($decision)))|. as $g|.providers[]|[.,$g.evidence_types[0]]|@tsv' "$feature_dir/state/gate-plan.json" | sort -u | while IFS=$'\t' read -r provider type; do
  kind="$(jq -r --arg id "$provider" '.providers[$id].kind' "$policy")"; [[ "$kind" == command ]] || continue
  attempt=0
  while true; do
    set +e; bash "$script_dir/run-evidence-provider.sh" --feature-dir "$feature_dir" --config "$config_path" --provider "$provider" --evidence-type "$type" --run-id "$run_id-$attempt"; status=$?; set -e
    [[ $status -eq 75 && $attempt -lt $retries ]] || { [[ $status -eq 0 || $status -eq 75 ]] || exit "$status"; break; }
    attempt=$((attempt+1))
  done
done
