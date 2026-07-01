# Item 020 — In-memory paired transport (M10) — APPROVED

**Approved iteration:** 002
**Date:** 2026-06-29

## Canonical artifacts
- `mcp/transport/in-memory.rkt` (125 lines) — `gen:transport` impl, relay-thread async delivery, FIFO pre-start buffer, close propagation, on-error survival.
- `mcp/transport/test/in-memory-test.rkt` — T1–T10, watchdog-guarded.

## Verdict
Reviewer (code-reviewer-expert, opus): **approved**, no blockers/majors. AC-1 through AC-12 all met. 10/10 `raco test` pass; M6 `transport.rkt` no regression.

## Iteration history
- **iteration-001**: initial impl, 10/10 pass, approved with 3 minor (non-gating) findings.
- **iteration-002** (applied, the approved cut):
  - F1: T9 idempotency test strengthened — now double-starts the **receiver** `b` and asserts exact 3-message order, so a duplicate-relay-thread regression is actually caught.
  - F2: Decisions note added — `started?` flips before pre-start drain → theoretical FIFO-inversion/lost-msg race under concurrent start, accepted out-of-scope for a single-threaded test transport.
  - F3: unused `racket/contract` dropped from require.

## Import boundary (AC-11) — verified
`racket/generic`, `racket/async-channel`, `"transport.rkt"` only. No `net/url`, sockets, subprocess, web-server.

## Provide (AC-12) — verified
Explicit, no `all-defined-out`: `in-memory-transport`, `in-memory-transport?`, `in-memory-transport-create-linked-pair`.
