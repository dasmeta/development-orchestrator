## Quality decision: merge-ready

**Outcome:** `blocked`

### Candidate subjects

- `app`: `commit:abc`

### Resolved impacts

- `architecture-sensitive`
- `implementation`

### Applicable evidence

- `documentation`: `ready`; evidence `EV-docs`
- `tests`: `failed`; evidence `EV-tests`
- `visual`: `blocked`; evidence `EV-visual`

### Failures, blockers, and gaps

- `EVIDENCE_BLOCKED:visual` — Visual provider unavailable
- `EVIDENCE_FAILED:tests` — Tests failed
- `GAP-1` — Architecture catalogue pending

### Architecture

- Advisory `ARCH-ADVISORY`

### Waivers

- `WV-1` for `performance` — Accepted for this revision
