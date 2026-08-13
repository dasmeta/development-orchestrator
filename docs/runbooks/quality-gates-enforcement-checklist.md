# Quality-gate enforcement checklist

Keep a product policy in `observe` mode until every item below has durable
evidence and an operator records the reviewed decision.

- [ ] All eight deterministic dogfood scenarios rerun without drift.
- [ ] There are zero false-ready outcomes for missing, malformed, stale,
  blocked, self-certified, architecture-unresolved, visual, and contract proof.
- [ ] Repair briefs assign the correct repository owner and never authorize
  changes to claims, architecture, validation sources, policy, providers,
  waivers, or evidence.
- [ ] Legacy initialization, stage routing, source-control collection, and
  mergeability commands still pass.
- [ ] Three real product features complete in observe mode and receive operator
  review of scope, evidence, reports, gaps, and PR summary.
- [ ] A governed architecture owner and source paths are approved before
  architecture-sensitive gates are enforced.
- [ ] Visual gates have committed scenarios or an approved hosted-review
  provider before enforcement.
- [ ] Contract gates have an executable compatibility provider or retain a
  trusted external-import workflow.
- [ ] Escaped defects prove both updated business-readable acceptance intent
  and the mapped executable E2E regression case.
- [ ] Required source-control checks evaluate committed candidate revisions
  before merge; release proof evaluates the configured deployed path.

Enforcement is a separate reviewed policy change. Enable only gates whose
provider, authority, fixtures, environment, and retention have demonstrated
reliable evidence. Never convert a missing capability to `passed` to unblock a
rollout.
