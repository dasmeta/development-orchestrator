# Feature Specification: Template Fork Contract

**Feature Branch**: `007-template-fork-contract`  
**Created**: 2026-05-19  
**Status**: Draft  
**Input**: Jira MAN-1495 refined description: "Make product-orchestration repo product agnostic upstream template"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Publish A Product-Agnostic Upstream Template (Priority: P1)

As a template maintainer, I need the upstream development orchestrator to contain only generic orchestration material so it can be safely published and reused.

**Why this priority**: This is the core safety requirement. The public upstream must not carry active product configuration, product-specific behavior, local machine paths, or downstream fork assumptions.

**Independent Test**: Inspect the tracked upstream tree and run the template conformance test. The tree contains no active product workspace config and no product-specific references.

**Acceptance Scenarios**:

1. **Given** the upstream repository tree, **When** a maintainer inspects `config/`, **Then** the repository contains `config/workspace.example.json` and does not contain tracked `config/workspace.json`.
2. **Given** the upstream repository tree, **When** a maintainer runs template conformance checks, **Then** product-specific names, local paths, and downstream fork assumptions are rejected.

---

### User Story 2 - Preserve Fork-Owned Workspace Overlays (Priority: P2)

As a downstream product fork maintainer, I need clear reserved paths for product-specific setup so upstream template changes can be merged without overwriting active product configuration.

**Why this priority**: The template must support long-lived product copies. Explicit fork-owned paths reduce merge conflicts and prevent upstream from assuming ownership of product workspace state.

**Independent Test**: Read the repository instructions and contract documentation. They identify upstream-owned paths, fork-owned reserved paths, and the `WORKSPACE.md` overlay rule.

**Acceptance Scenarios**:

1. **Given** a product fork with root `WORKSPACE.md`, **When** an agent reads root `AGENTS.md`, **Then** the agent is instructed to read `WORKSPACE.md` after `AGENTS.md`.
2. **Given** an upstream change, **When** the change touches fork-reserved paths such as `WORKSPACE.md`, `config/workspace.json`, numbered child repository folders, `workspace/`, or `overlays/`, **Then** repository guidance identifies that as outside upstream ownership.

---

### User Story 3 - Resolve Configuration Safely (Priority: P3)

As an operator running orchestration scripts, I need configuration resolution to prefer explicit or active fork configuration while still allowing upstream examples, demos, and tests to run.

**Why this priority**: Scripts need a deterministic default path in both product forks and the upstream template. The example config must not be mistaken for active product configuration in real work.

**Independent Test**: Run orchestration script tests for explicit config, active config, and example fallback behavior.

**Acceptance Scenarios**:

1. **Given** a command with `--config <path>`, **When** the command runs, **Then** it uses the explicit config path.
2. **Given** no explicit config and a fork-owned `config/workspace.json`, **When** the command runs, **Then** it uses `config/workspace.json`.
3. **Given** no explicit config and no active `config/workspace.json`, **When** a template example, demo, or test command runs, **Then** it may use `config/workspace.example.json`.

### Edge Cases

- The upstream tree has no active config but commands are run without `--config`: scripts must either use the example config for template-safe execution or fail with a clear message when a live target requires active workspace configuration.
- A downstream fork adds `WORKSPACE.md`: root guidance must make the overlay discoverable without requiring upstream to know product-specific rules.
- A future upstream change adds a root numbered folder or `overlays/`: conformance tests should catch that the path is fork-reserved.
- The example config is present: documentation and file naming must make clear it is not active product configuration.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Upstream MUST define the template/fork ownership contract in repository documentation.
- **FR-002**: Upstream MUST document upstream-owned paths, including `AGENTS.md`, `AI-INDEX.md`, `README.md`, `TODO.md`, `.github/`, `.specify/`, `.agents/`, `scripts/`, `schemas/`, `templates/`, `tests/`, `docs/`, and `config/workspace.example.json`.
- **FR-003**: Upstream MUST document fork-owned reserved paths, including `WORKSPACE.md`, `config/workspace.json`, `00-*`, `01-*`, `02-*`, `03-*`, `04-*`, `05-*`, `workspace/`, and `overlays/`.
- **FR-004**: Upstream MUST NOT ship a tracked active `config/workspace.json`.
- **FR-005**: Upstream MUST ship an example workspace configuration at `config/workspace.example.json`.
- **FR-006**: Root `AGENTS.md` MUST instruct agents to read root `WORKSPACE.md` after `AGENTS.md` when `WORKSPACE.md` exists.
- **FR-007**: Orchestration commands MUST support explicit `--config <path>` as the highest-precedence configuration source.
- **FR-008**: Orchestration commands MUST use `config/workspace.json` as the default active product-fork configuration when no explicit config is provided and the file exists.
- **FR-009**: Orchestration commands MUST allow `config/workspace.example.json` as a fallback when no active config exists, for template examples, demos, and tests.
- **FR-010**: Upstream conformance tests MUST verify that tracked upstream files do not include product-specific references, local machine paths, downstream fork remotes, or organization-specific product assumptions.
- **FR-011**: Upstream conformance tests MUST verify that fork-reserved paths are not tracked by upstream.
- **FR-012**: Upstream documentation MUST describe the downstream sync pattern using an `upstream` remote merge from `upstream/main`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A repository scan of tracked upstream files finds zero occurrences of the previous product workspace name.
- **SC-002**: `git ls-files config/workspace.json` returns no tracked active workspace configuration.
- **SC-003**: `git ls-files config/workspace.example.json` returns exactly one example workspace configuration.
- **SC-004**: Template conformance tests fail if `WORKSPACE.md`, `config/workspace.json`, numbered child repository folders, `workspace/`, or `overlays/` are tracked upstream.
- **SC-005**: All root orchestration tests pass after the config fallback and documentation changes.

## Assumptions

- The upstream repository is intended to be public and product-agnostic.
- Downstream product repositories are standalone copies or forks that may add product-owned files.
- Example workspace configuration is acceptable in upstream when named `workspace.example.json`.
- Product-specific downstream setup will be documented in `WORKSPACE.md` or child repository instructions, not in upstream-owned template files.
