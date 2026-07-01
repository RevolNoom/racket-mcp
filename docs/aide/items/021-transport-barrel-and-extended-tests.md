# Work Item 021: Transport barrel + extended in-memory test suite

> **Queue:** `docs/aide/queue/queue-003.md` — Item 021
> **Stage:** S3 (Transport port + in-memory adapter — L1 part 1)
> **Modules:** M6 (`mcp/transport/transport.rkt` ✅ 019), M10 (`mcp/transport/in-memory.rkt` ✅ 020)
> **Deliverables:** `mcp/transport/main.rkt` barrel + extended `mcp/transport/test/in-memory-test.rkt` (T11–T14)
> **Deps:** Items 019 ✅, 020 ✅ — both must be complete before starting.
> **Status:** 📋

---

## Description

**Deliverable 1 — Barrel.** `mcp/transport/main.rkt`: 4-line re-export of both `transport.rkt` (M6) and `in-memory.rkt` (M10) complete public surfaces. Downstream stages import one module instead of two. Mirrors the `mcp/core/main.rkt` pattern exactly.

**Deliverable 2 — Extended test suite.** Augment `mcp/transport/test/in-memory-test.rkt` with T11–T14: 50-message no-loss+FIFO (sequential + concurrent-senders variants), `message-extra-info` surface delivery, concurrent-close from both sides, and peer-onclose-throw close-order test. Switch transport requires to the barrel `(file "../main.rkt")`.

---

## Acceptance Criteria

### AC-1 — Barrel
- `mcp/transport/main.rkt` exists, `#lang racket/base`, no `all-defined-out`.
- Re-exports whatever each module provides via `(all-from-out ...)`. Both modules export disjoint identifiers — no collisions.
- `(require (file "../main.rkt"))` in the test file gives access to all T1–T14 bindings with no direct import of the two source files.

### AC-2 — T1–T10 pass after require-swap
After switching test requires to the barrel, all existing tests pass unchanged. Smoke-proves the barrel loads and re-exports the subset exercised by T1–T10. (`all-from-out` cannot silently drop bindings; risk of missing names is near-zero.)

### AC-3 — 50-message no-loss + FIFO (T11a + T11b)
- T11a (sequential): 50 messages A→B in a loop; all arrive in send order. Fresh pair for B→A (50 messages, FIFO). Watchdog 10 s.
- T11b (concurrent senders): 5 threads send 10 messages each (disjoint id-ranges) simultaneously A→B. Total received == 50; each sender's ids in sender order. Watchdog 10 s.

### AC-4 — `message-extra-info` surface delivery (T12)
- `on-message` receives a `message-extra-info?` value (not `#f`) for every in-memory delivery.
- All three accessors (`-session`, `-auth`, `-http-req-info`) callable and all return `#f` for in-memory.

### AC-5 — Concurrent close from both sides (T13)
- Two threads each call `transport-close` on their own endpoint simultaneously.
- Both `on-close` callbacks fire at-least-once, at-most-twice: `(and (>= count 1) (<= count 2))` per endpoint. Counter relaxed because `closed?` guard (in-memory.rkt:80) is non-atomic. Watchdog 5 s.

### AC-6 — Peer on-close throw aborts own on-close (T14)
- Peer's `on-close` throws. Racket close order: own `on-close` is NOT reached.
- Assert `a-closed?` is `#f`. Caller's `transport-close` wrapped in `check-exn` to confirm exn propagates out.

### AC-7 — raco test green
`raco test mcp/transport/test/` passes (exit 0), T1–T14 all green.
`raco test mcp/transport/` also passes (barrel loads, no undefined bindings).

---

## Implementation Steps

1. **Write `mcp/transport/main.rkt`** — mirror `mcp/core/main.rkt`:
   ```racket
   #lang racket/base
   (require "transport.rkt" "in-memory.rkt")
   (provide (all-from-out "transport.rkt") (all-from-out "in-memory.rkt"))
   ```
   Run `raco make mcp/transport/main.rkt` (exit 0).

2. **Switch requires in `mcp/transport/test/in-memory-test.rkt`.** Read in-memory-test.rkt:1–20 to confirm current require form, then replace the transport + in-memory requires with `(require (file "../main.rkt"))` (relative path — no `info.rkt` in repo; collection-style would fail at compile). Keep `rackunit` and `racket/async-channel` as-is. Run `raco test mcp/transport/test/` — confirm T1–T10 still pass.

3. **Add T11a, T11b, T12, T13, T14** appended after T10. Reuse `run-with-watchdog` (in-memory-test.rkt:19+). See Testing Strategy.

4. **Run** `raco test mcp/transport/test/`. Fix failures. Confirm `raco test mcp/transport/` green.

5. **Update** `docs/aide/progress.md` (see Completion Reminder).

---

## Testing Strategy

Run: `raco test mcp/transport/test/` then confirm `raco test mcp/transport/` green.

**TS cases already covered by T1–T10 — do NOT duplicate:**

| TS inMemory.test.ts case | Covered by |
|---|---|
| Create linked pair | T1 |
| Start without error (both directions) | T2 |
| Client→server send, server→client send | T2 |
| Handle close — both onclose fire | T5 |
| Throw when sending after close | T10 |
| onclose exactly once per transport | T5 |
| Double-close idempotent | T5 |
| Queue messages sent before start | T8 |

**New tests:**

### T11a — 50-message no-loss + FIFO (sequential sender)
`run-with-watchdog 10`. Create pair; start both. A→B: send ids `0..49` in a loop; collect in `on-message` handler; signal done channel when count hits 50. Assert `received == '(0 1 ... 49)`. **B→A: fresh linked pair** (not drain-and-reuse). Watchdog 10 s per direction.

FIFO guaranteed by single relay thread per direction. This is a no-loss + ordering correctness check.

### T11b — N=50 no-loss with concurrent senders
`run-with-watchdog 10`. 5 threads each `(transport-send ep-A ...)` 10 messages with disjoint id-ranges (thread-k sends ids `k*10..(k+1)*10-1`). Collect all 50 in B's `on-message`. Assert: total count == 50. Per-sender FIFO: for each sender-k, the subsequence of received ids in range `[k*10, k*10+9]` must be in ascending order. No cross-sender order assertion (interleaving is valid).

This exercises real `async-channel` contention: 5 concurrent writers on one send path.

### T12 — `message-extra-info` surface delivery (TS "send with authInfo" adapted)
Create pair; start both. Set `on-message` on B capturing extra to a channel. Send one message A→B. `sync/timeout 1` on extra-chan. Assert:
- `(message-extra-info? extra)` — wiring present; extra is not `#f`
- `(message-extra-info-session extra)` → `#f`
- `(message-extra-info-auth extra)` → `#f`
- `(message-extra-info-http-req-info extra)` → `#f`

TS "send with authInfo" expects `extra.authInfo` to round-trip. Racket has no equivalent send-path (see Decisions). Test asserts wiring surface only.

### T13 — Concurrent close from both sides; each on-close fires 1–2×
Create pair; start both. Install counter-incrementing `on-close` on each endpoint. Spawn two threads: thread-1 `(transport-close ep-A)`, thread-2 `(transport-close ep-B)`. Join both via `sync/timeout 5`. Sleep 0.05 s. Assert `(and (>= a-count 1) (<= a-count 2))` AND same for `b-count`.

`closed?` guard (in-memory.rkt:80) is non-atomic read-then-set; concurrent entry can cause double-fire. Impl guarantees at-least-once and at-most-twice, not exactly-once.

### T14 — Peer on-close throw aborts own on-close (Racket close order)
Create pair; start both. Set ep-B's `on-close` to `(λ () (error "peer-close-boom"))`. Set ep-A's `on-close` to set `a-closed? #t`.

Racket close order (in-memory.rkt:~87–90): `transport-close(A)` → recurse into `transport-close(B)` → fires B's `on-close` which THROWS → exception unwinds back through `transport-close(B)` and past A's own `on-close` call → A's `on-close` NEVER reached.

Run `(check-exn exn:fail? (λ () (transport-close ep-A)))` first — this is the single call that triggers close semantics. THEN assert `(check-false a-closed?)`. Order matters: asserting `#f` before any close call would be vacuous (trivially passes without testing close behavior).

---

## Dependencies

- M6 `mcp/transport/transport.rkt` (item 019 ✅) — `gen:transport`, `message-extra-info`, `make-message-extra-info`, `transport-send-options`
- M10 `mcp/transport/in-memory.rkt` (item 020 ✅) — `in-memory-transport-create-linked-pair`
- L0: `racket/base`, `racket/async-channel`, `rackunit`

---

## Decisions & Trade-offs

**Outcome (impl):** All 7 ACs met. `raco test mcp/transport/test/` and
`raco test mcp/transport/` both green — 46 tests passed. `main.rkt` barrel was
already present + correct (verbatim the spec's 3-line form); only require-swap +
T11–T14 append were needed. Require swapped to `(file "../main.rkt")`; T1–T10
pass unchanged (AC-2). Accessors confirmed against transport.rkt:143–146
(`message-extra-info-session/-auth/-http-req-info`). T11a/T11b use `build-list`
+ `sort` for no-loss assertions; T11b spawns 5 unjoined sender threads and gates
completion on the 50-count `done` channel. T13/T14 behaved exactly as predicted
by the pre-decided notes (relaxed 1–2 counter; peer-throw aborts own on-close).

Pre-decided:

- **Auth round-trip OUT OF SCOPE.** TS "send with authInfo" has no Racket equivalent: `transport-send-options` (transport.rkt:107–111) has no `auth` field; `%transport-send` (in-memory.rkt:64–76) always constructs all-`#f` `message-extra-info`. Extending requires M6+M10 source changes — out of scope for this barrel+test item. T12 asserts wiring surface only. Revisit at S4/S8.

- **Barrel uses `all-from-out` both modules; file-relative require.** `(require (file "../main.rkt"))` — repo has no `info.rkt`, so collection-style `mcp/transport/main` fails at compile. Both modules export disjoint identifiers, so `all-from-out` of both is collision-free. T1–T10 passing after the require-swap smoke-proves the barrel loads and re-exports the exercised subset.

- **T11 split into sequential (T11a) + concurrent-senders (T11b).** T11a is a no-loss + FIFO correctness check (single relay thread = deterministic order; not a concurrency test). T11b adds 5 concurrent writer threads to exercise real `async-channel` write contention. Per-sender FIFO asserted; cross-sender order left unasserted (valid interleaving). N=50 total completes in < 1 s on any CI.

- **T13 counter asserts `>= 1` and `<= 2` (not exactly 1).** `closed?` guard (in-memory.rkt:80) is non-atomic; concurrent close from both sides can trigger double-fire. Impl guarantee is at-least-once, at-most-twice. Hard `== 1` would produce flaky failures.

- **T14 asserts `a-closed? #f` (not `#t`).** Racket in-memory does NOT wrap the recursive peer `transport-close` in a handler, so a throwing peer `on-close` propagates to caller and aborts own `on-close`. This is the observed Racket behavior — materially different from TS (which ignores peer close errors). Source fix (wrapping peer close in `with-handlers`) would change in-memory.rkt semantics — out of scope for this item.

---

## Completion Reminder

After `raco test mcp/transport/test/` passes:

1. Open `docs/aide/progress.md`.
2. Grep for `mcp/transport/main.rkt` (barrel row, ~line 102) — flip 📋 → ✅.
3. Find `mcp/transport/test/in-memory-test.rkt` row (~line 103) — note extended with T11–T14.
4. Do NOT flip Stage S3 overview row (~line 29) or any other item rows.
