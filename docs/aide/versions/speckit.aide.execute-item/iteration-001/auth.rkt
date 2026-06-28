#lang racket/base

;; Work Item 015 — shared `AuthInfo` struct + token/metadata helpers (M5d).
;;
;; Mirrors the `AuthInfo` shape at the MCP TypeScript SDK's
;; `packages/core/src/types/types.ts:435` plus the NON-OAuth token/metadata
;; helpers from `shared/auth.ts` + `authUtils.ts`. This is the shared struct the
;; S8 client (`mcp/client/auth.rkt`) and server (`mcp/server/auth/`) both consume.
;;
;; ---------------------------------------------------------------------------
;; Field surface — mirrors TS `AuthInfo` field-for-field, kebab-cased,
;; `#:transparent`:
;;   (struct auth-info (token client-id scopes expires-at resource extra))
;;   | TS field   | Racket field | contract                          | required? |
;;   | token      | token        | string?                           | yes       |
;;   | clientId   | client-id    | string?                           | yes       |
;;   | scopes     | scopes       | (listof string?)                  | yes ('()) |
;;   | expiresAt? | expires-at   | (or/c #f exact-nonnegative-integer?) | opt -> #f |
;;   | resource?  | resource     | (or/c #f string?)                 | opt -> #f |
;;   | extra?     | extra        | (or/c #f json-object?)            | opt -> #f |
;; `scopes` is REQUIRED in TS (`string[]`, no `?`) — always present, '() when
;; none, never absent; the smart constructor defaults it to '(). Optional fields
;; default to #f (the codebase's opt/#f convention); #f ≠ a present-but-empty
;; value (an empty-but-present `extra` of `(hasheq)` is NOT #f).
;;
;; `resource` is a STRING, not a parsed URL (portability). TS holds it as a `URL`
;; object; this port holds the wire-form URL string. We do NOT use `net/url`: the
;; full `net/url` module transitively pulls `racket/tcp` (a socket dependency),
;; which would violate the Portability NFR (core L0–L2 loads with no
;; subprocess/socket) and break item 017's restricted-load sweep. If S8 later
;; needs a parsed form it may wrap with the pure `net/url-structs` at that layer.
;;
;; ---------------------------------------------------------------------------
;; Helpers (token + metadata, NO OAuth):
;;   `auth-info-expired?` — token helper. `expires-at` is seconds since epoch;
;;     (expired? ai [now]) ⇔ expires-at present AND <= now. #f expires-at -> #f
;;     (no expiry / unknown). epoch 0 is a REAL expiry (0 is truthy in Racket),
;;     not a #f-fallthrough. The optional `now` makes it wall-clock-independent.
;;   `auth-info-has-scope?` — metadata helper; scope ∈ scopes.
;;   `auth-info->json` / `json->auth-info` — wire round-trip (camelCase keys).
;;
;; `make-auth-info` / `auth-info` field contracts are enforced via `define/contract`
;; (checked on EVERY call, including the internal call from `json->auth-info`),
;; so bad field values raise `exn:fail:contract?`.
;;
;; `json->auth-info` DECODE-REJECT discipline (security-relevant): the decoder is
;; NOT a silent #f-filler. It reads the camelCase wire keys and RAISES on a
;; missing/non-string `token` or `clientId`, or a missing/non-list-of-string
;; `scopes`. Silently building an `auth-info` with an #f token would treat an
;; unauthenticated token as authenticated — a security footgun. Required-field
;; absence raises here; type violations are caught by `make-auth-info`'s contract.
;; `auth-info->json` emits camelCase `token`/`clientId`/`scopes` and omits #f
;; optionals (but 0 and an empty-but-present `extra` ARE emitted — #f ≠ falsy).
;;
;; Scope guard: NO OAuth logic (the OAuth zod schemas in TS `auth.ts` are S8/M14)
;; and NO `resourceUrlFromServerUrl`/`checkResourceAllowed` (those URL helpers
;; need URL parsing — the net/url hazard above — and belong to S8).
;;
;; ---------------------------------------------------------------------------
;; Imports — `racket/contract` (field contracts) + S1's `json-object?` via the
;; `../main.rkt` S1 barrel. NO `net/url`, no subprocess/socket. (Transitive
;; restricted-load proof is item 017's collection-wide sweep.)

(require racket/contract
         "../main.rkt")

(provide (struct-out auth-info)
         make-auth-info
         auth-info-expired?
         auth-info-has-scope?
         auth-info->json
         json->auth-info)

;; The AuthInfo struct — EXACTLY six fields, in this order, no others.
(struct auth-info (token client-id scopes expires-at resource extra) #:transparent)

;; Smart constructor — keyword args, scopes defaults to '(), optionals to #f.
;; `define/contract` so the field contracts are checked on every call (internal
;; calls from `json->auth-info` included), raising `exn:fail:contract?` on a bad
;; field value (non-string token, negative expires-at, non-list scopes, …).
(define/contract (make-auth-info #:token token
                                 #:client-id client-id
                                 #:scopes [scopes '()]
                                 #:expires-at [expires-at #f]
                                 #:resource [resource #f]
                                 #:extra [extra #f])
  (->* (#:token string? #:client-id string?)
       (#:scopes (listof string?)
        #:expires-at (or/c #f exact-nonnegative-integer?)
        #:resource (or/c #f string?)
        #:extra (or/c #f json-object?))
       auth-info?)
  (auth-info token client-id scopes expires-at resource extra))

;; (auth-info-expired? ai [now-seconds]) -> boolean?  ; TOKEN helper.
;; expires-at present AND <= now. #f expires-at -> #f. epoch 0 is a real expiry
;; (0 is truthy in Racket, so the `and` does NOT short-circuit on it).
(define (auth-info-expired? ai [now-seconds (current-seconds)])
  (define exp (auth-info-expires-at ai))
  (and exp (<= exp now-seconds)))

;; (auth-info-has-scope? ai scope) -> boolean?  ; METADATA helper.
(define (auth-info-has-scope? ai scope)
  (and (member scope (auth-info-scopes ai)) #t))

;; (auth-info->json ai) -> json-object?  ; camelCase keys, omit #f optionals.
;; 0 and an empty-but-present `extra` are NOT #f, so they ARE emitted.
(define (auth-info->json ai)
  (let* ([h (hasheq 'token    (auth-info-token ai)
                    'clientId  (auth-info-client-id ai)
                    'scopes    (auth-info-scopes ai))]
         [h (put-unless-false h 'expiresAt (auth-info-expires-at ai))]
         [h (put-unless-false h 'resource  (auth-info-resource ai))]
         [h (put-unless-false h 'extra     (auth-info-extra ai))])
    h))

;; Emit (key . value) only when value is not #f (mirrors S1's put-skips-#f).
(define (put-unless-false h key v)
  (if (eq? v #f) h (hash-set h key v)))

;; Sentinel distinguishing "absent" from a present #f/null wire value.
(define missing (gensym 'missing))

;; (json->auth-info h) -> auth-info?  ; inverse of auth-info->json. Reads the
;; camelCase wire keys; RAISES on a missing required field (decode-reject
;; discipline); type violations surface via make-auth-info's contract.
(define (json->auth-info h)
  (make-auth-info
   #:token      (req h 'token)
   #:client-id  (req h 'clientId)
   #:scopes     (req h 'scopes)
   #:expires-at (opt h 'expiresAt)
   #:resource   (opt h 'resource)
   #:extra      (opt h 'extra)))

;; Required wire field — raise on absence (do NOT silently #f-fill).
(define (req h key)
  (define v (hash-ref h key missing))
  (when (eq? v missing)
    (error 'json->auth-info "required field missing: ~a" key))
  v)

;; Optional wire field — absent -> #f.
(define (opt h key) (hash-ref h key #f))
