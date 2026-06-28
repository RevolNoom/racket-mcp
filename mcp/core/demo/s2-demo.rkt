#lang racket/base

;; Stage S2 demo + closeout witness (work item 018).
;;
;; A downstream consumer's view of the S2 foundation: it requires ONLY the
;; public module paths for three S2 subsystems, proving they compose as usable
;; standalone units (no S1 barrel needed here — each subsystem is self-contained
;; at the `file` path level). Exercises the roadmap S2 Demo line:
;;
;;   1. M3 validator — compile a JSON Schema, validate a good value, validate
;;      a bad value and print the structured validation-error path+message list.
;;   2. M5a URI template — expand a template with variable bindings, match the
;;      result URI back, print both.
;;   3. M5e stdio framing — serialize ≥2 messages, concatenate the frames, feed
;;      into a read-buffer, read them back in order, print the round-tripped
;;      messages and confirm the empty-buffer #f sentinel.
;;
;; This adds NO new protocol types / structs / contracts / errors — it is a pure
;; consumer over the already-✅ items 010–017.
;;
;; `file` requires (relative to THIS source) let `racket mcp/core/demo/s2-demo.rkt`
;; work from any working directory — same idiom as s1-demo.rkt:51.
;;
;; Plain `racket mcp/core/demo/s2-demo.rkt` prints the transcript; the
;; `module+ test` submodule holds the rackunit assertions so `raco test` makes
;; all three arms non-vacuous and CI-checkable.

(require racket/pretty
         (only-in (file "../validators/from-json-schema.rkt")
                  make-racket-native-provider)
         (only-in (file "../validators/provider.rkt")
                  provider-compile validate
                  validation-ok? validation-ok-value
                  validation-errors? validation-errors-errors
                  validation-error-path validation-error-message)
         (only-in (file "../shared/uri-template.rkt")
                  uri-template-expand uri-template-match)
         (only-in (file "../shared/stdio.rkt")
                  serialize-message make-read-buffer
                  read-buffer-append! read-buffer-read-message!))

;; ---- Arm 1: M3 JSON Schema validator ----
(define prov (make-racket-native-provider))

;; schema: object with required "name" (string) and optional "age" (number)
(define schema
  (hasheq 'type "object"
          'properties (hasheq 'name (hasheq 'type "string")
                              'age  (hasheq 'type "number"))
          'required '("name")))

(define handle (provider-compile prov schema))

(define good-value (hasheq 'name "Alice" 'age 30))
(define bad-value  (hasheq 'age 30))   ; missing required "name"

(define good-result (validate handle good-value))
(define bad-result  (validate handle bad-value))

;; ---- Arm 2: URI template expand + match ----
(define tmpl "/users/{id}/posts/{post}")
(define tmpl-vars (hasheq 'id "42" 'post "hello-world"))

(define expanded-uri (uri-template-expand tmpl tmpl-vars))
(define matched-vars (uri-template-match tmpl expanded-uri))

;; ---- Arm 3: stdio frame encode/decode ----
(define msg-a (hasheq 'jsonrpc "2.0" 'method "ping" 'id 1))
(define msg-b (hasheq 'jsonrpc "2.0" 'result (hasheq) 'id 1))

(define framed-a (serialize-message msg-a))
(define framed-b (serialize-message msg-b))
(define framed-concat (bytes-append framed-a framed-b))

(define rb (make-read-buffer))
(read-buffer-append! rb framed-concat)
(define rt-a (read-buffer-read-message! rb))
(define rt-b (read-buffer-read-message! rb))
(define rt-c (read-buffer-read-message! rb))  ; should be #f — buffer empty

;; ---- transcript (printed on a plain `racket <demo>` run) ----
(module+ main
  (printf "=== Stage S2 demo — validator + URI template + stdio round-trip ===\n\n")

  (printf "--- Arm 1: M3 JSON Schema validator ---\n")
  (printf "good value: ~a\n" good-value)
  (printf "good result (validation-ok):\n") (pretty-print good-result)
  (printf "good value → validation-ok?: ~a\n\n" (validation-ok? good-result))
  (printf "bad value: ~a\n" bad-value)
  (printf "bad result errors:\n")
  (for ([err (validation-errors-errors bad-result)])
    (printf "  path=~a  message=~a\n"
            (validation-error-path err)
            (validation-error-message err)))
  (printf "\n")

  (printf "--- Arm 2: URI template expand + match ---\n")
  (printf "template:     ~a\n" tmpl)
  (printf "vars:         ~a\n" tmpl-vars)
  (printf "expanded-uri: ~a\n" expanded-uri)
  (printf "matched-vars:\n") (pretty-print matched-vars)
  (printf "\n")

  (printf "--- Arm 3: stdio frame encode/decode ---\n")
  (printf "msg-a:  ") (pretty-print msg-a)
  (printf "msg-b:  ") (pretty-print msg-b)
  (printf "framed-concat bytes: ~a\n" (bytes-length framed-concat))
  (printf "rt-a (round-tripped):\n") (pretty-print rt-a)
  (printf "rt-b (round-tripped):\n") (pretty-print rt-b)
  (printf "rt-c (should be #f): ~a\n\n" rt-c)

  (printf "=== demo complete ===\n"))

;; ---- non-vacuous, CI-checkable assertions (run under `raco test`) ----
(module+ test
  (require rackunit)
  ;; arm 1
  (check-true  (validation-ok? good-result)     "good value → validation-ok")
  (check-equal? (validation-ok-value good-result) good-value "ok value preserved")
  (check-true  (validation-errors? bad-result)  "bad value → validation-errors")
  (let ([errs (validation-errors-errors bad-result)])
    (check-true (pair? errs)                    "at least one error")
    (check-true (string? (validation-error-message (car errs))) "error has string message")
    (check-true (regexp-match? #rx"name" (validation-error-message (car errs)))
                               "error message names the missing property")
    (check-true (list?   (validation-error-path    (car errs))) "error has list path"))
  ;; arm 2
  (check-equal? expanded-uri "/users/42/posts/hello-world" "expand correct")
  (check-true   (hash? matched-vars)            "match returns hash not #f")
  (check-equal? (hash-ref matched-vars 'id   #f) "42"          "matched id")
  (check-equal? (hash-ref matched-vars 'post #f) "hello-world" "matched post")
  ;; arm 3
  (check-true  (hash? rt-a)  "first message decoded")
  (check-true  (hash? rt-b)  "second message decoded")
  (check-false rt-c          "buffer empty → #f")
  (check-equal? (hash-ref rt-a 'method #f) "ping" "round-tripped method")
  (check-equal? (hash-ref rt-b 'id     #f) 1      "round-tripped id"))
