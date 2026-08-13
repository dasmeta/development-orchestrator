#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; control_repo_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/lib/feature_paths.sh"; source "$script_dir/lib/workspace_config.sh"
feature_dir=""; provider_id=""; repository_id=""; implementation_run_id=""; run_id=""; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; config_path="$(default_workspace_config_path "$script_dir")"
while [[ $# -gt 0 ]]; do case "$1" in --feature-dir) feature_dir="$2"; shift 2;; --config) config_path="$2"; shift 2;; --provider) provider_id="$2"; shift 2;; --repository) repository_id="$2"; shift 2;; --implementation-run-id) implementation_run_id="$2"; shift 2;; --run-id) run_id="$2"; shift 2;; --now) now="$2"; shift 2;; *) echo "unknown arg: $1" >&2; exit 1;; esac; done
[[ -n "$feature_dir" && -n "$provider_id" && -n "$repository_id" && -n "$implementation_run_id" && -n "$run_id" ]] || { echo "feature directory, provider, repository, implementation run, and verifier run are required" >&2; exit 1; }
[[ "$implementation_run_id" != "$run_id" ]] || { echo "verifier run must differ from implementation run" >&2; exit 1; }
policy="$(workspace_quality_policy_path "$config_path")"; validate_quality_policy "$policy"
jq -e --arg id "$provider_id" '.providers[$id].kind=="verifier" and (.providers[$id].trust|test("read-only";"i"))' "$policy" >/dev/null || { echo "verifier provider must declare a read-only trust profile" >&2; exit 1; }
repository="$(workspace_repository_path "$config_path" "$repository_id")"; repository="$(cd "$repository" && pwd)"
run_dir="$feature_dir/state/provider-runs/$run_id/$provider_id"; mkdir -p "$run_dir"; prompt="$run_dir/verifier-prompt.md"; result="$run_dir/verifier-result.json"; schema="$control_repo_root/schemas/verifier-result.schema.json"
template="$control_repo_root/templates/quality/verifier-prompt.md"; scope="$(feature_scope_path "$feature_dir")"; claims="$(feature_claims_path "$feature_dir")"; architecture="$(feature_architecture_path "$feature_dir")"; gate_plan="$feature_dir/state/gate-plan.json"
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    '{{INTAKE}}') [[ -f "$feature_dir/intake.md" ]] && sed -n '1,240p' "$feature_dir/intake.md" || printf 'No intake document supplied.\n';;
    '{{SCOPE}}') jq -S . "$scope";;
    '{{CLAIMS}}') jq -S . "$claims";;
    '{{ARCHITECTURE}}') jq -S . "$architecture";;
    '{{GATE_PLAN}}') jq -S . "$gate_plan";;
    '{{DIFF}}') git -C "$repository" diff --binary --no-ext-diff HEAD -- || true;;
    *) printf '%s\n' "$line";;
  esac
done < "$template" > "$prompt"
command_args=(); while IFS= read -r configured_arg; do
  arg="${configured_arg//\{repository\}/$repository}"; arg="${arg//\{prompt\}/$prompt}"; arg="${arg//\{schema\}/$schema}"; arg="${arg//\{result\}/$result}"
  [[ "$arg" != *'{'* && "$arg" != *'}'* ]] || { echo "unknown verifier command token: $configured_arg" >&2; exit 1; }
  command_args+=("$arg")
done < <(jq -r --arg id "$provider_id" '.providers[$id].command[]' "$policy")
working="$(jq -r --arg id "$provider_id" '.providers[$id].working_directory' "$policy")"; case "/$working/" in */../*) echo "verifier working directory escapes repository" >&2; exit 1;; esac
working_dir="$(cd "$repository/$working" && pwd)"; case "$working_dir/" in "$repository/"*) ;; *) echo "verifier working directory escapes repository" >&2; exit 1;; esac
set +e; (cd "$working_dir" && "${command_args[@]}" < "$prompt") > "$run_dir/stdout.log" 2> "$run_dir/stderr.log"; status=$?; set -e
[[ $status -eq 0 && -f "$result" ]] || { echo "configured verifier failed: exit $status" >&2; exit 1; }
jq -e '
 type=="object" and (.result|IN("passed","failed","blocked")) and
 (.covered_claim_ids|type=="array") and (.covered_architecture_constraint_ids|type=="array") and
 (.architecture_disposition|IN("updated","not_applicable","blocked")) and
 (.documentation_disposition|IN("updated","not_applicable","blocked")) and
 (.artifact_references|type=="array") and all(.artifact_references[];(.uri|type=="string" and length>0) and (.digest|type=="string" and length>0)) and
 (.findings|type=="array") and (.known_gaps|type=="array") and
 (if (.architecture_disposition=="updated" or .documentation_disposition=="updated") then (.artifact_references|length)>0 else true end)
' "$result" >/dev/null || { echo "configured verifier emitted an invalid result" >&2; exit 1; }
subjects="$(jq -c '.repositories|map({key:.id,value:.subject})|from_entries' "$scope")"
jq -r --arg provider "$provider_id" '.gates[]|select(.applicability=="required" and (.providers|index($provider)))|[.id,.evidence_types[0]]|@tsv' "$gate_plan" | while IFS=$'\t' read -r gate_id evidence_type; do
  evidence_id="EV-$provider_id-$gate_id-$run_id"; payload="$run_dir/$evidence_id.payload.json"
  jq --arg id "$evidence_id" --arg feature "$(feature_id_from_dir "$feature_dir")" --arg type "$evidence_type" --arg provider "$provider_id" --arg now "$now" --argjson subjects "$subjects" '
   {schema_version:"1",evidence_id:$id,feature_id:$feature,evidence_type:$type,provider_id:$provider,producer:{id:"independent-verifier",role:"pending",run_id:"pending"},coverage:{claim_ids:.covered_claim_ids,architecture_constraint_ids:.covered_architecture_constraint_ids},subject:{repositories:$subjects},policy_version:"pending",provider_config_digest:"pending",result:.result,outcome:("architecture:"+.architecture_disposition+",documentation:"+.documentation_disposition),environment:{id:"local",fixture:null},collected_at:$now,expires_at:null,artifacts:[.artifact_references[]|{reference:.uri,digest:.digest,media_type:null}],findings:.findings,known_gaps:.known_gaps}' "$result" > "$payload"
  bash "$script_dir/ingest-evidence.sh" --feature-dir "$feature_dir" --config "$config_path" --provider "$provider_id" --producer-id independent-verifier --run-id "$run_id" --input "$payload"
done
