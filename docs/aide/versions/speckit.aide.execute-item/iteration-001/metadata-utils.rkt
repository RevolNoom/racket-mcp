#lang racket/base

;; Work Item 015 — `_meta` metadata utils (M5c).
;;
;; Mirrors the MCP TypeScript SDK's `packages/core/src/shared/metadataUtils.ts`
;; (the `getDisplayName` precedence helper) and the reserved-`_meta`-key portion
;; of `packages/core/src/types/constants.ts` (the eight reserved keys). Two
;; responsibilities: (1) `get-display-name` (display-name precedence) and
;; (2) the reserved `_meta` key surface (constants + accessor/setter helpers).
;;
;; ---------------------------------------------------------------------------
;; (1) `get-display-name` — display-name precedence (NOT a verbatim TS port).
;;
;; Operates on the symbol-keyed JSON-object hash (the wire/duck-typed form that
;; `read-json` and every S1 `…->json` produce). TS `getDisplayName` is duck-typed
;; over `.title` / `.annotations?.title` / `.name`; this port reads the
;; equivalent hash keys. Chosen over struct-dispatch over the six S1 metadata
;; structs because it mirrors the TS object 1:1, round-trips with the wire form,
;; and keeps the annotations.title rung testable without a full `tool` struct.
;;
;; Precedence:
;;   rung 1 — non-empty STRING `title`            -> title
;;   rung 2 — (hash? annotations) AND non-empty STRING annotations.title -> it
;;   rung 3 — `name` (no default; raises if absent)
;;
;; Empty-string-title fallthrough (load-bearing): TS checks
;; `title !== undefined && title !== ''`, so a `title` of "" is treated as
;; ABSENT and falls through (rung 1 fails) into annotations.title then name.
;; `{name:"n", title:"", annotations:{title:"a"}}` -> "a";
;; `{name:"n", title:""}` -> "n". The same empty-string guard applies to
;; annotations.title (TS truthy-tests `annotations?.title`, so "" is falsy).
;;
;; Two DELIBERATE divergences from TS (this is NOT a byte-for-byte port at the
;; title rungs):
;;   (S5) non-string `title`/`annotations.title`: Racket's `(and (string? …) …)`
;;        guard is STRICTER than TS's `!== ''`. TS returns `null` for
;;        `title: null` and `42` for `title: 42`; this port falls through to
;;        name/annotations. Intentional — a display name must be a string;
;;        returning null/42 would be a downstream footgun.
;;   (C1) `null`/non-hash `annotations`: `read-json` yields `'annotations → 'null`
;;        (or a non-hash) for a malformed object. The `(hash? annotations)` guard
;;        makes such input fall through to `name` rather than crashing on the
;;        inner `hash-ref` (mirrors TS's optional-chaining `annotations?.title`).
;;        Without the guard `get-display-name` would crash — this is the latent
;;        crash fix.
;;
;; `name` is required (S1 domain): a metadata object always carries `name`. If
;; `'name` is absent the rung-3 `(hash-ref md 'name)` raises (no #f/"" fallback
;; invented — matches TS's static `name: string` contract).
;;
;; ---------------------------------------------------------------------------
;; (2) Reserved `_meta` key surface + the 5-vs-8 reconciliation.
;;
;; TS `constants.ts` defines EIGHT reserved `_meta` keys. S1's `constants.rkt`
;; captured FIVE (all `io.modelcontextprotocol/…`-prefixed). The three missing
;; ones are the W3C trace-context keys (SEP-414), defined HERE:
;;   `traceparent` / `tracestate` / `baggage` — UNPREFIXED plain strings, an
;; explicit exception to the `_meta` key-prefix rule, reserved for
;; OpenTelemetry-style distributed-trace propagation. This module aggregates all
;; eight in one place (re-exporting the five S1 constants + adding the three
;; trace constants), closing the 5-vs-8 gap rather than silently dropping it.
;;
;; The SDK does NOT interpret trace-context values: `traceparent`/`tracestate`/
;; `baggage` pass through `_meta` UNTOUCHED — never parsed/validated. They ride
;; S1's unreserved `request-meta-rest` passthrough and are re-emitted verbatim.
;;
;; Two-notions-of-reserved boundary: M5c's `reserved-meta-keys` (the 5 prefixed
;; keys ∪ {traceparent, tracestate, baggage} = 8) is NOT S1's
;; `request-meta-reserved-keys` ({progressToken} ∪ {the 5 prefixed keys} = 6).
;; Consequences: `(reserved-meta-key? 'progressToken)` -> #f (it IS reserved at
;; the S1 `RequestParams` level, but is not a namespaced `_meta` reserved key);
;; and the 3 trace keys are in M5c's set but ride S1's UNRESERVED rest.
;;
;; Accessors (`meta-ref`/`meta-set`) operate on a symbol-keyed `_meta` hash and
;; accept the key as either a string (a `…-META-KEY` constant) or a symbol,
;; normalizing to the symbol form (mirrors S1's `(string->symbol …-META-KEY)`).
;; `meta-ref` with no default returns #f on a missing key (a present-or-#f
;; probe, not a raiser). `meta-set` is functional (returns a NEW hash).
;;
;; ---------------------------------------------------------------------------
;; Imports — S1 ONLY (the five reserved-key constants), via the `../main.rkt`
;; S1 barrel. Pure non-I/O. NO `net/*`, no `racket/system`, no
;; `racket/tcp`/`racket/udp`, no subprocess/socket. (The transitive restricted-
;; load proof is item 017's collection-wide sweep — not duplicated here.)

(require "../main.rkt")

(provide get-display-name
         ;; eight reserved-key string constants (5 re-exported from S1 + 3 here)
         PROTOCOL-VERSION-META-KEY
         CLIENT-INFO-META-KEY
         CLIENT-CAPABILITIES-META-KEY
         LOG-LEVEL-META-KEY
         RELATED-TASK-META-KEY
         TRACEPARENT-META-KEY
         TRACESTATE-META-KEY
         BAGGAGE-META-KEY
         reserved-meta-key-strings
         reserved-meta-keys
         reserved-meta-key?
         meta-ref
         meta-set)

;; (get-display-name md) -> string?   ; md : symbol-keyed json-object hash.
;; rung 1 non-empty STRING title -> rung 2 (hash? annotations)-guarded non-empty
;; STRING annotations.title -> rung 3 name (no default; raises if absent).
(define (get-display-name md)
  (define title (hash-ref md 'title #f))
  (define annotations (hash-ref md 'annotations #f))
  (cond
    [(and (string? title) (not (string=? title ""))) title]          ; rung 1
    [(and (hash? annotations)                                        ; rung 2 — only if
          (let ([at (hash-ref annotations 'title #f)])               ;   annotations is a hash
            (and (string? at) (not (string=? at "")) at)))]          ;   (C1 guard)
    [else (hash-ref md 'name)]))                                     ; rung 3 — raises if absent

;; --- the three SEP-414 trace-context keys (UNPREFIXED, net-new in M5c) ---
(define TRACEPARENT-META-KEY "traceparent")
(define TRACESTATE-META-KEY "tracestate")
(define BAGGAGE-META-KEY "baggage")

;; All eight reserved `_meta` key strings, then their hash-key symbols.
(define reserved-meta-key-strings
  (list PROTOCOL-VERSION-META-KEY
        CLIENT-INFO-META-KEY
        CLIENT-CAPABILITIES-META-KEY
        LOG-LEVEL-META-KEY
        RELATED-TASK-META-KEY
        TRACEPARENT-META-KEY
        TRACESTATE-META-KEY
        BAGGAGE-META-KEY))
(define reserved-meta-keys (map string->symbol reserved-meta-key-strings))

;; Normalize a key (string OR symbol) to its hash-key symbol form.
(define (normalize-key k) (if (string? k) (string->symbol k) k))

;; (reserved-meta-key? k) -> boolean?  ; k a symbol or string; member of the 8.
(define (reserved-meta-key? k)
  (and (memq (normalize-key k) reserved-meta-keys) #t))

;; (meta-ref meta key [default]) -> value  ; read a key from a `_meta` hash.
;; No-default + missing key -> #f (a present-or-#f probe, not a raiser).
(define (meta-ref meta key [default #f])
  (hash-ref meta (normalize-key key) default))

;; (meta-set meta key value) -> meta'  ; functional set (returns a NEW hash).
(define (meta-set meta key value)
  (hash-set meta (normalize-key key) value))
