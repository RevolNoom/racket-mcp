#lang racket/base

;; Work Item 015 — tests for `_meta` metadata utils (M5c).
;;
;; Fixture provenance: the `get-display-name` cases are derived from the
;; documented precedence in TS `metadataUtils.ts` (`getDisplayName`) + its
;; empty-string/undefined guard order (TS has no dedicated test file for it).
;; The reserved-key set + the SEP-414 trace keys are from TS `constants.ts`. The
;; S1 envelope round-trip exercises `request-meta` (item 004) to prove the trace
;; keys ride S1's unreserved `request-meta-rest` passthrough.
;;
;; `json` is required for `(json-null)` (the C1/S5 malformed-input cases);
;; `mcp/core/main.rkt` for the S1 `request-meta` round-trip (r26:-prefixed) and
;; the S1 `…-META-KEY` constants.

(require rackunit
         json
         (file "../metadata-utils.rkt")
         (file "../../main.rkt"))

;; ===========================================================================
;; Part 1 — get-display-name precedence (G1), seven happy-path cases.
;; ===========================================================================
(check-equal? (get-display-name (hasheq 'name "n" 'title "t")) "t"
              "title wins")
(check-equal? (get-display-name (hasheq 'name "n" 'title "" 'annotations (hasheq 'title "a"))) "a"
              "empty-string title falls through to annotations.title")
(check-equal? (get-display-name (hasheq 'name "n" 'title "")) "n"
              "empty-string title + no annotations falls through to name")
(check-equal? (get-display-name (hasheq 'name "n")) "n"
              "no title, no annotations -> name")
(check-equal? (get-display-name (hasheq 'name "n" 'annotations (hasheq 'title "a"))) "a"
              "no title -> annotations.title")
(check-equal? (get-display-name (hasheq 'name "n" 'title "t" 'annotations (hasheq 'title "a"))) "t"
              "title wins over annotations.title")
(check-equal? (get-display-name (hasheq 'name "n" 'annotations (hasheq 'title ""))) "n"
              "empty annotations.title falls through to name")

;; ===========================================================================
;; Part 1b — malformed / irregular input (C1, S5, S6).
;; ===========================================================================
(check-equal? (get-display-name (hasheq 'name "n" 'annotations (json-null))) "n"
              "C1: null annotations falls through to name, no crash")
(check-equal? (get-display-name (hasheq 'name "n" 'annotations "garbage")) "n"
              "C1: non-hash annotations falls through to name, no crash")
(check-equal? (get-display-name (hasheq 'name "n" 'title (json-null))) "n"
              "S5: non-string title falls through (stricter than TS, documented)")
(check-exn exn:fail?
           (lambda () (get-display-name (hasheq 'title "")))
           "S6: missing name reaches rung 3 and raises")

;; ===========================================================================
;; Part 2 — reserved-key constants + predicate + two-notions boundary.
;; ===========================================================================
(check-equal? TRACEPARENT-META-KEY "traceparent")
(check-equal? TRACESTATE-META-KEY "tracestate")
(check-equal? BAGGAGE-META-KEY "baggage")
(check-equal? (length reserved-meta-keys) 8 "all eight reserved _meta keys")

;; each of the eight key symbols is a member of reserved-meta-keys
(for ([k (in-list (list (string->symbol PROTOCOL-VERSION-META-KEY)
                        (string->symbol CLIENT-INFO-META-KEY)
                        (string->symbol CLIENT-CAPABILITIES-META-KEY)
                        (string->symbol LOG-LEVEL-META-KEY)
                        (string->symbol RELATED-TASK-META-KEY)
                        'traceparent 'tracestate 'baggage))])
  (check-true (and (memq k reserved-meta-keys) #t)
              (format "~a is a reserved meta key" k)))

(check-true (reserved-meta-key? 'traceparent))
(check-true (reserved-meta-key? TRACEPARENT-META-KEY) "string form accepted")
(check-false (reserved-meta-key? 'someUserKey))
;; Two-notions-of-reserved boundary (S1): progressToken IS reserved at the S1
;; RequestParams level (request-meta-reserved-keys) but is NOT one of the 8
;; namespaced `_meta` reserved keys.
(check-false (reserved-meta-key? 'progressToken)
             "S1: progressToken is not a namespaced _meta reserved key")

;; ===========================================================================
;; Part 3 — meta-ref / meta-set round-trip, non-reserved untouched, key
;; normalization, missing-key behaviour.
;; ===========================================================================
(define m0 (hasheq 'someUserKey "keep"))
(define m1 (meta-set m0 'traceparent "00-abc-01"))
(check-equal? (meta-ref m1 'traceparent) "00-abc-01" "reserved key reads back")
(check-equal? (meta-ref m1 'someUserKey) "keep" "non-reserved key untouched")
(check-equal? (meta-ref m0 'traceparent) #f "m0 unchanged — meta-set is functional")
;; also a prefixed reserved key
(define m2 (meta-set m1 LOG-LEVEL-META-KEY "debug"))
(check-equal? (meta-ref m2 LOG-LEVEL-META-KEY) "debug")

;; Prefixed-key string/symbol equivalence (S2): a string-set is readable by the
;; equivalent (pipe-quoted) symbol, proven on a prefixed key (not a short word).
(define ml (meta-set (hasheq) LOG-LEVEL-META-KEY "debug"))
(check-equal? (meta-ref ml LOG-LEVEL-META-KEY) "debug")
(check-equal? (meta-ref ml (string->symbol LOG-LEVEL-META-KEY)) "debug"
              "S2: string-keyed set readable by equivalent symbol")

;; Missing-key default (S3).
(check-equal? (meta-ref (hasheq) 'absent) #f "no default -> #f, no raise")
(check-equal? (meta-ref (hasheq) 'absent 'dflt) 'dflt "explicit default returned")

;; ===========================================================================
;; Part 4 — trace keys pass through the S1 `_meta` envelope (C5/S7).
;; The three S1-required reserved keys MUST be VALID sub-objects (not bare
;; strings) or json->request-meta crashes for the wrong reason. clientCapabilities
;; = (hasheq) is accepted (client-capabilities wraps the raw object,
;; spec-2026-07-28.rkt:395-398).
;; ===========================================================================
(define meta-in
  (hasheq (string->symbol PROTOCOL-VERSION-META-KEY)    "2026-07-28"
          (string->symbol CLIENT-INFO-META-KEY)         (hasheq 'name "c" 'version "1")
          (string->symbol CLIENT-CAPABILITIES-META-KEY) (hasheq)
          'traceparent "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
          'tracestate  "vendor1=value1"
          'baggage     "userId=alice"))
(define re-emitted (r26:request-meta->json (r26:json->request-meta meta-in)))
(check-equal? (meta-ref re-emitted TRACEPARENT-META-KEY)
              "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
              "traceparent survives S1 envelope round-trip")
(check-equal? (meta-ref re-emitted TRACESTATE-META-KEY) "vendor1=value1"
              "tracestate survives S1 envelope round-trip")
(check-equal? (meta-ref re-emitted BAGGAGE-META-KEY) "userId=alice"
              "baggage survives S1 envelope round-trip")
