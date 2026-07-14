# Ready-To-Use Three-Forge CI Design

## Goal

Ship self-contained CI configuration for GitHub, GitLab, and Bitbucket so a
fork or clone runs the same repository checks when it is pushed, without
repository-specific variables, secrets, includes, caches, or custom runners.

The three forge adapters must share the actual test entry point rather than
copying test lists that can drift.

## Scope

This change will:

- keep GitHub pull-request and `main` push checks;
- add GitLab merge-request and default-branch push checks;
- add Bitbucket pull-request and `main` push checks;
- run the same local shell test entry point on all three forges;
- install required operating-system packages inside GitLab and Bitbucket jobs;
- document all three CI definitions as upstream-owned template surfaces; and
- add regression coverage for CI wiring and trigger intent.

This change will not:

- publish artifacts or deploy anything;
- require credentials or forge API access;
- configure organization-level CI permissions, billing, or runner capacity;
- introduce custom container images or remote CI includes; or
- add schedules, manual pipelines, release jobs, or feature-branch push jobs.

## External Preconditions

The repository files are zero-config, but each hosting platform must permit its
CI product to run and must provide an eligible runner. A committed configuration
cannot override organization-level settings that disable GitHub Actions,
GitLab CI, or Bitbucket Pipelines.

Forks and clones are expected to retain `main` as the default branch. GitLab can
address its default branch dynamically through `CI_DEFAULT_BRANCH`; GitHub and
Bitbucket use the template's explicit `main` branch contract.

## Architecture

### Shared test entry point

Add `scripts/orchestration/run-ci-tests.sh` as the only CI test entry point.
The script will:

1. resolve the repository root from its own location;
2. require Bash, Git, `jq`, and `rg` with a clear missing-command error;
3. enumerate `tests/orchestration/test-*.sh` in stable shell-glob order;
4. fail if no tests are found;
5. print the test path before execution;
6. run each test with Bash and stop on the first failure; and
7. print the number of completed test files on success.

The glob intentionally includes the two `*-live.sh` integration tests. Those
tests use local fake `gh` and Codex executables and do not access hosted APIs.
Using the glob also means a future orchestration test automatically joins all
three pipelines.

### GitHub Actions adapter

Keep `.github/workflows/control-repo-ci.yml` with its existing triggers:

- every pull request; and
- pushes to `main`.

The job continues to use `ubuntu-latest`, checks out the repository, verifies
required commands, and invokes:

```bash
bash scripts/orchestration/run-ci-tests.sh
```

### GitLab CI adapter

Add `.gitlab-ci.yml` with one `test` stage and one orchestration-check job.
Use `workflow: rules` so pipelines exist only for:

- `CI_PIPELINE_SOURCE == "merge_request_event"`; and
- `CI_COMMIT_BRANCH == CI_DEFAULT_BRANCH`.

The job uses public image `ubuntu:24.04`, installs `git`, `jq`, and `ripgrep`
with `apt-get`, then calls the shared test entry point. No GitLab variables,
project includes, services, artifacts, or caches are required.

### Bitbucket Pipelines adapter

Add `bitbucket-pipelines.yml` with public image `ubuntu:24.04`. Define one
reusable YAML-anchored step that installs `git`, `jq`, and `ripgrep`, then calls
the shared test entry point.

Use that step for:

- `pull-requests: '**'`; and
- `branches: main`.

Do not define `default:` because that would run an additional pipeline for
every feature-branch push and duplicate pull-request coverage.

## Ownership And Documentation

The reusable upstream template owns all three forge adapters and the shared
runner. Update:

- `AGENTS.md`;
- `AI-INDEX.md`;
- `README.md`;
- `docs/runbooks/template-fork-contract.md`; and
- `tests/orchestration/test-template-agnostic.sh`.

Product forks may narrow CI behavior in fork-owned overlays only when their
hosting policy requires it. The upstream defaults remain credential-free and
product-agnostic.

## Testing Strategy

Add `tests/orchestration/test-ci-configs.sh` before the production
configurations. The initial test must fail because GitLab, Bitbucket, and the
shared runner do not exist.

The regression test will verify:

- all three CI files exist;
- all three invoke `scripts/orchestration/run-ci-tests.sh`;
- GitHub retains pull-request and `main` push triggers;
- GitLab contains merge-request and default-branch workflow rules;
- Bitbucket contains pull-request and `main` branch pipelines;
- GitLab and Bitbucket use `ubuntu:24.04` and install required packages;
- none of the adapters require credentials; and
- the GitHub workflow itself runs the CI-configuration regression test through
  the shared entry point.

Validation will include:

- Bash syntax checks for the shared runner and orchestration scripts;
- a red-green run of `test-ci-configs.sh`;
- a complete local run through `run-ci-tests.sh`;
- YAML parse checks for all three adapters;
- template-agnostic validation; and
- `git diff --check`.

## Failure Behavior

- Missing local commands fail before tests with the command name and corrective
  context.
- Package-install failures stop the forge job before repository tests.
- The first failing orchestration test stops the shared runner and preserves its
  output as the job failure evidence.
- A disabled CI product or unavailable runner remains visible as a forge-level
  setup condition; the repository does not silently bypass checks.

## Acceptance Criteria

1. A push to `main` runs the same shared test entry point on GitHub, GitLab, and
   Bitbucket.
2. A pull or merge request runs the same shared test entry point on all three
   forges.
3. Feature-branch pushes without a pull or merge request do not create a second
   CI pipeline.
4. No repository variables, credentials, remote includes, custom images, or
   custom runners are needed.
5. New `tests/orchestration/test-*.sh` files automatically run everywhere.
6. All local validation passes and the template remains product-agnostic.
