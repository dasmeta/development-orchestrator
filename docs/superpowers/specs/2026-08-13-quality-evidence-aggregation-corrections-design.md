# Quality Evidence Aggregation Corrections Design

## Status

Approved for implementation by the operator on 2026-08-13 after review of the
five false-ready findings on Galust development-orchestrator PR #1.

## Problem

The first evidence-quality implementation binds records to feature revisions,
but it does not preserve what each provider actually examined. The evaluator
then selects one latest matching record for a gate. In a multi-repository
feature, one repository verifier can therefore certify other repositories. In
a gate with several providers, one provider can replace the results of the
others. The verifier also receives the checked-out working-tree diff instead
of the captured feature subject. Separately, GitHub evidence collection mixes
source snapshots with generated payloads and treats an empty check set as a
pass.

These are fail-open defects. They must be corrected before any adopter enables
`enforce` mode.

## Design Goals

- A verifier reviews the exact captured commit or worktree subject.
- Every evidence record identifies the repositories it actually covers.
- Multi-repository gates require evidence for every configured provider target
  present in feature scope.
- Gates with multiple providers declare whether the providers are conjunctive
  (`all`) or alternatives (`any`); ambiguous multi-provider gates are invalid.
- A failure from valid current evidence is never hidden by ordering.
- Evidence reports list every selected evidence record, not one arbitrary ID.
- GitHub snapshot collection is rerunnable and empty checks are blocked.
- Existing product-specific tools remain policy data; the engine stays
  product-agnostic.

## Considered Approaches

### 1. Split only the Galust orchestrator test gate

Creating three overlay gates would fix the scheduled-trigger symptom, but the
generic evaluator would remain unsafe for other products and for verifier
records. This is too narrow.

### 2. Add explicit provider and repository aggregation

Add repository IDs to evidence coverage, derive required repository targets
from provider configuration and feature scope, and evaluate current evidence
per provider and repository. Add an explicit provider strategy when a gate has
multiple providers. This addresses the model defect while preserving
product-configured tools. This is the selected approach.

### 3. Generate one composite evidence envelope per gate

A separate aggregation command could merge provider outputs before evaluation.
That creates a new trusted component, duplicates evaluator logic, and obscures
individual failure provenance. It is unnecessary.

## Evidence Contract

`coverage.repository_ids` is added to normalized evidence. It names only the
repositories the producer actually examined. Each named repository must also
exist in `subject.repositories`, bound to its captured subject.

New built-in producers emit repository-scoped subjects:

- command provider: the repository in which the command ran;
- independent verifier: the repository whose diff was supplied;
- GitHub checks and approval: the repository represented by the snapshot.

Previously collected evidence without repository coverage remains immutable
but cannot satisfy a repository-targeted gate. Operators recollect it; the
engine does not rewrite history.

## Exact Verifier Input

The verifier resolves its repository record from `scope.json` and refuses a
missing or inconsistent base, head, or subject.

- Commit subject: render the binary diff from captured `base` to captured
  `head`, independent of the currently checked-out branch.
- Worktree subject: verify the live worktree fingerprint still equals the
  captured subject, render tracked changes from captured `base` through the
  current worktree, then append deterministic binary patches for sorted
  untracked files.

Diff construction errors are provider failures. They are not converted to an
empty diff.

## Provider and Repository Aggregation

Each gate resolves a provider strategy:

- A one-provider gate defaults to `all`.
- A gate with multiple providers must explicitly set `provider_strategy` to
  `all` or `any`; policy validation rejects omission.
- `all` requires every configured provider.
- `any` permits alternatives, but valid current failed evidence is
  contradictory proof and keeps the gate failed. Otherwise one fully ready
  provider is sufficient.

For each provider, required repository coverage is the intersection of its
configured `repository_ids` or `repository_role` with repositories in feature
scope. A provider with no target in scope is not required for that gate. For
every required target, the evaluator selects the latest valid record from that
provider that explicitly covers the target and matches its current subject.

Provider status uses fail-closed precedence:

1. any valid current failure: `failed`;
2. otherwise any blockage: `blocked`;
3. otherwise any missing, stale, or incomplete target: `incomplete`;
4. only complete passing coverage: `ready`.

Gate results expose sorted `evidence_ids`. The legacy singular `evidence_id`
is retained only when exactly one record satisfies the gate, keeping existing
report consumers compatible while eliminating arbitrary last-record output.

## Galust Overlay

The `orchestrator-focused-tests` gate declares `provider_strategy: all`, so
core, MCP, and scheduled-trigger results are all independently required when
the gate applies. The scheduled-trigger result cannot stand in for either
general suite. Other multi-provider gates must also declare their strategy.

## GitHub Collection

GitHub snapshots remain under `state/github/`. Generated evidence payloads move
under the provider-run directory for the current run. Snapshot discovery also
rejects generated payload names and validates the minimal snapshot shape.

Check evaluation is:

- zero checks: `blocked`;
- any red check: `failed`;
- all nonempty checks green: `passed`;
- otherwise: `blocked`.

Each check or approval record covers only its snapshot repository.

## Error Handling and Compatibility

- Missing repository coverage produces a stable incomplete finding.
- Provider failures and blockages are aggregated without being hidden by
  evidence timestamps or lexical IDs.
- Old evidence records remain readable for diagnostics but are not selected
  when repository coverage is required.
- Policy schemas accept `provider_strategy`; semantic validation requires it
  only for multi-provider gates.
- Generated gate plans materialize the resolved strategy so evaluation is
  deterministic even if downstream tooling reads only the plan.

## Testing

Regression tests must demonstrate red before implementation and green after:

1. A clean worktree verifier prompt contains committed base-to-head changes.
2. A worktree verifier prompt contains tracked and untracked changes and
   rejects a changed fingerprint.
3. One passing repository verifier cannot ready a two-repository gate.
4. A later passing repository cannot hide another repository failure.
5. `all` requires every provider; `any` is explicit and deterministic.
6. The Galust orchestrator gate requires all three focused-test providers.
7. GitHub collection can run twice with distinct run IDs.
8. Empty checks produce blocked evidence.
9. Full generic tests and dogfood scenarios remain deterministic.

## Non-Goals

- Selecting product-specific test commands in generic code.
- Changing observe/enforce rollout policy.
- Mutating or deleting historical evidence.
- Incorporating unrelated verifier schema compatibility work from other open
  branches.
