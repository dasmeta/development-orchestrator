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

## Template / Fork Contract

The upstream repository ships generic orchestration machinery only. Product
forks own active workspace setup, child repository layout, product routing, and
active `config/workspace.json`.

Upstream-owned paths include `AGENTS.md`, `AI-INDEX.md`, `README.md`, `TODO.md`,
`.github/`, `.specify/`, `.agents/`, `scripts/`, `schemas/`, `templates/`,
`tests/`, `docs/`, and `config/workspace.example.json`.

Fork-owned reserved paths include `WORKSPACE.md`, `config/workspace.json`, root
`00-*` through `05-*` child repository folders, `workspace/`, and `overlays/`.

See [Template Fork Contract](docs/runbooks/template-fork-contract.md) for the
full ownership and sync contract.

## Compose A Product Workspace

Use the `workspace-bootstrap` skill after forking this template to discover and
classify local Git repositories, review a proposed `00-*` through `05-*`
topology, and explicitly approve repository moves, links, or clones.

The two-phase workflow generates a portable `config/repository-index.json` and
`overlays/repository-index.md`. A new team member can use the same index to set
up missing repositories, and maintainers can refresh it when repositories are
added or moved.

See [Workspace Bootstrap And Reconciliation](docs/runbooks/workspace-bootstrap.md)
for initial bootstrap, new-person setup, refresh, confirmation, and recovery.

## Configure A Product Workspace Manually

1. Fork or copy this template into the product workspace.
2. Copy `config/workspace.example.json` to `config/workspace.json` in the
   product fork.
3. Edit `config/workspace.json` with the product's child repositories, stages,
   skills, and merge gates.
4. Add product-specific routing rules in `WORKSPACE.md`, the fork, or child
   repositories.
5. Keep the upstream template free of product-specific names and behavior.

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
workspace configuration outside `config/workspace.json`. Without `--config`,
commands resolve configuration as explicit config, then active
`config/workspace.json`, then upstream `config/workspace.example.json` for
template examples, demos, and tests.
