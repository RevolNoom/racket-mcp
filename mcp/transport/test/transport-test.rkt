#lang racket/base

;; Item 019 — unit tests for gen:transport port (M6).
;; Pure logic; no external services. Run: raco test mcp/transport/test/

(require rackunit
         (file "../transport.rkt")
         (file "../../core/shared/auth.rkt"))

;; -----------------------------------------------------------------------
;; Full concrete stub — implements ALL gen:transport methods.
;; Uses mutable fields for the three sink callbacks.
;; -----------------------------------------------------------------------
(struct test-transport
  ([on-message #:mutable]
   [on-close   #:mutable]
   [on-error   #:mutable]
   [session-id])
  #:methods gen:transport
  ;; define-generics requires the generic name ("transport") as first arg.
  [(define (transport-start transport) (void))
   ;; %transport-send: opts always present at generic level (#f if 2-arg call).
   ;; Accepts and ignores opts (including non-#f related-request-id) — INERT.
   (define (%transport-send transport msg opts) (void))
   (define (transport-close transport) (void))
   ;; Sink getters
   (define (transport-on-message transport) (test-transport-on-message transport))
   (define (transport-on-close   transport) (test-transport-on-close transport))
   (define (transport-on-error   transport) (test-transport-on-error transport))
   ;; Sink setters
   (define (set-transport-on-message! transport h) (set-test-transport-on-message! transport h))
   (define (set-transport-on-close!   transport h) (set-test-transport-on-close! transport h))
   (define (set-transport-on-error!   transport h) (set-test-transport-on-error! transport h))
   ;; Session accessor
   (define (transport-session-id transport) (test-transport-session-id transport))])

;; Partial stub — omits %transport-send deliberately (triggers default raise).
(struct partial-transport ()
  #:methods gen:transport
  [(define (transport-start transport) (void))
   (define (transport-close transport) (void))])

;; -----------------------------------------------------------------------
;; Test helpers
;; -----------------------------------------------------------------------
(define s   (test-transport #f #f #f "sess-1"))
(define ai  (make-auth-info #:token "t" #:client-id "c"))
(define msg (hasheq 'jsonrpc "2.0" 'method "ping"))
(define pt  (partial-transport))

;; -----------------------------------------------------------------------
;; Part 1 — full stub satisfies gen:transport
;; -----------------------------------------------------------------------
(check-pred transport? s)
(check-not-exn (λ () (transport-start s)))
(check-not-exn (λ () (transport-send s msg)))  ; 2-arg

;; -----------------------------------------------------------------------
;; Part 2 — transport-send arity + related-request-id INERT (C4)
;; -----------------------------------------------------------------------
(check-not-exn (λ () (transport-send s msg (make-transport-send-options))))
; 3-arg, all-#f opts

(define opts-str (make-transport-send-options #:related-request-id "rid-1"))
(check-not-exn (λ () (transport-send s msg opts-str)))  ; string related-request-id

(define opts-int (make-transport-send-options #:related-request-id 42))
(check-not-exn (λ () (transport-send s msg opts-int)))  ; exact-integer related-request-id

(check-not-exn (λ () (transport-close s)))

;; -----------------------------------------------------------------------
;; Part 3 — partial stub triggers default raise (C2)
;; -----------------------------------------------------------------------
(check-exn exn:fail? (λ () (transport-send pt msg)))

;; -----------------------------------------------------------------------
;; Part 4 — sinks set + invoked with extra-info asserted (C3)
;; -----------------------------------------------------------------------

;; on-message with real extra-info
(define got-msg   #f)
(define got-extra 'unset)

(set-transport-on-message! s (λ (m e) (set! got-msg m) (set! got-extra e)))
(define ei (make-message-extra-info #:session "s1" #:auth ai #:http-req-info #f))
((transport-on-message s) msg ei)

(check-equal? got-msg msg)
(check-pred   message-extra-info? got-extra)
(check-equal? (message-extra-info-session got-extra) "s1")
(check-equal? (message-extra-info-auth got-extra) ai)
(check-false  (message-extra-info-http-req-info got-extra))

;; on-message with #f extra (unauthenticated path)
(set! got-extra 'unset)
((transport-on-message s) msg #f)
(check-false got-extra)

;; on-close
(define closed? #f)
(set-transport-on-close! s (λ () (set! closed? #t)))
((transport-on-close s))
(check-true closed?)

;; on-error
(define got-err #f)
(set-transport-on-error! s (λ (e) (set! got-err e)))
(define dummy-err (make-exn:fail "boom" (current-continuation-marks)))
((transport-on-error s) dummy-err)
(check-pred exn:fail? got-err)

;; -----------------------------------------------------------------------
;; Part 5 — message-extra-info field surface + zero-arg constructor
;; -----------------------------------------------------------------------
(define ei2 (make-message-extra-info #:session "s1" #:auth ai #:http-req-info #f))
(check-equal? (message-extra-info-session      ei2) "s1")
(check-equal? (message-extra-info-auth         ei2) ai)
(check-false  (message-extra-info-http-req-info ei2))

(define ei0 (make-message-extra-info))
(check-false (message-extra-info-session       ei0))
(check-false (message-extra-info-auth          ei0))
(check-false (message-extra-info-http-req-info ei0))

;; -----------------------------------------------------------------------
;; Part 6 — contract rejection (C1)
;; -----------------------------------------------------------------------

;; message-extra-info contracts
(check-exn exn:fail:contract? (λ () (make-message-extra-info #:session 42)))
(check-exn exn:fail:contract? (λ () (make-message-extra-info #:auth "not-auth-info")))

;; transport-send-options contracts
(check-exn exn:fail:contract?
           (λ () (make-transport-send-options #:related-request-id 'sym)))
(check-exn exn:fail:contract?
           (λ () (make-transport-send-options #:resumption-token 99)))

;; -----------------------------------------------------------------------
;; Part 7 — transport-session-id accessor
;; -----------------------------------------------------------------------
(check-equal? (transport-session-id s) "sess-1")

;; -----------------------------------------------------------------------
;; Part 8 — transport-send-options field surface
;; -----------------------------------------------------------------------
(define opts (make-transport-send-options #:related-request-id "req-1"
                                          #:resumption-token "tok"))
(check-equal? (transport-send-options-related-request-id opts) "req-1")
(check-equal? (transport-send-options-resumption-token   opts) "tok")

(define opts0 (make-transport-send-options))
(check-false (transport-send-options-related-request-id opts0))
(check-false (transport-send-options-resumption-token   opts0))
