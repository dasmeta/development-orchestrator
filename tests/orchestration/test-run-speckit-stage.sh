#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/features/FEAT-0001/state"
cat <<'EOF' > "$tmp_dir/features/FEAT-0001/intake.md"
# Feature Intake: FEAT-0001

## Title
Branch previews for product delivery
EOF
mkdir -p "$tmp_dir/config"
cat > "$tmp_dir/config/workspace.json" <<'JSON'
{
  "repositories": {
    "intent": {
      "path": "../intent",
      "role": "requirements"
    }
  },
  "stages": [
    {
      "id": "definition",
      "repository": "intent",
      "skill": "speckit-specify"
    }
  ]
}
JSON

bash "$repo_root/scripts/orchestration/run-speckit-stage.sh" \
  --feature-dir "$tmp_dir/features/FEAT-0001" \
  --stage definition \
  --dry-run \
  --config "$tmp_dir/config/workspace.json"

log_path="$tmp_dir/features/FEAT-0001/state/run-log.json"
assert_file_exists "$log_path"
jq -e '.repo == "intent"' "$log_path" >/dev/null
jq -e '.stage == "definition"' "$log_path" >/dev/null
jq -e '.dry_run == true' "$log_path" >/dev/null
