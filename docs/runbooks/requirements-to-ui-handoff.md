# Requirements To UI Handoff Runbook

Use this runbook when a product fork needs to convert approved intent into UI
implementation guidance for a configured UI or implementation child repository.

The goal is to keep product truth in the configured intent repository while
giving UI builders and code agents a bounded implementation package.

## Ownership

- The configured intent repository owns product behavior, business rules,
  acceptance criteria, edge cases, and requirement-level test intent.
- The configured contracts repository owns shared API/schema/interface changes.
- The configured UI or implementation repository owns UI implementation.
- The root orchestration repository owns only generic handoff templates.

## Repeatable Flow

1. Identify the ticket or feature requiring UI implementation.
2. Confirm the approved intent artifacts that define the behavior.
3. Confirm whether shared contracts need to change first.
4. Create a ticket-scoped handoff in the product fork's chosen child path.
5. Start from `templates/handoffs/ui/` and adapt paths to the product fork.
6. Record any temporary behavior when implementation capability lags behind
   approved requirements.
7. After implementation, add a child-repository change note in the product
   fork's chosen location.

## Completion Checks

- The handoff references approved upstream intent.
- The handoff does not weaken product requirements.
- Any contract/backend/runtime gap is explicit.
- The implementation note records verification and remaining gaps.
