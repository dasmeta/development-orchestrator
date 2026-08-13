#!/usr/bin/env bash

set -euo pipefail

stdin_digest() {
  git -C "$control_repo_root" hash-object --stdin | sed 's/^/git-blob:/'
}

git_commit_oid() {
  git -C "$1" rev-parse --verify "$2^{commit}"
}

git_commit_subject() {
  local repository_path="$1"
  local revision="$2"

  printf 'commit:%s\n' "$(git_commit_oid "$repository_path" "$revision")"
}

git_worktree_subject() {
  local repository_path="$1"
  local head_oid
  local diff_digest
  local untracked_records
  local canonical_subject
  local path
  local blob_digest

  head_oid="$(git_commit_oid "$repository_path" HEAD)"
  diff_digest="$({
    git -C "$repository_path" diff \
      --binary --no-ext-diff --no-textconv HEAD --
  } | stdin_digest)"
  untracked_records="$(mktemp)"

  while IFS= read -r -d '' path; do
    blob_digest="git-blob:$(git -C "$repository_path" \
      hash-object --no-filters -- "$path")"
    jq -cn --arg path "$path" --arg blob_digest "$blob_digest" \
      '{path: $path, blob_digest: $blob_digest}' >> "$untracked_records"
  done < <(git -C "$repository_path" ls-files \
    --others --exclude-standard -z)

  canonical_subject="$(
    jq -csS \
      --arg head "$head_oid" \
      --arg binary_diff_digest "$diff_digest" \
      '{
        head: $head,
        binary_diff_digest: $binary_diff_digest,
        untracked: (sort_by(.path))
      }' "$untracked_records"
  )"
  rm -f "$untracked_records"

  printf 'worktree:%s\n' "$(printf '%s' "$canonical_subject" | stdin_digest)"
}

git_changed_paths_json() {
  local repository_path="$1"
  local base_revision="$2"
  local head_revision="$3"
  local path_records
  local path

  path_records="$(mktemp)"
  if [[ "$head_revision" == "WORKTREE" ]]; then
    while IFS= read -r -d '' path; do
      jq -cn --arg path "$path" '$path' >> "$path_records"
    done < <(git -C "$repository_path" diff \
      --name-only --no-renames -z "$base_revision" --)
    while IFS= read -r -d '' path; do
      jq -cn --arg path "$path" '$path' >> "$path_records"
    done < <(git -C "$repository_path" ls-files \
      --others --exclude-standard -z)
  else
    while IFS= read -r -d '' path; do
      jq -cn --arg path "$path" '$path' >> "$path_records"
    done < <(git -C "$repository_path" diff \
      --name-only --no-renames -z "$base_revision" "$head_revision" --)
  fi

  jq -sc 'unique | sort' "$path_records"
  rm -f "$path_records"
}
