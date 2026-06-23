#lang racket/base

;; Stage S1 demo + closeout witness (work item 009).
;;
;; A downstream consumer's view of the S1 foundation: it requires ONLY the
;; item-008 curated barrel `mcp/core/main.rkt` (NOT the underlying per-revision
;; modules), proving the barrel is a usable single entry point (architecture
;; §1.3). It exercises the roadmap S1 Demo line (roadmap.md:99):
;;
;;   1. parse a sample `initialize` request from JSON -> struct, print, re-emit
;;   2. parse a sample `tools/call` request from JSON -> struct, print, re-emit
;;   3. take a malformed message -> convert to a spec-correct JSON-RPC error
;;      object via the errors.rkt ENCODE path (architecture §4.1 boundary)
;;   4. (bonus) round-trip a full JSON-RPC error-response envelope
;;
;; This adds NO new protocol types/structs/contracts/errors — it is a pure
;; consumer over the already-✅ items 001–008.
;;
;; "Re-emit identically" = canonical jsexpr equality (`jsexpr=?`, object keys as
;; unordered sets), NOT a byte/string compare — write-json key order is not
;; guaranteed and `initialize`'s `extraUnknownKey` is intentionally dropped on
;; decode. Same semantics as spec-2025-11-25-test.rkt:45–60.
;;
;; The demo's decoders are the per-revision (`r25:`-prefixed) decoders reached
;; through the barrel; the fixtures are 2025-11-25-shaped. A real protocol layer
;; (S4+) would further normalize these via the N1 façade, but the JSON<->struct
;; round-trip the roadmap line specifies is fully exercised at this level.
;;
;; Plain `racket mcp/core/demo/s1-demo.rkt` prints the transcript; the
;; `module+ test` submodule holds the rackunit assertions so `raco test` makes
;; the round-trip + error-encode claims non-vacuous and CI-checkable.

(require racket/pretty
         json
         racket/runtime-path
         racket/contract
         (only-in (file "../main.rkt")
                  ;; per-revision decoders/serializers (r25:-prefixed via item 008)
                  r25:json->initialize-request    r25:initialize-request->json
                  r25:json->call-tool-request     r25:call-tool-request->json
                  r25:json->jsonrpc-error-response r25:jsonrpc-error-response->json
                  ;; Arm 3 — the -params decoder + its contract. The decoder does
                  ;; NOT self-reject (name=42 is ACCEPTED); the contract is what
                  ;; raises. Both VERIFIED reachable through the barrel.
                  r25:json->call-tool-request-params r25:call-tool-request-params/c
                  ;; error ENCODE path (items 006/007) + a constant (item 001)
                  exn->jsonrpc-error-jsexpr make-protocol-error INTERNAL-ERROR))

;; Fixtures located relative to THIS file (not CWD), so `racket <demo>` works
;; from any working directory — same idiom as spec-2025-11-25-test.rkt:40.
(define-runtime-path fixtures "../types/test/fixtures")
(define (read-fx name) (call-with-input-file (build-path fixtures name) read-json))

;; canonical jsexpr equality — unordered object keys, ordered lists, numeric `=`
;; (same semantics as spec-2025-11-25-test.rkt:45–60).
(define (jsexpr=? a b)
  (cond
    [(and (hash? a) (hash? b))
     (and (= (hash-count a) (hash-count b))
          (for/and ([(k v) (in-hash a)])
            (and (hash-has-key? b k) (jsexpr=? v (hash-ref b k)))))]
    [(and (list? a) (list? b))
     (and (= (length a) (length b)) (andmap jsexpr=? a b))]
    [(and (number? a) (number? b)) (= a b)]
    [else (equal? a b)]))

;; ---- Arm 1: initialize round-trip (extraUnknownKey is dropped on decode) ----
(define init-orig   (read-fx "initialize-request.json"))
(define init-struct (r25:json->initialize-request init-orig))
(define init-rt     (r25:initialize-request->json init-struct))
;; the decoder keeps known fields + _meta, so the re-emit legitimately omits the
;; unknown key; expect the original with extraUnknownKey pruned from params
;; (mirrors spec-2025-11-25-test.rkt:77–81).
(define init-expect
  (hash-set init-orig 'params
            (hash-remove (hash-ref init-orig 'params) 'extraUnknownKey)))

;; ---- Arm 2: tools/call round-trip (no dropped key) ----
(define call-orig   (read-fx "tools-call-request.json"))
(define call-struct (r25:json->call-tool-request call-orig))
(define call-rt     (r25:call-tool-request->json call-struct))

;; ---- Arm 3: malformed -> JSON-RPC error object via a GENUINE contract reject ----
;; The decoder does NOT validate (verified: name=42 is ACCEPTED, returns a
;; struct). Rejection comes from applying the CONTRACT, exactly as
;; spec-2025-11-25-test.rkt:219–224 does. There is NO fabricating (error …)
;; guard producing err-obj: it can ONLY come from the (contract …/c …) raise, so
;; the not-fabricated assertions below cannot be fooled. If the contract ever
;; stops raising, control reaches the loud (error …) and the test FAILS — it is
;; not an err-obj source.
(define malformed-params (hasheq 'name 42 'arguments (hasheq))) ; name must be string?
(define err-obj
  (with-handlers ([exn:fail? exn->jsonrpc-error-jsexpr])
    (contract r25:call-tool-request-params/c
              (r25:json->call-tool-request-params malformed-params) ; decode succeeds…
              'demo 'demo)                                          ; …contract RAISES here
    (error 's1-demo
           "contract unexpectedly accepted malformed name — Arm 3 is vacuous, FIX")))

;; ---- Arm 4: error-response envelope round-trip ----
(define er-orig   (read-fx "error-response.json"))
(define er-struct (r25:json->jsonrpc-error-response er-orig))
(define er-rt     (r25:jsonrpc-error-response->json er-struct))

;; ---- transcript (printed on a plain `racket <demo>` run) ----
(module+ main
  (printf "=== Stage S1 demo — JSON<->struct round-trip + malformed->error ===\n\n")

  (printf "--- Arm 1: initialize request ---\n")
  (printf "parsed struct:\n") (pretty-print init-struct)
  (printf "re-emitted JSON:\n~a\n" (jsexpr->string init-rt))
  (printf "(note: unknown key 'extraUnknownKey is dropped on decode)\n")
  (printf "initialize round-trip: ~a\n\n"
          (if (jsexpr=? init-expect init-rt) "OK" "MISMATCH"))

  (printf "--- Arm 2: tools/call request ---\n")
  (printf "parsed struct:\n") (pretty-print call-struct)
  (printf "re-emitted JSON:\n~a\n" (jsexpr->string call-rt))
  (printf "tools/call round-trip: ~a\n\n"
          (if (jsexpr=? call-orig call-rt) "OK" "MISMATCH"))

  (printf "--- Arm 3: malformed message -> JSON-RPC error object ---\n")
  (printf "malformed input: ~a\n" (jsexpr->string malformed-params))
  (printf "  (decoder accepts it; the contract rejects it)\n")
  (printf "JSON-RPC error object: ~a\n" (jsexpr->string err-obj))
  (printf "error code: ~a\n\n" (hash-ref err-obj 'code))

  (printf "--- Arm 4: error-response envelope round-trip ---\n")
  (printf "parsed struct:\n") (pretty-print er-struct)
  (printf "re-emitted JSON:\n~a\n" (jsexpr->string er-rt))
  (printf "error-response round-trip: ~a\n\n"
          (if (jsexpr=? er-orig er-rt) "OK" "MISMATCH"))

  (printf "=== demo complete ===\n"))

;; ---- non-vacuous, CI-checkable assertions (run under `raco test`) ----
(module+ test
  (require rackunit)
  ;; arm 1 — round-trip + idempotence
  (check-true (jsexpr=? init-expect init-rt) "initialize round-trips (canonical)")
  (check-true (jsexpr=? init-rt (r25:initialize-request->json
                                 (r25:json->initialize-request init-rt)))
              "initialize idempotent")
  ;; arm 2 — round-trip + idempotence
  (check-true (jsexpr=? call-orig call-rt) "tools/call round-trips (canonical)")
  (check-true (jsexpr=? call-rt (r25:call-tool-request->json
                                 (r25:json->call-tool-request call-rt)))
              "tools/call idempotent")
  ;; arm 3 — the malformed message produced a correct JSON-RPC error object via a
  ;; REAL contract rejection (not a fabricated guard crash).
  (check-true (hash? err-obj) "error object is a JSON object")
  (check-true (exact-integer? (hash-ref err-obj 'code)) "error object has integer code")
  (check-equal? (hash-ref err-obj 'code) INTERNAL-ERROR
                "contract-violation maps to -32603")
  (let ([msg (hash-ref err-obj 'message)])
    (check-true (and (string? msg) (> (string-length msg) 0)) "non-empty message")
    ;; THE non-vacuous assertions: the error came from the CONTRACT, not the guard.
    (check-true  (regexp-match? #rx"contract violation" msg)
                 "error is a genuine contract rejection")
    (check-false (regexp-match? #rx"unexpectedly accepted" msg)
                 "error is NOT the fabricating guard crash"))
  ;; arm 4 — full envelope round-trip
  (check-true (jsexpr=? er-orig er-rt) "error-response envelope round-trips (canonical)"))
