# Tasks: Product-Agnostic Development Orchestration Template

## Phase 1: Tests

- [X] T001 Update manifest rendering test to expect config-driven repositories in `tests/orchestration/test-render-manifest.sh`
- [X] T002 Update stage-runner test to expect config-driven stages in `tests/orchestration/test-run-speckit-stage.sh`
- [X] T003 Update mergeability test to expect config-driven gates in `tests/orchestration/test-evaluate-mergeability.sh`

## Phase 2: Config-Driven Scripts

- [X] T004 Add workspace config helper in `scripts/orchestration/lib/workspace_config.sh`
- [X] T005 Update manifest rendering in `scripts/orchestration/render-manifest.sh`
- [X] T006 Update stage running in `scripts/orchestration/run-speckit-stage.sh`
- [X] T007 Update stage advancement in `scripts/orchestration/advance-stage.sh`
- [X] T008 Update GitHub state collection in `scripts/orchestration/collect-github-state.sh`
- [X] T009 Update mergeability evaluation in `scripts/orchestration/evaluate-mergeability.sh`

## Phase 3: Template Content

- [X] T010 Add generic workspace config in `config/workspace.json`
- [X] T011 Remove product-specific downstream config in `config/downstream-repos.json`
- [X] T012 Rewrite root instructions in `AGENTS.md`
- [X] T013 Rewrite repository navigation in `AI-INDEX.md`
- [X] T014 Rewrite template overview in `README.md`
- [X] T015 Rewrite runbooks and examples under `docs/`
- [X] T016 Replace UI handoff templates under `templates/handoffs/ui/`

## Phase 4: Cleanup And Guardrails

- [X] T017 Remove generated product feature state under `features/FEAT-0001/`
- [X] T018 Remove tracked product-specific symlinks
- [X] T019 Add product-agnostic conformance test in `tests/orchestration/test-template-agnostic.sh`
- [X] T020 Add conformance test to CI in `.github/workflows/control-repo-ci.yml`

## Phase 5: Verification

- [X] T021 Run all root orchestration tests
- [X] T022 Review git diff for accidental product-specific root content
