---
name: workspace-bootstrap
description: Discover, classify, organize, onboard, and reconcile repositories in a product/company/sub-product development-orchestrator fork. Use when creating a product workspace from local Git repositories, setting up the workspace for a new person, adding or relocating repositories, refreshing repository indexes, or validating that requirements, contracts, validation, governance, infrastructure, frontend, backend, and AI repositories are routed correctly.
---

# Workspace Bootstrap

Compose and maintain a product-aware multi-repository workspace while keeping
discovery and proposal generation separate from confirmed filesystem changes.

## Non-Negotiable Safety Rules

- Read child repositories during discovery; do not edit them.
- Do not silently move, clone, link, add, or remove repositories.
- Ask one question at a time when information is missing or ambiguous.
- Keep the proposal in `needs-input` until every question is answered.
- Show a deterministic `--dry-run` before requesting approval.
- Require explicit confirmation of the exact proposal token before apply.
- Ask separately before moving dirty repositories.
- Never store forge credentials in proposals, indexes, or journals.
- Stop on target collisions, remote mismatches, unclear authority, or incomplete
  rollback evidence.

## Select The Mode

### Initial bootstrap

Use when a product fork has no `config/repository-index.json`. Discover local
repositories, classify them, propose the numbered topology, ask for approval,
then organize the workspace and generate its indexes.

### New-person setup

Use when a committed repository index exists but required repositories are
missing locally. Compare the local inventory with the index, propose cloning
from declared remotes or linking/moving operator-supplied local checkouts, and
apply only after confirmation.

### Repository refresh

Use when a repository is added, moved, renamed, removed, or changes authority.
Discover again, compare with the committed index, and propose only the delta.
Do not adopt or remove a repository automatically.

## Workflow

1. Read root `AGENTS.md`. If `WORKSPACE.md` exists, read it next.
2. Determine the mode from the presence of `config/repository-index.json` and
   the operator's request.
3. Identify likely local search roots. Start with the workspace root and its
   parent. If repositories cannot be found, ask the operator where they are.
4. Run local-first discovery:

   ```bash
   bash scripts/orchestration/discover-workspace.sh \
     --search-root <local-root> \
     --workspace-root <orchestrator-fork> \
     --output workspace/bootstrap/inventory.json
   ```

5. Treat remote URLs as forge-agnostic evidence. Support GitHub, GitLab,
   Bitbucket, self-hosted Git, and local-only repositories. Do not query a
   hosted forge in this version.
6. When `config/repository-index.json` exists, compare it with discovery:

   ```bash
   bash scripts/orchestration/compare-workspace-inventory.sh \
     --inventory workspace/bootstrap/inventory.json \
     --index config/repository-index.json \
     --workspace-root . \
     --output workspace/bootstrap/delta.json
   ```

7. Inspect each candidate's `README.md`, `AGENTS.md`, `AI-INDEX.md`, Git remotes,
   and obvious repository structure. Do not infer product truth from
   implementation when a requirements source exists.
8. Classify candidates using the default taxonomy, allowing several repos per
   category:

   - `00-*`: operations and managed-service packs
   - `01-*`: infrastructure, technology, security, and other governance
   - `02-*`: product requirements and product-intent sources
   - `03-*`: shared contracts and cross-repository interfaces
   - `04-*`: executable validation and end-to-end tests
   - `05-*`: backend, frontend, AI, infrastructure, and other implementations

9. Record authority and dependencies as a graph, not only as a linear stage
   list. Requirements may depend on governance; contracts depend on approved
   requirements; implementations depend on requirements and affected contracts;
   validation depends on the upstream truth it verifies.
10. Draft a proposal conforming to
    `schemas/workspace-proposal.schema.json`. Include source paths only in this
    local proposal. Keep portable target paths and remotes for generated indexes.
11. If a location, role, dependency, authority, materialization choice, or
    remote is uncertain, set status to `needs-input`, record the question, and
    ask the operator one question at a time. Revalidate after every answer.
12. Prefer moving existing repositories into the orchestrator fork for a clean
    layout, but ask first. Offer `symlink` when the operator wants the existing
    location preserved. Offer `clone` for an approved missing repository with a
    known remote. Use `keep` only when already at the final target.
13. Validate and preview:

    ```bash
    bash scripts/orchestration/validate-workspace-proposal.sh \
      --proposal workspace/bootstrap/proposal.json
    bash scripts/orchestration/apply-workspace-proposal.sh \
      --proposal workspace/bootstrap/proposal.json \
      --dry-run
    ```

14. Present the exact operation/source/target list. Call out dirty repositories,
    clones, symlinks, moves, config updates, and index changes.
15. Ask for explicit confirmation. Only after the operator confirms, set the
    proposal status to `approved`, set `approval.confirmed` to `true`, and record
    the confirmation time.
16. Print the proposal-specific token:

    ```bash
    bash scripts/orchestration/apply-workspace-proposal.sh \
      --proposal workspace/bootstrap/proposal.json \
      --print-token
    ```

17. Show the token and ask the operator to confirm it. Apply only after that
    confirmation:

    ```bash
    bash scripts/orchestration/apply-workspace-proposal.sh \
      --proposal workspace/bootstrap/proposal.json \
      --confirm <token>
    ```

18. Verify every configured target is a Git repository, remotes match the
    approved proposal, the apply journal is `complete`, and these committed
    product-fork surfaces exist:

    - `config/repository-index.json`
    - `config/workspace.json`
    - `overlays/repository-index.md`
    - `WORKSPACE.md`

19. Report repositories that remain missing, optional, ambiguous, dirty, or in
    recovery. Do not claim setup complete while the journal says
    `recovery_required`.

## Proposal Guidance

- Use stable role IDs such as `intent`, `contracts`, `validation`, `backend`,
  `frontend`, `infrastructure`, or a product-specific unambiguous ID.
- Keep `config/repository-index.json` portable: no absolute source paths.
- Include all known repositories in the repository index, even when they are not
  assigned to a default execution stage.
- Keep `config/workspace.json` focused on executable routing and stages.
- Regenerate `overlays/repository-index.md`; do not hand-edit it after apply.

## Stop Conditions

Stop and ask the operator when:

- the product/company/sub-product boundary is unclear;
- repositories cannot be located locally and no remote is known;
- several repositories appear authoritative for the same concern;
- a dirty repository is proposed for moving;
- a target path already contains a different repository;
- an existing remote differs from the proposal;
- applying would overwrite active fork configuration without approved
  `allow_update`;
- the apply journal reports incomplete recovery.
