# Product Workspace Bootstrap And Reconciliation

Use this runbook after copying or forking the orchestration template for a
company, product, or sub-product. Workspace composition happens before feature
delivery: discover repositories, review a proposed topology, explicitly approve
filesystem operations, then generate the portable repository indexes.

Use the `workspace-bootstrap` skill as the operator-facing workflow. The shell
commands below provide deterministic evidence and mutation boundaries.

## Default Layout

| Prefix | Category |
| --- | --- |
| `00-*` | Operations and managed-service packs |
| `01-*` | Infrastructure, technology, security, and other governance |
| `02-*` | Product requirements and other intent sources |
| `03-*` | Shared contracts and cross-repository interfaces |
| `04-*` | Executable validation and end-to-end tests |
| `05-*` | Backend, frontend, AI, infrastructure, and other implementations |

Several repositories may share a prefix. The approved proposal may use a
different classification when this default does not fit.

## Initial Bootstrap

1. Discover local Git repositories. Repeat `--search-root` when repositories are
   spread across several locations.

   ```bash
   bash scripts/orchestration/discover-workspace.sh \
     --search-root .. \
     --workspace-root . \
     --output workspace/bootstrap/inventory.json
   ```

   Discovery is local-first and read-only. Remote detection is forge-agnostic:
   GitHub, GitLab, Bitbucket, self-hosted Git, and local-only repositories are
   supported without hosted API access.

2. Inspect the inventory and repository navigation files. Draft
   `workspace/bootstrap/proposal.json` using
   `schemas/workspace-proposal.schema.json`.
3. Keep the proposal in `needs-input` and ask one question at a time until
   locations, roles, authority, dependencies, targets, and materialization
   choices are unambiguous.
4. Validate and preview without mutation:

   ```bash
   bash scripts/orchestration/validate-workspace-proposal.sh \
     --proposal workspace/bootstrap/proposal.json
   bash scripts/orchestration/apply-workspace-proposal.sh \
     --proposal workspace/bootstrap/proposal.json \
     --dry-run
   ```

5. Review every `move`, `symlink`, `clone`, and `keep` operation. Confirm dirty
   repository moves separately.
6. After approval, set the proposal to `approved`, record approval, print its
   immutable confirmation token, and ask the operator to confirm that token:

   ```bash
   bash scripts/orchestration/apply-workspace-proposal.sh \
     --proposal workspace/bootstrap/proposal.json \
     --print-token
   ```

7. Apply using the confirmed token:

   ```bash
   bash scripts/orchestration/apply-workspace-proposal.sh \
     --proposal workspace/bootstrap/proposal.json \
     --confirm <token>
   ```

## Generated Repository Indexes

Successful apply produces:

- `config/repository-index.json`: portable catalog for onboarding and refresh;
- `overlays/repository-index.md`: human/LLM repository navigation;
- `config/workspace.json`: executable repository and stage routing;
- `WORKSPACE.md`: product-specific workspace overlay.

The repository index includes governance, operations, requirements, contracts,
validation, infrastructure, and every implementation repository, even when a
repository is not selected as a default execution stage.

## New-Person Setup

1. Clone or copy the product orchestrator fork.
2. Discover any existing local repositories.
3. Compare them with the committed catalog:

   ```bash
   bash scripts/orchestration/compare-workspace-inventory.sh \
     --inventory workspace/bootstrap/inventory.json \
     --index config/repository-index.json \
     --workspace-root . \
     --output workspace/bootstrap/delta.json
   ```

4. For each required missing repository, propose a clone from its indexed
   remote or ask for an existing local location. Show dry-run and obtain explicit
   confirmation before setup.
5. Rerun comparison after apply. Correctly positioned repositories appear in
   `present`; repeat setup does not disturb them.

## Repository Refresh

Run discovery and comparison when repositories are added, renamed, relocated,
removed, or change authority. Review `present`, `misplaced`, `missing`,
`unindexed`, and `remote_mismatches` in the delta.

Create a delta proposal for the intended changes. Do not silently add or remove
repositories. Use `allow_update: true` only after reviewing changes to active
`config/workspace.json`, `config/repository-index.json`, `WORKSPACE.md`, and the
Markdown index. Dry-run and confirmation remain mandatory.

## Recovery

Every real apply writes:

```text
workspace/bootstrap/<proposal-id>/apply-journal.json
```

`complete` means materialization and generated-file verification succeeded.
`rolled_back` means an operation failed and completed moves/links were restored.
`recovery_required` means some state could not be restored automatically.

When recovery is required:

1. Stop; do not rerun apply immediately.
2. Read the failed repository and operation states in the journal.
3. Verify original and target paths before moving anything manually.
4. Preserve cloned repositories until the operator decides whether to keep or
   remove them.
5. Correct the proposal or filesystem state, rerun `--dry-run`, and request a
   fresh confirmation token before another apply.

## Safety Summary

- Discovery and comparison are read-only.
- Dry-run creates no workspace state.
- Real apply requires proposal validation and an exact confirmation token.
- Dirty moves, collisions, mismatched remotes, unresolved questions, and
  unapproved active-file updates stop execution.
- Child-repository content, Git history, branches, and remotes are never edited.
