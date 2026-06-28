#lang racket/base

;; Work Item 013 — URI templates, RFC 6570 SUBSET (M5a).
;;
;; A near-direct TRANSLITERATION of the MCP TypeScript SDK's
;; `packages/core/src/shared/uriTemplate.ts` `UriTemplate` class into idiomatic
;; Racket. Same operator set, same expand semantics, same regex-based match
;; semantics, same edge-case behaviour. Built target: byte-for-byte parity with
;; the TS results for the ported `uriTemplate.test.ts` fixtures (vision goal G1).
;;
;; This is a SUBSET of RFC 6570 — exactly the operators/forms the TS impl
;; exercises. It is NOT a full Level-4 RFC 6570 implementation: no prefix
;; modifiers (`{var:3}`), no `;` path-style operator. A later item may add them.
;;
;; ---------------------------------------------------------------------------
;; Public surface (string-first functions; no exposed compiled-template struct):
;;   (uri-template-expand    template vars) -> string
;;   (uri-template-match     template uri)  -> (or/c (hash sym -> (or/c str (listof str))) #f)
;;   (uri-template?          str)           -> boolean?   (TS isTemplate)
;;   (uri-template-variables template)      -> (listof string?)  (TS variableNames)
;; Each operation re-parses the (tiny) template via one shared `parse-template`.
;;
;; ---------------------------------------------------------------------------
;; Operator table (ported from TS `expandPart` + `partToRegExp`).
;; The operator is the FIRST char of an expression if it is one of + # . / ? &
;; (else "" — simple). A trailing `*` on the expression marks EXPLODE.
;;
;;  Op | Form        | Expand                                  | Match regex
;;  ---+-------------+-----------------------------------------+-----------------------------
;;   - | {var}       | full-encode, join multi-value with ,    | ([^/,]+)  (exploded: ([^/,]+(?:,[^/,]+)*))
;;   + | {+var}      | reserved-encode (encodeURI), join ,     | (.+)
;;   # | {#var}      | "#" prefix, reserved-encode, join ,     | (.+)
;;   . | {.var}      | "." prefix, full-encode, join .         | \.([^/,]+)
;;   / | {/var}      | "/" prefix, full-encode, join /         | /([^/,]+)  (exploded: /([^/,]+(?:,[^/,]+)*))
;;   ? | {?a,b}      | "?" prefix, name=value pairs join &      | \?name=([^&]+) first, &name=([^&]+) after
;;   & | {&a,b}      | "&" prefix, name=value pairs join &      | \&name=([^&]+) first, &name=([^&]+) after
;;
;; Quirks ported verbatim:
;;  - Simple multi-name (non-query, names.length>1, e.g. {x,y}): take the FIRST
;;    element of any array value and join present values with "," (does NOT
;;    explode each).
;;  - Query/form multi-name skips undefined variables (no pair emitted). Arrays
;;    join their elements with "," into one name=v1,v2.
;;  - ?->& continuation: a second {?...}/{&...} after the first is rewritten from
;;    "?" to "&" (so {?a}{?b} -> ?a=1&b=2). Tracked via a hasQueryParam thread.
;;
;; ---------------------------------------------------------------------------
;; Encoding (match JS exactly; hand-rolled over UTF-8 BYTES; NO net/url, NO
;; net/uri-codec — both BANNED by the Portability NFR and semantically divergent
;; from JS). Multibyte chars encode over UTF-8 bytes (é -> %C3%A9, not %E9).
;;   encode-uri-component (default ops) unreserved (left as-is):
;;       A-Z a-z 0-9 - _ . ! ~ * ' ( )
;;   encode-uri (ops + and #) unreserved (left as-is): the above PLUS
;;       ; , / ? : @ & = + $ # [ ]
;;   Everything else -> %XX over UTF-8 bytes (UPPERCASE hex).
;;
;; ---------------------------------------------------------------------------
;; Match semantics (ported from TS `match`):
;;  - Build an anchored ^...$ regex: literals regex-escaped; each expression
;;    contributes its operator's capture pattern; name + exploded recorded per
;;    group.
;;  - No match -> #f (the idiomatic Racket analogue of TS null; an expected,
;;    non-exceptional outcome the S6b consumer routes on).
;;  - On match: strip trailing `*` from the name; if exploded AND the captured
;;    value contains a comma, split on "," into a list; else single string.
;;  - match does NOT percent-decode — the recovered value is the raw (encoded)
;;    captured substring (so encoded round-trips recover the ENCODED form).
;;  - Result hash is SYMBOL-keyed immutable (hasheq), matching the jsexpr
;;    convention; the vars map passed to expand is likewise symbol-keyed.
;;
;; ---------------------------------------------------------------------------
;; Security limits (ported from TS; CVE-2026-0621 ReDoS fix):
;;  MAX-TEMPLATE-LENGTH / MAX-VARIABLE-LENGTH / MAX-TEMPLATE-EXPRESSIONS (a `>`
;;  cap — 10_000 allowed, 10_001 raises) / MAX-REGEX-LENGTH. The exploded
;;  pattern shape ([^/,]+(?:,[^/,]+)*) is the de-ReDoS'd form — it does not
;;  catastrophically backtrack on adversarial comma-only input.
;;
;; ---------------------------------------------------------------------------
;; Malformed-template throw set (matches TS):
;;   "{unclosed"  -> RAISE (unclosed brace; an S1 make-protocol-error)
;;   "{a}{"       -> RAISE (trailing unclosed)
;;   "{}"         -> no raise (empty expr; getNames filters -> no names)
;;   "{,}"        -> no raise (comma-only; all names filtered)
;;   "{unclosed}" -> no raise (a variable named "unclosed")
;; Empty-name parts (the {}/{,} cases) are PUSHED with name = #f — the SAFE
;; analogue of TS `names[0]`, NOT (first names) which would raise on '() and
;; crash expand/match on these legal inputs. An empty-name part expands to ""
;; and binds no result key.

(require racket/string
         racket/list
         "../main.rkt")

(provide uri-template-expand
         uri-template-match
         uri-template?
         uri-template-variables)

;; ===========================================================================
;; Security limit constants (ported verbatim from TS).
;; ===========================================================================

(define MAX-TEMPLATE-LENGTH 1000000)      ; 1MB template-string cap
(define MAX-VARIABLE-LENGTH 1000000)      ; 1MB per variable name AND value
(define MAX-TEMPLATE-EXPRESSIONS 10000)   ; cap on number of {...} expressions
(define MAX-REGEX-LENGTH 1000000)         ; cap on generated match regex length

(define (validate-length str max-len context)
  (when (> (string-length str) max-len)
    (raise (make-protocol-error
            -32600
            (format "~a exceeds maximum length of ~a characters (got ~a)"
                    context max-len (string-length str))))))

;; ===========================================================================
;; Hand-rolled encoders (over UTF-8 BYTES; JS-parity; NO net/*).
;; ===========================================================================

;; The encodeURIComponent unreserved set (left as-is): alnum + - _ . ! ~ * ' ( )
(define (component-unreserved? b)
  (or (and (>= b 48) (<= b 57))    ; 0-9
      (and (>= b 65) (<= b 90))    ; A-Z
      (and (>= b 97) (<= b 122))   ; a-z
      (memv b '(45 95 46 33 126 42 39 40 41)))) ; - _ . ! ~ * ' ( )

;; The encodeURI unreserved set: the above PLUS ; , / ? : @ & = + $ # [ ]
(define (uri-unreserved? b)
  (or (component-unreserved? b)
      (memv b '(59 44 47 63 58 64 38 61 43 36 35 91 93)))) ; ; , / ? : @ & = + $ # [ ]

(define hex-digits "0123456789ABCDEF")

(define (encode-with unreserved? value)
  (define bs (string->bytes/utf-8 value))
  (define out (open-output-string))
  (for ([b (in-bytes bs)])
    (cond
      [(unreserved? b) (write-char (integer->char b) out)]
      [else
       (write-char #\% out)
       (write-char (string-ref hex-digits (quotient b 16)) out)
       (write-char (string-ref hex-digits (remainder b 16)) out)]))
  (get-output-string out))

(define (encode-uri-component value) (encode-with component-unreserved? value))
(define (encode-uri value)           (encode-with uri-unreserved? value))

;; encodeValue(value, operator): + / # -> encodeURI, else encodeURIComponent.
(define (encode-value value operator)
  (validate-length value MAX-VARIABLE-LENGTH "Variable value")
  (if (or (string=? operator "+") (string=? operator "#"))
      (encode-uri value)
      (encode-uri-component value)))

;; ===========================================================================
;; Parsing — a part is either a literal string or an expr struct.
;;   name:     #f when there are no names (the {}/{,} case) — SAFE TS names[0].
;;   operator: "" + # . / ? &
;;   names:    list of cleaned variable names (may be '())
;;   exploded: #t when the expression contains `*`
;; ===========================================================================

(struct expr-part (name operator names exploded) #:transparent)

(define operators '("+" "#" "." "/" "?" "&"))

(define (get-operator expr)
  (or (for/or ([op (in-list operators)])
        (and (string-prefix? expr op) op))
      ""))

;; getNames: strip operator prefix, split on ",", strip `*` + trim each name,
;; filter out empties.
(define (get-names expr)
  (define op (get-operator expr))
  (filter (lambda (n) (> (string-length n) 0))
          (map (lambda (n) (string-trim (string-replace n "*" "")))
               (string-split (substring expr (string-length op)) "," #:trim? #f))))

;; parse-template : string -> (listof (or/c string expr-part))
(define (parse-template template)
  (validate-length template MAX-TEMPLATE-LENGTH "Template")
  (let loop ([i 0]
             [current ""]
             [parts '()]
             [expr-count 0])
    (cond
      [(>= i (string-length template))
       (reverse (if (> (string-length current) 0) (cons current parts) parts))]
      [(char=? (string-ref template i) #\{)
       (define parts* (if (> (string-length current) 0) (cons current parts) parts))
       (define end (find-close template i))
       (when (not end) (raise (make-protocol-error -32600 "Unclosed template expression")))
       (define expr-count* (add1 expr-count))
       (when (> expr-count* MAX-TEMPLATE-EXPRESSIONS)
         (raise (make-protocol-error
                 -32600
                 (format "Template contains too many expressions (max ~a)"
                         MAX-TEMPLATE-EXPRESSIONS))))
       (define expr (substring template (add1 i) end))
       (define op (get-operator expr))
       (define exploded (string-contains? expr "*"))
       (define names (get-names expr))
       (for ([n (in-list names)])
         (validate-length n MAX-VARIABLE-LENGTH "Variable name"))
       ;; SAFE names[0] — #f on empty names (the {}/{,} case). See module doc.
       (define name (and (pair? names) (first names)))
       (loop (add1 end)
             ""
             (cons (expr-part name op names exploded) parts*)
             expr-count*)]
      [else
       (loop (add1 i)
             (string-append current (string (string-ref template i)))
             parts
             expr-count)])))

;; find-close : index of the next #\} at or after i, else #f.
(define (find-close template i)
  (let scan ([j (add1 i)])
    (cond
      [(>= j (string-length template)) #f]
      [(char=? (string-ref template j) #\}) j]
      [else (scan (add1 j))])))

;; ===========================================================================
;; uri-template? (TS isTemplate) — any {...} with a non-empty, non-whitespace
;; body. Mirrors the TS /\{[^}\s]+\}/ test.
;; ===========================================================================

(define template-rx #px"\\{[^}\\s]+\\}")

(define (uri-template? str)
  (and (regexp-match? template-rx str) #t))

;; ===========================================================================
;; uri-template-variables (TS variableNames) — flat-map expression parts' names.
;; ===========================================================================

(define (uri-template-variables template)
  (append-map (lambda (p) (if (expr-part? p) (expr-part-names p) '()))
              (parse-template template)))

;; ===========================================================================
;; Expand
;; ===========================================================================

(define (var-ref vars name)
  (and name (hash-ref vars (string->symbol name) #f)))

;; expand-part : expr-part hash -> string
(define (expand-part part vars)
  (define op (expr-part-operator part))
  (cond
    ;; Query / form: name=value pairs, skipping undefined; arrays join with ",".
    [(or (string=? op "?") (string=? op "&"))
     (define pairs
       (filter
        (lambda (s) (> (string-length s) 0))
        (map (lambda (name)
               (define value (var-ref vars name))
               (cond
                 [(eq? value #f) ""]
                 ;; An empty array contributes no pair, like an absent variable
                 ;; (spec PIN: {?tags*} + '() -> "", NOT "?tags=").
                 [(and (list? value) (null? value)) ""]
                 [(list? value)
                  (string-append name "=" (string-join
                                           (map (lambda (v) (encode-value v op)) value) ","))]
                 [else (string-append name "=" (encode-value value op))]))
             (expr-part-names part))))
     (if (null? pairs)
         ""
         (string-append (if (string=? op "?") "?" "&") (string-join pairs "&")))]
    ;; Simple multi-name (e.g. {x,y}): first element of arrays, join present ",".
    [(> (length (expr-part-names part)) 1)
     (define values (filter (lambda (v) (not (eq? v #f)))
                            (map (lambda (n) (var-ref vars n)) (expr-part-names part))))
     (if (null? values)
         ""
         (string-join (map (lambda (v) (if (list? v) (if (null? v) "" (first v)) v)) values) ","))]
    ;; Single name (name may be #f for an empty-name part -> "").
    [else
     (define value (var-ref vars (expr-part-name part)))
     (cond
       [(eq? value #f) ""]
       [else
        (define values (if (list? value) value (list value)))
        (define encoded (map (lambda (v) (encode-value v op)) values))
        (cond
          [(null? encoded) ""]
          [(string=? op "")  (string-join encoded ",")]
          [(string=? op "+") (string-join encoded ",")]
          [(string=? op "#") (string-append "#" (string-join encoded ","))]
          [(string=? op ".") (string-append "." (string-join encoded "."))]
          [(string=? op "/") (string-append "/" (string-join encoded "/"))]
          [else (string-join encoded ",")])])]))

(define (uri-template-expand template vars)
  (define parts (parse-template template))
  (let loop ([parts parts] [result ""] [has-query? #f])
    (cond
      [(null? parts) result]
      [(string? (car parts))
       (loop (cdr parts) (string-append result (car parts)) has-query?)]
      [else
       (define part (car parts))
       (define op (expr-part-operator part))
       (define expanded (expand-part part vars))
       (define query-op? (or (string=? op "?") (string=? op "&")))
       (cond
         [(= (string-length expanded) 0)
          (loop (cdr parts) result has-query?)]
         [else
          (define emitted
            (if (and query-op? has-query?)
                (string-replace expanded "?" "&" #:all? #f)
                expanded))
          (loop (cdr parts)
                (string-append result emitted)
                (or has-query? query-op?))])])))

;; ===========================================================================
;; Match
;; ===========================================================================

;; Regex-escape a literal (the JS escapeRegExp set: . * + ? ^ $ { } ( ) | [ ] \).
(define escape-rx #rx"[.*+?^${}()|[\\]\\\\]")

(define (escape-regexp str)
  (regexp-replace* escape-rx str "\\\\&"))

;; part->patterns : expr-part -> (listof (cons pattern name-or-#f))
(define (part->patterns part)
  (define op (expr-part-operator part))
  (for ([n (in-list (expr-part-names part))])
    (validate-length n MAX-VARIABLE-LENGTH "Variable name"))
  (cond
    [(or (string=? op "?") (string=? op "&"))
     (for/list ([name (in-list (expr-part-names part))] [i (in-naturals)])
       (define prefix (if (= i 0) (string-append "\\" op) "&"))
       (cons (string-append prefix (escape-regexp name) "=([^&]+)") name))]
    [else
     (define exploded (expr-part-exploded part))
     (define pattern
       (cond
         [(string=? op "")  (if exploded "([^/,]+(?:,[^/,]+)*)" "([^/,]+)")]
         [(string=? op "+") "(.+)"]
         [(string=? op "#") "(.+)"]
         [(string=? op ".") "\\.([^/,]+)"]
         [(string=? op "/") (string-append "/" (if exploded "([^/,]+(?:,[^/,]+)*)" "([^/,]+)"))]
         [else "([^/]+)"]))
     (list (cons pattern (expr-part-name part)))]))

(define (uri-template-match template uri)
  (validate-length uri MAX-TEMPLATE-LENGTH "URI")
  (define parts (parse-template template))
  ;; Build pattern + the ordered name/exploded list, one entry per capture group.
  (define-values (pattern names)
    (for/fold ([pattern "^"] [names '()] #:result (values pattern (reverse names)))
              ([part (in-list parts)])
      (cond
        [(string? part)
         (values (string-append pattern (escape-regexp part)) names)]
        [else
         (define exploded (expr-part-exploded part))
         (for/fold ([pattern pattern] [names names])
                   ([pp (in-list (part->patterns part))])
           (values (string-append pattern (car pp))
                   (cons (cons (cdr pp) exploded) names)))])))
  (define full-pattern (string-append pattern "$"))
  (validate-length full-pattern MAX-REGEX-LENGTH "Generated regex pattern")
  (define m (regexp-match (pregexp full-pattern) uri))
  (cond
    [(not m) #f]
    ;; An empty-name part ({}/{,}) emits a capture group but has no name to
    ;; bind. TS crashes here (undefined.replace); the port hardens to #f — a
    ;; nameless capture that actually matched is treated as a NO-match, never a
    ;; garbage-keyed bind. Issue #1. (match("{}","x") -> #f, not (hasheq).)
    [(for/or ([n+e (in-list names)]) (not (car n+e))) #f]
    [else
     (for/fold ([result (hasheq)])
               ([name+exploded (in-list names)] [value (in-list (cdr m))])
       (define name (car name+exploded))
       (define exploded (cdr name+exploded))
       (define clean (string->symbol (string-replace name "*" "")))
       (define v (if (and exploded value (string-contains? value ","))
                     (string-split value ",")
                     value))
       (hash-set result clean v))]))
