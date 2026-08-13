# Feature Evidence Quality Gates

The quality system turns product-configured tools into revision-bound evidence
and derives `stage-ready`, `merge-ready`, and `release-ready` decisions. The
engine is product-agnostic: product forks define impact rules, providers,
architecture sources, evidence types, and enforcement mode.

## Feature workflow

1. Initialize the ledger with `init-feature.sh`. This creates source inputs
   (`scope.json`, `claims.json`, `architecture.json`), immutable `evidence/`
   and `waivers/`, and derived `state/` paths.
2. Import approved claim and architecture references from their owning
   repositories. Do not rewrite product or architecture truth in the control
   repository.
3. Capture each candidate repository with `capture-feature-scope.sh`. Use a
   commit for merge/release proof; `WORKTREE` is limited to local stage proof.
4. Resolve impacts and gates with `resolve-quality-gates.sh`.
5. Run configured command providers with `run-quality-providers.sh`, collect
   source-control evidence, and invoke any configured independent verifier.
6. Derive readiness with `evaluate-readiness.sh`, then render both reports with
   `render-quality-reports.sh`.
7. Run `run-quality-cycle.sh` for bounded repair attempts. Repairs receive only
   evaluator findings and stop for authority, policy, architecture-source,
   protected-path, or infrastructure blockers.
8. Archive a ready `release-ready` record with
   `archive-feature-evidence.sh`.

## Policy modes

- `off`: legacy commands apply; the quality cycle requires `--force-evaluate`.
- `observe`: real decisions and reports are produced, but the cycle exits zero.
- `enforce`: named decisions gate delivery and use stable exits: `20`
  incomplete, `21` failed, `22` blocked, `23` repair budget exhausted, and
  `24` invalid policy or ledger input.

## Trust and immutability

Provider configuration is trusted policy. Feature content cannot supply shell
commands. Commands execute as argv arrays without `eval`; their working
directories must remain inside the configured repository. Evidence and waivers
are immutable. Human approval and waivers require a configured authority
provider. Architecture conformance and independent verification cannot be
self-certified by the implementation run.

## Waivers

Use `ingest-waiver.sh` only after ingesting matching authority evidence. A
waiver names one gate/finding and exact feature, subject, coverage, environment,
approver, issuance, and expiry scope. It remains visible in every report.

## Migration and proof levels

`migrate-feature-quality-v1.sh` adds missing v1 ledger files without changing
legacy intake, status, or source-control snapshots. Local `stage-ready` may use
worktree subjects. `merge-ready` uses committed PR heads and does not require
the PR to already be merged. `release-ready` represents deployed-path proof and
configured release-critical validation.

Run every generic control-plane test with:

```bash
bash tests/orchestration/run-all.sh
```
