#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp_dir"; exit $status' EXIT

proposal="$tmp_dir/proposal.json"
output_root="$tmp_dir/rendered"

mkdir -p "$tmp_dir/workspace" "$tmp_dir/requirements"
jq -n \
  --arg workspace_root "$tmp_dir/workspace" \
  --arg requirements_source "$tmp_dir/requirements" \
  '{
    schema_version: 1,
    proposal_id: "bootstrap-render",
    status: "approved",
    inventory_fingerprint: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    workspace: {name: "Example Workspace", description: "Example product workspace.", root: $workspace_root},
    repositories: [
      {
        id: "intent", name: "Product Requirements", role: "requirements",
        description: "Product behavior source of truth.",
        authority: ["product behavior", "acceptance criteria"], scope: ["product"], dependencies: [],
        source_path: $requirements_source, target_path: "02-product-requirements",
        materialization: "move", required: true, dirty: false, allow_dirty: false,
        remotes: {origin: "https://gitlab.com/example/requirements.git"}
      },
      {
        id: "implementation", name: "Backend", role: "implementation",
        description: "Backend runtime.", authority: ["backend runtime"], scope: ["product"], dependencies: ["intent"],
        source_path: "", target_path: "05-services/backend",
        materialization: "clone", required: true, dirty: false, allow_dirty: false,
        remotes: {origin: "https://bitbucket.org/example/backend.git"}
      }
    ],
    stages: [
      {id: "definition", repository: "intent", skill: "speckit-specify"},
      {id: "implementation", repository: "implementation", skill: "speckit-implement"}
    ],
    routing_notes: [
      "Requirements are authoritative for product behavior.",
      "Contracts must precede downstream interface changes."
    ],
    unresolved_questions: [], allow_update: false,
    approval: {confirmed: true, confirmed_at: "2026-07-14T00:00:00Z"}
  }' > "$proposal"

bash "$repo_root/scripts/orchestration/render-workspace-files.sh" \
  --proposal "$proposal" \
  --output-root "$output_root"

assert_file_exists "$output_root/config/repository-index.json"
assert_file_exists "$output_root/config/workspace.json"
assert_file_exists "$output_root/overlays/repository-index.md"
assert_file_exists "$output_root/WORKSPACE.md"

jq -e '.repositories.intent.target_path == "02-product-requirements"' "$output_root/config/repository-index.json" >/dev/null
jq -e '.repositories.intent.path == "../02-product-requirements"' "$output_root/config/workspace.json" >/dev/null
jq -e '.repositories.implementation.path == "../05-services/backend"' "$output_root/config/workspace.json" >/dev/null
jq -e '.stages[0].repository == "intent"' "$output_root/config/workspace.json" >/dev/null
jq -e '.initial_stage == "definition"' "$output_root/config/workspace.json" >/dev/null
assert_contains "$output_root/overlays/repository-index.md" "Source of truth"
assert_contains "$output_root/overlays/repository-index.md" "02-product-requirements"
assert_contains "$output_root/overlays/repository-index.md" "05-services/backend"
assert_contains "$output_root/WORKSPACE.md" "overlays/repository-index.md"
assert_contains "$output_root/WORKSPACE.md" "Requirements are authoritative for product behavior."
assert_contains "$output_root/WORKSPACE.md" "Contracts must precede downstream interface changes."

if rg -n -F "$tmp_dir" \
  "$output_root/config/repository-index.json" \
  "$output_root/config/workspace.json" \
  "$output_root/overlays/repository-index.md" \
  "$output_root/WORKSPACE.md"; then
  echo "generated portable files contain machine-local paths" >&2
  exit 1
fi
