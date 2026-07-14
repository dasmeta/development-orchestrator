#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"
source "$repo_root/tests/helpers/git-fixtures.sh"

tmp_dir="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp_dir"; exit $status' EXIT

apply_script="$repo_root/scripts/orchestration/apply-workspace-proposal.sh"
workspace_root="$tmp_dir/workspace"
proposal="$tmp_dir/proposal.json"

mkdir -p "$workspace_root/01-governance" "$tmp_dir/remotes"
create_git_repo "$tmp_dir/sources/requirements" "https://gitlab.com/example/requirements.git"
create_git_repo "$tmp_dir/sources/contracts" "git@github.com:example/contracts.git"
create_git_repo "$workspace_root/01-governance" "https://git.example.test/example/governance.git"
create_git_repo "$tmp_dir/backend-seed"
git clone --bare -q "$tmp_dir/backend-seed" "$tmp_dir/remotes/backend.git"

jq -n \
  --arg workspace_root "$workspace_root" \
  --arg requirements_source "$tmp_dir/sources/requirements" \
  --arg contracts_source "$tmp_dir/sources/contracts" \
  --arg governance_source "$workspace_root/01-governance" \
  --arg backend_remote "$tmp_dir/remotes/backend.git" \
  '{
    schema_version: 1,
    proposal_id: "bootstrap-apply",
    status: "approved",
    inventory_fingerprint: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    workspace: {name: "Applied Workspace", description: "Applied product workspace.", root: $workspace_root},
    repositories: [
      {
        id: "governance", name: "Governance", role: "governance", description: "Governance source.",
        authority: ["governance"], scope: ["product"], dependencies: [], source_path: $governance_source,
        target_path: "01-governance", materialization: "keep", required: true, dirty: false, allow_dirty: false,
        remotes: {origin: "https://git.example.test/example/governance.git"}
      },
      {
        id: "intent", name: "Requirements", role: "requirements", description: "Product behavior.",
        authority: ["behavior"], scope: ["product"], dependencies: ["governance"], source_path: $requirements_source,
        target_path: "02-product-requirements", materialization: "move", required: true, dirty: false, allow_dirty: false,
        remotes: {origin: "https://gitlab.com/example/requirements.git"}
      },
      {
        id: "contracts", name: "Contracts", role: "contracts", description: "Shared interfaces.",
        authority: ["interfaces"], scope: ["product"], dependencies: ["intent"], source_path: $contracts_source,
        target_path: "03-shared-contracts", materialization: "symlink", required: true, dirty: false, allow_dirty: false,
        remotes: {origin: "git@github.com:example/contracts.git"}
      },
      {
        id: "backend", name: "Backend", role: "implementation", description: "Backend runtime.",
        authority: ["runtime"], scope: ["product"], dependencies: ["intent", "contracts"], source_path: "",
        target_path: "05-services/backend", materialization: "clone", required: true, dirty: false, allow_dirty: false,
        remotes: {origin: $backend_remote}
      }
    ],
    stages: [
      {id: "definition", repository: "intent", skill: "speckit-specify"},
      {id: "implementation", repository: "backend", skill: "speckit-implement"}
    ],
    routing_notes: ["Use requirements before implementation."],
    unresolved_questions: [], allow_update: false,
    approval: {confirmed: true, confirmed_at: "2026-07-14T00:00:00Z"}
  }' > "$proposal"

bash "$apply_script" --proposal "$proposal" --dry-run > "$tmp_dir/dry-run.out"
assert_contains "$tmp_dir/dry-run.out" $'move\tintent'
assert_contains "$tmp_dir/dry-run.out" $'symlink\tcontracts'
assert_contains "$tmp_dir/dry-run.out" $'clone\tbackend'
[[ -d "$tmp_dir/sources/requirements/.git" ]]
[[ ! -e "$workspace_root/02-product-requirements" ]]
[[ ! -e "$workspace_root/03-shared-contracts" ]]
[[ ! -e "$workspace_root/05-services/backend" ]]
[[ ! -e "$workspace_root/config/workspace.json" ]]
[[ ! -e "$workspace_root/workspace/bootstrap" ]]

if bash "$apply_script" --proposal "$proposal" >"$tmp_dir/no-confirm.out" 2>&1; then
  echo "apply unexpectedly succeeded without confirmation" >&2
  exit 1
fi

if bash "$apply_script" --proposal "$proposal" --confirm "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" >"$tmp_dir/wrong-confirm.out" 2>&1; then
  echo "apply unexpectedly accepted the wrong confirmation token" >&2
  exit 1
fi

token="$(bash "$apply_script" --proposal "$proposal" --print-token)"
bash "$apply_script" --proposal "$proposal" --confirm "$token"

[[ ! -e "$tmp_dir/sources/requirements" ]]
git -C "$workspace_root/02-product-requirements" rev-parse --git-dir >/dev/null
[[ -L "$workspace_root/03-shared-contracts" ]]
git -C "$workspace_root/03-shared-contracts" rev-parse --git-dir >/dev/null
git -C "$workspace_root/05-services/backend" rev-parse --git-dir >/dev/null
git -C "$workspace_root/01-governance" rev-parse --git-dir >/dev/null
assert_file_exists "$workspace_root/config/repository-index.json"
assert_file_exists "$workspace_root/config/workspace.json"
assert_file_exists "$workspace_root/overlays/repository-index.md"
assert_file_exists "$workspace_root/WORKSPACE.md"
jq -e '.status == "complete"' "$workspace_root/workspace/bootstrap/bootstrap-apply/apply-journal.json" >/dev/null

# Reapplying an already-correct proposal is safe even though the moved source is gone.
bash "$apply_script" --proposal "$proposal" --confirm "$token"
jq -e '.status == "complete"' "$workspace_root/workspace/bootstrap/bootstrap-apply/apply-journal.json" >/dev/null

expect_apply_failure() {
  local name="$1"
  local invalid_proposal="$2"
  local invalid_token
  invalid_token="$(bash "$apply_script" --proposal "$invalid_proposal" --print-token 2>/dev/null || true)"
  if [[ -n "$invalid_token" ]] && bash "$apply_script" --proposal "$invalid_proposal" --confirm "$invalid_token" >"$tmp_dir/$name.out" 2>&1; then
    echo "expected apply failure: $name" >&2
    exit 1
  fi
}

collision_proposal="$tmp_dir/collision.json"
jq '.proposal_id = "collision" | .repositories[1].target_path = "02-collision" | .repositories[1].source_path = "'"$tmp_dir"'/sources/collision"' "$proposal" > "$collision_proposal"
mkdir -p "$workspace_root/02-collision"
expect_apply_failure collision "$collision_proposal"

dirty_source="$tmp_dir/sources/dirty"
create_git_repo "$dirty_source"
printf 'dirty\n' >> "$dirty_source/README.md"
dirty_proposal="$tmp_dir/dirty.json"
jq --arg source "$dirty_source" '
  .proposal_id = "dirty" |
  .repositories[1].source_path = $source |
  .repositories[1].target_path = "02-dirty" |
  .repositories[1].dirty = true |
  .repositories[1].allow_dirty = false
' "$proposal" > "$dirty_proposal"
expect_apply_failure dirty "$dirty_proposal"

mismatch_target="$workspace_root/05-mismatch"
create_git_repo "$mismatch_target" "https://example.test/wrong.git"
mismatch_proposal="$tmp_dir/mismatch.json"
jq '
  .proposal_id = "mismatch" |
  .repositories[3].target_path = "05-mismatch" |
  .repositories[3].remotes.origin = "https://example.test/expected.git"
' "$proposal" > "$mismatch_proposal"
expect_apply_failure remote_mismatch "$mismatch_proposal"

unresolved_proposal="$tmp_dir/unresolved.json"
jq '.proposal_id = "unresolved" | .unresolved_questions = ["Where is validation?"]' "$proposal" > "$unresolved_proposal"
expect_apply_failure unresolved "$unresolved_proposal"
