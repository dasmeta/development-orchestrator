# Feature Evidence Quality Gates

**Status:** Approved design

**Date:** 2026-08-13

**Target:** Development-orchestrator control repository

## 1. Purpose

The development orchestrator currently routes work across repositories and can
evaluate configured GitHub status values, but it cannot establish that a
customer-visible outcome was actually proved. It has no durable model for
acceptance claims, evidence applicability, tested revisions, independent
verification, documentation impact, blocked checks, or human-authorized risk
acceptance.

This design adds a product-agnostic quality control plane that lets autonomous
coding agents continue working until the required product claims are supported
by valid evidence. It must reduce customer-visible regressions, visual defects,
missing documentation, misleading pull-request summaries, and repeated repair
cycles without prescribing the tools used by individual products.

The governing principle is:

> The orchestrator is strict about the validity and completeness of proof, but
> remains loose about which product tools produce that proof.

## 2. Goals

The system must:

1. Aggregate readiness across every repository participating in one feature.
2. Bind acceptance claims and evidence to exact repository revisions.
3. Compute required gates from product-owned policy and change impact.
4. Accept evidence from heterogeneous, product-defined tools through a stable
   provider protocol.
5. Distinguish missing evidence, demonstrated product failure, unavailable
   infrastructure, and policy ambiguity.
6. Produce deterministic, actionable repair briefs for autonomous agents.
7. Prevent an implementation agent from approving its own product intent,
   waiving gates, or weakening protected validation to make a check pass.
8. Generate readiness reports and pull-request summaries from verified state.
9. Retain lightweight release evidence for audit and regression learning.
10. Keep generic machinery cleanly separable from adopter-specific policy so
    product forks can share the same upstream implementation.

## 3. Non-goals

The first implementation will not:

- replace product requirement repositories, test frameworks, CI systems,
  preview systems, visual-review tools, or artifact stores;
- define product behavior or decide which customer outcomes are correct;
- require a particular repository layout, programming language, CI vendor,
  browser framework, or deployment platform;
- build an event-sourced workflow service or long-running orchestration server;
- promise that all defects are preventable;
- allow agents to create authoritative product approvals or waivers;
- require every possible evidence type for every change.

## 4. Trust boundaries

### 4.1 Human-only authority

Only an authorized human may:

- approve product intent and acceptance criteria;
- issue a scoped, reasoned, expiring waiver;
- make a final merge or release decision when product governance requires one.

An agent may draft claims or a waiver request, but agent-authored state cannot
satisfy an approval or waiver gate. Approval and waiver records must be
collected through a configured trusted authority provider rather than accepted
as arbitrary feature input.

### 4.2 Agent authority

Within configured repository ownership and write scopes, an autonomous agent
may:

- implement approved behavior;
- run configured evidence providers;
- collect and normalize evidence;
- repair implementation failures;
- update documentation when authorized by the feature scope;
- produce readiness reports and pull-request summaries;
- report a blocker and prepare a human decision request.

### 4.3 Fail-closed behavior

Required proof that is unavailable does not become a pass. The evaluator marks
the decision `blocked` unless a valid human waiver applies. Unknown
applicability, ownership, or provenance becomes `incomplete` and must be
resolved rather than silently treated as not applicable.

## 5. Ownership model

The development-orchestrator control repository owns the generic protocol and
feature-level decision. It does not absorb product or repository-local truth.

| Surface | Owner |
| --- | --- |
| Evidence schemas, policy semantics, evaluator, reports, provider protocol | Generic development orchestrator |
| Active policy, impact rules, permitted providers, risk thresholds | Product fork configuration |
| Acceptance behavior and claim approval | Configured intent repository and human authority |
| Shared interface truth | Configured contracts repository |
| Focused implementation checks and detailed artifacts | Relevant implementation repository or its CI |
| Executable product E2E cases and deployed execution records | Configured validation repository or its CI |
| Aggregate feature evidence ledger and derived readiness | Development-orchestrator feature workspace |
| Durable large-artifact storage | Product-selected repository, CI, or artifact system |

Generic code must use configured repository IDs and roles. It must not contain
product names, product behavior, fixed paths, or tool-specific evidence types.

## 6. Architecture

The design has four primary components.

### 6.1 Evidence contract

A versioned JSON contract represents feature scope, acceptance claims,
evidence, human waivers, and readiness decisions. The contract defines what
must be proved and how proof is validated without defining how a tool performs
the underlying test or review.

### 6.2 Product policy

Product-owned configuration maps repository roles, changed paths, approved
feature metadata, and risk classes to required evidence types. It also defines
permitted providers, evidence freshness, independence requirements, and named
readiness decisions.

### 6.3 Feature evidence ledger

One feature-level ledger aggregates normalized evidence across all
participating repositories. Source records are immutable and derived state is
regenerated. Detailed reports, videos, screenshots, and logs remain with the
producer; the ledger stores durable references and integrity metadata.

### 6.4 Deterministic evaluator

The evaluator resolves applicable policy, validates source records, and emits
named decisions plus stable failure reasons. The same inputs must always
produce the same result. Agents and providers never write readiness directly.

## 7. Feature workspace model

The default filesystem layout is:

```text
features/<feature-id>/
├── intake.md
├── scope.json
├── claims.json
├── evidence/
│   └── <evidence-id>.json
├── waivers/
│   └── <waiver-id>.json
└── state/
    ├── manifest.json
    ├── readiness.json
    ├── readiness.md
    ├── repair-brief.json
    └── pr-summary.md
```

`scope.json`, `claims.json`, evidence records, and waiver records are evaluator
inputs. Files under `state/` are derived outputs and must be safe to delete and
regenerate.

Products may configure another durable state or archive destination, but the
logical ownership and schemas remain unchanged. At release, the lightweight
ledger and final decision record must be retained through the configured
storage mechanism. Large artifacts may follow their provider's retention
policy as long as the release record preserves stable references and required
integrity data.

## 8. Source records

### 8.1 Feature scope

`scope.json` records:

- feature identifier and schema version;
- participating repository IDs and roles;
- exact candidate subjects, represented by commit IDs for committed work or by
  deterministic Git tree and diff fingerprints for pre-commit work;
- changed paths or a stable diff reference;
- human-approved explicit impact or risk flags, when supplied;
- derived impact categories and the policy version that produced them;
- repository dependency relationships relevant to evidence invalidation.

Agent-proposed impact hints may add scrutiny but may not remove requirements
derived from product policy. If explicit and derived impacts disagree, the
evaluator uses their union and reports the conflict.

### 8.2 Acceptance claims

`claims.json` contains stable claim IDs and references to approved source
material. Each claim record includes:

- owning repository and source revision;
- source path or durable external reference;
- content digest;
- priority or release criticality when defined by the product;
- affected surfaces or declared evidence expectations;
- approval reference collected from a trusted human-authority provider.

The control repository does not become the source of product behavior. The
digest detects drift between the approved claim and the evidence subject.

### 8.3 Evidence envelope

Every provider emits a normalized record containing at least:

- schema version and globally unique evidence ID;
- feature ID;
- evidence type, expressed as an open product-configurable string;
- provider ID and producer identity;
- producer role and orchestration run ID;
- covered acceptance claim IDs;
- subject repository revisions;
- policy and provider-configuration versions;
- result: `passed`, `failed`, or `blocked`;
- environment and safe fixture identity where applicable;
- collection timestamp and optional expiration;
- artifact references and checksums where practical;
- structured findings, gaps, and diagnostic codes;
- optional superseded-evidence reference.

Evidence source records are immutable. A rerun creates a new record and may
supersede an older record. The evaluator selects valid current evidence; it
does not rewrite history.

### 8.4 Waiver envelope

A waiver records:

- waiver ID and schema version;
- exact gate or finding being waived;
- feature, claim, repository, revision, and environment scope;
- human approver identity and trusted approval reference;
- reason and acknowledged risk;
- issuance and expiration times;
- whether revision changes are allowed. The default is false.

A waiver affects only the named gate. It does not turn the overall feature into
a generic `waived` state or conceal the waived risk from reports.

## 9. Policy model

The product fork supplies policy through a versioned `quality` configuration
block and, when useful, referenced fork-owned policy files. Generic code treats
this as data.

Policy defines:

1. **Impact classifiers** based on repository role, changed paths, dependency
   metadata, and approved feature flags.
2. **Risk classification** with product-owned labels and deterministic rules.
3. **Evidence requirements** for impact and risk combinations.
4. **Provider mappings** that identify permitted ways to produce each evidence
   type.
5. **Validity rules** for revision binding, freshness, environment, claim
   coverage, and artifact integrity.
6. **Independence rules** describing which producer roles and run identities
   may satisfy verification gates.
7. **Named decisions** and the evidence requirements associated with each.
8. **Execution budgets** for provider retries and autonomous repair cycles.

The generic minimum policy requires:

- approved intent for the behavior in scope;
- coverage for every applicable acceptance claim;
- evidence bound to exact relevant revisions;
- passed implementation checks for changed implementation surfaces;
- independent verification for implementation changes, unless deterministic
  product policy marks it not applicable;
- an explicit documentation disposition, represented as typed evidence stating
  `updated`, `not_applicable`, or `blocked` with affected documentation paths
  or the applicable policy reason;
- declared blockers and known gaps;
- valid human authority for any waiver.

Conditional evidence types such as visual review, accessibility, security,
performance, contract compatibility, migration validation, or deployed E2E are
enabled by product policy. They are not hard-coded engine enums.

## 10. Provider protocol

Products and child repositories choose the tools. A provider is configured by
ID, supported evidence types, repository context, invocation method, trust
class, and output location.

The initial generic protocol supports these transport patterns:

- execute a trusted repository-configured command that writes one or more
  evidence envelopes;
- import a validated envelope produced by CI or another external system;
- normalize configured source-control status checks into evidence;
- collect a trusted human approval or review attestation.

Provider commands must be defined in trusted product or repository
configuration as argument arrays or repository-owned scripts. Feature input,
claim text, and agent output may provide data arguments but may not define an
executable command. Providers run with the minimum configured permissions and
in the owning repository context.

A successful process exit is not evidence of success by itself. Output must
validate against the evidence schema and satisfy policy provenance rules.

Examples of valid product choices include browser automation, hosted visual
review, repository-native test commands, contract checkers, deployment smoke
tests, or manual review systems. Their internal formats remain outside the
orchestrator.

## 11. Applicability and revision binding

Applicability is a policy decision, not an agent assertion. The evaluator
computes it from trusted scope data and policy. A gate may resolve to:

- `required`;
- `not_applicable`, with the deterministic policy rule recorded;
- `unknown`, which makes the enclosing decision `incomplete`.

Every gate identifies the repositories and claims relevant to its subject. Its
evidence must match the exact relevant subject fingerprint. Pre-commit evidence
may bind to a deterministic Git tree and diff fingerprint; `merge-ready`
evidence must bind to the committed candidate revisions. A change to a relevant
subject, claim digest, policy version, provider configuration, or required
environment invalidates the evidence.

Evidence for an unrelated repository may be reused when declared dependency
rules establish that its subject is unchanged. This avoids rerunning an entire
multi-repository suite for every local edit while remaining fail-closed when
dependencies are ambiguous.

## 12. Named lifecycle decisions

The evaluator supports multiple decisions instead of one overloaded
`mergeability.ready` boolean.

### 12.1 `stage-ready`

Determines whether upstream truth and evidence are sufficient to enter the
next configured repository stage. Each stage may reference a named policy
decision. Pull-request approval alone is not a universal stage-transition
condition.

### 12.2 `merge-ready`

Evaluates pre-merge evidence for all participating pull requests and relevant
candidate revisions. It must not require a pull request to already be merged.
Its result can be exposed as a required source-control check.

### 12.3 `release-ready`

Evaluates post-build or deployed-path proof, including release-critical E2E
where configured. Products may require it before merge when previews provide
the real deployed path, after merge before promotion, or at both lifecycle
points through separate named decisions.

Products may add other named decisions using the same evaluator semantics.

Each decision has one status:

- `ready`: every applicable gate is satisfied;
- `incomplete`: evidence or trusted classification is missing, stale,
  malformed, or ambiguous;
- `failed`: valid evidence demonstrates an unmet product claim;
- `blocked`: a required provider, fixture, environment, or external dependency
  cannot execute.

Waivers are recorded at gate level and remain visible within the decision.

## 13. Autonomous execution and repair loop

For an approved feature, the orchestrator performs this loop:

1. Resolve participating repositories and lock candidate revisions.
2. Load approved claim references and verify approval provenance.
3. Classify impact and compute required gates.
4. Execute or collect evidence from configured providers.
5. Validate envelopes, provenance, claim coverage, revision binding, freshness,
   environment, and independence.
6. Evaluate the requested named decision.
7. When not ready, generate a bounded repair brief containing stable finding
   IDs, owning repository, affected claims, permitted write scope, evidence
   diagnostics, and exact rerun instructions.
8. Run the configured implementation repair stage.
9. Recollect only invalidated or failed evidence and reevaluate.
10. Stop when ready, when the configured attempt budget is exhausted, or when
    human authority or unavailable infrastructure is required.

The repair agent may modify only the configured implementation or
documentation scope named in the brief. It may not make a gate pass by changing
approved claims, protected validation cases, policy, provider configuration,
or evidence source records. A legitimate need to change those surfaces routes
the feature back to the owning stage and invalidates downstream evidence.

Independent verification for implementation changes must come from a separate
run identity and a verifier role that lacks implementation write authority
where the execution environment supports that restriction. Imported evidence
must satisfy an equivalent product-configured trust rule.

## 14. Failure handling

The system separates four failure classes:

| Class | Meaning | Default response |
| --- | --- | --- |
| Product failure | Valid evidence demonstrates incorrect behavior | Repair implementation and rerun affected evidence |
| Evidence failure | Proof is missing, malformed, stale, incomplete, or revision-mismatched | Recollect or correct provider output |
| Infrastructure blockage | Required tool, fixture, preview, integration, or deployed path is unavailable | Retry within budget, then mark blocked |
| Policy failure | Ownership or applicability cannot be resolved safely | Mark incomplete and request policy or human resolution |

Retries are bounded and configurable. Exhausted retries do not convert a
failure into a pass. Behavioral failures remain failed; infrastructure failures
become blocked. Stable claim, gate, and finding IDs let the loop target exact
failures and avoid repeatedly restarting completed work.

## 15. Derived outputs

### 15.1 Machine-readable readiness

`readiness.json` includes:

- policy and schema versions;
- subject fingerprint;
- named decision and overall status;
- each applicable, not-applicable, waived, and unsatisfied gate;
- selected evidence IDs and rejected evidence reasons;
- stable findings and ownership;
- remaining gaps and blockers;
- evaluation timestamp.

### 15.2 Human-readable readiness

`readiness.md` explains what was proved, what was not applicable and why, what
failed, what is blocked, and what human action is required. It includes tested
revisions and evidence links.

### 15.3 Repair brief

`repair-brief.json` is generated only from evaluator findings. It contains no
new product behavior. It limits the next agent run to the owning repository and
permitted files or responsibility class.

### 15.4 Pull-request and release summaries

Summaries are generated from the same ledger and must include:

- approved outcome and acceptance-claim references;
- participating repositories and revisions;
- implementation and contract impact;
- test, visual, E2E, and other applicable evidence;
- documentation disposition;
- blockers, known gaps, and waivers;
- final named-decision status.

A summary cannot omit a failure, blocker, gap, or waiver present in current
readiness state. Source-control integration may publish the generated summary,
but publication is an adapter concern rather than evaluator logic.

## 16. Escaped-defect learning

Every customer-visible escaped defect must result in:

1. an updated or new business-readable acceptance claim in the configured
   intent source;
2. a mapped permanent regression case in the configured validation source when
   product E2E is applicable;
3. focused implementation coverage in the owning implementation repository;
4. a review of impact or evidence policy when the existing policy failed to
   require relevant proof.

The purpose is to prevent repeated classes of failure, not merely document an
incident in a pull-request description.

## 17. Backward compatibility

The quality system is additive during migration.

- Existing feature intake and manifest fields remain readable.
- The manifest gains references to current scope and readiness outputs rather
  than embedding the full ledger.
- Existing GitHub-state collection becomes one evidence provider instead of
  the sole readiness source.
- Existing JSON-path mergeability evaluation remains available during observe
  mode and is deprecated only after product migration.
- Stage configuration may continue using the current `advance_when` rule until
  a stage is mapped to a named evidence decision.
- Schemas include explicit versions and migration commands reject destructive
  or ambiguous conversion.

## 18. Configuration and rollout modes

Each product supports:

- `off`: normal workflow does not invoke quality evaluation automatically,
  although an explicit evaluation command remains available;
- `observe`: decisions and reports are computed but do not block progression;
- `enforce`: configured named decisions block progression when not ready.

Mode controls workflow invocation and enforcement, not evaluator semantics. An
explicit evaluator run must produce the same decision from the same inputs in
every mode.

An adopting product rolls out as follows:

1. Add schemas, provider protocol, evaluator, reports, and compatibility paths.
2. Configure product impact rules and repository-local providers in fork-owned
   paths.
3. Run observe mode on representative backend-only, UI, contract, deployed-E2E,
   and documentation-only features.
4. Compare decisions with discovered defects and operator review; tune product
   applicability and provider mappings without weakening evaluator semantics.
5. Enable enforcement for the generic minimum policy.
6. Enable conditional evidence types as their configured providers demonstrate
   reliable output.
7. Publish `merge-ready` as a required source-control check.
8. Review escaped defects and false classifications as ongoing policy inputs.

The fail-closed engine is implemented from the beginning. Observe mode is a
bounded calibration mechanism, not a permanent substitute for enforcement.

## 19. Validation strategy

### 19.1 Schema validation

Maintain accepted and rejected fixtures for feature scope, claims, evidence,
waivers, provider configuration, and readiness output.

### 19.2 Policy evaluation

Use table-driven tests for required, not-applicable, unknown, passed, failed,
blocked, stale, wrong-revision, wrong-environment, insufficient-coverage,
expired-waiver, and valid-waiver cases.

### 19.3 Provider contracts

Use fake providers that emit valid, malformed, partial, conflicting, failed,
and blocked evidence. Prove that different tool choices cannot change core
decision semantics.

### 19.4 Multi-repository integration

Exercise features spanning intent, contracts, multiple implementation
repositories, and validation. Verify feature-level aggregation, dependency
invalidation, partial reruns, and exact revision binding.

### 19.5 Autonomous repair

Use deterministic fake builder and verifier stages to demonstrate failure
discovery, bounded repair, evidence replacement through supersession, and final
readiness. Prove that repair runs cannot alter protected claims, policy,
providers, validation inputs, or prior evidence.

### 19.6 Report consistency

Generate readiness, repair, pull-request, and release outputs from the same
fixtures. Assert that failures, blockers, gaps, tested revisions, documentation
disposition, and waivers cannot disappear from one representation.

### 19.7 Product-agnostic conformance

Extend repository conformance checks to reject product names, local paths,
fixed repository IDs, specific frameworks, CI vendors, and product-only
evidence types in generic surfaces. Generic fixtures use fictional roles and
fake providers.

### 19.8 Adopter dogfood acceptance

Before enforcement, run at least these product scenarios:

- backend-only implementation with focused checks and independent verification;
- UI change with product-configured browser or visual evidence;
- shared-contract change spanning several repositories;
- documentation-only change with deterministic not-applicable decisions;
- required deployed-path E2E that is intentionally unavailable and therefore
  blocks;
- deliberate behavioral failure followed by a bounded autonomous repair;
- human waiver that applies to one gate and expires correctly.

## 20. Upstreamability

Generic implementation belongs in upstream-owned `scripts/`, `schemas/`,
`templates/`, `tests/`, and `docs/` paths. Each adopter's active quality policy,
provider wiring, repository mappings, and product evidence types belong in
fork-owned configuration or overlays.

The upstream implementation must work with adopter-owned paths excluded.
Generic tests must pass with only the example workspace and fake
providers. Product-specific extensions use open strings, configured rules, and
adapter contracts instead of changes to generic evaluator enums.

## 21. Implementation boundaries for the first release

The first release will use repository files, POSIX shell entry points, `jq`,
Git metadata, and configured provider commands, matching the existing control
plane. It will not introduce a database or daemon.

The first release must deliver:

- versioned source and derived schemas;
- deterministic scope fingerprinting and evidence validation;
- configurable impact, requirement, provider, and named-decision policy;
- command and import provider paths plus compatibility with existing GitHub
  state collection;
- immutable evidence ingestion;
- evaluation and actionable repair-brief generation;
- readiness and summary rendering;
- observe and enforce modes;
- compatibility for existing features and configuration;
- generic test fixtures and one adopter-owned active configuration used for
  dogfooding.

Cryptographic signing, remote event storage, a web dashboard, automatic policy
learning, and generalized distributed agent scheduling are deliberately
deferred. Trusted approval provenance, repository permissions, and CI identity
remain integrations supplied by the configured product environment.

## 22. Success criteria

The design is successfully implemented when:

1. The same ledger and policy always produce byte-equivalent machine-readable
   decisions apart from explicitly documented timestamps.
2. No feature can become merge-ready with a missing, failed, stale,
   wrong-revision, or unknown required gate in enforce mode.
3. An implementation agent cannot satisfy approval, waiver, or independent
   verification through its own output.
4. A multi-repository feature reports one aggregate decision with repository-
   and claim-specific findings.
5. A product can replace an evidence-producing tool without modifying generic
   evaluator code.
6. Generated summaries match the current evidence ledger and expose all gaps,
   blockers, and waivers.
7. Existing orchestration flows remain usable during observe-mode migration.
8. Generic conformance tests pass with adopter configuration excluded.
9. The initial adopter completes the dogfood scenarios before making
   `merge-ready` a required check.
