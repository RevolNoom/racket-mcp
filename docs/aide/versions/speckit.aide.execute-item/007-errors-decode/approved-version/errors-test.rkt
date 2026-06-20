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
                  ;; jsonrpc-error STRUCT CONSTRUCTOR + accessors for DECODE (item 007)
                  jsonrpc-error
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

;; ===========================================================================
;; Part 6 — DECODE (item 007): jsonrpc-error struct -> typed protocol exn.
;; Mirrors `ProtocolError.fromError` (errors.ts:21-39). The decode always
;; yields a :protocol exn (subtype erasure — the wire carries only the code).
;; ===========================================================================

;; --- 6a: special-code -> typed-error decodes (the queue's core claims) ------
;; -32042 with good data -> URL-elicitation-typed protocol error.
(define du (jsonrpc-error->exn
            (jsonrpc-error URL-ELICITATION-REQUIRED "url required"
                           (hasheq 'elicitations '()))))
(check-true (protocol-error? du))
(check = (mcp-error-code du) URL-ELICITATION-REQUIRED)
(check-equal? (mcp-error-data du) (hasheq 'elicitations '()))
(check-equal? (exn-message du) "url required")

;; -32004 with good data -> unsupported-version-typed protocol error.
(define dv (jsonrpc-error->exn
            (jsonrpc-error UNSUPPORTED-PROTOCOL-VERSION "bad ver"
                           (hasheq 'supported '("2025-11-25" "2025-06-18")
                                   'requested "1999-01-01"))))
(check-true (protocol-error? dv))
(check = (mcp-error-code dv) UNSUPPORTED-PROTOCOL-VERSION)
(check-equal? (mcp-error-data dv)
              (hasheq 'supported '("2025-11-25" "2025-06-18")
                      'requested "1999-01-01"))

;; (S5) decode does NOT synthesize a default message even on the SPECIALIZED
;; branch: a -32042 with "" message + good data threads "" verbatim (NOT the
;; TS-style synthesized "URL elicitation required", errors.ts:47).
(define dem (jsonrpc-error->exn
             (jsonrpc-error URL-ELICITATION-REQUIRED "" (hasheq 'elicitations '()))))
(check-equal? (exn-message dem) "")

;; --- 6b: unknown / generic code -> generic typed error ----------------------
;; A known-but-unspecialized code preserves the RECEIVED code, is :protocol,
;; not :auth, and carries absent data.
(define dg (jsonrpc-error->exn (jsonrpc-error INVALID-PARAMS "bad params" absent)))
(check-true (protocol-error? dg))
(check = (mcp-error-code dg) INVALID-PARAMS)
(check-true (absent? (mcp-error-data dg)))
(check-false (auth-error? dg))

;; A genuinely-unknown code is preserved exactly (NOT defaulted to -32603 etc.).
(define dx (jsonrpc-error->exn (jsonrpc-error -39999 "weird" absent)))
(check = (mcp-error-code dx) -39999)
(check-true (protocol-error? dx))

;; --- 6c: special code with absent/malformed data -> generic typed error -----
;; NON-VACUOUS gate tests: a code-only impl (dropping the shape conjuncts)
;; would FAIL the object-but-wrong-shape cases below.

;; -32042 with NO data: falls through, right code, no throw.
(define dun (jsonrpc-error->exn
             (jsonrpc-error URL-ELICITATION-REQUIRED "x" absent)))
(check = (mcp-error-code dun) URL-ELICITATION-REQUIRED)
(check-true (protocol-error? dun))

;; (C2) -32042 with an OBJECT lacking 'elicitations -> generic branch, code
;; preserved, data carried verbatim, no throw. Pins the 'elicitations conjunct
;; (mirrors the `if (errorData.elicitations)` miss at errors.ts:25).
(define dun2 (jsonrpc-error->exn
              (jsonrpc-error URL-ELICITATION-REQUIRED "x" (hasheq 'foo 1))))
(check = (mcp-error-code dun2) URL-ELICITATION-REQUIRED)
(check-true (protocol-error? dun2))
(check-equal? (mcp-error-data dun2) (hasheq 'foo 1))

;; -32004 with malformed 'supported (not a list) -> generic branch, no throw.
(define dvm (jsonrpc-error->exn
             (jsonrpc-error UNSUPPORTED-PROTOCOL-VERSION "x"
                            (hasheq 'supported "nope" 'requested "v"))))
(check = (mcp-error-code dvm) UNSUPPORTED-PROTOCOL-VERSION)
(check-true (protocol-error? dvm))

;; (C3) -32004 with valid 'supported but a non-string 'requested -> generic
;; branch, no throw. Pins the 'requested-is-a-string conjunct.
(define dvn (jsonrpc-error->exn
             (jsonrpc-error UNSUPPORTED-PROTOCOL-VERSION "x"
                            (hasheq 'supported '("2025-11-25") 'requested 7))))
(check = (mcp-error-code dvn) UNSUPPORTED-PROTOCOL-VERSION)
(check-true (protocol-error? dvn))

;; (C3) -32004 with valid 'supported but 'requested MISSING -> generic branch.
(define dvn2 (jsonrpc-error->exn
              (jsonrpc-error UNSUPPORTED-PROTOCOL-VERSION "x"
                             (hasheq 'supported '("2025-11-25")))))
(check = (mcp-error-code dvn2) UNSUPPORTED-PROTOCOL-VERSION)
(check-true (protocol-error? dvn2))

;; --- 6d: the ROUND-TRIP invariant (encode∘decode symmetry) ------------------
;; For each e, (jsonrpc-error->exn (exn->jsonrpc-error e)) preserves
;; code/message/data. Subtype is intentionally NOT preserved — ENCODE flattens
;; any subtype to a code-bearing jsonrpc-error, so DECODE always reconstructs a
;; :protocol exn (asserted below for the base + auth cases).
(for ([e (in-list
          (list (make-protocol-error INVALID-PARAMS "bad")
                (make-protocol-error URL-ELICITATION-REQUIRED "u"
                                     (hasheq 'elicitations '()))
                (make-protocol-error UNSUPPORTED-PROTOCOL-VERSION "v"
                                     (hasheq 'supported '("a") 'requested "b"))
                (make-mcp-error RESOURCE-NOT-FOUND "nf" (hasheq 'uri "u"))
                (make-auth-error MISSING-REQUIRED-CLIENT-CAPABILITY "x"
                                 (hasheq 'capability "roots"))))])
  (define r (jsonrpc-error->exn (exn->jsonrpc-error e)))
  (check = (mcp-error-code r) (mcp-error-code e))
  (check-equal? (exn-message r) (exn-message e))
  (check-equal? (mcp-error-data r) (mcp-error-data e)))

;; (S2/S3) subtype-erasure asymmetry, ASSERTED: a BASE mcp error and an AUTH
;; error both DECODE to a :protocol exn (never :auth). This asymmetry is
;; correct + intended — code/message/data are the invariants, subtype is not.
(define rb (jsonrpc-error->exn
            (exn->jsonrpc-error (make-mcp-error RESOURCE-NOT-FOUND "nf"
                                                (hasheq 'uri "u")))))
(check-true (protocol-error? rb))
(check-false (auth-error? rb))
(define rauth (jsonrpc-error->exn
               (exn->jsonrpc-error (make-auth-error MISSING-REQUIRED-CLIENT-CAPABILITY
                                                    "x" (hasheq 'capability "roots")))))
(check-true (protocol-error? rauth))
(check-false (auth-error? rauth))

;; (S1) reverse fixpoint: (exn->jsonrpc-error (jsonrpc-error->exn j)) equal? j.
;; The SPECIALIZED-branch fixpoint proves the specialized path carries data
;; verbatim through a full wire->exn->wire trip.
(define j-spec (jsonrpc-error URL-ELICITATION-REQUIRED "u" (hasheq 'elicitations '())))
(check-equal? (exn->jsonrpc-error (jsonrpc-error->exn j-spec)) j-spec)
(define j-ver (jsonrpc-error UNSUPPORTED-PROTOCOL-VERSION "v"
                             (hasheq 'supported '("a") 'requested "b")))
(check-equal? (exn->jsonrpc-error (jsonrpc-error->exn j-ver)) j-ver)
(define j-gen (jsonrpc-error INVALID-PARAMS "x" absent))
(check-equal? (exn->jsonrpc-error (jsonrpc-error->exn j-gen)) j-gen)

;; --- 6e: decoded error is a raisable, catchable exn (interop) ---------------
(check-true (with-handlers ([protocol-error? (lambda (_) #t)])
              (raise (jsonrpc-error->exn
                      (jsonrpc-error URL-ELICITATION-REQUIRED "x"
                                     (hasheq 'elicitations '()))))))
(check-true (exn:fail? du))
(check-true (mcp-error? du))

;; --- 6f: data-carriage / no-coercion matrix (decode side) -------------------
;; Falsy/odd present data survives verbatim through a generic-code decode.
(for ([d (in-list (list #f 'null 0 "" (hasheq)))])
  (define r (jsonrpc-error->exn (jsonrpc-error INTERNAL-ERROR "x" d)))
  (check-equal? (mcp-error-data r) d
                (format "decoded falsy data ~s must survive verbatim" d)))

;; nested data copied BY REFERENCE (not inspected/flattened).
(define nested6 (hasheq 'a (list 1 2)))
(check-eq? (mcp-error-data (jsonrpc-error->exn (jsonrpc-error INTERNAL-ERROR "x" nested6)))
           nested6)

;; absent data stays absent.
(check-true (absent? (mcp-error-data
                      (jsonrpc-error->exn (jsonrpc-error INTERNAL-ERROR "x" absent)))))

;; --- 6g: the contract rejects a non-jsonrpc-error? input --------------------
;; A raw wire hasheq is NOT a jsonrpc-error?; the (-> jsonrpc-error? ...)
;; contract rejects it (the canonical decode input is the struct, not the hash).
(check-exn exn:fail:contract?
           (lambda () (jsonrpc-error->exn (hasheq 'code -32602 'message "x"))))

(displayln "errors-test.rkt: all checks executed")
