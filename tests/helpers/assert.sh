#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "$*" >&2
  exit 1
}

assert_equals() {
  [[ "$1" == "$2" ]] || fail "expected '$1', got '$2'"
}

assert_directory_exists() {
  [[ -d "$1" ]] || fail "missing directory: $1"
}

assert_command_fails() {
  if "$@"; then
    fail "unexpected pass: $*"
  fi
}

assert_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    fail "expected file to exist: $path"
  fi
}

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$file"; then
    fail "expected '$expected' in $file"
  fi
}
