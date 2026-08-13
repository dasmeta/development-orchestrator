#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/templates/features"
cp "$repo_root/templates/features/intake.md" "$tmp_dir/templates/features/intake.md"
cp "$repo_root/templates/features/status.md" "$tmp_dir/templates/features/status.md"
cp "$repo_root/templates/features/scope.json" "$tmp_dir/templates/features/scope.json"
cp "$repo_root/templates/features/claims.json" "$tmp_dir/templates/features/claims.json"
cp "$repo_root/templates/features/architecture.json" "$tmp_dir/templates/features/architecture.json"
mkdir -p "$tmp_dir/config"
cat > "$tmp_dir/config/workspace.json" <<'JSON'
{
  "initial_stage": "definition",
  "advance_when": {
    "path": ".pull_request.approved",
    "equals": true
  },
  "repositories": {
    "intent": {
      "path": "../intent",
      "role": "requirements"
    },
    "implementation": {
      "path": "../implementation",
      "role": "implementation"
    }
  },
  "stages": [
    {
      "id": "definition",
      "repository": "intent",
      "skill": "speckit-specify"
    },
    {
      "id": "implementation",
      "repository": "implementation",
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
cat > "$feature_dir/state/github-state.json" <<'JSON'
{
  "pull_request": {
    "approved": true,
    "merged": false
  }
}
JSON

bash "$repo_root/scripts/orchestration/advance-stage.sh" \
  "$feature_dir" \
  --config "$tmp_dir/config/workspace.json"

jq -e '.stage == "implementation"' "$feature_dir/state/manifest.json" >/dev/null
jq -e '.mergeability.ready == false' "$feature_dir/state/manifest.json" >/dev/null
