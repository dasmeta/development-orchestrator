# Research: Template Fork Contract

## Decision: Upstream Ships Example Config Only

**Rationale**: `config/workspace.json` is active workspace state and belongs to product forks. Keeping only `config/workspace.example.json` in upstream makes the template usable without implying a live product workspace.

**Alternatives considered**:

- Keep `config/workspace.json` as a generic default: rejected because it conflicts with the fork-owned active configuration boundary.
- Remove config entirely: rejected because examples, demos, and tests need a concrete schema-compatible config.

## Decision: Scripts Resolve Config By Explicit, Active, Then Example

**Rationale**: Operators need explicit overrides first. Product forks need active `config/workspace.json` defaults. The upstream template still needs example fallback for local demos and tests.

**Alternatives considered**:

- Require `--config` everywhere: rejected because it makes common product-fork workflows unnecessarily noisy.
- Always use the example config in upstream: rejected because product forks must not accidentally run against example paths when active config exists.

## Decision: Contract Lives In Runbook And Entrypoints

**Rationale**: A dedicated runbook can hold the full contract while `AGENTS.md`, `AI-INDEX.md`, and `README.md` expose the rules future agents and maintainers need immediately.

**Alternatives considered**:

- Put the full contract only in `AGENTS.md`: rejected because it would overload agent instructions and duplicate user-facing documentation.
- Put the full contract only in `README.md`: rejected because agents may prioritize `AGENTS.md` for execution rules.

## Decision: Conformance Test Enforces Reserved Paths

**Rationale**: Documentation alone is not enough. A shell conformance test can fail CI if upstream starts tracking fork-owned paths or product-specific references.

**Alternatives considered**:

- Manual review only: rejected because the repository is intended to stay public and reusable over time.
