#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; control_repo_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/lib/common.sh"; source "$script_dir/lib/feature_paths.sh"; source "$script_dir/lib/workspace_config.sh"
require_command git; require_command jq
feature_dir=""; provider_id=""; repository_id=""; evidence_type=""; run_id=""; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; config_path="$(default_workspace_config_path "$script_dir")"
while [[ $# -gt 0 ]]; do case "$1" in --feature-dir) feature_dir="$2"; shift 2;; --config) config_path="$2"; shift 2;; --provider) provider_id="$2"; shift 2;; --repository) repository_id="$2"; shift 2;; --evidence-type) evidence_type="$2"; shift 2;; --run-id) run_id="$2"; shift 2;; --now) now="$2"; shift 2;; *) echo "unknown arg: $1" >&2; exit 1;; esac; done
[[ -n "$feature_dir" && -n "$provider_id" && -n "$repository_id" && -n "$evidence_type" && -n "$run_id" ]] || { echo "feature directory, provider, repository, evidence type, and run ID are required" >&2; exit 1; }
for value in "$provider_id" "$repository_id" "$evidence_type" "$run_id"; do
  [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || { echo "invalid provider execution identifier: $value" >&2; exit 1; }
done
require_workspace_config "$config_path"; policy="$(workspace_quality_policy_path "$config_path")"; validate_quality_policy "$policy"
provider="$(jq -c --arg id "$provider_id" '.providers[$id] // empty' "$policy")"; [[ -n "$provider" ]] || { echo "unknown evidence provider: $provider_id" >&2; exit 1; }
[[ "$(printf '%s' "$provider" | jq -r .kind)" == command ]] || { echo "provider is not a command provider: $provider_id" >&2; exit 1; }
repository_role="$(jq -r --arg id "$repository_id" '.repositories[$id].role // empty' "$config_path")"
[[ -n "$repository_role" ]] || { echo "unknown workspace repository: $repository_id" >&2; exit 1; }
printf '%s' "$provider" | jq -e --arg id "$repository_id" --arg role "$repository_role" '
  ((.repository_ids // []) | index($id)) != null or
  (.repository_role? == $role)
' >/dev/null || { echo "provider $provider_id does not target repository $repository_id" >&2; exit 1; }
repository_root="$(workspace_repository_path "$config_path" "$repository_id")"; repository_root="$(cd "$repository_root" && pwd)"
configured_working="$(printf '%s' "$provider" | jq -r '.working_directory')"; [[ "$configured_working" != /* ]] || { echo "provider working directory must be repository-relative" >&2; exit 1; }
case "/$configured_working/" in */../*) echo "provider working directory escapes repository root" >&2; exit 1;; esac
working_dir="$(cd "$repository_root/$configured_working" 2>/dev/null && pwd)" || { echo "provider working directory is unavailable" >&2; exit 1; }
case "$working_dir/" in "$repository_root/"*) ;; *) echo "provider working directory escapes repository root" >&2; exit 1;; esac
command_args=(); while IFS= read -r arg; do command_args+=("$arg"); done < <(printf '%s' "$provider" | jq -r '.command[]')
run_dir="$feature_dir/state/provider-runs/$run_id/$provider_id"; mkdir -p "$run_dir"; stdout_path="$run_dir/stdout.log"; stderr_path="$run_dir/stderr.log"
set +e; (cd "$working_dir" && "${command_args[@]}") > "$stdout_path" 2> "$stderr_path"; exit_code=$?; set -e
output_mode="$(printf '%s' "$provider" | jq -r .output_mode)"
if [[ "$output_mode" == evidence-json ]]; then
  [[ $exit_code -eq 0 ]] || { echo "evidence-json provider failed with exit code $exit_code" >&2; exit 1; }
  jq -e 'type=="object"' "$stdout_path" >/dev/null 2>&1 || { echo "provider emitted malformed evidence JSON" >&2; exit 1; }
  expected_subject="$(jq -r --arg id "$repository_id" '.repositories[] | select(.id==$id) | .subject' "$(feature_scope_path "$feature_dir")")"
  jq -e --arg id "$repository_id" --arg subject "$expected_subject" '
    .coverage.repository_ids == [$id] and
    .subject.repositories == {($id):$subject}
  ' "$stdout_path" >/dev/null || { echo "provider evidence does not match executed repository" >&2; exit 1; }
  bash "$script_dir/ingest-evidence.sh" --feature-dir "$feature_dir" --config "$config_path" --provider "$provider_id" --producer-id "$provider_id" --run-id "$run_id" --input "$stdout_path"
elif [[ "$output_mode" == exit-code ]]; then
  result=passed; outcome="exit-code:$exit_code"; retry_status=0
  if [[ $exit_code -eq 126 || $exit_code -eq 127 ]]; then result=blocked; retry_status=75; elif [[ $exit_code -ne 0 ]]; then result=failed; fi
  subject_json="$(jq -c --arg id "$repository_id" '.repositories | map(select(.id==$id) | {key:.id,value:.subject}) | from_entries' "$(feature_scope_path "$feature_dir")")"
  [[ "$subject_json" != "{}" ]] || { echo "provider repository is missing from feature scope: $repository_id" >&2; exit 1; }
  repository_ids="$(jq -cn --arg id "$repository_id" '[$id]')"
  claims_json="$(jq -c '[.claims[].id]|sort' "$(feature_claims_path "$feature_dir")")"; architecture_json="$(jq -c '[.constraints[]|select(.enforcement=="blocking")|.id]|sort' "$(feature_architecture_path "$feature_dir")")"
  stdout_digest="git-blob:$(git -C "$control_repo_root" hash-object "$stdout_path")"; stderr_digest="git-blob:$(git -C "$control_repo_root" hash-object "$stderr_path")"
  evidence_id="EV-$provider_id-$run_id"; payload="$run_dir/evidence.json"
  jq -n --arg id "$evidence_id" --arg feature_id "$(feature_id_from_dir "$feature_dir")" --arg type "$evidence_type" --arg result "$result" --arg outcome "$outcome" --arg now "$now" --arg stdout_ref "state/provider-runs/$run_id/$provider_id/stdout.log" --arg stderr_ref "state/provider-runs/$run_id/$provider_id/stderr.log" --arg stdout_digest "$stdout_digest" --arg stderr_digest "$stderr_digest" --argjson repository_ids "$repository_ids" --argjson subjects "$subject_json" --argjson claims "$claims_json" --argjson architecture "$architecture_json" '
   {schema_version:"1",evidence_id:$id,feature_id:$feature_id,evidence_type:$type,provider_id:"pending",producer:{id:"pending",role:"pending",run_id:"pending"},coverage:{repository_ids:$repository_ids,claim_ids:$claims,architecture_constraint_ids:$architecture},subject:{repositories:$subjects},policy_version:"pending",provider_config_digest:"pending",result:$result,outcome:$outcome,environment:{id:"local",fixture:null},collected_at:$now,expires_at:null,artifacts:[{reference:$stdout_ref,digest:$stdout_digest,media_type:"text/plain"},{reference:$stderr_ref,digest:$stderr_digest,media_type:"text/plain"}],findings:[],known_gaps:[]}' > "$payload"
  bash "$script_dir/ingest-evidence.sh" --feature-dir "$feature_dir" --config "$config_path" --provider "$provider_id" --producer-id "$provider_id" --run-id "$run_id" --input "$payload"
  exit "$retry_status"
else echo "unsupported provider output mode: $output_mode" >&2; exit 1; fi
