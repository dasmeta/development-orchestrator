# Tasks: Template Fork Contract

**Input**: Design documents from `specs/007-template-fork-contract/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Required by acceptance criteria for conformance, config resolution, and existing orchestration behavior.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Phase 1: Setup

**Purpose**: Confirm baseline and prepare shared contract assets.

- [x] T001 Inspect current tracked config and conformance test coverage in `config/` and `tests/orchestration/test-template-agnostic.sh`
- [x] T002 [P] Create the full template/fork contract runbook in `docs/runbooks/template-fork-contract.md`

---

## Phase 2: Foundational

**Purpose**: Establish configuration and test foundations used by all stories.

- [x] T003 Rename tracked example configuration from `config/workspace.json` to `config/workspace.example.json`
- [x] T004 Update workspace config resolution helper in `scripts/orchestration/lib/workspace_config.sh`
- [x] T005 Update orchestration scripts that call `default_workspace_config_path` to use the new helper behavior
- [x] T006 Expand template conformance checks in `tests/orchestration/test-template-agnostic.sh`

**Checkpoint**: Config ownership and conformance foundations are ready.

---

## Phase 3: User Story 1 - Publish A Product-Agnostic Upstream Template (Priority: P1)

**Goal**: Upstream ships only generic template contents and rejects product-specific references.

**Independent Test**: Run template conformance and tracked-file checks for product references and active config.

### Tests for User Story 1

- [x] T007 [US1] Verify `tests/orchestration/test-template-agnostic.sh` rejects tracked `config/workspace.json`
- [x] T008 [US1] Verify `git ls-files config/workspace.json` returns no tracked files after implementation

### Implementation for User Story 1

- [x] T009 [US1] Update `README.md` to explain example config and product-agnostic upstream behavior
- [x] T010 [US1] Update `AI-INDEX.md` root-owned surfaces to reference `config/workspace.example.json`
- [x] T011 [US1] Ensure scans of tracked upstream files contain no product-specific references

**Checkpoint**: User Story 1 is testable independently through conformance and tracked-file scans.

---

## Phase 4: User Story 2 - Preserve Fork-Owned Workspace Overlays (Priority: P2)

**Goal**: Product forks have clear reserved paths and discoverable overlay guidance.

**Independent Test**: Inspect documentation and `AGENTS.md` for the fork overlay and reserved path rules.

### Tests for User Story 2

- [x] T012 [US2] Verify conformance test rejects fork-owned reserved paths tracked upstream

### Implementation for User Story 2

- [x] T013 [US2] Add `WORKSPACE.md` overlay rule and fork contract summary to `AGENTS.md`
- [x] T014 [US2] Fix Speckit-generated `AGENTS.md` context text so it does not contain truncated dependency names
- [x] T015 [US2] Update `AI-INDEX.md` and `README.md` with upstream-owned and fork-owned path summaries

**Checkpoint**: User Story 2 is testable independently through docs inspection and conformance behavior.

---

## Phase 5: User Story 3 - Resolve Configuration Safely (Priority: P3)

**Goal**: Commands prefer explicit config, then active fork config, then example fallback for template-safe execution.

**Independent Test**: Run orchestration script tests with explicit config and default example fallback.

### Tests for User Story 3

- [x] T016 [US3] Add or update tests for default example config fallback in `tests/orchestration/`
- [x] T017 [US3] Run explicit config tests to ensure `--config <path>` remains highest precedence

### Implementation for User Story 3

- [x] T018 [US3] Update runbook documentation in `docs/runbooks/development-orchestration.md` to describe config resolution order
- [x] T019 [US3] Ensure script error messages remain clear when required config cannot be found

**Checkpoint**: User Story 3 is independently validated by script tests.

---

## Phase 6: Polish & Cross-Cutting

**Purpose**: Validate the full contract and prepare delivery.

- [x] T020 [P] Run the full orchestration shell test suite
- [x] T021 [P] Run product-agnostic repository scans from `specs/007-template-fork-contract/quickstart.md`
- [x] T022 Update Jira MAN-1495 progress comment with validation status

---

## Dependencies & Execution Order

### Phase Dependencies

- Setup (Phase 1): no dependencies.
- Foundational (Phase 2): depends on setup.
- User Stories (Phases 3-5): depend on foundational config/test behavior.
- Polish (Phase 6): depends on all selected user stories.

### User Story Dependencies

- User Story 1 (P1): starts after foundational phase.
- User Story 2 (P2): starts after foundational phase and can run alongside US1 docs work with file coordination.
- User Story 3 (P3): starts after foundational config helper changes.

### Parallel Opportunities

- T002 can run while T001 inspection happens.
- Documentation tasks touching different files can run in parallel when coordinated.
- Final validation scans and tests can run in parallel.

## Implementation Strategy

1. Complete setup and foundational config ownership changes.
2. Deliver User Story 1 so upstream no longer tracks active config.
3. Deliver User Story 2 so fork overlays are documented and discoverable.
4. Deliver User Story 3 so script behavior matches the contract.
5. Run the full validation set and update Jira.
