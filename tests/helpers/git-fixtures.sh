#!/usr/bin/env bash

set -euo pipefail

create_git_repo() {
  local path="$1"
  local remote_url="${2:-}"

  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.email test@example.test
  git -C "$path" config user.name "Test User"
  printf '# %s\n' "$(basename "$path")" > "$path/README.md"
  git -C "$path" add README.md
  git -C "$path" commit -qm "initial"

  if [[ -n "$remote_url" ]]; then
    git -C "$path" remote add origin "$remote_url"
  fi
}
