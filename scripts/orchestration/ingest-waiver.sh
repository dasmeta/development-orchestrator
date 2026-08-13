#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
control_repo_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/lib/feature_paths.sh"
source "$script_dir/lib/workspace_config.sh"
source "$script_dir/lib/quality_records.sh"

feature_dir=""
input_path=""
config_path="$(default_workspace_config_path "$script_dir")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --feature-dir) feature_dir="$2"; shift 2 ;;
    --config) config_path="$2"; shift 2 ;;
    --input) input_path="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$feature_dir" || -z "$input_path" ]]; then
  echo "feature directory and input are required" >&2
  exit 1
fi
require_workspace_config "$config_path"
policy_path="$(workspace_quality_policy_path "$config_path")" || {
  echo "quality policy is required for waiver ingestion" >&2
  exit 1
}
validate_quality_policy "$policy_path"

feature_id="$(feature_id_from_dir "$feature_dir")"
validate_waiver_record "$input_path" "$feature_id"

waiver_id="$(jq -r '.waiver_id' "$input_path")"
authority_evidence_id="$(jq -r '.authority_evidence_id' "$input_path")"
evidence_path="$(feature_evidence_dir "$feature_dir")/$authority_evidence_id.json"
if [[ ! -f "$evidence_path" ]]; then
  echo "waiver authority evidence does not exist: $authority_evidence_id" >&2
  exit 1
fi
validate_evidence_record "$evidence_path" "$feature_id"
validate_waiver_authority_evidence "$input_path" "$evidence_path" "$policy_path"

waiver_dir="$(feature_waiver_dir "$feature_dir")"
mkdir -p "$waiver_dir"
final_path="$waiver_dir/$waiver_id.json"
lock_path="$final_path.lock"
if ! mkdir "$lock_path" 2>/dev/null; then
  echo "waiver ingestion is already in progress: $waiver_id" >&2
  exit 1
fi
trap 'rmdir "$lock_path" 2>/dev/null || true' EXIT
if [[ -e "$final_path" ]]; then
  echo "waiver already exists and is immutable: $waiver_id" >&2
  exit 1
fi

staged_path="$(mktemp "$waiver_dir/.incoming-waiver.XXXXXX")"
jq -S . "$input_path" > "$staged_path"
mv "$staged_path" "$final_path"
rmdir "$lock_path"
trap - EXIT
