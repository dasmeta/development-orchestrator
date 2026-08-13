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

feature_id="$(feature_id_from_dir "$feature_dir")"
manifest_path="$(feature_manifest_path "$feature_dir")"
mkdir -p "$(dirname "$manifest_path")"
initial_stage="$(workspace_initial_stage "$config_path")"
repositories_json="$(workspace_repository_ids_json "$config_path")"
quality_mode="$(workspace_quality_mode "$config_path")"
quality_json="null"
if [[ "$quality_mode" != "off" || $(jq -r 'has("quality")' "$config_path") == true ]]; then
  quality_json="$(jq -n --arg mode "$quality_mode" '{schema_version:"1",mode:$mode,scope:"../scope.json",claims:"../claims.json",architecture:"../architecture.json",gate_plan:"gate-plan.json",readiness:"readiness.json",current_decision:"stage-ready"}')"
fi

jq -n \
  --arg feature_id "$feature_id" \
  --arg stage "$initial_stage" \
  --argjson repositories "$repositories_json" \
  --argjson quality "$quality_json" \
  '{
    feature_id: $feature_id,
    stage: $stage,
    repositories: $repositories,
    mergeability: {
      ready: false,
      reason: "configured_gates_incomplete"
    },
    quality: $quality
  }' > "$manifest_path"
