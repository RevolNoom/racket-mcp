#lang racket/base

;; ===========================================================================
;; S2 collection-wide Portability-NFR sweep (item 017).
;;
;; PURPOSE. Items 010–015 each ship a *per-module* portability walk inside
;; their own test. This file is the single, collection-spanning proof the
;; Portability NFR (vision.md §6; architecture.md §4.1) requires for ALL S2
;; non-I/O modules at once: requiring any of the seven roots below pulls in
;; NO subprocess/socket module, transitively, at any import depth. It mirrors
;; what main-test.rkt already does for the two S1 barrels, extended to S2's
;; leaves. The restricted-namespace transitive-import walk machinery below is
;; COPIED VERBATIM from main-test.rkt:49-105 (copy, not factor — zero risk to
;; the existing S1 suite; ~45 lines of duplication is the cheaper trade).
;;
;; THE SEVEN NON-I/O ROOTS (each referenced by an explicit literal path):
;;   validators/provider.rkt              (M3, item 010)
;;   validators/from-json-schema.rkt      (M3, item 011)
;;   util/schema.rkt                      (M4, item 012)
;;   shared/uri-template.rkt              (M5a, item 013)
;;   shared/tool-name-validation.rkt      (M5b, item 014)
;;   shared/metadata-utils.rkt            (M5c, item 015)
;;   shared/auth.rkt                      (M5d, item 015)
;;
;; stdio.rkt (M5e) CARVE-OUT. mcp/core/shared/stdio.rkt is the one S2 module
;; permitted to touch byte-stream I/O (the newline-delimited framing buffer).
;; It is excluded HERE *as a root* — the sweep never names it and never walks
;; it as a starting point. It is NOT exempt from portability, though: if any
;; swept module ever transitively `require`s stdio.rkt, the walk follows that
;; edge and would correctly surface stdio's banned imports as the *importing*
;; module's portability regression. Exclusion is scoped to "do not start the
;; walk at stdio", not "skip stdio if reached".
;;
;; LITERAL PATHS, NOT GLOB. The roots are enumerated literally — never a
;; directory-list/glob over shared/ — precisely so the carve-out holds: a glob
;; would silently pick up stdio.rkt the moment item 016 lands and break the
;; isolation. As of this file, mcp/core/shared/stdio.rkt does not yet exist
;; (item 016 unbuilt); its absence changes nothing here, and the test is NOT
;; conditional on it. If 016 lands first, stdio.rkt simply stays off the roots
;; list. Either way this sweep is byte-identical.
;;
;; rackunit `check-*` run at module top level, so
;; `racket mcp/core/test/s2-portability-test.rkt` executes the suite.
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

;; check-portable! is retained VERBATIM from the S1 template (copy mandate,
;; acceptance line 61). The S2 sweep itself uses check-root below instead: it
;; runs ONE walk per root and asserts BOTH the banned-module checks AND the
;; teeth-proving non-vacuity guard on that single `visited` set.
(define (check-portable! top-path top-dir label)
  (parameterize ([current-namespace (make-base-namespace)])
    (define visited (transitive-imports top-path top-dir))
    (for ([b banned-module-paths])
      (check-false (banned-hit? visited b)
                   (format "~a transitively imports banned module ~a" label b)))))

;; ---------------------------------------------------------------------------
;; Teeth-proving non-vacuity guard (item 017 — strengthens the bare
;; `(> (set-count visited) 1)` guard, which is provably blind to a truncated
;; walk: a wrong-base-dir walk that never reaches the S1 subtree still reports
;; visited≈79 — racket/base's own closure — and passes `> 1` green). We prove
;; the walk was not truncated by PATH PRESENCE, the mirror of banned-hit?.
;; ---------------------------------------------------------------------------

;; #t iff some resolved path in `visited` matches `rx` — the positive twin of
;; banned-hit?, used to assert a known edge actually resolved.
(define (visited-matches? visited rx)
  (for/or ([m (in-set visited)])
    (and (path? m) (regexp-match? rx (path->string m)))))

;; The six S1-importing roots: a resolved `../main.rkt` (or a spec-2026 module
;; reached through it) proves the relative S1 edge actually resolved — i.e. the
;; walk was NOT truncated one level early by a wrong base-dir.
(define (s1-edge-teeth visited label)
  (check-true (or (visited-matches? visited #rx"core/main\\.rkt")
                  (visited-matches? visited #rx"spec-2026"))
              (format "walk truncated — S1 edge not reached for ~a" label)))

;; tool-name-validation.rkt has NO S1 edge (base-collections-only per item 014);
;; its only declared imports are racket/string + racket/list. Assert one of
;; those resolved, or floor at >= 50 visited (its real closure is ≈ 82). The
;; bare `> 1` guard is meaningless for this root.
(define (base-collection-teeth visited label)
  (check-true (or (visited-matches? visited #rx"/(string|list)\\.rkt$")
                  (>= (set-count visited) 50))
              (format "walk truncated — base-collection edge not reached for ~a" label)))

;; Run ONE walk for `root-path` in a fresh base namespace with a PER-ROOT
;; base-dir = (path-only root-path) — never a single shared here-derived dir
;; (the seven roots span three directories; a shared base-dir would truncate
;; every root in the "wrong" collection). Assert BOTH banned-module absence
;; (check-portable!'s inner loop) AND the supplied teeth guard on that one set.
(define (check-root root-path label teeth-check)
  (parameterize ([current-namespace (make-base-namespace)])
    (define base-dir (path-only root-path))
    (define visited (transitive-imports (list 'file (path->string root-path)) base-dir))
    (for ([b banned-module-paths])
      (check-false (banned-hit? visited b)
                   (format "~a transitively imports banned module ~a" label b)))
    (teeth-check visited label)))

;; ---------------------------------------------------------------------------
;; The seven roots — built from `here` (the test dir) via literal build-path,
;; mirroring main-test.rkt:107-114. `here`/".." is mcp/core/.
;; ---------------------------------------------------------------------------

(define-runtime-path here ".")
(define provider-path     (simplify-path (build-path here ".." "validators" "provider.rkt")))
(define from-json-path    (simplify-path (build-path here ".." "validators" "from-json-schema.rkt")))
(define schema-path       (simplify-path (build-path here ".." "util" "schema.rkt")))
(define uri-template-path (simplify-path (build-path here ".." "shared" "uri-template.rkt")))
(define tool-name-path    (simplify-path (build-path here ".." "shared" "tool-name-validation.rkt")))
(define metadata-path     (simplify-path (build-path here ".." "shared" "metadata-utils.rkt")))
(define auth-path         (simplify-path (build-path here ".." "shared" "auth.rkt")))

(check-root provider-path     "validators/provider.rkt"          s1-edge-teeth)
(check-root from-json-path    "validators/from-json-schema.rkt"  s1-edge-teeth)
(check-root schema-path       "util/schema.rkt"                  s1-edge-teeth)
(check-root uri-template-path "shared/uri-template.rkt"          s1-edge-teeth)
(check-root tool-name-path    "shared/tool-name-validation.rkt"  base-collection-teeth)
(check-root metadata-path     "shared/metadata-utils.rkt"        s1-edge-teeth)
(check-root auth-path         "shared/auth.rkt"                  s1-edge-teeth)
