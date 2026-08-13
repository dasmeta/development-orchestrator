#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
feature_dir="$tmp_dir/features/FEAT-AGG"
mkdir -p "$feature_dir/state" "$feature_dir/evidence" \
  "$feature_dir/waivers" "$tmp_dir/config"

cat > "$tmp_dir/config/workspace.json" <<'JSON'
{"quality":{"mode":"observe","policy":"policy.json"},"repositories":{"app-a":{"path":"../app-a","role":"implementation"},"app-b":{"path":"../app-b","role":"implementation"}}}
JSON
cat > "$feature_dir/scope.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-AGG","repositories":[{"id":"app-a","role":"implementation","subject":"commit:aaa","base":"base-a","head":"aaa","changed_paths":["a"]},{"id":"app-b","role":"implementation","subject":"commit:bbb","base":"base-b","head":"bbb","changed_paths":["b"]}],"explicit_impacts":["implementation"],"derived_impacts":[],"policy_version":"1"}
JSON
cat > "$feature_dir/claims.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-AGG","claims":[{"id":"AC-1","source":{"repository_id":"intent","revision":"1","path":"spec.md"},"content_digest":"x"}]}
JSON
cat > "$feature_dir/architecture.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-AGG","sources":[],"constraints":[]}
JSON

write_policy() {
  local providers="$1" strategy="$2"
  jq -n --argjson providers "$providers" --arg strategy "$strategy" '
    {schema_version:"1",policy_version:"1",protected_path_regex:[],impact_rules:[],
     gates:[{id:"aggregate",decisions:["merge-ready"],when:{impacts_any:["implementation"]},evidence_types:["independent-verification"],providers:$providers,coverage:{claims:"all",architecture:"none"},required_result:"passed"} + (if ($providers|length)>1 then {provider_strategy:$strategy} else {} end)],
     providers:{
       verifier:{kind:"external-import",trust:"read-only-verifier",producer_role:"verification",repository_ids:["app-a","app-b"]},
       "suite-a":{kind:"external-import",trust:"repository-check",producer_role:"verification",repository_ids:["app-a"]},
       "suite-b":{kind:"external-import",trust:"repository-check",producer_role:"verification",repository_ids:["app-a"]}},
     decisions:{"merge-ready":{require_gates:["aggregate"]}},release_archive:{kind:"filesystem",destination:"archive"},budgets:{provider_retries:0,repair_attempts:0}}
  ' > "$tmp_dir/config/policy.json"
  jq -n --argjson providers "$providers" --arg strategy "$strategy" '
    {schema_version:"1",feature_id:"FEAT-AGG",policy_version:"1",subject_fingerprint:"git-blob:scope",resolved_at:"2026-08-13T00:00:00Z",impacts:{explicit:["implementation"],derived:[],all:["implementation"]},impact_sources:[],
     gates:[{id:"aggregate",applicability:"required",reason:"match",decisions:["merge-ready"],evidence_types:["independent-verification"],providers:$providers,provider_strategy:$strategy,coverage:{claims:"all",architecture:"none"},required_result:"passed"}],findings:[]}
  ' > "$feature_dir/state/gate-plan.json"
}

provider_digest() {
  jq -cS --arg id "$1" '.providers[$id]' "$tmp_dir/config/policy.json" |
    git hash-object --stdin | sed 's/^/git-blob:/'
}

write_evidence() {
  local id="$1" provider="$2" repository_id="$3" result="$4"
  local collected_at="${5:-2026-08-13T01:00:00Z}"
  local app_a_subject="${6:-commit:aaa}"
  jq -n --arg id "$id" --arg provider "$provider" \
    --arg repository_id "$repository_id" --arg result "$result" \
    --arg collected_at "$collected_at" --arg app_a_subject "$app_a_subject" \
    --arg digest "$(provider_digest "$provider")" '
    {schema_version:"1",evidence_id:$id,feature_id:"FEAT-AGG",evidence_type:"independent-verification",provider_id:$provider,
     producer:{id:"verifier",role:"verification",run_id:$id},coverage:{repository_ids:[$repository_id],claim_ids:["AC-1"],architecture_constraint_ids:[]},
     subject:{repositories:{"app-a":$app_a_subject,"app-b":"commit:bbb"}},policy_version:"1",provider_config_digest:$digest,result:$result,outcome:"completed",
     environment:{id:"local",fixture:null},collected_at:$collected_at,expires_at:null,artifacts:[],findings:[],known_gaps:[]}
  ' > "$feature_dir/evidence/$id.json"
}

clear_evidence() {
  find "$feature_dir/evidence" -type f -name '*.json' -delete
}

evaluate() {
  bash "$repo_root/scripts/orchestration/evaluate-readiness.sh" \
    --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json" \
    --decision merge-ready --now 2026-08-13T02:00:00Z
}

write_policy '["verifier"]' all
write_evidence EV-app-b verifier app-b passed
evaluate
assert_equals incomplete "$(jq -r .status "$feature_dir/state/readiness.json")"

clear_evidence
write_evidence EV-app-a verifier app-a failed 2026-08-13T01:00:00Z
write_evidence EV-app-b verifier app-b passed 2026-08-13T01:01:00Z
evaluate
assert_equals failed "$(jq -r .status "$feature_dir/state/readiness.json")"

clear_evidence
write_evidence EV-app-a verifier app-a passed
write_evidence EV-app-b verifier app-b passed
evaluate
assert_equals ready "$(jq -r .status "$feature_dir/state/readiness.json")"
jq -e '.gates[0].evidence_ids == ["EV-app-a","EV-app-b"]' \
  "$feature_dir/state/readiness.json" >/dev/null

clear_evidence
write_evidence EV-app-a-stale verifier app-a passed \
  2026-08-13T01:00:00Z commit:wrong
write_evidence EV-app-b verifier app-b passed
evaluate
assert_equals incomplete "$(jq -r .status "$feature_dir/state/readiness.json")"

clear_evidence
write_policy '["suite-a","suite-b"]' all
write_evidence EV-suite-a suite-a app-a passed
evaluate
assert_equals incomplete "$(jq -r .status "$feature_dir/state/readiness.json")"

write_evidence EV-suite-b suite-b app-a passed
evaluate
assert_equals ready "$(jq -r .status "$feature_dir/state/readiness.json")"
jq -e '.gates[0].evidence_ids == ["EV-suite-a","EV-suite-b"]' \
  "$feature_dir/state/readiness.json" >/dev/null

clear_evidence
write_evidence EV-suite-a suite-a app-a failed 2026-08-13T01:00:00Z
write_evidence EV-suite-b suite-b app-a passed 2026-08-13T01:01:00Z
evaluate
assert_equals failed "$(jq -r .status "$feature_dir/state/readiness.json")"

clear_evidence
write_policy '["suite-a","suite-b"]' any
write_evidence EV-suite-b suite-b app-a passed
evaluate
assert_equals ready "$(jq -r .status "$feature_dir/state/readiness.json")"

clear_evidence
write_evidence EV-suite-a suite-a app-a failed 2026-08-13T01:00:00Z
write_evidence EV-suite-b suite-b app-a passed 2026-08-13T01:01:00Z
evaluate
assert_equals failed "$(jq -r .status "$feature_dir/state/readiness.json")"
