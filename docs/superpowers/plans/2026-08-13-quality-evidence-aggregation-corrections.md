# Quality Evidence Aggregation Corrections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate five false-ready paths by binding evidence to the repository actually examined, aggregating every required provider target, rendering exact captured diffs, and making GitHub evidence collection fail closed and rerunnable.

**Architecture:** Normalized evidence gains explicit repository coverage. Gate policy gains explicit provider aggregation, while the evaluator selects current evidence per provider and target repository and combines results deterministically. Built-in providers produce repository-scoped evidence, and the verifier renders its candidate diff from captured scope rather than checkout state.

**Tech Stack:** POSIX shell, Bash, jq, JSON Schema, Git, GitHub CLI fixtures, Markdown.

---

## File Responsibility Map

- `schemas/feature-evidence.schema.json`: repository coverage field for evidence.
- `schemas/quality-policy.schema.json`: `provider_strategy` contract.
- `schemas/quality-gate-plan.schema.json`: resolved strategy contract.
- `scripts/orchestration/lib/quality_records.sh`: evidence envelope validation.
- `scripts/orchestration/lib/quality_config.sh`: semantic policy validation.
- `scripts/orchestration/lib/git_subject.sh`: exact commit/worktree diff rendering.
- `scripts/orchestration/run-independent-verifier.sh`: repository-specific prompt and evidence.
- `scripts/orchestration/run-evidence-provider.sh`: explicit command-provider repository target and evidence.
- `scripts/orchestration/run-quality-providers.sh`: execute command providers for every scoped target.
- `scripts/orchestration/collect-github-evidence.sh`: rerunnable snapshot-to-evidence conversion.
- `scripts/orchestration/jq/resolve-gates.jq`: materialize provider strategy.
- `scripts/orchestration/jq/evaluate-readiness.jq`: per-provider/per-repository aggregation.
- `scripts/orchestration/jq/render-readiness.jq`: render all selected evidence IDs.
- `scripts/orchestration/jq/render-pr-summary.jq`: summarize all selected evidence IDs.
- `overlays/quality/policy.json`: require all Galust orchestrator focused suites.
- `tests/orchestration/`: adversarial regression coverage.

### Task 1: Extend evidence and policy contracts

**Files:**

- Modify: `schemas/feature-evidence.schema.json`
- Modify: `schemas/quality-policy.schema.json`
- Modify: `schemas/quality-gate-plan.schema.json`
- Modify: `scripts/orchestration/lib/quality_records.sh`
- Modify: `scripts/orchestration/lib/quality_config.sh`
- Modify: `tests/orchestration/test-ingest-quality-records.sh`
- Modify: `tests/orchestration/test-quality-config.sh`

- [ ] **Step 1: Add failing evidence repository-coverage tests**

Extend `test-ingest-quality-records.sh` with a valid record containing:

```json
"coverage": {
  "repository_ids": ["app"],
  "claim_ids": ["AC-1"],
  "architecture_constraint_ids": []
},
"subject": {"repositories": {"app": "commit:abc"}}
```

Add negative records where `repository_ids` is not an ID array and where a
covered repository is absent from `subject.repositories`. Assert both are
rejected as malformed.

- [ ] **Step 2: Add failing provider-strategy policy tests**

In `test-quality-config.sh`, create a two-provider gate without
`provider_strategy` and assert:

```text
multi-provider gate requires provider_strategy
```

Then assert `provider_strategy: all` and `provider_strategy: any` validate,
while any other value fails schema validation.

- [ ] **Step 3: Run contract tests and verify RED**

Run:

```bash
bash tests/orchestration/test-ingest-quality-records.sh
bash tests/orchestration/test-quality-config.sh
```

Expected: failures because repository coverage and provider strategy are not
implemented.

- [ ] **Step 4: Implement the schema and semantic contracts**

Add this required field to evidence coverage and include it in the coverage
object's `required` list:

```json
"repository_ids": {
  "type": "array",
  "items": {"$ref": "#/$defs/id"},
  "uniqueItems": true
}
```

Validation must require a nonempty repository ID array for newly generated
records and ensure every ID is present in `subject.repositories`. Add this gate
property:

```json
"provider_strategy": {"enum": ["all", "any"]}
```

Semantic validation must reject `providers | length > 1` when the property is
absent. A one-provider gate resolves to `all` without requiring policy churn.

- [ ] **Step 5: Run contract tests and verify GREEN**

Run the two focused tests. Expected: PASS.

- [ ] **Step 6: Commit the contract change**

```bash
git add schemas scripts/orchestration/lib tests/orchestration/test-ingest-quality-records.sh tests/orchestration/test-quality-config.sh
git commit -m "Define repository and provider evidence coverage"
```

### Task 2: Render the exact captured verifier diff

**Files:**

- Modify: `scripts/orchestration/lib/git_subject.sh`
- Modify: `scripts/orchestration/run-independent-verifier.sh`
- Modify: `tests/orchestration/test-run-independent-verifier.sh`

- [ ] **Step 1: Add a failing committed-subject verifier test**

Create a base commit and a feature commit, leave the test repository clean, and
capture both OIDs in `scope.json`. Make the fake verifier require the prompt to
contain the feature commit’s patch text. This must fail with the existing
`git diff HEAD` behavior.

- [ ] **Step 2: Add a failing worktree-subject verifier test**

Capture a worktree containing one tracked change and one untracked file. Make
the verifier require both paths and contents in the prompt. After capture,
change the worktree again and assert verification refuses the stale captured
fingerprint.

- [ ] **Step 3: Run the verifier test and verify RED**

```bash
bash tests/orchestration/test-run-independent-verifier.sh
```

Expected: the committed patch is missing and the stale worktree is not
rejected.

- [ ] **Step 4: Add exact subject diff helpers**

Add a helper with this interface:

```bash
git_subject_diff repository_path base_oid head_oid subject
```

For `commit:*`, verify `subject == commit:$head_oid` and run:

```bash
git -C "$repository_path" diff --binary --no-ext-diff --no-textconv \
  "$base_oid" "$head_oid" --
```

For `worktree:*`, recompute `git_worktree_subject`, require equality, render
tracked changes from `base_oid` to the live worktree, then append sorted
`git diff --no-index --binary /dev/null <path>` patches for untracked files.

- [ ] **Step 5: Use the captured repository record in the verifier**

Resolve exactly one scope record by `repository_id`, require `base`, `head`, and
`subject`, and replace `git diff HEAD || true` with `git_subject_diff`. A diff
error must terminate the verifier run.

Generate repository-scoped evidence:

```json
"coverage": {
  "repository_ids": ["<repository-id>"],
  "claim_ids": [],
  "architecture_constraint_ids": []
},
"subject": {
  "repositories": {"<repository-id>": "<captured-subject>"}
}
```

- [ ] **Step 6: Run the verifier test and verify GREEN**

Run the focused test. Expected: PASS for committed and unchanged worktree
subjects; stale worktree assertion fails as expected.

- [ ] **Step 7: Commit exact verifier input**

```bash
git add scripts/orchestration/lib/git_subject.sh scripts/orchestration/run-independent-verifier.sh tests/orchestration/test-run-independent-verifier.sh
git commit -m "Bind verifier prompts to captured subjects"
```

### Task 3: Produce repository-scoped command evidence

**Files:**

- Modify: `scripts/orchestration/run-evidence-provider.sh`
- Modify: `scripts/orchestration/run-quality-providers.sh`
- Modify: `tests/orchestration/test-run-evidence-provider.sh`

- [ ] **Step 1: Add failing multi-repository command-provider tests**

Configure one command provider for `app-a` and `app-b`, put both in scope, and
run `run-quality-providers.sh`. Assert two immutable evidence records exist,
each with one `coverage.repository_ids` value and only that repository subject.

- [ ] **Step 2: Run the provider test and verify RED**

```bash
bash tests/orchestration/test-run-evidence-provider.sh
```

Expected: only the provider’s first configured repository runs and its evidence
claims the full feature scope.

- [ ] **Step 3: Add explicit repository targeting**

Add `--repository <id>` to `run-evidence-provider.sh`. Validate that the ID is
permitted by the provider’s `repository_ids` or `repository_role`. Resolve only
that repository, include it in the evidence ID/run path, and emit only its
subject and coverage ID.

- [ ] **Step 4: Loop command providers over scoped targets**

For each required command provider, intersect its configured targets with
`scope.json`, sort repository IDs, and invoke the provider once per target.
Include the repository ID in the run ID so immutable evidence cannot collide.

- [ ] **Step 5: Run the provider test and verify GREEN**

Run the focused test. Expected: PASS.

- [ ] **Step 6: Commit command-provider scoping**

```bash
git add scripts/orchestration/run-evidence-provider.sh scripts/orchestration/run-quality-providers.sh tests/orchestration/test-run-evidence-provider.sh
git commit -m "Scope command evidence to executed repositories"
```

### Task 4: Aggregate evidence per provider and repository

**Files:**

- Modify: `scripts/orchestration/jq/resolve-gates.jq`
- Modify: `scripts/orchestration/jq/evaluate-readiness.jq`
- Modify: `tests/orchestration/test-evaluate-readiness-core.sh`
- Create: `tests/orchestration/test-evaluate-readiness-aggregation.sh`

- [ ] **Step 1: Add failing two-repository verifier aggregation tests**

Create a gate whose verifier targets `app-a` and `app-b`. Prove these cases:

```text
only app-b passed                         => incomplete
app-a failed and later app-b passed       => failed
app-a passed and app-b passed             => ready
app-a passed for a stale app-a subject    => incomplete
```

Each record explicitly covers one repository.

- [ ] **Step 2: Add failing provider-strategy tests**

For two providers targeting one repository, prove:

```text
strategy all + one pass                   => incomplete
strategy all + two passes                 => ready
strategy all + one fail + one pass        => failed
strategy any + one pass + one missing     => ready
strategy any + one fail + one pass        => failed
```

- [ ] **Step 3: Run aggregation tests and verify RED**

```bash
bash tests/orchestration/test-evaluate-readiness-aggregation.sh
```

Expected: latest-record selection incorrectly produces ready in at least the
single-repository-verifier and multi-provider cases.

- [ ] **Step 4: Materialize provider strategy in gate plans**

In `resolve-gates.jq`, add:

```jq
provider_strategy: ($gate.provider_strategy // "all")
```

Update the gate-plan schema accordingly.

- [ ] **Step 5: Replace global latest-record selection with grouped evaluation**

For each gate:

1. Calculate each provider’s target repository IDs from policy and scope.
2. For each provider/target pair, select the newest record that explicitly
   covers that repository, has its matching current subject, and passes current
   feature, policy, provider-digest, expiry, claim, architecture, and trust
   validation.
3. Preserve missing/stale/coverage/trust reasons per target.
4. Aggregate repository results into each provider.
5. Aggregate providers according to `provider_strategy` and fail-closed
   precedence.
6. Return sorted unique `evidence_ids`; set `evidence_id` only when the array
   contains one ID.

Use stable finding IDs that include provider and repository when relevant, for
example:

```text
EVIDENCE_MISSING:independent-verification:verifier:app-a
EVIDENCE_FAILED:focused-tests:core-tests:orchestrator
```

- [ ] **Step 6: Run aggregation and legacy evaluator tests**

```bash
bash tests/orchestration/test-evaluate-readiness-aggregation.sh
bash tests/orchestration/test-evaluate-readiness-core.sh
bash tests/orchestration/test-evaluate-readiness-trust.sh
```

Expected: PASS.

- [ ] **Step 7: Commit deterministic aggregation**

```bash
git add scripts/orchestration/jq schemas/quality-gate-plan.schema.json tests/orchestration/test-evaluate-readiness-core.sh tests/orchestration/test-evaluate-readiness-aggregation.sh
git commit -m "Aggregate evidence across providers and repositories"
```

### Task 5: Render every selected evidence record

**Files:**

- Modify: `scripts/orchestration/jq/render-readiness.jq`
- Modify: `scripts/orchestration/jq/render-pr-summary.jq`
- Modify: `tests/orchestration/test-render-quality-reports.sh`
- Modify: `tests/fixtures/quality/expected-readiness.md`
- Modify: `tests/fixtures/quality/expected-pr-summary.md`

- [ ] **Step 1: Add failing report assertions**

Give one gate two `evidence_ids` and assert both appear in readiness and PR
summary output in sorted order.

- [ ] **Step 2: Run report tests and verify RED**

```bash
bash tests/orchestration/test-render-quality-reports.sh
```

Expected: only the legacy singular evidence ID is rendered.

- [ ] **Step 3: Render evidence arrays compatibly**

Use `(.evidence_ids // ([.evidence_id] | map(select(. != null))))` everywhere
reports render gate evidence. Do not collapse multiple IDs into one.

- [ ] **Step 4: Run report tests and verify GREEN**

Run the focused test. Expected: PASS.

- [ ] **Step 5: Commit report provenance**

```bash
git add scripts/orchestration/jq/render-readiness.jq scripts/orchestration/jq/render-pr-summary.jq tests/orchestration/test-render-quality-reports.sh tests/fixtures/quality
git commit -m "Report all evidence selected for each gate"
```

### Task 6: Make GitHub collection rerunnable and fail closed

**Files:**

- Modify: `scripts/orchestration/collect-github-evidence.sh`
- Modify: `tests/orchestration/test-collect-github-evidence.sh`

- [ ] **Step 1: Add failing rerun regression**

Run the collector with `gh-run-1`, then again with `gh-run-2`. Assert both sets
of immutable evidence exist and the second run does not read first-run payloads
as snapshots.

- [ ] **Step 2: Add failing empty-check regression**

Add a valid snapshot with `"checks": {}` and assert its source-control evidence
has `result: blocked` and a stable known gap explaining that no checks were
collected.

- [ ] **Step 3: Run collector tests and verify RED**

```bash
bash tests/orchestration/test-collect-github-evidence.sh
```

Expected: rerun fails the head check and empty checks pass.

- [ ] **Step 4: Separate snapshot input and payload output**

Discover sorted snapshot JSON files under `state/github/`, excluding
`*.payload.json`, and validate `repository_id`, `pull_request.head_oid`, and
`checks` before use. Write payloads under:

```text
state/provider-runs/<run-id>/source-control/<repository-id>/
```

- [ ] **Step 5: Implement nonempty check evaluation**

Use this ordering:

```jq
if (.checks | length) == 0 then "blocked"
elif ([.checks[].status] | any(. == "red")) then "failed"
elif ([.checks[].status] | all(. == "green")) then "passed"
else "blocked"
end
```

Emit repository-scoped subject and coverage fields for both checks and
approval evidence.

- [ ] **Step 6: Run collector tests and verify GREEN**

Run the focused test. Expected: PASS for rerun and empty-check cases.

- [ ] **Step 7: Commit collector safety**

```bash
git add scripts/orchestration/collect-github-evidence.sh tests/orchestration/test-collect-github-evidence.sh
git commit -m "Make GitHub evidence collection fail closed"
```

### Task 7: Correct the active overlay and dogfood false-ready paths

**Files:**

- Modify: `overlays/quality/policy.json`
- Modify: `overlays/quality/adopter-implementation-plan.md`
- Modify: `tests/orchestration/test-active-quality-overlay.sh`
- Modify: `tests/orchestration/test-quality-dogfood.sh`
- Modify: `tests/fixtures/quality/dogfood/scenarios.json`
- Modify: `docs/runbooks/feature-evidence-quality-gates.md`

- [ ] **Step 1: Add failing overlay assertion**

Require the `orchestrator-focused-tests` gate to contain:

```json
"provider_strategy": "all"
```

and all three provider IDs.

- [ ] **Step 2: Add adversarial dogfood scenarios**

Add deterministic scenarios for:

- one verifier passing only the last repository;
- a later pass attempting to hide an earlier repository failure;
- only scheduled-trigger tests passing;
- source-control evidence with no checks.

Assert none become ready.

- [ ] **Step 3: Run focused tests and verify RED**

```bash
bash tests/orchestration/test-active-quality-overlay.sh
bash tests/orchestration/test-quality-dogfood.sh
```

- [ ] **Step 4: Set active provider aggregation and update documentation**

Set the orchestrator focused gate to `all`. Document explicit provider
strategy, repository coverage, historical evidence recollection, exact
verifier subjects, and empty-check blocking.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run both focused tests. Expected: PASS.

- [ ] **Step 6: Commit adopter correction**

```bash
git add overlays/quality tests/orchestration/test-active-quality-overlay.sh tests/orchestration/test-quality-dogfood.sh tests/fixtures/quality/dogfood docs/runbooks/feature-evidence-quality-gates.md
git commit -m "Dogfood fail-closed evidence aggregation"
```

### Task 8: Full verification and corrective PR

**Files:**

- Modify only if verification exposes a scoped defect.

- [ ] **Step 1: Run the full orchestration suite**

```bash
bash tests/orchestration/run-all.sh
```

Expected: every orchestration test passes, including adversarial aggregation
and rerun scenarios.

- [ ] **Step 2: Validate every shell script and JSON file**

```bash
find scripts tests -type f -name '*.sh' -exec bash -n {} +
find schemas config overlays tests/fixtures/quality -type f -name '*.json' -exec jq empty {} +
git diff --check origin/main...HEAD
```

Expected: all commands exit zero.

- [ ] **Step 3: Review requirements against the diff**

Confirm all five review findings have a red-green regression, evidence reports
show all selected IDs, old evidence without repository coverage cannot satisfy
current gates, and no product-specific command entered generic code.

- [ ] **Step 4: Push the corrective branch**

```bash
git push -u origin codex/fix-quality-evidence-aggregation
```

- [ ] **Step 5: Create a ready corrective PR**

Create a PR against `main` titled:

```text
Fix fail-open quality evidence aggregation
```

The body must identify all five corrected findings, explain repository and
provider aggregation semantics, state that Galust remains in observe mode, and
list the exact verification commands and results.
