# Development Orchestration Template

This repository is a product-agnostic control plane for coordinating feature
delivery across child repositories.

It owns:

- feature intake
- child repository routing
- generated feature state
- orchestration scripts
- handoff templates
- mergeability evaluation across configured child repositories

It does not own product behavior, shared contracts, runtime implementation, or
validation scenario truth. Those belong to the child repositories configured in
`config/workspace.json`.

## Configure A Product Workspace

1. Fork or copy this template into the product workspace.
2. Edit `config/workspace.json` with the product's child repositories, stages,
   skills, and merge gates.
3. Add product-specific routing rules in the fork or child repositories.
4. Keep the upstream template free of product-specific names and behavior.

## Core Commands

```bash
bash scripts/orchestration/init-feature.sh --feature-id FEAT-0001 --title "Branch previews for product delivery"
bash scripts/orchestration/render-manifest.sh features/FEAT-0001
bash scripts/orchestration/collect-github-state.sh --feature-dir features/FEAT-0001 --fixtures tests/fixtures/github
bash scripts/orchestration/collect-github-state.sh --feature-dir features/FEAT-0001 --repo example/implementation --pr-number 12
bash scripts/orchestration/advance-stage.sh features/FEAT-0001
bash scripts/orchestration/run-speckit-stage.sh --feature-dir features/FEAT-0001 --stage implementation --dry-run
bash scripts/orchestration/evaluate-mergeability.sh features/FEAT-0001
```

Most commands accept `--config <path>` when a product fork needs to use a
workspace configuration outside `config/workspace.json`.
