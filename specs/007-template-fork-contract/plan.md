# Implementation Plan: Template Fork Contract

**Branch**: `007-template-fork-contract` | **Date**: 2026-05-19 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/007-template-fork-contract/spec.md`

## Summary

Make the development orchestrator upstream repository a product-agnostic template with an explicit fork contract. The implementation will move active workspace config to an example config, document upstream/fork ownership boundaries, add the root `WORKSPACE.md` overlay rule, update workspace config resolution, and extend conformance tests so upstream does not track fork-owned paths or product-specific assumptions.

## Technical Context

**Language/Version**: POSIX shell scripts and Markdown documentation  
**Primary Dependencies**: `bash`, `jq`, `rg`, Git  
**Storage**: Repository files only  
**Testing**: Shell-based orchestration tests under `tests/orchestration/`  
**Target Platform**: Local developer workstations and CI runners with Git, Bash, `jq`, and `rg`
**Project Type**: Repository template / CLI orchestration scripts  
**Performance Goals**: Conformance and orchestration tests complete quickly enough for CI feedback  
**Constraints**: Upstream must not track active product configuration or fork-owned reserved paths  
**Scale/Scope**: One upstream template repository with downstream product copies/forks

## Constitution Check

The current constitution file is the stock placeholder and does not define enforceable project-specific gates. This plan therefore uses the refined Jira acceptance criteria and repository `AGENTS.md` ownership rules as the controlling constraints.

Gate status:

- Product-agnostic upstream: PASS, addressed by documentation and conformance tests.
- Correct repository scope: PASS, all changes are in upstream-owned paths.
- Fork-owned reserved paths untouched: PASS, implementation will remove tracked active config and avoid creating reserved paths.
- Validation evidence required: PASS, shell tests and repository scans are included.

## Project Structure

### Documentation (this feature)

```text
specs/007-template-fork-contract/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
AGENTS.md
AI-INDEX.md
README.md
config/
└── workspace.example.json
docs/
└── runbooks/
    └── template-fork-contract.md
scripts/orchestration/
├── collect-github-state.sh
├── advance-stage.sh
├── evaluate-mergeability.sh
├── render-manifest.sh
├── run-speckit-stage.sh
└── lib/
    └── workspace_config.sh
tests/orchestration/
└── test-template-agnostic.sh
```

**Structure Decision**: This is a repository-template change. The implementation updates existing shell scripts, docs, and conformance tests rather than adding an application source tree.

## Complexity Tracking

No constitution violations or exceptional complexity are required.
