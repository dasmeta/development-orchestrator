# Implementation Plan: Product-Agnostic Development Orchestration Template

**Branch**: `006-template-orchestrator`
**Spec**: `specs/006-template-orchestrator/spec.md`

## Technical Context

- Shell orchestration scripts with `jq` for config and JSON state handling.
- Existing root tests are Bash scripts under `tests/orchestration/`.
- Product-specific behavior must move out of root docs and templates.
- No runtime child repository code should be changed.

## Constitution Check

- Root repository owns delivery wiring only.
- Child repositories own product behavior, contracts, implementation, and
  validation.
- All changes remain bounded to the root orchestration repository.
- Tests must prove config-driven behavior before relying on implementation.

## Design

Add a shared `workspace_config.sh` helper that provides script-safe access to
workspace configuration. Convert the manifest renderer, stage runner, stage
advancer, GitHub state collector, and mergeability evaluator to use that helper.

Add `config/workspace.json` as the default generic template config. Delete the
old product-specific downstream config.

Rewrite root docs and handoff templates so they describe generic roles and
product-fork overlays. Remove tracked generated feature state and product
symlinks from the template.

Add a conformance test that scans root-owned files for product-specific names
and local machine paths.

## Validation

- `bash tests/orchestration/test-init-feature.sh`
- `bash tests/orchestration/test-render-manifest.sh`
- `bash tests/orchestration/test-collect-github-state.sh`
- `bash tests/orchestration/test-advance-stage.sh`
- `bash tests/orchestration/test-run-speckit-stage.sh`
- `bash tests/orchestration/test-evaluate-mergeability.sh`
- `bash tests/orchestration/test-template-agnostic.sh`
- `bash tests/orchestration/test-collect-github-state-live.sh`
- `bash tests/orchestration/test-run-speckit-stage-live.sh`
