#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp_dir"; exit $status' EXIT

validator="$repo_root/scripts/orchestration/validate-workspace-proposal.sh"
proposal="$tmp_dir/proposal.json"

mkdir -p "$tmp_dir/workspace" "$tmp_dir/requirements"

jq -n \
  --arg workspace_root "$tmp_dir/workspace" \
  --arg requirements_source "$tmp_dir/requirements" \
  '{
    schema_version: 1,
    proposal_id: "bootstrap-001",
    status: "approved",
    inventory_fingerprint: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    workspace: {
      name: "Example Workspace",
      description: "Example product workspace",
      root: $workspace_root
    },
    repositories: [
      {
        id: "intent",
        name: "Product Requirements",
        role: "requirements",
        description: "Product behavior source of truth.",
        authority: ["product behavior", "acceptance criteria"],
        scope: ["product"],
        dependencies: [],
        source_path: $requirements_source,
        target_path: "02-product-requirements",
        materialization: "move",
        required: true,
        dirty: false,
        allow_dirty: false,
        remotes: {origin: "https://gitlab.com/example/requirements.git"}
      },
      {
        id: "implementation",
        name: "Backend",
        role: "implementation",
        description: "Backend runtime.",
        authority: ["backend runtime"],
        scope: ["product"],
        dependencies: ["intent"],
        source_path: "",
        target_path: "05-services/backend",
        materialization: "clone",
        required: true,
        dirty: false,
        allow_dirty: false,
        remotes: {origin: "https://bitbucket.org/example/backend.git"}
      }
    ],
    stages: [
      {id: "definition", repository: "intent", skill: "speckit-specify"},
      {id: "implementation", repository: "implementation", skill: "speckit-implement"}
    ],
    routing_notes: ["Requirements are authoritative for product behavior."],
    unresolved_questions: [],
    allow_update: false,
    approval: {confirmed: true, confirmed_at: "2026-07-14T00:00:00Z"}
  }' > "$proposal"

bash "$validator" --proposal "$proposal"
token="$(bash "$validator" --proposal "$proposal" --print-token)"
[[ "$token" =~ ^[a-f0-9]{64}$ ]]

assert_file_exists "$repo_root/schemas/workspace-proposal.schema.json"
assert_file_exists "$repo_root/schemas/repository-index.schema.json"

expect_invalid() {
  local name="$1"
  local filter="$2"
  local invalid="$tmp_dir/$name.json"

  jq "$filter" "$proposal" > "$invalid"
  if bash "$validator" --proposal "$invalid" >"$tmp_dir/$name.out" 2>&1; then
    echo "expected invalid proposal to fail: $name" >&2
    exit 1
  fi
}

expect_invalid duplicate_id '.repositories[1].id = .repositories[0].id'
expect_invalid duplicate_target '.repositories[1].target_path = .repositories[0].target_path'
expect_invalid traversal_target '.repositories[0].target_path = "02-product-requirements/../escape"'
expect_invalid unknown_dependency '.repositories[1].dependencies = ["missing"]'
expect_invalid unknown_stage_repository '.stages[0].repository = "missing"'
expect_invalid clone_without_origin '.repositories[1].remotes = {}'
expect_invalid unresolved_questions '.unresolved_questions = ["Where is validation?"]'
expect_invalid dirty_without_approval '.repositories[0].dirty = true | .repositories[0].allow_dirty = false'
