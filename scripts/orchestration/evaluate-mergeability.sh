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

if jq -e --slurpfile cfg "$config_path" '
  [($cfg[0].mergeability.required // [])[] as $gate
    | getpath(($gate.path | ltrimstr(".") | split("."))) == $gate.equals
  ] | all
' "$github_state_path" >/dev/null
then
  ready=true
  reason="$(workspace_merge_ready_reason "$config_path")"
else
  ready=false
  reason="$(workspace_merge_incomplete_reason "$config_path")"
fi

tmp_file="$(mktemp)"
jq \
  --argjson ready "$ready" \
  --arg reason "$reason" \
  '.mergeability.ready = $ready | .mergeability.reason = $reason' \
  "$manifest_path" > "$tmp_file"
mv "$tmp_file" "$manifest_path"
