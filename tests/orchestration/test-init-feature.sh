#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/templates/features"
cat <<'EOF' > "$tmp_dir/templates/features/intake.md"
# Feature Intake: {{FEATURE_ID}}

## Title
{{TITLE}}
EOF
cat <<'EOF' > "$tmp_dir/templates/features/status.md"
# Feature Status: {{FEATURE_ID}}

- stage: `requirements`
- status: `pending`
EOF
cat <<'EOF' > "$tmp_dir/templates/features/scope.json"
{"schema_version":"1","feature_id":"{{FEATURE_ID}}","repositories":[],"explicit_impacts":[],"derived_impacts":[],"policy_version":null}
EOF
cat <<'EOF' > "$tmp_dir/templates/features/claims.json"
{"schema_version":"1","feature_id":"{{FEATURE_ID}}","claims":[]}
EOF
cat <<'EOF' > "$tmp_dir/templates/features/architecture.json"
{"schema_version":"1","feature_id":"{{FEATURE_ID}}","sources":[],"constraints":[]}
EOF

bash "$repo_root/scripts/orchestration/init-feature.sh" \
  --feature-id FEAT-0001 \
  --title "Branch previews for product delivery" \
  --repo-root "$tmp_dir"

feature_dir="$tmp_dir/features/FEAT-0001"
assert_file_exists "$feature_dir/intake.md"
assert_file_exists "$feature_dir/state/status.md"
assert_contains "$feature_dir/intake.md" "FEAT-0001"
assert_contains "$feature_dir/intake.md" "Branch previews for product delivery"
assert_contains "$feature_dir/state/status.md" "FEAT-0001"
assert_file_exists "$feature_dir/scope.json"
assert_file_exists "$feature_dir/claims.json"
assert_file_exists "$feature_dir/architecture.json"
[[ -d "$feature_dir/evidence" ]] || {
  echo "expected directory to exist: $feature_dir/evidence" >&2
  exit 1
}
[[ -d "$feature_dir/waivers" ]] || {
  echo "expected directory to exist: $feature_dir/waivers" >&2
  exit 1
}
[[ -d "$feature_dir/state/runs" ]] || {
  echo "expected directory to exist: $feature_dir/state/runs" >&2
  exit 1
}
[[ -d "$feature_dir/state/provider-runs" ]] || {
  echo "expected directory to exist: $feature_dir/state/provider-runs" >&2
  exit 1
}

jq -e '.schema_version == "1" and .feature_id == "FEAT-0001"' \
  "$feature_dir/scope.json" >/dev/null
jq -e '.schema_version == "1" and .feature_id == "FEAT-0001"' \
  "$feature_dir/claims.json" >/dev/null
jq -e '.schema_version == "1" and .feature_id == "FEAT-0001"' \
  "$feature_dir/architecture.json" >/dev/null
