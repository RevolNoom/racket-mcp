#lang racket/base

;; Work Item 010 — tests for the validator-provider PORT.
;;
;; A SHAPE / CONTRACT test through stub providers — explicitly NOT a TS-baseline
;; parity test (that is item 011). Six parts:
;;   1. TWO stub providers prove the gen: swap seam (the port's whole point).
;;   2. handle reuse + independent handles ("called multiple times").
;;   3. value matrix — the result carries the validated value, equal?.
;;   4. result/error struct contract (falsifiable: guards, closed-set, dispatch).
;;   5. restricted-namespace portability walk (S1-only) — entry IS provider.rkt.
;;   6. compile-on-garbage + cross-provider handle + non-jsexpr input policy.

(require rackunit
         racket/generic
         json
         racket/set
         racket/path
         racket/runtime-path
         (file "../provider.rkt"))

;; ===========================================================================
;; Stub providers (NO real keyword logic — trivial by design).
;; Both fail-fast at compile on a missing key (Decisions (e), item 011 inherits).
;; ===========================================================================

;; Stub A — const-equality. Reads (hash-ref schema 'const) at compile.
(struct stub-const ()
  #:methods gen:json-schema-validator-provider
  [(define (provider-compile p schema)
     (unless (and (hash? schema) (hash-has-key? schema 'const))
       (error 'stub-const "schema missing 'const key: ~e" schema))
     (define expected (hash-ref schema 'const))
     (compiled-validator
      (lambda (v)
        (if (equal? v expected)
            (validation-ok v)
            (validation-errors
             (list (validation-error '() (format "expected ~e, got ~e" expected v))))))))])

;; Stub B — type-style. Reads (hash-ref schema 'type) at compile -> predicate.
(struct stub-type ()
  #:methods gen:json-schema-validator-provider
  [(define (provider-compile p schema)
     (unless (and (hash? schema) (hash-has-key? schema 'type))
       (error 'stub-type "schema missing 'type key: ~e" schema))
     (define t (hash-ref schema 'type))
     (define pred (cond [(equal? t "string") string?]
                        [(equal? t "number") number?]
                        [else (lambda (_) #f)]))
     (compiled-validator
      (lambda (v)
        (if (pred v)
            (validation-ok v)
            (validation-errors
             (list (validation-error '() (format "not a ~a" t))))))))])

;; Stub C — accept-anything (for the value matrix). Ignores the schema body.
(struct stub-any ()
  #:methods gen:json-schema-validator-provider
  [(define (provider-compile p schema)
     (compiled-validator (lambda (v) (validation-ok v))))])

(define stub-a (stub-const))
(define stub-b (stub-type))
(define stub-c (stub-any))

;; ===========================================================================
;; Part 1 — TWO stub providers (the swap seam — most important test)
;; ===========================================================================

(define hA (provider-compile stub-a (hasheq 'const 42)))
(define hB (provider-compile stub-b (hasheq 'type "string")))

(check-true (compiled-validator? hA))
(check-true (compiled-validator? hB))

;; both flow through the IDENTICAL surface, correct per-provider outcomes
(check-true (validation-ok?     (validate hA 42)))
(check-true (validation-ok?     (validate hB "hi")))
(check-true (validation-errors? (validate hA 7)))
(check-true (validation-errors? (validate hB 5)))

;; cross-check: ok-for-one is error-for-other (catches a hard-coded validate)
(check-true (validation-errors? (validate hA "hi"))) ; "hi" != 42
(check-true (validation-ok?     (validate hB "hi"))) ; "hi" is a string

;; interface conformance — the stubs really implement gen:, not bare procs
(check-true  (json-schema-validator-provider? stub-a))
(check-true  (json-schema-validator-provider? stub-b))
(check-false (json-schema-validator-provider? 42))

;; ok result recovers value; error result exposes structured path+message
(check-equal? (validation-ok-value (validate hA 42)) 42)
(let ([r (validate hA 7)])
  (check-true (validation-errors? r))
  (define errs (validation-errors-errors r))
  (check-true (pair? errs))
  (check-true (andmap validation-error? errs))
  (check-equal? (validation-error-path (car errs)) '())          ; root
  (check-true (string? (validation-error-message (car errs)))))

;; ===========================================================================
;; Part 2 — handle reuse + independence ("called multiple times")
;; ===========================================================================

;; one handle, many calls, no per-call state
(check-true  (validation-ok?     (validate hA 42)))
(check-true  (validation-errors? (validate hA 1)))
(check-equal? (validation-ok-value (validate hA 42)) 42) ; second ok still recovers 42
(check-true  (validation-errors? (validate hA 2)))

;; two independent handles from the SAME provider, different schemas
(define h1 (provider-compile stub-a (hasheq 'const 1)))
(define h2 (provider-compile stub-a (hasheq 'const 2)))
(check-true  (validation-ok?     (validate h1 1)))
(check-true  (validation-errors? (validate h2 1)))
(check-true  (validation-ok?     (validate h2 2)))
(check-true  (validation-errors? (validate h1 2))) ; no last-schema memoization

;; ===========================================================================
;; Part 3 — value matrix (the result carries the validated value, equal?)
;; ===========================================================================

(define h-any (provider-compile stub-c (hasheq)))
(for ([v (list (json-null) (hasheq 'a 1) '(1 2 3) "str" 42 #t)])
  (define r (validate h-any v))
  (check-true (validation-ok? r))
  (check-equal? (validation-ok-value r) v)) ; SAME value, no coercion/drop

;; ===========================================================================
;; Part 4 — result/error struct contract (falsifiable)
;; ===========================================================================

;; zero-error RAISES (the #:guard); non-validation-error element RAISES
(check-exn exn:fail? (lambda () (validation-errors '())))
(check-exn exn:fail? (lambda () (validation-errors (list "not-a-validation-error"))))

;; closed-set negatives — pins the variant set as exactly ok | errors
(check-false (validation-result? 42))
(check-false (validation-result? (validation-error '() "x"))) ; element is not a result

;; mutual exclusivity over built results
(let ([ok (validation-ok 1)]
      [er (validation-errors (list (validation-error '() "x")))])
  (check-false (and (validation-ok? ok) (validation-errors? ok)))
  (check-false (and (validation-ok? er) (validation-errors? er))))

;; accessor mis-dispatch RAISES — consumers MUST predicate-dispatch first
(check-exn exn:fail?
           (lambda () (validation-ok-value (validation-errors (list (validation-error '() "x"))))))
(check-exn exn:fail?
           (lambda () (validation-errors-errors (validation-ok 1))))

;; many-errors (>=2), order preserved — catches a validate keeping only first
(let ([r (validation-errors (list (validation-error '("a") "e1")
                                   (validation-error '("b") "e2")))])
  (check-equal? (length (validation-errors-errors r)) 2)
  (check-true (andmap validation-error? (validation-errors-errors r)))
  (check-equal? (map validation-error-message (validation-errors-errors r)) '("e1" "e2")))

;; path contract — root, all-string, mixed string/integer
(check-equal? (validation-error-path (validation-error '() "x")) '())
(check-equal? (validation-error-path (validation-error '("a" "b") "x")) '("a" "b"))
(check-equal? (validation-error-path (validation-error '("items" 0 "name") "x"))
              '("items" 0 "name")) ; integer array-index segment

;; ===========================================================================
;; Part 5 — restricted-namespace portability (S1-only).
;; Reuses the transitive module->imports walk from item 008 (Part C). Entry
;; point is provider.rkt ITSELF (there is no validators/main.rkt barrel yet).
;; Scope limit: module->imports does NOT see into (module+ test ...) submodules,
;; so this proves the module's OWN phase-0/1 import graph is clean.
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
(define provider-path (simplify-path (build-path here ".." "provider.rkt")))

(parameterize ([current-namespace (make-base-namespace)])
  (define visited (transitive-imports (list 'file (path->string provider-path))
                                      (path-only provider-path)))
  (for ([b banned-module-paths])
    (check-false (banned-hit? visited b)
                 (format "provider.rkt transitively imports banned module ~a" b))))

;; ===========================================================================
;; Part 6 — compile-on-garbage + cross-provider handle + non-jsexpr input
;; ===========================================================================

;; compile-on-garbage: stubs RAISE at compile on a missing/non-object schema
;; (fail-fast precedent item 011 inherits, Decisions (e)).
(check-exn exn:fail? (lambda () (provider-compile stub-a 42)))
(check-exn exn:fail? (lambda () (provider-compile stub-a '())))
(check-exn exn:fail? (lambda () (provider-compile stub-a (hasheq 'type "string")))) ; wrong key
(check-exn exn:fail? (lambda () (provider-compile stub-b (hasheq 'const 1))))        ; wrong key

;; cross-provider handle totality: handles from BOTH stubs flow through the
;; SAME validate entry point without dispatch error (vacuous-by-construction
;; under closure-in-handle — Decisions (e); stated, not a real dispatch test).
(check-true (validation-result? (validate hA 42)))
(check-true (validation-result? (validate hB "hi")))

;; non-jsexpr input: validate does NOT police input type; it applies the
;; provider closure. Pin the stub's actual behavior on (void): stub-a's
;; equal?-check returns a (validation-errors ...) (void != 42), no raise.
(let ([r (validate hA (void))])
  (check-true (validation-errors? r)))
