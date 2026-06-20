#lang racket/base

;; JSON-RPC message-shape predicates, mirroring the MCP TypeScript SDK's
;; `core/src/types/guards.ts` JSON-RPC envelope guards (isJSONRPCRequest,
;; isJSONRPCNotification, isJSONRPCResultResponse, isJSONRPCErrorResponse,
;; isJSONRPCResponse). Each predicate classifies a parsed-but-untrusted
;; inbound JSON value (the `jsexpr` from `read-json`: a JSON object is an
;; immutable `hasheq` with SYMBOL keys; JSON null is the symbol 'null) into
;; request / notification / result-response / error-response.
;;
;; The TS guards delegate to `Schema.safeParse(value).success` (Zod); since
;; Racket has no Zod, these re-implement the same structural rules by hand.
;; The truth-table test (test/guards-test.rkt) keeps the two in parity.
;;
;; Strictness (Zod `.strict()`) is replicated at the ENVELOPE LEVEL ONLY: an
;; exact allowed-key-set check on the top-level message keys. It is NEVER
;; recursed into nested objects — the inner `error`, `result`, and `params`
;; objects are non-strict/loose in the reference SDK, so unknown keys inside
;; them are ALLOWED (Zod v4 strips them). Restricting nested keys would make
;; this guard stricter than the reference SDK and break wire parity (G1/G2).
;;
;; Per architecture J3, MCP removed JSON-RPC batching: there is NO batch
;; predicate here, and the test asserts its absence by module introspection.
;;
;; Requires only racket/base + the sibling constants.rkt (for JSONRPC-VERSION)
;; — no subprocess/socket (Portability NFR).

(require (only-in "constants.rkt" JSONRPC-VERSION))

(provide
 is-jsonrpc-request?
 is-jsonrpc-notification?
 is-jsonrpc-result-response?
 is-jsonrpc-error?
 is-jsonrpc-response?)

;; --- internal shape helpers (NOT provided) -------------------------------

;; A `read-json` object: an immutable, eq?-keyed (symbol-keyed) hash.
;; Mutable hashes and string-keyed hashes are NOT the read-json shape.
(define (json-object? v)
  (and (hash? v) (immutable? v) (hash-eq? v)))

;; jsonrpc field present and exactly the string "2.0".
(define (valid-jsonrpc? h)
  (and (json-object? h)
       (equal? (hash-ref h 'jsonrpc #f) JSONRPC-VERSION)))

;; RequestIdSchema = z.union([z.string(), z.number().int()]) — a string OR an
;; exact integer. exact-integer? rejects 1.0 (inexact), 1.5, booleans, 'null,
;; and objects. JSON null parses to the symbol 'null, which is not valid here.
(define (valid-id? x)
  (or (string? x) (exact-integer? x)))

;; Envelope-level `.strict()`: every top-level key of `h` must be in `allowed`.
;; NEVER call this on a nested object.
(define (only-keys? h allowed)
  (for/and ([k (in-hash-keys h)]) (and (memq k allowed) #t)))

;; TS `params` is a loose OBJECT (schemas.ts:102,115): if present it must be an
;; object; a non-object params (params:5, params:'null) is rejected. Its inner
;; contents are NOT validated here.
(define (params-ok? h)
  (define p (hash-ref h 'params 'absent))
  (or (eq? p 'absent) (json-object? p)))

;; Sentinel-based key presence (a present 'null is distinct from absent).
(define (has-key? h k)
  (not (eq? (hash-ref h k 'absent) 'absent)))

;; --- request -------------------------------------------------------------

;; jsonrpc="2.0", valid id, string method, optional object params, no
;; result/error, no extra top-level keys.
(define (is-jsonrpc-request? v)
  (and (valid-jsonrpc? v)
       (valid-id? (hash-ref v 'id 'absent))
       (string? (hash-ref v 'method #f))
       (params-ok? v)
       (not (has-key? v 'result))
       (not (has-key? v 'error))
       (only-keys? v '(jsonrpc id method params))
       #t))

;; --- notification --------------------------------------------------------

;; jsonrpc="2.0", string method, optional object params, NO id, no
;; result/error, no extra top-level keys. (id presence => request, not
;; notification.)
(define (is-jsonrpc-notification? v)
  (and (valid-jsonrpc? v)
       (not (has-key? v 'id))
       (string? (hash-ref v 'method #f))
       (params-ok? v)
       (not (has-key? v 'result))
       (not (has-key? v 'error))
       (only-keys? v '(jsonrpc method params))
       #t))

;; --- responses -----------------------------------------------------------

;; jsonrpc="2.0", valid id (required), result is an object, no method/error,
;; no extra top-level keys. `result` is a loose object (may be empty / carry
;; extra keys); its contents are not constrained at the envelope level.
(define (is-jsonrpc-result-response? v)
  (and (valid-jsonrpc? v)
       (valid-id? (hash-ref v 'id 'absent))
       (json-object? (hash-ref v 'result #f))
       (not (has-key? v 'method))
       (not (has-key? v 'error))
       (only-keys? v '(jsonrpc id result))
       #t))

;; The inner `error` object: a plain z.object (NOT strict, schemas.ts:177–190)
;; requiring code (exact integer) and message (string); `data` and any other
;; unknown inner keys are ALLOWED. We therefore check only code/message
;; presence+type and do NOT key-restrict the error object.
(define (valid-error-object? e)
  (and (json-object? e)
       (exact-integer? (hash-ref e 'code 'absent))
       (string? (hash-ref e 'message #f))))

;; jsonrpc="2.0", error object (as above), id OPTIONAL (string|int when
;; present — a present 'null id is rejected), no result/method, no extra
;; top-level keys. An id-less error is STILL an error (NOT a notification).
(define (is-jsonrpc-error? v)
  (and (valid-jsonrpc? v)
       (let ([id (hash-ref v 'id 'absent)])
         (or (eq? id 'absent) (valid-id? id)))
       (valid-error-object? (hash-ref v 'error #f))
       (not (has-key? v 'result))
       (not (has-key? v 'method))
       (only-keys? v '(jsonrpc id error))
       #t))

;; JSONRPCResponseSchema = z.union([Result, Error]) (guards.ts:71) — the union
;; of result-response OR error-response.
(define (is-jsonrpc-response? v)
  (or (is-jsonrpc-result-response? v)
      (is-jsonrpc-error? v)))
