# Data Model: Template Fork Contract

## Template/Fork Contract

Represents the ownership boundary between upstream template files and downstream product fork files.

Fields:

- `upstream_owned_paths`: paths upstream may create and modify.
- `fork_reserved_paths`: paths upstream must not create, modify, or assume.
- `configuration_resolution_order`: ordered list of config sources.
- `product_agnostic_rules`: content categories upstream must not contain.
- `sync_pattern`: recommended downstream update flow from upstream.

Validation rules:

- `config/workspace.json` is fork-reserved.
- `config/workspace.example.json` is upstream-owned.
- Reserved root paths include `WORKSPACE.md`, numbered child repo prefixes, `workspace/`, and `overlays/`.

## Workspace Configuration Source

Represents the config file selected by orchestration scripts.

Fields:

- `source_type`: `explicit`, `active`, or `example`.
- `path`: resolved filesystem path.
- `allowed_usage`: normal execution, template example, demo, or test.

Validation rules:

- Explicit config has highest precedence.
- Active config uses `config/workspace.json`.
- Example config uses `config/workspace.example.json` only when active config is absent.

## Fork Overlay

Represents product-specific guidance that downstream repositories may add.

Fields:

- `path`: root `WORKSPACE.md`.
- `ownership`: fork-owned.
- `relationship_to_agents`: read after root `AGENTS.md` when present.

Validation rules:

- Upstream must not track `WORKSPACE.md`.
- `AGENTS.md` must make `WORKSPACE.md` discoverable.
