# Development Orchestration Runbook

Use the root control repository to initialize and track feature delivery across
configured child repositories.

## Initial Operator Flow

1. Configure child repositories and stages in `config/workspace.json`.
2. Initialize a feature directory.
3. Review or edit the generated intake and status files.
4. Render the feature manifest.
5. Run the configured stages one repository at a time.
6. Collect GitHub state and evaluate mergeability.

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

2. `run-speckit-stage.sh` reads `config/workspace.json` and invokes `codex exec`
   in the mapped child repository.

3. The stage runner passes the control-repo intake into the child repository
   prompt and tells Codex which configured skill to use.

Use `--config <path>` with any orchestration command when validating an
alternate product workspace configuration.
