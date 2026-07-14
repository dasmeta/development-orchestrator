#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

runner="$repo_root/scripts/orchestration/run-ci-tests.sh"
github_ci="$repo_root/.github/workflows/control-repo-ci.yml"
gitlab_ci="$repo_root/.gitlab-ci.yml"
bitbucket_ci="$repo_root/bitbucket-pipelines.yml"

assert_file_exists "$runner"
assert_file_exists "$github_ci"
assert_file_exists "$gitlab_ci"
assert_file_exists "$bitbucket_ci"

for ci_file in "$github_ci" "$gitlab_ci" "$bitbucket_ci"; do
  assert_contains "$ci_file" "bash scripts/orchestration/run-ci-tests.sh"
done

assert_contains "$github_ci" "pull_request:"
assert_contains "$github_ci" "push:"
assert_contains "$github_ci" "- main"

assert_contains "$gitlab_ci" 'CI_PIPELINE_SOURCE == "merge_request_event"'
assert_contains "$gitlab_ci" 'CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
assert_contains "$gitlab_ci" "ubuntu:24.04"
assert_contains "$gitlab_ci" "git jq ripgrep"

assert_contains "$bitbucket_ci" "pull-requests:"
assert_contains "$bitbucket_ci" "'**':"
assert_contains "$bitbucket_ci" "branches:"
assert_contains "$bitbucket_ci" "main:"
assert_contains "$bitbucket_ci" "ubuntu:24.04"
assert_contains "$bitbucket_ci" "git jq ripgrep"

if rg -n '(TOKEN|PASSWORD|SECRET|PRIVATE_KEY)' \
  "$github_ci" "$gitlab_ci" "$bitbucket_ci"; then
  echo "CI adapters must not require credentials" >&2
  exit 1
fi
