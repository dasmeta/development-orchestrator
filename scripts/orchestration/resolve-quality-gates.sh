#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
control_repo_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/lib/common.sh"
source "$script_dir/lib/feature_paths.sh"
source "$script_dir/lib/workspace_config.sh"

require_command git
require_command jq

feature_dir=""
resolved_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
config_path="$(default_workspace_config_path "$script_dir")"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --feature-dir) feature_dir="$2"; shift 2 ;;
    --config) config_path="$2"; shift 2 ;;
    --now) resolved_at="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$feature_dir" ]] || { echo "feature directory is required" >&2; exit 1; }
require_workspace_config "$config_path"
policy_path="$(workspace_quality_policy_path "$config_path")" || {
  echo "quality policy is required" >&2; exit 1;
}
validate_quality_policy "$policy_path"
scope_path="$(feature_scope_path "$feature_dir")"
[[ -f "$scope_path" ]] || { echo "feature scope is required: $scope_path" >&2; exit 1; }

if ! jq -e '
  .schema_version == "1" and
  (.feature_id | type == "string" and length > 0) and
  (.repositories | type == "array") and
  all(.repositories[];
    (.id | type == "string" and length > 0) and
    (.role | type == "string" and length > 0) and
    (.subject | type == "string" and length > 0) and
    (.changed_paths | type == "array")
  ) and
  (.explicit_impacts | type == "array")
' "$scope_path" >/dev/null; then
  echo "invalid feature scope: $scope_path" >&2
  exit 1
fi

subject_fingerprint="$(jq -cS '
  del(.derived_impacts, .policy_version) |
  .repositories |= map(del(.captured_at))
' "$scope_path" | git -C "$control_repo_root" hash-object --stdin | sed 's/^/git-blob:/')"

state_dir="$feature_dir/state"
mkdir -p "$state_dir"
plan_tmp="$(mktemp "$state_dir/.gate-plan.XXXXXX")"
jq -n \
  --slurpfile scope "$scope_path" \
  --slurpfile policy "$policy_path" \
  --arg subject_fingerprint "$subject_fingerprint" \
  --arg resolved_at "$resolved_at" \
  -f "$script_dir/jq/resolve-gates.jq" > "$plan_tmp"
mv "$plan_tmp" "$state_dir/gate-plan.json"

scope_tmp="$(mktemp "$(dirname "$scope_path")/.scope.XXXXXX")"
jq \
  --slurpfile plan "$state_dir/gate-plan.json" '
    .derived_impacts = $plan[0].impacts.derived |
    .policy_version = $plan[0].policy_version
  ' "$scope_path" > "$scope_tmp"
mv "$scope_tmp" "$scope_path"
