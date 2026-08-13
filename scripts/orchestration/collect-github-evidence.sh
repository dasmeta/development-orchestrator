#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$script_dir/lib/feature_paths.sh"; source "$script_dir/lib/workspace_config.sh"
feature_dir=""; checks_provider=""; authority_provider=""; run_id=""; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; config_path="$(default_workspace_config_path "$script_dir")"
while [[ $# -gt 0 ]]; do case "$1" in --feature-dir) feature_dir="$2"; shift 2;; --config) config_path="$2"; shift 2;; --checks-provider) checks_provider="$2"; shift 2;; --authority-provider) authority_provider="$2"; shift 2;; --run-id) run_id="$2"; shift 2;; --now) now="$2"; shift 2;; *) echo "unknown arg: $1" >&2; exit 1;; esac; done
[[ -n "$feature_dir" && -n "$checks_provider" && -n "$authority_provider" && -n "$run_id" ]] || { echo "feature directory, providers, and run ID are required" >&2; exit 1; }
scope="$(feature_scope_path "$feature_dir")"
for snapshot in "$feature_dir"/state/github/*.json; do
  [[ -f "$snapshot" ]] || continue
  repository_id="$(jq -r .repository_id "$snapshot")"; head_oid="$(jq -r '.pull_request.head_oid' "$snapshot")"; expected="$(jq -r --arg id "$repository_id" '.repositories[]|select(.id==$id)|.subject' "$scope")"
  [[ "$expected" == "commit:$head_oid" ]] || { echo "GitHub head does not match feature subject for $repository_id" >&2; exit 1; }
  checks_result="$(jq -r 'if ([.checks[].status]|all(.=="green")) then "passed" elif ([.checks[].status]|any(.=="red")) then "failed" else "blocked" end' "$snapshot")"
  checks_id="EV-$checks_provider-$repository_id-$run_id"; checks_payload="$feature_dir/state/github/$checks_id.payload.json"
  jq -n --arg id "$checks_id" --arg feature "$(feature_id_from_dir "$feature_dir")" --arg provider "$checks_provider" --arg repo "$repository_id" --arg subject "commit:$head_oid" --arg result "$checks_result" --arg now "$now" --argjson artifacts "$(jq '[.checks[]|select(.url!="")|{reference:.url,digest:null,media_type:"text/html"}]' "$snapshot")" '
   {schema_version:"1",evidence_id:$id,feature_id:$feature,evidence_type:"source-control-checks",provider_id:$provider,producer:{id:"source-control",role:"pending",run_id:"pending"},coverage:{claim_ids:[],architecture_constraint_ids:[]},subject:{repositories:{($repo):$subject}},policy_version:"pending",provider_config_digest:"pending",result:$result,outcome:"completed",environment:{id:"source-control",fixture:null},collected_at:$now,expires_at:null,artifacts:$artifacts,findings:[],known_gaps:[]}' > "$checks_payload"
  bash "$script_dir/ingest-evidence.sh" --feature-dir "$feature_dir" --config "$config_path" --provider "$checks_provider" --producer-id source-control --run-id "$run_id-$repository_id" --input "$checks_payload"
  if jq -e '.pull_request.approved==true and (.pull_request.reviewers|length)>0' "$snapshot" >/dev/null; then
    reviewer="$(jq -r '.pull_request.reviewers|sort|.[0]' "$snapshot")"; authority_id="EV-$authority_provider-$repository_id-$run_id"; authority_payload="$feature_dir/state/github/$authority_id.payload.json"
    jq -n --arg id "$authority_id" --arg feature "$(feature_id_from_dir "$feature_dir")" --arg provider "$authority_provider" --arg repo "$repository_id" --arg subject "commit:$head_oid" --arg reviewer "$reviewer" --arg now "$now" --arg url "$(jq -r .pull_request.url "$snapshot")" '
     {schema_version:"1",evidence_id:$id,feature_id:$feature,evidence_type:"intent-approval",provider_id:$provider,producer:{id:$reviewer,role:"pending",run_id:"pending"},coverage:{claim_ids:[],architecture_constraint_ids:[]},subject:{repositories:{($repo):$subject}},policy_version:"pending",provider_config_digest:"pending",result:"passed",outcome:"approved-review",environment:{id:"source-control",fixture:null},collected_at:$now,expires_at:null,artifacts:[{reference:$url,digest:null,media_type:"text/html"}],findings:[],known_gaps:[]}' > "$authority_payload"
    QUALITY_AUTHORITY_COLLECTION=1 bash "$script_dir/ingest-evidence.sh" --feature-dir "$feature_dir" --config "$config_path" --provider "$authority_provider" --producer-id "$reviewer" --run-id "$run_id-$repository_id" --input "$authority_payload"
  fi
done
