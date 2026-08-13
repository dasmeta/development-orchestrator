#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
control_repo_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/lib/feature_paths.sh"
source "$script_dir/lib/workspace_config.sh"
source "$script_dir/lib/quality_records.sh"

feature_dir=""
provider_id=""
producer_id=""
run_id=""
input_path=""
config_path="$(default_workspace_config_path "$script_dir")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --feature-dir) feature_dir="$2"; shift 2 ;;
    --config) config_path="$2"; shift 2 ;;
    --provider) provider_id="$2"; shift 2 ;;
    --producer-id) producer_id="$2"; shift 2 ;;
    --run-id) run_id="$2"; shift 2 ;;
    --input) input_path="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$feature_dir" || -z "$provider_id" || -z "$producer_id" || \
      -z "$run_id" || -z "$input_path" ]]; then
  echo "feature directory, provider, producer ID, run ID, and input are required" >&2
  exit 1
fi
require_workspace_config "$config_path"

policy_path="$(workspace_quality_policy_path "$config_path")" || {
  echo "quality policy is required for evidence ingestion" >&2
  exit 1
}
validate_quality_policy "$policy_path"

if ! jq -e --arg provider_id "$provider_id" \
  '.providers[$provider_id] != null' "$policy_path" >/dev/null; then
  echo "unknown evidence provider: $provider_id" >&2
  exit 1
fi
if ! jq -e 'type == "object"' "$input_path" >/dev/null 2>&1; then
  echo "evidence payload must be a JSON object" >&2
  exit 1
fi

evidence_type="$(jq -r '.evidence_type // empty' "$input_path")"
if [[ -z "$evidence_type" ]] || \
   ! quality_provider_allows_evidence_type \
     "$policy_path" "$provider_id" "$evidence_type"; then
  echo "provider $provider_id does not allow evidence type $evidence_type" >&2
  exit 1
fi

if quality_provider_is_authority "$policy_path" "$provider_id" && \
   [[ "${QUALITY_AUTHORITY_COLLECTION:-0}" != "1" ]]; then
  echo "authority providers require QUALITY_AUTHORITY_COLLECTION=1" >&2
  exit 1
fi

feature_id="$(feature_id_from_dir "$feature_dir")"
producer_role="$(jq -r --arg provider_id "$provider_id" \
  '.providers[$provider_id].producer_role' "$policy_path")"
policy_version="$(jq -r '.policy_version' "$policy_path")"
provider_digest="$(quality_provider_config_digest "$policy_path" "$provider_id")"
evidence_id="$(jq -r '.evidence_id // empty' "$input_path")"
evidence_dir="$(feature_evidence_dir "$feature_dir")"
mkdir -p "$evidence_dir"

if [[ ! "$evidence_id" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]]; then
  echo "invalid evidence ID: $evidence_id" >&2
  exit 1
fi
final_path="$evidence_dir/$evidence_id.json"
lock_path="$final_path.lock"
if ! mkdir "$lock_path" 2>/dev/null; then
  echo "evidence ingestion is already in progress: $evidence_id" >&2
  exit 1
fi
trap 'rmdir "$lock_path" 2>/dev/null || true' EXIT
if [[ -e "$final_path" ]]; then
  echo "evidence already exists and is immutable: $evidence_id" >&2
  exit 1
fi

staged_path="$(mktemp "$evidence_dir/.incoming-evidence.XXXXXX")"
jq \
  --arg feature_id "$feature_id" \
  --arg provider_id "$provider_id" \
  --arg producer_id "$producer_id" \
  --arg producer_role "$producer_role" \
  --arg run_id "$run_id" \
  --arg policy_version "$policy_version" \
  --arg provider_digest "$provider_digest" '
    .feature_id = $feature_id |
    .provider_id = $provider_id |
    .producer = {
      id: $producer_id,
      role: $producer_role,
      run_id: $run_id
    } |
    .policy_version = $policy_version |
    .provider_config_digest = $provider_digest
  ' "$input_path" > "$staged_path"

if ! validate_evidence_record "$staged_path" "$feature_id"; then
  rm -f "$staged_path"
  exit 1
fi
mv "$staged_path" "$final_path"
rmdir "$lock_path"
trap - EXIT
