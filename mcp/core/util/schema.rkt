#lang racket/base

;; Work Item 012 — the schema-normalization util (M4): contract-or-JSON-Schema.
;;
;; The Racket-native Standard-Schema ANALOGUE. Given a tool/prompt argument
;; schema in EITHER of two native Racket forms — a `racket/contract` flat
;; contract (Form B) OR a parsed JSON Schema (an immutable symbol-keyed
;; `hasheq`, Form A) — it produces ONE uniform `normalized-schema` carrying:
;;   1. a WIRE JSON Schema (jsexpr hasheq, root type:"object") for advertisement
;;      in `tools/list` / prompt-argument lists; and
;;   2. a VALIDATION HANDLE — an item-010 `compiled-validator?` produced by
;;      compiling the wire schema through the M3 provider (default item 011's
;;      `make-racket-native-provider`) — that validates incoming arguments.
;;
;; ---------------------------------------------------------------------------
;; FRAMING — ported role vs net-new input forms
;; ---------------------------------------------------------------------------
;; TS `util/standardSchema.ts` bridges Standard-Schema library objects
;; (Zod/Valibot/ArkType) to (wire JSON Schema + validate-fn). Vision §8 EXCLUDES
;; that ecosystem, so the INPUT FORMS here are net-new (a `racket/contract` flat
;; contract OR a parsed JSON Schema). The OUTPUT PAIR and the `type:"object"`-
;; at-root invariant are ported faithfully:
;;   - `standardSchemaToJsonSchema` -> `normalized-schema-wire` (root type:object)
;;   - `validateStandardSchema`      -> the validation handle (delegates to M3)
;;   - `promptArgumentsFromStandardSchema` -> `normalized-schema-prompt-arguments`
;;
;; ---------------------------------------------------------------------------
;; SINGLE DELEGATION PATH (committed design directive)
;; ---------------------------------------------------------------------------
;; BOTH input forms produce the handle by compiling a WIRE JSON SCHEMA through
;; the M3 provider. Form B does NOT validate by applying the raw `racket/contract`
;; at validate time — the contract is used ONLY to DERIVE the wire schema (a
;; compile-time mapping). Rationale: (1) the dual-form guarantee (a contract
;; input and an equivalent JSON-Schema input accept/reject the SAME values) is
;; true-by-construction when both compile to a JSON Schema validated by the same
;; provider; (2) one portable, provider-swappable validate path; (3) no second,
;; divergent validation semantics.
;;
;; ---------------------------------------------------------------------------
;; CONTRACT -> JSON-SCHEMA MAPPING (Form B) — supported FLAT subset + limits
;; ---------------------------------------------------------------------------
;;   string?                        -> {type:"string"}
;;   exact-integer?                 -> {type:"integer"}   (NOT integer? — see S5)
;;   real? / rational? / number?    -> {type:"number"}
;;   boolean?                       -> {type:"boolean"}
;;   (listof <flat-or-descriptor>)  -> {type:"array", items:<map(elem)>}
;;   (or/c <lit> <lit> ...)         -> {enum:[<lit> ...]}  (ALL arms literal)
;;   an object-schema/c descriptor  -> {type:"object", properties:…, required:…}
;; REJECTED (clear S1 error naming the field): `and/c` (its non-type conjuncts
;; are item-011 DEFERRED keywords — mapping the type and dropping the constraint
;; would advertise a contract NARROWER than written); mixed/all-predicate `or/c`
;; (`(or/c "a" string?)`, `(or/c string? number?)` — no clean enum); `integer?`
;; (S5: item 011's json-integer is exact-integer?, so `5.0` would be advertised
;; valid yet the derived handle rejects it — self-inconsistency); higher-order /
;; dependent / struct / parametric / opaque-predicate contracts (`->`, `->i`,
;; `struct/c`, `even?`) — NO JSON-Schema equivalent in the M3 subset. NO `format`
;; is ever produced from a contract (a format constraint is supplied as a Form-A
;; JSON Schema instead).
;;
;; Recognition is by IDENTITY/structure: descriptors via `object-schema/c?`;
;; flat scalar predicates + `or/c`/`listof` arms via `contract-name` (a STRUCT
;; datum, not a string-parse) — a compiled `or/c` exposes no public arm API, so
;; the literal/predicate classification reads its `contract-name` datum. A
;; nested `object-schema/c` is a flat contract whose `contract-name` is the
;; descriptor struct itself, so `(listof <descriptor>)` recovers the descriptor.
;;
;; ---------------------------------------------------------------------------
;; ROOT type:"object" INVARIANT — DELIBERATELY FORM-DEPENDENT
;; ---------------------------------------------------------------------------
;;   Form A object root      -> ensured/unchanged -> accept
;;   Form A typeless root    -> ADD type:"object" -> accept   (TS {oneOf} parity)
;;   Form A non-object root  -> REJECT                        (TS throw parity)
;;   Form B object descriptor-> accept (always object)
;;   Form B bare contract    -> REJECT (scalar/array/enum root is non-object;
;;                              a contract author choosing a non-object root
;;                              asked for it explicitly — NOT auto-wrapped,
;;                              unlike a typeless Form-A which is the Zod quirk
;;                              the add-rule exists to paper over).
;;
;; ---------------------------------------------------------------------------
;; FORM DETECTION (silent-total-failure guard)
;; ---------------------------------------------------------------------------
;; Form A iff (and (hash? x) (immutable? x) (hash-eq? x)) — what `read-json` /
;; `string->jsexpr` produce (symbol keys). A string-keyed / `equal?`-keyed /
;; mutable hash is OUT OF CONTRACT -> rejected: routed into item 011's
;; symbol-keyed provider it would mis-validate every `required`/`properties`
;; lookup (the silent-total-failure bug item 011 warns of). The Form-B object
;; descriptor is a distinct struct, so a hasheq is never ambiguous.
;;
;; ---------------------------------------------------------------------------
;; DEFERRED KEYWORDS (Form A) pass through UNTOUCHED
;; ---------------------------------------------------------------------------
;; A hand-written JSON Schema carrying an item-011 DEFERRED keyword
;; (minLength/pattern/minimum/…) is NOT stripped/rewritten/rejected: the wire
;; schema retains the keyword verbatim (advertised as-is, enforceable by a future
;; vetted-library provider) and the handle's accept/reject is exactly item 011's
;; (ignore-with-warning, recorded in `provider-warnings-for`).
;;
;; ---------------------------------------------------------------------------
;; IMPORTS — S1 + M3 ONLY (no transport/engine/role/subprocess/socket; NO net/url)
;; ---------------------------------------------------------------------------
;; Tests live in test/schema-test.rkt — NO (module+ test …) here, so the
;; restricted-load portability walk is a faithful proof of this module's own
;; import graph.

(require racket/contract            ; introspect flat contracts (contract-name) + flat-contract property
         racket/list                ; remove-duplicates
         "../main.rkt"              ; S1 barrel (types M1 + errors M2) -> make-protocol-error
         "../validators/provider.rkt"          ; M3 port: provider-compile, validate, compiled-validator?
         "../validators/from-json-schema.rkt") ; M3 default provider: make-racket-native-provider

(provide normalize-schema
         normalized-schema?
         normalized-schema-wire
         normalized-schema-handle
         normalized-schema-validate
         normalized-schema-prompt-arguments
         object-schema/c
         object-schema/c?)

;; JSON-RPC Invalid params — reused for un-mappable contracts / bad root schema.
(define INVALID-PARAMS -32602)

(define (reject fmt . args)
  (raise (make-protocol-error INVALID-PARAMS (apply format fmt args))))

;; ===========================================================================
;; Form-B object-descriptor surface.
;; A struct that IS a flat contract (so it nests inside `listof`) whose
;; contract-name is the struct itself (so a `(listof <descriptor>)` recovers the
;; descriptor for recursion). `object-schema/c?` is the form-detection predicate.
;;   fields   : hash of field-symbol -> flat-contract (or nested descriptor)
;;   required : (listof symbol?) — subset of (hash-keys fields), validated at ctor
;; ===========================================================================
(struct object-descriptor (fields required)
  #:property prop:flat-contract
  (build-flat-contract-property
   #:name (lambda (self) self)
   #:first-order (lambda (self) hash?)))

(define (object-schema/c? x) (object-descriptor? x))

;; (object-schema/c field-hash #:required req-list)
;; Raises at CONSTRUCTION if #:required names a field absent from field-hash
;; (a required-but-undeclared field is a programmer error caught earliest).
(define (object-schema/c field-hash #:required [required '()])
  (unless (hash? field-hash)
    (reject "object-schema/c: field hash must be a hash; got ~e" field-hash))
  (for ([r (in-list required)])
    (unless (hash-has-key? field-hash r)
      (reject "object-schema/c: required field ~a is not declared in the field hash" r)))
  (object-descriptor field-hash required))

;; ===========================================================================
;; The normalized result. Curated accessors only; the constructor is NOT
;; provided (callers build via `normalize-schema`).
;; ===========================================================================
(struct normalized-schema (wire handle) #:transparent)

;; ===========================================================================
;; Form B — contract -> wire JSON-Schema fragment.
;; ===========================================================================

;; In an `or/c` contract-name datum, a LITERAL arm is a self-quoting datum
;; (string/number/boolean) or a QUOTED symbol — `(or/c "a" (json-null))` renders
;; the null member (the symbol 'null) as `(quote null)`, distinct from a bare
;; (unquoted) symbol like `string?` which denotes a PREDICATE reference. So
;; literal-symbol enum members (e.g. (json-null)) are recovered by unwrapping the
;; quote; a bare symbol arm means a predicate -> not a clean enum -> reject.
;; arm->literal : datum -> (values literal? value)
(define (arm->literal a)
  (cond
    [(or (string? a) (number? a) (boolean? a)) (values #t a)]
    [(and (pair? a) (eq? (car a) 'quote) (pair? (cdr a))) (values #t (cadr a))]
    [else (values #f #f)]))

;; scalar->fragment : the supported flat scalar predicates, by contract-name.
(define (scalar->fragment sym field)
  (case sym
    [(string?)        (hasheq 'type "string")]
    [(exact-integer?) (hasheq 'type "integer")]
    [(real? rational? number?) (hasheq 'type "number")]
    [(boolean?)       (hasheq 'type "boolean")]
    [else (reject "field ~a: contract ~a has no JSON-Schema equivalent in the supported subset"
                  field sym)]))

;; spec->fragment : map a contract-name DATUM (or a descriptor struct, for
;; `listof` element recursion) to a wire fragment.
(define (spec->fragment spec field)
  (cond
    [(object-schema/c? spec) (descriptor->wire spec)]
    [(symbol? spec) (scalar->fragment spec field)]
    [(or (string? spec) (number? spec) (boolean? spec))
     ;; a bare literal datum / collapsed single-arm (or/c "a") -> enum
     (hasheq 'enum (list spec))]
    [(and (pair? spec) (eq? (car spec) 'quote) (pair? (cdr spec)))
     ;; a collapsed single quoted-symbol literal, e.g. (or/c (json-null)) -> enum
     (hasheq 'enum (list (cadr spec)))]
    [(and (pair? spec) (eq? (car spec) 'listof))
     (hasheq 'type "array" 'items (spec->fragment (cadr spec) field))]
    [(and (pair? spec) (eq? (car spec) 'or/c))
     (define members
       (for/list ([a (in-list (cdr spec))])
         (define-values (lit? v) (arm->literal a))
         (unless lit?
           (reject "field ~a: or/c with a non-literal arm (~a) is not a clean enum" field a))
         v))
     (hasheq 'enum (remove-duplicates members))]
    [(and (pair? spec) (eq? (car spec) 'and/c))
     (reject "field ~a: and/c has no clean single-fragment JSON-Schema equivalent (supply a JSON Schema instead)"
             field)]
    [else
     (reject "field ~a: contract ~a has no JSON-Schema equivalent in the supported subset"
             field spec)]))

;; contract->fragment : map a field's contract value to a wire fragment.
(define (contract->fragment c field)
  (cond
    [(object-schema/c? c) (descriptor->wire c)]
    [(flat-contract? c) (spec->fragment (contract-name c) field)]
    [(contract? c)
     (reject "field ~a: higher-order/dependent contract has no JSON-Schema equivalent" field)]
    [else
     (reject "field ~a: value ~e is not a contract" field c)]))

;; descriptor->wire : an object descriptor -> {type:"object", properties, required}.
;; properties keys are SYMBOLS; required members are STRINGS (item-011 boundary).
(define (descriptor->wire d)
  (define fields (object-descriptor-fields d))
  (define required (object-descriptor-required d))
  (define props
    (for/hasheq ([(k c) (in-hash fields)])
      (values k (contract->fragment c k))))
  (hasheq 'type "object"
          'properties props
          'required (map symbol->string required)))

;; ===========================================================================
;; Form A — JSON Schema -> wire JSON Schema (root type:"object" invariant).
;; ===========================================================================
(define (json-schema->wire schema)
  (define t (hash-ref schema 'type #f))
  (cond
    [(not t) (hash-set schema 'type "object")]      ; typeless -> add (TS parity)
    [(equal? t "object") schema]                    ; object root -> unchanged
    [else (reject "root schema type must be \"object\"; got ~s" t)]))

;; ===========================================================================
;; normalize-schema — the entry point.
;; ===========================================================================
(define (normalize-schema input #:provider [provider (make-racket-native-provider)])
  (define wire
    (cond
      [(and (hash? input) (immutable? input) (hash-eq? input))
       (json-schema->wire input)]                   ; Form A
      [(object-schema/c? input)
       (descriptor->wire input)]                    ; Form B descriptor
      [(contract? input)
       ;; Form B bare contract at root -> non-object root -> reject.
       (reject "root tool/prompt schema must be an object; a bare contract maps to a non-object root — wrap fields in object-schema/c")]
      [else
       (reject "normalize-schema: input must be a JSON-Schema hasheq (symbol keys), an object-schema/c descriptor, or a flat contract; got ~e" input)]))
  (normalized-schema wire (provider-compile provider wire)))

;; ===========================================================================
;; Sugar + helpers.
;; ===========================================================================

;; (normalized-schema-validate ns v) = (validate (normalized-schema-handle ns) v)
(define (normalized-schema-validate ns v)
  (validate (normalized-schema-handle ns) v))

;; normalized-schema-prompt-arguments : entries {name, [description], required}
;; per top-level wire property (mirrors TS promptArgumentsFromStandardSchema).
(define (normalized-schema-prompt-arguments ns)
  (define wire (normalized-schema-wire ns))
  (define props (hash-ref wire 'properties (hasheq)))
  (define required
    (for/list ([r (in-list (hash-ref wire 'required '()))])
      (if (string? r) (string->symbol r) r)))
  (for/list ([(k v) (in-hash props)])
    (define base (hasheq 'name (symbol->string k)
                         'required (and (memq k required) #t)))
    (if (and (hash? v) (hash-has-key? v 'description))
        (hash-set base 'description (hash-ref v 'description))
        base)))
