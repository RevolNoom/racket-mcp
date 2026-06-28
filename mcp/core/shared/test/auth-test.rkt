#lang racket/base

;; Work Item 015 — tests for the shared AuthInfo struct + helpers (M5d).
;;
;; Fixture provenance: the field surface is from TS `types/types.ts:435`. The
;; OAuth zod-schema fixtures in TS `auth.test.ts` are OUT of scope (no OAuth
;; logic here); the `resourceUrlFromServerUrl`/`checkResourceAllowed` fixtures in
;; `authUtils.test.ts` are DEFERRED to S8 (those helpers are not implemented in
;; M5d). So a reviewer should not expect them.

(require rackunit
         (file "../auth.rkt"))

;; ===========================================================================
;; Part 1 — construct + required/optional defaults.
;; ===========================================================================
(define minimal (make-auth-info #:token "t" #:client-id "c"))
(check-equal? (auth-info-token minimal) "t")
(check-equal? (auth-info-client-id minimal) "c")
(check-equal? (auth-info-scopes minimal) '() "scopes defaults to '()")
(check-equal? (auth-info-expires-at minimal) #f)
(check-equal? (auth-info-resource minimal) #f)
(check-equal? (auth-info-extra minimal) #f)

(define full (make-auth-info #:token "t" #:client-id "c"
                             #:scopes (list "read" "write")
                             #:expires-at 1700000000
                             #:resource "https://api.example.com/mcp"
                             #:extra (hasheq 'k "v")))
(check-equal? (auth-info-scopes full) (list "read" "write"))
(check-equal? (auth-info-expires-at full) 1700000000)
(check-equal? (auth-info-resource full) "https://api.example.com/mcp")
(check-equal? (auth-info-extra full) (hasheq 'k "v"))

;; ===========================================================================
;; Part 2 — field surface EXACT: 6 fields (tag + 6 = vector length 7).
;; ===========================================================================
(check-equal? (vector-length (struct->vector (make-auth-info #:token "t" #:client-id "c"))) 7
              "auth-info has exactly 6 fields")

;; ===========================================================================
;; Part 3 — auth-info-expired? (token helper).
;; ===========================================================================
(check-true  (auth-info-expired? (make-auth-info #:token "t" #:client-id "c" #:expires-at 100) 200)
             "expired (100 <= 200)")
(check-false (auth-info-expired? (make-auth-info #:token "t" #:client-id "c" #:expires-at 300) 200)
             "not yet (300 > 200)")
(check-true  (auth-info-expired? (make-auth-info #:token "t" #:client-id "c" #:expires-at 200) 200)
             "boundary <= (200 <= 200)")
(check-false (auth-info-expired? (make-auth-info #:token "t" #:client-id "c") 200)
             "no expiry recorded -> #f")
(check-true  (auth-info-expired? (make-auth-info #:token "t" #:client-id "c" #:expires-at 0) 1)
             "S4: epoch 0 is a real expiry, not a #f-fallthrough")

;; ===========================================================================
;; Part 4 — auth-info-has-scope? (metadata helper).
;; ===========================================================================
(check-true  (auth-info-has-scope? (make-auth-info #:token "t" #:client-id "c"
                                                   #:scopes (list "read" "write")) "read"))
(check-false (auth-info-has-scope? (make-auth-info #:token "t" #:client-id "c"
                                                   #:scopes (list "read" "write")) "admin"))
(check-false (auth-info-has-scope? (make-auth-info #:token "t" #:client-id "c") "read")
             "empty scopes -> #f")

;; ===========================================================================
;; Part 5 — JSON encode (omit-on-#f) + symmetric round-trip.
;; ===========================================================================
(check-equal? (json->auth-info (auth-info->json full)) full "full round-trip")
(check-equal? (json->auth-info (auth-info->json minimal)) minimal "minimal round-trip")
(check-false (hash-has-key? (auth-info->json minimal) 'expiresAt) "minimal omits expiresAt")
(check-false (hash-has-key? (auth-info->json minimal) 'resource) "minimal omits resource")
(check-false (hash-has-key? (auth-info->json minimal) 'extra) "minimal omits extra")
(check-true  (hash-has-key? (auth-info->json full) 'clientId) "camelCase clientId emitted")

;; expires-at = 0 IS emitted (S4) — the omit test is #f-valued, not falsy.
(check-true (hash-has-key? (auth-info->json (make-auth-info #:token "t" #:client-id "c" #:expires-at 0))
                           'expiresAt)
            "S4: expires-at 0 is emitted")

;; empty-but-present extra IS emitted (S4) — #f ≠ empty hash.
(define e0 (make-auth-info #:token "t" #:client-id "c" #:extra (hasheq)))
(check-true (hash-has-key? (auth-info->json e0) 'extra) "S4: empty extra is emitted")
(check-equal? (auth-info-extra (json->auth-info (auth-info->json e0))) (hasheq)
              "S4: empty extra survives round-trip")

;; ===========================================================================
;; Part 6 — JSON decode from a LITERAL wire hash (C4 — round-trip de-vacuumed).
;; Proves the decoder honors clientId/expiresAt (camelCase), not kebab-case.
;; ===========================================================================
(check-equal?
 (json->auth-info (hasheq 'token "t" 'clientId "c" 'scopes (list "read")
                          'expiresAt 100 'resource "https://x/mcp"))
 (make-auth-info #:token "t" #:client-id "c" #:scopes (list "read")
                 #:expires-at 100 #:resource "https://x/mcp")
 "C4: decoder reads camelCase wire keys")

;; ===========================================================================
;; Part 7 — json->auth-info REJECTS malformed wire input (C2 — security).
;; ===========================================================================
(check-exn exn:fail? (lambda () (json->auth-info (hasheq 'clientId "c" 'scopes '())))
           "missing token raises")
(check-exn exn:fail? (lambda () (json->auth-info (hasheq 'token "t" 'scopes '())))
           "missing clientId raises")
(check-exn exn:fail? (lambda () (json->auth-info (hasheq 'token 5 'clientId "c" 'scopes '())))
           "non-string token raises")
(check-exn exn:fail? (lambda () (json->auth-info (hasheq 'token "t" 'clientId "c" 'scopes "read")))
           "scopes not a list raises")

;; ===========================================================================
;; Part 8 — make-auth-info REJECTS bad field values (C3 — contract falsified).
;; ===========================================================================
(check-exn exn:fail:contract? (lambda () (make-auth-info #:token 5 #:client-id "c"))
           "non-string token -> contract error")
(check-exn exn:fail:contract? (lambda () (make-auth-info #:token "t" #:client-id "c" #:expires-at -1))
           "negative expires-at -> exact-nonnegative-integer? violation")
(check-exn exn:fail:contract? (lambda () (make-auth-info #:token "t" #:client-id "c" #:scopes "read"))
           "scopes string, not a list -> contract error")
(check-exn exn:fail:contract? (lambda () (make-auth-info #:token "t" #:client-id "c" #:resource 5))
           "non-string resource -> contract error")
(check-exn exn:fail:contract? (lambda () (make-auth-info #:token "t" #:client-id "c" #:extra "x"))
           "non-json-object extra -> contract error")

;; ===========================================================================
;; Part 9 — resource is a string.
;; ===========================================================================
(check-true (string? (auth-info-resource
                      (make-auth-info #:token "t" #:client-id "c"
                                      #:resource "https://api.example.com/mcp")))
            "resource is a string, not a parsed URL")
