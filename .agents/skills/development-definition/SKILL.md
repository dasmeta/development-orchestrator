---
name: development-definition
description: Define or resume a delivery work item from intake through a reviewable specification and the workspace's Definition decision. Use before solution planning when the requested outcome, acceptance or scope needs definition.
---

# Development Definition

Return one canonical Definition, its location and revision, the decisions it
depends on, and the next action permitted by the workspace. Start with the work
item or request the operator supplied.

## Resolve the work item

Read the control repository instructions, active workspace overlay, effective
delivery policy and owner repository instructions. Use the configured tracker
and review bindings. Distinguish a live work item from a controlled fixture and
keep every effect within the authorized target. Search for an existing work
item before creating one. Read its parent, dependencies, priority, previous
decisions and linked artifacts. Apply the workspace's intake, progress and
transition rules at their specified triggers.

Resolve the owning repository, routed stage and selected producer from the
workspace configuration and policy. A phase can span several repository
stages. Confirm the intended owner against the work item. For a configured
repository stage with a repository-local producer, run the read-only check
from the control workspace before authoring:

```sh
bash .agents/skills/development-definition/scripts/check-route.sh "$config" "$stage" "$expected_owner_path"
```

Supply the owner established from intake and policy. For a shared skill
installation, the optional fourth argument is the active skill catalog
directory containing the selected producer. Verify its availability in the
target authoring session. For control-repository work or a different authorized
producer mechanism, use the existing documented route and its availability
check. Resolve a missing or ambiguous route before performing writes.

## Establish and author the Definition

Locate the canonical current intent and any existing Definition before invoking
a writer. Use the workspace's conflict check on overlapping requirements,
changes, work items and prior decisions. Delegate conflicts, requester
decisions and resume/revision handling to the effective workspace procedures.
If a required procedure is unavailable, report the affected operation, owner
and next action. On retry reconcile actual tracker, artifact and review
receipts first. Reuse accepted decisions only for scope they still cover.

Establish the problem, observable outcome, exclusions, affected capabilities
and constraints with the requester. Check existing capabilities for reuse.
Use a focused question or a bounded probe for uncertainty that could change
the outcome. Apply available advisory methods selectively. Route consequential
changes and uncovered permissions to their actual owners.

Invoke the selected authoring procedure in its owning repository; for a Spec
Kit workspace this usually means specify, then clarify where needed. Inspect
its prerequisites, hooks and write destinations first. Resume the existing
artifact using the owner's update procedure. Record requirements, dependencies,
assumptions, specialist review triggers and logical acceptance scenarios,
including negative outcomes mapped to the requirements they exercise.

## Review and hand off

Call the workspace's review procedure for the actual subject. For a
Definition-only package, use the authorized Definition completeness and
traceability profile. Check clarity, testability, ownership, constraints,
failure outcomes, dependencies and risk. Request independent semantic review
when required by materiality or policy. Defer task-dependent consistency
checks until their inputs exist when policy permits. Record a required check
with missing inputs as blocked. Identify an unresolved review route explicitly.

Use the workspace's requester-decision procedure before freezing the Definition.
Link the attributable agreement on the problem, outcome and boundaries, its
scope and its original evidence. For changed inputs call the owning revision
procedure and preserve history. Return the actual review disposition and
remaining gaps. Link the artifact and decision to the work item, with the
current stage, next owner and action. Stop at the Definition handoff.
