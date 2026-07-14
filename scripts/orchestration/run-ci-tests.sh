#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

for command_name in git jq rg; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "required CI command is unavailable: $command_name" >&2
    exit 1
  fi
done

test_files=("$repo_root"/tests/orchestration/test-*.sh)
if [[ ${#test_files[@]} -eq 0 || ! -f "${test_files[0]}" ]]; then
  echo "no orchestration tests found under tests/orchestration" >&2
  exit 1
fi

completed=0
for test_file in "${test_files[@]}"; do
  relative_path="${test_file#"$repo_root"/}"
  echo "==> $relative_path"
  bash "$test_file"
  completed=$((completed + 1))
done

echo "Completed $completed orchestration test files."
