<p align="center">
  <a href="https://www.dasmeta.com">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://a.storyblok.com/f/295271/424783ac50/dasmeta-wordmark-light.png">
      <source media="(prefers-color-scheme: light)" srcset="https://a.storyblok.com/f/295271/5938d2b888/dasmeta-wordmark-dark.png">
      <img src="https://a.storyblok.com/f/295271/5938d2b888/dasmeta-wordmark-dark.png" alt="Das Meta" width="220">
    </picture>
  </a>
</p>

<h1 align="center">Development Orchestrator</h1>

<p align="center">
  Coordinate multi-repository product delivery with explicit ownership,<br>
  staged workflows, and mergeability evidence.
</p>

<p align="center">
  <a href="https://github.com/dasmeta/development-orchestrator/actions/workflows/control-repo-ci.yml">
    <img src="https://github.com/dasmeta/development-orchestrator/actions/workflows/control-repo-ci.yml/badge.svg" alt="CI">
  </a>
</p>

<p align="center">
  <a href="#compose-a-product-workspace">Quick start</a> ·
  <a href="#mental-model">How it works</a> ·
  <a href="#documentation-map">Documentation</a>
</p>

## Overview

Development Orchestrator is a reusable control repository for a product's
multi-repository software workspace. Fork it once for a company, product, or
sub-product, then use the fork to discover related Git repositories, record
which repository owns each concern, and coordinate feature delivery across
them.

It is not a monorepo builder and it does not become the source of truth for
product behavior or implementation. Requirements, contracts, runtime code, and
executable validation stay in their owning repositories. This repository owns
the wiring between them: repository discovery, routing, feature state, stage
execution, handoffs, and mergeability evidence.

## When To Use It

Use this template when a product is delivered through several repositories and
people or AI agents need one reliable place to answer:

- Which repository owns product intent, interfaces, implementation, or tests?
- In what order should a cross-repository change happen?
- Which repositories are required on a new team member's machine?
- What changed when a repository was added, moved, renamed, or removed?
- Is a feature ready to advance or merge across its configured stages?

For a single repository with no cross-repository routing, this template is
usually unnecessary.

## Mental Model

Treat the product workspace as a dependency graph with explicit authority, not
as one mixed codebase.

| Concern | Authoritative home |
| --- | --- |
| Requirements and product intent | Configured `intent` repository or repositories |
| Shared APIs, schemas, and interfaces | Configured `contracts` repositories |
| Runtime behavior | Configured implementation repositories |
| Executable and end-to-end validation | Configured validation repositories |
| Repository routing, feature state, and merge gates | This orchestrator fork |

The default delivery order is:

```text
intent -> contracts when affected -> implementation -> validation
```

The actual repositories, dependencies, stages, and skills come from
`config/workspace.json`. A product may have several repositories in any
category, and its dependency graph does not need to be strictly linear.

## What A Product Fork Looks Like

After workspace composition, a product fork commonly looks like this:

```text
product-orchestrator/
├── 00-operations/
├── 01-governance/
├── 02-product-intent/
├── 03-interface-contracts/
├── 04-e2e-validation/
├── 05-service-api/
├── 05-web-ui/
├── config/
│   ├── repository-index.json
│   └── workspace.json
├── overlays/
│   └── repository-index.md
└── WORKSPACE.md
```

The numbered prefixes are a default classification, not a fixed list:

| Prefix | Repository category |
| --- | --- |
| `00-*` | Operations and managed-service packs |
| `01-*` | Infrastructure, technology, security, and other governance |
| `02-*` | Product requirements and other intent sources |
| `03-*` | Shared contracts and cross-repository interfaces |
| `04-*` | Executable validation and end-to-end tests |
| `05-*` | Backend, frontend, AI, infrastructure, and other implementations |

Several repositories may share a prefix. The workspace bootstrap workflow asks
before moving, linking, or cloning any repository.

## Choose Your Workflow

| Situation | Start here |
| --- | --- |
| Creating a product workspace | [Compose A Product Workspace](#compose-a-product-workspace) |
| Joining an existing product workspace | [New-Person Setup](#new-person-setup) |
| Refreshing the repository catalog | [Repository Refresh](#repository-refresh) |
| Delivering a feature | [Deliver A Feature](#deliver-a-feature) |
| Maintaining the reusable upstream template | [Template And Fork Ownership](#template-and-fork-ownership) |

## Prerequisites

Required for local workspace discovery and orchestration:

- Bash 3.2 or newer
- Git
- `jq`
- `rg`
- either `sha256sum` or `shasum`

The shell workflow is tested on macOS and Ubuntu Linux. On Windows, use WSL or
another Unix-compatible environment; native PowerShell execution is not
supported.

Choose one workspace-setup interface:

- Recommended: an agent runtime that discovers repository-local skills under
  `.agents/skills/` and can run `$workspace-bootstrap`.
- Manual: the deterministic commands and proposal process in the
  [workspace bootstrap runbook](docs/runbooks/workspace-bootstrap.md).

Optional feature-delivery integrations:

- Codex for `run-speckit-stage.sh`, which invokes a configured skill inside a
  child repository.
- GitHub CLI (`gh`) for collecting live GitHub pull-request state.

No package installation is required for the shell scripts themselves.

## Compose A Product Workspace

The recommended setup is agent-guided and has two separate phases: first build
a proposal, then apply only what the operator explicitly confirms.

### Create the product fork

Create a Git fork or product-owned copy of this template, then clone that fork:

```bash
git clone <product-orchestrator-fork-url> product-orchestrator
cd product-orchestrator
```

Keep the reusable template as an `upstream` remote when the forge did not add
one automatically:

```bash
git remote add upstream <development-orchestrator-template-url>
git fetch upstream
```

Do not add active product repositories or configuration to the reusable
template repository. Those belong only in the product fork.

### Start the guided workflow

Start an agent session with its working directory set to the product fork. The
runtime should discover `.agents/skills/workspace-bootstrap/SKILL.md`. Paste the
following prompt into that session; no separate skill installation is required.

Use `$workspace-bootstrap` with this prompt from a product fork:

```text
Use $workspace-bootstrap to inspect this orchestrator fork and nearby Git
repositories. Propose the 00-05 repository layout, ask me about anything
ambiguous, and do not move, clone, or link repositories until I confirm.
```

The skill starts with the fork and its parent directory. If it cannot find the
repositories, it asks where they are or which Git remotes should be used.

### Phase 1: discover and propose

This phase is read-only:

1. Discover local Git repositories and their remotes.
2. Read their `README.md`, `AGENTS.md`, and `AI-INDEX.md` files when present.
3. Classify operations, governance, intent, contracts, validation, and
   implementation repositories.
4. Record authority and dependencies.
5. Ask one question at a time for ambiguous locations, roles, or remotes.
6. Produce a validated proposal and deterministic dry-run.

Discovery recognizes GitHub, GitLab, Bitbucket, self-hosted Git, and local-only
remotes without requiring hosted-forge API access.

### Phase 2: confirm and apply

The operator reviews every proposed `move`, `symlink`, `clone`, and `keep`
operation. A real apply requires an approved proposal and confirmation of its
exact immutable token. Dirty repository moves require separate approval.

The apply process stops on unresolved questions, target collisions, mismatched
remotes, or unapproved changes to active workspace files. Completed moves and
links are rolled back when safe; the apply journal records any recovery that
still requires an operator.

See the [workspace bootstrap and reconciliation runbook](docs/runbooks/workspace-bootstrap.md)
for deterministic shell commands, proposal fields, confirmation, refresh, and
recovery.

### Successful bootstrap

A successful bootstrap leaves all required repositories at their confirmed
targets and produces:

| File | Purpose |
| --- | --- |
| `config/repository-index.json` | Portable catalog for onboarding and repository refresh |
| `config/workspace.json` | Active repository paths, stages, skills, and merge gates |
| `overlays/repository-index.md` | Human- and agent-readable repository navigation |
| `WORKSPACE.md` | Product-specific routing and workspace conventions |
| `workspace/bootstrap/<proposal-id>/apply-journal.json` | Local evidence of the apply result and recovery state |

The task is complete only when every configured target is a Git repository,
remotes match the approved proposal, generated files exist, and the apply
journal reports `complete`.

After apply, rediscover the workspace and require an empty delta:

```bash
bash scripts/orchestration/discover-workspace.sh \
  --search-root . \
  --workspace-root . \
  --output workspace/bootstrap/verification-inventory.json
bash scripts/orchestration/compare-workspace-inventory.sh \
  --inventory workspace/bootstrap/verification-inventory.json \
  --index config/repository-index.json \
  --workspace-root . \
  --output workspace/bootstrap/verification-delta.json
jq -e '.has_changes == false' workspace/bootstrap/verification-delta.json
jq -e '.status == "complete"' \
  workspace/bootstrap/<proposal-id>/apply-journal.json
```

Repeat `--search-root` during verification if confirmed repositories remain
outside the product fork. A failing `jq` command means setup is incomplete and
the delta or journal must be reviewed before continuing.

### Manual configuration

For a small, already-known topology, a product fork may be configured manually:

1. Copy `config/workspace.example.json` to `config/workspace.json`.
2. Replace example repository paths, roles, stages, skills, and merge gates.
3. Add product-specific routing rules to `WORKSPACE.md`.
4. Create and maintain `config/repository-index.json` and
   `overlays/repository-index.md` for onboarding and refresh.

Paths in `config/workspace.json` are resolved relative to the `config/`
directory. Prefer the guided workflow when repositories must be discovered or
filesystem operations are required.

## New-Person Setup

Joining an existing product workspace starts from the committed portable index:

1. Clone the product's orchestrator fork.
2. Run `$workspace-bootstrap` and ask it to set up the workspace for a new team
   member.
3. Let it discover repositories already present locally.
4. Review the delta against `config/repository-index.json`.
5. Confirm any proposed clones, links, or moves.
6. Rerun comparison and verify that required repositories are `present`.

The same index works across machines because it contains portable target paths
and remotes, not the original operator's absolute source paths.

Without a skill-aware agent runtime, follow the runbook's discovery, comparison,
proposal, dry-run, and confirmation commands manually. The same validation and
approval boundaries apply.

## Repository Refresh

Run `$workspace-bootstrap` in refresh mode when a repository is added, moved,
renamed, removed, or changes authority. Refresh reports:

- repositories present at their expected targets;
- repositories found at another location;
- required repositories missing locally;
- newly discovered but unindexed repositories; and
- remote mismatches.

Refresh produces a delta proposal. It never silently adopts or removes a
repository, and it requires a new dry-run and confirmation before updating the
catalog or active routing.

## Deliver A Feature

Workspace composition establishes the repository graph. Feature orchestration
then moves one change through that configured graph, one repository at a time.

### 1. Initialize feature state

```bash
bash scripts/orchestration/init-feature.sh \
  --feature-id FEAT-0001 \
  --title "Example product capability"
```

Review the generated intake and status files under `features/FEAT-0001/`, then
render the machine-readable manifest:

```bash
bash scripts/orchestration/render-manifest.sh features/FEAT-0001
```

### 2. Preview or run a configured stage

Always preview the target repository and skill before live execution:

```bash
bash scripts/orchestration/run-speckit-stage.sh \
  --feature-dir features/FEAT-0001 \
  --stage definition \
  --dry-run
```

Without `--dry-run`, the stage runner invokes Codex inside the configured child
repository. Follow that repository's local instructions and do not invent
missing upstream intent or contracts.

### 3. Collect delivery state and advance

For a fixture-backed local demonstration:

```bash
bash scripts/orchestration/collect-github-state.sh \
  --feature-dir features/FEAT-0001 \
  --fixtures tests/fixtures/github
bash scripts/orchestration/advance-stage.sh features/FEAT-0001
bash scripts/orchestration/evaluate-mergeability.sh features/FEAT-0001
```

For a live GitHub pull request:

```bash
bash scripts/orchestration/collect-github-state.sh \
  --feature-dir features/FEAT-0001 \
  --repo <owner/repository> \
  --pr-number <number>
```

See the [development orchestration runbook](docs/runbooks/development-orchestration.md)
for stage execution, state collection, and configuration resolution.

## Forge Support

Workspace discovery is forge-agnostic. It derives evidence from local Git
repositories and remote URLs and supports GitHub, GitLab, Bitbucket,
self-hosted Git, and local-only repositories.

Live pull-request state collection is currently GitHub-specific through
`collect-github-state.sh` and `gh`. Product forks using another forge can still
use discovery, indexing, routing, and stage execution, but need a compatible
state collector before claiming equivalent live mergeability evidence.

## Safety And Authority

- Discovery and comparison are read-only.
- No repository is moved, cloned, linked, added, or removed without explicit
  confirmation.
- Dirty moves, collisions, remote mismatches, and incomplete recovery stop the
  workflow.
- Read across repositories for context; write only in the explicitly targeted
  repository.
- Do not silently edit several repositories in one pass.
- Do not infer product behavior from implementation when an intent source
  exists.
- Do not define shared contracts only inside an implementation repository.
- Do not claim end-to-end completion without the relevant validation evidence
  unless the operator explicitly accepts the gap.

Root execution rules are defined in [AGENTS.md](AGENTS.md). Product forks may
narrow them through their generated `WORKSPACE.md` and child-repository
instructions.

## Configuration Resolution

Most feature-orchestration commands accept `--config <path>`. Configuration is
resolved in this order:

1. explicit `--config <path>`;
2. fork-owned `config/workspace.json`; and
3. upstream `config/workspace.example.json` for template examples, demos, and
   tests.

The portable repository catalog is broader than stage routing: it should list
all known product repositories, including governance, operations, and optional
implementations that are not part of the default execution path.

## Template And Fork Ownership

The upstream repository owns generic orchestration machinery. Product forks
own product-specific configuration and child repositories.

| Upstream template owns | Product fork owns |
| --- | --- |
| Root instructions and navigation | `WORKSPACE.md` |
| Scripts, schemas, tests, and CI | `config/workspace.json` |
| Generic templates and runbooks | `config/repository-index.json` |
| `config/workspace.example.json` | Root `00-*` through `05-*` repositories |
| Reusable agent skills | `workspace/` and `overlays/` |

Do not add product names, behavior, or active child repositories to the reusable
upstream template. See the complete
[template/fork contract](docs/runbooks/template-fork-contract.md) before syncing
upstream changes into a product fork.

## Validate The Template

Run the complete local orchestration suite:

```bash
bash scripts/orchestration/run-ci-tests.sh
```

The suite uses temporary Git fixtures and requires no hosted-forge access.
GitHub, GitLab, and Bitbucket invoke this same command for pull or merge
requests and pushes to the default `main` branch. The committed forge adapters
need no repository variables, credentials, remote includes, or custom runners.
The hosting organization must still permit its CI product and provide an
eligible runner.

## Documentation Map

| Document | Use it for |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Root execution, routing, authority, and stop rules |
| [AI-INDEX.md](AI-INDEX.md) | Agent-oriented navigation across root surfaces and generated outputs |
| [Workspace bootstrap runbook](docs/runbooks/workspace-bootstrap.md) | Initial bootstrap, onboarding, refresh, approval, and recovery |
| [Development orchestration runbook](docs/runbooks/development-orchestration.md) | Feature initialization, stage execution, state, and mergeability |
| [Template/fork contract](docs/runbooks/template-fork-contract.md) | Upstream ownership, fork ownership, and safe synchronization |
| [Requirements-to-UI handoff](docs/runbooks/requirements-to-ui-handoff.md) | Translating approved product intent into bounded UI implementation guidance |
| [TODO.md](TODO.md) | Known gaps and planned adapters |

---

<p align="center">
  Maintained by <a href="https://github.com/dasmeta">DasMeta</a> ·
  <a href="../../issues">Issues and support</a> ·
  <a href="#documentation-map">Documentation</a>
</p>
