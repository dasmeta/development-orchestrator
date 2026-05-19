#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/features/FEAT-0001/state"

bash "$repo_root/scripts/orchestration/collect-github-state.sh" \
  --feature-dir "$tmp_dir/features/FEAT-0001" \
  --fixtures "$repo_root/tests/fixtures/github"

state_path="$tmp_dir/features/FEAT-0001/state/github-state.json"
assert_file_exists "$state_path"
jq -e '.pull_request.approved == true' "$state_path" >/dev/null
jq -e '.pull_request.merged == false' "$state_path" >/dev/null
jq -e '.checks.implementation == "green"' "$state_path" >/dev/null
jq -e '.preview.status == "ready"' "$state_path" >/dev/null
