#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"
source "$repo_root/tests/helpers/git-fixtures.sh"

tmp_dir="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp_dir"; exit $status' EXIT

search_root="$tmp_dir/search"
workspace_root="$search_root/orchestrator"
inventory="$tmp_dir/inventory.json"

create_git_repo "$workspace_root"
create_git_repo "$search_root/requirements" "git@github.com:example/requirements.git"
create_git_repo "$search_root/contracts" "https://gitlab.com/example/contracts.git"
create_git_repo "$search_root/e2e" "ssh://git@bitbucket.org/example/e2e.git"
create_git_repo "$search_root/backend" "https://git.example.test/example/backend.git"
create_git_repo "$search_root/dirty"
create_git_repo "$search_root/node_modules/ignored" "https://github.com/example/ignored.git"
printf 'uncommitted\n' >> "$search_root/dirty/README.md"

bash "$repo_root/scripts/orchestration/discover-workspace.sh" \
  --search-root "$search_root" \
  --workspace-root "$workspace_root" \
  --output "$inventory"

assert_file_exists "$inventory"
jq -e '.schema_version == 1' "$inventory" >/dev/null
jq -e '.repositories | length == 5' "$inventory" >/dev/null
jq -e '.repositories[] | select(.name == "requirements") | .forge == "github.com"' "$inventory" >/dev/null
jq -e '.repositories[] | select(.name == "contracts") | .forge == "gitlab.com"' "$inventory" >/dev/null
jq -e '.repositories[] | select(.name == "e2e") | .forge == "bitbucket.org"' "$inventory" >/dev/null
jq -e '.repositories[] | select(.name == "backend") | .forge == "git.example.test"' "$inventory" >/dev/null
jq -e '.repositories[] | select(.name == "dirty") | .dirty == true and .forge == "local"' "$inventory" >/dev/null
jq -e '.repositories | all(.name != "orchestrator" and .name != "ignored")' "$inventory" >/dev/null
jq -e '.repositories[] | select(.name == "requirements") | .signals.readme == true' "$inventory" >/dev/null
jq -e '.fingerprint | test("^[a-f0-9]{64}$")' "$inventory" >/dev/null
