#lang racket/base

;; Item 020 — in-memory paired transport adapter (M10).
;;
;; Implements gen:transport from mcp/transport/transport.rkt (M6).
;; Async delivery via relay thread + async-channel; send never blocks on consumer.
;;
;; send on endpoint A enqueues on B's inbox; B's relay thread dequeues and calls
;; B's on-message. close propagates to peer. on-error fires if relay catches exn.
;;
;; IMPORTS: M6 + L0 only. NO net/url, sockets, subprocess, web-server.

(require racket/generic
         racket/async-channel
         "transport.rkt")

;; -----------------------------------------------------------------------
;; in-memory-transport struct.
;;
;; Fields:
;;   on-message      : (or/c #f procedure?) — installed message handler
;;   on-close        : (or/c #f procedure?) — installed close handler
;;   on-error        : (or/c #f procedure?) — installed error handler
;;   peer            : (or/c #f in-memory-transport?) — linked partner
;;   inbox           : async-channel — peer writes here; relay reads here
;;   relay-thread    : (or/c #f thread?) — #f until transport-start
;;   started?        : boolean — idempotency guard for transport-start
;;   closed?         : boolean — set on transport-close
;;   pre-start-queue : list — FIFO buffer for pre-start sends; append-only (never cons)
;; -----------------------------------------------------------------------
(struct in-memory-transport
  (on-message on-close on-error peer inbox relay-thread started? closed? pre-start-queue)
  #:mutable
  #:methods gen:transport

  [(define (transport-start self)
     ;; Idempotent — second call returns immediately without spawning another thread.
     (unless (in-memory-transport-started? self)
       (set-in-memory-transport-started?! self #t)
       (define inbox (in-memory-transport-inbox self))
       ;; Spawn relay thread; reads handler fields freshly on each iteration so
       ;; handlers installed after start are picked up.
       (define t
         (thread
          (λ ()
            (let loop ()
              (define item (async-channel-get inbox))
              (cond
                [(eq? item 'close) (void)]   ; sentinel — relay exits cleanly
                [else
                 ;; Read fields fresh each iteration (handlers may be set post-start).
                 (define h   (in-memory-transport-on-message self))
                 (define err (in-memory-transport-on-error   self))
                 ;; Relay SURVIVES handler exceptions — on-error fires, loop continues.
                 (with-handlers ([exn:fail? (λ (e) (when err (err e)))])
                   (when h (h (car item) (cdr item))))
                 (loop)])))))
       (set-in-memory-transport-relay-thread! self t)
       ;; Drain pre-start FIFO queue onto inbox in list order.
       (for ([item (in-memory-transport-pre-start-queue self)])
         (async-channel-put inbox item))
       (set-in-memory-transport-pre-start-queue! self '())))

   (define (%transport-send self msg opts)
     ;; Raise immediately on closed transport; opts (related-request-id etc.) silently ignored.
     (when (in-memory-transport-closed? self)
       (raise (make-exn:fail "in-memory-transport: cannot send on closed transport"
                             (current-continuation-marks))))
     (define extra (cons msg (make-message-extra-info)))  ; extra-info all-#f
     (define peer (in-memory-transport-peer self))
     ;; Deliver to peer: queue on inbox if started, else append to pre-start FIFO.
     (if (in-memory-transport-started? peer)
         (async-channel-put (in-memory-transport-inbox peer) extra)
         (set-in-memory-transport-pre-start-queue!
          peer
          (append (in-memory-transport-pre-start-queue peer) (list extra)))))

   (define (transport-close self)
     ;; Guard: no-op + no double-fire if already closed.
     (unless (in-memory-transport-closed? self)
       (set-in-memory-transport-closed?! self #t)
       ;; Signal relay thread to exit after draining in-flight messages.
       (async-channel-put (in-memory-transport-inbox self) 'close)
       ;; Propagate close to peer before firing own on-close.
       (define peer (in-memory-transport-peer self))
       (when (and peer (not (in-memory-transport-closed? peer)))
         (transport-close peer))
       ;; Fire own on-close exactly once.
       (define on-close (in-memory-transport-on-close self))
       (when on-close (on-close))
       ;; Clear peer reference to avoid cycles.
       (set-in-memory-transport-peer! self #f)))

   ;; Sink getters — return currently installed handler or #f.
   (define (transport-on-message self) (in-memory-transport-on-message self))
   (define (transport-on-close   self) (in-memory-transport-on-close   self))
   (define (transport-on-error   self) (in-memory-transport-on-error   self))

   ;; Sink setters — install new handler (may be called before or after start).
   (define (set-transport-on-message! self h) (set-in-memory-transport-on-message! self h))
   (define (set-transport-on-close!   self h) (set-in-memory-transport-on-close!   self h))
   (define (set-transport-on-error!   self h) (set-in-memory-transport-on-error!   self h))

   ;; In-memory transport has no persistent session concept.
   (define (transport-session-id self) #f)])

;; -----------------------------------------------------------------------
;; in-memory-transport-create-linked-pair — construct cross-linked pair.
;; Each endpoint gets its own inbox async-channel and a #f peer until linked.
;; -----------------------------------------------------------------------
(define (in-memory-transport-create-linked-pair)
  (define ep-a (in-memory-transport #f #f #f #f (make-async-channel) #f #f #f '()))
  (define ep-b (in-memory-transport #f #f #f #f (make-async-channel) #f #f #f '()))
  (set-in-memory-transport-peer! ep-a ep-b)
  (set-in-memory-transport-peer! ep-b ep-a)
  (values ep-a ep-b))

;; -----------------------------------------------------------------------
;; Explicit provide — NO all-defined-out.
;; -----------------------------------------------------------------------
(provide
 in-memory-transport
 in-memory-transport?
 in-memory-transport-create-linked-pair)
