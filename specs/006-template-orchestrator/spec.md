# Feature Specification: Product-Agnostic Development Orchestration Template

**Feature Branch**: `006-template-orchestrator`
**Created**: 2026-05-19
**Status**: Draft
**Input**: Convert this development orchestration repository into a product-agnostic upstream template that can be moved to a central template location and forked per product.

## User Scenarios & Testing

### User Story 1 - Configure A Product Workspace (Priority: P1)

An operator forks the template for a product and configures child repositories,
stages, skills, and merge gates without editing orchestration scripts.

**Why this priority**: A reusable template is only valuable if product-specific
wiring is data-driven.

**Independent Test**: Use a temporary `config/workspace.json`, render a
manifest, dry-run a configured stage, and verify the configured repository and
stage are used.

**Acceptance Scenarios**:

1. **Given** a workspace config with custom repository IDs, **When** a manifest
   is rendered, **Then** the manifest uses those repository IDs and initial
   stage.
2. **Given** a workspace config with a custom stage, **When** the stage runner
   is dry-run, **Then** the run log records the configured repository and skill.

### User Story 2 - Evaluate Configured Merge Gates (Priority: P2)

An operator defines product-specific merge gates in config and the root
evaluates readiness from those gates rather than fixed repository names.

**Why this priority**: Different product workspaces can have different CI,
preview, and validation expectations.

**Independent Test**: Provide a GitHub state snapshot and mergeability rules,
then verify the manifest readiness and reason are computed from config.

**Acceptance Scenarios**:

1. **Given** all configured gate paths match their expected values, **When**
   mergeability is evaluated, **Then** the feature is marked ready.
2. **Given** any configured gate fails, **When** mergeability is evaluated,
   **Then** the feature remains not ready.

### User Story 3 - Keep The Template Product-Agnostic (Priority: P3)

A maintainer can validate that upstream template files do not contain
product-specific names, local machine paths, or runtime product behavior.

**Why this priority**: A central template must not leak assumptions into future
product forks.

**Independent Test**: Run a conformance test that scans root-owned files for
forbidden product-specific strings.

**Acceptance Scenarios**:

1. **Given** the upstream template, **When** conformance runs, **Then** no
   product-specific child names or local absolute paths are found.

### Edge Cases

- A configured stage does not exist: the stage runner fails with `unknown stage`.
- A workspace config is missing: orchestration commands fail clearly.
- A configured repository path is relative: it resolves relative to the config
  file location.
- A product fork needs a UI handoff: it adapts generic handoff templates without
  changing upstream product behavior.

## Requirements

### Functional Requirements

- **FR-001**: Root orchestration scripts MUST read repository IDs, stages,
  skills, and merge gates from workspace configuration.
- **FR-002**: The root repository MUST NOT hardcode product-specific child
  repository names in scripts, docs, tests, or templates.
- **FR-003**: The manifest renderer MUST use the configured initial stage and
  configured repository list.
- **FR-004**: The stage runner MUST resolve stage-to-repository and stage-to-skill
  mappings from config.
- **FR-005**: Mergeability evaluation MUST use configured gate paths and expected
  values.
- **FR-006**: GitHub state collection MUST support configured check-name
  patterns.
- **FR-007**: Root documentation MUST define delivery wiring ownership and
  delegate product behavior to child repositories.
- **FR-008**: The template MUST include a conformance check that fails when
  root-owned files reintroduce product-specific names or local absolute paths.

### Key Entities

- **Workspace Configuration**: Product fork configuration for repositories,
  stages, skills, GitHub check matching, and mergeability gates.
- **Feature Manifest**: Generated state containing feature ID, current stage,
  configured repositories, and mergeability status.
- **GitHub State Snapshot**: Evidence collected from fixtures or a PR for
  configured gate evaluation.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A fresh clone can initialize a feature, render a manifest, dry-run
  a stage, collect fixture state, and evaluate mergeability using only template
  config.
- **SC-002**: All root orchestration tests pass.
- **SC-003**: Root conformance scan reports no product-specific or local
  machine-specific strings.
- **SC-004**: Product-specific symlinks and generated product state are absent
  from the upstream template.

## Assumptions

- Product forks may add product-specific overlays after forking.
- The central upstream template should ship with generic example roles.
- Existing Spec Kit and orchestration shell test patterns remain the preferred
  implementation mechanism.
