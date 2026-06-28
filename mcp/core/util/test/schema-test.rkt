#lang racket/base

;; Work Item 012 — tests for the schema-normalization util (M4).
;;
;; A DUAL-FORM normalization test: it proves a contract input and an equivalent
;; JSON-Schema input produce the same validation behaviour AND the same wire
;; schema, plus per-form mapping coverage, the form-dependent root-type:"object"
;; invariant, the documented edge cases (the nine reviewer-mandated regression
;; cases of Part 8), and the restricted-load portability sub-test. Keyword
;; VERDICT mechanics are already covered by item 011's from-json-schema-test.rkt
;; and are NOT re-litigated here — this test asserts that normalization wires the
;; RIGHT schema into the provider.

(require rackunit
         json
         racket/contract
         racket/set
         racket/path
         racket/runtime-path
         (file "../schema.rkt")
         (file "../../main.rkt")            ; exn:fail:mcp? — the S1 error type
         (file "../../validators/provider.rkt")
         (file "../../validators/from-json-schema.rkt"))

;; --- terse helpers -------------------------------------------------------
(define (ok? ns v)  (validation-ok? (normalized-schema-validate ns v)))
(define (bad? ns v) (validation-errors? (normalized-schema-validate ns v)))
(define (wire ns)   (normalized-schema-wire ns))
(define (raises th) (check-exn exn:fail? th))

;; (same-verdicts ns-a ns-b accepts rejects): every accept ok? under BOTH,
;; every reject bad? under BOTH (the dual-form core).
(define (same-verdicts ns-a ns-b accepts rejects)
  (for ([v (in-list accepts)])
    (check-true (ok? ns-a v) (format "A should accept ~e" v))
    (check-true (ok? ns-b v) (format "B should accept ~e" v)))
  (for ([v (in-list rejects)])
    (check-true (bad? ns-a v) (format "A should reject ~e" v))
    (check-true (bad? ns-b v) (format "B should reject ~e" v))))

;; ===========================================================================
;; Part 1 — Form A (JSON Schema input)
;; ===========================================================================

;; identity + handle
(let ([ns (normalize-schema
           (hasheq 'type "object"
                   'properties (hasheq 'name (hasheq 'type "string"))
                   'required '("name")))])
  (check-true (normalized-schema? ns))
  (check-equal? (hash-ref (wire ns) 'type) "object")
  (check-true (compiled-validator? (normalized-schema-handle ns)))
  (check-true (ok? ns (hasheq 'name "John")))
  (check-true (bad? ns (hasheq))))                     ; missing required

;; root type added when absent
(let ([ns (normalize-schema (hasheq 'properties (hasheq 'x (hasheq 'type "string"))))])
  (check-equal? (hash-ref (wire ns) 'type) "object"))

;; root unchanged when already object (wire equals input modulo ensured type)
(let* ([in (hasheq 'type "object" 'properties (hasheq 'x (hasheq 'type "string")))]
       [ns (normalize-schema in)])
  (check-equal? (wire ns) in))

;; non-object root rejected — two reps (case 1c, not string-specific)
(raises (lambda () (normalize-schema (hasheq 'type "string"))))
(raises (lambda () (normalize-schema (hasheq 'type "array"))))

;; empty schema -> validation-ok (case 9, issue #7) — assert validation-ok?, not just no-exn
(let ([ns (normalize-schema (hasheq))])
  (check-equal? (hash-ref (wire ns) 'type) "object")
  (check-true (validation-ok? (normalized-schema-validate ns (hasheq 'anything 1))))
  (check-true (validation-ok? (normalized-schema-validate ns (hasheq)))))

;; deferred keyword passes through (case 3, issue #3)
(let* ([P (make-racket-native-provider)]
       [ns (normalize-schema
            (hasheq 'type "object"
                    'properties (hasheq 'name (hasheq 'type "string" 'minLength 3)))
            #:provider P)])
  (check-true (hash-has-key? (hash-ref (hash-ref (wire ns) 'properties) 'name) 'minLength))
  (check-true (ok? ns (hasheq 'name "x")))             ; deferred, not enforced
  (check-not-false (memq 'minLength (provider-warnings-for P (normalized-schema-handle ns)))))

;; string-keyed / mutable hash + non-input rejected (case 8, issue #6)
(raises (lambda () (normalize-schema (hash "type" "object"))))     ; string-keyed equal? hash
(raises (lambda () (normalize-schema (make-hasheq))))              ; mutable hasheq
(raises (lambda () (normalize-schema 42)))
(raises (lambda () (normalize-schema "x")))

;; ===========================================================================
;; Part 2 — Form B (flat-contract object descriptor)
;; ===========================================================================

(define desc-base
  (object-schema/c (hash 'name string? 'age exact-integer?) #:required '(name)))

(let ([ns (normalize-schema desc-base)])
  ;; wire equals the equivalent hand-written JSON Schema
  (check-equal? (wire ns)
                (hasheq 'type "object"
                        'properties (hasheq 'name (hasheq 'type "string")
                                            'age  (hasheq 'type "integer"))
                        'required '("name")))
  ;; required members are STRINGS; properties keys are SYMBOLS
  (check-true (string? (car (hash-ref (wire ns) 'required))))
  (check-true (andmap symbol? (hash-keys (hash-ref (wire ns) 'properties))))
  ;; optional vs required behaviour
  (check-true (bad? ns (hasheq 'age 5)))                ; missing required name
  (check-true (ok?  ns (hasheq 'name "a")))             ; optional age absent
  (check-true (bad? ns (hasheq 'name "a" 'age "x"))))   ; optional present-but-wrong-type

;; helper: the wire fragment a one-field required descriptor produces
(define (frag-of field-contract)
  (define ns (normalize-schema (object-schema/c (hash 'x field-contract) #:required '(x))))
  (hash-ref (hash-ref (wire ns) 'properties) 'x))

;; scalar mappings
(check-equal? (frag-of string?)        (hasheq 'type "string"))
(check-equal? (frag-of exact-integer?) (hasheq 'type "integer"))
(check-equal? (frag-of real?)          (hasheq 'type "number"))
(check-equal? (frag-of rational?)      (hasheq 'type "number"))
(check-equal? (frag-of number?)        (hasheq 'type "number"))
(check-equal? (frag-of boolean?)       (hasheq 'type "boolean"))

;; array mapping
(check-equal? (frag-of (listof string?))
              (hasheq 'type "array" 'items (hasheq 'type "string")))

;; enum mapping (all-literal only)
(check-equal? (frag-of (or/c "red" "green")) (hasheq 'enum '("red" "green")))
(let ([m (hash-ref (frag-of (or/c "x" 42 #t)) 'enum)])
  (check-true (and (member "x" m) (member 42 m) (member #t m) #t)))
(check-true (and (member (json-null) (hash-ref (frag-of (or/c "x" (json-null))) 'enum)) #t))
(check-equal? (frag-of (or/c "a"))     (hasheq 'enum '("a")))       ; single-arm
(check-equal? (frag-of (or/c "a" "a")) (hasheq 'enum '("a")))       ; duplicate de-dup

;; ===========================================================================
;; Part 3 — Dual-form equivalence (the headline)
;; ===========================================================================

(define ns-contract desc-base)
(define ns-json
  (hasheq 'type "object"
          'properties (hasheq 'name (hasheq 'type "string")
                              'age  (hasheq 'type "integer"))
          'required '("name")))

(define nc (normalize-schema ns-contract))
(define nj (normalize-schema ns-json))

(define dual-accepts (list (hasheq 'name "a" 'age 5) (hasheq 'name "a")))
(define dual-rejects (list (hasheq 'age 5)                  ; no name
                           (hasheq 'name 5)                 ; wrong-type name
                           (hasheq 'name "a" 'age "x")))    ; wrong-type age

(same-verdicts nc nj dual-accepts dual-rejects)
(check-equal? (wire nc) (wire nj))                         ; same wire

;; --- Delegation parity (issue #2) — compile DIRECT on the POST-normalization wire
;; Case 2 — typeless Form-A input exercises normalize-THEN-compile.
(let* ([P (hasheq 'properties (hasheq 'name (hasheq 'type "string")))]   ; no root type
       [nsP (normalize-schema P)]
       [direct (provider-compile (make-racket-native-provider) (wire nsP))])
  (check-equal? (validation-ok? (validate (normalized-schema-handle nsP) (hasheq 'name "x")))
                (validation-ok? (validate direct (hasheq 'name "x"))))
  (check-equal? (validation-ok? (validate (normalized-schema-handle nsP) (hasheq)))
                (validation-ok? (validate direct (hasheq))))
  ;; once type:object is present, an empty object still validates (no required) -> both ok
  (check-true (validation-ok? (validate (normalized-schema-handle nsP) (hasheq)))))

;; Case 2b — contract-form self-delegation over the full sample set.
(let ([direct-c (provider-compile (make-racket-native-provider) (wire nc))])
  (for ([v (in-list (append dual-accepts dual-rejects))])
    (check-equal? (validation-ok? (validate (normalized-schema-handle nc) v))
                  (validation-ok? (validate direct-c v))
                  (format "contract self-delegation mismatch on ~e" v))))

;; ===========================================================================
;; Part 4 — Edge cases
;; ===========================================================================

;; no-JSON-Schema-equivalent contracts -> reject (S1 error, not silent {})
(struct pt (x y))
(raises (lambda () (normalize-schema (object-schema/c (hash 'x (-> string? string?)) #:required '(x)))))
(raises (lambda () (normalize-schema (object-schema/c (hash 'x (->i ([a string?]) [r string?])) #:required '(x)))))
(raises (lambda () (normalize-schema (object-schema/c (hash 'x (struct/c pt any/c any/c)) #:required '(x)))))
(raises (lambda () (normalize-schema (object-schema/c (hash 'x even?) #:required '(x)))))
(raises (lambda () (normalize-schema (object-schema/c (hash 'x integer?) #:required '(x)))))  ; inexact-integer trap

;; error is an mcp error (S1), not a raw racket contract error
(check-exn exn:fail:mcp?
           (lambda () (normalize-schema (object-schema/c (hash 'x even?) #:required '(x)))))

;; nested object descriptors (supported) + located paths
(define inner (object-schema/c (hash 'id exact-integer?) #:required '(id)))
(let ([ns (normalize-schema (object-schema/c (hash 'outer inner) #:required '(outer)))])
  (check-equal? (hash-ref (hash-ref (wire ns) 'properties) 'outer)
                (hasheq 'type "object"
                        'properties (hasheq 'id (hasheq 'type "integer"))
                        'required '("id")))
  (let ([r (normalized-schema-validate ns (hasheq 'outer (hasheq 'id "bad")))])
    (check-true (validation-errors? r))
    (check-equal? (validation-error-path (car (validation-errors-errors r)))
                  '("outer" "id"))))

;; (listof <object-schema/c>) -> items of an object sub-schema; located path with index
(let ([ns (normalize-schema (object-schema/c (hash 'items (listof inner)) #:required '()))])
  (check-equal? (hash-ref (hash-ref (wire ns) 'properties) 'items)
                (hasheq 'type "array"
                        'items (hasheq 'type "object"
                                       'properties (hasheq 'id (hasheq 'type "integer"))
                                       'required '("id"))))
  (let ([r (normalized-schema-validate ns (hasheq 'items (list (hasheq 'id "bad"))))])
    (check-true (validation-errors? r))
    (check-equal? (validation-error-path (car (validation-errors-errors r)))
                  '("items" 0 "id"))))

;; higher-order Racket contract inside listof -> always rejected
(raises (lambda () (normalize-schema (object-schema/c (hash 'x (listof (-> any/c any/c))) #:required '()))))

;; and/c rejected (case 7) — not drop-and-record
(raises (lambda () (normalize-schema (object-schema/c (hash 'x (and/c string? immutable?)) #:required '(x)))))
(raises (lambda () (normalize-schema (object-schema/c (hash 'x (and/c string? (string-len/c 10))) #:required '(x)))))

;; or/c arm rules: mixed + all-predicate rejected (case 5 + all-predicate row)
(raises (lambda () (normalize-schema (object-schema/c (hash 'x (or/c "a" string?)) #:required '(x)))))
(raises (lambda () (normalize-schema (object-schema/c (hash 'x (or/c string? number?)) #:required '(x)))))

;; exact-integer? self-consistency (case 6): handle rejects 5.0, accepts 5
(let ([ns (normalize-schema (object-schema/c (hash 'n exact-integer?) #:required '(n)))])
  (check-true (bad? ns (hasheq 'n 5.0)))
  (check-true (ok?  ns (hasheq 'n 5))))

;; object-schema/c absent-required raises AT CONSTRUCTION (case 4)
(raises (lambda () (object-schema/c (hash 'name string?) #:required '(missing))))

;; empty Form-B descriptor (case 9) -> validation-ok (asserted, not just no-exn)
(let ([ns (normalize-schema (object-schema/c (hash) #:required '()))])
  (check-equal? (hash-ref (wire ns) 'type) "object")
  (check-true (validation-ok? (normalized-schema-validate ns (hasheq))))
  (check-true (validation-ok? (normalized-schema-validate ns (hasheq 'anything 1)))))

;; Form B root rule (form-dependent): bare scalar / array / enum root -> reject
(raises (lambda () (normalize-schema string?)))            ; bare scalar root
(raises (lambda () (normalize-schema (listof string?))))   ; case 1a array root
(raises (lambda () (normalize-schema (or/c "a" "b"))))      ; case 1b enum root (NOT auto-wrapped)

;; ===========================================================================
;; Part 5 — Provider injection + default + sugar
;; ===========================================================================

;; default provider
(let ([ns (normalize-schema (hasheq 'type "object"))])
  (check-true (compiled-validator? (normalized-schema-handle ns))))

;; custom provider routed; provider-warnings-for proves compile-through-provider
(let* ([P (make-racket-native-provider)]
       [ns (normalize-schema
            (hasheq 'type "object"
                    'properties (hasheq 'name (hasheq 'type "string" 'minLength 3)))
            #:provider P)])
  (check-not-false (memq 'minLength (provider-warnings-for P (normalized-schema-handle ns)))))

;; custom stub provider (satisfies the port) is honoured
(struct accept-all-provider ()
  #:methods gen:json-schema-validator-provider
  [(define (provider-compile p schema)
     (compiled-validator (lambda (v) (validation-ok v))))])
(let ([ns (normalize-schema (hasheq 'type "object") #:provider (accept-all-provider))])
  (check-true (ok? ns (hasheq)))
  (check-true (ok? ns (hasheq 'whatever 1))))

;; normalized-schema-validate sugar == (validate (handle ns) v)
(let ([ns (normalize-schema (hasheq 'type "object"
                                    'properties (hasheq 'name (hasheq 'type "string"))
                                    'required '("name")))])
  (check-equal? (normalized-schema-validate ns (hasheq 'name "a"))
                (validate (normalized-schema-handle ns) (hasheq 'name "a")))
  (check-true (validation-ok? (normalized-schema-validate ns (hasheq 'name "a"))))
  (check-true (validation-errors? (normalized-schema-validate ns (hasheq)))))

;; ===========================================================================
;; Part 6 — prompt-arguments helper (ships here)
;; ===========================================================================

(let* ([ns (normalize-schema
            (hasheq 'type "object"
                    'properties (hasheq 'name (hasheq 'type "string" 'description "the name")
                                        'age  (hasheq 'type "integer"))
                    'required '("name")))]
       [args (normalized-schema-prompt-arguments ns)]
       [by-name (lambda (n) (findf (lambda (a) (equal? (hash-ref a 'name) n)) args))])
  (check-equal? (length args) 2)
  (check-true (hash-ref (by-name "name") 'required))
  (check-false (hash-ref (by-name "age") 'required))
  (check-equal? (hash-ref (by-name "name") 'description) "the name")
  (check-false (hash-has-key? (by-name "age") 'description)))

;; ===========================================================================
;; Part 7 — restricted-namespace portability (S1 + M3 only).
;; Reuses the transitive module->imports walk (items 008/010/011). Entry point
;; is schema.rkt ITSELF. Guards specifically that the contract->JSON-Schema
;; mapping did NOT reach for net/url. module->imports does NOT see into
;; (module+ test …) — schema.rkt defines none.
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
(define schema-path (simplify-path (build-path here ".." "schema.rkt")))

(parameterize ([current-namespace (make-base-namespace)])
  (define visited (transitive-imports (list 'file (path->string schema-path))
                                      (path-only schema-path)))
  (for ([b banned-module-paths])
    (check-false (banned-hit? visited b)
                 (format "schema.rkt transitively imports banned module ~a" b))))
