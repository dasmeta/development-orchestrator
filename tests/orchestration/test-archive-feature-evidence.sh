#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; source "$repo_root/tests/helpers/assert.sh"
tmp_dir="$(mktemp -d)"; trap 'rm -rf "$tmp_dir"' EXIT
feature_dir="$tmp_dir/features/FEAT-REL"; mkdir -p "$feature_dir/state" "$feature_dir/evidence" "$feature_dir/waivers" "$tmp_dir/config"
cat > "$tmp_dir/config/workspace.json" <<'JSON'
{"quality":{"mode":"observe","policy":"policy.json"}}
JSON
cat > "$tmp_dir/config/policy.json" <<'JSON'
{"schema_version":"1","policy_version":"1","protected_path_regex":[],"impact_rules":[],"gates":[],"providers":{},"decisions":{"release-ready":{"require_gates":[]}},"release_archive":{"kind":"filesystem","destination":"../archive"},"budgets":{"provider_retries":0,"repair_attempts":0}}
JSON
cat > "$feature_dir/scope.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-REL","repositories":[{"id":"app","role":"implementation","subject":"commit:abc","changed_paths":[]}],"explicit_impacts":[],"derived_impacts":[],"policy_version":"1"}
JSON
cat > "$feature_dir/state/readiness.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-REL","decision":"release-ready","status":"ready","subject_fingerprint":"git-blob:scope","evaluated_at":"2026-08-13T02:00:00Z","gates":[],"findings":[],"known_gaps":[],"waivers":[],"advisory_architecture_constraint_ids":[]}
JSON
cat > "$feature_dir/evidence/EV-1.json" <<'JSON'
{"evidence_id":"EV-1","artifacts":[{"reference":"https://example.invalid/result","digest":"sha256:abc"}]}
JSON
bash "$repo_root/scripts/orchestration/archive-feature-evidence.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json" --now 2026-08-13T03:00:00Z
record="$tmp_dir/archive/FEAT-REL.json"; assert_file_exists "$record"
jq -e '.status=="ready" and .decision=="release-ready" and .subjects.app=="commit:abc" and (.evidence|length)==1 and .archived_at=="2026-08-13T03:00:00Z"' "$record" >/dev/null
cp "$record" "$tmp_dir/first-archive.json"
bash "$repo_root/scripts/orchestration/archive-feature-evidence.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json" --now 2026-08-13T04:00:00Z
cmp "$tmp_dir/first-archive.json" "$record"
jq '.status="blocked"' "$feature_dir/state/readiness.json" > "$tmp_dir/blocked.json"; mv "$tmp_dir/blocked.json" "$feature_dir/state/readiness.json"
assert_command_fails bash "$repo_root/scripts/orchestration/archive-feature-evidence.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json"
