#lang racket/base

;; Work Item 011 — the DEFAULT Racket-native JSON-Schema validator provider (M3).
;;
;; This module is the FIRST concrete provider implementing the item-010 port
;; (`gen:json-schema-validator-provider`, `provider-compile`, `validate`, and
;; the `validation-ok` / `validation-errors` / `validation-error` result shape,
;; all from `provider.rkt`). It is the provider the schema util (item 012) and
;; the S2 demo (item 018) wire up by default, and the one the high-level server
;; (S6b) uses for tool I/O until/unless a vetted-library provider is adopted.
;;
;; ---------------------------------------------------------------------------
;; FRAMING — what is ported vs net-new
;; ---------------------------------------------------------------------------
;; The TS source `fromJsonSchema.ts` is a ~43-line, keyword-FREE wrapper that
;; delegates keyword logic to an injected provider (Ajv / cfWorker). Vision §8
;; EXCLUDES both, and §4.5 collapses them into ONE Racket-native provider —
;; this module. We mirror only the WRAPPER SHAPE (schema-in -> reusable
;; validate-fn-out; value-on-success / located-error-on-failure). The keyword
;; semantics here are NET-NEW Racket-native design, hand-rolled against the
;; observable behaviour `validators.test.ts` asserts for the supported subset.
;;
;; ---------------------------------------------------------------------------
;; MINIMAL-DEPS DECISION (vision §6 / §8)
;; ---------------------------------------------------------------------------
;; The default is a HAND-ROLLED keyword subset — NO external JSON-Schema
;; library — because vision §6 (Minimal-deps NFR) and §8 (Ajv/cfWorker
;; exclusions) call for it. The item-010 port exists precisely so a vetted
;; library provider can be swapped in later WITHOUT changing callers. The cost
;; of hand-rolling is a deliberately limited keyword subset (below); the
;; benefit is zero new dependencies and a portability-clean core.
;;
;; ---------------------------------------------------------------------------
;; SUPPORTED KEYWORDS (fully evaluated)
;; ---------------------------------------------------------------------------
;;   type        : "string"/"number"/"integer"/"boolean"/"object"/"array"/"null"
;;                 (per-value type check; integer = exact-integer?, number =
;;                 finite rational — +nan.0 / +inf.0 REJECTED, see below)
;;   properties  : object — for each present property, validate against its
;;                 sub-schema; absence is NOT a failure (that is `required`).
;;   required    : object — each listed key MUST be present (presence only).
;;   enum        : value MUST be `equal?` (deep structural) to a listed member.
;;   items       : array — every element MUST validate against the single
;;                 `items` sub-schema (tuple/prefixItems form OUT of scope).
;;   format      : string formats "date-time"/"uri"/"email" ONLY, and only when
;;                 the value is a string (format on a non-string is a no-op).
;;
;; ---------------------------------------------------------------------------
;; DEFERRED KEYWORDS — ignore-with-warning, warned ONCE at compile
;; ---------------------------------------------------------------------------
;;   pattern, minLength, maxLength, minimum, maximum, additionalProperties,
;;   uniqueItems
;; Each is SKIPPED during evaluation (does NOT affect accept/reject) and its
;; presence is recorded ONCE, at `provider-compile` time, in the provider's
;; per-compile weak handle->ignored-keyword map (read via
;; `provider-warnings-for`). The recorded list is the load-bearing, test-
;; readable warn-once record; a stderr line (via `eprintf`) is an optional
;; human-facing side effect. A schema using a deferred keyword stays usable —
;; its supported keywords still validate. (Reject was the considered
;; alternative — rejected: it makes the default provider brittle against
;; perfectly ordinary schemas.) The forbidden behaviour is silently honoring
;; the APPEARANCE of support: a deferred keyword's value is accepted because
;; the keyword is skipped (warned + recorded), not because it was checked.
;;
;; UNKNOWN FORMATS (any `format` other than the three supported) and UNKNOWN
;; KEYWORDS (anything neither supported, deferred, nor a pure annotation —
;; e.g. multipleOf, propertyNames, $ref, allOf/anyOf/oneOf/not, contains) are
;; routed through the SAME ignore-with-warning policy: skipped + recorded once.
;; No keyword is ever silently honored-as-support.
;;
;; PURE ANNOTATIONS — $schema, $id, title, description, default, examples — are
;; ignored harmlessly and WITHOUT a warning (they carry no validation
;; semantics, appear in TS fixtures, and must neither fail nor suppress a
;; failure).
;;
;; ---------------------------------------------------------------------------
;; ERROR POLICY — COLLECT-ALL
;; ---------------------------------------------------------------------------
;; When a value violates MULTIPLE keywords / multiple properties / multiple
;; array elements, ALL independent failures are collected into the
;; `validation-errors` list — no short-circuit across siblings. (A single
;; scalar leaf MAY stop at the first keyword.) Every failing array element
;; contributes its own error; an ignored keyword contributes ZERO errors.
;; Errors carry located paths: `properties` prepends the string key, `items`
;; prepends the integer index, so a nested failure carries e.g.
;; '("data" "items" 0 "name"). `'()` = root.
;;
;; ---------------------------------------------------------------------------
;; OBJECT-KEY REPRESENTATION — the symbol/string boundary
;; ---------------------------------------------------------------------------
;; Racket's `json` reader parses JSON object keys as SYMBOLS
;; ({"name":…} -> (hasheq 'name …)). A schema's `required` array members and
;; `properties` keys, however, are STRINGS in the JSON text but become SYMBOLS
;; once the schema itself is a parsed jsexpr. So:
;;   - `required` entries are STRINGS; presence is checked via
;;     (hash-has-key? value (string->symbol req)). A naive string lookup would
;;     make EVERY object fail `required` (a silent total-failure bug).
;;   - `properties` is itself a parsed-jsexpr hasheq with SYMBOL keys, matched
;;     symbol-to-symbol against the value's symbol keys.
;;   - recorded WARNINGS are SYMBOLS (schema keys arrive as symbols).
;; The contract assumes both schema and value are parsed jsexprs (symbol keys);
;; a caller passing a string-keyed hash is out of contract.
;;
;; ---------------------------------------------------------------------------
;; FORMAT-RECOGNIZER CHOICES + ONE DOCUMENTED LIMITATION EACH
;; ---------------------------------------------------------------------------
;;   email     : pragmatic local@domain — exactly one '@', non-empty local
;;               part, domain containing a '.', no whitespace. REJECTS "a@",
;;               "@b.com", "a b@c.com", "a@b" (no dot in domain).
;;               LIMITATION: not full RFC 5322 — quoted local parts, comments,
;;               and IP-literal domains are NOT handled.
;;   uri       : pragmatic scheme presence — a leading "scheme:" where scheme
;;               starts with a letter then [A-Za-z0-9+.-]*. REJECTS
;;               "example.com" (scheme-less) and "://example.com" (empty
;;               scheme); ACCEPTS "mailto:x@y.com", "urn:isbn:123".
;;               LIMITATION: scheme-presence + shape only, NOT full RFC 3986
;;               (no host / path / authority validation). Implemented with a
;;               string/regex recognizer — `net/url` is BANNED by portability.
;;   date-time : ISO-8601 SHAPE check — YYYY-MM-DDThh:mm:ss with optional
;;               fractional seconds and a Z / +hh:mm / -hh:mm offset.
;;               LIMITATION: shape-only — it does NOT range-check fields, so
;;               "2025-13-01T00:00:00Z" (month 13) is ACCEPTED; "not-a-date"
;;               is rejected.
;;
;; ---------------------------------------------------------------------------
;; IMPORTS — S1 + the item-010 port ONLY
;; ---------------------------------------------------------------------------
;; Requires `../main.rkt` (S1 barrel: types M1 + errors M2 — for the error
;; constructors used by fail-fast compile) and `provider.rkt` (item-010 port).
;; `json` for (json-null). NO transport/engine/role/subprocess/socket module;
;; the uri recognizer is string/regex-based (NOT `net/url`). Restricted-load
;; portability stays clean — proven by the load test in
;; test/from-json-schema-test.rkt.

(require racket/generic
         racket/list
         racket/string
         json
         "../main.rkt"          ; S1 barrel (types + errors) -> make-protocol-error
         "provider.rkt")        ; item-010 port: gen:, provider-compile, validate, results

(provide make-racket-native-provider
         racket-native-provider?
         provider-warnings-for)

;; ===========================================================================
;; Keyword classification
;; ===========================================================================

;; The six supported keyword families (fully evaluated).
(define supported-keywords
  '(type properties required enum items format))

;; Deliberately deferred — ignore-with-warning (recorded once at compile).
(define deferred-keywords
  '(pattern minLength maxLength minimum maximum additionalProperties uniqueItems))

;; Pure annotations — ignored WITHOUT a warning (no validation semantics).
(define annotation-keywords
  '($schema $id title description default examples))

;; The three supported string formats.
(define supported-formats '("date-time" "uri" "email"))

;; ===========================================================================
;; Format recognizers (string/regex only — NO net/url). See module docs for
;; the one documented limitation per recognizer.
;; ===========================================================================

;; email — exactly one '@', non-empty local part with no whitespace, domain
;; containing a '.' with no whitespace. NOT full RFC 5322.
(define rx-email #rx"^[^@ \t\r\n]+@[^@ \t\r\n.]+(\\.[^@ \t\r\n.]+)+$")
(define (email? s) (regexp-match? rx-email s))

;; uri — a leading "scheme:" where scheme = letter then [A-Za-z0-9+.-]*. Scheme
;; presence + shape only, NOT full RFC 3986.
(define rx-uri #rx"^[A-Za-z][A-Za-z0-9+.-]*:")
(define (uri? s) (regexp-match? rx-uri s))

;; date-time — ISO-8601 SHAPE: YYYY-MM-DDThh:mm:ss, optional .fraction, then
;; Z or +hh:mm / -hh:mm. SHAPE only — no field range checks (month 13 accepts).
(define rx-date-time
  #px"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$")
(define (date-time? s) (regexp-match? rx-date-time s))

(define (format-recognizer fmt)
  (cond [(equal? fmt "email") email?]
        [(equal? fmt "uri") uri?]
        [(equal? fmt "date-time") date-time?]
        [else #f]))

;; ===========================================================================
;; Type recognizers. A JSON integer is an EXACT integer (42.0 is NOT an
;; integer); a JSON number is a FINITE rational (+nan.0 / +inf.0 are rejected —
;; a JSON number cannot be NaN/Inf even though (number? +nan.0) is #t).
;; ===========================================================================

(define (json-number? v)
  (and (real? v) (rational? v)))   ; rational? is #f for +nan.0/+inf.0/-inf.0

(define (json-integer? v)
  (exact-integer? v))

(define (type-recognizer t)
  (cond [(equal? t "string")  string?]
        [(equal? t "number")  json-number?]
        [(equal? t "integer") json-integer?]
        [(equal? t "boolean") boolean?]
        [(equal? t "object")  hash?]
        [(equal? t "array")   list?]
        [(equal? t "null")    (lambda (v) (eq? v (json-null)))]
        [else #f]))

(define (type-label t)
  (cond [(equal? t "string")  "string"]
        [(equal? t "number")  "number"]
        [(equal? t "integer") "integer"]
        [(equal? t "boolean") "boolean"]
        [(equal? t "object")  "object"]
        [(equal? t "array")   "array"]
        [(equal? t "null")    "null"]
        [else (format "~a" t)]))

;; ===========================================================================
;; Compile-time schema-shape check (fail-fast) + ignored-keyword collection.
;;
;; Two DISTINCT policies, both pinned:
;;   - structurally MALFORMED shape -> RAISE (via make-protocol-error), incl.
;;     recursion into sub-schemas (a bad nested `type` raises at compile).
;;   - deferred / unknown-format / unknown keyword -> RECORD (ignore-with-
;;     warning); collected here and returned for the per-handle record.
;; S-c (malformed deferred-keyword VALUE, e.g. minLength:"three") is treated as
;; IGNORE-WITH-WARNING: the deferred keyword is skipped regardless of its value,
;; so a malformed value is recorded like any other deferral (we never evaluate
;; the value, so its shape is immaterial). Documented in Decisions.
;; ===========================================================================

(define INVALID-SCHEMA -32602) ; JSON-RPC Invalid params — reused for bad schema shape

(define (schema-error fmt . args)
  (raise (make-protocol-error INVALID-SCHEMA (apply format fmt args))))

;; check-schema-shape : schema -> (listof symbol?)
;; Raises on a malformed schema; returns the list of ignored keyword symbols
;; (deferred + unknown-format + unknown keyword) collected across THIS schema
;; AND all its sub-schemas (so a deferred keyword in a nested sub-schema is
;; recorded too).
(define (check-schema-shape schema)
  (unless (hash? schema)
    (schema-error "schema must be a JSON object (hash); got: ~e" schema))
  (define ignored '())   ; accumulates symbols, de-duplicated at the end
  (define (record! sym) (set! ignored (cons sym ignored)))
  (let walk ([schema schema])
    (unless (hash? schema)
      (schema-error "sub-schema must be a JSON object (hash); got: ~e" schema))
    ;; type — must be a recognized type string when present.
    (define t (hash-ref schema 'type #f))
    (when (and t (not (type-recognizer t)))
      (schema-error "unrecognized `type`: ~e" t))
    ;; properties — must be a hash of sub-schemas; recurse into each.
    (define props (hash-ref schema 'properties #f))
    (when props
      (unless (hash? props)
        (schema-error "`properties` must be a JSON object; got: ~e" props))
      (for ([(k v) (in-hash props)]) (walk v)))
    ;; items — must be a sub-schema; recurse.
    (define its (hash-ref schema 'items #f))
    (when its (walk its))
    ;; required — must be a list (of strings).
    (define req (hash-ref schema 'required #f))
    (when req
      (unless (list? req)
        (schema-error "`required` must be an array; got: ~e" req)))
    ;; enum — must be a list.
    (define en (hash-ref schema 'enum #f))
    (when (and (hash-has-key? schema 'enum) (not (list? en)))
      (schema-error "`enum` must be an array; got: ~e" en))
    ;; format — record unknown formats (skipped + warned); known ones evaluate.
    (define fmt (hash-ref schema 'format #f))
    (when (and fmt (not (member fmt supported-formats)))
      ;; unknown format: record the format symbol (S-g chosen form).
      (record! (string->symbol fmt)))
    ;; deferred + unknown keywords -> record (ignore-with-warning).
    (for ([k (in-hash-keys schema)])
      (cond [(memq k supported-keywords) (void)]
            [(memq k annotation-keywords) (void)]   ; ignored WITHOUT warning
            [(eq? k 'format) (void)]                 ; handled above
            [(memq k deferred-keywords) (record! k)]
            [else (record! k)])))                    ; unknown -> same catch-all
  (remove-duplicates (reverse ignored)))

;; ===========================================================================
;; Recursive collect-all evaluator.
;; evaluate : schema value path -> (listof validation-error)   ('() = ok)
;; Each keyword family contributes its errors; ALL are appended (collect-all).
;; Each structural keyword type-guards the value first (no crash on wrong kind).
;; An ignored keyword contributes ZERO errors.
;; ===========================================================================

(define (err path msg) (validation-error path msg))

(define (evaluate schema value path)
  (define errors '())
  (define (add! e) (set! errors (cons e errors)))
  (define (add-all! es) (set! errors (append (reverse es) errors)))

  ;; --- type ---
  (define t (hash-ref schema 'type #f))
  (define type-pred (and t (type-recognizer t)))
  (define type-ok?
    (cond [(not t) #t]                       ; no `type` keyword -> no constraint
          [(type-pred value) #t]
          [else (add! (err path (format "expected ~a, got ~e" (type-label t) value)))
                #f]))

  ;; --- enum ---  (independent of type; collect-all)
  (when (hash-has-key? schema 'enum)
    (define members (hash-ref schema 'enum))
    (unless (memf (lambda (m) (equal? value m)) members)
      (add! (err path "value not in enum"))))

  ;; --- properties / required ---  (object structural keywords)
  ;; Self-guard on hash?. Only descend when value is a hash. When `type` is
  ;; present and already rejected the value's kind, skip descent (no point).
  (define props (hash-ref schema 'properties #f))
  (define req (hash-ref schema 'required #f))
  (when (or props req)
    (cond
      [(hash? value)
       ;; properties: validate each PRESENT property against its sub-schema.
       (when props
         (for ([(k subschema) (in-hash props)])
           (when (hash-has-key? value k)
             (add-all! (evaluate subschema (hash-ref value k)
                                  (append path (list (symbol->string k))))))))
       ;; required: each listed (string) key must be present (symbol bridge).
       (when req
         (for ([r (in-list req)])
           (unless (hash-has-key? value (string->symbol r))
             (add! (err path (format "missing required property: ~a" r))))))]
      [else
       ;; Non-hash value under an object structural keyword. If `type` already
       ;; reported a mismatch, do not double-report; else emit one clean error.
       (when type-ok?
         (add! (err path (format "expected object, got ~e" value))))]))

  ;; --- items ---  (array structural keyword)
  (define its (hash-ref schema 'items #f))
  (when its
    (cond
      [(list? value)
       (for ([elem (in-list value)] [i (in-naturals)])
         (add-all! (evaluate its elem (append path (list i)))))]
      [else
       (when type-ok?
         (add! (err path (format "expected array, got ~e" value))))]))

  ;; --- format ---  (string keyword; no-op on non-strings)
  (define fmt (hash-ref schema 'format #f))
  (when (and fmt (string? value) (member fmt supported-formats))
    (define rec (format-recognizer fmt))
    (unless (rec value)
      (add! (err path (format "invalid ~a format" fmt)))))
  ;; format on a non-string, or an unknown format, contributes ZERO errors
  ;; (unknown formats were recorded at compile, ignore-with-warning).

  (reverse errors))

;; ===========================================================================
;; The provider — implements the item-010 port. Carries a WEAK map
;; handle -> ignored-keyword-list (S-g), populated by provider-compile, read
;; via provider-warnings-for. Weak so a long-lived provider does NOT retain
;; every handle it ever compiled (item 012 compiles many schemas through one
;; provider). The compiled-validator is item-010's FROZEN single-field struct
;; (NOT widened) — warnings live HERE, keyed by handle, NOT on the handle.
;; ===========================================================================

(struct racket-native-provider (warnings)   ; warnings : weak-hasheq handle -> (listof symbol?)
  #:methods gen:json-schema-validator-provider
  [(define (provider-compile p schema)
     ;; Fail-fast on malformed shape; collect ignored keywords for this schema.
     (define ignored (check-schema-shape schema))
     ;; Optional human-facing side effect: warn ONCE here, at compile (NOT per
     ;; validate). Emitted via eprintf so a current-error-port capture is valid
     ;; (NOT log-warning). The RECORDED list below is the load-bearing oracle.
     (unless (null? ignored)
       (eprintf "racket-native-provider: ignoring unsupported keyword(s): ~a\n"
                (string-join (map symbol->string ignored) ", ")))
     ;; Build the closure-in-handle. It NEVER touches the ignore-list
     ;; (warn-once = compile-time; validate does not append — N2).
     (define handle
       (compiled-validator
        (lambda (v)
          (define es (evaluate schema v '()))
          (if (null? es) (validation-ok v) (validation-errors es)))))
     ;; Record handle -> ignored list in the provider's weak map (per-compile-
     ;; keyed; two handles from one provider stay distinct — N1).
     (hash-set! (racket-native-provider-warnings p) handle ignored)
     handle)])

;; make-racket-native-provider : -> racket-native-provider?
(define (make-racket-native-provider)
  (racket-native-provider (make-weak-hasheq)))

;; provider-warnings-for : provider handle -> (listof symbol?)
;; The handle's recorded ignored-keyword list (deferred + unknown-format +
;; unknown keywords), as SYMBOLS (S-g). '() when nothing was ignored.
(define (provider-warnings-for provider handle)
  (hash-ref (racket-native-provider-warnings provider) handle '()))
