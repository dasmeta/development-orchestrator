# Readiness: FEAT-0001 / merge-ready

- Status: `blocked`
- Evaluated: `2026-08-13T02:00:00Z`
- Subject fingerprint: `git-blob:scope`

## Repository subjects

- `app`: `commit:abc`

## Acceptance coverage

- `documentation`: `ready`
- `tests`: `failed`
- `visual`: `blocked`

## Architecture conformance

- Advisory: `ARCH-ADVISORY`

## Gate results

- `documentation` — `ready` (configured_impact_match); evidence: `EV-docs`
- `tests` — `failed` (configured_impact_match); evidence: `EV-tests`
- `visual` — `blocked` (configured_impact_match); evidence: `EV-visual`

## Documentation disposition

- `documentation`: `ready`

## Failures and blockers

- `EVIDENCE_BLOCKED:visual` — Visual provider unavailable
- `EVIDENCE_FAILED:tests` — Tests failed

## Known gaps

- `GAP-1` — Architecture catalogue pending

## Waivers

- `WV-1` for `performance` — Accepted for this revision

## Evidence

- `EV-docs` satisfies `documentation`
- `EV-tests` satisfies `tests`
- `EV-visual` satisfies `visual`
