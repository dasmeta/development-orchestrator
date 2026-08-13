#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
source "$script_dir/lib/feature_paths.sh"
source "$script_dir/lib/workspace_config.sh"

require_command jq

feature_dir=""
config_path="$(default_workspace_config_path "$script_dir")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      config_path="$2"
      shift 2
      ;;
    *)
      if [[ -z "$feature_dir" ]]; then
        feature_dir="$1"
        shift
      else
        echo "unknown arg: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$feature_dir" ]]; then
  echo "feature directory is required" >&2
  exit 1
fi
require_workspace_config "$config_path"

manifest_path="$(feature_manifest_path "$feature_dir")"
github_state_path="$feature_dir/state/github-state.json"

if [[ ! -f "$manifest_path" || ! -f "$github_state_path" ]]; then
  echo "manifest and github state are required" >&2
  exit 1
fi

current_stage="$(jq -r '.stage' "$manifest_path")"
next_stage="$(workspace_next_stage "$config_path" "$current_stage")"
advance_path="$(workspace_advance_when_path "$config_path")"
advance_equals="$(workspace_advance_when_equals_json "$config_path")"
quality_mode="$(workspace_quality_mode "$config_path")"
advance_allowed=false
if [[ "$quality_mode" == "enforce" && -f "$feature_dir/state/readiness.json" && -f "$feature_dir/state/gate-plan.json" ]]; then
  decision="$(workspace_stage_advance_decision "$config_path" "$current_stage")"
  if jq -e --arg decision "$decision" --slurpfile plan "$feature_dir/state/gate-plan.json" \
    '.decision==$decision and .status=="ready" and .subject_fingerprint==$plan[0].subject_fingerprint' "$feature_dir/state/readiness.json" >/dev/null; then
    advance_allowed=true
  fi
elif [[ "$quality_mode" != "enforce" ]] && jq -e \
  --arg path "$advance_path" --argjson expected "$advance_equals" \
  'getpath(($path | ltrimstr(".") | split("."))) == $expected' "$github_state_path" >/dev/null; then
  advance_allowed=true
fi

if [[ -n "$next_stage" && "$advance_allowed" == true ]]; then
  tmp_file="$(mktemp)"
  jq --arg stage "$next_stage" \
    '.stage = $stage | .mergeability.ready = false | .mergeability.reason = "configured_gates_incomplete"' \
    "$manifest_path" > "$tmp_file"
  mv "$tmp_file" "$manifest_path"
fi
