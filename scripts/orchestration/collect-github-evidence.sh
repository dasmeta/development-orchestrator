#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$script_dir/lib/feature_paths.sh"; source "$script_dir/lib/workspace_config.sh"
feature_dir=""; checks_provider=""; authority_provider=""; run_id=""; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; config_path="$(default_workspace_config_path "$script_dir")"
while [[ $# -gt 0 ]]; do case "$1" in --feature-dir) feature_dir="$2"; shift 2;; --config) config_path="$2"; shift 2;; --checks-provider) checks_provider="$2"; shift 2;; --authority-provider) authority_provider="$2"; shift 2;; --run-id) run_id="$2"; shift 2;; --now) now="$2"; shift 2;; *) echo "unknown arg: $1" >&2; exit 1;; esac; done
[[ -n "$feature_dir" && -n "$checks_provider" && -n "$authority_provider" && -n "$run_id" ]] || { echo "feature directory, providers, and run ID are required" >&2; exit 1; }
scope="$(feature_scope_path "$feature_dir")"
claims_path="$(feature_claims_path "$feature_dir")"
claim_ids='[]'
if [[ -f "$claims_path" ]]; then
  claim_ids="$(jq -c '[.claims[].id]|unique|sort' "$claims_path")"
fi
while IFS= read -r snapshot; do
  if ! jq -e '
    (.repository_id | type) == "string" and
    (.repository_id | length) > 0 and
    (.pull_request.head_oid | type) == "string" and
    (.pull_request.head_oid | length) > 0 and
    (.checks | type) == "object"
  ' "$snapshot" >/dev/null 2>&1; then
    echo "invalid GitHub snapshot: $snapshot" >&2
    exit 1
  fi
  repository_id="$(jq -r .repository_id "$snapshot")"; head_oid="$(jq -r '.pull_request.head_oid' "$snapshot")"; expected="$(jq -r --arg id "$repository_id" '.repositories[]|select(.id==$id)|.subject' "$scope")"
  [[ "$expected" == "commit:$head_oid" ]] || { echo "GitHub head does not match feature subject for $repository_id" >&2; exit 1; }
  subjects="$(jq -nc --arg id "$repository_id" --arg subject "$expected" '{($id):$subject}')"
  repository_ids="$(jq -nc --arg id "$repository_id" '[$id]')"
  checks_result="$(jq -r '
    if (.checks | length) == 0 then "blocked"
    elif ([.checks[].status] | any(. == "red")) then "failed"
    elif ([.checks[].status] | all(. == "green")) then "passed"
    else "blocked"
    end
  ' "$snapshot")"
  checks_gaps="$(jq -c 'if (.checks | length) == 0 then [{id:"SOURCE_CONTROL_CHECKS_EMPTY",message:"No source-control checks were collected"}] else [] end' "$snapshot")"
  payload_dir="$feature_dir/state/provider-runs/$run_id/source-control/$repository_id"
  mkdir -p "$payload_dir"
  checks_id="EV-$checks_provider-$repository_id-$run_id"; checks_payload="$payload_dir/$checks_id.payload.json"
  jq -n --arg id "$checks_id" --arg feature "$(feature_id_from_dir "$feature_dir")" --arg provider "$checks_provider" --arg result "$checks_result" --arg now "$now" --argjson subjects "$subjects" --argjson repository_ids "$repository_ids" --argjson artifacts "$(jq '[.checks[]|select(.url!="")|{reference:.url,digest:null,media_type:"text/html"}]' "$snapshot")" --argjson known_gaps "$checks_gaps" '
   {schema_version:"1",evidence_id:$id,feature_id:$feature,evidence_type:"source-control-checks",provider_id:$provider,producer:{id:"source-control",role:"pending",run_id:"pending"},coverage:{claim_ids:[],architecture_constraint_ids:[],repository_ids:$repository_ids},subject:{repositories:$subjects},policy_version:"pending",provider_config_digest:"pending",result:$result,outcome:"completed",environment:{id:"source-control",fixture:null},collected_at:$now,expires_at:null,artifacts:$artifacts,findings:[],known_gaps:$known_gaps}' > "$checks_payload"
  bash "$script_dir/ingest-evidence.sh" --feature-dir "$feature_dir" --config "$config_path" --provider "$checks_provider" --producer-id source-control --run-id "$run_id-$repository_id" --input "$checks_payload"
  if jq -e '.pull_request.approved==true and (.pull_request.reviewers|length)>0' "$snapshot" >/dev/null; then
    reviewer="$(jq -r '.pull_request.reviewers|sort|.[0]' "$snapshot")"; authority_id="EV-$authority_provider-$repository_id-$run_id"; authority_payload="$payload_dir/$authority_id.payload.json"
    jq -n --arg id "$authority_id" --arg feature "$(feature_id_from_dir "$feature_dir")" --arg provider "$authority_provider" --arg reviewer "$reviewer" --arg now "$now" --arg url "$(jq -r .pull_request.url "$snapshot")" --argjson subjects "$subjects" --argjson repository_ids "$repository_ids" --argjson claim_ids "$claim_ids" '
     {schema_version:"1",evidence_id:$id,feature_id:$feature,evidence_type:"intent-approval",provider_id:$provider,producer:{id:$reviewer,role:"pending",run_id:"pending"},coverage:{claim_ids:$claim_ids,architecture_constraint_ids:[],repository_ids:$repository_ids},subject:{repositories:$subjects},policy_version:"pending",provider_config_digest:"pending",result:"passed",outcome:"approved-review",environment:{id:"source-control",fixture:null},collected_at:$now,expires_at:null,artifacts:[{reference:$url,digest:null,media_type:"text/html"}],findings:[],known_gaps:[]}' > "$authority_payload"
    QUALITY_AUTHORITY_COLLECTION=1 bash "$script_dir/ingest-evidence.sh" --feature-dir "$feature_dir" --config "$config_path" --provider "$authority_provider" --producer-id "$reviewer" --run-id "$run_id-$repository_id" --input "$authority_payload"
  fi
done < <(find "$feature_dir/state/github" -maxdepth 1 -type f -name '*.json' ! -name '*.payload.json' -print | sort)
