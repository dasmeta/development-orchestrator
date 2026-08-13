#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; source "$repo_root/tests/helpers/assert.sh"
tmp_dir="$(mktemp -d)"; trap 'rm -rf "$tmp_dir"' EXIT
feature_dir="$tmp_dir/features/FEAT-V"; mkdir -p "$feature_dir/state" "$feature_dir/evidence" "$feature_dir/waivers" "$tmp_dir/config" "$tmp_dir/app"
git init -q "$tmp_dir/app"; git -C "$tmp_dir/app" config user.name Test; git -C "$tmp_dir/app" config user.email test@example.invalid; printf 'base\n' > "$tmp_dir/app/a.txt"; git -C "$tmp_dir/app" add a.txt; git -C "$tmp_dir/app" commit -qm base
cat > "$tmp_dir/fake-verifier" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
repository="$1"; prompt="$2"; schema="$3"; result="$4"
[[ -d "$repository" && -f "$prompt" && -f "$schema" ]]
grep -q 'Do not edit files' "$prompt"; grep -q 'AC-1' "$prompt"; grep -q 'ARCH-1' "$prompt"
printf '%s\n' '{"result":"passed","covered_claim_ids":["AC-1"],"covered_architecture_constraint_ids":["ARCH-1"],"architecture_disposition":"not_applicable","documentation_disposition":"updated","artifact_references":[{"uri":"changes/FEAT-V.md","digest":"git-blob:abc"}],"findings":[],"known_gaps":[]}' > "$result"
SH
chmod +x "$tmp_dir/fake-verifier"
cat > "$tmp_dir/config/workspace.json" <<'JSON'
{"quality":{"mode":"observe","policy":"policy.json"},"repositories":{"app":{"path":"../app","role":"implementation"}}}
JSON
jq -n --arg command "$tmp_dir/fake-verifier" '{schema_version:"1",policy_version:"1",protected_path_regex:[],impact_rules:[],gates:[{id:"independent",decisions:["merge-ready"],when:{impacts_any:["implementation"]},evidence_types:["independent-verification"],providers:["verifier"],coverage:{claims:"all",architecture:"all_blocking"},required_result:"passed"}],providers:{verifier:{kind:"verifier",trust:"read-only-verifier",producer_role:"verification",repository_ids:["app"],working_directory:".",command:[$command,"{repository}","{prompt}","{schema}","{result}"],output_mode:"verifier-json"}},decisions:{"merge-ready":{require_gates:["independent"]}},release_archive:{kind:"filesystem",destination:"archive"},budgets:{provider_retries:0,repair_attempts:1}}' > "$tmp_dir/config/policy.json"
cat > "$feature_dir/intake.md" <<'EOF'
# Feature verifier test
EOF
cat > "$feature_dir/scope.json" <<JSON
{"schema_version":"1","feature_id":"FEAT-V","repositories":[{"id":"app","role":"implementation","subject":"commit:$(git -C "$tmp_dir/app" rev-parse HEAD)","changed_paths":["a.txt"]}],"explicit_impacts":["implementation"],"derived_impacts":[],"policy_version":"1"}
JSON
cat > "$feature_dir/claims.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-V","claims":[{"id":"AC-1","source":{"repository_id":"intent","revision":"1","path":"spec.md"},"content_digest":"x"}]}
JSON
cat > "$feature_dir/architecture.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-V","sources":[{"id":"S","repository_id":"arch","revision":"1","path":"adr.md","content_digest":"x","approval_evidence_id":null}],"constraints":[{"id":"ARCH-1","source_id":"S","content_digest":"x","impacts":["implementation"],"enforcement":"blocking","approval_evidence_id":null}]}
JSON
cat > "$feature_dir/state/gate-plan.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-V","policy_version":"1","subject_fingerprint":"git-blob:scope","resolved_at":"2026-08-13T00:00:00Z","impacts":{"explicit":["implementation"],"derived":[],"all":["implementation"]},"impact_sources":[],"gates":[{"id":"independent","applicability":"required","reason":"match","decisions":["merge-ready"],"evidence_types":["independent-verification"],"providers":["verifier"],"coverage":{"claims":"all","architecture":"all_blocking"},"required_result":"passed"}],"findings":[]}
JSON
assert_command_fails bash "$repo_root/scripts/orchestration/run-independent-verifier.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json" --provider verifier --repository app --implementation-run-id same-run --run-id same-run
bash "$repo_root/scripts/orchestration/run-independent-verifier.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json" --provider verifier --repository app --implementation-run-id implementation-run --run-id verifier-run --now 2026-08-13T01:00:00Z
evidence="$feature_dir/evidence/EV-verifier-independent-verifier-run.json"; assert_file_exists "$evidence"
jq -e '.result=="passed" and .producer.run_id=="verifier-run" and .coverage.claim_ids==["AC-1"] and .coverage.architecture_constraint_ids==["ARCH-1"] and .producer.role=="verification"' "$evidence" >/dev/null
assert_file_exists "$feature_dir/state/provider-runs/verifier-run/verifier/verifier-prompt.md"
