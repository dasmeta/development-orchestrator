#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "$*" >&2
  exit 1
}

init_repository() {
  local path="$1"
  git init -q "$path"
  git -C "$path" config user.name "Quality Test"
  git -C "$path" config user.email "quality@example.invalid"
}

mkdir -p "$tmp_dir/config" "$tmp_dir/features/FEAT-0001"
init_repository "$tmp_dir/implementation"

printf 'base\n' > "$tmp_dir/implementation/a.txt"
git -C "$tmp_dir/implementation" add a.txt
git -C "$tmp_dir/implementation" commit -qm "base"
base_oid="$(git -C "$tmp_dir/implementation" rev-parse HEAD)"

printf 'changed\n' > "$tmp_dir/implementation/a.txt"
printf 'second\n' > "$tmp_dir/implementation/z.txt"
git -C "$tmp_dir/implementation" add a.txt z.txt
git -C "$tmp_dir/implementation" commit -qm "candidate"
candidate_oid="$(git -C "$tmp_dir/implementation" rev-parse HEAD)"

cp "$repo_root/templates/features/scope.json" \
  "$tmp_dir/features/FEAT-0001/scope.json"
sed -i.bak 's/{{FEATURE_ID}}/FEAT-0001/g' \
  "$tmp_dir/features/FEAT-0001/scope.json"
rm "$tmp_dir/features/FEAT-0001/scope.json.bak"

cat > "$tmp_dir/config/workspace.json" <<'JSON'
{
  "repositories": {
    "implementation": {
      "path": "../implementation",
      "role": "implementation"
    }
  }
}
JSON

capture() {
  bash "$repo_root/scripts/orchestration/capture-feature-scope.sh" \
    --feature-dir "$tmp_dir/features/FEAT-0001" \
    --config "$tmp_dir/config/workspace.json" \
    --repository implementation \
    --base "$base_oid" \
    --head "$1" \
    --now "2026-08-13T00:00:00Z"
}

capture "$candidate_oid"
scope_path="$tmp_dir/features/FEAT-0001/scope.json"
jq -e --arg subject "commit:$candidate_oid" \
  '.repositories == [{
    id: "implementation",
    role: "implementation",
    subject: $subject,
    base: $base,
    head: $head,
    changed_paths: ["a.txt", "z.txt"],
    dependencies: [],
    captured_at: "2026-08-13T00:00:00Z"
  }]' --arg base "$base_oid" --arg head "$candidate_oid" \
  "$scope_path" >/dev/null

jq 'del(.repositories[].captured_at)' "$scope_path" > "$tmp_dir/committed-first.json"
capture "$candidate_oid"
jq 'del(.repositories[].captured_at)' "$scope_path" > "$tmp_dir/committed-second.json"
cmp "$tmp_dir/committed-first.json" "$tmp_dir/committed-second.json"

printf 'dirty\n' >> "$tmp_dir/implementation/a.txt"
printf 'untracked-one\n' > "$tmp_dir/implementation/m.txt"
capture WORKTREE
first_worktree_subject="$(jq -r '.repositories[0].subject' "$scope_path")"
[[ "$first_worktree_subject" == worktree:* ]] || \
  fail "expected worktree subject, got $first_worktree_subject"
jq -e '.repositories[0].changed_paths == ["a.txt", "m.txt", "z.txt"]' \
  "$scope_path" >/dev/null

jq 'del(.repositories[].captured_at)' "$scope_path" > "$tmp_dir/worktree-first.json"
capture WORKTREE
jq 'del(.repositories[].captured_at)' "$scope_path" > "$tmp_dir/worktree-second.json"
cmp "$tmp_dir/worktree-first.json" "$tmp_dir/worktree-second.json"

printf 'untracked-two\n' > "$tmp_dir/implementation/m.txt"
capture WORKTREE
second_worktree_subject="$(jq -r '.repositories[0].subject' "$scope_path")"
[[ "$first_worktree_subject" != "$second_worktree_subject" ]] || \
  fail "untracked content must change the worktree digest"

jq -e '.repositories | map(.id) == (map(.id) | sort)' "$scope_path" >/dev/null
