#lang racket/base

;; Work Item 013 — tests for the URI-template engine (M5a).
;;
;; A FIXTURE-PORT + expand/match round-trip test: it ports every
;; `typescript-sdk/packages/core/test/shared/uriTemplate.test.ts` fixture 1:1
;; (Parts 1-7), asserting the SAME expand/match result the TS suite asserts
;; (G1 parity), plus the round-trip (expand->match) for the fixtures TS itself
;; round-trips, the no-match #f cases, the symbol-key boundary, the
;; malformed-template throw set (incl. the issue #1 empty-name {}/{,} cases),
;; the security-limit + ReDoS-timing cases, an encoder-divergence unit check,
;; and the restricted-namespace portability sub-test (Part 7b).

(require rackunit
         racket/string
         racket/list
         racket/set
         racket/path
         racket/runtime-path
         (file "../uri-template.rkt")
         (only-in (file "../../main.rkt") exn:fail:mcp?))

;; Terse helpers.
(define (exp t vars) (uri-template-expand t vars))
(define (mat t uri)  (uri-template-match t uri))

;; ===========================================================================
;; Part 1 — isTemplate (uri-template?)
;; ===========================================================================

(check-true (uri-template? "{foo}"))
(check-true (uri-template? "/users/{id}"))
(check-true (uri-template? "http://example.com/{path}/{file}"))
(check-true (uri-template? "/search{?q,limit}"))

(check-false (uri-template? ""))
(check-false (uri-template? "plain string"))
(check-false (uri-template? "http://example.com/foo/bar"))
(check-false (uri-template? "{}"))   ; empty braces don't count
(check-false (uri-template? "{ }"))  ; whitespace-only doesn't count

;; ===========================================================================
;; Part 2 — Expansion (each operator)
;; ===========================================================================

;; Simple.
(check-equal? (exp "http://example.com/users/{username}" (hasheq 'username "fred"))
              "http://example.com/users/fred")
(check-equal? (uri-template-variables "http://example.com/users/{username}") '("username"))

;; Multi-name simple {x,y}.
(check-equal? (exp "{x,y}" (hasheq 'x "1024" 'y "768")) "1024,768")
(check-equal? (uri-template-variables "{x,y}") '("x" "y"))

;; Reserved-character (full) encoding.
(check-equal? (exp "{var}" (hasheq 'var "value with spaces")) "value%20with%20spaces")

;; Reserved (+) expansion — / preserved.
(check-equal? (exp "{+path}/here" (hasheq 'path "/foo/bar")) "/foo/bar/here")
(check-equal? (uri-template-variables "{+path}/here") '("path"))

;; Fragment (#).
(check-equal? (exp "X{#var}" (hasheq 'var "/test")) "X#/test")
(check-equal? (uri-template-variables "X{#var}") '("var"))

;; Label (.).
(check-equal? (exp "X{.var}" (hasheq 'var "test")) "X.test")
(check-equal? (uri-template-variables "X{.var}") '("var"))

;; Path (/).
(check-equal? (exp "X{/var}" (hasheq 'var "test")) "X/test")
(check-equal? (uri-template-variables "X{/var}") '("var"))

;; Query (?).
(check-equal? (exp "X{?var}" (hasheq 'var "test")) "X?var=test")
(check-equal? (uri-template-variables "X{?var}") '("var"))

;; Form continuation (&).
(check-equal? (exp "X{&var}" (hasheq 'var "test")) "X&var=test")
(check-equal? (uri-template-variables "X{&var}") '("var"))

;; Complex.
(check-equal? (exp "/api/{version}/{resource}/{id}"
                   (hasheq 'version "v1" 'resource "users" 'id "123"))
              "/api/v1/users/123")
(check-equal? (uri-template-variables "/api/{version}/{resource}/{id}")
              '("version" "resource" "id"))
(check-equal? (exp "/search{?tags*}" (hasheq 'tags '("nodejs" "typescript" "testing")))
              "/search?tags=nodejs,typescript,testing")
(check-equal? (uri-template-variables "/search{?tags*}") '("tags"))
(check-equal? (exp "/search{?q,page,limit}" (hasheq 'q "test" 'page "1" 'limit "10"))
              "/search?q=test&page=1&limit=10")
(check-equal? (uri-template-variables "/search{?q,page,limit}") '("q" "page" "limit"))

;; ===========================================================================
;; Part 3 — Matching
;; ===========================================================================

;; Simple — assert the SYMBOL key.
(let ([m (mat "http://example.com/users/{username}" "http://example.com/users/fred")])
  (check-equal? m (hasheq 'username "fred"))
  (check-equal? (hash-ref m 'username) "fred"))

;; Multi-var.
(check-equal? (mat "/users/{username}/posts/{postId}" "/users/fred/posts/123")
              (hasheq 'username "fred" 'postId "123"))

;; No match -> #f.
(check-equal? (mat "/users/{username}" "/posts/123") #f)

;; Exploded array -> LIST value.
(check-equal? (mat "{/list*}" "/red,green,blue")
              (hasheq 'list '("red" "green" "blue")))

;; Complex match.
(check-equal? (mat "/api/{version}/{resource}/{id}" "/api/v1/users/123")
              (hasheq 'version "v1" 'resource "users" 'id "123"))
(check-equal? (mat "/search{?q}" "/search?q=test") (hasheq 'q "test"))
(check-equal? (mat "/search{?q,page}" "/search?q=test&page=1")
              (hasheq 'q "test" 'page "1"))

;; Missing query param -> #f (required &page=([^&]+) group absent).
(check-equal? (mat "/search{?q,page}" "/search?q=test") #f)

;; Partial / over-match -> #f.
(check-equal? (mat "/users/{id}" "/users/123/extra") #f)
(check-equal? (mat "/users/{id}" "/users") #f)

;; Length mismatches -> #f.
(check-equal? (mat "/api/{param}" "/api/") #f)
(check-equal? (mat "/api/{param}" "/api") #f)
(check-equal? (mat "/api/{param}" "/api/value/extra") #f)

;; ===========================================================================
;; Part 4 — Round-trip parity (G1)
;; For the three fixtures TS itself round-trips: expand -> URI -> match recovers.
;; ===========================================================================

(let* ([t "http://example.com/users/{username}"]
       [v (hasheq 'username "fred")]
       [u (exp t v)])
  (check-equal? u "http://example.com/users/fred")
  (check-equal? (mat t u) v))

(let* ([t "/users/{username}/posts/{postId}"]
       [v (hasheq 'username "fred" 'postId "123")]
       [u (exp t v)])
  (check-equal? u "/users/fred/posts/123")
  (check-equal? (mat t u) v))

(let* ([t "/api/{version}/{resource}/{id}"]
       [v (hasheq 'version "v1" 'resource "users" 'id "123")]
       [u (exp t v)])
  (check-equal? u "/api/v1/users/123")
  (check-equal? (mat t u) v))

;; Non-bijective: an encoded value round-trips to the ENCODED substring
;; (TS match does NOT decode). Multi-name simple {x,y} and exploded-array
;; expand are expand-ONLY in TS — no inverse fixture, none asserted here.
(let* ([t "/p/{var}"]
       [u (exp t (hasheq 'var "value with spaces"))])
  (check-equal? u "/p/value%20with%20spaces")
  (check-equal? (mat t u) (hasheq 'var "value%20with%20spaces"))) ; encoded, not decoded

;; ===========================================================================
;; Part 5 — Edge cases (ported)
;; ===========================================================================

;; Empty variables.
(check-equal? (exp "{empty}" (hasheq)) "")
(check-equal? (exp "{empty}" (hasheq 'empty "")) "")

;; Undefined variables.
(check-equal? (exp "{a}{b}{c}" (hasheq 'b "2")) "2")

;; Special chars in names.
(check-equal? (exp "{$var_name}" (hasheq '$var_name "value")) "value")

;; Overlapping names.
(check-equal? (exp "{var}{vara}" (hasheq 'var "1" 'vara "2")) "12")
(check-equal? (uri-template-variables "{var}{vara}") '("var" "vara"))

;; Empty segments preserved (expand + match back).
(check-equal? (exp "///{a}////{b}////" (hasheq 'a "1" 'b "2")) "///1////2////")
(check-equal? (mat "///{a}////{b}////" "///1////2////") (hasheq 'a "1" 'b "2"))
(check-equal? (uri-template-variables "///{a}////{b}////") '("a" "b"))

;; Repeated operators (?->& continuation).
(check-equal? (exp "{?a}{?b}{?c}" (hasheq 'a "1" 'b "2" 'c "3")) "?a=1&b=2&c=3")
(check-equal? (uri-template-variables "{?a}{?b}{?c}") '("a" "b" "c"))

;; ===========================================================================
;; Part 6 — Malformed templates (the throw set) + issue #1 empty-name cases
;; ===========================================================================

;; Drive raise/no-raise through uri-template-variables (parses unconditionally).
(check-exn exn:fail? (lambda () (uri-template-variables "{unclosed"))) ; opening-only -> raise
(check-exn exn:fail? (lambda () (uri-template-variables "{a}{")))      ; trailing unclosed -> raise
(check-not-exn (lambda () (uri-template-variables "{}")))              ; empty expr -> no raise
(check-not-exn (lambda () (uri-template-variables "{,}")))             ; comma-only -> no raise
(check-not-exn (lambda () (uri-template-variables "{unclosed}")))      ; properly closed -> no raise

;; Confirm the raise is an S1 protocol error.
(check-exn exn:fail:mcp? (lambda () (uri-template-variables "{unclosed")))

;; Empty-name expressions MUST be exercised through expand AND match (issue #1 —
;; the names[0] footgun): the SAFE #f name must not crash.
(check-not-exn (lambda () (exp "{}" (hasheq))))
(check-equal? (exp "{}" (hasheq)) "")
(check-not-exn (lambda () (exp "{,}" (hasheq))))
(check-equal? (exp "{,}" (hasheq)) "")
(check-equal? (mat "{}" "") #f)   ; deliberate hardening over TS (TS throws); MUST NOT crash
(check-equal? (mat "{}" "x") #f)

;; Empty-name part contributes NO key (never a garbage #f/empty key) — assert
;; whichever the port produces, one of (hasheq)/#f, never a crash.
(check-not-exn (lambda () (mat "a{}b" "ab")))
(check-true (let ([r (mat "a{}b" "ab")]) (or (equal? r (hasheq)) (equal? r #f))))

;; ===========================================================================
;; Part 7 — Security, ReDoS, Unicode, encoder divergence
;; ===========================================================================

;; Long input — expand returns it; match recovers it.
(let ([long (make-string 100000 #\x)])
  (check-equal? (exp "/api/{param}" (hasheq 'param long)) (string-append "/api/" long))
  (check-equal? (mat "/api/{param}" (string-append "/api/" long)) (hasheq 'param long)))

;; Deeply nested (1000x 10-expr) — expand does not raise.
(check-not-exn
 (lambda ()
   (define t (apply string-append (make-list 1000 "{a}{b}{c}{d}{e}{f}{g}{h}{i}{j}")))
   (exp t (hasheq 'a "1" 'b "2" 'c "3" 'd "4" 'e "5"
                  'f "6" 'g "7" 'h "8" 'i "9" 'j "0"))))

;; Max expression count — exactly 10_000 {param} -> no raise (cap is `>`).
(check-not-exn
 (lambda ()
   (uri-template-variables (apply string-append (make-list 10000 "{param}")))))

;; Max variable name length — a 10_000-char name -> no raise.
(check-not-exn
 (lambda ()
   (define name (make-string 10000 #\a))
   (exp (string-append "{" name "}") (hasheq (string->symbol name) "value"))))

;; Pathological match input — 100_000 a's -> no raise/hang.
(check-not-exn
 (lambda () (mat "/api/{param}" (string-append "/api/" (make-string 100000 #\a)))))

;; Non-ASCII / Unicode value (no crash). Racket strings are valid Unicode.
(check-not-exn (lambda () (exp "/api/{param}" (hasheq 'param "日本語"))))
(check-not-exn (lambda () (mat "/api/{param}" "/api/日本語")))

;; Multibyte encode parity (byte-vs-codepoint guard).
(check-equal? (exp "{var}" (hasheq 'var "é")) "%C3%A9")   ; UTF-8 bytes, not %E9
(check-equal? (exp "{var}" (hasheq 'var "あ")) "%E3%81%82") ; 3-byte char

;; Explode value-shape boundaries.
(check-equal? (exp "{?tags*}" (hasheq 'tags '("solo"))) "?tags=solo")
(check-equal? (exp "{?tags*}" (hasheq 'tags '())) "")  ; empty array -> "", NOT "?tags="
(check-equal? (exp "{list*}" (hasheq 'list '())) "")

;; Encoder divergence: a/b under {var} (component) vs {+var} (uri).
(check-equal? (exp "{var}" (hasheq 'var "a/b")) "a%2Fb")  ; component encodes /
(check-equal? (exp "{+var}" (hasheq 'var "a/b")) "a/b")   ; uri leaves / alone

;; ReDoS guard (CVE-2026-0621): timing-bounded AND result-checked.
(define redos-bound 100.0) ; ms — generous bound that still falsifies catastrophic backtracking
(let* ([payload (string-append "/" (make-string 50 #\,))]
       [t0 (current-inexact-milliseconds)]
       [r (mat "{/id*}" payload)]
       [elapsed (- (current-inexact-milliseconds) t0)])
  (check-true (< elapsed redos-bound) (format "{/id*} ReDoS elapsed ~a ms" elapsed))
  (check-equal? r #f))  ; comma-only payload has no [^/,]+ segment -> no match
(let* ([payload (make-string 50 #\,)]
       [t0 (current-inexact-milliseconds)]
       [r (mat "{id*}" payload)]
       [elapsed (- (current-inexact-milliseconds) t0)])
  (check-true (< elapsed redos-bound) (format "{id*} ReDoS elapsed ~a ms" elapsed))
  (check-equal? r #f))

;; ===========================================================================
;; Part 7b — restricted-namespace portability (S1 only).
;; Reuses the transitive module->imports walk from item 008/010/011/012. Entry
;; point is uri-template.rkt ITSELF. Specifically guards that the encoders did
;; NOT reach for net/url or net/uri-codec. Scope: module->imports does not see
;; into (module+ test ...) submodules (uri-template.rkt has none) — proves the
;; module's own import graph.
;; ===========================================================================

(define banned-module-paths
  '(racket/system racket/tcp racket/udp
    net/url net/uri-codec net/http-client net/sendurl
    racket/sandbox racket/port))

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
(define ut-path (simplify-path (build-path here ".." "uri-template.rkt")))

(parameterize ([current-namespace (make-base-namespace)])
  (define visited (transitive-imports (list 'file (path->string ut-path))
                                      (path-only ut-path)))
  ;; Non-vacuity sanity: the walk visited a non-trivial set (the entry + S1 deps).
  (check-true (> (set-count visited) 1)
              "portability walk visited too few modules (vacuous)")
  (for ([b banned-module-paths])
    (check-false (banned-hit? visited b)
                 (format "uri-template.rkt transitively imports banned module ~a" b))))
