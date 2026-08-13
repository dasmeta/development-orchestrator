#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

feature_dir="$tmp_dir/features/FEAT-0001"
mkdir -p "$feature_dir/state" "$feature_dir/evidence" "$feature_dir/waivers" "$tmp_dir/config"
cat > "$tmp_dir/config/workspace.json" <<'JSON'
{"quality":{"mode":"observe","policy":"policy.json"},"repositories":{"app":{"path":"../app","role":"implementation"}}}
JSON
cat > "$tmp_dir/config/policy.json" <<'JSON'
{
  "schema_version":"1","policy_version":"1","protected_path_regex":[],"impact_rules":[],
  "gates":[
    {"id":"tests","decisions":["merge-ready"],"when":{"impacts_any":["implementation"]},"evidence_types":["focused-tests"],"providers":["tests"],"coverage":{"claims":"all","architecture":"none"},"required_result":"passed"},
    {"id":"build","decisions":["merge-ready"],"when":{"impacts_any":["implementation"]},"evidence_types":["build"],"providers":["build"],"coverage":{"claims":"none","architecture":"none"},"required_result":"passed"}
  ],
  "providers":{
    "tests":{"kind":"external-import","trust":"repository-check","producer_role":"verification","repository_role":"implementation"},
    "build":{"kind":"external-import","trust":"repository-check","producer_role":"verification","repository_role":"implementation"}
  },
  "decisions":{"merge-ready":{"require_gates":["tests","build"]}},
  "release_archive":{"kind":"filesystem","destination":"archive"},"budgets":{"provider_retries":1,"repair_attempts":2}
}
JSON
cat > "$feature_dir/scope.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-0001","repositories":[{"id":"app","role":"implementation","subject":"commit:abc","base":"base","head":"abc","changed_paths":["src/a.ts"],"dependencies":[],"captured_at":"2026-08-13T00:00:00Z"}],"explicit_impacts":["implementation"],"derived_impacts":[],"policy_version":"1"}
JSON
cat > "$feature_dir/claims.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-0001","claims":[{"id":"AC-1","source":{"repository_id":"intent","revision":"commit:1","path":"spec.md"},"content_digest":"git-blob:claim"}]}
JSON
cat > "$feature_dir/architecture.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-0001","sources":[],"constraints":[]}
JSON
cat > "$feature_dir/state/gate-plan.json" <<'JSON'
{
  "schema_version":"1","feature_id":"FEAT-0001","policy_version":"1","subject_fingerprint":"git-blob:scope","resolved_at":"2026-08-13T00:00:00Z",
  "impacts":{"explicit":["implementation"],"derived":[],"all":["implementation"]},"impact_sources":[],
  "gates":[
    {"id":"build","applicability":"required","reason":"configured_impact_match","decisions":["merge-ready"],"evidence_types":["build"],"providers":["build"],"coverage":{"claims":"none","architecture":"none"},"required_result":"passed"},
    {"id":"tests","applicability":"required","reason":"configured_impact_match","decisions":["merge-ready"],"evidence_types":["focused-tests"],"providers":["tests"],"coverage":{"claims":"all","architecture":"none"},"required_result":"passed"}
  ],"findings":[]
}
JSON

provider_digest() { jq -cS --arg id "$1" '.providers[$id]' "$tmp_dir/config/policy.json" | git hash-object --stdin | sed 's/^/git-blob:/'; }
write_evidence() {
  local id="$1" type="$2" provider="$3" result="$4" claims="$5" subject="${6:-commit:abc}" expires="${7:-null}"
  jq -n --arg id "$id" --arg type "$type" --arg provider "$provider" --arg result "$result" \
    --arg digest "$(provider_digest "$provider")" --arg subject "$subject" --argjson claims "$claims" --argjson expires "$expires" '
    {schema_version:"1",evidence_id:$id,feature_id:"FEAT-0001",evidence_type:$type,provider_id:$provider,
     producer:{id:"ci",role:"verification",run_id:$id},coverage:{claim_ids:$claims,architecture_constraint_ids:[]},
     subject:{repositories:{app:$subject}},policy_version:"1",provider_config_digest:$digest,result:$result,outcome:"completed",
     environment:{id:"local",fixture:null},collected_at:"2026-08-13T01:00:00Z",expires_at:$expires,artifacts:[],findings:[],known_gaps:[]}' \
    > "$feature_dir/evidence/$id.json"
}
evaluate() {
  bash "$repo_root/scripts/orchestration/evaluate-readiness.sh" --feature-dir "$feature_dir" \
    --config "$tmp_dir/config/workspace.json" --decision merge-ready --now "2026-08-13T02:00:00Z"
}

evaluate
assert_equals incomplete "$(jq -r .status "$feature_dir/state/readiness.json")"
jq -e '.findings | map(.id) == ["EVIDENCE_MISSING:build","EVIDENCE_MISSING:tests"]' "$feature_dir/state/readiness.json" >/dev/null
jq -e '.human_action_required == false and (.repairs | length == 2)' "$feature_dir/state/repair-brief.json" >/dev/null

write_evidence EV-tests focused-tests tests passed '["AC-1"]'
write_evidence EV-build build build passed '[]'
evaluate
assert_equals ready "$(jq -r .status "$feature_dir/state/readiness.json")"
cp "$feature_dir/state/readiness.json" "$tmp_dir/first.json"
evaluate
cmp "$tmp_dir/first.json" "$feature_dir/state/readiness.json"

rm "$feature_dir/evidence/EV-tests.json"
write_evidence EV-tests-new focused-tests tests passed '[]'
evaluate
assert_equals incomplete "$(jq -r .status "$feature_dir/state/readiness.json")"
jq -e '.findings | any(.id == "EVIDENCE_COVERAGE_INCOMPLETE:tests")' "$feature_dir/state/readiness.json" >/dev/null

rm "$feature_dir/evidence/EV-tests-new.json"
write_evidence EV-build-failed build build failed '[]'
write_evidence EV-tests-blocked focused-tests tests blocked '["AC-1"]'
evaluate
assert_equals failed "$(jq -r .status "$feature_dir/state/readiness.json")"
jq -e '(.findings | any(.id == "EVIDENCE_FAILED:build")) and (.findings | any(.id == "EVIDENCE_BLOCKED:tests"))' "$feature_dir/state/readiness.json" >/dev/null

rm "$feature_dir/evidence/EV-build-failed.json" "$feature_dir/evidence/EV-tests-blocked.json"
write_evidence EV-tests-wrong focused-tests tests passed '["AC-1"]' commit:wrong
evaluate
assert_equals incomplete "$(jq -r .status "$feature_dir/state/readiness.json")"
jq -e '.findings | any(.id == "EVIDENCE_SUBJECT_MISMATCH:tests")' "$feature_dir/state/readiness.json" >/dev/null

printf '{bad json' > "$feature_dir/evidence/malformed.json"
evaluate
jq -e '.findings | any(.id == "EVIDENCE_MALFORMED:malformed.json")' "$feature_dir/state/readiness.json" >/dev/null

printf '{"schema_version":"1"}\n' > "$feature_dir/evidence/malformed-object.json"
evaluate
jq -e '.findings | any(.id == "EVIDENCE_MALFORMED:malformed-object.json")' "$feature_dir/state/readiness.json" >/dev/null

rm "$feature_dir/evidence/malformed.json" "$feature_dir/evidence/malformed-object.json" "$feature_dir/evidence/EV-tests-wrong.json"
write_evidence EV-tests-worktree focused-tests tests passed '["AC-1"]' worktree:dirty
jq '.repositories[0].subject="worktree:dirty"' "$feature_dir/scope.json" > "$tmp_dir/worktree-scope.json"; mv "$tmp_dir/worktree-scope.json" "$feature_dir/scope.json"
evaluate
assert_equals incomplete "$(jq -r .status "$feature_dir/state/readiness.json")"
jq -e '.findings | any(.id == "SUBJECT_NOT_COMMITTED:app")' "$feature_dir/state/readiness.json" >/dev/null
