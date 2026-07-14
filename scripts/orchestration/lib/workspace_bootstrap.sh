#!/usr/bin/env bash

set -euo pipefail

sha256_stream() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

absolute_path() {
  local path="$1"
  (cd "$path" 2>/dev/null && pwd -P)
}

remote_host() {
  local url="$1"

  case "$url" in
    file://*|/*|./*|../*)
      printf 'local\n'
      ;;
    *@*:*)
      printf '%s\n' "$url" | sed -E 's#^[^@]+@([^:]+):.*#\1#'
      ;;
    *://*)
      printf '%s\n' "$url" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^/@]+@)?([^/:]+).*#\2#'
      ;;
    *)
      printf 'unknown\n'
      ;;
  esac
}

proposal_token() {
  local proposal_path="$1"
  jq -S -c 'del(.approval)' "$proposal_path" | sha256_stream
}

is_safe_workspace_target() {
  local target_path="$1"
  [[ "$target_path" =~ ^(00|01|02|03|04|05)-[^/]+(/[^/]+)*$ ]] &&
    [[ "$target_path" != *".."* ]] &&
    [[ "$target_path" != /* ]]
}
