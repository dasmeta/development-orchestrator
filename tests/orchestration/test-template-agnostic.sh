#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

forbidden_parts=(
  "Gal""ust"
  "01-product""-requirements"
  "03-shared""-contracts"
  "02-e2e""-tests"
  "04-front""end"
  "04-orch""estrator"
  "frontend""-handoff"
  "Lov""able"
  "Product Core"" Prompt"
  "Product Use"" Case"
  "Product"" Tool"
  "/Users/""aram"
)
forbidden="$(IFS='|'; echo "${forbidden_parts[*]}")"
reserved_paths='^(WORKSPACE\.md|config/workspace\.json|00-[^/]*(/|$)|01-[^/]*(/|$)|02-[^/]*(/|$)|03-[^/]*(/|$)|04-[^/]*(/|$)|05-[^/]*(/|$)|workspace(/|$)|overlays(/|$))'

if rg -n '/(Users|home)/|[A-Z]:\\\\' \
  "$repo_root/scripts" "$repo_root/schemas" "$repo_root/templates" \
  "$repo_root/config/workspace.example.json"; then
  echo "generic engine contains an absolute local path" >&2
  exit 1
fi

if rg -n 'frontend-tests|product-e2e|visual-review-import|architecture-review-import|orchestrator-core-tests|orchestrator-mcp-tests|orchestrator-scheduled-trigger-test' \
  "$repo_root/scripts" "$repo_root/schemas" "$repo_root/templates" \
  "$repo_root/config/workspace.example.json"; then
  echo "generic engine contains adopter-only provider or evidence identifiers" >&2
  exit 1
fi

if rg -n "$forbidden" \
  --glob '!**/test-template-agnostic.sh' \
  "$repo_root/AGENTS.md" \
  "$repo_root/CLAUDE.md" \
  "$repo_root/AI-INDEX.md" \
  "$repo_root/README.md" \
  "$repo_root/TODO.md" \
  "$repo_root/config" \
  "$repo_root/docs" \
  "$repo_root/scripts" \
  "$repo_root/schemas" \
  "$repo_root/specs" \
  "$repo_root/templates" \
  "$repo_root/tests" \
  "$repo_root/.github" \
  "$repo_root/.gitlab-ci.yml" \
  "$repo_root/bitbucket-pipelines.yml" \
  "$repo_root/.specify" \
  "$repo_root/.agents"; then
  echo "template contains product-specific or local-machine-specific text" >&2
  exit 1
fi

if git -C "$repo_root" ls-files | rg -n "$reserved_paths"; then
  echo "template tracks fork-owned reserved paths" >&2
  exit 1
fi

if ! git -C "$repo_root" ls-files --error-unmatch config/workspace.example.json >/dev/null 2>&1; then
  echo "template must track config/workspace.example.json" >&2
  exit 1
fi
