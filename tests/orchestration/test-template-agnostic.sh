#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

forbidden='01-product-requirements|03-shared-contracts|02-e2e-tests|04-frontend|04-orchestrator|frontend-handoff|Lovable|Product Core Prompt|Product Use Case|Product Tool|/Users/aram'

if rg -n "$forbidden" \
  --glob '!**/test-template-agnostic.sh' \
  "$repo_root/AGENTS.md" \
  "$repo_root/AI-INDEX.md" \
  "$repo_root/README.md" \
  "$repo_root/TODO.md" \
  "$repo_root/config" \
  "$repo_root/docs" \
  "$repo_root/scripts" \
  "$repo_root/schemas" \
  "$repo_root/templates" \
  "$repo_root/tests" \
  "$repo_root/.github" \
  "$repo_root/.specify" \
  "$repo_root/.agents"; then
  echo "template contains product-specific or local-machine-specific text" >&2
  exit 1
fi
