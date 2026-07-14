#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
source "$script_dir/lib/workspace_bootstrap.sh"

proposal_path=""
print_token=false

fail() {
  echo "invalid workspace proposal: $1" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposal)
      proposal_path="$2"
      shift 2
      ;;
    --print-token)
      print_token=true
      shift
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

[[ -n "$proposal_path" ]] || fail "--proposal is required"
[[ -f "$proposal_path" ]] || fail "proposal file does not exist: $proposal_path"
require_command jq

jq -e . "$proposal_path" >/dev/null 2>&1 || fail "proposal is not valid JSON"

jq -e '
  .schema_version == 1 and
  (.proposal_id | type == "string" and length > 0) and
  (.status | IN("draft", "needs-input", "ready", "approved")) and
  (.inventory_fingerprint | test("^[a-f0-9]{64}$")) and
  (.workspace | type == "object") and
  (.workspace.name | type == "string" and length > 0) and
  (.workspace.description | type == "string" and length > 0) and
  (.workspace.root | type == "string" and length > 0) and
  (.repositories | type == "array" and length > 0) and
  (.stages | type == "array") and
  (.routing_notes | type == "array") and
  (.unresolved_questions | type == "array") and
  (.allow_update | type == "boolean") and
  (.approval.confirmed | type == "boolean") and
  (.approval.confirmed_at | type == "string")
' "$proposal_path" >/dev/null || fail "required top-level fields are missing or invalid"

jq -e '
  all(.repositories[];
    (.id | test("^[a-z][a-z0-9_]*$")) and
    (.name | type == "string" and length > 0) and
    (.role | type == "string" and length > 0) and
    (.description | type == "string" and length > 0) and
    (.authority | type == "array") and
    (.scope | type == "array") and
    (.dependencies | type == "array") and
    (.source_path | type == "string") and
    (.target_path | type == "string") and
    (.target_path | test("^(00|01|02|03|04|05)-[^/]+(/[^/]+)*$") and (contains("..") | not)) and
    (.materialization | IN("move", "symlink", "clone", "keep")) and
    (.required | type == "boolean") and
    (.dirty | type == "boolean") and
    (.allow_dirty | type == "boolean") and
    (.remotes | type == "object")
  )
' "$proposal_path" >/dev/null || fail "repository entries are missing required fields"

jq -e '(.repositories | map(.id) | length) == (.repositories | map(.id) | unique | length)' "$proposal_path" >/dev/null || fail "repository IDs must be unique"
jq -e '(.repositories | map(.target_path) | length) == (.repositories | map(.target_path) | unique | length)' "$proposal_path" >/dev/null || fail "repository target paths must be unique"
jq -e '(.repositories | map(.id)) as $ids | ([.repositories[].dependencies[]] - $ids | length) == 0' "$proposal_path" >/dev/null || fail "dependencies must reference configured repository IDs"
jq -e '(.repositories | map(.id)) as $ids | ([.stages[].repository] - $ids | length) == 0' "$proposal_path" >/dev/null || fail "stages must reference configured repository IDs"
jq -e 'all(.repositories[]; . as $repo | if $repo.materialization == "clone" then ($repo.remotes.origin | type == "string" and length > 0) else true end)' "$proposal_path" >/dev/null || fail "clone repositories require remotes.origin"
jq -e 'all(.repositories[]; . as $repo | if ($repo.materialization == "move" or $repo.materialization == "symlink") then ($repo.source_path | length > 0) else true end)' "$proposal_path" >/dev/null || fail "move and symlink repositories require source_path"
jq -e 'all(.repositories[]; . as $repo | if $repo.materialization == "keep" then ($repo.source_path | endswith($repo.target_path)) else true end)' "$proposal_path" >/dev/null || fail "keep repositories must already be at their target path"
jq -e 'all(.repositories[]; . as $repo | if ($repo.materialization == "move" and $repo.dirty) then $repo.allow_dirty else true end)' "$proposal_path" >/dev/null || fail "dirty repository moves require allow_dirty"
jq -e '.unresolved_questions | length == 0' "$proposal_path" >/dev/null || fail "unresolved questions must be answered before validation"

if [[ "$print_token" == true ]]; then
  proposal_token "$proposal_path"
fi
