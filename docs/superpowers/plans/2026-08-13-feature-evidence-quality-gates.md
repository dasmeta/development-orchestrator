# Feature Evidence Quality Gates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a product-agnostic, multi-repository evidence ledger and deterministic quality loop that lets autonomous agents repair implementation failures until configured stage, merge, and release gates are proved.

**Architecture:** The control repository owns versioned record contracts, scope capture, policy resolution, immutable evidence ingestion, deterministic evaluation, provider orchestration, repair briefs, and derived reports. Product forks supply impact rules, trusted providers, architecture sources, and enforcement modes; child repositories retain product truth and detailed test artifacts.

**Tech Stack:** Bash 3.2+, `jq`, Git, GitHub CLI compatibility, repository-configured provider and verifier commands, Markdown, JSON Schema.

---

## Execution scope and invariants

This plan writes only to the development-orchestrator control repository. It
may configure commands that already exist in child repositories, but it does
not modify those repositories. Missing child capabilities become explicit
observe-mode findings and separate repository-owned follow-up plans.

- Generic engine files contain no product names, fixed child paths, test
  frameworks, CI vendors, or closed evidence-type enums.
- Product behavior stays in the configured intent source; contracts and
  architecture stay with their configured owners.
- Only trusted authority providers satisfy intent approval, architecture
  approval, or waivers.
- Derived state is regenerable; evidence and waivers are immutable.
- Worktree evidence may satisfy `stage-ready`; `merge-ready` requires commits.
- Implementation runs cannot satisfy independent verification or blocking
  architecture conformance.
- Existing commands remain compatible in `off` and `observe` modes.

## File map

New generic contracts:

- `schemas/quality-policy.schema.json`
- `schemas/feature-scope.schema.json`
- `schemas/feature-claims.schema.json`
- `schemas/feature-architecture.schema.json`
- `schemas/feature-evidence.schema.json`
- `schemas/feature-waiver.schema.json`
- `schemas/feature-readiness.schema.json`
- `schemas/feature-release-record.schema.json`
- `schemas/repair-brief.schema.json`
- `schemas/verifier-result.schema.json`
- `schemas/quality-gate-plan.schema.json`

New generic implementation:

- `scripts/orchestration/lib/quality_config.sh`
- `scripts/orchestration/lib/quality_records.sh`
- `scripts/orchestration/lib/git_subject.sh`
- `scripts/orchestration/jq/resolve-gates.jq`
- `scripts/orchestration/jq/evaluate-readiness.jq`
- `scripts/orchestration/jq/render-readiness.jq`
- `scripts/orchestration/jq/render-pr-summary.jq`
- `scripts/orchestration/capture-feature-scope.sh`
- `scripts/orchestration/validate-quality-record.sh`
- `scripts/orchestration/ingest-evidence.sh`
- `scripts/orchestration/ingest-waiver.sh`
- `scripts/orchestration/resolve-quality-gates.sh`
- `scripts/orchestration/evaluate-readiness.sh`
- `scripts/orchestration/render-quality-reports.sh`
- `scripts/orchestration/archive-feature-evidence.sh`
- `scripts/orchestration/run-evidence-provider.sh`
- `scripts/orchestration/run-quality-providers.sh`
- `scripts/orchestration/collect-github-evidence.sh`
- `scripts/orchestration/run-independent-verifier.sh`
- `scripts/orchestration/run-quality-cycle.sh`
- `scripts/orchestration/migrate-feature-quality-v1.sh`

New templates and adopter surfaces:

- `templates/features/scope.json`
- `templates/features/claims.json`
- `templates/features/architecture.json`
- `templates/quality/verifier-prompt.md`
- `overlays/quality/policy.json`
- `overlays/quality/README.md`
- `overlays/quality/adopter-implementation-plan.md`

Existing files modified during the plan:

- `scripts/orchestration/init-feature.sh`
- `scripts/orchestration/render-manifest.sh`
- `scripts/orchestration/advance-stage.sh`
- `scripts/orchestration/evaluate-mergeability.sh`
- `scripts/orchestration/collect-github-state.sh`
- `scripts/orchestration/run-speckit-stage.sh`
- `scripts/orchestration/lib/feature_paths.sh`
- `scripts/orchestration/lib/workspace_config.sh`
- `schemas/feature-manifest.schema.json`
- `config/workspace.example.json`
- `config/workspace.json`
- `.github/workflows/control-repo-ci.yml`
- `README.md`, `AI-INDEX.md`, `TODO.md`
- `docs/runbooks/development-orchestration.md`
- `tests/helpers/assert.sh`
- `tests/orchestration/test-template-agnostic.sh`

## Dependency sequence

```text
policy -> ledger -> subjects -> ingestion -> gate resolution -> evaluation
       -> reports -> providers -> GitHub/authority -> verifier -> repair loop
       -> lifecycle integration -> adopter observe mode -> dogfood -> enforce
```

## Phase A: Contracts and deterministic state

### Task 1: Add the quality policy contract and resolver

**Files:**

- Create: `schemas/quality-policy.schema.json`
- Create: `scripts/orchestration/lib/quality_config.sh`
- Create: `tests/orchestration/test-quality-config.sh`
- Modify: `scripts/orchestration/lib/workspace_config.sh`
- Modify: `config/workspace.example.json`

- [ ] **Step 1: Write failing compatibility tests**

Test that a legacy config resolves to `mode=off`, a referenced policy resolves
relative to the workspace config, and duplicate gate IDs or newline command
arguments fail validation.

```bash
assert_equals "off" "$(workspace_quality_mode "$legacy_config")"
assert_equals "$tmp_dir/overlays/quality/policy.json" \
  "$(workspace_quality_policy_path "$valid_config")"
assert_command_fails validate_quality_policy "$invalid_policy"
```

- [ ] **Step 2: Run `bash tests/orchestration/test-quality-config.sh`**

Expected: failure because quality config helpers do not exist.

- [ ] **Step 3: Define the policy schema around this exact logical shape**

```json
{
  "schema_version": "1",
  "policy_version": "1",
  "protected_path_regex": ["(^|/)evidence/", "(^|/)waivers/"],
  "impact_rules": [{
    "id": "implementation-change",
    "when": {"repository_ids_any": [], "repository_roles_any": ["implementation"], "path_regex_any": ["(^|/)src/"]},
    "add_impacts": ["implementation"]
  }],
  "gates": [{
    "id": "focused-tests",
    "decisions": ["stage-ready", "merge-ready"],
    "when": {"impacts_any": ["implementation"]},
    "evidence_types": ["focused-tests"],
    "providers": ["repository-tests"],
    "coverage": {"claims": "all", "architecture": "none"},
    "required_result": "passed"
  }],
  "providers": {
    "repository-tests": {
      "kind": "command",
      "trust": "repository-check",
      "producer_role": "verification",
      "repository_role": "implementation",
      "repository_ids": [],
      "working_directory": ".",
      "command": ["scripts/quality/focused-tests.sh"],
      "output_mode": "exit-code"
    }
  },
  "decisions": {
    "stage-ready": {"require_gates": ["focused-tests"]},
    "merge-ready": {"require_gates": ["focused-tests"]},
    "release-ready": {"require_gates": []}
  },
  "release_archive": {"kind": "filesystem", "destination": "workspace/quality-archive"},
  "budgets": {"provider_retries": 1, "repair_attempts": 3}
}
```

Provider kinds are `command`, `external-import`, `source-control`, and
`verifier`. Evidence types remain open strings. Claim coverage is `none|all`;
architecture coverage is `none|all|all_blocking`. Providers may target a role,
explicit repository IDs, or both. Release archive kind is `filesystem` or
`command` and its destination resolves relative to the workspace config.

- [ ] **Step 4: Implement resolver and validator**

```bash
workspace_quality_mode() { jq -r '.quality.mode // "off"' "$1"; }

resolve_config_relative_path() {
  local config_path="$1" configured_path="$2" config_dir
  config_dir="$(cd "$(dirname "$config_path")" && pwd)"
  if [[ "$configured_path" = /* ]]; then
    printf '%s\n' "$configured_path"
  else
    printf '%s\n' "$config_dir/$configured_path"
  fi
}

workspace_quality_policy_path() {
  local config_path="$1" policy
  policy="$(jq -r '.quality.policy // empty' "$config_path")"
  [[ -n "$policy" ]] || return 1
  resolve_config_relative_path "$config_path" "$policy"
}

validate_quality_policy() {
  jq -e '
    .schema_version == "1" and
    ([.impact_rules[].id] | length == (unique | length)) and
    ([.gates[].id] | length == (unique | length)) and
    ([.providers[].command[]? | contains("\n")] | any | not)
  ' "$1" >/dev/null
}
```

Cross-check gate/provider/decision references in shell validation. Missing
`.quality` remains valid and off.

- [ ] **Step 5: Add an inert example reference and verify**

Add `"quality":{"mode":"off","policy":"../overlays/quality/policy.json"}`
to the example config. Run:

```bash
bash tests/orchestration/test-quality-config.sh
bash tests/orchestration/test-template-agnostic.sh
```

Expected: pass. Commit with
`git commit -m "Add product-agnostic quality policy contract"`.

### Task 2: Initialize versioned feature-ledger inputs

**Files:**

- Create: all `feature-*.schema.json` files listed in the file map
- Create: `schemas/repair-brief.schema.json`
- Create: `templates/features/scope.json`
- Create: `templates/features/claims.json`
- Create: `templates/features/architecture.json`
- Modify: `scripts/orchestration/init-feature.sh`
- Modify: `scripts/orchestration/lib/feature_paths.sh`
- Modify: `tests/orchestration/test-init-feature.sh`

- [ ] **Step 1: Extend the init test before implementation**

```bash
assert_file_exists "$feature_dir/scope.json"
assert_file_exists "$feature_dir/claims.json"
assert_file_exists "$feature_dir/architecture.json"
assert_directory_exists "$feature_dir/evidence"
assert_directory_exists "$feature_dir/waivers"
assert_directory_exists "$feature_dir/state/runs"
```

Run the test. Expected: missing ledger files.

- [ ] **Step 2: Create exact initial templates**

```json
{"schema_version":"1","feature_id":"{{FEATURE_ID}}","repositories":[],"explicit_impacts":[],"derived_impacts":[],"policy_version":null}
```

```json
{"schema_version":"1","feature_id":"{{FEATURE_ID}}","claims":[]}
```

```json
{"schema_version":"1","feature_id":"{{FEATURE_ID}}","sources":[],"constraints":[]}
```

- [ ] **Step 3: Define the normalized evidence envelope**

Require these fields in `feature-evidence.schema.json`:

```json
{
  "schema_version":"1",
  "evidence_id":"EV-run-1",
  "feature_id":"FEAT-0001",
  "evidence_type":"focused-tests",
  "provider_id":"repository-tests",
  "producer":{"id":"ci","role":"verification","run_id":"run-1"},
  "coverage":{"claim_ids":["AC-1"],"architecture_constraint_ids":[]},
  "subject":{"repositories":{"implementation":"commit:abc"}},
  "policy_version":"1",
  "provider_config_digest":"git-blob:abc",
  "result":"passed",
  "outcome":"completed",
  "environment":{"id":"local","fixture":null},
  "collected_at":"2026-08-13T00:00:00Z",
  "expires_at":null,
  "artifacts":[],
  "findings":[],
  "known_gaps":[]
}
```

Evidence results are `passed|failed|blocked`; decision statuses are
`ready|incomplete|failed|blocked`; architecture enforcement is
`blocking|advisory`.

- [ ] **Step 4: Add path helpers and initialization**

```bash
feature_scope_path() { echo "$1/scope.json"; }
feature_claims_path() { echo "$1/claims.json"; }
feature_architecture_path() { echo "$1/architecture.json"; }
feature_evidence_dir() { echo "$1/evidence"; }
feature_waiver_dir() { echo "$1/waivers"; }
feature_readiness_path() { echo "$1/state/readiness.json"; }
feature_repair_brief_path() { echo "$1/state/repair-brief.json"; }
```

Create `evidence`, `waivers`, `state/runs`, and `state/provider-runs`, then
render all templates with the existing renderer.

- [ ] **Step 5: Run and commit**

Run `bash tests/orchestration/test-init-feature.sh` and `git diff --check`.
Expected: pass. Commit with
`git commit -m "Initialize feature evidence ledgers"`.

### Task 3: Capture committed and worktree subjects

**Files:**

- Create: `scripts/orchestration/lib/git_subject.sh`
- Create: `scripts/orchestration/capture-feature-scope.sh`
- Create: `tests/orchestration/test-capture-feature-scope.sh`
- Modify: `schemas/feature-scope.schema.json`

- [ ] **Step 1: Write tests using temporary Git repositories**

Assert committed captures use `commit:<oid>`, dirty captures use
`worktree:<digest>`, paths are sorted, untracked content changes the digest,
and identical recapture is stable after removing `captured_at`.

- [ ] **Step 2: Run the test**

Run `bash tests/orchestration/test-capture-feature-scope.sh`. Expected: missing
capture command.

- [ ] **Step 3: Implement canonical hashing**

```bash
stdin_digest() {
  git -C "$control_repo_root" hash-object --stdin | sed 's/^/git-blob:/'
}
```

For worktrees, hash canonical JSON containing HEAD, a binary-diff digest, and
sorted untracked `{path,blob_digest}` entries. Do not call `git write-tree`.

- [ ] **Step 4: Implement deterministic scope replacement**

Resolve repositories through workspace config. Use `git diff --name-only
--no-renames <base> <head>` for commits; add untracked files for `WORKTREE`.
Replace only the matching repository record and sort by repository ID.

- [ ] **Step 5: Run and commit**

Run:

```bash
bash tests/orchestration/test-capture-feature-scope.sh
bash tests/orchestration/test-init-feature.sh
```

Expected: pass. Commit with
`git commit -m "Capture revision-bound feature scope"`.

### Task 4: Validate and immutably ingest evidence and waivers

**Files:**

- Create: `scripts/orchestration/lib/quality_records.sh`
- Create: `scripts/orchestration/validate-quality-record.sh`
- Create: `scripts/orchestration/ingest-evidence.sh`
- Create: `scripts/orchestration/ingest-waiver.sh`
- Create: `tests/orchestration/test-ingest-quality-records.sh`
- Create: `tests/fixtures/quality/evidence-payload-passed.json`
- Create: `tests/fixtures/quality/waiver-valid.json`
- Modify: `tests/helpers/assert.sh`

- [ ] **Step 1: Write failing ingestion tests**

Cover valid evidence, malformed records, provider/type mismatch, duplicate ID,
overwrite attempt, and waiver ingestion without authority evidence.

- [ ] **Step 2: Add exact assertion helpers**

```bash
fail() { echo "$*" >&2; exit 1; }
assert_equals() { [[ "$1" == "$2" ]] || fail "expected '$1', got '$2'"; }
assert_directory_exists() { [[ -d "$1" ]] || fail "missing directory: $1"; }
assert_command_fails() { if "$@"; then fail "unexpected pass: $*"; fi; }
```

Run the ingestion test. Expected: missing commands.

- [ ] **Step 3: Implement explicit structural validators**

Reject invalid IDs, enums, arrays, feature IDs, and absolute local artifact
paths for merge/release evidence. Use `^[A-Za-z0-9][A-Za-z0-9._:-]*$` for IDs.

```bash
jq -e '
  (.result | IN("passed","failed","blocked")) and
  (.coverage.claim_ids | type == "array") and
  (.coverage.architecture_constraint_ids | type == "array") and
  (.findings | type == "array") and (.known_gaps | type == "array")
' "$input" >/dev/null
```

- [ ] **Step 4: Stamp provider identity and write immutably**

Resolve provider kind, trust, role, evidence types, policy version, and config
digest from trusted policy. Ignore payload identity. Authority providers require
`QUALITY_AUTHORITY_COLLECTION=1`. Write to a temporary file, fail if the final
ID exists, then atomically `mv`. Waivers require an existing authority evidence
ID and exact scope.

- [ ] **Step 5: Run and commit**

Run `bash tests/orchestration/test-ingest-quality-records.sh` and
`git diff --check`. Expected: pass. Commit with
`git commit -m "Ingest immutable feature evidence"`.

### Task 5: Resolve impacts and applicable gates

**Files:**

- Create: `scripts/orchestration/jq/resolve-gates.jq`
- Create: `scripts/orchestration/resolve-quality-gates.sh`
- Create: `schemas/quality-gate-plan.schema.json`
- Create: `tests/orchestration/test-resolve-quality-gates.sh`

- [ ] **Step 1: Write table-driven selector tests**

Cover role-only, path regex, explicit additive impacts, documentation-only,
architecture-sensitive, and missing-provider ambiguity. Explicit impacts may
add but never remove derived impacts.

- [ ] **Step 2: Run the test**

Run `bash tests/orchestration/test-resolve-quality-gates.sh`. Expected: missing
resolver.

- [ ] **Step 3: Implement AND-between-groups, ANY-within-group semantics**

```jq
def matches_role($scope; $roles):
  ($roles | length == 0) or
  any($scope.repositories[]?; .role as $r | $roles | index($r));
def matches_repo($scope; $ids):
  ($ids | length == 0) or
  any($scope.repositories[]?; .id as $id | $ids | index($id));
def matches_path($scope; $patterns):
  ($patterns | length == 0) or
  any($scope.repositories[].changed_paths[]?; . as $p |
    any($patterns[]; $p | test(.)));
def rule_matches($scope; $rule):
  matches_repo($scope; ($rule.when.repository_ids_any // [])) and
  matches_role($scope; ($rule.when.repository_roles_any // [])) and
  matches_path($scope; ($rule.when.path_regex_any // []));
```

Sort impacts/gates, record source rules and not-applicable reasons, and emit
stable `POLICY_*` findings for unresolved references.

- [ ] **Step 4: Write `state/gate-plan.json` atomically**

Validate policy/scope before invoking jq. Accept `--now` for tests; timestamps
must not participate in the subject fingerprint.

- [ ] **Step 5: Run and commit**

Run the resolver and config tests. Expected: pass. Commit with
`git commit -m "Resolve product-configured quality gates"`.

### Task 6: Evaluate evidence validity, coverage, and status

**Files:**

- Create: `scripts/orchestration/jq/evaluate-readiness.jq`
- Create: `scripts/orchestration/evaluate-readiness.sh`
- Create: `tests/orchestration/test-evaluate-readiness-core.sh`
- Modify: `schemas/feature-readiness.schema.json`
- Modify: `schemas/repair-brief.schema.json`

- [ ] **Step 1: Write status-precedence fixtures**

Cover ready, missing, malformed, stale, wrong revision, failed, blocked,
unknown applicability, and mixed states. Enforce
`failed > blocked > incomplete > ready`, while preserving every lower-priority
finding.

- [ ] **Step 2: Run `bash tests/orchestration/test-evaluate-readiness-core.sh`**

Expected: missing evaluator.

- [ ] **Step 3: Implement pure evidence selection**

Load policy, gate plan, scope, claims, architecture, evidence, and waivers with
`jq --slurpfile`. Per gate: reject disallowed provider/type, stale policy or
provider digest, wrong subject, expired evidence, and incomplete coverage.
Select newest valid evidence by `collected_at` then `evidence_id`.

```json
{"id":"EVIDENCE_MISSING:focused-tests","class":"evidence","owner":"implementation","gate_id":"focused-tests","message":"No valid evidence satisfies gate focused-tests"}
```

- [ ] **Step 4: Emit readiness and a bounded repair brief**

`evaluate-readiness.sh --decision <id> --now <RFC3339>` writes readiness and
repair JSON. Repair briefs contain only repairable findings, owner, affected
claims/constraints, and allowed responsibility. Authority/policy findings set
`human_action_required=true` and authorize no edits.

- [ ] **Step 5: Prove determinism and commit**

Run twice with identical `--now`; compare `jq -S` output using `cmp`. Run the
core test. Expected: pass. Commit with
`git commit -m "Evaluate feature readiness from evidence"`.

### Task 7: Enforce authority, architecture, independence, and waivers

**Files:**

- Create: `tests/orchestration/test-evaluate-readiness-trust.sh`
- Modify: `scripts/orchestration/jq/evaluate-readiness.jq`
- Modify: `scripts/orchestration/ingest-waiver.sh`
- Modify: `schemas/feature-architecture.schema.json`
- Modify: `schemas/feature-waiver.schema.json`

- [ ] **Step 1: Add adversarial tests**

Test non-authority approval, missing blocking architecture proof, advisory
findings, implementation self-certification, distinct verifier success,
architecture impact without governed source, and invalid waivers.

- [ ] **Step 2: Implement coverage and independence after observing failures**

```jq
def covers_all($required; $actual): ($required - $actual) | length == 0;
def independent($implementation_runs; $e):
  ($e.producer.role != "implementation") and
  (($implementation_runs | index($e.producer.run_id)) == null);
```

Require all blocking architecture IDs; preserve advisory findings. Emit
`ARCHITECTURE_SOURCE_UNRESOLVED` when architecture impact lacks a governed
source.

- [ ] **Step 3: Apply exact waivers after normal evaluation**

Verify authority, feature, gate/finding, subjects, environment, issuance, and
expiry. Mark only the named gate waived and retain reason, approver, and risk.

- [ ] **Step 4: Run and commit**

Run core and trust tests. Expected: pass. Commit with
`git commit -m "Enforce quality evidence trust boundaries"`.

## Phase B: Reports and provider adapters

### Task 8: Render readiness and PR summaries from one decision

**Files:**

- Create: `scripts/orchestration/jq/render-readiness.jq`
- Create: `scripts/orchestration/jq/render-pr-summary.jq`
- Create: `scripts/orchestration/render-quality-reports.sh`
- Create: `tests/orchestration/test-render-quality-reports.sh`
- Create: `tests/fixtures/quality/expected-readiness.md`
- Create: `tests/fixtures/quality/expected-pr-summary.md`
- Create: `scripts/orchestration/archive-feature-evidence.sh`
- Create: `tests/orchestration/test-archive-feature-evidence.sh`
- Create: `schemas/feature-release-record.schema.json`

- [ ] **Step 1: Write snapshots containing failures and waivers**

Include revisions, failed gate, blocked visual evidence, advisory architecture,
documentation disposition, gap, and waiver. Assert every finding ID is in both
outputs.

- [ ] **Step 2: Implement deterministic readiness sections**

```markdown
# Readiness: FEAT-0001 / merge-ready

- Status: `blocked`

## Repository subjects
## Acceptance coverage
## Architecture conformance
## Gate results
## Documentation disposition
## Failures and blockers
## Known gaps
## Waivers
## Evidence
```

Escape provider text and sort by stable ID.

- [ ] **Step 3: Implement the PR-summary renderer**

Include outcome, subjects, contract/implementation/architecture impact,
applicable test/visual/E2E evidence, documentation, failures, blockers, gaps,
waivers, and decision. Refuse stale fingerprints.

- [ ] **Step 4: Run and commit**

Before committing, implement lightweight release retention. The archive command
requires `release-ready`, writes a canonical record containing policy/schema
versions, repository subjects, claims, architecture constraints, selected
evidence metadata, artifact references/digests, waivers, and final decision,
then sends it to a configured storage command or filesystem destination. It
must never copy large provider artifacts into the ledger.

Test idempotent identical archives, refusal of non-release-ready state, and
failure when configured durable storage is unavailable.

Run both report and archive tests. Expected: pass.
Commit with `git commit -m "Render evidence-grounded readiness reports"`.

### Task 9: Run configured evidence providers safely

**Files:**

- Create: `scripts/orchestration/run-evidence-provider.sh`
- Create: `scripts/orchestration/run-quality-providers.sh`
- Create: `tests/orchestration/test-run-evidence-provider.sh`
- Create: `tests/fixtures/quality/bin/fake-pass-provider`
- Create: `tests/fixtures/quality/bin/fake-fail-provider`
- Create: `tests/fixtures/quality/bin/fake-json-provider`

- [ ] **Step 1: Write provider contract tests**

Cover `exit-code`, `evidence-json`, nonzero execution, malformed JSON,
provider/type mismatch, unknown provider, directory escape, and spaced argv.

- [ ] **Step 2: Execute trusted arrays without `eval`**

```bash
command_args=()
while IFS= read -r arg; do command_args+=("$arg"); done \
  < <(jq -r --arg id "$provider_id" '.providers[$id].command[]' "$policy")
set +e
(cd "$working_dir" && "${command_args[@]}") >"$stdout_path" 2>"$stderr_path"
exit_code=$?
set -e
```

Reject working directories outside the configured repository root.

- [ ] **Step 3: Normalize, ingest, and select providers**

For `exit-code`, synthesize passed/failed evidence with log digests. For
`evidence-json`, validate stdout. Always ingest through the immutable command.
The multi-provider runner reads the gate plan, deduplicates providers, skips
external imports, and retries blocked execution only.

- [ ] **Step 4: Run and commit**

Run provider and ingestion tests. Expected: pass. Commit with
`git commit -m "Run product-configured evidence providers"`.

### Task 10: Collect multi-repository GitHub evidence and approvals

**Files:**

- Create: `scripts/orchestration/collect-github-evidence.sh`
- Create: `tests/orchestration/test-collect-github-evidence.sh`
- Modify: `scripts/orchestration/collect-github-state.sh`
- Modify: `tests/orchestration/test-collect-github-state-live.sh`
- Modify: `tests/fixtures/github/pr-approved.json`

- [ ] **Step 1: Test two repositories with a fake `gh`**

Assert separate snapshots, head OIDs, check URLs, reviewers, and immutable
check/authority evidence.

- [ ] **Step 2: Expand the query compatibly**

```bash
gh pr view "$pr_number" --repo "$repo" \
  --json reviewDecision,mergeStateStatus,statusCheckRollup,url,headRefName,headRefOid,latestReviews
```

Add `--repo-id`; retain legacy output when absent.

- [ ] **Step 3: Normalize checks and authority**

Bind checks to `commit:<headRefOid>` and retain URLs. For human authority,
require approved review decision plus an approved latest review; stamp reviewer
and PR URL through `QUALITY_AUTHORITY_COLLECTION=1`. Enforce mode cannot use
fixtures.

- [ ] **Step 4: Prove merge-ready is pre-merge and commit**

Test `merged=false` with valid evidence and expect ready. Run all GitHub tests.
Commit with `git commit -m "Collect revision-bound GitHub evidence"`.

### Task 11: Add a separate read-only verifier adapter

**Files:**

- Create: `schemas/verifier-result.schema.json`
- Create: `templates/quality/verifier-prompt.md`
- Create: `scripts/orchestration/run-independent-verifier.sh`
- Create: `tests/orchestration/test-run-independent-verifier.sh`

- [ ] **Step 1: Define and test exact output**

```json
{"result":"passed","covered_claim_ids":["AC-1"],"covered_architecture_constraint_ids":["ARCH-1"],"architecture_disposition":"not_applicable","documentation_disposition":"updated","artifact_references":[],"findings":[],"known_gaps":[]}
```

Dispositions are `updated|not_applicable|blocked`; updated requires an artifact.
Use a fake configured verifier executable in tests. An `updated` disposition
must include an artifact reference, for example:

```json
{"uri":"changes/FEAT-0001.md","digest":"git-blob:abc"}
```

- [ ] **Step 2: Build an adversarial prompt**

Include intake, scope, claims, architecture, gate plan, subjects, and diff.
Require no edits, no invented behavior, and no applicability downgrade.

- [ ] **Step 3: Run a distinct configured read-only invocation**

```bash
run_configured_verifier \
  --provider "$provider_id" \
  --repository "$target_repository" \
  --prompt "$prompt_path" \
  --schema "$repo_root/schemas/verifier-result.schema.json" \
  --result "$result_path"
```

Resolve the verifier argv array from trusted policy and substitute only the
fixed tokens `{repository}`, `{prompt}`, `{schema}`, and `{result}`. Reject
unknown tokens, shell evaluation, and a provider that does not declare a
read-only trust profile. Generate a distinct run ID, split applicable evidence
types, and ingest through configured verifier providers.

- [ ] **Step 4: Prove self-certification rejection and commit**

Test matching implementation run IDs are rejected and separate runs pass. Run
verifier and trust tests. Commit with
`git commit -m "Add independent read-only verification adapter"`.

## Phase C: Autonomous repair and lifecycle enforcement

### Task 12: Make stage execution auditable and repair-brief aware

**Files:**

- Modify: `scripts/orchestration/run-speckit-stage.sh`
- Modify: `tests/orchestration/test-run-speckit-stage.sh`
- Modify: `tests/orchestration/test-run-speckit-stage-live.sh`
- Modify: `scripts/orchestration/lib/feature_paths.sh`

- [ ] **Step 1: Write run-history and scope tests**

Assert each invocation writes `state/runs/<run-id>.json`, legacy
`run-log.json` reflects the latest run, repair prompts contain finding IDs and
protected surfaces, protected-path changes are detected, and briefs targeting
another repository fail.

- [ ] **Step 2: Add runner arguments**

Support `--run-id`, `--repair-brief`, and
`--sandbox read-only|workspace-write`. Resolve repair ownership against the
stage repository before invoking the configured repair agent.

- [ ] **Step 3: Add the bounded repair instruction**

```text
Repair only the findings in the attached repair brief.
Do not modify approved claims, architecture constraints, validation sources,
quality policy, provider configuration, waivers, or evidence records.
If one of those must change, stop and report the owning stage.
```

Write an immutable run record with run ID, repository, stage, skill, sandbox,
finding IDs, timestamps, exit status, and dry-run flag. Copy it atomically to
legacy `run-log.json`.

Capture the target repository's before/after changed-path set. Compare newly
changed paths with policy `protected_path_regex` entries for acceptance,
architecture, validation, policy, provider, waiver, and evidence sources. Emit
`PROTECTED_PATH_CHANGED`, stop the cycle, and require human review if any match.
Repair runs must not receive the control repository through writable
`--add-dir`; intake and briefs are copied into the prompt.

- [ ] **Step 4: Run and commit**

Run both existing stage-runner tests. Expected: pass. Commit with
`git commit -m "Run bounded evidence-driven repairs"`.

### Task 13: Implement the bounded autonomous cycle

**Files:**

- Create: `scripts/orchestration/run-quality-cycle.sh`
- Create: `tests/orchestration/test-run-quality-cycle.sh`
- Create: `tests/fixtures/quality/bin/fake-repair-agent`

- [ ] **Step 1: Write the complete fake-loop test**

Prove first-run failure, claim-specific repair brief, implementation repair,
new scope fingerprint, old-evidence invalidation, affected-provider rerun,
second-run ready, nonrepairable authority/architecture stop, and budget stop.

- [ ] **Step 2: Define stable exits**

```text
0  ready, or observe-mode decision recorded
20 incomplete in enforce mode
21 failed in enforce mode
22 blocked in enforce mode
23 repair budget exhausted
24 invalid policy or ledger input
```

- [ ] **Step 3: Implement the loop in this order**

```bash
capture_required_subjects
resolve_quality_gates
run_quality_providers
run_independent_verifier_if_required
evaluate_readiness
render_quality_reports
```

Stop on ready, blocked, human action, or exhausted budget. Otherwise invoke the
configured implementation stage with the repair brief and start a new attempt.
Never mutate claims, architecture, policy, evidence, or waivers in controller
code.

- [ ] **Step 4: Respect modes and commit**

Observe mode records the real decision and returns zero unless parsing fails.
Enforce maps status to exits. Off requires `--force-evaluate`. Run the controller
plus evaluator tests. Commit with
`git commit -m "Add bounded autonomous quality cycle"`.

### Task 14: Integrate named decisions and migrate legacy features

**Files:**

- Modify: `scripts/orchestration/advance-stage.sh`
- Modify: `scripts/orchestration/evaluate-mergeability.sh`
- Modify: `scripts/orchestration/render-manifest.sh`
- Modify: `schemas/feature-manifest.schema.json`
- Modify: `templates/features/status.md`
- Create: `scripts/orchestration/migrate-feature-quality-v1.sh`
- Create: `tests/orchestration/test-quality-lifecycle-integration.sh`
- Modify: `tests/orchestration/test-advance-stage.sh`
- Modify: `tests/orchestration/test-evaluate-mergeability.sh`

- [ ] **Step 1: Test legacy, observe, enforce, and migration paths**

Cover `stage-ready`, pre-merge `merge-ready`, post-deploy `release-ready`, and a
legacy feature containing only intake, manifest, and GitHub state.

- [ ] **Step 2: Extend manifest by reference**

```json
"quality": {
  "schema_version":"1",
  "mode":"observe",
  "scope":"../scope.json",
  "claims":"../claims.json",
  "architecture":"../architecture.json",
  "gate_plan":"gate-plan.json",
  "readiness":"readiness.json",
  "current_decision":"stage-ready"
}
```

Retain legacy mergeability fields as projections.

- [ ] **Step 3: Gate stages and mergeability**

In enforce mode, require the stage's configured `advance_decision=ready` and a
current fingerprint. In observe/off or legacy config, keep `advance_when`.
When quality exists, mergeability evaluates `merge-ready` and never requires
the PR already merged; otherwise preserve legacy JSON-path evaluation.

- [ ] **Step 4: Implement idempotent migration**

Create missing v1 inputs/references without altering intake, status, or GitHub
state. Refuse unknown future versions and ambiguous destructive conversion.

- [ ] **Step 5: Run and commit**

Run lifecycle, advance, mergeability, and manifest tests. Expected: pass.
Commit with `git commit -m "Gate delivery with named evidence decisions"`.

## Phase D: Initial adopter and rollout

### Task 15: Configure an honest observe-mode adopter policy

**Files:**

- Create: `overlays/quality/policy.json`
- Create: `overlays/quality/README.md`
- Modify: `config/workspace.json`
- Create: `tests/orchestration/test-active-quality-overlay.sh`

- [ ] **Step 1: Write overlay validation first**

Assert valid schema, configured repository IDs only, no absolute paths,
`mode=observe`, and explicit unresolved visual/architecture capabilities.

- [ ] **Step 2: Configure the adopter's verified provider inventory**

Use the exact repository IDs, working directories, commands, verifier argv,
and gap ownership recorded in the fork-owned
`overlays/quality/adopter-implementation-plan.md`. Before copying a provider
into active policy, verify its working directory and command exist and run the
command once without mutation. Map providers by repository/path impact so
unrelated suites do not run.

- [ ] **Step 3: Represent gaps as external imports**

Create external-import providers for visual review, contract compatibility,
and governed architecture review. UI/contract/architecture-sensitive changes
remain incomplete until evidence arrives. Tool configuration without committed
review scenarios is not proof.

If the adopter lacks a governed engineering-architecture source, document the
owner gap and keep architecture enforcement incomplete. Implementation
documentation remains advisory until product governance promotes a source.
Verifier commands remain adopter policy; the generic runner never names an
agent product.

- [ ] **Step 4: Add impact and decision rules**

Classify UI implementation, runtime components, contracts, validation,
public-content implementation, and documentation separately. Markdown-only is
documentation unless stronger paths also change. Ingress, containers,
deployment descriptors, workflows, public APIs, persistence, authentication,
and runtime routing are architecture-sensitive. The fork-owned annex supplies
the adopter's exact repository and path mappings.

Stage-ready requires approved intent, implementation evidence, independent
verification, and documentation disposition. Merge-ready adds committed
subjects and applicable build/contract/UI proof. Release-ready adds preview or
deployed evidence and release-critical E2E. Keep mode observe.

Add an `escaped-defect` explicit impact that cannot be inferred away. It
requires authority-backed evidence that the owning intent source gained or
updated a business-readable acceptance claim and that the validation source
gained or updated its mapped regression case. An implementation test or release
note alone cannot satisfy either gate.

- [ ] **Step 5: Run and commit adopter scope separately**

Run active-overlay and template-agnostic tests. Expected: pass. Commit only
active config, overlay, and its test with
`git commit -m "Configure quality gates in observe mode"`.

### Task 16: Add complete CI and operator documentation

**Files:**

- Create: `CLAUDE.md`
- Create: `tests/orchestration/test-agent-quality-instructions.sh`
- Create: `tests/orchestration/run-all.sh`
- Create: `docs/runbooks/feature-evidence-quality-gates.md`
- Modify: `.github/workflows/control-repo-ci.yml`
- Modify: `AGENTS.md`, `README.md`, `AI-INDEX.md`, `TODO.md`
- Modify: `docs/runbooks/development-orchestration.md`
- Modify: `docs/runbooks/template-fork-contract.md`
- Modify: `tests/orchestration/test-template-agnostic.sh`

- [ ] **Step 1: Add one sorted test runner**

```bash
while IFS= read -r test_file; do
  echo "Running $test_file"
  bash "$test_file"
done < <(find "$repo_root/tests/orchestration" -maxdepth 1 -name 'test-*.sh' -print | sort)
```

- [ ] **Step 2: Make CI call only `bash tests/orchestration/run-all.sh`**

Keep live product-provider execution out of generic CI; fake providers remain
covered.

- [ ] **Step 3: Document exact workflows**

Cover initialization, scope capture, claim/architecture import, providers,
evaluation, repair cycle, reports, migration, modes, waivers, exits, and the
distinction between local stage, committed merge, and deployed release proof.

- [ ] **Step 4: Wire agent instruction discovery**

Add the product-agnostic quality lifecycle to root `AGENTS.md`, including the
stage, merge, release, mode, architecture, repair, and generated-summary rules.
Add a root `CLAUDE.md` that imports `AGENTS.md`, and test both instruction
surfaces so Codex and Claude Code receive the same lifecycle contract.

- [ ] **Step 5: Strengthen generic conformance**

Reject adopter names, child IDs, absolute paths, and product-only evidence
types from generic engine, schema, default policy, and template surfaces.
Tool-specific adapters may name their integration in adapter tests/docs but
must remain replaceable through provider configuration. Continue excluding
fork-owned active config, numeric repos, `workspace/`, and `overlays/`.

- [ ] **Step 6: Run and commit**

Run:

```bash
bash tests/orchestration/run-all.sh
git diff --check
```

Expected: all pass. Commit with
`git commit -m "Document and validate evidence quality gates"`.

### Task 17: Dogfood before enforcement

**Files:**

- Create: `tests/orchestration/test-quality-dogfood.sh`
- Create: `tests/fixtures/quality/dogfood/`
- Create: `docs/runbooks/quality-gates-enforcement-checklist.md`

- [ ] **Step 1: Add eight deterministic scenarios**

Create backend-only, UI+visual import, cross-repository contract,
documentation-only, architecture blocking/advisory, unavailable release E2E,
fail-then-repair, and escaped-defect regression-catalogue fixtures.

- [ ] **Step 2: Exercise all decisions**

```bash
bash scripts/orchestration/resolve-quality-gates.sh --feature-dir "$scenario"
bash scripts/orchestration/evaluate-readiness.sh \
  --feature-dir "$scenario" --decision stage-ready \
  --now 2026-08-13T00:00:00Z
bash scripts/orchestration/render-quality-reports.sh --feature-dir "$scenario"
```

Also evaluate merge/release where applicable. Assert status, stable findings,
and report completeness.

- [ ] **Step 3: Self-dogfood this feature**

Create `features/QUALITY-GATES-V1`, reference the approved design and plan
commits as claims, capture the control-repository candidate, run generic tests,
run the independent verifier, and evaluate stage-ready. Collect human design
approval through the authority path; never self-approve.

- [ ] **Step 4: Set enforcement criteria**

Require deterministic eight-scenario reruns, zero false-ready outcomes, correct
repair ownership, honest blocked missing providers, passing legacy commands,
and three operator-reviewed real features in observe mode. Governed
architecture and visual providers require separate approval before their gates
are enforced.

- [ ] **Step 5: Final verification and commit**

```bash
bash tests/orchestration/run-all.sh
bash scripts/orchestration/run-quality-cycle.sh \
  --feature-dir features/QUALITY-GATES-V1 \
  --decision stage-ready --force-evaluate
git status --short
git diff --check
```

The self-dogfood result may truthfully be ready, incomplete, or blocked; it
must never be forced green. Commit deterministic fixtures/checklist with
`git commit -m "Dogfood feature evidence quality gates"`.

## Completion gates

- Generic and legacy orchestration tests pass.
- Eight dogfood decisions are deterministic.
- Merge-ready works before merge and uses committed subjects.
- Implementation cannot self-certify verification or architecture.
- Reports expose every failure, blocker, gap, subject, documentation and
  architecture disposition, and waiver.
- The adopter stays observe-only until three real reviewed features complete.
- Missing architecture and visual capabilities have explicit owning follow-up
  repositories and are never weakened into passes.
- Escaped-defect changes cannot become ready without both acceptance-intent and
  mapped executable-regression evidence.

## Specification coverage review

| Approved design concern | Implemented by |
| --- | --- |
| Product-agnostic policy and provider protocol | Tasks 1, 5, 9, 15 |
| Versioned feature ledger and exact subjects | Tasks 2-4 |
| Deterministic fail-closed decisions | Tasks 5-7 |
| Human approval and scoped waivers | Tasks 4, 7, 10 |
| Architecture constraints and independent conformance | Tasks 5, 7, 11, 15 |
| Autonomous bounded repair and protected sources | Tasks 12-13 |
| Stage, merge, and release decisions | Task 14 |
| Evidence-grounded reports and summaries | Task 8 |
| Durable lightweight release retention | Task 8 |
| Legacy compatibility and migration | Tasks 1, 2, 10, 14 |
| Escaped-defect regression learning | Tasks 15, 17 |
| Observe-to-enforce rollout and upstreamability | Tasks 15-17 |

After these gates, enable only proven generic minimum gates in a separate
reviewed adopter change. Make `merge-ready` required only after that change
passes its own release-ready evaluation.
