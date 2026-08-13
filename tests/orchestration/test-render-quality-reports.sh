#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; source "$repo_root/tests/helpers/assert.sh"
tmp_dir="$(mktemp -d)"; trap 'rm -rf "$tmp_dir"' EXIT
feature_dir="$tmp_dir/features/FEAT-0001"; mkdir -p "$feature_dir/state"
cat > "$feature_dir/scope.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-0001","repositories":[{"id":"app","role":"implementation","subject":"commit:abc","changed_paths":["src/a.ts"],"dependencies":[],"captured_at":"2026-08-13T00:00:00Z"}],"explicit_impacts":["implementation","architecture-sensitive"],"derived_impacts":[],"policy_version":"1"}
JSON
cat > "$feature_dir/state/gate-plan.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-0001","policy_version":"1","subject_fingerprint":"git-blob:scope","resolved_at":"2026-08-13T00:00:00Z","impacts":{"explicit":["architecture-sensitive","implementation"],"derived":[],"all":["architecture-sensitive","implementation"]},"impact_sources":[],"gates":[],"findings":[]}
JSON
cat > "$feature_dir/state/readiness.json" <<'JSON'
{
 "schema_version":"1","feature_id":"FEAT-0001","decision":"merge-ready","status":"blocked","subject_fingerprint":"git-blob:scope","evaluated_at":"2026-08-13T02:00:00Z",
 "gates":[
  {"id":"tests","status":"failed","applicability":"required","reason":"configured_impact_match","evidence_id":null,"evidence_ids":["EV-tests-a","EV-tests-b"],"waiver":null,"findings":[]},
  {"id":"visual","status":"blocked","applicability":"required","reason":"configured_impact_match","evidence_id":"EV-visual","waiver":null,"findings":[]},
  {"id":"documentation","status":"ready","applicability":"required","reason":"configured_impact_match","evidence_id":"EV-docs","waiver":null,"findings":[]}
 ],
 "findings":[
  {"id":"EVIDENCE_FAILED:tests","class":"evidence","owner":"implementation","gate_id":"tests","message":"Tests failed"},
  {"id":"EVIDENCE_BLOCKED:visual","class":"evidence","owner":"verification","gate_id":"visual","message":"Visual provider unavailable"}
 ],
 "known_gaps":[{"id":"GAP-1","message":"Architecture catalogue pending"}],
 "waivers":[{"waiver_id":"WV-1","gate_id":"performance","reason":"Accepted for this revision","approver":{"id":"reviewer"}}],
 "advisory_architecture_constraint_ids":["ARCH-ADVISORY"]
}
JSON
bash "$repo_root/scripts/orchestration/render-quality-reports.sh" --feature-dir "$feature_dir"
assert_file_exists "$feature_dir/state/readiness.md"; assert_file_exists "$feature_dir/state/pr-summary.md"
for id in EVIDENCE_FAILED:tests EVIDENCE_BLOCKED:visual; do
  assert_contains "$feature_dir/state/readiness.md" "$id"; assert_contains "$feature_dir/state/pr-summary.md" "$id"
done
assert_contains "$feature_dir/state/readiness.md" "Architecture conformance"
assert_contains "$feature_dir/state/readiness.md" "ARCH-ADVISORY"
assert_contains "$feature_dir/state/pr-summary.md" "commit:abc"
assert_contains "$feature_dir/state/pr-summary.md" "WV-1"
for evidence_id in EV-tests-a EV-tests-b; do
  assert_contains "$feature_dir/state/readiness.md" "$evidence_id"
  assert_contains "$feature_dir/state/pr-summary.md" "$evidence_id"
done
cmp "$repo_root/tests/fixtures/quality/expected-readiness.md" \
  "$feature_dir/state/readiness.md"
cmp "$repo_root/tests/fixtures/quality/expected-pr-summary.md" \
  "$feature_dir/state/pr-summary.md"
cp "$feature_dir/state/readiness.md" "$tmp_dir/readiness-first.md"; cp "$feature_dir/state/pr-summary.md" "$tmp_dir/summary-first.md"
bash "$repo_root/scripts/orchestration/render-quality-reports.sh" --feature-dir "$feature_dir"
cmp "$tmp_dir/readiness-first.md" "$feature_dir/state/readiness.md"; cmp "$tmp_dir/summary-first.md" "$feature_dir/state/pr-summary.md"
jq '.subject_fingerprint="git-blob:stale"' "$feature_dir/state/readiness.json" > "$tmp_dir/stale.json"; mv "$tmp_dir/stale.json" "$feature_dir/state/readiness.json"
assert_command_fails bash "$repo_root/scripts/orchestration/render-quality-reports.sh" --feature-dir "$feature_dir"
