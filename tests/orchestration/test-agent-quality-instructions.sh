#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

assert_file_exists "$repo_root/CLAUDE.md"
assert_contains "$repo_root/CLAUDE.md" "@AGENTS.md"

assert_contains "$repo_root/AGENTS.md" "## Evidence Quality Lifecycle"
assert_contains "$repo_root/AGENTS.md" "config/workspace.json"
assert_contains "$repo_root/AGENTS.md" "mandatory"
assert_contains "$repo_root/AGENTS.md" "scripts/orchestration/run-quality-cycle.sh"
assert_contains "$repo_root/AGENTS.md" '`stage-ready`'
assert_contains "$repo_root/AGENTS.md" '`merge-ready`'
assert_contains "$repo_root/AGENTS.md" '`release-ready`'
assert_contains "$repo_root/AGENTS.md" '`observe`'
assert_contains "$repo_root/AGENTS.md" '`enforce`'
assert_contains "$repo_root/AGENTS.md" "Do not claim readiness"
assert_contains "$repo_root/AGENTS.md" "generated readiness report"
