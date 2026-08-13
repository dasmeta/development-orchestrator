#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
feature_dir="$tmp_dir/features/FEAT-MULTI"
mkdir -p "$feature_dir/state" "$feature_dir/evidence" \
  "$feature_dir/waivers" "$tmp_dir/config" "$tmp_dir/app-a" "$tmp_dir/app-b"

cat > "$tmp_dir/config/workspace.json" <<'JSON'
{"quality":{"mode":"observe","policy":"policy.json"},"repositories":{"app-a":{"path":"../app-a","role":"implementation"},"app-b":{"path":"../app-b","role":"implementation"}}}
JSON
jq -n --arg command "$repo_root/tests/fixtures/quality/bin/fake-pass-provider" '
  {schema_version:"1",policy_version:"1",protected_path_regex:[],impact_rules:[],
   gates:[{id:"tests",decisions:["merge-ready"],when:{impacts_any:["implementation"]},evidence_types:["focused-tests"],providers:["tests"],coverage:{claims:"all",architecture:"none"},required_result:"passed"}],
   providers:{tests:{kind:"command",trust:"repository-check",producer_role:"verification",repository_ids:["app-a","app-b"],working_directory:".",command:[$command],output_mode:"exit-code"}},
   decisions:{"merge-ready":{require_gates:["tests"]}},release_archive:{kind:"filesystem",destination:"archive"},budgets:{provider_retries:0,repair_attempts:0}}
' > "$tmp_dir/config/policy.json"
cat > "$feature_dir/scope.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-MULTI","repositories":[{"id":"app-a","role":"implementation","subject":"commit:aaa","changed_paths":["a"]},{"id":"app-b","role":"implementation","subject":"commit:bbb","changed_paths":["b"]}],"explicit_impacts":["implementation"],"derived_impacts":[],"policy_version":"1"}
JSON
cat > "$feature_dir/claims.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-MULTI","claims":[{"id":"AC-1","source":{"repository_id":"intent","revision":"1","path":"spec.md"},"content_digest":"x"}]}
JSON
cat > "$feature_dir/architecture.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-MULTI","sources":[],"constraints":[]}
JSON
cat > "$feature_dir/state/gate-plan.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-MULTI","policy_version":"1","subject_fingerprint":"git-blob:scope","resolved_at":"2026-08-13T00:00:00Z","impacts":{"explicit":["implementation"],"derived":[],"all":["implementation"]},"impact_sources":[],"gates":[{"id":"tests","applicability":"required","reason":"match","decisions":["merge-ready"],"evidence_types":["focused-tests"],"providers":["tests"],"provider_strategy":"all","coverage":{"claims":"all","architecture":"none"},"required_result":"passed"}],"findings":[]}
JSON

bash "$repo_root/scripts/orchestration/run-quality-providers.sh" \
  --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json" \
  --decision merge-ready --run-id multi

assert_file_exists "$feature_dir/evidence/EV-tests-multi-app-a-0.json"
assert_file_exists "$feature_dir/evidence/EV-tests-multi-app-b-0.json"
jq -e '.coverage.repository_ids==["app-a"] and .subject.repositories=={"app-a":"commit:aaa"}' \
  "$feature_dir/evidence/EV-tests-multi-app-a-0.json" >/dev/null
jq -e '.coverage.repository_ids==["app-b"] and .subject.repositories=={"app-b":"commit:bbb"}' \
  "$feature_dir/evidence/EV-tests-multi-app-b-0.json" >/dev/null
