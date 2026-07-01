#lang racket/base

;; Item 019 — gen:transport hexagonal port (M6).
;;
;; Racket port of TS `Transport` interface + `TransportSendOptions` +
;; `MessageExtraInfo` (typescript-sdk/packages/core/src/shared/transport.ts:74).
;;
;; INERT NOTE: `related-request-id` in `transport-send-options` is a routing
;; hint defined here for port-surface stability. It is INERT until S6a/M8
;; (Streamable HTTP). Adapters MUST accept and ignore non-#f values; they
;; MUST NOT error on it.
;;
;; DESIGN NOTE: `message-extra-info.session` has no direct TS `MessageExtraInfo`
;; counterpart (TS surfaces session via `sessionId` on the Transport object).
;; It is a deliberate Racket-specific addition — do not remove it.
;;
;; IMPORTS: L0/L1 only. NO net/url, subprocess, socket, web-server.

(require racket/generic
         racket/contract
         "../core/main.rkt"         ; S1 barrel — json-object?
         "../core/shared/auth.rkt") ; S2 — auth-info?

;; -----------------------------------------------------------------------
;; message-extra-info — per-message context passed to the on-message handler.
;; Mirrors TS MessageExtraInfo (types.ts:561), scoped to fields relevant here.
;;
;; Fields:
;;   session      : (or/c #f string?) — per-connection session ID.
;;                  Racket-specific: TS exposes session via `sessionId` on the
;;                  Transport object, not on MessageExtraInfo. Co-located here
;;                  for handler convenience (sanctioned by queue-003.md).
;;   auth         : (or/c #f auth-info?) — S2 auth token; #f = unauthenticated.
;;   http-req-info: (or/c #f json-object?) — wire-safe jsexpr map of HTTP
;;                  metadata; #f for stdio. TS counterpart is `request?` (live
;;                  HTTP object); Racket uses a plain jsexpr map per portability
;;                  NFR (no net/url at this layer).
;; -----------------------------------------------------------------------
(struct message-extra-info (session auth http-req-info) #:transparent)

;; make-message-extra-info — smart constructor; all fields default to #f.
;; Raises exn:fail:contract? on bad field values (house precedent: auth.rkt:81).
(define/contract (make-message-extra-info
                  #:session       [session #f]
                  #:auth          [auth #f]
                  #:http-req-info [http-req-info #f])
  (->* ()
       (#:session       (or/c #f string?)
        #:auth          (or/c #f auth-info?)
        #:http-req-info (or/c #f json-object?))
       message-extra-info?)
  (message-extra-info session auth http-req-info))

;; -----------------------------------------------------------------------
;; transport-send-options — optional second arg to transport-send.
;;
;; Fields:
;;   related-request-id: (or/c #f string? exact-integer?) — INERT until S6a/M8.
;;                       Multiplexed-transport routing hint. Adapters MUST
;;                       accept and ignore non-#f values until M8.
;;   resumption-token  : (or/c #f string?) — reconnect continuity token;
;;                       adapter decides whether to use it.
;; -----------------------------------------------------------------------
(struct transport-send-options (related-request-id resumption-token) #:transparent)

;; make-transport-send-options — smart constructor; all fields default to #f.
;; Raises exn:fail:contract? on bad field values.
(define/contract (make-transport-send-options
                  #:related-request-id [related-request-id #f]
                  #:resumption-token   [resumption-token #f])
  (->* ()
       (#:related-request-id (or/c #f string? exact-integer?)
        #:resumption-token   (or/c #f string?))
       transport-send-options?)
  (transport-send-options related-request-id resumption-token))

;; -----------------------------------------------------------------------
;; gen:transport — the hexagonal port generic interface.
;;
;; ARITY NOTE: `define-generics` does not cleanly support optional positional
;; args. `%transport-send` is declared as a 3-arg internal generic (opts always
;; required at dispatch level). The public `transport-send` wrapper (defined
;; below) defaults opts to #f, giving callers 2-arg OR 3-arg call sites. This
;; is the resolved design from Decisions (see item-019 spec).
;;
;; All methods default to raising exn:fail when not implemented, so incomplete
;; concrete types are caught early (deliberate; see Decisions).
;;
;; Sink pattern: on-message / on-close / on-error are generic getter methods
;; paired with generic setter methods (set-transport-on-message! etc.) that
;; concrete types implement by delegating to their own mutable struct fields.
;; A transport-base convenience struct is NOT provided at this layer; adapters
;; own their own field layouts and wire up these generics to mutable fields.
;; -----------------------------------------------------------------------
(define-generics transport
  ;; Racket's define-generics requires the generic name ("transport") as the
  ;; first positional argument identifier in every method signature.
  (transport-start transport)
  ;; Internal 3-arg send — use public transport-send wrapper, not this directly.
  (%transport-send transport msg opts)
  (transport-close transport)
  ;; Sink getters — return the currently installed handler, or #f.
  (transport-on-message transport)
  (transport-on-close transport)
  (transport-on-error transport)
  ;; Sink setters — install a new handler.
  (set-transport-on-message! transport h)
  (set-transport-on-close! transport h)
  (set-transport-on-error! transport h)
  ;; Session accessor — (or/c #f string?); #f if transport doesn't track sessions.
  (transport-session-id transport))

;; transport-send — public wrapper; opts defaults to #f.
;; Concrete types implement %transport-send (opts always present, may be #f).
;; INERT: passing a non-#f related-request-id in opts is accepted and ignored
;; by stdio / in-memory adapters until S6a/M8.
(define (transport-send transport msg [opts #f])
  (%transport-send transport msg opts))

;; -----------------------------------------------------------------------
;; Explicit, curated provide. NO all-defined-out.
;; -----------------------------------------------------------------------
(provide
 ;; Generic port
 gen:transport
 transport?
 transport-start
 transport-send           ; public wrapper (2-arg or 3-arg)
 transport-close
 ;; Sink getters
 transport-on-message
 transport-on-close
 transport-on-error
 ;; Sink setters
 set-transport-on-message!
 set-transport-on-close!
 set-transport-on-error!
 ;; Optional session accessor
 transport-session-id
 ;; message-extra-info
 message-extra-info
 message-extra-info?
 make-message-extra-info
 message-extra-info-session
 message-extra-info-auth
 message-extra-info-http-req-info
 ;; transport-send-options
 transport-send-options
 transport-send-options?
 make-transport-send-options
 transport-send-options-related-request-id
 transport-send-options-resumption-token)
