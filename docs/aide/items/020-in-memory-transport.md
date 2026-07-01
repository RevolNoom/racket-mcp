# Work Item 020: In-memory paired transport — async linked endpoints (M10)

> **Queue:** `docs/aide/queue/queue-003.md` — Item 020
> **Stage:** S3 (Transport port + in-memory adapter — L1 part 1)
> **Module:** **M10** — `mcp/transport/in-memory.rkt` + `mcp/transport/test/in-memory-test.rkt`.
> **Source roadmap:** `docs/aide/roadmap.md` Stage S3 → Deliverables.
> **Reference impl:** `typescript-sdk/packages/core/src/util/inMemory.ts` — linked-pair relay semantics.
> **Port dep:** `mcp/transport/transport.rkt` (M6, item 019) — the gen:transport interface this adapter implements.
> **Status:** 📋

---

## Description

Implement `mcp/transport/in-memory.rkt` — first concrete adapter for `gen:transport` (M6). Mirrors TS `InMemoryTransport` with one critical difference: TS uses `Promise.resolve().then` microtask scheduling; Racket uses a **real relay thread + `async-channel`** so `send` returns before the peer's `on-message` fires.

Constructor `in-memory-transport-create-linked-pair` returns a linked pair. `send` on endpoint A enqueues on B's inbox; B's relay thread dequeues and calls B's `on-message` with `(make-message-extra-info)` (all-`#f`) as extra arg. `close` propagates to the peer. `on-error` fires if the relay thread catches an exception. `related-request-id` is accepted and silently ignored. Imports M6 + L0 only.

**No-handler behavior:** if `on-message` is `#f` when the relay thread processes a message (after start, handler not installed), the message is **dropped silently**. Pre-start messages are buffered in FIFO order and drained when `transport-start` runs.

---

## Acceptance Criteria

### AC-1 — Struct + constructor
- `in-memory-transport` implements `gen:transport`: `(transport? ep)` is `#t`.
- `(in-memory-transport-create-linked-pair)` returns `(values ep-a ep-b)`, each an `in-memory-transport?`.
- Cross-link: send on one endpoint delivers to the other's `on-message`.

### AC-2 — Generic interface completeness
Implements ALL methods from `mcp/transport/transport.rkt:95–111`:
- `transport-start` — spawns relay thread; **idempotent** (double-call starts exactly one thread).
- `%transport-send` (3-arg internal; public via `transport-send` wrapper) — enqueues on peer inbox; `opts` accepted.
- `transport-close` — tears down relay; fires `on-close` on both endpoints.
- `transport-on-message`, `transport-on-close`, `transport-on-error` — getter generics.
- `set-transport-on-message!`, `set-transport-on-close!`, `set-transport-on-error!` — setter generics.
- `transport-session-id` — returns `#f`.

### AC-3 — Async delivery (load-bearing)
`send` returns before peer's `on-message` fires. Proven by T3 (semaphore-gate that deadlocks under inline delivery). T3 is wrapped in a watchdog thread; if it doesn't complete within 5 s, the watchdog fails the test (`fail "T3: deadlock — delivery not async"`).

### AC-4 — FIFO ordering per direction
Messages sent A→B arrive in send order. Pre-start buffer drains in FIFO order. Both proven by T4 and T8 (3-message ordering asserts).

### AC-5 — Bidirectional round-trip
A→B and B→A deliver correctly and independently.

### AC-6 — Close propagation (counter, not boolean)
`(transport-close ep-A)` fires `on-close` on **both** endpoints exactly once each. Verified via integer counter (not boolean flag): assert `== 1` per endpoint after close, and still `== 1` after a second `(transport-close ep-A)` (no double-fire).

### AC-7 — on-error + relay survival
Relay thread catches handler exception → calls `on-error`. Relay thread **survives** (subsequent send to same endpoint still delivers). Proven by T6.

### AC-8 — related-request-id accepted and ignored
`(transport-send ep msg (make-transport-send-options #:related-request-id "x"))` and `... #:related-request-id 42` both `check-not-exn`.

### AC-9 — Pre-start FIFO buffering
3 messages sent before `transport-start` arrive in send order after start. Proven by T8 (3-message assert).

### AC-10 — Send-after-close raises
`(transport-send closed-ep msg)` raises `exn:fail?`. Proven by T10.

### AC-11 — Import boundary
Requires only: `mcp/transport/transport.rkt`, `racket/base`, `racket/generic`, `racket/async-channel`, `racket/contract`. NO `net/url`, sockets, subprocess, web-server.

### AC-12 — Explicit provide
No `all-defined-out`. Exported: `in-memory-transport`, `in-memory-transport?`, `in-memory-transport-create-linked-pair`.

---

## Implementation Steps

1. **Read** `mcp/transport/transport.rkt:95–118` (already read — method names confirmed). No re-read needed.

2. **Struct layout.** `in-memory-transport` with `#:mutable` fields:
   - `on-message`, `on-close`, `on-error` — sinks (init `#f`).
   - `peer` — other endpoint; set by pair constructor.
   - `inbox` — `(async-channel)` created at construction; peer's `send` writes here.
   - `relay-thread` — `#f` until `transport-start`.
   - `started?` — `#f`; set to `#t` on first `transport-start` (idempotency guard).
   - `closed?` — `#f`; set to `#t` on `transport-close`.
   - `pre-start-queue` — mutable list; FIFO: **append** to end, drain in list order (never `cons`/prepend).

3. **Relay thread.** `transport-start` guards with `started?`; if already `#t`, returns immediately (idempotent). Otherwise sets `started? = #t`, spawns thread:
   ```
   (let loop ()
     (define item (async-channel-get inbox))
     (cond
       [(eq? item 'close) (void)]
       [else
        (with-handlers ([exn:fail? (λ (e) (when on-error (on-error e)))])
          (when on-message (on-message (car item) (cdr item))))
        (loop)]))
   ```
   After spawning, drain `pre-start-queue` in FIFO order onto `inbox` (each `(async-channel-put inbox item)`).

4. **`%transport-send` impl.** If `closed?` → raise `exn:fail`. Build `extra = (cons msg (make-message-extra-info))`. If peer `started?` → `(async-channel-put peer-inbox extra)`. Else → append `extra` to peer's `pre-start-queue` (FIFO). Ignore `opts` entirely (accept-and-discard `related-request-id`, `resumption-token`). Note: `make-message-extra-info` (all-`#f`) is always passed as extra-info — Racket `transport-send-options` has no `auth` field (unlike TS `options.authInfo`); item 021 may extend if needed.

5. **`transport-close` impl.** Guard: if `closed?` return immediately. Set `closed? = #t`. Put `'close` sentinel on own `inbox`. If peer is set and peer not `closed?`, call `(transport-close peer)`. Call own `on-close` if set. Clear `peer` field.

6. **`in-memory-transport-create-linked-pair`.** Construct two endpoints; set peer fields on each. Return `(values ep-a ep-b)`.

7. **Write test file** (see Testing Strategy).

8. **Run** `raco test mcp/transport/test/`. Confirm `raco test mcp/transport/` still passes.

9. **Update** `docs/aide/progress.md`.

---

## Testing Strategy

One-line run: `raco test mcp/transport/test/`.

File: `mcp/transport/test/in-memory-test.rkt` (`#lang racket/base`).

Requires: `rackunit`, `mcp/transport/transport.rkt`, `mcp/transport/in-memory.rkt`, `racket/async-channel`.

**Watchdog helper** (use for any test that could hang under a wrong impl):
```racket
(define (run-with-watchdog secs thunk fail-msg)
  (define t (thread thunk))
  (unless (sync/timeout secs t)
    (kill-thread t)
    (fail fail-msg)))
```

### T1 — Pair wiring + transport? predicate

```racket
(define-values (a b) (in-memory-transport-create-linked-pair))
(check-pred transport? a)
(check-pred transport? b)
(check-pred in-memory-transport? a)
```

### T2 — Each-direction round-trip (extra-info is message-extra-info?)

```racket
(define-values (a b) (in-memory-transport-create-linked-pair))
(transport-start a) (transport-start b)
(define got-b (make-channel)) (define got-b-extra (make-channel))
(set-transport-on-message! b (λ (msg extra) (channel-put got-b msg) (channel-put got-b-extra extra)))
(transport-send a (hasheq 'jsonrpc "2.0" 'method "ping"))
(check-equal? (sync/timeout 1 got-b) (hasheq 'jsonrpc "2.0" 'method "ping"))
(check-pred message-extra-info? (sync/timeout 1 got-b-extra))
; Reverse direction
(define got-a (make-channel))
(set-transport-on-message! a (λ (msg extra) (channel-put got-a msg)))
(transport-send b (hasheq 'jsonrpc "2.0" 'method "pong"))
(check-equal? (sync/timeout 1 got-a) (hasheq 'jsonrpc "2.0" 'method "pong"))
```

### T3 — ASYNC DELIVERY (semaphore-gate; deadlocks under inline; guarded by watchdog)

The gate semaphore starts at 0. B's handler calls `(semaphore-wait gate)` before completing. Under inline delivery: `transport-send` blocks on gate on the calling thread → `(semaphore-post gate)` is never reached → **deadlock**. The watchdog thread detects the hang and fails within 5 s.

```racket
(run-with-watchdog 5
  (λ ()
    (define-values (a b) (in-memory-transport-create-linked-pair))
    (transport-start a) (transport-start b)
    (define gate (make-semaphore 0))
    (define handler-ran? #f)
    (set-transport-on-message! b
      (λ (msg extra)
        (semaphore-wait gate)       ; blocks relay thread until gate posted
        (set! handler-ran? #t)))
    (transport-send a (hasheq 'jsonrpc "2.0" 'method "async-test"))
    ; Under async: we reach here. handler-ran? must still be #f.
    (check-false handler-ran?)
    (semaphore-post gate)           ; release relay thread
    ; Wait for handler to finish
    (check-not-false (sync/timeout 1 (thread (λ ()
                                               (let loop ()
                                                 (unless handler-ran? (sleep 0.01) (loop))))))))
  "T3: deadlock — transport-send did not return before on-message fired (inline delivery)")
```

### T4 — FIFO ordering (3 messages; watchdog guarded)

```racket
(run-with-watchdog 5
  (λ ()
    (define-values (a b) (in-memory-transport-create-linked-pair))
    (transport-start a) (transport-start b)
    (define received '())
    (define done (make-channel))
    (set-transport-on-message! b
      (λ (msg extra)
        (set! received (append received (list (hash-ref msg 'id))))
        (when (= (length received) 3) (channel-put done #t))))
    (for ([i '(1 2 3)])
      (transport-send a (hasheq 'jsonrpc "2.0" 'method "m" 'id i)))
    (check-not-false (sync/timeout 1 done))
    (check-equal? received '(1 2 3)))
  "T4: FIFO ordering hang")
```

### T5 — on-close fires on both endpoints exactly once; no double-fire

```racket
(define-values (a b) (in-memory-transport-create-linked-pair))
(transport-start a) (transport-start b)
(define a-count 0) (define b-count 0)
(set-transport-on-close! a (λ () (set! a-count (+ a-count 1))))
(set-transport-on-close! b (λ () (set! b-count (+ b-count 1))))
(transport-close a)
(sleep 0.05)
(check-equal? a-count 1)
(check-equal? b-count 1)
; Double-close: no-op (no double-fire)
(check-not-exn (λ () (transport-close a)))
(sleep 0.01)
(check-equal? a-count 1)
(check-equal? b-count 1)
```

### T6 — on-error fires on induced failure; relay survives exception

```racket
(define-values (a b) (in-memory-transport-create-linked-pair))
(transport-start a) (transport-start b)
(define got-error #f)
(define error-latch (make-channel))
(define success-latch (make-channel))
; First message: handler throws
(set-transport-on-error! b (λ (e) (set! got-error e) (channel-put error-latch #t)))
(set-transport-on-message! b
  (λ (msg extra)
    (if (equal? (hash-ref msg 'method) "boom")
        (error "induced failure")
        (channel-put success-latch #t))))
(transport-send a (hasheq 'jsonrpc "2.0" 'method "boom"))
(check-not-false (sync/timeout 1 error-latch))
(check-pred exn:fail? got-error)
; Relay must still be running: send a second message and assert it arrives
(transport-send a (hasheq 'jsonrpc "2.0" 'method "survive"))
(check-not-false (sync/timeout 1 success-latch))
```

### T7 — related-request-id accepted and ignored

```racket
(define-values (a b) (in-memory-transport-create-linked-pair))
(transport-start a) (transport-start b)
(check-not-exn
  (λ () (transport-send a (hasheq 'jsonrpc "2.0" 'method "x")
                          (make-transport-send-options #:related-request-id "rid-1"))))
(check-not-exn
  (λ () (transport-send a (hasheq 'jsonrpc "2.0" 'method "x")
                          (make-transport-send-options #:related-request-id 42))))
```

### T8 — Pre-start FIFO buffering (3 messages; watchdog guarded)

```racket
(run-with-watchdog 5
  (λ ()
    (define-values (a b) (in-memory-transport-create-linked-pair))
    (transport-start a)
    ; b not started — send 3 messages before b's relay thread exists
    (define received '())
    (define done (make-channel))
    (set-transport-on-message! b
      (λ (msg extra)
        (set! received (append received (list (hash-ref msg 'id))))
        (when (= (length received) 3) (channel-put done #t))))
    (for ([i '(1 2 3)])
      (transport-send a (hasheq 'jsonrpc "2.0" 'method "pre" 'id i)))
    (transport-start b)  ; drain pre-start queue in FIFO order
    (check-not-false (sync/timeout 1 done))
    (check-equal? received '(1 2 3)))
  "T8: pre-start buffering hang or wrong FIFO order")
```

### T9 — transport-start idempotency (double-start: no split stream)

```racket
(define-values (a b) (in-memory-transport-create-linked-pair))
(transport-start a) (transport-start b)
(transport-start a)  ; second start — must not spawn second relay thread
(define received '())
(define done (make-channel))
(set-transport-on-message! b
  (λ (msg extra)
    (set! received (append received (list (hash-ref msg 'id))))
    (when (= (length received) 2) (channel-put done #t))))
(transport-send a (hasheq 'jsonrpc "2.0" 'method "m" 'id 1))
(transport-send a (hasheq 'jsonrpc "2.0" 'method "m" 'id 2))
(check-not-false (sync/timeout 1 done))
; Each message delivered exactly once (no duplication from two relay threads)
(check-equal? received '(1 2))
```

### T10 — send-after-close raises exn:fail?

```racket
(define-values (a b) (in-memory-transport-create-linked-pair))
(transport-start a) (transport-start b)
(transport-close a)
(check-exn exn:fail? (λ () (transport-send a (hasheq 'jsonrpc "2.0" 'method "x"))))
```

---

## Dependencies

- **M6** (`mcp/transport/transport.rkt`, item 019): `gen:transport`, all generic methods, `message-extra-info`, `make-message-extra-info`, `transport-send-options`. Must be ✅.
- **L0**: `racket/base`, `racket/generic`, `racket/async-channel`, `racket/contract`. No external packages.

---

## Decisions & Trade-offs

> To be updated during implementation.

Implementation notes:

- **`make-async-channel` not `async-channel`.** `racket/async-channel` exports `async-channel` as the type predicate, not a constructor. Constructor is `make-async-channel`. Spec pseudocode used `(async-channel)` as shorthand — corrected in impl.

Pre-decided:

- **Relay thread per endpoint, not per pair.** Each endpoint owns its inbox `async-channel` + one relay thread. Peer writes to inbox; owner reads. Independent FIFO channels per direction; isolated error handling.
- **`async-channel` over plain `channel`.** Unbounded → `send` never blocks waiting for consumer. A bounded channel would block `send` under backpressure, breaking the async invariant.
- **Close sentinel `'close` on inbox.** Lets relay thread drain in-flight messages before exiting (FIFO-safe). `thread-break` alternative would discard queued items.
- **`message-extra-info` always `(make-message-extra-info)` (all-`#f`).** TS `send` propagates `authInfo` via `options.authInfo`; Racket `transport-send-options` (M6) has no `auth` field. Extra-info is all-`#f` for in-memory. Item 021 may extend if auth-in-memory testing is needed.
- **Pre-start queue is FIFO (append-to-end, drain in list order).** Never `cons`/prepend — that would produce LIFO order on drain, breaking message ordering.
- **No-handler drop (after start).** If `on-message` is `#f` when relay processes a message, message is silently dropped. This diverges from TS (which buffers to `_messageQueue`); TS only does so to handle pre-`start` sends. Post-`start` drop is intentional and documented here.
- **`started?=#t` set before pre-start queue drain — accepted race.** `transport-start` sets `started?=#t` before draining the pre-start queue; under truly concurrent sends during start there is a theoretical FIFO-inversion/lost-message race (a sender sees `started?=#t` and puts directly on inbox while drain is still running, potentially reordering relative to buffered items). In-memory transport is a single-threaded test transport so this race cannot occur in practice — accepted, out of scope.

---

## Completion Reminder

After `raco test mcp/transport/test/` passes:

1. Open `docs/aide/progress.md`.
2. Find `mcp/transport/in-memory.rkt (M10)` row (~line 101) — flip 📋 → 🚧 → ✅.
3. Find `mcp/transport/test/in-memory-test.rkt` row (~line 103) — flip 📋 → 🚧 → ✅.
4. Do NOT flip the Stage S3 overview row or any other item rows.
