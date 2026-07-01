# Reviewer Feedback — Item 020 (iteration 002)

Re-review of `docs/aide/items/020-in-memory-transport.md` (336 lines) after worker
applied all iteration-001 fixes.

## Verdict: GREEN-LIGHT (rating 9/10) — implementation-ready

All four critical iter-001 issues (C1-C4) and every suggested item I raised are
resolved. I empirically verified the load-bearing claims rather than trusting the
prose. No regressions to the previously-praised parts. Ship it.

---

## Verification performed (not just read)

### Watchdog soundness — the key question, VERIFIED SOUND
The team-lead asked whether `run-with-watchdog` is sound and whether it's racy.
My own iter-001-style worry was that wrapping a test body containing `check-*`
inside `(thread thunk)` would let an **assertion** failure die silently in the
child thread (false green), even while catching hangs. I tested both axes with a
throwaway `raco test`:

- **Assertion failure inside the watchdog thread:** a `(check-equal? 1 2)` placed
  inside the thunk was still reported — `raco test` printed `1/1 test failures`
  and exited 1. rackunit's failure tracking rides on thread-**inherited**
  parameters, so failures inside the spawned thread ARE counted. No swallowing.
- **Genuine hang inside the watchdog thread:** a thunk blocking on an unposted
  semaphore was converted to `(fail ...)` in the main thread — `1/1 test
  failures`, exit 1.

So the helper is sound on both axes: real assertion failures propagate, real
hangs become failures. Not racy in the single-threaded test bodies here (sync on
the worker thread; on timeout it `kill-thread`s and `fail`s). The 5 s budget is
generous for these millisecond tests.

### APIs exist / compile
- `sync/timeout`, `make-channel`, `channel-put`, `thread`, `kill-thread`,
  `make-semaphore`, `semaphore-wait`/`-post`, `async-channel*`, `fail`,
  `check-not-false`, `check-pred`, `check-exn` — all real. `semaphore-wait/timeout`
  (the iter-001 compile blocker) is gone; T4/T8 now use `(sync/timeout 1 done)`.
- `message-extra-info?` and `make-message-extra-info` confirmed exported from
  `mcp/transport/transport.rkt` and `(message-extra-info? (make-message-extra-info))`
  returns `#t` — so T2's `check-pred message-extra-info?` is valid.

---

## Per-issue resolution (iter-001 → iter-002)

| iter-001 issue | Resolution | Status |
|---|---|---|
| C1 `semaphore-wait/timeout` undefined | replaced with `(sync/timeout 1 done)` + `make-channel` latches | FIXED |
| C2 deadlock test hangs CI | `run-with-watchdog` on T3/T4/T8; verified hang→fail | FIXED |
| C3 pre-start `cons` LIFO, masked by 1-msg test | Impl step 2/4 + Decisions mandate append-to-end FIFO drain (never cons); T8 sends 3, asserts `'(1 2 3)` | FIXED |
| C4 start idempotency untested | T9: double-start, 2 msgs, assert `'(1 2)` once; `started?` guard in step 3 | FIXED |
| S1 send-after-close untested | T10: `check-exn exn:fail?` | FIXED |
| S2 on-close no-double-fire unfalsifiable | AC-6 + T5 use integer counters, assert `==1` after close and again after double-close | FIXED |
| S3 extra-info `#f` vs make-... | always passes `(make-message-extra-info)`; T2 `check-pred message-extra-info?` on B's extra | FIXED |
| S4 no-handler drop undefined | documented in Description + Decisions (post-start drop intentional; deliberate TS divergence) | RESOLVED (see note) |
| S5 relay survival after on-error | T6 sends a second "survive" msg, asserts arrival | FIXED |
| S6/S7/S8/S9 | T5 counters; T7 covers ids; sleep limited to T5 (where on-close is fired inline by `transport-close`, so it's harmless) | ADEQUATE |

### C3 FIFO drain — unambiguous
Impl step 2 ("append to end, drain in list order — never `cons`/prepend"), step 4
("append `extra` to peer's `pre-start-queue` (FIFO)"), and the Decisions bullet all
agree. Clear and consistent. T8 now actually exercises ordering with 3 messages
(and, per the verified watchdog, its `check-equal? received '(1 2 3)` would truly
fail a LIFO impl, not silently pass).

### Post-start-drop divergence — sound deliberate call
Dropping a relayed message when `on-message` is `#f` (after start) diverges from TS
(`_messageQueue`). This is acceptable and well-documented:
- Item 021's message-extra-info test installs the handler **before** sending, so it
  is unaffected.
- The S4 engine / client+server handshake installs `on-message` during its start
  sequence before peers transmit, so normal usage never hits the drop.
Not a hidden hazard. **One carry-forward caveat** (note for item 021 / S-stage
integration, not a blocker here): downstream code MUST install `on-message` before
the peer can send post-start, or messages are silently lost with no `on-error`.
Worth a one-line reminder in the engine wiring item.

---

## Nits (non-blocking, worker's discretion)

1. **Claim "sleep only in T5" is slightly inaccurate.** T3's completion-wait spawns
   a nested polling thread that uses `(sleep 0.01)`. Functionally fine (it polls
   `handler-ran?` and is itself bounded by `(sync/timeout 1 ...)`), but the prose
   claim is imprecise. Optional cleanup: have B's handler `channel-put` a `done`
   channel after `(set! handler-ran? #t)` and `(sync/timeout 1 done)` instead of
   the poll loop — simpler and removes the stray sleep.
2. **T9 "no duplication" wording.** Two relay threads on one `async-channel` would
   not actually duplicate (each item is consumed once); a broken idempotency guard
   manifests as scrambled order / head-of-line, which T9's `check-equal? '(1 2)`
   (or a `sync/timeout` miss) still catches. The test is correct; only the comment
   over-claims. Cosmetic.
3. T9/T10/T5/T7 are unwrapped by the watchdog — correct, since each is bounded by
   `sync/timeout` or runs inline (no hang path).

---

## Summary
Mechanism sound, port mapping exact, every blocking issue fixed, no regressions,
and I verified the watchdog and the extra-info predicate empirically rather than on
faith. Approved for implementation. Carry the post-start-drop caveat forward to the
engine-wiring item.
