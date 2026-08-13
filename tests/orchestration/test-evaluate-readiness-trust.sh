#!/usr/bin/env bash

set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"
tmp_dir="$(mktemp -d)"; trap 'rm -rf "$tmp_dir"' EXIT
feature_dir="$tmp_dir/features/FEAT-TRUST"; mkdir -p "$feature_dir/state" "$feature_dir/evidence" "$feature_dir/waivers" "$tmp_dir/config"

cat > "$tmp_dir/config/workspace.json" <<'JSON'
{"quality":{"mode":"observe","policy":"policy.json"},"repositories":{"app":{"path":"../app","role":"implementation"}}}
JSON
cat > "$tmp_dir/config/policy.json" <<'JSON'
{
 "schema_version":"1","policy_version":"1","protected_path_regex":[],"impact_rules":[],
 "gates":[{"id":"architecture","decisions":["merge-ready"],"when":{"impacts_any":["architecture-sensitive"]},"evidence_types":["architecture-conformance"],"providers":["verifier"],"coverage":{"claims":"none","architecture":"all_blocking"},"required_result":"passed"}],
 "providers":{
   "verifier":{"kind":"external-import","trust":"read-only-verifier","producer_role":"verification","repository_role":"implementation"},
   "authority":{"kind":"external-import","trust":"human-authority","producer_role":"authority","repository_role":"implementation"}
 },
 "decisions":{"merge-ready":{"require_gates":["architecture"]}},"release_archive":{"kind":"filesystem","destination":"archive"},"budgets":{"provider_retries":1,"repair_attempts":2}
}
JSON
cat > "$feature_dir/scope.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-TRUST","repositories":[{"id":"app","role":"implementation","subject":"commit:abc","base":"base","head":"abc","changed_paths":["src/api.ts"],"dependencies":[],"captured_at":"2026-08-13T00:00:00Z"}],"explicit_impacts":["architecture-sensitive"],"derived_impacts":[],"policy_version":"1"}
JSON
cat > "$feature_dir/claims.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-TRUST","claims":[]}
JSON
cat > "$feature_dir/architecture.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-TRUST","sources":[],"constraints":[]}
JSON
cat > "$feature_dir/state/gate-plan.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-TRUST","policy_version":"1","subject_fingerprint":"git-blob:scope","resolved_at":"2026-08-13T00:00:00Z","impacts":{"explicit":["architecture-sensitive"],"derived":[],"all":["architecture-sensitive"]},"impact_sources":[],"gates":[{"id":"architecture","applicability":"required","reason":"configured_impact_match","decisions":["merge-ready"],"evidence_types":["architecture-conformance"],"providers":["verifier"],"coverage":{"claims":"none","architecture":"all_blocking"},"required_result":"passed"}],"findings":[]}
JSON
digest="$(jq -cS '.providers.verifier' "$tmp_dir/config/policy.json" | git hash-object --stdin | sed 's/^/git-blob:/')"
write_arch_evidence() {
  local id="$1" role="$2" constraints="$3"
  jq -n --arg id "$id" --arg role "$role" --arg digest "$digest" --argjson constraints "$constraints" '
   {schema_version:"1",evidence_id:$id,feature_id:"FEAT-TRUST",evidence_type:"architecture-conformance",provider_id:"verifier",producer:{id:"agent",role:$role,run_id:$id},coverage:{repository_ids:["app"],claim_ids:[],architecture_constraint_ids:$constraints},subject:{repositories:{app:"commit:abc"}},policy_version:"1",provider_config_digest:$digest,result:"passed",outcome:"completed",environment:{id:"local",fixture:null},collected_at:"2026-08-13T01:00:00Z",expires_at:null,artifacts:[],findings:[],known_gaps:[]}' > "$feature_dir/evidence/$id.json"
}
evaluate() { bash "$repo_root/scripts/orchestration/evaluate-readiness.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json" --decision merge-ready --now 2026-08-13T02:00:00Z; }

write_arch_evidence EV-self implementation '[]'
evaluate
assert_equals incomplete "$(jq -r .status "$feature_dir/state/readiness.json")"
jq -e '.findings | any(.id == "ARCHITECTURE_SOURCE_UNRESOLVED")' "$feature_dir/state/readiness.json" >/dev/null

cat > "$feature_dir/architecture.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-TRUST","sources":[{"id":"ARCH-SOURCE","repository_id":"architecture","revision":"commit:1","path":"adr.md","content_digest":"git-blob:source","approval_evidence_id":null}],"constraints":[{"id":"ARCH-1","source_id":"ARCH-SOURCE","section":"API","content_digest":"git-blob:constraint","impacts":["architecture-sensitive"],"enforcement":"blocking","approval_evidence_id":null},{"id":"ARCH-ADVISORY","source_id":"ARCH-SOURCE","section":"Style","content_digest":"git-blob:advisory","impacts":["architecture-sensitive"],"enforcement":"advisory","approval_evidence_id":null}]}
JSON
rm "$feature_dir/evidence/EV-self.json"; write_arch_evidence EV-self implementation '["ARCH-1"]'
evaluate
assert_equals incomplete "$(jq -r .status "$feature_dir/state/readiness.json")"
jq -e '.findings | any(.id == "EVIDENCE_TRUST_INVALID:architecture")' "$feature_dir/state/readiness.json" >/dev/null

rm "$feature_dir/evidence/EV-self.json"; write_arch_evidence EV-verifier verification '["ARCH-1"]'; evaluate
assert_equals ready "$(jq -r .status "$feature_dir/state/readiness.json")"
jq -e '.advisory_architecture_constraint_ids == ["ARCH-ADVISORY"]' "$feature_dir/state/readiness.json" >/dev/null

write_arch_evidence EV-implementation-run implementation '["ARCH-1"]'
rm "$feature_dir/evidence/EV-verifier.json"
jq -n --arg digest "$digest" '{schema_version:"1",evidence_id:"EV-same-run",feature_id:"FEAT-TRUST",evidence_type:"architecture-conformance",provider_id:"verifier",producer:{id:"verifier",role:"verification",run_id:"EV-implementation-run"},coverage:{repository_ids:["app"],claim_ids:[],architecture_constraint_ids:["ARCH-1"]},subject:{repositories:{app:"commit:abc"}},policy_version:"1",provider_config_digest:$digest,result:"passed",outcome:"completed",environment:{id:"local",fixture:null},collected_at:"2026-08-13T01:01:00Z",expires_at:null,artifacts:[],findings:[],known_gaps:[]}' > "$feature_dir/evidence/EV-same-run.json"
evaluate
assert_equals incomplete "$(jq -r .status "$feature_dir/state/readiness.json")"
jq -e '.findings | any(.id == "EVIDENCE_TRUST_INVALID:architecture")' "$feature_dir/state/readiness.json" >/dev/null

rm "$feature_dir/evidence/EV-implementation-run.json" "$feature_dir/evidence/EV-same-run.json"
cat > "$feature_dir/waivers/WV-invalid.json" <<'JSON'
{"schema_version":"1","waiver_id":"WV-invalid","feature_id":"FEAT-TRUST","gate_id":"architecture","finding_id":"EVIDENCE_MISSING:architecture","scope":{"repositories":{"app":"commit:abc"},"claim_ids":[],"architecture_constraint_ids":["ARCH-1"],"environment_id":"local"},"approver":{"id":"agent"},"authority_evidence_id":"EV-missing","reason":"self approved","acknowledged_risk":"architecture proof missing","issued_at":"2026-08-13T00:00:00Z","expires_at":"2026-08-14T00:00:00Z","allow_revision_change":false}
JSON
evaluate
assert_equals incomplete "$(jq -r .status "$feature_dir/state/readiness.json")"
jq -e '.waivers == [] and (.findings | any(.id == "WAIVER_INVALID:architecture"))' "$feature_dir/state/readiness.json" >/dev/null
