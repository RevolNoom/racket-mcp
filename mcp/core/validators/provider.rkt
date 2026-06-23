#lang racket/base

;; Work Item 010 — the pluggable JSON-Schema validator-provider PORT (M3).
;;
;; This is the dependency-inversion seam (architecture M3, §4.1): the default
;; Racket-native provider (item 011) and any future vetted-library provider
;; implement `gen:json-schema-validator-provider` so callers (the schema util
;; item 012, the high-level server in S6b) can swap providers WITHOUT change.
;;
;; Ported from MCP TypeScript SDK v2 `packages/core/src/validators/types.ts`,
;; whose `jsonSchemaValidator` is a SINGLE fused method
;;   getValidator<T>(schema) -> (input) => { valid, data, errorMessage }
;; This Racket port DELIBERATELY SPLITS that fused method into two explicit
;; operations (Decisions (a)): `provider-compile` (provider + schema -> opaque
;; handle, compile once) and `validate` (handle + value -> result, validate
;; many). The result is a SUPERSET of the TS shape (Decisions (b)): a list of
;; structured `validation-error`s, each with a JSON-Pointer-ish `path`, rather
;; than one flat `errorMessage` string.
;;
;; SCOPE: port + result types + the (closure-in-handle) compiled handle ONLY.
;; NO JSON-Schema keyword evaluation (item 011), NO schema normalization
;; (item 012), NO TS Ajv-baseline parity. The only concrete validator is a
;; trivial stub in the test file.
;;
;; IMPORTS: S1 only. `racket/generic` for the port; the S1 barrel
;; (`../main.rkt` = types M1 + errors M2) for dependency-story uniformity with
;; the rest of L0 (Decisions (f)). The port body is purely structural so it
;; references no specific S1 binding, but the barrel require keeps the
;; validator collection's dependency graph identical to its siblings and gives
;; item 011 the error constructors without widening this require list. NO
;; transport/engine/role/subprocess/socket module is reachable — proven by the
;; restricted-namespace load test in test/provider-test.rkt.

(require racket/generic
         "../main.rkt") ; S1 barrel (types + errors); see Decisions (f)

;; ---------------------------------------------------------------------------
;; Result type — a CLOSED two-variant set under `validation-result?`.
;; Defined in dependency order: `validation-error` BEFORE `validation-errors`,
;; because the latter's #:guard references `validation-error?` (Decisions (b)).
;; ---------------------------------------------------------------------------

;; ok variant — carries the validated value (<-> TS `data`).
(struct validation-ok (value) #:transparent)

;; one structured error — path + message (the deliberate Racket enrichment).
;;   path    : (listof (or/c string? exact-nonnegative-integer?))
;;             JSON-Pointer-ish segments; '() = root; mixed string/int allowed
;;             (e.g. '("items" 0 "name")).
;;   message : string?
(struct validation-error (path message) #:transparent)

;; error variant — carries a NON-EMPTY list of `validation-error`.
;; The #:guard ENFORCES non-emptiness + element type, so `(validation-errors
;; '())` RAISES rather than silently constructing a malformed result. This
;; makes the "non-empty errors" acceptance criterion falsifiable (Decisions
;; (b)), not advisory.
(struct validation-errors (errors)
  #:transparent
  #:guard (lambda (errors _type-name)
            (unless (and (pair? errors) (andmap validation-error? errors))
              (error 'validation-errors
                     "errors must be a non-empty list of validation-error; got: ~e" errors))
            errors))

;; The closed umbrella predicate. `validation-ok?` and `validation-errors?`
;; are mutually exclusive (distinct structs) and exhaustive over results.
(define (validation-result? v)
  (or (validation-ok? v) (validation-errors? v)))

;; ---------------------------------------------------------------------------
;; Compiled handle (closure-in-handle encoding, Decisions (a)).
;; The handle IS the validate closure, wrapped in a struct for opacity and a
;; stable `compiled-validator?` predicate. The validate-proc field is NOT
;; provided — only the constructor + predicate are (opacity, Decisions (a)).
;; ---------------------------------------------------------------------------
(struct compiled-validator (validate-proc) #:transparent)

;; validate : compiled-validator? jsexpr -> validation-result?
;; Total over ANY `compiled-validator?` regardless of originating provider —
;; it just applies the carried closure (cross-provider totality, Decisions
;; (e)). Does NOT police input type: assumes a jsexpr; non-jsexpr input is the
;; provider's / contract layer's concern (Decisions (e)).
(define (validate handle value)
  ((compiled-validator-validate-proc handle) value))

;; ---------------------------------------------------------------------------
;; The port — `racket/generic` (Decisions (c)). `provider-compile` is the
;; provider's polymorphic job (interpret the schema -> compiled handle).
;; `validate` (above) operates on the produced handle and does NOT re-dispatch.
;; ---------------------------------------------------------------------------
(define-generics json-schema-validator-provider
  ;; provider + JSON Schema (a jsexpr) -> opaque compiled-validator handle.
  (provider-compile json-schema-validator-provider schema))

;; ---------------------------------------------------------------------------
;; Public surface — EXPLICIT + curated (NO all-defined-out). Exactly the
;; Description §3 surface. The compiled handle's validate-proc accessor is
;; intentionally absent (opacity).
;; ---------------------------------------------------------------------------
(provide ;; the port
         gen:json-schema-validator-provider
         json-schema-validator-provider?
         provider-compile
         ;; validate entry point
         validate
         ;; compiled handle: constructor + predicate ONLY (field stays opaque)
         compiled-validator
         compiled-validator?
         ;; result API
         validation-result?
         validation-ok validation-ok? validation-ok-value
         validation-errors validation-errors? validation-errors-errors
         validation-error validation-error? validation-error-path validation-error-message)
