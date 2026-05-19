# Development Orchestrator Template / Fork Contract

The upstream `dasmeta/development-orchestrator` repository is the generic
development orchestration template.

Downstream product repositories are product-aware copies or forks of this
template. They own active workspace configuration and product-specific child
repository layout.

## Ownership Boundary

Upstream owns generic orchestration machinery.

Product forks own workspace-specific setup, child repository layout, product
routing, and active configuration.

## Upstream-Owned Paths

Upstream may create and modify:

- `AGENTS.md`
- `AI-INDEX.md`
- `README.md`
- `TODO.md`
- `.github/`
- `.specify/`
- `.agents/`
- `scripts/`
- `schemas/`
- `templates/`
- `tests/`
- `docs/`
- `config/workspace.example.json`

## Fork-Owned Reserved Paths

Upstream must not create, modify, or assume ownership of:

- `WORKSPACE.md`
- `config/workspace.json`
- `00-*`
- `01-*`
- `02-*`
- `03-*`
- `04-*`
- `05-*`
- `workspace/`
- `overlays/`

These paths are reserved for downstream product forks.

## Configuration Rules

- Upstream must not ship an active `config/workspace.json`.
- Upstream ships only `config/workspace.example.json`.
- Product forks create their own `config/workspace.json`.
- Scripts resolve configuration in this order:
  1. explicit `--config <path>`
  2. `config/workspace.json`
  3. `config/workspace.example.json` for template examples, demos, or tests

## Fork Overlay Rule

Root `AGENTS.md` must include this rule:

> If `WORKSPACE.md` exists in the repository root, read it after this file.
> `WORKSPACE.md` is fork-owned and may define product-specific child repositories,
> routing rules, validation gates, and workspace conventions. Generic upstream
> rules still apply unless the fork overlay narrows them for the product
> workspace.

## Product-Agnostic Upstream Rules

Upstream must not contain:

- product-specific child repository names
- product-specific business behavior
- product-specific API contracts
- product-specific runtime AI or tooling rules
- product-specific validation scenarios
- local machine paths
- downstream fork remotes or organization-specific assumptions

Examples must live under `docs/examples/` or use `*.example.*` filenames.

## Downstream Fork Rules

A product fork may add root-level setup such as:

- `WORKSPACE.md`
- `config/workspace.json`
- `00-<upstream-mirror>/`
- `01-<intent-repository>/`
- `02-<contracts-repository>/`
- `03-<validation-repository>/`
- `04-<implementation-repository>/`
- `05-<additional-product-repository>/`

The fork should avoid editing upstream-owned files unless the change is
intentionally meant to be contributed back upstream.

## Future Sync Pattern

Product forks should pull upstream template changes with:

```bash
git fetch upstream
git merge upstream/main
git push origin main
```

This should remain low-conflict because upstream does not touch fork-owned
reserved paths.
