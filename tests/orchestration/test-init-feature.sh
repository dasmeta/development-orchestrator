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
