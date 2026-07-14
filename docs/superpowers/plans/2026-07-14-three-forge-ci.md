# Three-Forge CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide ready-to-use GitHub, GitLab, and Bitbucket CI configurations that run one shared, credential-free orchestration test suite on pull or merge requests and default-branch pushes.

**Architecture:** A repository-local Bash runner owns test discovery and execution. GitHub Actions, GitLab CI, and Bitbucket Pipelines remain thin forge adapters that install any missing operating-system tools and invoke that runner with equivalent triggers.

**Tech Stack:** Bash 3.2+, Git, `jq`, `rg`, GitHub Actions YAML, GitLab CI YAML, Bitbucket Pipelines YAML, Ubuntu runner images

---

## File Map

- Create `scripts/orchestration/run-ci-tests.sh`: canonical test discovery,
  dependency checks, execution, and summary.
- Create `.gitlab-ci.yml`: GitLab merge-request and default-branch adapter.
- Create `bitbucket-pipelines.yml`: Bitbucket pull-request and `main` adapter.
- Create `tests/orchestration/test-ci-configs.sh`: cross-forge CI contract test.
- Modify `.github/workflows/control-repo-ci.yml`: replace the copied test list
  with the shared runner.
- Modify `AGENTS.md`: register GitLab and Bitbucket CI as upstream-owned.
- Modify `AI-INDEX.md`: expose the three CI adapters and shared validation
  command.
- Modify `README.md`: document ready-to-use CI behavior and the shared local
  command.
- Modify `docs/runbooks/template-fork-contract.md`: extend upstream ownership.
- Modify `tests/orchestration/test-template-agnostic.sh`: scan both new root CI
  files for product-specific content.

### Task 1: Write The Cross-Forge CI Contract Test

**Files:**
- Create: `tests/orchestration/test-ci-configs.sh`

- [ ] **Step 1: Add the failing CI contract test**

Create `tests/orchestration/test-ci-configs.sh` with:

```bash
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
```

- [ ] **Step 2: Verify the test fails for the missing runner**

Run:

```bash
bash tests/orchestration/test-ci-configs.sh
```

Expected: exit `1` with `expected file to exist` for
`scripts/orchestration/run-ci-tests.sh`.

### Task 2: Add The Shared Runner And Three Forge Adapters

**Files:**
- Create: `scripts/orchestration/run-ci-tests.sh`
- Create: `.gitlab-ci.yml`
- Create: `bitbucket-pipelines.yml`
- Modify: `.github/workflows/control-repo-ci.yml`
- Test: `tests/orchestration/test-ci-configs.sh`

- [ ] **Step 1: Add the shared CI test runner**

Create `scripts/orchestration/run-ci-tests.sh` with:

```bash
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
```

Make it executable:

```bash
chmod +x scripts/orchestration/run-ci-tests.sh
```

- [ ] **Step 2: Replace the GitHub test list with the shared runner**

Replace `.github/workflows/control-repo-ci.yml` with:

```yaml
name: control-repo-ci

on:
  pull_request:
  push:
    branches:
      - main

jobs:
  shell-tests:
    runs-on: ubuntu-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Verify required tools
        run: |
          git --version
          jq --version
          rg --version

      - name: Run orchestration shell tests
        run: bash scripts/orchestration/run-ci-tests.sh
```

- [ ] **Step 3: Add the GitLab adapter**

Create `.gitlab-ci.yml` with:

```yaml
stages:
  - test

workflow:
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'

orchestration-tests:
  stage: test
  image: ubuntu:24.04
  before_script:
    - apt-get update
    - apt-get install -y --no-install-recommends git jq ripgrep ca-certificates
  script:
    - bash scripts/orchestration/run-ci-tests.sh
```

- [ ] **Step 4: Add the Bitbucket adapter**

Create `bitbucket-pipelines.yml` with:

```yaml
image: ubuntu:24.04

definitions:
  steps:
    - step: &orchestration-tests
        name: Orchestration shell tests
        script:
          - apt-get update
          - apt-get install -y --no-install-recommends git jq ripgrep ca-certificates
          - bash scripts/orchestration/run-ci-tests.sh

pipelines:
  pull-requests:
    '**':
      - step: *orchestration-tests
  branches:
    main:
      - step: *orchestration-tests
```

- [ ] **Step 5: Verify the focused CI contract passes**

Run:

```bash
bash tests/orchestration/test-ci-configs.sh
```

Expected: exit `0` with no error output.

- [ ] **Step 6: Run the shared test entry point**

Run:

```bash
bash scripts/orchestration/run-ci-tests.sh
```

Expected: every `tests/orchestration/test-*.sh` file is printed and executed,
ending with a completed-file count.

- [ ] **Step 7: Commit the shared runner and forge adapters**

```bash
git add \
  scripts/orchestration/run-ci-tests.sh \
  .github/workflows/control-repo-ci.yml \
  .gitlab-ci.yml \
  bitbucket-pipelines.yml \
  tests/orchestration/test-ci-configs.sh
git commit -m "ci: add shared checks for three forges"
```

### Task 3: Register CI Ownership And Usage

**Files:**
- Modify: `tests/orchestration/test-ci-configs.sh`
- Modify: `AGENTS.md`
- Modify: `AI-INDEX.md`
- Modify: `README.md`
- Modify: `docs/runbooks/template-fork-contract.md`
- Modify: `tests/orchestration/test-template-agnostic.sh`

- [ ] **Step 1: Add failing documentation and ownership assertions**

Append to `tests/orchestration/test-ci-configs.sh`:

```bash
assert_contains "$repo_root/AGENTS.md" ".gitlab-ci.yml"
assert_contains "$repo_root/AGENTS.md" "bitbucket-pipelines.yml"
assert_contains "$repo_root/AI-INDEX.md" ".gitlab-ci.yml"
assert_contains "$repo_root/AI-INDEX.md" "bitbucket-pipelines.yml"
assert_contains "$repo_root/README.md" "GitHub, GitLab, and Bitbucket"
assert_contains "$repo_root/README.md" "run-ci-tests.sh"
assert_contains "$repo_root/docs/runbooks/template-fork-contract.md" ".gitlab-ci.yml"
assert_contains "$repo_root/docs/runbooks/template-fork-contract.md" "bitbucket-pipelines.yml"
```

- [ ] **Step 2: Verify the new assertions fail**

Run:

```bash
bash tests/orchestration/test-ci-configs.sh
```

Expected: exit `1` because `AGENTS.md` does not yet contain `.gitlab-ci.yml`.

- [ ] **Step 3: Extend upstream ownership rules**

In `AGENTS.md`, add `.gitlab-ci.yml` and `bitbucket-pipelines.yml` to the
upstream-owned path sentence in `Template Fork Contract`.

In `docs/runbooks/template-fork-contract.md`, add these entries under
`Upstream-Owned Paths`:

```markdown
- `.gitlab-ci.yml`
- `bitbucket-pipelines.yml`
```

- [ ] **Step 4: Update root navigation and validation guidance**

In `AI-INDEX.md`, add this Root-Owned Surfaces row:

```markdown
| `.github/workflows/control-repo-ci.yml`, `.gitlab-ci.yml`, `bitbucket-pipelines.yml` | Ready-to-use forge adapters that invoke the shared orchestration test runner. |
```

Replace the enumerated validation commands with:

```bash
bash scripts/orchestration/run-ci-tests.sh
```

In the README `Validate The Template` section, replace the test loop with:

```bash
bash scripts/orchestration/run-ci-tests.sh
```

Then state:

```markdown
GitHub, GitLab, and Bitbucket invoke this same command for pull or merge
requests and pushes to the default `main` branch. The committed forge adapters
need no repository variables, credentials, remote includes, or custom runners.
The hosting organization must still permit its CI product and provide an
eligible runner.
```

- [ ] **Step 5: Extend template-agnostic scanning to root CI files**

Add these paths to the `rg` input list in
`tests/orchestration/test-template-agnostic.sh`:

```bash
  "$repo_root/.gitlab-ci.yml" \
  "$repo_root/bitbucket-pipelines.yml" \
```

- [ ] **Step 6: Verify focused documentation and conformance checks**

Run:

```bash
bash tests/orchestration/test-ci-configs.sh
bash tests/orchestration/test-template-agnostic.sh
```

Expected: both commands exit `0` with no error output.

- [ ] **Step 7: Commit ownership and documentation**

```bash
git add \
  AGENTS.md \
  AI-INDEX.md \
  README.md \
  docs/runbooks/template-fork-contract.md \
  tests/orchestration/test-ci-configs.sh \
  tests/orchestration/test-template-agnostic.sh
git commit -m "docs: document three-forge CI defaults"
```

### Task 4: Validate And Publish

**Files:**
- Verify all files changed by Tasks 1-3

- [ ] **Step 1: Parse all YAML configurations**

Run:

```bash
ruby -e 'require "yaml"; ARGV.each { |path| YAML.load_file(path); puts "parsed #{path}" }' \
  .github/workflows/control-repo-ci.yml \
  .gitlab-ci.yml \
  bitbucket-pipelines.yml
```

Expected: one `parsed ...` line for each configuration and exit `0`.

- [ ] **Step 2: Run Bash syntax validation**

Run:

```bash
for script in scripts/orchestration/*.sh scripts/orchestration/lib/*.sh; do
  bash -n "$script"
done
```

Expected: exit `0` with no output.

- [ ] **Step 3: Run the exact shared CI suite**

Run:

```bash
bash scripts/orchestration/run-ci-tests.sh
```

Expected: all orchestration tests pass and the final completed count matches
the number of `tests/orchestration/test-*.sh` files.

- [ ] **Step 4: Check patch integrity and repository state**

Run:

```bash
git diff --check
git status --short --branch
```

Expected: no whitespace errors and only intentional commits ahead of
`origin/main`.

- [ ] **Step 5: Refresh the remote and verify a fast-forward push**

Run:

```bash
git fetch origin
git rev-list --left-right --count origin/main...main
```

Expected: the left count is `0`; `main` contains only local commits ahead of
`origin/main`.

- [ ] **Step 6: Push the completed implementation**

Run:

```bash
git push origin main
```

Expected: `main -> main` succeeds.

- [ ] **Step 7: Verify local and remote main match**

Run:

```bash
git status --short --branch
git rev-parse HEAD
git rev-parse origin/main
```

Expected: clean `main`, no ahead/behind marker, and identical hashes.
