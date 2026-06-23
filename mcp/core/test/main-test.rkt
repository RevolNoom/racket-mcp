#lang racket/base

;; Tests for the two curated public-surface barrels (item 008):
;;   mcp/core/types/main.rkt  and  mcp/core/main.rkt
;; Covers, in one file (so the portability-walk helper is defined once and
;; reused for both barrel entry points):
;;   Part 1 — barrel re-export presence (a representative binding per module)
;;   Part 2 — the restricted-namespace transitive portability walk
;;   Part 3 — curation / negative checks (internal helpers NOT leaked)
;; rackunit `check-*` run at module top level, so
;; `racket mcp/core/test/main-test.rkt` from the repo root executes the suite.

(require rackunit
         racket/set
         racket/path
         racket/runtime-path)

;; ===========================================================================
;; Part 1 — barrel re-export presence (the representative-binding checks).
;; Each name is drawn from a DIFFERENT underlying module, so a barrel that
;; silently drops one module fails at least one check. The r25:/r26: prefixes
;; are the per-revision spec modules' re-exported names (834-collision fix).
;; ===========================================================================
(require (only-in (file "../main.rkt")
                  INTERNAL-ERROR                  ; item 001 constants (via types barrel)
                  is-jsonrpc-request?             ; item 002 guards
                  r25:jsonrpc-request?            ; item 003 spec-2025-11-25 (r25: prefix)
                  r26:related-task-metadata-task-id ; item 004 spec-2026-07-28 (r26: prefix)
                  facade-text-content?            ; item 005 types.rkt façade
                  mcp-error? protocol-error?      ; item 006 errors
                  jsonrpc-error->exn))            ; item 007 errors (DECODE)

(check-equal? INTERNAL-ERROR -32603)
(check-true (procedure? is-jsonrpc-request?))
(check-true (procedure? r25:jsonrpc-request?))
(check-true (procedure? r26:related-task-metadata-task-id))
(check-true (procedure? facade-text-content?))
(check-true (procedure? mcp-error?))
(check-true (procedure? protocol-error?))
(check-true (procedure? jsonrpc-error->exn))

;; ===========================================================================
;; Part 2 — the restricted-namespace transitive portability walk.
;; Walk module->imports from each barrel in a FRESH base namespace; assert the
;; visited resolved-module-path set never mentions a banned subprocess/socket
;; module, transitively, at any hop depth.
;; ===========================================================================

(define banned-module-paths
  '(racket/system racket/port racket/tcp racket/udp
    net/url net/http-client net/sendurl racket/sandbox))

;; Resolve a module-path-index to its resolved-module-path-name, using the
;; REQUIRING module's own directory (base-dir) as the base for relative
;; resolution. Without this base-dir, a relative sub-require resolves against
;; the ambient CWD, producing a bogus path; module->imports then raises on it
;; and the with-handlers guard below swallows it as "no further imports",
;; silently truncating the walk one level early for every relatively-required
;; module. base-dir threading is the fix.
(define (resolve-mpi mpi base-dir)
  (define resolved
    (parameterize ([current-load-relative-directory base-dir])
      (module-path-index-resolve mpi)))
  (resolved-module-path-name resolved))

;; The directory to use as the base for resolving a module's OWN children.
;; path? names propagate their containing directory; symbol? names
;; (collection requires, e.g. racket/base) have no meaningful directory here —
;; keep the parent's base-dir (never consulted for a symbol-named module).
(define (dir-of name parent-base-dir)
  (if (path? name) (path-only name) parent-base-dir))

(define (direct-imports m base-dir)
  (with-handlers ([exn:fail? (lambda (e) '())])  ; genuine introspection dead-ends only
    (define phase-groups (module->imports m))     ; ONE value, not two — no define-values
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

(define (check-portable! top-path top-dir label)
  (parameterize ([current-namespace (make-base-namespace)])
    (define visited (transitive-imports top-path top-dir))
    (for ([b banned-module-paths])
      (check-false (banned-hit? visited b)
                   (format "~a transitively imports banned module ~a" label b)))))

(define-runtime-path here ".")
(define types-main-path (simplify-path (build-path here ".." "types" "main.rkt")))
(define core-main-path  (simplify-path (build-path here ".." "main.rkt")))

(check-portable! (list 'file (path->string types-main-path))
                 (path-only types-main-path) "types/main.rkt")
(check-portable! (list 'file (path->string core-main-path))
                 (path-only core-main-path) "core/main.rkt")

;; ===========================================================================
;; Part 3 — curation / negative checks: internal-only helpers from the
;; underlying modules are NOT reachable through the barrel. Proves the barrels
;; are curated (per-module all-from-out inherits the leaf's own curation),
;; not blanket. dynamic-require with a failure thunk returns 'not-found when
;; the name is absent rather than raising.
;; ===========================================================================
(define types-main-mp (list 'file (path->string types-main-path)))
(define core-main-mp   (list 'file (path->string core-main-path)))

;; spec-2025-11-25.rkt internal wire helpers (never in its provide block)
(check-equal? (dynamic-require types-main-mp 'split-loose (lambda () 'not-found)) 'not-found)
(check-equal? (dynamic-require types-main-mp 'h-opt       (lambda () 'not-found)) 'not-found)
(check-equal? (dynamic-require types-main-mp 'put!        (lambda () 'not-found)) 'not-found)

;; errors.rkt private data-gate helpers (used only internally by jsonrpc-error->exn)
(check-equal? (dynamic-require core-main-mp 'url-elicitation-data?    (lambda () 'not-found)) 'not-found)
(check-equal? (dynamic-require core-main-mp 'unsupported-version-data? (lambda () 'not-found)) 'not-found)
