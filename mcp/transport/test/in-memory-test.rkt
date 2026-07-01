#lang racket/base

;; Items 020/021 — tests for mcp/transport (M10 in-memory, via M6 barrel).
;; T1–T10 (item 020): pair wiring, round-trip, async delivery, FIFO ordering,
;; close propagation, on-error + relay survival, opts, pre-start buffering,
;; idempotent start, send-after-close.
;; T11–T14 (item 021): 50-msg no-loss+FIFO (sequential + concurrent senders),
;; message-extra-info surface delivery, concurrent close, peer-onclose-throw.
;; Transport surface imported via the barrel (file "../main.rkt").

(require rackunit
         racket/async-channel
         (file "../main.rkt"))

;; -----------------------------------------------------------------------
;; Watchdog helper — runs thunk in a thread; kills it and fails if it
;; doesn't finish within secs seconds. Guards tests that could hang under
;; a wrong implementation (inline delivery, blocking channels, etc.).
;; -----------------------------------------------------------------------
(define (run-with-watchdog secs thunk fail-msg)
  (define t (thread thunk))
  (unless (sync/timeout secs t)
    (kill-thread t)
    (fail fail-msg)))

;; -----------------------------------------------------------------------
;; T1 — Pair wiring + transport? predicate
;; -----------------------------------------------------------------------
(test-case "T1: pair wiring + transport? predicate"
  (define-values (a b) (in-memory-transport-create-linked-pair))
  (check-pred transport? a)
  (check-pred transport? b)
  (check-pred in-memory-transport? a))

;; -----------------------------------------------------------------------
;; T2 — Each-direction round-trip (extra-info is message-extra-info?)
;; -----------------------------------------------------------------------
(test-case "T2: each-direction round-trip + extra-info type"
  (define-values (a b) (in-memory-transport-create-linked-pair))
  (transport-start a) (transport-start b)
  (define got-b       (make-channel))
  (define got-b-extra (make-channel))
  (set-transport-on-message! b (λ (msg extra)
                                 (channel-put got-b msg)
                                 (channel-put got-b-extra extra)))
  (transport-send a (hasheq 'jsonrpc "2.0" 'method "ping"))
  (check-equal? (sync/timeout 1 got-b) (hasheq 'jsonrpc "2.0" 'method "ping"))
  (check-pred message-extra-info? (sync/timeout 1 got-b-extra))
  ;; Reverse direction
  (define got-a (make-channel))
  (set-transport-on-message! a (λ (msg extra) (channel-put got-a msg)))
  (transport-send b (hasheq 'jsonrpc "2.0" 'method "pong"))
  (check-equal? (sync/timeout 1 got-a) (hasheq 'jsonrpc "2.0" 'method "pong")))

;; -----------------------------------------------------------------------
;; T3 — ASYNC DELIVERY (semaphore-gate; deadlocks under inline; guarded by watchdog)
;; Gate semaphore starts at 0. B's handler calls (semaphore-wait gate) before
;; completing. Under inline delivery transport-send would block on gate on the
;; calling thread → (semaphore-post gate) is never reached → deadlock.
;; The watchdog detects the hang and fails within 5 s.
;; -----------------------------------------------------------------------
(test-case "T3: async delivery (semaphore-gate deadlock test)"
  (run-with-watchdog 5
    (λ ()
      (define-values (a b) (in-memory-transport-create-linked-pair))
      (transport-start a) (transport-start b)
      (define gate (make-semaphore 0))
      (define handler-ran? #f)
      (set-transport-on-message! b
        (λ (msg extra)
          (semaphore-wait gate)        ; blocks relay thread until gate posted
          (set! handler-ran? #t)))
      (transport-send a (hasheq 'jsonrpc "2.0" 'method "async-test"))
      ;; Under async: we reach here. handler-ran? must still be #f.
      (check-false handler-ran?)
      (semaphore-post gate)            ; release relay thread
      ;; Wait for handler to finish
      (check-not-false (sync/timeout 1 (thread (λ ()
                                                 (let loop ()
                                                   (unless handler-ran? (sleep 0.01) (loop))))))))
    "T3: deadlock — transport-send did not return before on-message fired (inline delivery)"))

;; -----------------------------------------------------------------------
;; T4 — FIFO ordering (3 messages; watchdog guarded)
;; -----------------------------------------------------------------------
(test-case "T4: FIFO ordering (3 messages)"
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
    "T4: FIFO ordering hang"))

;; -----------------------------------------------------------------------
;; T5 — on-close fires on both endpoints exactly once; no double-fire
;; -----------------------------------------------------------------------
(test-case "T5: on-close fires on both endpoints exactly once"
  (define-values (a b) (in-memory-transport-create-linked-pair))
  (transport-start a) (transport-start b)
  (define a-count 0) (define b-count 0)
  (set-transport-on-close! a (λ () (set! a-count (+ a-count 1))))
  (set-transport-on-close! b (λ () (set! b-count (+ b-count 1))))
  (transport-close a)
  (sleep 0.05)
  (check-equal? a-count 1)
  (check-equal? b-count 1)
  ;; Double-close: no-op (no double-fire)
  (check-not-exn (λ () (transport-close a)))
  (sleep 0.01)
  (check-equal? a-count 1)
  (check-equal? b-count 1))

;; -----------------------------------------------------------------------
;; T6 — on-error fires on induced failure; relay survives exception
;; -----------------------------------------------------------------------
(test-case "T6: on-error fires; relay survives handler exception"
  (define-values (a b) (in-memory-transport-create-linked-pair))
  (transport-start a) (transport-start b)
  (define got-error #f)
  (define error-latch   (make-channel))
  (define success-latch (make-channel))
  ;; First message: handler throws
  (set-transport-on-error! b (λ (e) (set! got-error e) (channel-put error-latch #t)))
  (set-transport-on-message! b
    (λ (msg extra)
      (if (equal? (hash-ref msg 'method) "boom")
          (error "induced failure")
          (channel-put success-latch #t))))
  (transport-send a (hasheq 'jsonrpc "2.0" 'method "boom"))
  (check-not-false (sync/timeout 1 error-latch))
  (check-pred exn:fail? got-error)
  ;; Relay must still be running: send a second message and assert it arrives
  (transport-send a (hasheq 'jsonrpc "2.0" 'method "survive"))
  (check-not-false (sync/timeout 1 success-latch)))

;; -----------------------------------------------------------------------
;; T7 — related-request-id accepted and ignored
;; -----------------------------------------------------------------------
(test-case "T7: related-request-id accepted and ignored"
  (define-values (a b) (in-memory-transport-create-linked-pair))
  (transport-start a) (transport-start b)
  (check-not-exn
    (λ () (transport-send a (hasheq 'jsonrpc "2.0" 'method "x")
                            (make-transport-send-options #:related-request-id "rid-1"))))
  (check-not-exn
    (λ () (transport-send a (hasheq 'jsonrpc "2.0" 'method "x")
                            (make-transport-send-options #:related-request-id 42)))))

;; -----------------------------------------------------------------------
;; T8 — Pre-start FIFO buffering (3 messages; watchdog guarded)
;; -----------------------------------------------------------------------
(test-case "T8: pre-start FIFO buffering (3 messages)"
  (run-with-watchdog 5
    (λ ()
      (define-values (a b) (in-memory-transport-create-linked-pair))
      (transport-start a)
      ;; b not started — send 3 messages before b's relay thread exists
      (define received '())
      (define done (make-channel))
      (set-transport-on-message! b
        (λ (msg extra)
          (set! received (append received (list (hash-ref msg 'id))))
          (when (= (length received) 3) (channel-put done #t))))
      (for ([i '(1 2 3)])
        (transport-send a (hasheq 'jsonrpc "2.0" 'method "pre" 'id i)))
      (transport-start b)   ; drain pre-start queue in FIFO order
      (check-not-false (sync/timeout 1 done))
      (check-equal? received '(1 2 3)))
    "T8: pre-start buffering hang or wrong FIFO order"))

;; -----------------------------------------------------------------------
;; T9 — transport-start idempotency (double-start RECEIVER: no split stream)
;; Double-starting the RECEIVER b catches the real regression: two relay threads
;; competing on b's inbox → messages duplicated or delivered out of order.
;; Double-starting only the sender would be invisible to this failure mode.
;; -----------------------------------------------------------------------
(test-case "T9: transport-start idempotency (double-start receiver)"
  (run-with-watchdog 5
    (λ ()
      (define-values (a b) (in-memory-transport-create-linked-pair))
      (transport-start a) (transport-start b)
      (transport-start b)   ; second start on RECEIVER — must not spawn second relay thread
      (define received '())
      (define done (make-channel))
      (set-transport-on-message! b
        (λ (msg extra)
          (set! received (append received (list (hash-ref msg 'id))))
          (when (= (length received) 3) (channel-put done #t))))
      (for ([i '(1 2 3)])
        (transport-send a (hasheq 'jsonrpc "2.0" 'method "m" 'id i)))
      (check-not-false (sync/timeout 1 done))
      ;; Exactly 3 deliveries in order (no duplication from two competing relay threads)
      (check-equal? received '(1 2 3)))
    "T9: idempotency hang"))

;; -----------------------------------------------------------------------
;; T10 — send-after-close raises exn:fail?
;; -----------------------------------------------------------------------
(test-case "T10: send-after-close raises exn:fail?"
  (define-values (a b) (in-memory-transport-create-linked-pair))
  (transport-start a) (transport-start b)
  (transport-close a)
  (check-exn exn:fail? (λ () (transport-send a (hasheq 'jsonrpc "2.0" 'method "x")))))

;; -----------------------------------------------------------------------
;; T11a — 50-message no-loss + FIFO (sequential sender), both directions
;; -----------------------------------------------------------------------
(test-case "T11a: 50-message no-loss + FIFO (sequential, both directions)"
  (run-with-watchdog 10
    (λ ()
      ;; A→B
      (define-values (a b) (in-memory-transport-create-linked-pair))
      (transport-start a) (transport-start b)
      (define recv-b '())
      (define done-b (make-channel))
      (set-transport-on-message! b
        (λ (msg extra)
          (set! recv-b (cons (hash-ref msg 'id) recv-b))
          (when (= (length recv-b) 50) (channel-put done-b #t))))
      (for ([i (in-range 50)])
        (transport-send a (hasheq 'jsonrpc "2.0" 'method "m" 'id i)))
      (check-not-false (sync/timeout 5 done-b))
      (check-equal? (reverse recv-b) (build-list 50 values))
      ;; B→A — fresh pair
      (define-values (c d) (in-memory-transport-create-linked-pair))
      (transport-start c) (transport-start d)
      (define recv-c '())
      (define done-c (make-channel))
      (set-transport-on-message! c
        (λ (msg extra)
          (set! recv-c (cons (hash-ref msg 'id) recv-c))
          (when (= (length recv-c) 50) (channel-put done-c #t))))
      (for ([i (in-range 50)])
        (transport-send d (hasheq 'jsonrpc "2.0" 'method "m" 'id i)))
      (check-not-false (sync/timeout 5 done-c))
      (check-equal? (reverse recv-c) (build-list 50 values)))
    "T11a: 50-message sequential no-loss/FIFO hang"))

;; -----------------------------------------------------------------------
;; T11b — 50-message no-loss with 5 concurrent senders; per-sender FIFO
;; -----------------------------------------------------------------------
(test-case "T11b: 50-message no-loss, concurrent senders, per-sender FIFO"
  (run-with-watchdog 10
    (λ ()
      (define-values (a b) (in-memory-transport-create-linked-pair))
      (transport-start a) (transport-start b)
      (define recv '())
      (define done (make-channel))
      (set-transport-on-message! b
        (λ (msg extra)
          (set! recv (cons (hash-ref msg 'id) recv))
          (when (= (length recv) 50) (channel-put done #t))))
      ;; 5 threads, thread-k sends ids [k*10, k*10+9]
      (for ([k (in-range 5)])
        (thread (λ ()
                  (for ([j (in-range 10)])
                    (transport-send a (hasheq 'jsonrpc "2.0" 'method "m"
                                              'id (+ (* k 10) j)))))))
      (check-not-false (sync/timeout 5 done))
      (define ordered (reverse recv))
      (check-equal? (length ordered) 50)
      ;; No loss: every id 0..49 present exactly once
      (check-equal? (sort ordered <) (build-list 50 values))
      ;; Per-sender FIFO: each sender's subsequence is ascending
      (for ([k (in-range 5)])
        (define lo (* k 10)) (define hi (+ lo 9))
        (define sub (filter (λ (id) (and (>= id lo) (<= id hi))) ordered))
        (check-equal? sub (sort sub <)
                      (format "sender ~a subsequence out of order: ~a" k sub))))
    "T11b: concurrent-senders no-loss hang"))

;; -----------------------------------------------------------------------
;; T12 — message-extra-info surface delivery (all accessors #f for in-memory)
;; -----------------------------------------------------------------------
(test-case "T12: message-extra-info surface delivery"
  (define-values (a b) (in-memory-transport-create-linked-pair))
  (transport-start a) (transport-start b)
  (define extra-chan (make-channel))
  (set-transport-on-message! b (λ (msg extra) (channel-put extra-chan extra)))
  (transport-send a (hasheq 'jsonrpc "2.0" 'method "x"))
  (define extra (sync/timeout 1 extra-chan))
  (check-pred message-extra-info? extra)
  (check-false (message-extra-info-session extra))
  (check-false (message-extra-info-auth extra))
  (check-false (message-extra-info-http-req-info extra)))

;; -----------------------------------------------------------------------
;; T13 — Concurrent close from both sides; each on-close fires 1–2×
;; closed? guard (in-memory.rkt:80) is non-atomic → at-least-once, at-most-twice.
;; -----------------------------------------------------------------------
(test-case "T13: concurrent close from both sides (each on-close 1-2x)"
  (define-values (a b) (in-memory-transport-create-linked-pair))
  (transport-start a) (transport-start b)
  (define a-count 0) (define b-count 0)
  (set-transport-on-close! a (λ () (set! a-count (+ a-count 1))))
  (set-transport-on-close! b (λ () (set! b-count (+ b-count 1))))
  (define t1 (thread (λ () (transport-close a))))
  (define t2 (thread (λ () (transport-close b))))
  (check-not-false (sync/timeout 5 t1))
  (check-not-false (sync/timeout 5 t2))
  (sleep 0.05)
  (check-true (and (>= a-count 1) (<= a-count 2)) (format "a-count=~a" a-count))
  (check-true (and (>= b-count 1) (<= b-count 2)) (format "b-count=~a" b-count)))

;; -----------------------------------------------------------------------
;; T14 — Peer on-close throw aborts own on-close (Racket close order)
;; transport-close(A) recurses into close(B); B's on-close throws; exn unwinds
;; past A's own on-close call → A's on-close never reached.
;; -----------------------------------------------------------------------
(test-case "T14: peer on-close throw aborts own on-close"
  (define-values (a b) (in-memory-transport-create-linked-pair))
  (transport-start a) (transport-start b)
  (define a-closed? #f)
  (set-transport-on-close! b (λ () (error "peer-close-boom")))
  (set-transport-on-close! a (λ () (set! a-closed? #t)))
  (check-exn exn:fail? (λ () (transport-close a)))
  (check-false a-closed?))
