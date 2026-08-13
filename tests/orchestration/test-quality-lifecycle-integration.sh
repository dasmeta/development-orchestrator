#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; source "$repo_root/tests/helpers/assert.sh"
tmp_dir="$(mktemp -d)"; trap 'rm -rf "$tmp_dir"' EXIT
feature="$tmp_dir/features/FEAT-LIFE"; mkdir -p "$feature/state" "$tmp_dir/config"
cat > "$feature/intake.md" <<'EOF'
# Legacy feature
EOF
cat > "$feature/state/manifest.json" <<'JSON'
{"feature_id":"FEAT-LIFE","stage":"definition","repositories":[],"mergeability":{"ready":false,"reason":"legacy"}}
JSON
cat > "$feature/state/github-state.json" <<'JSON'
{"pull_request":{"approved":true,"merged":false}}
JSON
cat > "$tmp_dir/config/workspace.json" <<'JSON'
{"quality":{"mode":"observe","policy":"policy.json"},"advance_when":{"path":".pull_request.approved","equals":true},"repositories":{},"stages":[]}
JSON
cat > "$tmp_dir/config/policy.json" <<'JSON'
{"schema_version":"1","policy_version":"1","protected_path_regex":[],"impact_rules":[],"gates":[],"providers":{},"decisions":{"stage-ready":{"require_gates":[]},"merge-ready":{"require_gates":[]},"release-ready":{"require_gates":[]}},"release_archive":{"kind":"filesystem","destination":"archive"},"budgets":{"provider_retries":0,"repair_attempts":0}}
JSON
bash "$repo_root/scripts/orchestration/migrate-feature-quality-v1.sh" --feature-dir "$feature" --config "$tmp_dir/config/workspace.json"
assert_file_exists "$feature/scope.json"; assert_file_exists "$feature/claims.json"; assert_file_exists "$feature/architecture.json"
jq -e '.quality.schema_version=="1" and .quality.current_decision=="stage-ready"' "$feature/state/manifest.json" >/dev/null
cp "$feature/intake.md" "$tmp_dir/intake-before"; bash "$repo_root/scripts/orchestration/migrate-feature-quality-v1.sh" --feature-dir "$feature" --config "$tmp_dir/config/workspace.json"; cmp "$tmp_dir/intake-before" "$feature/intake.md"

cat > "$feature/state/gate-plan.json" <<'JSON'
{"subject_fingerprint":"git-blob:current"}
JSON
cat > "$feature/state/readiness.json" <<'JSON'
{"decision":"merge-ready","status":"ready","subject_fingerprint":"git-blob:current"}
JSON
bash "$repo_root/scripts/orchestration/evaluate-mergeability.sh" "$feature" --config "$tmp_dir/config/workspace.json"
jq -e '.mergeability.ready==true and .mergeability.reason=="merge_ready"' "$feature/state/manifest.json" >/dev/null
jq '.subject_fingerprint="git-blob:stale"' "$feature/state/readiness.json" > "$tmp_dir/stale"; mv "$tmp_dir/stale" "$feature/state/readiness.json"
bash "$repo_root/scripts/orchestration/evaluate-mergeability.sh" "$feature" --config "$tmp_dir/config/workspace.json"
jq -e '.mergeability.ready==false' "$feature/state/manifest.json" >/dev/null
