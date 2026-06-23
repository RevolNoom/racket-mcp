#lang racket/base

;; Work Item 011 — tests for the DEFAULT Racket-native validator provider.
;;
;; A BEHAVIOURAL keyword-coverage test for the supported subset, with a
;; TS-baseline cross-check, the deferred-keyword ignore-with-warning policy
;; pinned per keyword, edge cases for every tricky semantic, the fail-fast
;; compile precedent, path-construction assertions, and the restricted-load
;; portability sub-test. Result-shape mechanics (the result API, the non-empty
;; guard, opacity) are covered by item 010's provider-test.rkt and are NOT
;; re-litigated here — this test asserts VERDICTS and PATHS.
;;
;; ---------------------------------------------------------------------------
;; DOCUMENTED CHOICES asserted by this test (see module docs in
;; ../from-json-schema.rkt):
;;   - integer = exact-integer?  (42.0 REJECTS; bignum + (/ 84 2) ACCEPT)
;;   - number  = finite rational (+nan.0 / +inf.0 REJECT)
;;   - email "a@b" (no dot in domain) REJECTS (chosen)
;;   - uri "mailto:..."/"urn:..." ACCEPT; scheme-less / empty-scheme REJECT
;;   - date-time is SHAPE-only: "2025-13-01T00:00:00Z" (month 13) ACCEPTS
;;   - unknown format recorded as the format SYMBOL ('ipv4) (S-g chosen form)
;;   - S-c malformed deferred VALUE (minLength:"three") -> ignore-with-warning
;;     (the deferred keyword is skipped regardless of value; recorded)
;;   - S-d malformed NESTED sub-schema -> check-schema-shape RECURSES ->
;;     RAISES at compile.

(require rackunit
         json
         racket/set
         racket/path
         racket/port
         racket/runtime-path
         (file "../from-json-schema.rkt")
         (file "../provider.rkt"))

(define-runtime-path module-source-path "../from-json-schema.rkt")

(define P (make-racket-native-provider))

(define (accepts? schema value)
  (validation-ok? (validate (provider-compile P schema) value)))
(define (rejects? schema value)
  (validation-errors? (validate (provider-compile P schema) value)))
(define (errs schema value)
  (validation-errors-errors (validate (provider-compile P schema) value)))
;; errs-from : over an ALREADY-compiled handle (so warnings can be inspected
;; on the same handle whose verdict we assert — S-b).
(define (errs-from h value)
  (validation-errors-errors (validate h value)))

;; provider is a real gen: implementer.
(check-true (json-schema-validator-provider? (make-racket-native-provider)))

;; ===========================================================================
;; Part 1 — `type`, all seven types + the hard numeric edges
;; ===========================================================================

;; string
(check-true (accepts? (hasheq 'type "string") "hi"))
(check-true (rejects? (hasheq 'type "string") 123))
;; number — 42 AND 3.14 accept; "42" rejects
(check-true (accepts? (hasheq 'type "number") 42))
(check-true (accepts? (hasheq 'type "number") 3.14))
(check-true (rejects? (hasheq 'type "number") "42"))
;; integer — 42 accepts; 3.14 rejects (integer-vs-number)
(check-true (accepts? (hasheq 'type "integer") 42))
(check-true (rejects? (hasheq 'type "integer") 3.14))
;; boolean — #t/#f accept; 1 and "true" reject
(check-true (accepts? (hasheq 'type "boolean") #t))
(check-true (accepts? (hasheq 'type "boolean") #f))
(check-true (rejects? (hasheq 'type "boolean") 1))
(check-true (rejects? (hasheq 'type "boolean") "true"))
;; object — hasheq accepts; list rejects; string rejects
(check-true (accepts? (hasheq 'type "object") (hasheq 'a 1)))
(check-true (rejects? (hasheq 'type "object") '(1 2 3)))
(check-true (rejects? (hasheq 'type "object") "str"))
;; array — list accepts; hasheq rejects
(check-true (accepts? (hasheq 'type "array") '(1 2 3)))
(check-true (rejects? (hasheq 'type "array") (hasheq 'a 1)))
;; null — (json-null) accepts; 0/#f/"" reject
(check-true (accepts? (hasheq 'type "null") (json-null)))
(check-true (rejects? (hasheq 'type "null") 0))
(check-true (rejects? (hasheq 'type "null") #f))
(check-true (rejects? (hasheq 'type "null") ""))

;; S5 numeric edges — integer
(check-true (accepts? (hasheq 'type "integer") 42))
(check-true (rejects? (hasheq 'type "integer") 3.14))
(check-true (rejects? (hasheq 'type "integer") 42.0))        ; inexact-integer trap
(check-true (accepts? (hasheq 'type "integer") (/ 84 2)))    ; exact 42
(check-true (accepts? (hasheq 'type "integer") (expt 10 100))) ; bignum
;; S5 numeric edges — number; +nan.0/+inf.0 documented REJECT (a JSON number
;; cannot be NaN/Inf, though (number? +nan.0) is #t).
(check-true (accepts? (hasheq 'type "number") 42))
(check-true (accepts? (hasheq 'type "number") 3.14))
(check-true (accepts? (hasheq 'type "number") (expt 10 100)))
(check-true (rejects? (hasheq 'type "number") +nan.0))
(check-true (rejects? (hasheq 'type "number") +inf.0))

;; ===========================================================================
;; Part 2 — object / properties / required (C1 collect-all, C2 non-object, S8)
;; ===========================================================================

(define obj-schema
  (hasheq 'type "object"
          'properties (hasheq 'name (hasheq 'type "string")
                              'age (hasheq 'type "number"))
          'required '("name")))

;; properties accept
(check-true (accepts? obj-schema (hasheq 'name "John" 'age 30)))
(check-true (accepts? obj-schema (hasheq 'name "John")))     ; age absent is fine
;; properties reject + path includes "name"
(let ([es (errs obj-schema (hasheq 'name 123))])
  (check-not-false (memf (lambda (e) (member "name" (validation-error-path e))) es)))
;; required reject + message names name
(let ([es (errs obj-schema (hasheq 'age 30))])
  (check-not-false (memf (lambda (e) (regexp-match? #rx"name" (validation-error-message e))) es)))
(check-true (rejects? obj-schema (hasheq)))

;; S8 symbol/string `required` ACCEPT (the silent-total-failure guard)
(check-true (accepts? (hasheq 'type "object"
                              'properties (hasheq 'name (hasheq 'type "string"))
                              'required '("name"))
                      (hasheq 'name "John")))

;; C1 collect-all error COUNT — exactly 2 (missing required name + age type)
(let ([es (errs obj-schema (hasheq 'age "x"))])
  (check-equal? (length es) 2)
  (check-true (andmap validation-error? es)))

;; C2 non-object value MUST return errors, NOT raise — for each kind
(for ([v (list 42 "str" '(1 2 3) (json-null))])
  (check-not-exn (lambda () (validate (provider-compile P obj-schema) v)))
  (check-true (rejects? obj-schema v)))
;; C2 no-`type` variant — structural keywords self-guard on hash?
(define obj-no-type
  (hasheq 'properties (hasheq 'name (hasheq 'type "string"))
          'required '("name")))
(check-not-exn (lambda () (validate (provider-compile P obj-no-type) 42)))
(check-true (rejects? obj-no-type 42))

;; Empty required accepts every object
(check-true (accepts? (hasheq 'type "object" 'properties (hasheq) 'required '()) (hasheq)))
(check-true (accepts? (hasheq 'type "object" 'properties (hasheq) 'required '())
                      (hasheq 'anything 1)))

;; Nested objects (TS "validates nested objects") — path includes "user"
(define nested-schema
  (hasheq 'type "object"
          'properties
          (hasheq 'user
                  (hasheq 'type "object"
                          'properties (hasheq 'name (hasheq 'type "string")
                                              'email (hasheq 'type "string" 'format "email"))
                          'required '("name")))
          'required '("user")))
(check-true (accepts? nested-schema (hasheq 'user (hasheq 'name "John" 'email "john@example.com"))))
(check-true (accepts? nested-schema (hasheq 'user (hasheq 'name "John"))))
(let ([es (errs nested-schema (hasheq 'user (hasheq 'email "john@example.com")))])
  (check-not-false (memf (lambda (e) (member "user" (validation-error-path e))) es)))

;; S-e nested enum carries a located path '("color")
(let ([es (errs (hasheq 'type "object"
                        'properties (hasheq 'color (hasheq 'enum '("red" "green"))))
                (hasheq 'color "blue"))])
  (check-not-false (memf (lambda (e) (equal? (validation-error-path e) '("color"))) es)))

;; ===========================================================================
;; Part 3 — enum, heterogeneous + null member + edges (S4)
;; ===========================================================================

;; homogeneous string enum
(for ([v '("red" "green" "blue")])
  (check-true (accepts? (hasheq 'enum '("red" "green" "blue")) v)))
(check-true (rejects? (hasheq 'enum '("red" "green" "blue")) "yellow"))

;; heterogeneous enum (TS "validates enum with mixed types")
(define het-enum (hasheq 'enum (list "option1" 42 #t (json-null))))
(check-true (accepts? het-enum "option1"))
(check-true (accepts? het-enum 42))
(check-true (accepts? het-enum #t))
(check-true (accepts? het-enum (json-null)))
(check-true (rejects? het-enum "other"))
;; (json-null) member matches a (json-null) value, NOT #f/0
(check-true (rejects? het-enum 0))     ; 0 is not in the enum (#t there, not 0)
(check-true (accepts? (hasheq 'enum (list (json-null))) (json-null)))
(check-true (rejects? (hasheq 'enum (list (json-null))) #f))

;; S4 empty enum rejects every value
(check-true (rejects? (hasheq 'enum '()) "x"))
(check-true (rejects? (hasheq 'enum '()) 42))
;; S4 duplicate members accept without crash
(check-true (accepts? (hasheq 'enum '("a" "a")) "a"))
;; S4 compound member — deep equal? (catches eq?/eqv? membership)
(check-true (accepts? (hasheq 'enum (list (hasheq 'a 1))) (hasheq 'a 1)))

;; C3-ish type+enum co-occurrence COUNT
(check-equal? (length (errs (hasheq 'type "string" 'enum '("a" "b")) 42)) 2)  ; type AND enum
(check-equal? (length (errs (hasheq 'type "string" 'enum '("a" "b")) "c")) 1) ; enum only

;; ===========================================================================
;; Part 4 — items, empty array, non-array (C3), nested + both-element paths (S6)
;; ===========================================================================

(define str-arr (hasheq 'type "array" 'items (hasheq 'type "string")))
(check-true (accepts? str-arr '("a" "b" "c")))
(check-true (accepts? str-arr '()))                  ; empty array trivially accepts
(check-true (rejects? str-arr '("a" 1 "c")))
(let ([es (errs str-arr '("a" 1 "c"))])
  (check-not-false (memf (lambda (e) (member 1 (validation-error-path e))) es))) ; integer index 1

;; C3 non-array value MUST return errors, NOT raise
(for ([v (list (hasheq 'a 1) 42)])
  (check-not-exn (lambda () (validate (provider-compile P str-arr) v)))
  (check-true (rejects? str-arr v)))
;; C3 no-`type` variant self-guards on list?
(define items-no-type (hasheq 'items (hasheq 'type "string")))
(check-not-exn (lambda () (validate (provider-compile P items-no-type) (hasheq 'a 1))))
(check-true (rejects? items-no-type (hasheq 'a 1)))

;; S6 collect-all over array elements — BOTH '(0 "name") and '(1 "name")
(define arr-of-obj
  (hasheq 'type "array"
          'items (hasheq 'type "object"
                         'properties (hasheq 'name (hasheq 'type "string"))
                         'required '("name"))))
(let ([paths (map validation-error-path
                  (errs arr-of-obj (list (hasheq 'name 123) (hasheq 'name 456))))])
  (check-not-false (member '(0 "name") paths))
  (check-not-false (member '(1 "name") paths)))

;; nested items + properties mixed path '(1 "name")
(let ([paths (map validation-error-path
                  (errs arr-of-obj (list (hasheq 'name "ok") (hasheq 'name 123))))])
  (check-not-false (member '(1 "name") paths)))

;; deeply-nested "API response" style path '("data" "items" 0 "name")
(define api-schema
  (hasheq 'type "object"
          'properties
          (hasheq 'data
                  (hasheq 'type "object"
                          'properties
                          (hasheq 'items
                                  (hasheq 'type "array"
                                          'items (hasheq 'type "object"
                                                         'properties (hasheq 'name (hasheq 'type "string"))
                                                         'required '("name"))))))))
(let ([paths (map validation-error-path
                  (errs api-schema
                        (hasheq 'data (hasheq 'items (list (hasheq 'name 123))))))])
  (check-not-false (member '("data" "items" 0 "name") paths)))

;; ===========================================================================
;; Part 5 — format (recognizer rigor C6, non-string + unknown-format C5)
;; ===========================================================================

(define (sf f) (hasheq 'type "string" 'format f))

;; TS pairs
(check-true (accepts? (sf "date-time") "2025-10-17T12:00:00Z"))
(check-true (rejects? (sf "date-time") "not-a-date"))
(check-true (accepts? (sf "uri") "https://example.com"))
(check-true (rejects? (sf "uri") "not-a-uri"))
(check-true (accepts? (sf "email") "user@example.com"))
(check-true (rejects? (sf "email") "invalid-email"))

;; C6 email adversarial rejects + chosen "a@b" reject
(check-true (rejects? (sf "email") "a@"))
(check-true (rejects? (sf "email") "@b.com"))
(check-true (rejects? (sf "email") "a b@c.com"))
(check-true (rejects? (sf "email") "a@b"))          ; no dot in domain — chosen REJECT
;; C6 uri adversarial rejects + documented accepts
(check-true (rejects? (sf "uri") "example.com"))    ; scheme-less
(check-true (rejects? (sf "uri") "://example.com")) ; empty scheme
(check-true (accepts? (sf "uri") "mailto:x@y.com"))
(check-true (accepts? (sf "uri") "urn:isbn:123"))
;; C6 date-time documented shape-only limitation — month 13 ACCEPTS
(check-true (accepts? (sf "date-time") "2025-13-01T00:00:00Z"))

;; C5 format on non-string + unknown format
(check-not-exn (lambda () (validate (provider-compile P (hasheq 'format "email")) 42)))
(check-true (accepts? (hasheq 'format "email") 42))        ; no-op on non-string, no crash
(check-true (rejects? (sf "email") 42))                    ; rejects on type, recognizer skipped
;; unknown format ipv4 — accepts on supported keywords, recorded as 'ipv4
(let ([h (provider-compile P (hasheq 'type "string" 'format "ipv4"))])
  (check-true (validation-ok? (validate h "1.2.3.4")))
  (check-not-false (memq 'ipv4 (provider-warnings-for P h))))   ; SYMBOL, not string

;; ===========================================================================
;; Part 6 — ignore-with-warning policy
;;   uniform across five (C4) + warn-once on recorded list (N2)
;;   + per-compile-keyed (N1) + S-a + S-b + unknown keyword (S3) + annotations (S2)
;;
;; Warnings are read via (provider-warnings-for P h) — a (listof symbol?)
;; (S-g); membership checked with SYMBOLS. We do NOT read a compiled-validator
;; field (item 010's struct is frozen).
;; ===========================================================================

;; Uniform across all five deferred keyword families.
(define deferred-cases
  ;; (schema accepted-value type-rejected-value expected-symbol)
  (list (list (hasheq 'type "string" 'pattern "^[A-Z]{3}$") "ab" 123 'pattern)
        (list (hasheq 'type "string" 'minLength 3) "ab" 123 'minLength)
        (list (hasheq 'type "string" 'maxLength 1) "abc" 123 'maxLength)
        (list (hasheq 'type "number" 'minimum 0) -1 "x" 'minimum)
        (list (hasheq 'type "number" 'maximum 100) 101 "x" 'maximum)
        (list (hasheq 'type "object"
                      'properties (hasheq 'name (hasheq 'type "string"))
                      'additionalProperties #f)
              (hasheq 'name "x" 'extra "y") 42 'additionalProperties)
        (list (hasheq 'type "array" 'items (hasheq 'type "number") 'uniqueItems #t)
              '(1 1) "x" 'uniqueItems)))

(for ([c deferred-cases])
  (define schema (list-ref c 0))
  (define accepted-value (list-ref c 1))
  (define type-rejected-value (list-ref c 2))
  (define sym (list-ref c 3))
  ;; none of the five causes provider-compile to RAISE
  (check-not-exn (lambda () (provider-compile P schema)))
  (define h (provider-compile P schema))
  ;; the value the deferred keyword WOULD reject is ACCEPTED (keyword skipped)
  (check-true (validation-ok? (validate h accepted-value))
              (format "deferred ~a should be ignored (accepted)" sym))
  ;; the supported part still fires (type rejects a wrong-typed value)
  (check-true (validation-errors? (validate h type-rejected-value))
              (format "supported type keyword still fires alongside ~a" sym))
  ;; the deferred keyword symbol is recorded
  (check-not-false (memq sym (provider-warnings-for P h))
              (format "deferred ~a recorded in provider-warnings-for" sym)))

;; N1 per-compile-keyed — two handles from ONE provider stay distinct.
(define h-min (provider-compile P (hasheq 'type "string" 'minLength 3)))
(define h-pat (provider-compile P (hasheq 'type "string" 'pattern "x")))
(check-not-false (memq 'minLength (provider-warnings-for P h-min)))
(check-false     (memq 'pattern   (provider-warnings-for P h-min)))
(check-not-false (memq 'pattern   (provider-warnings-for P h-pat)))
(check-false     (memq 'minLength (provider-warnings-for P h-pat)))

;; N2 warn-once on the RECORDED LIST — list length identical after 3 validates.
(let ([h (provider-compile P (hasheq 'type "string" 'minLength 3))])
  (define n0 (length (provider-warnings-for P h)))
  (validate h "ab")
  (validate h "abcd")
  (validate h 123)
  (check-equal? (length (provider-warnings-for P h)) n0)) ; validate NEVER appends

;; N3 supplementary — if a stderr line is emitted it is via eprintf
;; (current-error-port capturable). Compile emits exactly one line; the three
;; validates emit nothing. (Recorded list above is the load-bearing oracle.)
(let ([compile-out (open-output-string)])
  (define h (parameterize ([current-error-port compile-out])
              (provider-compile P (hasheq 'type "string" 'minLength 3))))
  (check-equal? (length (regexp-match* #rx"\n" (get-output-string compile-out))) 1)
  (let ([validate-out (open-output-string)])
    (parameterize ([current-error-port validate-out])
      (validate h "ab") (validate h "abcd") (validate h 123))
    (check-equal? (get-output-string validate-out) "")))

;; S-a C1×C4 — ignored keyword contributes ZERO errors.
(check-equal? (length (errs (hasheq 'type "number" 'minimum 0) "x")) 1) ; type only, no phantom

;; S-b recording is compile-time, independent of verdict.
(let ([h (provider-compile P (hasheq 'type "string" 'format "ipv4"))])
  (check-equal? (length (errs-from h 42)) 1)            ; type only
  (check-not-false (memq 'ipv4 (provider-warnings-for P h)))) ; recorded despite reject

;; S3 unknown (non-deferred) keyword — same ignore-with-warning catch-all.
(for ([kw '(multipleOf propertyNames $ref allOf)])
  (define h (provider-compile P (hasheq 'type "string" kw 2)))
  (check-true (validation-ok? (validate h "hi")))
  (check-not-false (memq kw (provider-warnings-for P h)))
  (check-not-exn (lambda () (provider-compile P (hasheq 'type "string" kw 2)))))

;; S2 annotations must NOT warn or suppress.
(let ([h (provider-compile P (hasheq 'type "string" 'title "X" 'description "Y" 'default "z"))])
  (check-true (validation-errors? (validate h 42)))  ; type failure not suppressed
  (check-true (null? (provider-warnings-for P h))))  ; pure annotations -> no warning

;; Module-docs listing — each deferred keyword named in the module doc block.
(define module-text
  (call-with-input-file module-source-path
    (lambda (in) (port->string in))))
(for ([kw '("pattern" "minLength" "maxLength" "minimum" "maximum"
            "additionalProperties" "uniqueItems")])
  (check-true (regexp-match? (regexp kw) module-text)
              (format "deferred keyword ~a listed in module docs" kw)))

;; ===========================================================================
;; Part 6b — empty/degenerate schemas (S1) + provider statelessness (S7)
;; ===========================================================================

;; S1 empty schema accepts everything
(check-true (accepts? (hasheq) 42))
(check-true (accepts? (hasheq) (json-null)))
(check-true (accepts? (hasheq) (hasheq)))
;; S1 {type:object} with no properties/required
(check-true (accepts? (hasheq 'type "object") (hasheq 'whatever 1)))
(check-true (accepts? (hasheq 'type "object") (hasheq)))
;; S1 {required:["name"]} with no properties still enforces presence
(check-true (accepts? (hasheq 'required '("name")) (hasheq 'name 1)))
(check-true (rejects? (hasheq 'required '("name")) (hasheq)))
;; S-f empty properties hash vs absent properties key
(check-not-exn (lambda () (validate (provider-compile P (hasheq 'type "object" 'properties (hasheq)))
                                    (hasheq 'anything 1))))
(check-true (accepts? (hasheq 'type "object" 'properties (hasheq)) (hasheq 'anything 1)))

;; S7 provider statelessness across schemas
(let ([h1 (provider-compile P (hasheq 'type "string"))]
      [h2 (provider-compile P (hasheq 'type "number"))])
  (check-true (validation-ok? (validate h1 "hi")))
  (check-true (validation-errors? (validate h2 "hi")))
  (check-true (validation-ok? (validate h2 42)))
  (check-true (validation-errors? (validate h1 42))))

;; ===========================================================================
;; Part 7 — TS-baseline cross-check (supported subset only)
;;
;; Each case uses the exact schema+value from validators.test.ts and asserts
;; the Racket verdict equals the TS-asserted `valid`. Only supported-subset
;; fixtures are used; deferred/excluded-keyword fixtures (minLength, pattern,
;; minimum, additionalProperties, uniqueItems, allOf/anyOf/oneOf/not,
;; $schema/$id constraint behaviour) are intentionally omitted. The two
;; "complex real-world" fixtures are cross-checked on their SUPPORTED-keyword
;; PROJECTION only (type/properties/required/enum/format).
;; ===========================================================================

;; basic string
(check-true (accepts? (hasheq 'type "string") "hello"))
(check-true (rejects? (hasheq 'type "string") 123))
;; number type
(check-true (accepts? (hasheq 'type "number") 42))
(check-true (accepts? (hasheq 'type "number") 3.14))
(check-true (rejects? (hasheq 'type "number") "42"))
;; integer type
(check-true (accepts? (hasheq 'type "integer") 42))
(check-true (rejects? (hasheq 'type "integer") 3.14))
;; boolean type
(check-true (accepts? (hasheq 'type "boolean") #t))
(check-true (accepts? (hasheq 'type "boolean") #f))
(check-true (rejects? (hasheq 'type "boolean") "true"))
(check-true (rejects? (hasheq 'type "boolean") 1))
;; enum values
(check-true (accepts? (hasheq 'enum '("red" "green" "blue")) "red"))
(check-true (rejects? (hasheq 'enum '("red" "green" "blue")) "yellow"))
;; enum mixed types
(check-true (accepts? (hasheq 'enum (list "option1" 42 #t (json-null))) "option1"))
(check-true (accepts? (hasheq 'enum (list "option1" 42 #t (json-null))) 42))
(check-true (accepts? (hasheq 'enum (list "option1" 42 #t (json-null))) #t))
(check-true (accepts? (hasheq 'enum (list "option1" 42 #t (json-null))) (json-null)))
(check-true (rejects? (hasheq 'enum (list "option1" 42 #t (json-null))) "other"))
;; simple object (TS: name/age, required name)
(check-true (accepts? obj-schema (hasheq 'name "John" 'age 30)))
(check-true (accepts? obj-schema (hasheq 'name "John")))
(check-true (rejects? obj-schema (hasheq 'age 30)))
(check-true (rejects? obj-schema (hasheq)))
;; nested objects (TS) — supported projection
(check-true (accepts? nested-schema (hasheq 'user (hasheq 'name "John" 'email "john@example.com"))))
(check-true (accepts? nested-schema (hasheq 'user (hasheq 'name "John"))))
(check-true (rejects? nested-schema (hasheq 'user (hasheq 'email "john@example.com"))))
;; array of strings (TS)
(check-true (accepts? str-arr '("a" "b" "c")))
(check-true (accepts? str-arr '()))
(check-true (rejects? str-arr '("a" 1 "c")))
;; string formats (TS)
(check-true (accepts? (sf "email") "user@example.com"))
(check-true (rejects? (sf "email") "invalid-email"))
(check-true (accepts? (sf "uri") "https://example.com"))
(check-true (rejects? (sf "uri") "not-a-uri"))
(check-true (accepts? (sf "date-time") "2025-10-17T12:00:00Z"))
(check-true (rejects? (sf "date-time") "not-a-date"))
;; complex "user registration" SUPPORTED PROJECTION — type/properties/required/format
(define user-reg
  (hasheq 'type "object"
          'properties (hasheq 'username (hasheq 'type "string")
                              'email (hasheq 'type "string" 'format "email")
                              'age (hasheq 'type "integer"))
          'required '("username" "email")))
(check-true (accepts? user-reg (hasheq 'username "jdoe" 'email "jdoe@example.com" 'age 30)))
(check-true (rejects? user-reg (hasheq 'username "jdoe")))                 ; email missing
(check-true (rejects? user-reg (hasheq 'username "jdoe" 'email "bad")))    ; email format

;; ===========================================================================
;; Part 8 — malformed-schema fail-fast (item-010 precedent) + S-c + S-d
;; ===========================================================================

;; non-hasheq schema
(check-exn exn:fail? (lambda () (provider-compile P 42)))
(check-exn exn:fail? (lambda () (provider-compile P '())))
;; properties whose value is not an object-of-subschemas
(check-exn exn:fail? (lambda () (provider-compile P (hasheq 'properties 5))))
;; type not a recognized type string
(check-exn exn:fail? (lambda () (provider-compile P (hasheq 'type "stringg"))))
(check-exn exn:fail? (lambda () (provider-compile P (hasheq 'type 5))))
;; enum not a list
(check-exn exn:fail? (lambda () (provider-compile P (hasheq 'enum 5))))
;; S-d malformed NESTED sub-schema — check-schema-shape recurses -> raises
(check-exn exn:fail?
           (lambda () (provider-compile P (hasheq 'type "object"
                                                  'properties (hasheq 'name (hasheq 'type "stringg"))))))

;; S-c malformed deferred-keyword VALUE — chosen branch: ignore-with-warning.
;; minLength:"three" (a string, not integer) is SKIPPED regardless of value and
;; recorded; compile does NOT raise.
(check-not-exn (lambda () (provider-compile P (hasheq 'type "string" 'minLength "three"))))
(let ([h (provider-compile P (hasheq 'type "string" 'minLength "three"))])
  (check-true (validation-ok? (validate h "ab")))           ; accepted (skipped)
  (check-not-false (memq 'minLength (provider-warnings-for P h)))) ; recorded

;; ===========================================================================
;; Part 9 — restricted-namespace portability (S1 + port only).
;; Reuses the transitive module->imports walk (item 008/010). Entry point is
;; from-json-schema.rkt ITSELF. Guards specifically that the uri recognizer did
;; NOT reach for net/url. module->imports does NOT see into (module+ test ...).
;; ===========================================================================

(define banned-module-paths
  '(racket/system racket/port racket/tcp racket/udp
    net/url net/http-client net/sendurl racket/sandbox))

(define (resolve-mpi mpi base-dir)
  (define resolved
    (parameterize ([current-load-relative-directory base-dir])
      (module-path-index-resolve mpi)))
  (resolved-module-path-name resolved))

(define (dir-of name parent-base-dir)
  (if (path? name) (path-only name) parent-base-dir))

(define (direct-imports m base-dir)
  (with-handlers ([exn:fail? (lambda (e) '())])
    (define phase-groups (module->imports m))
    (apply append
           (map (lambda (pg) (map (lambda (mpi) (resolve-mpi mpi base-dir)) (cdr pg)))
                phase-groups))))

(define (transitive-imports top top-dir)
  (namespace-require top)
  (let loop ([queue (list (cons top top-dir))] [seen (set)])
    (cond
      [(null? queue) seen]
      [else
       (define m (car (car queue)))
       (define base-dir (cdr (car queue)))
       (cond
         [(or (not m) (set-member? seen m)) (loop (cdr queue) seen)]
         [else
          (define children (direct-imports m base-dir))
          (define child-pairs (map (lambda (c) (cons c (dir-of c base-dir))) children))
          (loop (append (cdr queue) child-pairs) (set-add seen m))])])))

(define (banned-hit? visited banned-sym)
  (for/or ([m (in-set visited)])
    (and (path? m) (regexp-match? (regexp (format "/~a(\\.rkt)?$" banned-sym))
                                  (path->string m)))))

(define-runtime-path here ".")
(define fjs-path (simplify-path (build-path here ".." "from-json-schema.rkt")))

(parameterize ([current-namespace (make-base-namespace)])
  (define visited (transitive-imports (list 'file (path->string fjs-path))
                                      (path-only fjs-path)))
  (for ([b banned-module-paths])
    (check-false (banned-hit? visited b)
                 (format "from-json-schema.rkt transitively imports banned module ~a" b))))
