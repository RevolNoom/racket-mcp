#lang racket/base

;; Tests for mcp/core/errors.rkt — the ENCODE half of the exn<->JSON-RPC seam
;; (item 006). rackunit `check-*` forms run at module top level, so
;; `racket mcp/core/test/errors-test.rkt` from the repo root executes the suite.
;; Silence + exit 0 = all checks passed; a failed check prints a FAILURE block.
;;
;; SCOPE: encode-only. The DECODE-direction tests (-32042 -> URL-elicitation
;; exn; -32004 -> unsupported-version exn) are item 007's; they are NOT here.

(require rackunit
         (file "../errors.rkt")
         (only-in (file "../types/constants.rkt")
                  INTERNAL-ERROR PARSE-ERROR INVALID-REQUEST METHOD-NOT-FOUND
                  INVALID-PARAMS RESOURCE-NOT-FOUND
                  MISSING-REQUIRED-CLIENT-CAPABILITY
                  UNSUPPORTED-PROTOCOL-VERSION URL-ELICITATION-REQUIRED)
         (only-in (file "../types/spec-2025-11-25.rkt")
                  jsonrpc-error? jsonrpc-error-code jsonrpc-error-message
                  jsonrpc-error-data jsonrpc-error->json absent absent?)
         (only-in (file "../types/guards.rkt")
                  is-jsonrpc-error?))

;; ===========================================================================
;; Part 1 — construction with stable codes (anti-magic: assert against the
;; imported constants.rkt bindings, never a literal).
;; ===========================================================================
(check = (mcp-error-code (make-mcp-error INTERNAL-ERROR "x")) INTERNAL-ERROR)
(check = (mcp-error-code (make-protocol-error INVALID-PARAMS "x")) INVALID-PARAMS)
(check = (mcp-error-code (make-protocol-error METHOD-NOT-FOUND "x")) METHOD-NOT-FOUND)
(check = (mcp-error-code (make-auth-error MISSING-REQUIRED-CLIENT-CAPABILITY "x"))
       MISSING-REQUIRED-CLIENT-CAPABILITY)

(check-equal? (exn-message (make-mcp-error INTERNAL-ERROR "boom")) "boom")

;; data carriage: present payload survives; default is the `absent` sentinel.
(check-equal? (mcp-error-data (make-mcp-error RESOURCE-NOT-FOUND "x" (hasheq 'uri "y")))
              (hasheq 'uri "y"))
(check-true (absent? (mcp-error-data (make-mcp-error RESOURCE-NOT-FOUND "x"))))

;; Code preserved EXACTLY (no coercion) — a negative round-trips identically.
(check = (mcp-error-code (make-auth-error -1 "a")) -1)

;; continuation-marks populated by default (advisory 5: prove #:marks is real).
(check-true (continuation-mark-set? (exn-continuation-marks (make-mcp-error INTERNAL-ERROR "m"))))

;; ===========================================================================
;; Part 1b — constructor contract violations (advisory 1).
;; ===========================================================================
;; non-integer code is rejected.
(check-exn exn:fail:contract? (lambda () (make-mcp-error "not-an-int" "msg")))
;; non-string message is rejected.
(check-exn exn:fail:contract? (lambda () (make-protocol-error INVALID-PARAMS 42)))
;; the optional data contract ADMITS `absent` (positive assertion).
(check-true (mcp-error? (make-mcp-error INTERNAL-ERROR "ok" absent)))

;; ===========================================================================
;; Part 2 — predicate discrimination matrix.
;; ===========================================================================
(define b (make-mcp-error INTERNAL-ERROR "b"))
(define p (make-protocol-error INVALID-PARAMS "p"))
(define a (make-auth-error -1 "a"))
(define g (make-exn:fail "g" (current-continuation-marks)))
(define caught (with-handlers ([exn:fail? values]) (car '())))

;; b : base
(check-true  (exn:fail? b))
(check-true  (mcp-error? b))
(check-false (protocol-error? b))
(check-false (auth-error? b))
;; p : protocol
(check-true  (exn:fail? p))
(check-true  (mcp-error? p))
(check-true  (protocol-error? p))
(check-false (auth-error? p))
;; a : auth
(check-true  (exn:fail? a))
(check-true  (mcp-error? a))
(check-false (protocol-error? a))
(check-true  (auth-error? a))
;; g : generic exn:fail
(check-true  (exn:fail? g))
(check-false (mcp-error? g))
(check-false (protocol-error? g))
(check-false (auth-error? g))
;; caught generic (car '())
(check-true  (exn:fail? caught))
(check-false (mcp-error? caught))
(check-false (protocol-error? caught))
(check-false (auth-error? caught))

;; a raised mcp error is catchable by the predicate handler.
(check-true (with-handlers ([mcp-error? (lambda (_) #t)]) (raise p)))

;; ===========================================================================
;; Part 3 — ENCODE produces a spec-correct error object (core requirement).
;; ===========================================================================
;; mcp subtype -> its own code; absent data stays absent.
(define j (exn->jsonrpc-error (make-protocol-error INVALID-PARAMS "bad")))
(check-true (jsonrpc-error? j))
(check = (jsonrpc-error-code j) INVALID-PARAMS)
(check-equal? (jsonrpc-error-message j) "bad")
(check-true (absent? (jsonrpc-error-data j)))

;; data preserved through encode.
(define jd (exn->jsonrpc-error (make-mcp-error RESOURCE-NOT-FOUND "nf" (hasheq 'uri "u"))))
(check-equal? (jsonrpc-error-data jd) (hasheq 'uri "u"))

;; THE -32603 FALLBACK (HARD): synthetic non-mcp exn.
(define j2 (exn->jsonrpc-error (make-exn:fail "kaboom" (current-continuation-marks))))
(check = (jsonrpc-error-code j2) INTERNAL-ERROR)
(check-equal? (jsonrpc-error-message j2) "kaboom")
(check-true (absent? (jsonrpc-error-data j2)))

;; THE -32603 FALLBACK (HARD): a REAL thrown generic exn.
(define j3 (exn->jsonrpc-error (with-handlers ([exn:fail? values]) (vector-ref (vector) 0))))
(check = (jsonrpc-error-code j3) INTERNAL-ERROR)

;; auth subtype encodes with its code (advisory 3: inheritance for data/code).
(define ja (exn->jsonrpc-error (make-auth-error MISSING-REQUIRED-CLIENT-CAPABILITY "no cap")))
(check = (jsonrpc-error-code ja) MISSING-REQUIRED-CLIENT-CAPABILITY)

;; Encode inheritance for structured data through BOTH non-base subtypes
;; (advisory 3 + 007-seam): the single (mcp-error? e) branch handles all three.
(define jproto (exn->jsonrpc-error
                (make-protocol-error UNSUPPORTED-PROTOCOL-VERSION "bad ver"
                                     (hasheq 'supported '("2025-11-25" "2025-06-18")))))
(check = (jsonrpc-error-code jproto) UNSUPPORTED-PROTOCOL-VERSION)
(check-equal? (jsonrpc-error-data jproto) (hasheq 'supported '("2025-11-25" "2025-06-18")))
(define jauth (exn->jsonrpc-error
               (make-auth-error MISSING-REQUIRED-CLIENT-CAPABILITY "need cap"
                                (hasheq 'capability "roots"))))
(check-equal? (jsonrpc-error-data jauth) (hasheq 'capability "roots"))

;; Empty message is valid (not omitted, not coerced).
(check-equal? (jsonrpc-error-message (exn->jsonrpc-error (make-mcp-error INTERNAL-ERROR "")))
              "")

;; ===========================================================================
;; Part 4 — serialized wire jsexpr is spec-correct (absent-vs-null).
;; ===========================================================================
(define w (jsonrpc-error->json (exn->jsonrpc-error (make-protocol-error INVALID-REQUEST "x"))))
(check-true (hash-eq? w))
(check = (hash-ref w 'code) INVALID-REQUEST)
(check-equal? (hash-ref w 'message) "x")
;; absent data OMITTED — never 'data: 'null.
(check-false (hash-has-key? w 'data))

;; present data emitted.
(define wd (jsonrpc-error->json (exn->jsonrpc-error
                                 (make-mcp-error PARSE-ERROR "p" (hasheq 'detail "d")))))
(check-true (hash-has-key? wd 'data))
(check-equal? (hash-ref wd 'data) (hasheq 'detail "d"))

;; the convenience wire wrapper agrees with the manual serialize.
(check-equal? (exn->jsonrpc-error-jsexpr (make-protocol-error INVALID-REQUEST "x")) w)

;; valid-error-object shape: code is exact-integer, message is string.
(check-true (exact-integer? (hash-ref w 'code)))
(check-true (string? (hash-ref w 'message)))

;; The encoded error composes into a wire-valid error response envelope
;; (encode<->guard parity): is-jsonrpc-error? accepts it.
(check-true (is-jsonrpc-error? (hasheq 'jsonrpc "2.0" 'id 1 'error w)))

;; ===========================================================================
;; Part 4b — falsy-data carriage matrix (advisory 2): #f, 'null, 0, "" each
;; SURVIVE into the wire object (a truthiness presence check would drop them).
;; ===========================================================================
(for ([falsy (in-list (list #f 'null 0 ""))])
  (define wf (jsonrpc-error->json (exn->jsonrpc-error
                                   (make-mcp-error INTERNAL-ERROR "x" falsy))))
  (check-true (hash-has-key? wf 'data)
              (format "falsy data ~s must be present on the wire" falsy))
  (check-equal? (hash-ref wf 'data) falsy
                (format "falsy data ~s must survive verbatim" falsy)))

;; empty hasheq is a present (not absent) payload.
(define we (jsonrpc-error->json (exn->jsonrpc-error
                                 (make-mcp-error INTERNAL-ERROR "x" (hasheq)))))
(check-true (hash-has-key? we 'data))
(check-equal? (hash-ref we 'data) (hasheq))

;; nested object/array: data is copied BY REFERENCE, not inspected/flattened.
(define nested (hasheq 'a (list 1 2 (hasheq 'b "c")) 'd '()))
(define wn (jsonrpc-error->json (exn->jsonrpc-error
                                 (make-mcp-error INTERNAL-ERROR "x" nested))))
(check-eq? (hash-ref wn 'data) nested)

;; ===========================================================================
;; Part 5 — 007-readiness (lightweight, anti-vacuous): the constructors accept
;; the shape 007's decode will use, with no new struct.
;; ===========================================================================
(define decoded (make-protocol-error URL-ELICITATION-REQUIRED "url required"
                                      (hasheq 'elicitations '())))
(check-true (protocol-error? decoded))
(check = (mcp-error-code decoded) URL-ELICITATION-REQUIRED)
(check-equal? (mcp-error-data decoded) (hasheq 'elicitations '()))

(displayln "errors-test.rkt: all checks executed")
