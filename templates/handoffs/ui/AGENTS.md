# Ticket UI Handoff Instructions

This folder is a downstream UI handoff for `<ticket>`.

## Source Of Truth

- Product behavior is owned by the configured intent repository.
- This handoff translates approved intent into UI implementation guidance.
- Do not invent product behavior, acceptance criteria, contracts, persistence,
  or validation ownership in this folder.

## Implementation Rules

- Read `README.md` first, then `product-understanding.md`, then
  `implementation-instructions.md`.
- Keep implementation bounded to the configured target child repository unless
  the operator explicitly requests multi-repo work.
- If runtime persistence, shared contracts, or real API support are missing,
  use the temporary behavior described in the handoff and record the remaining
  gap.
- UI-builder work must add or update a matching change note in the product
  fork's configured location.

## Completion

Before finishing, verify the implemented UI against the upstream intent
artifacts and update the ticket change note.
