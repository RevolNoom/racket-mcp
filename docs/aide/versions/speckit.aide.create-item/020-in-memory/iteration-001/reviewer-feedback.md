# Reviewer Feedback — Item 020: In-memory paired transport (M10)

Iteration 001. Reviewer focus: testing strategy, prerequisites, edge cases.

## Verdict: NEEDS REVISION (rating 6.5/10)

Strong foundation. The async-delivery mechanism is genuinely sound, the
generic-interface naming matches the M6 port exactly, and the Decisions section
shows real thought (relay-per-endpoint, unbounded async-channel, sentinel drain).
But there are two **must-fix** defects (one test won't compile, one risks
hanging CI forever) plus a masked ordering bug and several unfalsifiable/missing
assertions that let claimed acceptance criteria pass vacuously.

---

## Port-surface verification (PASS)

Cross-checked `mcp/transport/transport.rkt:95-118` against AC-2:
- Method names all correct: `transport-start`, `%transport-send` (3-arg internal),
  `transport-close`, `transport-on-message/close/error`,
  `set-transport-on-message!/close!/error!`, `transport-session-id`.
- Adapter correctly implements `%transport-send` (internal 3-arg) and lets the
  public `transport-send` 2-arg/3-arg wrapper dispatch to it. AC-8 / T7 exercise
  both 2-arg (T2) and 3-arg (T7) call sites — arity coverage is real.
- `make-transport-send-options #:related-request-id`, `message-extra-info`,
  `make-message-extra-info` all exist as used. No naming mismatch.

Import boundary (AC-10), explicit provide (AC-11), R2 size: all fine.

---

## Async-delivery mechanism (T3) — SOUND, but operationally dangerous

The semaphore-gate is correct reasoning:
- **Inline delivery:** `transport-send` calls B's handler on A's thread → handler
  blocks on `(semaphore-wait gate)`; A's thread therefore never reaches
  `(semaphore-post gate)` → genuine deadlock. Confirmed it WOULD deadlock.
- **Async delivery:** `transport-send` enqueues and returns; A posts the gate;
  B's relay thread unblocks. Passes.
- **Not vacuously green / not racy:** `(check-false handler-ran?)` is robust under
  correct async because the handler is pinned at the gate (can't set the flag
  regardless of how fast the relay thread starts). The real proof of async is
  simply *reaching the line without deadlock*. Good design.

BUT — see Critical #2: there is no timeout/watchdog, so the deadlock failure mode
hangs `raco test` (and CI) indefinitely instead of failing.

---

## Missing Coverage (CRITICAL)

### C1 — T4 uses a nonexistent function: `semaphore-wait/timeout`
Verified at the REPL: `semaphore-wait/timeout` is **undefined** in Racket. T4 will
not compile, so the FIFO acceptance criterion (AC-4) cannot pass as written.
Fix: use `(sync/timeout 1 done)`. (`sync/timeout` confirmed working.) This same
non-API should not appear anywhere else.

### C2 — No deadlock watchdog/timeout in T3 (CI-hang risk)
T3 is explicitly designed to deadlock under a buggy (inline) implementation.
rackunit has **no per-test timeout**. A deadlocking T3 hangs `raco test` forever,
hanging CI rather than reporting a failure — the worst failure mode for the one
test whose job is to catch the worst bug. Wrap the deadlock-prone body so a
timeout converts the hang into a hard failure, e.g. run the send+assert in a
sub-thread and `(sync/timeout 5 t)`; if it returns `#f`, `(fail "inline delivery deadlock")`.
Spec must mandate this, not leave it to the worker.

### C3 — Pre-start queue ordering bug, masked by single-item T8
Impl Step 4 says "cons onto peer's `pre-start-queue`" — `cons` prepends, so a
multi-message pre-start queue drains **LIFO**, violating FIFO (AC-4/AC-9). T8 only
queues ONE message, so the bug is invisible (classic single-item-list masking an
ordering bug). Two required fixes:
- Spec must state the drain reverses the list (or uses a queue/`append`) so
  pre-start order is FIFO.
- T8 must queue **at least 3** messages before `transport-start b` and assert they
  arrive in send order.

### C4 — `transport-start` idempotency claimed (AC-2) but UNTESTED
AC-2 says start is "idempotent on double-call." If a double `transport-start`
spawns a second relay thread on the same `inbox`, two consumers split the stream →
message loss / FIFO violation. Nothing tests this. Add: start `a` twice, send 3
messages, assert all 3 arrive in order (proves exactly one consumer).

---

## Missing Coverage (SUGGESTED)

### S1 — Send-after-close is unspecified-in-test
Impl Step 4 says "Check `closed?` → error if closed" and TS throws `NotConnected`
when `_otherTransport` is gone, but no test exercises it. Add: `(transport-close a)`
then assert `(transport-send a msg)` raises (`check-exn exn:fail?`). Pin down WHICH
error so the parity matrix is meaningful.

### S2 — "No double-fire" on-close is unfalsifiable as written
AC-6 promises closing twice causes no double-fire, but T5 tracks `a-closed?` as a
**boolean** — setting `#t` twice is indistinguishable from once. Use a counter and
assert it equals 1 after the second close. As written the invariant cannot fail.

### S3 — extra-info: `#f` vs `(make-message-extra-info)` ambiguity
Lines 97-99 / Decisions contradict themselves: "pass `#f` as extra-info" vs
"`extra-info` here is `(make-message-extra-info)` (all-`#f`)". This matters: item 021
will assert `message-extra-info` is *delivered* to `on-message`. If 020 ships
literal `#f` as the second arg, the on-message second arg is not a
`message-extra-info?`, diverging from the port's intent and forcing a behavior
change in 021. Recommend: always pass `(make-message-extra-info)` (a valid all-`#f`
value), not `#f`. Resolve the contradiction in the spec now.

### S4 — Peer has no on-message handler at dequeue time → silent drop (TS divergence)
Relay does `(when on-message (on-message ...))`. If a message is relayed onto a
started peer that has no handler yet, the relay dequeues and **silently drops** it.
TS instead pushes to `_messageQueue` (delivered on next `start`). The spec never
states the intended in-memory behavior for "started peer, no handler." Either
document the drop as intentional or buffer it — and add a test pinning whichever is
chosen. Currently undefined.

### S5 — Relay survival after on-error is untested
T6 induces a handler exception and checks `on-error` fired, but never checks the
relay thread *survived* (Impl Step 3 loops after the `with-handlers`). Add: after
the throwing handler, install a good handler and send another message; assert it
arrives — proves the relay didn't die on the exception.

### S6 — Trivial getters / session-id untested
AC-2 lists getter generics (`transport-on-message` etc.) and `transport-session-id`,
but tests only use setters. Add: set a handler then assert the getter returns it;
assert `(transport-session-id a)` is `#f`. Cheap, closes AC-2.

### S7 — Replace `(sleep 0.05)` with explicit synchronization (flakiness)
T3, T5, T6 wait via `(sleep 0.05)` — a timing assumption that can flake under CI
load. Prefer a `done` semaphore posted by the handler/on-close/on-error plus
`(sync/timeout 1 done)`. Deterministic and faster.

### S8 — Close on a never-started endpoint (edge, untested)
`transport-close` on an endpoint whose relay thread was never spawned still puts a
`'close` sentinel on an inbox no one consumes and fires `on-close`. Should be
harmless; add a `check-not-exn` to confirm (covers close-before-start and the
peer-not-started propagation branch in T5-style tests).

### S9 — on-close handler that throws (robustness)
Impl Step 5 calls peer-close (peer's on-close) then own on-close, unguarded — TS
uses try/finally. If the peer's on-close throws, own on-close is skipped and the
exception escapes `transport-close`. Either mirror TS's finally semantics or
explicitly accept the divergence in Decisions.

---

## Concrete Test Case Proposals

1. **FIFO compile fix (C1):** in T4 replace `(semaphore-wait/timeout done 1)` with
   `(check-not-false (sync/timeout 1 done))` then `(check-equal? received '(1 2 3))`.

2. **Deadlock watchdog (C2):**
   ```racket
   (define t (thread (lambda ()
     (transport-send a (hasheq 'jsonrpc "2.0" 'method "test"))
     (check-false handler-ran?)
     (semaphore-post gate))))
   (unless (sync/timeout 5 t) (kill-thread t) (fail "inline delivery deadlocked"))
   (check-not-false (sync/timeout 1 done)) ; handler posts done after set!
   (check-true handler-ran?)
   ```

3. **Pre-start FIFO (C3):** queue ids 1..5 to b before `(transport-start b)`;
   collect on b; assert `'(1 2 3 4 5)`.

4. **Double-start idempotency (C4):**
   `(transport-start a)(transport-start a)`; send ids 1 2 3 from b→a (or a→b with
   roles swapped); assert all three arrive once, in order.

5. **Send-after-close (S1):**
   `(transport-close a)`; `(check-exn exn:fail? (lambda () (transport-send a (hasheq 'jsonrpc "2.0" 'method "x"))))`.

6. **No double on-close fire (S2):** `(define fires 0)`;
   `(set-transport-on-close! a (lambda () (set! fires (add1 fires))))`;
   `(transport-close a)(transport-close a)`; `(check-equal? fires 1)`.

7. **Relay survives error (S5):** after the boom handler fires on-error, swap in a
   good handler, send again, assert delivery.

8. **Getters + session (S6):**
   `(define h (lambda (m e) (void)))(set-transport-on-message! a h)(check-eq? (transport-on-message a) h)(check-false (transport-session-id a))`.

---

## Summary
Mechanism design is sound and the port mapping is correct. Block on C1-C4
(compile error, CI-hang risk, masked LIFO ordering bug, untested idempotency
invariant). S1-S9 raise the suite from "passes" to "actually adversarial." Resolve
the extra-info `#f` vs `make-message-extra-info` contradiction (S3) before 021
depends on it.
