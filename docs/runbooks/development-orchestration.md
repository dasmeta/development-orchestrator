# Development Orchestration Runbook

Use the root control repository to initialize and track feature delivery across
configured child repositories.

## Initial Operator Flow

1. In a product fork, create `config/workspace.json` from
   `config/workspace.example.json`.
2. Configure child repositories and stages in `config/workspace.json`.
3. Initialize a feature directory.
4. Review or edit the generated intake and status files.
5. Render the feature manifest.
6. Run the configured stages one repository at a time.
7. Capture exact repository subjects and resolve the configured evidence gates.
8. Collect provider/source-control proof and evaluate the named readiness
   decision.
9. Render reports or run the bounded repair cycle.

## Example Local Dry Run

```bash
bash scripts/orchestration/init-feature.sh --feature-id FEAT-0001 --title "Branch previews for product delivery"
bash scripts/orchestration/render-manifest.sh features/FEAT-0001
bash scripts/orchestration/collect-github-state.sh --feature-dir features/FEAT-0001 --fixtures tests/fixtures/github
bash scripts/orchestration/advance-stage.sh features/FEAT-0001
bash scripts/orchestration/run-speckit-stage.sh --feature-dir features/FEAT-0001 --stage implementation --dry-run
bash scripts/orchestration/evaluate-mergeability.sh features/FEAT-0001
```

## Live Integration Entry Points

1. `collect-github-state.sh` can query a real PR through:

   ```bash
   bash scripts/orchestration/collect-github-state.sh \
     --feature-dir features/FEAT-0001 \
     --repo <owner/repo> \
     --pr-number <number>
   ```

2. `run-speckit-stage.sh` reads the resolved workspace config and invokes
   `codex exec` in the mapped child repository.

3. The stage runner passes the control-repo intake into the child repository
   prompt and tells Codex which configured skill to use.

4. Quality-enabled workspaces bind source-control checks to each PR head,
   independently evaluate `stage-ready`, `merge-ready`, and `release-ready`,
   and retain legacy mergeability as a projection.

See [Feature Evidence Quality Gates](feature-evidence-quality-gates.md) for the
complete evidence and repair workflow.

## Configuration Resolution

Use `--config <path>` with any orchestration command when validating an
alternate product workspace configuration.

Without `--config`, orchestration commands resolve configuration in this order:

1. explicit `--config <path>`
2. fork-owned `config/workspace.json`
3. upstream `config/workspace.example.json` for template examples, demos, and tests
