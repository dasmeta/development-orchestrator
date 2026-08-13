#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; source "$repo_root/tests/helpers/assert.sh"
tmp_dir="$(mktemp -d)"; trap 'rm -rf "$tmp_dir"' EXIT
feature_dir="$tmp_dir/features/FEAT-CYCLE"; mkdir -p "$feature_dir/state" "$feature_dir/evidence" "$feature_dir/waivers" "$tmp_dir/config"
cat > "$tmp_dir/config/workspace.json" <<'JSON'
{"quality":{"mode":"observe","policy":"policy.json"},"repositories":{},"stages":[]}
JSON
cat > "$tmp_dir/config/policy.json" <<'JSON'
{"schema_version":"1","policy_version":"1","protected_path_regex":[],"impact_rules":[],"gates":[],"providers":{},"decisions":{"merge-ready":{"require_gates":[]}},"release_archive":{"kind":"filesystem","destination":"archive"},"budgets":{"provider_retries":0,"repair_attempts":1}}
JSON
cat > "$feature_dir/scope.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-CYCLE","repositories":[],"explicit_impacts":[],"derived_impacts":[],"policy_version":"1"}
JSON
cat > "$feature_dir/claims.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-CYCLE","claims":[]}
JSON
cat > "$feature_dir/architecture.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-CYCLE","sources":[],"constraints":[]}
JSON
bash "$repo_root/scripts/orchestration/run-quality-cycle.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json" --decision merge-ready --run-id cycle-1 --now 2026-08-13T01:00:00Z
assert_equals ready "$(jq -r .status "$feature_dir/state/readiness.json")"; assert_file_exists "$feature_dir/state/readiness.md"

jq '.quality.mode="off"' "$tmp_dir/config/workspace.json" > "$tmp_dir/config/off.json"
assert_command_fails bash "$repo_root/scripts/orchestration/run-quality-cycle.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/off.json" --decision merge-ready --run-id cycle-off
bash "$repo_root/scripts/orchestration/run-quality-cycle.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/off.json" --decision merge-ready --run-id cycle-force --force-evaluate

jq '.quality.mode="enforce"' "$tmp_dir/config/workspace.json" > "$tmp_dir/config/enforce.json"
jq '.gates=[{"id":"missing","decisions":["merge-ready"],"when":{"impacts_any":[]},"evidence_types":["external"],"providers":["external"],"coverage":{"claims":"none","architecture":"none"},"required_result":"passed"}] | .providers={"external":{"kind":"external-import","trust":"external","producer_role":"verification","repository_ids":["none"]}} | .decisions["merge-ready"].require_gates=["missing"]' "$tmp_dir/config/policy.json" > "$tmp_dir/config/enforce-policy.json"
jq '.quality.policy="enforce-policy.json"' "$tmp_dir/config/enforce.json" > "$tmp_dir/config/enforce-workspace.json"
set +e; bash "$repo_root/scripts/orchestration/run-quality-cycle.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/enforce-workspace.json" --decision merge-ready --run-id cycle-incomplete; status=$?; set -e
assert_equals 20 "$status"
