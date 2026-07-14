# Workspace Bootstrap And Repository Reconciliation Design

## Purpose

Extend the development orchestration template so a product or company fork can
be composed from an existing collection of local Git repositories before
feature-delivery orchestration begins.

The workflow must help an LLM and operator discover repositories, classify their
ownership and dependencies, propose a numbered product-workspace layout, obtain
explicit approval, materialize that layout, and maintain a repository index for
future onboarding and repository changes.

This adds a workspace-composition phase before the existing feature-delivery
phase. It does not move product behavior, contracts, runtime implementation, or
validation truth into the upstream template.

## Goals

- Discover local Git repositories without assuming GitHub as the forge.
- Recognize GitHub, GitLab, Bitbucket, self-hosted, and local-only remotes.
- Let an LLM inspect repository guidance and propose classifications.
- Ask the operator when repository locations, roles, authority, or operations
  are ambiguous.
- Separate discovery and proposal from filesystem mutation.
- Require explicit confirmation before moving, linking, cloning, or adopting a
  repository.
- Default to a consistent `00-*` through `05-*` taxonomy while permitting
  approved exceptions.
- Produce a portable repository catalog for new-person setup and later refresh.
- Preserve an auditable local record of discovery and apply operations.
- Keep repository setup repeatable and safe to rerun.

## Non-Goals

- Automatically approve repository classifications.
- Search hosted forge organizations in the first version.
- Store forge credentials or automate authentication.
- Modify child-repository content, history, branches, or remotes.
- Replace product requirements, contracts, tests, or child `AGENTS.md` files.
- Make probabilistic LLM output an executable source of truth without schema
  validation and operator approval.

## Default Workspace Taxonomy

The bootstrap skill proposes this taxonomy by default:

| Prefix | Default repository category |
| --- | --- |
| `00-*` | Operations and managed-service operating packs |
| `01-*` | Infrastructure, technology, security, and other governance |
| `02-*` | Product requirements and other product-intent sources |
| `03-*` | Shared contracts and cross-repository interfaces |
| `04-*` | Executable validation and end-to-end tests |
| `05-*` | Backend, frontend, AI, infrastructure, and other implementation repositories |

The proposal may contain several repositories in any category. A product fork
may approve a different prefix or role when this taxonomy does not fit.

## Architecture

### LLM Bootstrap Skill

Add `.agents/skills/workspace-bootstrap/SKILL.md` as the operator-facing entry
point. The skill:

1. Establishes the target product/company/sub-product scope.
2. Runs local discovery against likely roots or roots supplied by the operator.
3. Reads repository `README.md`, `AGENTS.md`, `AI-INDEX.md`, remote metadata,
   and other lightweight navigation signals.
4. Classifies repositories by role, authority, scope, and dependency direction.
5. Creates a proposal conforming to the workspace-proposal schema.
6. Surfaces unresolved questions one at a time to the operator.
7. Shows the exact materialization and generated-file delta.
8. Records explicit approval in the proposal.
9. Runs validation and apply actions.
10. Verifies the resulting workspace and reports remaining gaps.

The skill does not silently choose locations or perform filesystem mutations.

### Deterministic Shell Actions

Add shell entry points under `scripts/orchestration/` for these responsibilities:

1. **Discovery**
   - Scan supplied roots for Git repositories.
   - Exclude the target orchestrator and common generated directories.
   - Record absolute discovery paths only in local bootstrap state.
   - Capture repository name, branch, clean/dirty state, remotes, inferred forge
     host, and the presence of repository navigation files.
   - Never mutate discovered repositories.

2. **Proposal validation**
   - Validate required proposal structure and allowed operations.
   - Require a unique repository ID and target path for every selected repo.
   - Require role, authority, dependencies, materialization method, and remote
     data where cloning is proposed.
   - Reject unresolved questions, path traversal, collisions, stale inventory,
     and unapproved dirty-repository operations.

3. **Apply and reconciliation**
   - Support `--dry-run` without mutation.
   - Require an approval token tied to the validated proposal.
   - Preflight all operations before the first mutation.
   - Materialize each repository using `move`, `symlink`, `clone`, or `keep`.
   - Treat an already-correct target as successfully configured.
   - Generate the active workspace configuration and indexes only after
     repository operations succeed.
   - Write an apply journal before execution and update it after each operation.
   - Attempt to reverse completed moves after a later failure and preserve the
     journal when recovery is incomplete.

The implementation may expose these responsibilities as separate scripts or a
single command with subcommands, provided each boundary remains independently
testable.

## Discovery And Proposal Flow

```text
local search roots
    -> deterministic Git inventory
    -> LLM inspection and classification
    -> workspace proposal
    -> operator questions for ambiguity
    -> exact dry-run delta
    -> operator approval
    -> deterministic validation
    -> apply
    -> workspace verification
```

Discovery is local-first. Remote URLs are evidence and portable setup inputs,
not a reason to query a hosted forge automatically. When a repository cannot be
found locally and has no known remote, the workflow asks the operator where it
is. When a remote exists but the repository is absent, cloning is proposed and
requires approval.

## Proposal Model

The proposal records:

- proposal ID and inventory fingerprint;
- target workspace root;
- lifecycle state such as `draft`, `needs-input`, `ready`, or `approved`;
- unresolved operator questions;
- repositories selected for the workspace;
- each repository's stable ID, role, authority, scope, dependencies, source
  location, target path, remotes, and proposed materialization method;
- explicit exceptions such as approval to move a dirty repository;
- files that will be generated or updated;
- approval token and approval timestamp after confirmation.

Absolute source paths are local execution data and must not be copied into the
committed repository catalog.

## Repository Index And Generated Surfaces

Product forks maintain these committed generated artifacts:

1. `config/repository-index.json`
   - Portable machine-readable catalog.
   - Includes target path, role, authority, scope, dependencies, remote URLs,
     required/optional status, and setup hints.
   - Covers all known workspace repositories, not only default delivery stages.

2. `overlays/repository-index.md`
   - Human- and LLM-readable navigation index generated from the catalog.
   - Explains sources of truth, upstream/downstream relationships, and local
     paths.

3. `config/workspace.json`
   - Remains the executable routing and stage configuration.
   - Is generated or updated from the approved subset and stage choices in the
     proposal.

4. `WORKSPACE.md`
   - Remains the product-specific overlay.
   - Points agents to the generated repository index and records product-level
     routing rules that are not generic template behavior.

Machine-specific inventories, absolute paths, and apply journals stay under
`workspace/bootstrap/` in the product fork.

## Ongoing Modes

### Initial Bootstrap

When no repository index exists, discovery and classification produce a complete
proposal. Approved apply operations organize repositories and create the
catalog, overlay index, workspace configuration, and workspace overlay.

### New-Person Setup

When a repository index exists, setup compares required indexed repositories
with the local workspace. Missing repositories produce a proposal to clone from
the declared remote, link an existing local checkout, or use an operator-supplied
location. The user confirms the proposal before setup. Re-running setup leaves
correct repositories unchanged.

### Repository Refresh

Refresh re-scans configured local roots and compares discovered repositories,
current targets, remotes, and metadata with the committed index. It reports:

- newly discovered but unindexed repositories;
- indexed repositories missing locally;
- repositories found at unexpected paths;
- remote mismatches;
- changed navigation or ownership signals;
- configuration/index drift.

Refresh creates a delta proposal. No addition, removal, move, clone, or index
change occurs before operator approval.

## Safety And Failure Handling

- Refuse target-path collisions and path traversal.
- Refuse missing or mismatched repositories.
- Require separate recorded approval for dirty repository moves.
- Never delete repositories, branches, history, or remotes.
- Never persist credentials in configuration, indexes, proposals, or logs.
- Validate every operation before applying any operation.
- Use temporary generated files and install them only after repository
  materialization succeeds.
- Journal original and target paths before moves.
- Attempt best-effort rollback of completed moves after later failure.
- Stop with a recovery report when automatic rollback cannot restore the prior
  layout.
- Preserve existing active configuration unless the approved proposal explicitly
  describes its update.
- Treat inaccessible search roots, ambiguous roles, missing remotes, and unclear
  authority as `needs-input`, not as guessed values.

## Testing Strategy

Shell tests create temporary local Git repositories and require no network.
Fixtures cover GitHub, GitLab, Bitbucket, self-hosted, and local-only remotes.

Required behavior tests include:

- discovery and forge-agnostic remote capture;
- exclusion of the orchestrator and generated directories;
- clean and dirty repository detection;
- proposal schema and semantic validation;
- unresolved-question rejection;
- dry-run immutability;
- approval-token enforcement;
- move, symlink, local clone, and keep operations;
- dirty-repository confirmation;
- target collision and remote mismatch failures;
- repeatable new-person setup;
- refresh delta generation;
- portable JSON index generation;
- Markdown index generation;
- configuration and overlay generation;
- apply journaling and partial-failure reporting;
- existing template conformance and orchestration regression tests.

The new shell tests are added to the existing control-repository CI workflow.

## Documentation And Navigation

Update the upstream README and `AI-INDEX.md` to introduce workspace composition
as the phase before feature delivery. Add a runbook covering initial bootstrap,
new-person setup, refresh, approval, recovery, and the boundary between the
LLM-guided skill and deterministic scripts.

The upstream template must not track generated product-specific configuration,
numbered repositories, `WORKSPACE.md`, `workspace/`, or `overlays/`. Existing
template conformance rules continue to enforce that boundary.

## Success Criteria

- A fresh product fork can inventory local repositories and produce a proposal
  without mutating them.
- The workflow asks the operator about ambiguous or missing information.
- A proposal cannot be applied without schema validation and explicit approval.
- Approved repositories can be organized into the default numbered taxonomy.
- A portable committed index enables a new team member to reproduce repository
  setup after confirmation.
- Refresh detects and proposes new or changed repositories without silently
  adopting them.
- Existing orchestration commands and template conformance tests continue to
  pass.
