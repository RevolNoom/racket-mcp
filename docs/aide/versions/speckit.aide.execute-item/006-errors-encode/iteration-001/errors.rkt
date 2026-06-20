#lang racket/base

;; M2 Errors module — the exn hierarchy + the single exn<->JSON-RPC error
;; conversion point (architecture §4.1, the error-to-wire boundary).
;;
;; THIS FILE IS BUILT IN TWO HALVES:
;;   - Item 006 (this delivery) builds the ENCODE half: the `exn:fail:mcp` /
;;     `:protocol` / `:auth` struct subtypes (stable codes + constructors +
;;     predicates + accessors) and `exn->jsonrpc-error` (exn -> a JSON-RPC
;;     `{code,message,data?}` error object; any non-mcp exn -> InternalError
;;     -32603, so a handler failure never crashes the engine).
;;   - Item 007 will add the DECODE half (`jsonrpc-error->exn` + the typed
;;     `-32042`/`-32004` decoders, mirroring `ProtocolError.fromError`) into
;;     THIS SAME file, at the "DECODE (item 007)" anchor near the bottom. 007
;;     needs NO new struct — it builds decoded errors with `make-protocol-error`
;;     / `make-auth-error`. 007 APPENDS to the `provide` block; it does not edit
;;     006's exports. Until 007 lands, the roadmap S1 `errors.rkt` deliverable
;;     stays at 🚧 (encode half only).
;;
;; Parity (authoritative reference: typescript-sdk/):
;;   - `packages/core/src/types/errors.ts` is a FLAT hierarchy: one
;;     `ProtocolError` (code/message/data?) plus two data-specialized subclasses
;;     (`UrlElicitationRequiredError` -32042, `UnsupportedProtocolVersionError`
;;     -32004). The Racket hierarchy is intentionally RICHER: it splits the
;;     single TS wire-error class into `exn:fail:mcp:protocol` (the wire/JSON-RPC
;;     role) and `exn:fail:mcp:auth` (the `core/auth/errors.ts` role, a separate
;;     TS module), both under `exn:fail:mcp` (vision §4.8). The two TS
;;     data-subclasses are NOT separate Racket structs — they are
;;     `exn:fail:mcp:protocol` instances carrying the right code + data, built by
;;     item 007's decode helpers.
;;   - The error codes come from `enums.ts:5-25` (ProtocolErrorCode), modeled in
;;     `types/constants.rkt` (item 001) — re-literaled here NOWHERE.
;;
;; Portability NFR (roadmap line 96): requires only racket/base + racket/contract
;; + types/constants.rkt + types/spec-2025-11-25.rkt — no subprocess/socket, no
;; I/O at module load. (The spec module is itself portable; see Decisions in the
;; item spec for why importing it for the `jsonrpc-error` shape keeps the NFR.)

(require racket/contract
         ;; codes only (zero re-literaled numbers — anti-magic, item 006 AC)
         (only-in "types/constants.rkt"
                  INTERNAL-ERROR
                  PARSE-ERROR
                  INVALID-REQUEST
                  METHOD-NOT-FOUND
                  INVALID-PARAMS
                  RESOURCE-NOT-FOUND
                  MISSING-REQUIRED-CLIENT-CAPABILITY
                  UNSUPPORTED-PROTOCOL-VERSION
                  URL-ELICITATION-REQUIRED)
         ;; The ONE `jsonrpc-error` type + its serializer + the SHARED `absent`
         ;; sentinel (so absent `data` is OMITTED on the wire, never "data":null)
         ;; + the `jsexpr-value?` predicate used by `jsonrpc-error/c`. Reusing
         ;; these (Decisions option (a)) means one struct, one serializer, and
         ;; item 007 consumes the same struct symmetrically.
         (only-in "types/spec-2025-11-25.rkt"
                  jsonrpc-error
                  jsonrpc-error?
                  jsonrpc-error->json
                  jsexpr-value?
                  absent
                  absent?))

;; ---------------------------------------------------------------------------
;; Curated provide surface (NO all-defined-out). Item 007 APPENDS to this block
;; (decode bindings) — it does not edit these exports.
;; ---------------------------------------------------------------------------
(provide
 ;; --- exn hierarchy (struct-out: constructor + predicate + accessors) ---
 (struct-out exn:fail:mcp)
 (struct-out exn:fail:mcp:protocol)
 (struct-out exn:fail:mcp:auth)
 ;; --- friendly predicates ---
 mcp-error?
 protocol-error?
 auth-error?
 ;; --- friendly accessors (the base fields, inherited by all subtypes) ---
 mcp-error-code
 mcp-error-data)

(provide
 (contract-out
  ;; --- friendly constructors (hide the super-field order; validate args) ---
  [make-mcp-error      (->* (exact-integer? string?)
                            (mcp-data/c #:marks continuation-mark-set?)
                            exn:fail:mcp?)]
  [make-protocol-error (->* (exact-integer? string?)
                            (mcp-data/c)
                            exn:fail:mcp:protocol?)]
  [make-auth-error     (->* (exact-integer? string?)
                            (mcp-data/c)
                            exn:fail:mcp:auth?)]
  ;; --- the ENCODE function (canonical: returns the typed struct) ---
  [exn->jsonrpc-error        (-> exn? jsonrpc-error?)]
  ;; --- convenience wire wrapper (= jsonrpc-error->json of the above) ---
  [exn->jsonrpc-error-jsexpr (-> exn? hash?)]))

;; ---------------------------------------------------------------------------
;; The exception hierarchy.
;;
;; `exn:fail` already supplies `message` (string) + `continuation-marks`; the
;; base subtype adds ONLY `code` + `data`, so the RAW constructor sees
;;   (exn:fail:mcp message continuation-marks code data).
;; The friendly `make-*` constructors below hide that ordering. The two
;; subtypes add no new fields in S1 (auth's OAuth-specific fields are an S6/S7
;; concern, added additively later) — they exist to make protocol vs auth
;; errors DISCRIMINABLE now without a later restructure.
;; ---------------------------------------------------------------------------
(struct exn:fail:mcp exn:fail (code data) #:transparent)
(struct exn:fail:mcp:protocol exn:fail:mcp () #:transparent)
(struct exn:fail:mcp:auth exn:fail:mcp () #:transparent)

;; Friendly predicates / accessors (re-named auto-generated struct bindings).
(define mcp-error?      exn:fail:mcp?)
(define protocol-error? exn:fail:mcp:protocol?)
(define auth-error?     exn:fail:mcp:auth?)
(define mcp-error-code  exn:fail:mcp-code)
(define mcp-error-data  exn:fail:mcp-data)

;; The `data` contract: a jsexpr value OR the `absent` sentinel (no data). A
;; present falsy jsexpr — #f, 'null, 0, "" — is carried verbatim; only `absent`
;; is omitted on encode.
(define mcp-data/c (or/c absent? jsexpr-value?))

;; ---------------------------------------------------------------------------
;; Friendly constructors.
;;
;; Signature: (make-… code message [data absent] [#:marks marks]). `marks`
;; defaults to (current-continuation-marks) so a constructed error has a usable
;; stack (catchable by ordinary exn:fail? handlers, displayable by
;; error-display-handler) without the caller threading marks.
;; ---------------------------------------------------------------------------
(define (make-mcp-error code message [data absent]
                        #:marks [marks (current-continuation-marks)])
  (exn:fail:mcp message marks code data))

(define (make-protocol-error code message [data absent]
                             #:marks [marks (current-continuation-marks)])
  (exn:fail:mcp:protocol message marks code data))

(define (make-auth-error code message [data absent]
                         #:marks [marks (current-continuation-marks)])
  (exn:fail:mcp:auth message marks code data))

;; ---------------------------------------------------------------------------
;; ENCODE: exn -> jsonrpc-error struct.
;;
;; A single `cond`:
;;   - an mcp error (base OR any subtype, since the subtypes are sub-structs)
;;     copies its OWN code/message/data through — `data` is copied by reference
;;     (absent stays absent and the serializer omits it; a present payload,
;;     including a falsy 'null/#f/0/"", survives verbatim).
;;   - any other exn -> the InternalError (-32603) FALLBACK with the exn's
;;     message and no data. This is the architecture §4.1 guarantee: a thrown
;;     handler error surfaces as a well-formed -32603 wire error, never an
;;     unhandled crash. `exn-message` is total over `exn?`, so the fallback's
;;     message is always a string. (NOTE on `exn:break`: the protocol boundary
;;     S3 is expected to let breaks PROPAGATE; this encoder does not swallow
;;     them — it only maps an exn:break to -32603 IF one is ever handed to it.)
;; ---------------------------------------------------------------------------
(define (exn->jsonrpc-error e)
  (cond
    [(mcp-error? e)
     (jsonrpc-error (mcp-error-code e) (exn-message e) (mcp-error-data e))]
    [else
     (jsonrpc-error INTERNAL-ERROR (exn-message e) absent)]))

;; Convenience: the wire jsexpr (symbol-keyed hasheq with 'code/'message and
;; 'data iff present). The wire bytes are produced by the ONE spec serializer.
(define (exn->jsonrpc-error-jsexpr e)
  (jsonrpc-error->json (exn->jsonrpc-error e)))

;; ===========================================================================
;; DECODE (item 007) — jsonrpc-error->exn + the typed decoders go HERE.
;;
;;   Item 007 adds `jsonrpc-error->exn : jsonrpc-error? -> exn:fail:mcp?` plus
;;   the typed helpers mirroring `ProtocolError.fromError` (errors.ts:21-39):
;;     -32042 (URL-ELICITATION-REQUIRED)   -> (make-protocol-error -32042 …
;;              (hasheq 'elicitations …))
;;     -32004 (UNSUPPORTED-PROTOCOL-VERSION)-> (make-protocol-error -32004 …
;;              (hasheq 'supported …))
;;     otherwise                            -> a generic (make-protocol-error …)
;;   No new struct is needed — the hierarchy + constructors above are
;;   sufficient. APPEND the new bindings to the second `provide` block above
;;   (decode functions) — do NOT edit 006's exports.
;; ===========================================================================
