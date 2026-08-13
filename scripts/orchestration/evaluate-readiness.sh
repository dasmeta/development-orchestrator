#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
control_repo_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/lib/common.sh"
source "$script_dir/lib/feature_paths.sh"
source "$script_dir/lib/workspace_config.sh"
source "$script_dir/lib/quality_records.sh"
require_command git
require_command jq

feature_dir=""; decision=""; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
config_path="$(default_workspace_config_path "$script_dir")"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --feature-dir) feature_dir="$2"; shift 2;;
    --config) config_path="$2"; shift 2;;
    --decision) decision="$2"; shift 2;;
    --now) now="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
[[ -n "$feature_dir" && -n "$decision" ]] || { echo "feature directory and decision are required" >&2; exit 1; }
require_workspace_config "$config_path"
policy_path="$(workspace_quality_policy_path "$config_path")" || { echo "quality policy is required" >&2; exit 1; }
validate_quality_policy "$policy_path"
jq -e --arg decision "$decision" '.decisions[$decision] != null' "$policy_path" >/dev/null || { echo "unknown quality decision: $decision" >&2; exit 1; }

scope_path="$(feature_scope_path "$feature_dir")"; claims_path="$(feature_claims_path "$feature_dir")"
architecture_path="$(feature_architecture_path "$feature_dir")"; gate_plan_path="$feature_dir/state/gate-plan.json"
for required_path in "$scope_path" "$claims_path" "$architecture_path" "$gate_plan_path"; do
  [[ -f "$required_path" ]] || { echo "required quality input missing: $required_path" >&2; exit 1; }
done

scratch_dir="$(mktemp -d)"; trap 'rm -rf "$scratch_dir"' EXIT
printf '[]\n' > "$scratch_dir/evidence.json"; printf '[]\n' > "$scratch_dir/waivers.json"; printf '[]\n' > "$scratch_dir/malformed.json"
valid_files=(); malformed_records=()
for record in "$feature_dir"/evidence/*.json; do
  [[ -f "$record" ]] || continue
  if validate_evidence_record "$record" "$(feature_id_from_dir "$feature_dir")" >/dev/null 2>&1; then
    valid_files+=("$record")
  else
    malformed_records+=("$(basename "$record")")
  fi
done
if [[ ${#valid_files[@]} -gt 0 ]]; then
  jq -s . "${valid_files[@]}" > "$scratch_dir/evidence.json"
fi
if [[ ${#malformed_records[@]} -gt 0 ]]; then
  printf '%s\n' "${malformed_records[@]}" | jq -R . | jq -s . > "$scratch_dir/malformed.json"
fi
waiver_files=()
for record in "$feature_dir"/waivers/*.json; do [[ -f "$record" ]] && waiver_files+=("$record"); done
if [[ ${#waiver_files[@]} -gt 0 ]]; then
  jq -s . "${waiver_files[@]}" > "$scratch_dir/waivers.json"
fi

printf '{}\n' > "$scratch_dir/provider-digests.json"
while IFS= read -r provider_id; do
  digest="$(jq -cS --arg id "$provider_id" '.providers[$id]' "$policy_path" | git -C "$control_repo_root" hash-object --stdin | sed 's/^/git-blob:/')"
  jq --arg id "$provider_id" --arg digest "$digest" '. + {($id):$digest}' "$scratch_dir/provider-digests.json" > "$scratch_dir/digests.next"
  mv "$scratch_dir/digests.next" "$scratch_dir/provider-digests.json"
done < <(jq -r '.providers | keys[]' "$policy_path")

readiness_path="$(feature_readiness_path "$feature_dir")"; repair_path="$(feature_repair_brief_path "$feature_dir")"
mkdir -p "$(dirname "$readiness_path")"
readiness_tmp="$(mktemp "$(dirname "$readiness_path")/.readiness.XXXXXX")"
jq -n --slurpfile policy "$policy_path" --slurpfile gate_plan "$gate_plan_path" \
  --slurpfile scope "$scope_path" --slurpfile claims "$claims_path" --slurpfile architecture "$architecture_path" \
  --slurpfile evidence "$scratch_dir/evidence.json" --slurpfile waivers "$scratch_dir/waivers.json" \
  --slurpfile malformed "$scratch_dir/malformed.json" --slurpfile provider_digests "$scratch_dir/provider-digests.json" \
  --arg decision "$decision" --arg now "$now" -f "$script_dir/jq/evaluate-readiness.jq" > "$readiness_tmp"
mv "$readiness_tmp" "$readiness_path"

repair_tmp="$(mktemp "$(dirname "$repair_path")/.repair.XXXXXX")"
jq '{schema_version:"1",feature_id,decision,subject_fingerprint,
  human_action_required:(any(.findings[]; .class == "authority" or .class == "policy")),
  repairs:[.findings[] | select(.class == "evidence") | {finding_id:.id,gate_id:.gate_id,owner,affected_claim_ids:[],affected_architecture_constraint_ids:[],allowed_responsibility:(if .owner == "implementation" then "implementation" else "provider-output" end),message}]}' \
  "$readiness_path" > "$repair_tmp"
mv "$repair_tmp" "$repair_path"
