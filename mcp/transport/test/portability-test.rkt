#lang racket/base

;; ===========================================================================
;; S3 transport Portability-NFR sweep (item 022).
;;
;; PURPOSE. The S3 restricted-load portability proof for the transport layer:
;; requiring the transport barrel `mcp/transport/main.rkt` pulls in NO
;; subprocess/socket/web-server module, transitively, at any import depth
;; (vision.md §6 Portability NFR; roadmap.md:157-158). It mirrors what
;; main-test.rkt does for the two S1 barrels and s2-portability-test.rkt does
;; for the S2 leaves. The restricted-namespace transitive-import walk machinery
;; below is COPIED VERBATIM from main-test.rkt:49-105 (copy, not factor — zero
;; risk to the existing S1/S2 suites).
;;
;; ONE ROOT — the barrel. The barrel `mcp/transport/main.rkt` re-exports both
;; M6 (transport.rkt) and M10 (in-memory.rkt), so a single walk rooted at the
;; barrel transitively covers both modules. We walk exactly ONE root, never
;; enumerating transport.rkt/in-memory.rkt separately.
;;
;; S3-SPECIFIC — web-server ban. The S1 banned-module-paths list has no
;; `web-server` entry, and banned-hit?'s `#rx"/<sym>(\.rkt)?$"` matches only a
;; path ending `/web-server.rkt`, missing nested collection paths like
;; `web-server/http`. So the web-server ban is a SEPARATE assertion over the
;; visited set: `#rx"/web-server/"`.
;;
;; rackunit `check-*` run at module top level, so
;; `racket mcp/transport/test/portability-test.rkt` executes the suite.
;; ===========================================================================

(require rackunit
         racket/set
         racket/path
         racket/runtime-path)

;; ---------------------------------------------------------------------------
;; Walk machinery — COPIED VERBATIM from main-test.rkt:49-105.
;; ---------------------------------------------------------------------------

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

;; check-portable! is retained VERBATIM from the S1 template (copy mandate).
;; The sweep below drives the walk once and asserts on that single `visited`
;; set (banned-module loop + web-server + two non-vacuity guards).
(define (check-portable! top-path top-dir label)
  (parameterize ([current-namespace (make-base-namespace)])
    (define visited (transitive-imports top-path top-dir))
    (for ([b banned-module-paths])
      (check-false (banned-hit? visited b)
                   (format "~a transitively imports banned module ~a" label b)))))

;; ---------------------------------------------------------------------------
;; Positive-match helper — the twin of banned-hit?, for the web-server ban and
;; the two teeth-proving non-vacuity guards.
;; ---------------------------------------------------------------------------

;; #t iff some resolved path in `visited` matches `rx`.
(define (visited-has? visited rx)
  (for/or ([m (in-set visited)])
    (and (path? m) (regexp-match? rx (path->string m)))))

;; ---------------------------------------------------------------------------
;; The single root — the transport barrel, built from `here` (the test dir).
;; `here` = mcp/transport/test/ ; ".." = mcp/transport/ ; main.rkt = the barrel.
;; base-dir = (path-only root) so transport.rkt's `../core/main.rkt` relative
;; import resolves without truncation.
;; ---------------------------------------------------------------------------

(define-runtime-path here ".")
(define root (simplify-path (build-path here ".." "main.rkt")))

(parameterize ([current-namespace (make-base-namespace)])
  (define base-dir (path-only root))
  (define visited (transitive-imports (list 'file (path->string root)) base-dir))

  ;; (1) banned-module absence — no subprocess/socket module reachable.
  (for ([b banned-module-paths])
    (check-false (banned-hit? visited b)
                 (format "transport barrel transitively imports banned module ~a" b)))

  ;; (2) web-server collection ban (S3-specific separate assertion — catches
  ;; nested paths like web-server/http that banned-hit?'s regex would miss).
  (check-false (visited-has? visited #rx"/web-server/")
               "transport barrel transitively imports web-server collection")

  ;; (3) teeth-proving non-vacuity guards (BOTH mandatory). A truncated walk
  ;; reports racket/base's own closure (~79 visited) and passes a bare
  ;; `(> (set-count visited) 1)` green. Prove both barrel branches were reached
  ;; by PATH PRESENCE.
  (check-true (visited-has? visited #rx"core/main\\.rkt")
              "walk truncated — S1 edge (M6 branch via transport.rkt) not reached")
  (check-true (visited-has? visited #rx"in-memory\\.rkt")
              "walk truncated — M10 branch (in-memory.rkt) not reached"))
