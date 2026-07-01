# Reviewer feedback — Item 020 (in-memory paired transport, M10)

**Verdict: approved.** No blockers, no majors. 10/10 tests pass (`raco test mcp/transport/test/in-memory-test.rkt`). All AC-1–AC-12 met by the implementation. Findings below are minor (test rigor + theoretical concurrency) — none gate completion.

---

## AC results

| AC | Result | Note |
|----|--------|------|
| AC-1 struct + constructor + cross-link | pass | `in-memory-transport` impls `gen:transport`; `create-linked-pair` returns two `in-memory-transport?`; peers cross-set. |
| AC-2 generic completeness + idempotent start | pass (concern on test) | All 10 generics present; `transport-session-id`→`#f`. Start guarded by `started?`. See F1 — the *test* for idempotency is weak, impl is correct. |
| AC-3 async delivery | pass | Relay reads `async-channel-get`; send does `async-channel-put` on unbounded channel. No inline path exists. |
| AC-4 FIFO per direction | pass | Direct path = FIFO channel. Pre-start = `(append queue (list extra))` then drain in list order. No cons/prepend. |
| AC-5 bidirectional | pass | Independent inbox + relay per endpoint. |
| AC-6 close counter, no double-fire | pass | `transport-close` guards on `closed?`; fires own `on-close` once; idempotent. |
| AC-7 on-error + relay survival | pass | `with-handlers` wraps the per-message call *inside* the loop; `(loop)` runs after. |
| AC-8 related-request-id ignored | pass | `opts` never read in `%transport-send`. |
| AC-9 pre-start FIFO drain | pass | Same append-to-end queue; drained on start. |
| AC-10 send-after-close raises | pass | `closed?` check raises `exn:fail` before peer access. |
| AC-11 import boundary | pass (minor) | Only `transport.rkt` + `racket/generic` + `racket/async-channel` + `racket/contract`. `racket/base` via `#lang`. No net/sockets/subprocess. See F3 — `racket/contract` is imported but unused. |
| AC-12 explicit provide | pass | Exactly `in-memory-transport`, `in-memory-transport?`, `in-memory-transport-create-linked-pair`. No `all-defined-out`. |

Handler-freshness check: relay reads `on-message`/`on-error` fresh each iteration (in-memory.rkt:53–54), so handlers installed post-start fire. Confirmed by T2 (handler set after `transport-start`).

---

## Findings

### F1 — [minor, AC-2] T9 does not actually exercise start idempotency

`test/in-memory-test.rkt:181`. The test double-starts **`a`** (the *sender*), then sends `a→b` and asserts `b` received `'(1 2)`.

A non-idempotent `transport-start` would spawn a second relay thread on **`a`**, but `a`'s relay reads `a`'s inbox — it has nothing to do with delivery into `b`. So a duplicate-thread regression on `a` is invisible to this assertion. Even if the test double-started `b` instead, two relay threads competing on the same `async-channel` would *consume each item once* (async-channel-get removes the item), so messages would be split/reordered, not duplicated — `received` count would still reach 2. The "delivered exactly once / no duplication from two relay threads" claim in the comment is not what the test proves.

The implementation IS idempotent (in-memory.rkt:39 `unless ... started?`), so the AC passes. This is purely a test-coverage gap: a future idempotency regression would slip through.

Fix (optional, not blocking): double-start **`b`** (the receiver) and assert both order *and* count, e.g. send 3 messages and assert `received` equals `'(1 2 3)` exactly (a split-stream from two competing readers would scramble order under load). Or expose/observe `relay-thread` identity isn't re-created.

### F2 — [minor, AC-4/AC-9] Pre-start drain has a concurrency race (out of current test scope)

`%transport-send` (in-memory.rkt:73) branches on `(in-memory-transport-started? peer)`. `transport-start` (in-memory.rkt:39–63) sets `started? = #t` *before* it finishes draining the pre-start queue. A concurrent `send` that observes `started? = #t` mid-drain will `async-channel-put` directly onto the inbox, potentially landing *ahead* of still-draining buffered items → FIFO inversion. The mirror case: a `send` reads `started? = #f`, gets pre-empted, peer fully drains, then the late `append` lands in a queue that is never drained → lost message.

Not exercised by the suite (T8 sends all pre-start messages, then starts, single-threaded — correct by construction). For a test/in-memory transport this is acceptable, but worth a one-line note in Decisions that pre-start FIFO is only guaranteed when sends and the peer's `transport-start` are not concurrent. No fix required for this item.

### F3 — [minor, AC-11] `racket/contract` imported but unused

in-memory.rkt:15 requires `racket/contract`, but the module uses no contracts (`define/contract`, `contract-out`, `->`, etc.). AC-11 lists it as *permitted*, so this is not a violation — just dead weight. Drop the require, or add it back if a `provide (contract-out ...)` is intended for the public API.

---

## Notes (non-actionable)

- `make-exn:fail "..." (current-continuation-marks)` (in-memory.rkt:68) — correct arity; `exn:fail?` is true. T10 confirms.
- Close semantics: messages already queued on the inbox before the `'close` sentinel are still processed (drain-in-flight), so `on-message` can fire after `closed? = #t`. Matches the documented "drain in-flight before exit" decision — intentional, not a bug.
- `%transport-send` reaching `(in-memory-transport-started? peer)` with `peer = #f` is unreachable in normal flow: close always propagates to both endpoints, so `self.closed?` is true whenever `self.peer` has been cleared, and the closed-check raises first.
