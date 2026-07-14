#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

skill="$repo_root/.agents/skills/workspace-bootstrap/SKILL.md"
runbook="$repo_root/docs/runbooks/workspace-bootstrap.md"

assert_file_exists "$skill"
assert_file_exists "$runbook"

assert_contains "$skill" "name: workspace-bootstrap"
assert_contains "$skill" "Initial bootstrap"
assert_contains "$skill" "New-person setup"
assert_contains "$skill" "Repository refresh"
assert_contains "$skill" "one question at a time"
assert_contains "$skill" "needs-input"
assert_contains "$skill" "--dry-run"
assert_contains "$skill" "--print-token"
assert_contains "$skill" "explicit confirmation"
assert_contains "$skill" "dirty repositories"
assert_contains "$skill" "Do not silently move, clone, link, add, or remove repositories"

for expected in \
  "GitHub" \
  "GitLab" \
  "Bitbucket" \
  "self-hosted" \
  "local-only" \
  "00-" \
  "01-" \
  "02-" \
  "03-" \
  "04-" \
  "05-" \
  "config/repository-index.json" \
  "overlays/repository-index.md"; do
  assert_contains "$skill" "$expected"
done

assert_contains "$runbook" "Initial Bootstrap"
assert_contains "$runbook" "New-Person Setup"
assert_contains "$runbook" "Repository Refresh"
assert_contains "$runbook" "discover-workspace.sh"
assert_contains "$runbook" "compare-workspace-inventory.sh"
assert_contains "$runbook" "validate-workspace-proposal.sh"
assert_contains "$runbook" "apply-workspace-proposal.sh"
assert_contains "$runbook" "Recovery"

assert_contains "$repo_root/README.md" "Compose A Product Workspace"
assert_contains "$repo_root/README.md" "docs/runbooks/workspace-bootstrap.md"
assert_contains "$repo_root/README.md" 'Use `$workspace-bootstrap`'
assert_contains "$repo_root/README.md" "Creating a product workspace"
assert_contains "$repo_root/README.md" "Joining an existing product workspace"
assert_contains "$repo_root/README.md" "Refreshing the repository catalog"
assert_contains "$repo_root/README.md" "Requirements and product intent"
assert_contains "$repo_root/README.md" "Successful bootstrap"
assert_contains "$repo_root/README.md" "Forge Support"
assert_contains "$repo_root/README.md" "GitHub-specific"
assert_contains "$repo_root/README.md" "Prerequisites"
assert_contains "$repo_root/README.md" "Bash 3.2 or newer"
assert_contains "$repo_root/README.md" "git remote add upstream"
assert_contains "$repo_root/README.md" "working directory set to the product fork"
assert_contains "$repo_root/README.md" ".has_changes == false"
assert_contains "$repo_root/README.md" "Documentation Map"
assert_contains "$repo_root/AI-INDEX.md" "workspace-bootstrap"
assert_contains "$repo_root/AI-INDEX.md" "config/repository-index.json"

for test_command in \
  "test-discover-workspace.sh" \
  "test-validate-workspace-proposal.sh" \
  "test-render-workspace-files.sh" \
  "test-compare-workspace-inventory.sh" \
  "test-apply-workspace-proposal.sh" \
  "test-workspace-bootstrap-guidance.sh"; do
  assert_file_exists "$repo_root/tests/orchestration/$test_command"
done

assert_contains \
  "$repo_root/scripts/orchestration/run-ci-tests.sh" \
  'tests/orchestration/test-*.sh'
