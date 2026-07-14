# Development Orchestration Repository Navigation Index

This index is the root AI navigation surface for a product-agnostic development
orchestration template. It maps root-owned orchestration surfaces, configured
child repository roles, generated outputs, validation commands, and handoff
templates.

It does not replace child repository `AGENTS.md` files and does not define
product behavior.

## Repository Role

This root repository is the workspace-level control plane for feature delivery.
It coordinates feature intake, configured child-repository routing, generated
feature state, orchestration scripts, and mergeability evaluation.

## Root-Owned Surfaces

| Path | Ownership |
| --- | --- |
| `config/workspace.example.json` | Example child repository, stage, skill, and merge-gate configuration for template demos and tests. |
| `schemas/` | Root feature-state schemas. |
| `scripts/orchestration/` | Workspace orchestration commands and helpers. |
| `.agents/skills/workspace-bootstrap/` | LLM-guided repository discovery, classification, onboarding, and refresh workflow. |
| `templates/features/` | Feature intake and status templates. |
| `templates/workspace/` | Generic generated workspace overlay and repository-index templates. |
| `templates/handoffs/` | Generic handoff templates for product forks to adapt. |
| `tests/orchestration/` | Root orchestration script tests. |
| `docs/` | Generic template runbooks and examples. |

## Fork-Owned Reserved Surfaces

| Path | Ownership |
| --- | --- |
| `WORKSPACE.md` | Product-specific fork overlay read after root `AGENTS.md`. |
| `config/workspace.json` | Active child repository, stage, skill, and merge-gate configuration. |
| `config/repository-index.json` | Portable product-fork repository catalog used for onboarding and refresh. |
| `00-*` through `05-*` | Product fork child repository folders. |
| `workspace/` | Product fork workspace state. |
| `overlays/` | Product fork overlays and conventions. |

## Configured Child Roles

The default template configuration defines these roles. Product forks may
replace the repository IDs while preserving clear ownership.

| Role | Owns |
| --- | --- |
| `intent` | Product behavior, acceptance criteria, edge cases, and logical test intent. |
| `contracts` | Shared request, response, schema, and interface definitions. |
| `implementation` | Runtime implementation downstream of approved intent and contracts. |
| `validation` | Executable validation grounded in approved intent and contracts. |

## Product Backbone Routing

Product behavior must start in the configured intent repository. AI agents must
not invent product behavior in implementation repositories or in this root
orchestration repository.

| Concern | Canonical source |
| --- | --- |
| Product behavior and business rules | Configured intent repository |
| Shared interface contracts | Configured contracts repository |
| Runtime implementation | Configured implementation repository |
| Executable validation | Configured validation repository |
| Cross-repo routing and mergeability | This root repository |

## Configuration Resolution

Orchestration commands resolve workspace configuration in this order:

1. explicit `--config <path>`
2. fork-owned `config/workspace.json`
3. upstream `config/workspace.example.json` for template examples, demos, and tests

## Generated Outputs

| Output | Location |
| --- | --- |
| Feature orchestration state | `features/<feature-id>/` |
| Local bootstrap inventories, proposals, deltas, and journals | `workspace/bootstrap/` |
| Portable repository catalog | `config/repository-index.json` |
| Human/LLM repository index | `overlays/repository-index.md` |
| Feature manifest | `features/<feature-id>/state/manifest.json` |
| GitHub state snapshot | `features/<feature-id>/state/github-state.json` |
| Stage run log | `features/<feature-id>/state/run-log.json` |
| Handoff packages | Product fork-defined child paths, usually generated from `templates/handoffs/` |

## Validation Commands

Use repository-local commands when a target repository defines them. Common
root-level checks:

```bash
bash tests/orchestration/test-init-feature.sh
bash tests/orchestration/test-render-manifest.sh
bash tests/orchestration/test-collect-github-state.sh
bash tests/orchestration/test-advance-stage.sh
bash tests/orchestration/test-run-speckit-stage.sh
bash tests/orchestration/test-evaluate-mergeability.sh
bash tests/orchestration/test-discover-workspace.sh
bash tests/orchestration/test-validate-workspace-proposal.sh
bash tests/orchestration/test-render-workspace-files.sh
bash tests/orchestration/test-compare-workspace-inventory.sh
bash tests/orchestration/test-apply-workspace-proposal.sh
bash tests/orchestration/test-workspace-bootstrap-guidance.sh
```

Template conformance:

```bash
bash tests/orchestration/test-template-agnostic.sh
```

## Human Approval Boundaries

- Cross-repository writes require explicit multi-repo scope from the operator.
- Product-specific live writes require product-fork or child-repository guidance.
- Runtime implementation must remain downstream of approved intent and shared
  contracts where applicable.
- Direct pushes to the default branch require explicit operator instruction.
