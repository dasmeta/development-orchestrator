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

git_subject_diff() {
  local repository_path="$1"
  local base_oid="$2"
  local head_oid="$3"
  local subject="$4"
  local current_subject
  local path
  local diff_status

  git_commit_oid "$repository_path" "$base_oid" >/dev/null
  git_commit_oid "$repository_path" "$head_oid" >/dev/null

  case "$subject" in
    commit:*)
      if [[ "$subject" != "commit:$head_oid" ]]; then
        echo "captured commit subject does not match its head" >&2
        return 1
      fi
      git -C "$repository_path" diff \
        --binary --no-ext-diff --no-textconv "$base_oid" "$head_oid" --
      ;;
    worktree:*)
      current_subject="$(git_worktree_subject "$repository_path")"
      if [[ "$current_subject" != "$subject" ]]; then
        echo "captured worktree subject is stale" >&2
        return 1
      fi
      git -C "$repository_path" diff \
        --binary --no-ext-diff --no-textconv "$base_oid" --
      while IFS= read -r -d '' path; do
        printf '\n# Untracked file: %s\n' "$path"
        diff_status=0
        git -C "$repository_path" diff --no-index \
          --binary --no-ext-diff --no-textconv -- /dev/null "$path" || \
          diff_status=$?
        if [[ $diff_status -ne 1 ]]; then
          echo "failed to render untracked file diff: $path" >&2
          return 1
        fi
      done < <(git -C "$repository_path" ls-files \
        --others --exclude-standard -z)
      ;;
    *)
      echo "unsupported captured subject: $subject" >&2
      return 1
      ;;
  esac
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
