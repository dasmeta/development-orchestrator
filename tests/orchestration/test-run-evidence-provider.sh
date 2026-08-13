#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; source "$repo_root/tests/helpers/assert.sh"
tmp_dir="$(mktemp -d)"; trap 'rm -rf "$tmp_dir"' EXIT
feature_dir="$tmp_dir/features/FEAT-0001"; mkdir -p "$feature_dir/state" "$feature_dir/evidence" "$feature_dir/waivers" "$tmp_dir/config" "$tmp_dir/app"
bin="$repo_root/tests/fixtures/quality/bin"
cat > "$tmp_dir/config/workspace.json" <<'JSON'
{"quality":{"mode":"observe","policy":"policy.json"},"repositories":{"app":{"path":"../app","role":"implementation"}}}
JSON
jq -n --arg pass "$bin/fake-pass-provider" --arg fail "$bin/fake-fail-provider" --arg json "$bin/fake-json-provider" '
 {schema_version:"1",policy_version:"1",protected_path_regex:[],impact_rules:[],gates:[
  {id:"tests",decisions:["merge-ready"],when:{impacts_any:["implementation"]},evidence_types:["focused-tests"],providers:["pass","fail","json"],coverage:{claims:"all",architecture:"none"},required_result:"passed"}],
  providers:{
   pass:{kind:"command",trust:"repository-check",producer_role:"verification",repository_ids:["app"],working_directory:".",command:[$pass,"spaced argument"],output_mode:"exit-code"},
   fail:{kind:"command",trust:"repository-check",producer_role:"verification",repository_ids:["app"],working_directory:".",command:[$fail],output_mode:"exit-code"},
   json:{kind:"command",trust:"repository-check",producer_role:"verification",repository_ids:["app"],working_directory:".",command:[$json],output_mode:"evidence-json"}},
  decisions:{"merge-ready":{require_gates:["tests"]}},release_archive:{kind:"filesystem",destination:"archive"},budgets:{provider_retries:1,repair_attempts:2}}' > "$tmp_dir/config/policy.json"
cat > "$feature_dir/scope.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-0001","repositories":[{"id":"app","role":"implementation","subject":"commit:abc","changed_paths":["src/a.ts"]}],"explicit_impacts":["implementation"],"derived_impacts":[],"policy_version":"1"}
JSON
cat > "$feature_dir/claims.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-0001","claims":[{"id":"AC-1","source":{"repository_id":"intent","revision":"1","path":"spec.md"},"content_digest":"x"}]}
JSON
cat > "$feature_dir/architecture.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-0001","sources":[],"constraints":[]}
JSON
cat > "$feature_dir/state/gate-plan.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-0001","policy_version":"1","subject_fingerprint":"git-blob:scope","resolved_at":"2026-08-13T00:00:00Z","impacts":{"explicit":["implementation"],"derived":[],"all":["implementation"]},"impact_sources":[],"gates":[{"id":"tests","applicability":"required","reason":"match","decisions":["merge-ready"],"evidence_types":["focused-tests"],"providers":["pass","fail","json"],"coverage":{"claims":"all","architecture":"none"},"required_result":"passed"}],"findings":[]}
JSON
run_provider() { bash "$repo_root/scripts/orchestration/run-evidence-provider.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json" --provider "$1" --evidence-type focused-tests --run-id "$2" --now 2026-08-13T01:00:00Z; }
run_provider pass run-pass
jq -e '.result=="passed" and .producer.run_id=="run-pass" and .coverage.claim_ids==["AC-1"] and (.artifacts[0].digest|startswith("git-blob:"))' "$feature_dir/evidence/EV-pass-run-pass.json" >/dev/null
run_provider fail run-fail
jq -e '.result=="failed" and .outcome=="exit-code:7"' "$feature_dir/evidence/EV-fail-run-fail.json" >/dev/null
run_provider json run-json
assert_file_exists "$feature_dir/evidence/EV-json.json"
assert_command_fails bash "$repo_root/scripts/orchestration/run-evidence-provider.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json" --provider pass --evidence-type build --run-id mismatch

jq '.providers.pass.working_directory="../outside"' "$tmp_dir/config/policy.json" > "$tmp_dir/config/escape-policy.json"
jq '.quality.policy="escape-policy.json"' "$tmp_dir/config/workspace.json" > "$tmp_dir/config/escape-workspace.json"
assert_command_fails bash "$repo_root/scripts/orchestration/run-evidence-provider.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/escape-workspace.json" --provider pass --evidence-type focused-tests --run-id escape
assert_command_fails bash "$repo_root/scripts/orchestration/run-evidence-provider.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json" --provider missing --evidence-type focused-tests --run-id missing
assert_command_fails bash "$repo_root/scripts/orchestration/run-evidence-provider.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json" --provider pass --evidence-type focused-tests --run-id ../escape
jq '.providers.json.command=["/bin/echo","not-json"]' "$tmp_dir/config/policy.json" > "$tmp_dir/config/bad-json-policy.json"
jq '.quality.policy="bad-json-policy.json"' "$tmp_dir/config/workspace.json" > "$tmp_dir/config/bad-json-workspace.json"
assert_command_fails bash "$repo_root/scripts/orchestration/run-evidence-provider.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/bad-json-workspace.json" --provider json --evidence-type focused-tests --run-id malformed
