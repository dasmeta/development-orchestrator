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
  "initial_stage": "definition",
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
      "id": "build",
      "repository": "implementation",
      "skill": "speckit-implement"
    }
  ],
  "mergeability": {
    "ready_reason": "all_configured_gates_green",
    "incomplete_reason": "configured_gates_incomplete",
    "required": [
      {
        "path": ".pull_request.merged",
        "equals": true
      },
      {
        "path": ".checks.implementation",
        "equals": "green"
      }
    ]
  }
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

jq -n \
  '{
    pull_request: {
      approved: true,
      merged: true
    },
    checks: {
      implementation: "green"
    }
  }' > "$feature_dir/state/github-state.json"

bash "$repo_root/scripts/orchestration/evaluate-mergeability.sh" \
  "$feature_dir" \
  --config "$tmp_dir/config/workspace.json"

jq -e '.mergeability.ready == true' "$feature_dir/state/manifest.json" >/dev/null
jq -e '.mergeability.reason == "all_configured_gates_green"' "$feature_dir/state/manifest.json" >/dev/null
