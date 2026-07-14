# {{WORKSPACE_NAME}} Workspace Overlay

## Purpose

{{WORKSPACE_DESCRIPTION}}

Use `config/workspace.json` as the executable routing map. Read
`overlays/repository-index.md` before selecting a child repository; it records
repository authority, dependencies, remotes, and local target paths.

## Routing Notes

{{ROUTING_NOTES}}

## Execution Rules

- Keep changes inside the explicitly targeted child repository.
- Treat upstream requirements and contracts as inputs, not implementation hints.
- Ask before adding, removing, moving, linking, or cloning repositories.
- Refresh the repository index when the workspace topology changes.
