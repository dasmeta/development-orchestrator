#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/templates/features"
cp "$repo_root/templates/features/intake.md" "$tmp_dir/templates/features/intake.md"
cp "$repo_root/templates/features/status.md" "$tmp_dir/templates/features/status.md"
mkdir -p "$tmp_dir/config"
cat > "$tmp_dir/config/workspace.json" <<'JSON'
{
  "workspace": {
    "name": "Example Product"
  },
  "initial_stage": "definition",
  "repositories": {
    "intent": {
      "path": "../intent",
      "role": "requirements"
    },
    "implementation": {
      "path": "../implementation",
      "role": "implementation"
    },
    "validation": {
      "path": "../validation",
      "role": "validation"
    }
  },
  "stages": [
    {
      "id": "definition",
      "repository": "intent",
      "skill": "speckit-specify"
    },
    {
      "id": "build",
      "repository": "implementation",
      "skill": "speckit-implement"
    },
    {
      "id": "validate",
      "repository": "validation",
      "skill": "speckit-implement"
    }
  ]
}
JSON

bash "$repo_root/scripts/orchestration/init-feature.sh" \
  --feature-id FEAT-0001 \
  --title "Branch previews for product delivery" \
  --repo-root "$tmp_dir" >/dev/null

feature_dir="$tmp_dir/features/FEAT-0001"

bash "$repo_root/scripts/orchestration/render-manifest.sh" \
  "$feature_dir" \
  --config "$tmp_dir/config/workspace.json"

assert_file_exists "$feature_dir/state/manifest.json"
jq -e '.feature_id == "FEAT-0001"' "$feature_dir/state/manifest.json" >/dev/null
jq -e '.stage == "definition"' "$feature_dir/state/manifest.json" >/dev/null
jq -e '.repositories == ["intent","implementation","validation"]' \
  "$feature_dir/state/manifest.json" >/dev/null
jq -e '.mergeability.ready == false' "$feature_dir/state/manifest.json" >/dev/null

bash "$repo_root/scripts/orchestration/render-manifest.sh" \
  "$feature_dir"

jq -e '.repositories == ["intent","contracts","implementation","validation"]' \
  "$feature_dir/state/manifest.json" >/dev/null
