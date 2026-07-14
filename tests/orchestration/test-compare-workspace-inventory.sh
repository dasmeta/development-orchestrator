#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp_dir"; exit $status' EXIT

workspace_root="$tmp_dir/workspace"
inventory="$tmp_dir/inventory.json"
index="$tmp_dir/repository-index.json"
delta="$tmp_dir/delta.json"

mkdir -p "$workspace_root/02-product-requirements" "$tmp_dir/elsewhere/contracts" "$tmp_dir/elsewhere/e2e"
workspace_root="$(cd "$workspace_root" && pwd -P)"

jq -n '{
  schema_version: 1,
  workspace: {name: "Example", description: "Example workspace"},
  repositories: {
    intent: {
      id: "intent", name: "Requirements", role: "requirements", description: "Requirements",
      authority: ["behavior"], scope: ["product"], dependencies: [], target_path: "02-product-requirements",
      required: true, remotes: {origin: "https://gitlab.com/example/requirements.git"}
    },
    contracts: {
      id: "contracts", name: "Contracts", role: "contracts", description: "Contracts",
      authority: ["interfaces"], scope: ["product"], dependencies: ["intent"], target_path: "03-interface-contracts",
      required: true, remotes: {origin: "git@github.com:example/contracts.git"}
    },
    backend: {
      id: "backend", name: "Backend", role: "implementation", description: "Backend",
      authority: ["runtime"], scope: ["product"], dependencies: ["intent", "contracts"], target_path: "05-services/backend",
      required: true, remotes: {origin: "https://bitbucket.org/example/backend.git"}
    }
  },
  stages: []
}' > "$index"

jq -n \
  --arg intent_path "$workspace_root/02-product-requirements" \
  --arg contracts_path "$tmp_dir/elsewhere/contracts" \
  --arg e2e_path "$tmp_dir/elsewhere/e2e" \
  '{
    schema_version: 1,
    fingerprint: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    repositories: [
      {name: "requirements", path: $intent_path, remotes: {origin: "https://gitlab.com/example/requirements.git"}},
      {name: "contracts", path: $contracts_path, remotes: {origin: "git@github.com:example/contracts.git"}},
      {name: "e2e", path: $e2e_path, remotes: {origin: "https://git.example.test/example/e2e.git"}}
    ]
  }' > "$inventory"

bash "$repo_root/scripts/orchestration/compare-workspace-inventory.sh" \
  --inventory "$inventory" \
  --index "$index" \
  --workspace-root "$workspace_root" \
  --output "$delta"

assert_file_exists "$delta"
jq -e '.present == ["intent"]' "$delta" >/dev/null
jq -e '.misplaced[0].id == "contracts"' "$delta" >/dev/null
jq -e '.missing[0].id == "backend"' "$delta" >/dev/null
jq -e '.unindexed[0].name == "e2e"' "$delta" >/dev/null
jq -e '.remote_mismatches | length == 0' "$delta" >/dev/null
jq -e '.has_changes == true' "$delta" >/dev/null

exact_inventory="$tmp_dir/exact-inventory.json"
exact_delta="$tmp_dir/exact-delta.json"
jq -n \
  --arg intent_path "$workspace_root/02-product-requirements" \
  --arg contracts_path "$workspace_root/03-interface-contracts" \
  --arg backend_path "$workspace_root/05-services/backend" \
  '{
    schema_version: 1,
    fingerprint: "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    repositories: [
      {name: "requirements", path: $intent_path, remotes: {origin: "https://gitlab.com/example/requirements.git"}},
      {name: "contracts", path: $contracts_path, remotes: {origin: "git@github.com:example/contracts.git"}},
      {name: "backend", path: $backend_path, remotes: {origin: "https://bitbucket.org/example/backend.git"}}
    ]
  }' > "$exact_inventory"

bash "$repo_root/scripts/orchestration/compare-workspace-inventory.sh" \
  --inventory "$exact_inventory" \
  --index "$index" \
  --workspace-root "$workspace_root" \
  --output "$exact_delta"

jq -e '.present == ["backend", "contracts", "intent"]' "$exact_delta" >/dev/null
jq -e '.has_changes == false' "$exact_delta" >/dev/null
