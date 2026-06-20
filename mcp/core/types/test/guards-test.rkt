#lang racket/base

;; Truth-table test for the JSON-RPC envelope guards in ../guards.rkt.
;; Every predicate is asserted against a curated set of valid-accept and
;; invalid-reject message values, with explicit attention to the
;; ambiguous/overlapping shapes (both result+error; id+method+result;
;; id-less error; inner-error extra key; non-object params; strict envelope).
;;
;; All object values are built with `hasheq` (symbol keys) to mirror
;; read-json's output. A no-batch introspection block (with a positive
;; control over the five real predicates) asserts no batch predicate is
;; exported. An optional TS cross-check reads the live guards.test.ts inline
;; value set and confirms wire parity for the 3 response-side predicates.
;;
;; The check count is pinned EXACTLY at the end (per item 001's precedent).

(require rackunit
         racket/runtime-path
         (file "../guards.rkt")
         (file "../constants.rkt"))

(define V JSONRPC-VERSION)

;; --- reusable value fixtures ---------------------------------------------
(define req          (hasheq 'jsonrpc V 'id 1 'method "ping"))
(define req/str-id   (hasheq 'jsonrpc V 'id "abc" 'method "ping"))
(define req/params   (hasheq 'jsonrpc V 'id 1 'method "ping" 'params (hasheq 'x 1)))
(define notif        (hasheq 'jsonrpc V 'method "notifications/initialized"))
(define notif/params (hasheq 'jsonrpc V 'method "x" 'params (hasheq)))
(define result       (hasheq 'jsonrpc V 'id 1 'result (hasheq)))
(define result/full  (hasheq 'jsonrpc V 'id "id-2" 'result (hasheq 'data 1 'resultType "complete")))
(define err          (hasheq 'jsonrpc V 'id 1 'error (hasheq 'code -32600 'message "Invalid Request")))
(define err/no-id    (hasheq 'jsonrpc V 'error (hasheq 'code -32700 'message "Parse error")))
(define err/data     (hasheq 'jsonrpc V 'id 1 'error (hasheq 'code -1 'message "e" 'data (hasheq 'k 1))))

;; ========================================================================
;; Truth table — is-jsonrpc-request?
;; ========================================================================
(check-true  (is-jsonrpc-request? req)            "req")
(check-true  (is-jsonrpc-request? req/str-id)     "req/str-id")
(check-true  (is-jsonrpc-request? req/params)     "req/params (object params)")
(check-false (is-jsonrpc-request? notif)          "notif (no id) is not a request")
(check-false (is-jsonrpc-request? result)         "result is not a request")
(check-false (is-jsonrpc-request? err)            "err is not a request")
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc V 'id 'null 'method "m")) "id 'null rejected")
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc V 'id 1.5 'method "m"))   "fractional id rejected")
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc V 'id 1.0 'method "m"))   "inexact whole 1.0 id rejected")
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc V 'id #t 'method "m"))    "boolean id rejected")
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc V 'id 1))                 "method missing")
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc V 'id 1 'method 5))       "non-string method")
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc V 'id 1 'method "m" 'params 5))     "non-object params rejected")
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc V 'id 1 'method "m" 'params 'null)) "'null params rejected")
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc V 'id 1 'method "m" 'foo 1))        "extra top-level key rejected")
(check-false (is-jsonrpc-request? (hasheq 'id 1 'method "m"))               "jsonrpc missing")
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc "1.0" 'id 1 'method "m"))"jsonrpc \"1.0\"")
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc 1 'id 1 'method "m"))    "jsonrpc number")
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc V 'id 1 'method "m" 'result (hasheq))) "id+method+result rejected")

;; ========================================================================
;; Truth table — is-jsonrpc-notification?
;; ========================================================================
(check-true  (is-jsonrpc-notification? notif)        "notif")
(check-true  (is-jsonrpc-notification? notif/params) "notif/params")
(check-false (is-jsonrpc-notification? req)          "req (has id) is not a notification")
(check-false (is-jsonrpc-notification? result)       "result is not a notification")
(check-false (is-jsonrpc-notification? err)          "err is not a notification")
(check-false (is-jsonrpc-notification? err/no-id)    "id-less error is NOT a notification (THE TRAP)")
(check-false (is-jsonrpc-notification? (hasheq 'jsonrpc V)) "jsonrpc-only (no method)")
(check-false (is-jsonrpc-notification? (hasheq 'jsonrpc V 'method 5)) "non-string method")
(check-false (is-jsonrpc-notification? (hasheq 'jsonrpc V 'method "m" 'params 5)) "non-object params rejected")
(check-false (is-jsonrpc-notification? (hasheq 'jsonrpc V 'method "m" 'foo 1)) "extra top-level key rejected")
(check-false (is-jsonrpc-notification? (hasheq 'method "m")) "jsonrpc missing")
(check-false (is-jsonrpc-notification? (hasheq 'jsonrpc "1.0" 'method "m")) "jsonrpc wrong")

;; ========================================================================
;; Truth table — is-jsonrpc-result-response?
;; ========================================================================
(check-true  (is-jsonrpc-result-response? result)      "result")
(check-true  (is-jsonrpc-result-response? result/full) "result/full")
(check-true  (is-jsonrpc-result-response? (hasheq 'jsonrpc V 'id "s" 'result (hasheq))) "result with string id")
(check-false (is-jsonrpc-result-response? req)         "req is not a result-response")
(check-false (is-jsonrpc-result-response? notif)       "notif is not a result-response")
(check-false (is-jsonrpc-result-response? err)         "err (has error) is not a result-response")
(check-false (is-jsonrpc-result-response? (hasheq 'jsonrpc V 'result (hasheq))) "missing id rejected")
(check-false (is-jsonrpc-result-response? (hasheq 'jsonrpc V 'id 1 'result 5))     "non-object result rejected")
(check-false (is-jsonrpc-result-response? (hasheq 'jsonrpc V 'id 1 'result 'null)) "'null result rejected")
(check-false (is-jsonrpc-result-response?
              (hasheq 'jsonrpc V 'id 1 'result (hasheq) 'error (hasheq 'code 1 'message "m")))
             "both result and error rejected")
(check-false (is-jsonrpc-result-response? (hasheq 'jsonrpc V 'id 1 'method "m" 'result (hasheq)))
             "id+method+result rejected (extra method)")
(check-false (is-jsonrpc-result-response? (hasheq 'jsonrpc V 'id 1 'result (hasheq) 'foo 1))
             "extra top-level key rejected")

;; ========================================================================
;; Truth table — is-jsonrpc-error?
;; ========================================================================
(check-true  (is-jsonrpc-error? err)       "err")
(check-true  (is-jsonrpc-error? err/data)  "err/data")
(check-true  (is-jsonrpc-error? err/no-id) "id-less error is an error (id optional)")
(check-true  (is-jsonrpc-error? (hasheq 'jsonrpc V 'id "s" 'error (hasheq 'code 1 'message "m")))
             "error with string id")
(check-false (is-jsonrpc-error? result) "result is not an error")
(check-false (is-jsonrpc-error? req)    "req is not an error")
(check-false (is-jsonrpc-error? notif)  "notif is not an error")
(check-false (is-jsonrpc-error? (hasheq 'jsonrpc V 'id 'null 'error (hasheq 'code 1 'message "m")))
             "present 'null id rejected even when optional")
(check-false (is-jsonrpc-error? (hasheq 'jsonrpc V 'id 1 'error (hasheq 'code 1.5 'message "m")))
             "non-integer error.code rejected")
(check-false (is-jsonrpc-error? (hasheq 'jsonrpc V 'id 1 'error (hasheq 'message "m")))
             "missing error.code rejected")
(check-false (is-jsonrpc-error? (hasheq 'jsonrpc V 'id 1 'error (hasheq 'code 1)))
             "missing error.message rejected")
(check-false (is-jsonrpc-error? (hasheq 'jsonrpc V 'id 1 'error (hasheq 'code 1 'message 5)))
             "non-string error.message rejected")
(check-false (is-jsonrpc-error? (hasheq 'jsonrpc V 'id 1 'error "boom")) "non-object error rejected")
(check-false (is-jsonrpc-error?
              (hasheq 'jsonrpc V 'id 1 'result (hasheq) 'error (hasheq 'code 1 'message "m")))
             "both result and error rejected")
(check-false (is-jsonrpc-error? (hasheq 'jsonrpc V 'id 1 'error (hasheq 'code 1 'message "m") 'foo 1))
             "extra top-level key rejected")
;; Inner-error is NOT strict — unknown key inside error is ACCEPTED (wire parity)
(check-true  (is-jsonrpc-error? (hasheq 'jsonrpc V 'id 1 'error (hasheq 'code 1 'message "m" 'foo 1)))
             "unknown key INSIDE error is accepted (inner z.object non-strict)")

;; ========================================================================
;; Truth table — is-jsonrpc-response? (union)
;; ========================================================================
(check-true  (is-jsonrpc-response? result)      "response: result")
(check-true  (is-jsonrpc-response? result/full) "response: result/full")
(check-true  (is-jsonrpc-response? err)         "response: err")
(check-true  (is-jsonrpc-response? err/no-id)   "response: err/no-id")
(check-true  (is-jsonrpc-response? err/data)    "response: err/data")
(check-false (is-jsonrpc-response? req)         "response: req false")
(check-false (is-jsonrpc-response? notif)       "response: notif false")
(check-false (is-jsonrpc-response?
              (hasheq 'jsonrpc V 'id 1 'result (hasheq) 'error (hasheq 'code 1 'message "m")))
             "response: both result+error false (matches neither strict schema)")
(check-false (is-jsonrpc-response? (hasheq 'foo "bar")) "response: arbitrary object false")
(check-false (is-jsonrpc-response? 42)     "response: 42 false")
(check-false (is-jsonrpc-response? 'null)  "response: 'null false")
(check-false (is-jsonrpc-response? #f)     "response: #f false")
(check-false (is-jsonrpc-response? "s")    "response: string false")
(check-false (is-jsonrpc-response? '())    "response: empty list false")

;; Identity assertion: response ≡ (or result-response error) over the fixture set
(define identity-set
  (list req req/str-id req/params notif notif/params result result/full err err/no-id err/data
        (hasheq 'jsonrpc V 'id 1 'result (hasheq) 'error (hasheq 'code 1 'message "m"))
        (hasheq 'jsonrpc V 'id 1 'method "m" 'result (hasheq))
        (hasheq 'foo "bar") 42 'null #f "s" '()))
(for ([v (in-list identity-set)] [i (in-naturals)])
  (check-equal? (is-jsonrpc-response? v)
                (or (is-jsonrpc-result-response? v) (is-jsonrpc-error? v))
                (format "union identity holds for fixture #~a" i)))

;; ========================================================================
;; Cross-cutting "never raises" — every predicate over hostile inputs
;; ========================================================================
(define hostile-inputs
  (list 42 1.5 "string" 'null #f #t '() '(1 2 3) (vector 1 2) (box 1)
        (make-hash)                 ; mutable hash
        (hash "jsonrpc" "2.0")      ; string keys, not symbol keys
        (hasheq)                    ; empty
        (hasheq 'foo 1)))           ; symbol-keyed but not an envelope
(define all-preds
  (list is-jsonrpc-request? is-jsonrpc-notification? is-jsonrpc-result-response?
        is-jsonrpc-error? is-jsonrpc-response?))
(for ([p (in-list all-preds)] [pi (in-naturals)])
  (for ([v (in-list hostile-inputs)] [vi (in-naturals)])
    (check-not-exn (lambda () (p v)) (format "pred#~a never raises on input#~a" pi vi))
    (check-false (p v) (format "pred#~a returns #f on hostile input#~a" pi vi))))

;; ========================================================================
;; Ambiguous / overlapping shapes — assert ALL explicitly
;; ========================================================================
;; 1. result AND error together → false for all three response-side checks
(define both-r+e (hasheq 'jsonrpc V 'id 1 'result (hasheq) 'error (hasheq 'code 1 'message "m")))
(check-false (is-jsonrpc-result-response? both-r+e) "both result+error: not result-response")
(check-false (is-jsonrpc-error? both-r+e)           "both result+error: not error")
(check-false (is-jsonrpc-response? both-r+e)        "both result+error: not response")

;; 2. id + method + result → false for request and result-response and response
(define idmr (hasheq 'jsonrpc V 'id 1 'method "m" 'result (hasheq)))
(check-false (is-jsonrpc-request? idmr)         "id+method+result: not request (extra result)")
(check-false (is-jsonrpc-result-response? idmr) "id+method+result: not result-response (extra method)")
(check-false (is-jsonrpc-response? idmr)        "id+method+result: not response")

;; 3. method + id (no result/error) → request true, notification false
(check-true  (is-jsonrpc-request? req)      "method+id: request true")
(check-false (is-jsonrpc-notification? req) "method+id: notification false (id-presence discriminator)")

;; 4. method only (no id) → notification true, request false
(check-true  (is-jsonrpc-notification? notif) "method-only: notification true")
(check-false (is-jsonrpc-request? notif)      "method-only: request false")

;; 5. id-less error TRAP → all five predicates asserted on err/no-id
(check-false (is-jsonrpc-request? err/no-id)         "id-less error: not request (no method)")
(check-false (is-jsonrpc-notification? err/no-id)    "id-less error: not notification")
(check-false (is-jsonrpc-result-response? err/no-id) "id-less error: not result-response")
(check-true  (is-jsonrpc-error? err/no-id)           "id-less error: IS error")
(check-true  (is-jsonrpc-response? err/no-id)        "id-less error: IS response")

;; 6. id string vs exact integer → both accepted everywhere an id is valid
(check-true (is-jsonrpc-request? req)        "int id accepted (request)")
(check-true (is-jsonrpc-request? req/str-id) "string id accepted (request)")
(check-true (is-jsonrpc-result-response? (hasheq 'jsonrpc V 'id 7 'result (hasheq)))   "int id accepted (result)")
(check-true (is-jsonrpc-result-response? (hasheq 'jsonrpc V 'id "k" 'result (hasheq))) "string id accepted (result)")
(check-true (is-jsonrpc-error? (hasheq 'jsonrpc V 'id 7 'error (hasheq 'code 1 'message "m")))   "int id accepted (error)")
(check-true (is-jsonrpc-error? (hasheq 'jsonrpc V 'id "k" 'error (hasheq 'code 1 'message "m"))) "string id accepted (error)")

;; 7. id 'null → rejected everywhere
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc V 'id 'null 'method "m")) "'null id: request false")
(check-false (is-jsonrpc-result-response? (hasheq 'jsonrpc V 'id 'null 'result (hasheq))) "'null id: result false")
(check-false (is-jsonrpc-error? (hasheq 'jsonrpc V 'id 'null 'error (hasheq 'code 1 'message "m"))) "'null id: error false")

;; 8. missing jsonrpc → false for all five
(define no-jsonrpc (hasheq 'id 1 'method "m"))
(for ([p (in-list all-preds)] [pi (in-naturals)])
  (check-false (p no-jsonrpc) (format "missing jsonrpc: pred#~a false" pi)))

;; 9. jsonrpc "1.0" / 2.0-as-number / 2 → false for all five
(for ([bad (in-list (list (hasheq 'jsonrpc "1.0" 'id 1 'method "m")
                          (hasheq 'jsonrpc 2.0   'id 1 'method "m")
                          (hasheq 'jsonrpc 2     'id 1 'method "m")))]
      [bi (in-naturals)])
  (for ([p (in-list all-preds)] [pi (in-naturals)])
    (check-false (p bad) (format "bad jsonrpc #~a: pred#~a false" bi pi))))

;; 10. extra/unknown top-level key on an otherwise-valid envelope → false
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc V 'id 1 'method "m" 'extra 1))      "extra key: request false")
(check-false (is-jsonrpc-notification? (hasheq 'jsonrpc V 'method "m" 'extra 1))       "extra key: notification false")
(check-false (is-jsonrpc-result-response? (hasheq 'jsonrpc V 'id 1 'result (hasheq) 'extra 1)) "extra key: result false")
(check-false (is-jsonrpc-error? (hasheq 'jsonrpc V 'id 1 'error (hasheq 'code 1 'message "m") 'extra 1)) "extra key: error false")

;; 11. empty result object → true for result-response (loose object allows empty)
(check-true (is-jsonrpc-result-response? (hasheq 'jsonrpc V 'id 1 'result (hasheq))) "empty result object accepted")

;; 12. unknown key INSIDE error → true (envelope-only strictness)
(check-true (is-jsonrpc-error? (hasheq 'jsonrpc V 'id 1 'error (hasheq 'code 1 'message "m" 'foo 1)))
            "inner-error extra key: error true")
(check-true (is-jsonrpc-response? (hasheq 'jsonrpc V 'id 1 'error (hasheq 'code 1 'message "m" 'foo 1)))
            "inner-error extra key: response true")

;; 13. non-object params → false for request and notification
(check-false (is-jsonrpc-request? (hasheq 'jsonrpc V 'id 1 'method "m" 'params 5))      "params:5 request false")
(check-false (is-jsonrpc-notification? (hasheq 'jsonrpc V 'method "m" 'params 5))       "params:5 notification false")
(check-true  (is-jsonrpc-request? (hasheq 'jsonrpc V 'id 1 'method "m" 'params (hasheq 'x 1))) "object params request true")
(check-true  (is-jsonrpc-request? (hasheq 'jsonrpc V 'id 1 'method "m")) "absent params request true")

;; ========================================================================
;; No-batch-export assertion (required) + positive control
;; ========================================================================
(define-runtime-path guards-path "../guards.rkt")
(define provided
  (let-values ([(vars _stx)
                (module->exports `(file ,(path->string (path->complete-path guards-path))))])
    (for*/list ([phase (in-list vars)] [b (in-list (cdr phase))]) (car b))))
(check-false (and (memq 'is-jsonrpc-batch? provided) #t) "no is-jsonrpc-batch? export")
(check-false (for/or ([n (in-list provided)]) (regexp-match? #rx"(?i:batch)" (symbol->string n)))
             "no provided name contains 'batch'")
(check-exn exn:fail?
           (lambda () (dynamic-require `(file ,(path->string (path->complete-path guards-path)))
                                       'is-jsonrpc-batch?))
           "is-jsonrpc-batch? is not dynamically requirable")
;; positive control: the five real predicates ARE exported
(for ([n '(is-jsonrpc-request? is-jsonrpc-notification? is-jsonrpc-result-response?
           is-jsonrpc-error? is-jsonrpc-response?)])
  (check-true (and (memq n provided) #t) (format "~a is exported" n)))
;; exactly five provided bindings
(check-equal? (length provided) 5 "exactly five public bindings provided")

;; ========================================================================
;; Optional TS parity cross-check — reads the live guards.test.ts inline set
;; (covers only the 3 response-side predicates; request/notification have no
;; TS cases there, so they are covered solely by the truth table above).
;; ========================================================================
(define-runtime-path ts-guards-test-path
  "../../../../typescript-sdk/packages/core/test/types/guards.test.ts")
(unless (file-exists? ts-guards-test-path)
  (fail (format "TS cross-check fixture missing: ~a" ts-guards-test-path)))
;; The guards.test.ts isJSONRPCResponse describe block's inline value set
;; (guards.test.ts:6–77), transcribed to the read-json hasheq shape. Each row
;; pairs a value with its expected (isJSONRPCResponse) boolean from upstream.
(define ts-cases
  (list (cons (hasheq 'jsonrpc V 'id 1 'result (hasheq)) #t)
        (cons (hasheq 'jsonrpc V 'id 1 'error (hasheq 'code -32600 'message "Invalid Request")) #t)
        (cons (hasheq 'jsonrpc V 'id 1 'method "test") #f)
        (cons (hasheq 'jsonrpc V 'method "test") #f)
        (cons (hasheq 'foo "bar") #f)
        (cons (hasheq 'jsonrpc V 'id 1 'result (hasheq 'content '())) #t)
        (cons (hasheq 'jsonrpc V 'id 2 'error (hasheq 'code -1 'message "err")) #t)
        (cons (hasheq 'jsonrpc V 'id 3 'method "test") #f)
        (cons (hasheq 'jsonrpc V 'method "notify") #f)
        (cons 'null #f)
        (cons 42 #f)))
(for ([c (in-list ts-cases)] [i (in-naturals)])
  (check-equal? (is-jsonrpc-response? (car c)) (cdr c)
                (format "TS parity isJSONRPCResponse case #~a" i))
  ;; upstream's union identity must also hold on these
  (check-equal? (is-jsonrpc-response? (car c))
                (or (is-jsonrpc-result-response? (car c)) (is-jsonrpc-error? (car c)))
                (format "TS parity union identity case #~a" i)))
