#lang racket/base
;; ============================================================================
;; types.rkt — Public protocol types + normalized-superset façade (N1)
;; ----------------------------------------------------------------------------
;; This module is the M1 PUBLIC surface and the architecture-N1 normalized
;; superset façade. Where items 003/004 each model ONE wire revision, this
;; module exposes ONE internal shape per protocol primitive that is the UNION
;; of both revisions' fields. Every layer above M1 (transport, the protocol
;; engine, client, server, the handler API) consumes THESE façade structs
;; regardless of the negotiated protocol version.
;;
;; Per field, a façade struct field is:
;;   - SHARED      — present in both 003 and 004; both normalizers copy it.
;;   - 2025-only   — present only in 003; normalize-from-2026 sets it `absent`;
;;                   denormalize-to-2026 REFUSES it if non-absent.
;;   - 2026-only   — present only in 004; normalize-from-2025 sets it `absent`;
;;                   denormalize-to-2025 REFUSES it if non-absent.
;;
;; The `absent` sentinel is the SAME `eq?` binding 003/004 use (imported from
;; spec-2025-11-25.rkt and re-exported). `(absent? field)` is the cross-stack
;; field-presence test. Revision identity is carried by an explicit negotiated
;; version tag threaded from the protocol engine — NEVER sniffed from a field
;; value (see Decisions "presence-vs-revision-capability").
;;
;; The façade does NO I/O and introduces NO new wire shapes. It composes
;; 003/004's `json->X`/`X->json` with the per-primitive normalize/denormalize
;; seam below.
;; ============================================================================

(require racket/contract
         (prefix-in r25: "spec-2025-11-25.rkt")
         (prefix-in r26: "spec-2026-07-28.rkt")
         ;; The shared sentinel: import from ONE place (003) and re-export.
         (only-in "spec-2025-11-25.rkt" absent absent? present?))

;; ----------------------------------------------------------------------------
;; json-object? — same shape predicate the revision modules use (immutable
;; symbol-keyed hasheq). Re-defined here (not provided by 003/004) so the
;; façade contracts can name it.
;; ----------------------------------------------------------------------------
(define (json-object? v)
  (and (hash? v) (immutable? v) (hash-eq? v)))

;; opt/c — a contract that also admits the absent sentinel (mirrors 003/004).
(define (opt/c c) (or/c absent? c))

;; revision/c — the negotiated-version tag.
(define revision/c (or/c '2025-11-25 '2026-07-28))

;; ----------------------------------------------------------------------------
;; Façade helper kit (internal; NOT provided).
;; ----------------------------------------------------------------------------
;; copy-opt: identity, documents "this field is copied straight through".
(define (copy-opt v) v)
;; the-other-revision-lacks-it: the field does not exist on the source
;; revision, so it is `absent` on the façade.
(define absent-field absent)
;; refuse-if-present: the N1 wire-parity guard used by denormalizers — raise if
;; a revision-gated field is non-absent while emitting to a revision that lacks
;; it.
(define (refuse-if-present who field-name v target-rev)
  (when (present? v)
    (error who "field ~a is absent from revision ~a; cannot emit it"
           field-name target-rev)))
;; refuse-primitive: a whole primitive does not exist on the target revision.
(define (refuse-primitive who prim target-rev)
  (error who "primitive ~a does not exist in revision ~a" prim target-rev))

;; ============================================================================
;; Re-exported scalar / enum contracts (identical in both revisions) + absent.
;; ============================================================================
(provide absent absent? present?
         json-object? revision/c)

(define role/c (or/c "user" "assistant"))
(define cursor/c string?)
(define progress-token/c r25:progress-token/c)
(define request-id/c r25:request-id/c)
(define logging-level/c
  (or/c "debug" "info" "notice" "warning" "error" "critical" "alert" "emergency"))
(define result-type/c r26:result-type/c)
(define cache-scope/c r26:cache-scope/c)
(define task-status/c r25:task-status/c)

(provide role/c cursor/c progress-token/c request-id/c logging-level/c
         result-type/c cache-scope/c task-status/c)

;; ============================================================================
;; GROUP 0 — primitives shape-identical in both revisions.
;; Decision (S5): define FRESH façade structs and CONVERT both revisions into
;; them (pure aliasing would leave a 2026 value as a 004 struct, failing the
;; SAME-façade predicate). The copy is mechanical.
;; ============================================================================

;; --- facade-base-metadata (name title) ---
(struct facade-base-metadata (name title) #:transparent)
(define facade-base-metadata/c
  (struct/c facade-base-metadata string? (opt/c string?)))

;; --- facade-icon (src mime-type sizes theme) ---
(struct facade-icon (src mime-type sizes theme) #:transparent)
(define facade-icon/c
  (struct/c facade-icon string? (opt/c string?) (opt/c (listof string?)) (opt/c string?)))
(define (normalize-facade-icon-from-2025 v)
  (facade-icon (r25:icon-src v) (r25:icon-mime-type v) (r25:icon-sizes v) (r25:icon-theme v)))
(define (normalize-facade-icon-from-2026 v)
  (facade-icon (r26:icon-src v) (r26:icon-mime-type v) (r26:icon-sizes v) (r26:icon-theme v)))
(define (denormalize-facade-icon-to-2025 v)
  (r25:icon (facade-icon-src v) (facade-icon-mime-type v) (facade-icon-sizes v) (facade-icon-theme v)))
(define (denormalize-facade-icon-to-2026 v)
  (r26:icon (facade-icon-src v) (facade-icon-mime-type v) (facade-icon-sizes v) (facade-icon-theme v)))

;; --- facade-annotations (audience priority last-modified) ---
(struct facade-annotations (audience priority last-modified) #:transparent)
(define facade-annotations/c
  (struct/c facade-annotations (opt/c (listof role/c)) (opt/c real?) (opt/c string?)))
(define (normalize-facade-annotations-from-2025 v)
  (facade-annotations (r25:annotations-audience v) (r25:annotations-priority v) (r25:annotations-last-modified v)))
(define (normalize-facade-annotations-from-2026 v)
  (facade-annotations (r26:annotations-audience v) (r26:annotations-priority v) (r26:annotations-last-modified v)))
(define (denormalize-facade-annotations-to-2025 v)
  (r25:annotations (facade-annotations-audience v) (facade-annotations-priority v) (facade-annotations-last-modified v)))
(define (denormalize-facade-annotations-to-2026 v)
  (r26:annotations (facade-annotations-audience v) (facade-annotations-priority v) (facade-annotations-last-modified v)))

;; opt-map for annotations across normalization (used by content blocks).
(define (norm-annots-25 v) (if (present? v) (normalize-facade-annotations-from-2025 v) absent))
(define (norm-annots-26 v) (if (present? v) (normalize-facade-annotations-from-2026 v) absent))
(define (denorm-annots-25 v) (if (present? v) (denormalize-facade-annotations-to-2025 v) absent))
(define (denorm-annots-26 v) (if (present? v) (denormalize-facade-annotations-to-2026 v) absent))

;; --- facade-implementation (name title version description website-url icons) ---
(struct facade-implementation (name title version description website-url icons) #:transparent)
(define facade-implementation/c
  (struct/c facade-implementation string? (opt/c string?) string?
            (opt/c string?) (opt/c string?) (opt/c (listof facade-icon/c))))
(define (opt-map-list v f) (if (present? v) (map f v) v))
(define (normalize-facade-implementation-from-2025 v)
  (facade-implementation (r25:implementation-name v) (r25:implementation-title v)
                         (r25:implementation-version v) (r25:implementation-description v)
                         (r25:implementation-website-url v)
                         (opt-map-list (r25:implementation-icons v) normalize-facade-icon-from-2025)))
(define (normalize-facade-implementation-from-2026 v)
  (facade-implementation (r26:implementation-name v) (r26:implementation-title v)
                         (r26:implementation-version v) (r26:implementation-description v)
                         (r26:implementation-website-url v)
                         (opt-map-list (r26:implementation-icons v) normalize-facade-icon-from-2026)))
(define (denormalize-facade-implementation-to-2025 v)
  (r25:implementation (facade-implementation-name v) (facade-implementation-title v)
                      (facade-implementation-version v) (facade-implementation-description v)
                      (facade-implementation-website-url v)
                      (opt-map-list (facade-implementation-icons v) denormalize-facade-icon-to-2025)))
(define (denormalize-facade-implementation-to-2026 v)
  (r26:implementation (facade-implementation-name v) (facade-implementation-title v)
                      (facade-implementation-version v) (facade-implementation-description v)
                      (facade-implementation-website-url v)
                      (opt-map-list (facade-implementation-icons v) denormalize-facade-icon-to-2026)))

;; --- Content blocks (5 arms, identical both revisions) ---
(struct facade-text-content (text annotations meta) #:transparent)
(define facade-text-content/c
  (struct/c facade-text-content string? (opt/c facade-annotations/c) (opt/c json-object?)))
(struct facade-image-content (data mime-type annotations meta) #:transparent)
(define facade-image-content/c
  (struct/c facade-image-content string? string? (opt/c facade-annotations/c) (opt/c json-object?)))
(struct facade-audio-content (data mime-type annotations meta) #:transparent)
(define facade-audio-content/c
  (struct/c facade-audio-content string? string? (opt/c facade-annotations/c) (opt/c json-object?)))
(struct facade-resource-link (name title uri description mime-type annotations size icons meta rest) #:transparent)
(define facade-resource-link/c
  (struct/c facade-resource-link string? (opt/c string?) string? (opt/c string?)
            (opt/c string?) (opt/c facade-annotations/c) (opt/c real?)
            (opt/c (listof facade-icon/c)) (opt/c json-object?) json-object?))
(struct facade-embedded-resource (resource annotations meta) #:transparent)
(define facade-embedded-resource/c
  (struct/c facade-embedded-resource any/c (opt/c facade-annotations/c) (opt/c json-object?)))
(struct facade-tool-use-content (id name input meta) #:transparent)
(define facade-tool-use-content/c
  (struct/c facade-tool-use-content string? string? json-object? (opt/c json-object?)))
(struct facade-tool-result-content (tool-use-id content structured-content is-error meta) #:transparent)
(define facade-tool-result-content/c
  (struct/c facade-tool-result-content string? (listof any/c) (opt/c json-object?)
            (opt/c boolean?) (opt/c json-object?)))

;; resource-contents façade (text|blob), identical both revs.
(struct facade-text-resource-contents (uri mime-type text meta) #:transparent)
(define facade-text-resource-contents/c
  (struct/c facade-text-resource-contents string? (opt/c string?) string? (opt/c json-object?)))
(struct facade-blob-resource-contents (uri mime-type blob meta) #:transparent)
(define facade-blob-resource-contents/c
  (struct/c facade-blob-resource-contents string? (opt/c string?) string? (opt/c json-object?)))
(define facade-resource-contents/c
  (or/c facade-text-resource-contents/c facade-blob-resource-contents/c))

(define (normalize-facade-resource-contents-from-2025 v)
  (cond [(r25:text-resource-contents? v)
         (facade-text-resource-contents (r25:text-resource-contents-uri v)
                                        (r25:text-resource-contents-mime-type v)
                                        (r25:text-resource-contents-text v)
                                        (r25:text-resource-contents-meta v))]
        [else
         (facade-blob-resource-contents (r25:blob-resource-contents-uri v)
                                        (r25:blob-resource-contents-mime-type v)
                                        (r25:blob-resource-contents-blob v)
                                        (r25:blob-resource-contents-meta v))]))
(define (normalize-facade-resource-contents-from-2026 v)
  (cond [(r26:text-resource-contents? v)
         (facade-text-resource-contents (r26:text-resource-contents-uri v)
                                        (r26:text-resource-contents-mime-type v)
                                        (r26:text-resource-contents-text v)
                                        (r26:text-resource-contents-meta v))]
        [else
         (facade-blob-resource-contents (r26:blob-resource-contents-uri v)
                                        (r26:blob-resource-contents-mime-type v)
                                        (r26:blob-resource-contents-blob v)
                                        (r26:blob-resource-contents-meta v))]))
(define (denormalize-facade-resource-contents-to-2025 v)
  (cond [(facade-text-resource-contents? v)
         (r25:text-resource-contents (facade-text-resource-contents-uri v)
                                     (facade-text-resource-contents-mime-type v)
                                     (facade-text-resource-contents-text v)
                                     (facade-text-resource-contents-meta v))]
        [else
         (r25:blob-resource-contents (facade-blob-resource-contents-uri v)
                                     (facade-blob-resource-contents-mime-type v)
                                     (facade-blob-resource-contents-blob v)
                                     (facade-blob-resource-contents-meta v))]))
(define (denormalize-facade-resource-contents-to-2026 v)
  (cond [(facade-text-resource-contents? v)
         (r26:text-resource-contents (facade-text-resource-contents-uri v)
                                     (facade-text-resource-contents-mime-type v)
                                     (facade-text-resource-contents-text v)
                                     (facade-text-resource-contents-meta v))]
        [else
         (r26:blob-resource-contents (facade-blob-resource-contents-uri v)
                                     (facade-blob-resource-contents-mime-type v)
                                     (facade-blob-resource-contents-blob v)
                                     (facade-blob-resource-contents-meta v))]))

(define facade-content-block/c
  (or/c facade-text-content/c facade-image-content/c facade-audio-content/c
        facade-resource-link/c facade-embedded-resource/c
        facade-tool-use-content/c facade-tool-result-content/c))
(define facade-sampling-message-content-block/c
  (or/c facade-text-content/c facade-image-content/c facade-audio-content/c
        facade-resource-link/c facade-embedded-resource/c))

;; content-block normalizers (dispatch on the revision struct predicate).
(define (normalize-facade-content-block-from-2025 v)
  (cond [(r25:text-content? v)
         (facade-text-content (r25:text-content-text v) (norm-annots-25 (r25:text-content-annotations v)) (r25:text-content-meta v))]
        [(r25:image-content? v)
         (facade-image-content (r25:image-content-data v) (r25:image-content-mime-type v) (norm-annots-25 (r25:image-content-annotations v)) (r25:image-content-meta v))]
        [(r25:audio-content? v)
         (facade-audio-content (r25:audio-content-data v) (r25:audio-content-mime-type v) (norm-annots-25 (r25:audio-content-annotations v)) (r25:audio-content-meta v))]
        [(r25:resource-link? v)
         (facade-resource-link (r25:resource-link-name v) (r25:resource-link-title v) (r25:resource-link-uri v)
                               (r25:resource-link-description v) (r25:resource-link-mime-type v)
                               (norm-annots-25 (r25:resource-link-annotations v)) (r25:resource-link-size v)
                               (opt-map-list (r25:resource-link-icons v) normalize-facade-icon-from-2025)
                               (r25:resource-link-meta v) (r25:resource-link-rest v))]
        [(r25:embedded-resource? v)
         (facade-embedded-resource (normalize-facade-resource-contents-from-2025 (r25:embedded-resource-resource v))
                                   (norm-annots-25 (r25:embedded-resource-annotations v)) (r25:embedded-resource-meta v))]
        [(r25:tool-use-content? v)
         (facade-tool-use-content (r25:tool-use-content-id v) (r25:tool-use-content-name v) (r25:tool-use-content-input v) (r25:tool-use-content-meta v))]
        [(r25:tool-result-content? v)
         (facade-tool-result-content (r25:tool-result-content-tool-use-id v)
                                     (map normalize-facade-content-block-from-2025 (r25:tool-result-content-content v))
                                     (r25:tool-result-content-structured-content v) (r25:tool-result-content-is-error v) (r25:tool-result-content-meta v))]
        [else (error 'normalize-facade-content-block-from-2025 "unknown content block")]))
(define (normalize-facade-content-block-from-2026 v)
  (cond [(r26:text-content? v)
         (facade-text-content (r26:text-content-text v) (norm-annots-26 (r26:text-content-annotations v)) (r26:text-content-meta v))]
        [(r26:image-content? v)
         (facade-image-content (r26:image-content-data v) (r26:image-content-mime-type v) (norm-annots-26 (r26:image-content-annotations v)) (r26:image-content-meta v))]
        [(r26:audio-content? v)
         (facade-audio-content (r26:audio-content-data v) (r26:audio-content-mime-type v) (norm-annots-26 (r26:audio-content-annotations v)) (r26:audio-content-meta v))]
        [(r26:resource-link? v)
         (facade-resource-link (r26:resource-link-name v) (r26:resource-link-title v) (r26:resource-link-uri v)
                               (r26:resource-link-description v) (r26:resource-link-mime-type v)
                               (norm-annots-26 (r26:resource-link-annotations v)) (r26:resource-link-size v)
                               (opt-map-list (r26:resource-link-icons v) normalize-facade-icon-from-2026)
                               (r26:resource-link-meta v) (r26:resource-link-rest v))]
        [(r26:embedded-resource? v)
         (facade-embedded-resource (normalize-facade-resource-contents-from-2026 (r26:embedded-resource-resource v))
                                   (norm-annots-26 (r26:embedded-resource-annotations v)) (r26:embedded-resource-meta v))]
        [(r26:tool-use-content? v)
         (facade-tool-use-content (r26:tool-use-content-id v) (r26:tool-use-content-name v) (r26:tool-use-content-input v) (r26:tool-use-content-meta v))]
        [(r26:tool-result-content? v)
         (facade-tool-result-content (r26:tool-result-content-tool-use-id v)
                                     (map normalize-facade-content-block-from-2026 (r26:tool-result-content-content v))
                                     (r26:tool-result-content-structured-content v) (r26:tool-result-content-is-error v) (r26:tool-result-content-meta v))]
        [else (error 'normalize-facade-content-block-from-2026 "unknown content block")]))
(define (denormalize-facade-content-block-to-2025 v)
  (cond [(facade-text-content? v)
         (r25:text-content (facade-text-content-text v) (denorm-annots-25 (facade-text-content-annotations v)) (facade-text-content-meta v))]
        [(facade-image-content? v)
         (r25:image-content (facade-image-content-data v) (facade-image-content-mime-type v) (denorm-annots-25 (facade-image-content-annotations v)) (facade-image-content-meta v))]
        [(facade-audio-content? v)
         (r25:audio-content (facade-audio-content-data v) (facade-audio-content-mime-type v) (denorm-annots-25 (facade-audio-content-annotations v)) (facade-audio-content-meta v))]
        [(facade-resource-link? v)
         (r25:resource-link (facade-resource-link-name v) (facade-resource-link-title v) (facade-resource-link-uri v)
                            (facade-resource-link-description v) (facade-resource-link-mime-type v)
                            (denorm-annots-25 (facade-resource-link-annotations v)) (facade-resource-link-size v)
                            (opt-map-list (facade-resource-link-icons v) denormalize-facade-icon-to-2025)
                            (facade-resource-link-meta v) (facade-resource-link-rest v))]
        [(facade-embedded-resource? v)
         (r25:embedded-resource (denormalize-facade-resource-contents-to-2025 (facade-embedded-resource-resource v))
                                (denorm-annots-25 (facade-embedded-resource-annotations v)) (facade-embedded-resource-meta v))]
        [(facade-tool-use-content? v)
         (r25:tool-use-content (facade-tool-use-content-id v) (facade-tool-use-content-name v) (facade-tool-use-content-input v) (facade-tool-use-content-meta v))]
        [(facade-tool-result-content? v)
         (r25:tool-result-content (facade-tool-result-content-tool-use-id v)
                                  (map denormalize-facade-content-block-to-2025 (facade-tool-result-content-content v))
                                  (facade-tool-result-content-structured-content v) (facade-tool-result-content-is-error v) (facade-tool-result-content-meta v))]
        [else (error 'denormalize-facade-content-block-to-2025 "unknown content block")]))
(define (denormalize-facade-content-block-to-2026 v)
  (cond [(facade-text-content? v)
         (r26:text-content (facade-text-content-text v) (denorm-annots-26 (facade-text-content-annotations v)) (facade-text-content-meta v))]
        [(facade-image-content? v)
         (r26:image-content (facade-image-content-data v) (facade-image-content-mime-type v) (denorm-annots-26 (facade-image-content-annotations v)) (facade-image-content-meta v))]
        [(facade-audio-content? v)
         (r26:audio-content (facade-audio-content-data v) (facade-audio-content-mime-type v) (denorm-annots-26 (facade-audio-content-annotations v)) (facade-audio-content-meta v))]
        [(facade-resource-link? v)
         (r26:resource-link (facade-resource-link-name v) (facade-resource-link-title v) (facade-resource-link-uri v)
                            (facade-resource-link-description v) (facade-resource-link-mime-type v)
                            (denorm-annots-26 (facade-resource-link-annotations v)) (facade-resource-link-size v)
                            (opt-map-list (facade-resource-link-icons v) denormalize-facade-icon-to-2026)
                            (facade-resource-link-meta v) (facade-resource-link-rest v))]
        [(facade-embedded-resource? v)
         (r26:embedded-resource (denormalize-facade-resource-contents-to-2026 (facade-embedded-resource-resource v))
                                (denorm-annots-26 (facade-embedded-resource-annotations v)) (facade-embedded-resource-meta v))]
        [(facade-tool-use-content? v)
         (r26:tool-use-content (facade-tool-use-content-id v) (facade-tool-use-content-name v) (facade-tool-use-content-input v) (facade-tool-use-content-meta v))]
        [(facade-tool-result-content? v)
         (r26:tool-result-content (facade-tool-result-content-tool-use-id v)
                                  (map denormalize-facade-content-block-to-2026 (facade-tool-result-content-content v))
                                  (facade-tool-result-content-structured-content v) (facade-tool-result-content-is-error v) (facade-tool-result-content-meta v))]
        [else (error 'denormalize-facade-content-block-to-2026 "unknown content block")]))

;; sampling-message content can be a single block or a list of blocks.
(define (norm-smc-25 c) (if (list? c) (map normalize-facade-content-block-from-2025 c) (normalize-facade-content-block-from-2025 c)))
(define (norm-smc-26 c) (if (list? c) (map normalize-facade-content-block-from-2026 c) (normalize-facade-content-block-from-2026 c)))
(define (denorm-smc-25 c) (if (list? c) (map denormalize-facade-content-block-to-2025 c) (denormalize-facade-content-block-to-2025 c)))
(define (denorm-smc-26 c) (if (list? c) (map denormalize-facade-content-block-to-2026 c) (denormalize-facade-content-block-to-2026 c)))

;; --- facade-sampling-message (role content meta) ---
(struct facade-sampling-message (role content meta) #:transparent)
(define facade-sampling-message/c
  (struct/c facade-sampling-message role/c any/c (opt/c json-object?)))
(define (normalize-facade-sampling-message-from-2025 v)
  (facade-sampling-message (r25:sampling-message-role v) (norm-smc-25 (r25:sampling-message-content v)) (r25:sampling-message-meta v)))
(define (normalize-facade-sampling-message-from-2026 v)
  (facade-sampling-message (r26:sampling-message-role v) (norm-smc-26 (r26:sampling-message-content v)) (r26:sampling-message-meta v)))
(define (denormalize-facade-sampling-message-to-2025 v)
  (r25:sampling-message (facade-sampling-message-role v) (denorm-smc-25 (facade-sampling-message-content v)) (facade-sampling-message-meta v)))
(define (denormalize-facade-sampling-message-to-2026 v)
  (r26:sampling-message (facade-sampling-message-role v) (denorm-smc-26 (facade-sampling-message-content v)) (facade-sampling-message-meta v)))

;; --- facade-prompt-message (role content) ---
(struct facade-prompt-message (role content) #:transparent)
(define facade-prompt-message/c (struct/c facade-prompt-message role/c any/c))
(define (normalize-facade-prompt-message-from-2025 v)
  (facade-prompt-message (r25:prompt-message-role v) (norm-smc-25 (r25:prompt-message-content v))))
(define (normalize-facade-prompt-message-from-2026 v)
  (facade-prompt-message (r26:prompt-message-role v) (norm-smc-26 (r26:prompt-message-content v))))
(define (denormalize-facade-prompt-message-to-2025 v)
  (r25:prompt-message (facade-prompt-message-role v) (denorm-smc-25 (facade-prompt-message-content v))))
(define (denormalize-facade-prompt-message-to-2026 v)
  (r26:prompt-message (facade-prompt-message-role v) (denorm-smc-26 (facade-prompt-message-content v))))

;; --- facade-prompt-argument ---
(struct facade-prompt-argument (name title description required) #:transparent)
(define facade-prompt-argument/c
  (struct/c facade-prompt-argument string? (opt/c string?) (opt/c string?) (opt/c boolean?)))
(define (normalize-facade-prompt-argument-from-2025 v)
  (facade-prompt-argument (r25:prompt-argument-name v) (r25:prompt-argument-title v) (r25:prompt-argument-description v) (r25:prompt-argument-required v)))
(define (normalize-facade-prompt-argument-from-2026 v)
  (facade-prompt-argument (r26:prompt-argument-name v) (r26:prompt-argument-title v) (r26:prompt-argument-description v) (r26:prompt-argument-required v)))
(define (denormalize-facade-prompt-argument-to-2025 v)
  (r25:prompt-argument (facade-prompt-argument-name v) (facade-prompt-argument-title v) (facade-prompt-argument-description v) (facade-prompt-argument-required v)))
(define (denormalize-facade-prompt-argument-to-2026 v)
  (r26:prompt-argument (facade-prompt-argument-name v) (facade-prompt-argument-title v) (facade-prompt-argument-description v) (facade-prompt-argument-required v)))

;; --- facade-prompt ---
(struct facade-prompt (name title description arguments icons meta rest) #:transparent)
(define facade-prompt/c
  (struct/c facade-prompt string? (opt/c string?) (opt/c string?)
            (opt/c (listof facade-prompt-argument/c)) (opt/c (listof facade-icon/c))
            (opt/c json-object?) json-object?))
(define (normalize-facade-prompt-from-2025 v)
  (facade-prompt (r25:prompt-name v) (r25:prompt-title v) (r25:prompt-description v)
                 (opt-map-list (r25:prompt-arguments v) normalize-facade-prompt-argument-from-2025)
                 (opt-map-list (r25:prompt-icons v) normalize-facade-icon-from-2025)
                 (r25:prompt-meta v) (r25:prompt-rest v)))
(define (normalize-facade-prompt-from-2026 v)
  (facade-prompt (r26:prompt-name v) (r26:prompt-title v) (r26:prompt-description v)
                 (opt-map-list (r26:prompt-arguments v) normalize-facade-prompt-argument-from-2026)
                 (opt-map-list (r26:prompt-icons v) normalize-facade-icon-from-2026)
                 (r26:prompt-meta v) (r26:prompt-rest v)))
(define (denormalize-facade-prompt-to-2025 v)
  (r25:prompt (facade-prompt-name v) (facade-prompt-title v) (facade-prompt-description v)
              (opt-map-list (facade-prompt-arguments v) denormalize-facade-prompt-argument-to-2025)
              (opt-map-list (facade-prompt-icons v) denormalize-facade-icon-to-2025)
              (facade-prompt-meta v) (facade-prompt-rest v)))
(define (denormalize-facade-prompt-to-2026 v)
  (r26:prompt (facade-prompt-name v) (facade-prompt-title v) (facade-prompt-description v)
              (opt-map-list (facade-prompt-arguments v) denormalize-facade-prompt-argument-to-2026)
              (opt-map-list (facade-prompt-icons v) denormalize-facade-icon-to-2026)
              (facade-prompt-meta v) (facade-prompt-rest v)))

;; --- facade-resource / facade-resource-template ---
(struct facade-resource (name title uri description mime-type annotations size icons meta rest) #:transparent)
(define facade-resource/c
  (struct/c facade-resource string? (opt/c string?) string? (opt/c string?) (opt/c string?)
            (opt/c facade-annotations/c) (opt/c real?) (opt/c (listof facade-icon/c))
            (opt/c json-object?) json-object?))
(define (normalize-facade-resource-from-2025 v)
  (facade-resource (r25:resource-name v) (r25:resource-title v) (r25:resource-uri v) (r25:resource-description v)
                   (r25:resource-mime-type v) (norm-annots-25 (r25:resource-annotations v)) (r25:resource-size v)
                   (opt-map-list (r25:resource-icons v) normalize-facade-icon-from-2025) (r25:resource-meta v) (r25:resource-rest v)))
(define (normalize-facade-resource-from-2026 v)
  (facade-resource (r26:resource-name v) (r26:resource-title v) (r26:resource-uri v) (r26:resource-description v)
                   (r26:resource-mime-type v) (norm-annots-26 (r26:resource-annotations v)) (r26:resource-size v)
                   (opt-map-list (r26:resource-icons v) normalize-facade-icon-from-2026) (r26:resource-meta v) (r26:resource-rest v)))
(define (denormalize-facade-resource-to-2025 v)
  (r25:resource (facade-resource-name v) (facade-resource-title v) (facade-resource-uri v) (facade-resource-description v)
                (facade-resource-mime-type v) (denorm-annots-25 (facade-resource-annotations v)) (facade-resource-size v)
                (opt-map-list (facade-resource-icons v) denormalize-facade-icon-to-2025) (facade-resource-meta v) (facade-resource-rest v)))
(define (denormalize-facade-resource-to-2026 v)
  (r26:resource (facade-resource-name v) (facade-resource-title v) (facade-resource-uri v) (facade-resource-description v)
                (facade-resource-mime-type v) (denorm-annots-26 (facade-resource-annotations v)) (facade-resource-size v)
                (opt-map-list (facade-resource-icons v) denormalize-facade-icon-to-2026) (facade-resource-meta v) (facade-resource-rest v)))

(struct facade-resource-template (name title uri-template description mime-type annotations icons meta rest) #:transparent)
(define facade-resource-template/c
  (struct/c facade-resource-template string? (opt/c string?) string? (opt/c string?) (opt/c string?)
            (opt/c facade-annotations/c) (opt/c (listof facade-icon/c)) (opt/c json-object?) json-object?))
(define (normalize-facade-resource-template-from-2025 v)
  (facade-resource-template (r25:resource-template-name v) (r25:resource-template-title v) (r25:resource-template-uri-template v)
                            (r25:resource-template-description v) (r25:resource-template-mime-type v)
                            (norm-annots-25 (r25:resource-template-annotations v))
                            (opt-map-list (r25:resource-template-icons v) normalize-facade-icon-from-2025)
                            (r25:resource-template-meta v) (r25:resource-template-rest v)))
(define (normalize-facade-resource-template-from-2026 v)
  (facade-resource-template (r26:resource-template-name v) (r26:resource-template-title v) (r26:resource-template-uri-template v)
                            (r26:resource-template-description v) (r26:resource-template-mime-type v)
                            (norm-annots-26 (r26:resource-template-annotations v))
                            (opt-map-list (r26:resource-template-icons v) normalize-facade-icon-from-2026)
                            (r26:resource-template-meta v) (r26:resource-template-rest v)))
(define (denormalize-facade-resource-template-to-2025 v)
  (r25:resource-template (facade-resource-template-name v) (facade-resource-template-title v) (facade-resource-template-uri-template v)
                         (facade-resource-template-description v) (facade-resource-template-mime-type v)
                         (denorm-annots-25 (facade-resource-template-annotations v))
                         (opt-map-list (facade-resource-template-icons v) denormalize-facade-icon-to-2025)
                         (facade-resource-template-meta v) (facade-resource-template-rest v)))
(define (denormalize-facade-resource-template-to-2026 v)
  (r26:resource-template (facade-resource-template-name v) (facade-resource-template-title v) (facade-resource-template-uri-template v)
                         (facade-resource-template-description v) (facade-resource-template-mime-type v)
                         (denorm-annots-26 (facade-resource-template-annotations v))
                         (opt-map-list (facade-resource-template-icons v) denormalize-facade-icon-to-2026)
                         (facade-resource-template-meta v) (facade-resource-template-rest v)))

;; --- facade-tool-annotations (identical) ---
(struct facade-tool-annotations (title read-only-hint destructive-hint idempotent-hint open-world-hint) #:transparent)
(define facade-tool-annotations/c
  (struct/c facade-tool-annotations (opt/c string?) (opt/c boolean?) (opt/c boolean?) (opt/c boolean?) (opt/c boolean?)))
(define (normalize-facade-tool-annotations-from-2025 v)
  (facade-tool-annotations (r25:tool-annotations-title v) (r25:tool-annotations-read-only-hint v) (r25:tool-annotations-destructive-hint v) (r25:tool-annotations-idempotent-hint v) (r25:tool-annotations-open-world-hint v)))
(define (normalize-facade-tool-annotations-from-2026 v)
  (facade-tool-annotations (r26:tool-annotations-title v) (r26:tool-annotations-read-only-hint v) (r26:tool-annotations-destructive-hint v) (r26:tool-annotations-idempotent-hint v) (r26:tool-annotations-open-world-hint v)))
(define (denormalize-facade-tool-annotations-to-2025 v)
  (r25:tool-annotations (facade-tool-annotations-title v) (facade-tool-annotations-read-only-hint v) (facade-tool-annotations-destructive-hint v) (facade-tool-annotations-idempotent-hint v) (facade-tool-annotations-open-world-hint v)))
(define (denormalize-facade-tool-annotations-to-2026 v)
  (r26:tool-annotations (facade-tool-annotations-title v) (facade-tool-annotations-read-only-hint v) (facade-tool-annotations-destructive-hint v) (facade-tool-annotations-idempotent-hint v) (facade-tool-annotations-open-world-hint v)))
(define (norm-ta-25 v) (if (present? v) (normalize-facade-tool-annotations-from-2025 v) absent))
(define (norm-ta-26 v) (if (present? v) (normalize-facade-tool-annotations-from-2026 v) absent))
(define (denorm-ta-25 v) (if (present? v) (denormalize-facade-tool-annotations-to-2025 v) absent))
(define (denorm-ta-26 v) (if (present? v) (denormalize-facade-tool-annotations-to-2026 v) absent))

;; --- sampling helpers: model-preferences / model-hint / tool-choice ---
(struct facade-model-hint (name) #:transparent)
(define facade-model-hint/c (struct/c facade-model-hint (opt/c string?)))
(struct facade-model-preferences (hints cost-priority speed-priority intelligence-priority) #:transparent)
(define facade-model-preferences/c
  (struct/c facade-model-preferences (opt/c (listof facade-model-hint/c)) (opt/c real?) (opt/c real?) (opt/c real?)))
(struct facade-tool-choice (mode) #:transparent)
(define facade-tool-choice/c (struct/c facade-tool-choice string?))
(define (normalize-facade-model-hint-from-2025 v) (facade-model-hint (r25:model-hint-name v)))
(define (normalize-facade-model-hint-from-2026 v) (facade-model-hint (r26:model-hint-name v)))
(define (denormalize-facade-model-hint-to-2025 v) (r25:model-hint (facade-model-hint-name v)))
(define (denormalize-facade-model-hint-to-2026 v) (r26:model-hint (facade-model-hint-name v)))
(define (normalize-facade-model-preferences-from-2025 v)
  (facade-model-preferences (opt-map-list (r25:model-preferences-hints v) normalize-facade-model-hint-from-2025)
                            (r25:model-preferences-cost-priority v) (r25:model-preferences-speed-priority v) (r25:model-preferences-intelligence-priority v)))
(define (normalize-facade-model-preferences-from-2026 v)
  (facade-model-preferences (opt-map-list (r26:model-preferences-hints v) normalize-facade-model-hint-from-2026)
                            (r26:model-preferences-cost-priority v) (r26:model-preferences-speed-priority v) (r26:model-preferences-intelligence-priority v)))
(define (denormalize-facade-model-preferences-to-2025 v)
  (r25:model-preferences (opt-map-list (facade-model-preferences-hints v) denormalize-facade-model-hint-to-2025)
                         (facade-model-preferences-cost-priority v) (facade-model-preferences-speed-priority v) (facade-model-preferences-intelligence-priority v)))
(define (denormalize-facade-model-preferences-to-2026 v)
  (r26:model-preferences (opt-map-list (facade-model-preferences-hints v) denormalize-facade-model-hint-to-2026)
                         (facade-model-preferences-cost-priority v) (facade-model-preferences-speed-priority v) (facade-model-preferences-intelligence-priority v)))
(define (normalize-facade-tool-choice-from-2025 v) (facade-tool-choice (r25:tool-choice-mode v)))
(define (normalize-facade-tool-choice-from-2026 v) (facade-tool-choice (r26:tool-choice-mode v)))
(define (denormalize-facade-tool-choice-to-2025 v) (r25:tool-choice (facade-tool-choice-mode v)))
(define (denormalize-facade-tool-choice-to-2026 v) (r26:tool-choice (facade-tool-choice-mode v)))
(define (norm-mp-25 v) (if (present? v) (normalize-facade-model-preferences-from-2025 v) absent))
(define (norm-mp-26 v) (if (present? v) (normalize-facade-model-preferences-from-2026 v) absent))
(define (denorm-mp-25 v) (if (present? v) (denormalize-facade-model-preferences-to-2025 v) absent))
(define (denorm-mp-26 v) (if (present? v) (denormalize-facade-model-preferences-to-2026 v) absent))
(define (norm-tc-25 v) (if (present? v) (normalize-facade-tool-choice-from-2025 v) absent))
(define (norm-tc-26 v) (if (present? v) (normalize-facade-tool-choice-from-2026 v) absent))
(define (denorm-tc-25 v) (if (present? v) (denormalize-facade-tool-choice-to-2025 v) absent))
(define (denorm-tc-26 v) (if (present? v) (denormalize-facade-tool-choice-to-2026 v) absent))

;; --- completion refs (identical) ---
(struct facade-resource-template-reference (uri) #:transparent)
(define facade-resource-template-reference/c (struct/c facade-resource-template-reference string?))
(struct facade-prompt-reference (name title) #:transparent)
(define facade-prompt-reference/c (struct/c facade-prompt-reference string? (opt/c string?)))

;; --- facade-root (uri name meta) — identical both revs ---
(struct facade-root (uri name meta) #:transparent)
(define facade-root/c (struct/c facade-root string? (opt/c string?) (opt/c json-object?)))
(define (normalize-facade-root-from-2025 v) (facade-root (r25:root-uri v) (r25:root-name v) (r25:root-meta v)))
(define (normalize-facade-root-from-2026 v) (facade-root (r26:root-uri v) (r26:root-name v) (r26:root-meta v)))
(define (denormalize-facade-root-to-2025 v) (r25:root (facade-root-uri v) (facade-root-name v) (facade-root-meta v)))
(define (denormalize-facade-root-to-2026 v) (r26:root (facade-root-uri v) (facade-root-name v) (facade-root-meta v)))

;; ============================================================================
;; GROUP 1 — facade-tool (2025 has `execution`; 2026 lacks it).
;; NOTE: 2025 accessor is `tool-exec` / `tool-annots` (not -execution/-annotations).
;; ============================================================================
(struct facade-tool-execution (task-support) #:transparent)
(define facade-tool-execution/c (struct/c facade-tool-execution (opt/c string?)))
(define (normalize-facade-tool-execution-from-2025 v)
  (facade-tool-execution (r25:tool-execution-task-support v)))
(define (denormalize-facade-tool-execution-to-2025 v)
  (r25:tool-execution (facade-tool-execution-task-support v)))

;; NOTE: field is named `exec` (not `execution`) to avoid colliding with the
;; `facade-tool-execution` struct's constructor accessor.
(struct facade-tool (name title description input-schema exec output-schema annots icons meta rest) #:transparent)
(define facade-tool/c
  (struct/c facade-tool string? (opt/c string?) (opt/c string?) json-object?
            (opt/c facade-tool-execution/c) (opt/c json-object?) (opt/c facade-tool-annotations/c)
            (opt/c (listof facade-icon/c)) (opt/c json-object?) json-object?))
(define (normalize-facade-tool-from-2025 v)
  (facade-tool (r25:tool-name v) (r25:tool-title v) (r25:tool-description v) (r25:tool-input-schema v)
               (let ([e (r25:tool-exec v)]) (if (present? e) (normalize-facade-tool-execution-from-2025 e) absent))
               (r25:tool-output-schema v) (norm-ta-25 (r25:tool-annots v))
               (opt-map-list (r25:tool-icons v) normalize-facade-icon-from-2025) (r25:tool-meta v) (r25:tool-rest v)))
(define (normalize-facade-tool-from-2026 v)
  (facade-tool (r26:tool-name v) (r26:tool-title v) (r26:tool-description v) (r26:tool-input-schema v)
               absent-field            ; execution: 2025-only
               (r26:tool-output-schema v) (norm-ta-26 (r26:tool-annots v))
               (opt-map-list (r26:tool-icons v) normalize-facade-icon-from-2026) (r26:tool-meta v) (r26:tool-rest v)))
(define (denormalize-facade-tool-to-2025 v)
  (r25:tool (facade-tool-name v) (facade-tool-title v) (facade-tool-description v) (facade-tool-input-schema v)
            (let ([e (facade-tool-exec v)]) (if (present? e) (denormalize-facade-tool-execution-to-2025 e) absent))
            (facade-tool-output-schema v) (denorm-ta-25 (facade-tool-annots v))
            (opt-map-list (facade-tool-icons v) denormalize-facade-icon-to-2025) (facade-tool-meta v) (facade-tool-rest v)))
(define (denormalize-facade-tool-to-2026 v)
  (refuse-if-present 'denormalize-facade-tool-to-2026 'execution (facade-tool-exec v) '2026-07-28)
  (r26:tool (facade-tool-name v) (facade-tool-title v) (facade-tool-description v) (facade-tool-input-schema v)
            (facade-tool-output-schema v) (denorm-ta-26 (facade-tool-annots v))
            (opt-map-list (facade-tool-icons v) denormalize-facade-icon-to-2026) (facade-tool-meta v) (facade-tool-rest v)))

;; Helper: normalize a list of revision tools.
(define (norm-tools-25 xs) (map normalize-facade-tool-from-2025 xs))
(define (norm-tools-26 xs) (map normalize-facade-tool-from-2026 xs))
(define (denorm-tools-25 xs) (map denormalize-facade-tool-to-2025 xs))
(define (denorm-tools-26 xs) (map denormalize-facade-tool-to-2026 xs))

;; ============================================================================
;; GROUP 2 — Results: base + result-type / ttl-ms / cache-scope (all 2026-only).
;; `rest` is SHARED and NOT revision-gated (loose-result semantics identical):
;; it passes through on denormalize to EITHER revision and is never refused.
;; ============================================================================

;; --- facade-list-tools-result ---
(struct facade-list-tools-result (tools next-cursor ttl-ms cache-scope meta result-type rest) #:transparent)
(define facade-list-tools-result/c
  (struct/c facade-list-tools-result (listof facade-tool/c) (opt/c cursor/c) (opt/c real?)
            (opt/c cache-scope/c) (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (normalize-facade-list-tools-result-from-2025 v)
  (facade-list-tools-result (norm-tools-25 (r25:list-tools-result-tools v)) (r25:list-tools-result-next-cursor v)
                            absent-field absent-field (r25:list-tools-result-meta v) absent-field (r25:list-tools-result-rest v)))
(define (normalize-facade-list-tools-result-from-2026 v)
  (facade-list-tools-result (norm-tools-26 (r26:list-tools-result-tools v)) (r26:list-tools-result-next-cursor v)
                            (r26:list-tools-result-ttl-ms v) (r26:list-tools-result-cache-scope v)
                            (r26:list-tools-result-meta v) (r26:list-tools-result-result-type v) (r26:list-tools-result-rest v)))
(define (denormalize-facade-list-tools-result-to-2025 v)
  (refuse-if-present 'denormalize-facade-list-tools-result-to-2025 'ttl-ms (facade-list-tools-result-ttl-ms v) '2025-11-25)
  (refuse-if-present 'denormalize-facade-list-tools-result-to-2025 'cache-scope (facade-list-tools-result-cache-scope v) '2025-11-25)
  (refuse-if-present 'denormalize-facade-list-tools-result-to-2025 'result-type (facade-list-tools-result-result-type v) '2025-11-25)
  (r25:list-tools-result (denorm-tools-25 (facade-list-tools-result-tools v)) (facade-list-tools-result-next-cursor v)
                         (facade-list-tools-result-meta v) (facade-list-tools-result-rest v)))
(define (denormalize-facade-list-tools-result-to-2026 v)
  (r26:list-tools-result (denorm-tools-26 (facade-list-tools-result-tools v)) (facade-list-tools-result-next-cursor v)
                         (facade-list-tools-result-ttl-ms v) (facade-list-tools-result-cache-scope v)
                         (facade-list-tools-result-meta v) (facade-list-tools-result-result-type v) (facade-list-tools-result-rest v)))

;; --- facade-call-tool-result ---
(struct facade-call-tool-result (content structured-content is-error meta result-type rest) #:transparent)
(define facade-call-tool-result/c
  (struct/c facade-call-tool-result (listof facade-content-block/c) (opt/c json-object?)
            (opt/c boolean?) (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (normalize-facade-call-tool-result-from-2025 v)
  (facade-call-tool-result (map normalize-facade-content-block-from-2025 (r25:call-tool-result-content v))
                           (r25:call-tool-result-structured-content v) (r25:call-tool-result-is-error v)
                           (r25:call-tool-result-meta v) absent-field (r25:call-tool-result-rest v)))
(define (normalize-facade-call-tool-result-from-2026 v)
  (facade-call-tool-result (map normalize-facade-content-block-from-2026 (r26:call-tool-result-content v))
                           (r26:call-tool-result-structured-content v) (r26:call-tool-result-is-error v)
                           (r26:call-tool-result-meta v) (r26:call-tool-result-result-type v) (r26:call-tool-result-rest v)))
(define (denormalize-facade-call-tool-result-to-2025 v)
  (refuse-if-present 'denormalize-facade-call-tool-result-to-2025 'result-type (facade-call-tool-result-result-type v) '2025-11-25)
  (r25:call-tool-result (map denormalize-facade-content-block-to-2025 (facade-call-tool-result-content v))
                        (facade-call-tool-result-structured-content v) (facade-call-tool-result-is-error v)
                        (facade-call-tool-result-meta v) (facade-call-tool-result-rest v)))
(define (denormalize-facade-call-tool-result-to-2026 v)
  (r26:call-tool-result (map denormalize-facade-content-block-to-2026 (facade-call-tool-result-content v))
                        (facade-call-tool-result-structured-content v) (facade-call-tool-result-is-error v)
                        (facade-call-tool-result-meta v) (facade-call-tool-result-result-type v) (facade-call-tool-result-rest v)))

;; --- facade-list-resources-result ---
(struct facade-list-resources-result (resources next-cursor ttl-ms cache-scope meta result-type rest) #:transparent)
(define facade-list-resources-result/c
  (struct/c facade-list-resources-result (listof facade-resource/c) (opt/c cursor/c) (opt/c real?)
            (opt/c cache-scope/c) (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (normalize-facade-list-resources-result-from-2025 v)
  (facade-list-resources-result (map normalize-facade-resource-from-2025 (r25:list-resources-result-resources v)) (r25:list-resources-result-next-cursor v)
                                absent-field absent-field (r25:list-resources-result-meta v) absent-field (r25:list-resources-result-rest v)))
(define (normalize-facade-list-resources-result-from-2026 v)
  (facade-list-resources-result (map normalize-facade-resource-from-2026 (r26:list-resources-result-resources v)) (r26:list-resources-result-next-cursor v)
                                (r26:list-resources-result-ttl-ms v) (r26:list-resources-result-cache-scope v)
                                (r26:list-resources-result-meta v) (r26:list-resources-result-result-type v) (r26:list-resources-result-rest v)))
(define (denormalize-facade-list-resources-result-to-2025 v)
  (refuse-if-present 'denormalize-facade-list-resources-result-to-2025 'ttl-ms (facade-list-resources-result-ttl-ms v) '2025-11-25)
  (refuse-if-present 'denormalize-facade-list-resources-result-to-2025 'cache-scope (facade-list-resources-result-cache-scope v) '2025-11-25)
  (refuse-if-present 'denormalize-facade-list-resources-result-to-2025 'result-type (facade-list-resources-result-result-type v) '2025-11-25)
  (r25:list-resources-result (map denormalize-facade-resource-to-2025 (facade-list-resources-result-resources v)) (facade-list-resources-result-next-cursor v)
                             (facade-list-resources-result-meta v) (facade-list-resources-result-rest v)))
(define (denormalize-facade-list-resources-result-to-2026 v)
  (r26:list-resources-result (map denormalize-facade-resource-to-2026 (facade-list-resources-result-resources v)) (facade-list-resources-result-next-cursor v)
                             (facade-list-resources-result-ttl-ms v) (facade-list-resources-result-cache-scope v)
                             (facade-list-resources-result-meta v) (facade-list-resources-result-result-type v) (facade-list-resources-result-rest v)))

;; --- facade-list-resource-templates-result ---
(struct facade-list-resource-templates-result (resource-templates next-cursor ttl-ms cache-scope meta result-type rest) #:transparent)
(define facade-list-resource-templates-result/c
  (struct/c facade-list-resource-templates-result (listof facade-resource-template/c) (opt/c cursor/c) (opt/c real?)
            (opt/c cache-scope/c) (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (normalize-facade-list-resource-templates-result-from-2025 v)
  (facade-list-resource-templates-result (map normalize-facade-resource-template-from-2025 (r25:list-resource-templates-result-resource-templates v)) (r25:list-resource-templates-result-next-cursor v)
                                         absent-field absent-field (r25:list-resource-templates-result-meta v) absent-field (r25:list-resource-templates-result-rest v)))
(define (normalize-facade-list-resource-templates-result-from-2026 v)
  (facade-list-resource-templates-result (map normalize-facade-resource-template-from-2026 (r26:list-resource-templates-result-resource-templates v)) (r26:list-resource-templates-result-next-cursor v)
                                         (r26:list-resource-templates-result-ttl-ms v) (r26:list-resource-templates-result-cache-scope v)
                                         (r26:list-resource-templates-result-meta v) (r26:list-resource-templates-result-result-type v) (r26:list-resource-templates-result-rest v)))
(define (denormalize-facade-list-resource-templates-result-to-2025 v)
  (refuse-if-present 'denormalize-facade-list-resource-templates-result-to-2025 'ttl-ms (facade-list-resource-templates-result-ttl-ms v) '2025-11-25)
  (refuse-if-present 'denormalize-facade-list-resource-templates-result-to-2025 'cache-scope (facade-list-resource-templates-result-cache-scope v) '2025-11-25)
  (refuse-if-present 'denormalize-facade-list-resource-templates-result-to-2025 'result-type (facade-list-resource-templates-result-result-type v) '2025-11-25)
  (r25:list-resource-templates-result (map denormalize-facade-resource-template-to-2025 (facade-list-resource-templates-result-resource-templates v)) (facade-list-resource-templates-result-next-cursor v)
                                      (facade-list-resource-templates-result-meta v) (facade-list-resource-templates-result-rest v)))
(define (denormalize-facade-list-resource-templates-result-to-2026 v)
  (r26:list-resource-templates-result (map denormalize-facade-resource-template-to-2026 (facade-list-resource-templates-result-resource-templates v)) (facade-list-resource-templates-result-next-cursor v)
                                      (facade-list-resource-templates-result-ttl-ms v) (facade-list-resource-templates-result-cache-scope v)
                                      (facade-list-resource-templates-result-meta v) (facade-list-resource-templates-result-result-type v) (facade-list-resource-templates-result-rest v)))

;; --- facade-list-prompts-result ---
(struct facade-list-prompts-result (prompts next-cursor ttl-ms cache-scope meta result-type rest) #:transparent)
(define facade-list-prompts-result/c
  (struct/c facade-list-prompts-result (listof facade-prompt/c) (opt/c cursor/c) (opt/c real?)
            (opt/c cache-scope/c) (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (normalize-facade-list-prompts-result-from-2025 v)
  (facade-list-prompts-result (map normalize-facade-prompt-from-2025 (r25:list-prompts-result-prompts v)) (r25:list-prompts-result-next-cursor v)
                              absent-field absent-field (r25:list-prompts-result-meta v) absent-field (r25:list-prompts-result-rest v)))
(define (normalize-facade-list-prompts-result-from-2026 v)
  (facade-list-prompts-result (map normalize-facade-prompt-from-2026 (r26:list-prompts-result-prompts v)) (r26:list-prompts-result-next-cursor v)
                              (r26:list-prompts-result-ttl-ms v) (r26:list-prompts-result-cache-scope v)
                              (r26:list-prompts-result-meta v) (r26:list-prompts-result-result-type v) (r26:list-prompts-result-rest v)))
(define (denormalize-facade-list-prompts-result-to-2025 v)
  (refuse-if-present 'denormalize-facade-list-prompts-result-to-2025 'ttl-ms (facade-list-prompts-result-ttl-ms v) '2025-11-25)
  (refuse-if-present 'denormalize-facade-list-prompts-result-to-2025 'cache-scope (facade-list-prompts-result-cache-scope v) '2025-11-25)
  (refuse-if-present 'denormalize-facade-list-prompts-result-to-2025 'result-type (facade-list-prompts-result-result-type v) '2025-11-25)
  (r25:list-prompts-result (map denormalize-facade-prompt-to-2025 (facade-list-prompts-result-prompts v)) (facade-list-prompts-result-next-cursor v)
                           (facade-list-prompts-result-meta v) (facade-list-prompts-result-rest v)))
(define (denormalize-facade-list-prompts-result-to-2026 v)
  (r26:list-prompts-result (map denormalize-facade-prompt-to-2026 (facade-list-prompts-result-prompts v)) (facade-list-prompts-result-next-cursor v)
                           (facade-list-prompts-result-ttl-ms v) (facade-list-prompts-result-cache-scope v)
                           (facade-list-prompts-result-meta v) (facade-list-prompts-result-result-type v) (facade-list-prompts-result-rest v)))

;; --- facade-read-resource-result (NOTE: 2026 adds next-cursor too) ---
(struct facade-read-resource-result (contents next-cursor ttl-ms cache-scope meta result-type rest) #:transparent)
(define facade-read-resource-result/c
  (struct/c facade-read-resource-result (listof facade-resource-contents/c) (opt/c cursor/c) (opt/c real?)
            (opt/c cache-scope/c) (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (normalize-facade-read-resource-result-from-2025 v)
  (facade-read-resource-result (map normalize-facade-resource-contents-from-2025 (r25:read-resource-result-contents v))
                               absent-field absent-field absent-field (r25:read-resource-result-meta v) absent-field (r25:read-resource-result-rest v)))
(define (normalize-facade-read-resource-result-from-2026 v)
  (facade-read-resource-result (map normalize-facade-resource-contents-from-2026 (r26:read-resource-result-contents v))
                               (r26:read-resource-result-next-cursor v)
                               (r26:read-resource-result-ttl-ms v) (r26:read-resource-result-cache-scope v)
                               (r26:read-resource-result-meta v) (r26:read-resource-result-result-type v) (r26:read-resource-result-rest v)))
(define (denormalize-facade-read-resource-result-to-2025 v)
  (refuse-if-present 'denormalize-facade-read-resource-result-to-2025 'next-cursor (facade-read-resource-result-next-cursor v) '2025-11-25)
  (refuse-if-present 'denormalize-facade-read-resource-result-to-2025 'ttl-ms (facade-read-resource-result-ttl-ms v) '2025-11-25)
  (refuse-if-present 'denormalize-facade-read-resource-result-to-2025 'cache-scope (facade-read-resource-result-cache-scope v) '2025-11-25)
  (refuse-if-present 'denormalize-facade-read-resource-result-to-2025 'result-type (facade-read-resource-result-result-type v) '2025-11-25)
  (r25:read-resource-result (map denormalize-facade-resource-contents-to-2025 (facade-read-resource-result-contents v))
                            (facade-read-resource-result-meta v) (facade-read-resource-result-rest v)))
(define (denormalize-facade-read-resource-result-to-2026 v)
  (r26:read-resource-result (map denormalize-facade-resource-contents-to-2026 (facade-read-resource-result-contents v))
                            (facade-read-resource-result-next-cursor v)
                            (facade-read-resource-result-ttl-ms v) (facade-read-resource-result-cache-scope v)
                            (facade-read-resource-result-meta v) (facade-read-resource-result-result-type v) (facade-read-resource-result-rest v)))

;; --- facade-get-prompt-result ---
(struct facade-get-prompt-result (description messages meta result-type rest) #:transparent)
(define facade-get-prompt-result/c
  (struct/c facade-get-prompt-result (opt/c string?) (listof facade-prompt-message/c) (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (normalize-facade-get-prompt-result-from-2025 v)
  (facade-get-prompt-result (r25:get-prompt-result-description v) (map normalize-facade-prompt-message-from-2025 (r25:get-prompt-result-messages v))
                            (r25:get-prompt-result-meta v) absent-field (r25:get-prompt-result-rest v)))
(define (normalize-facade-get-prompt-result-from-2026 v)
  (facade-get-prompt-result (r26:get-prompt-result-description v) (map normalize-facade-prompt-message-from-2026 (r26:get-prompt-result-messages v))
                            (r26:get-prompt-result-meta v) (r26:get-prompt-result-result-type v) (r26:get-prompt-result-rest v)))
(define (denormalize-facade-get-prompt-result-to-2025 v)
  (refuse-if-present 'denormalize-facade-get-prompt-result-to-2025 'result-type (facade-get-prompt-result-result-type v) '2025-11-25)
  (r25:get-prompt-result (facade-get-prompt-result-description v) (map denormalize-facade-prompt-message-to-2025 (facade-get-prompt-result-messages v))
                         (facade-get-prompt-result-meta v) (facade-get-prompt-result-rest v)))
(define (denormalize-facade-get-prompt-result-to-2026 v)
  (r26:get-prompt-result (facade-get-prompt-result-description v) (map denormalize-facade-prompt-message-to-2026 (facade-get-prompt-result-messages v))
                         (facade-get-prompt-result-meta v) (facade-get-prompt-result-result-type v) (facade-get-prompt-result-rest v)))

;; --- facade-complete-result ---
(struct facade-complete-result (completion meta result-type rest) #:transparent)
(define facade-complete-result/c
  (struct/c facade-complete-result json-object? (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (normalize-facade-complete-result-from-2025 v)
  (facade-complete-result (r25:complete-result-completion v) (r25:complete-result-meta v) absent-field (r25:complete-result-rest v)))
(define (normalize-facade-complete-result-from-2026 v)
  (facade-complete-result (r26:complete-result-completion v) (r26:complete-result-meta v) (r26:complete-result-result-type v) (r26:complete-result-rest v)))
(define (denormalize-facade-complete-result-to-2025 v)
  (refuse-if-present 'denormalize-facade-complete-result-to-2025 'result-type (facade-complete-result-result-type v) '2025-11-25)
  (r25:complete-result (facade-complete-result-completion v) (facade-complete-result-meta v) (facade-complete-result-rest v)))
(define (denormalize-facade-complete-result-to-2026 v)
  (r26:complete-result (facade-complete-result-completion v) (facade-complete-result-meta v) (facade-complete-result-result-type v) (facade-complete-result-rest v)))

;; --- facade-create-message-result ---
(struct facade-create-message-result (role content model stop-reason meta result-type rest) #:transparent)
(define facade-create-message-result/c
  (struct/c facade-create-message-result role/c any/c string? (opt/c string?) (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (normalize-facade-create-message-result-from-2025 v)
  (facade-create-message-result (r25:create-message-result-role v) (norm-smc-25 (r25:create-message-result-content v))
                                (r25:create-message-result-model v) (r25:create-message-result-stop-reason v)
                                (r25:create-message-result-meta v) absent-field (r25:create-message-result-rest v)))
(define (normalize-facade-create-message-result-from-2026 v)
  (facade-create-message-result (r26:create-message-result-role v) (norm-smc-26 (r26:create-message-result-content v))
                                (r26:create-message-result-model v) (r26:create-message-result-stop-reason v)
                                (r26:create-message-result-meta v) (r26:create-message-result-result-type v) (r26:create-message-result-rest v)))
(define (denormalize-facade-create-message-result-to-2025 v)
  (refuse-if-present 'denormalize-facade-create-message-result-to-2025 'result-type (facade-create-message-result-result-type v) '2025-11-25)
  (r25:create-message-result (facade-create-message-result-role v) (denorm-smc-25 (facade-create-message-result-content v))
                             (facade-create-message-result-model v) (facade-create-message-result-stop-reason v)
                             (facade-create-message-result-meta v) (facade-create-message-result-rest v)))
(define (denormalize-facade-create-message-result-to-2026 v)
  (r26:create-message-result (facade-create-message-result-role v) (denorm-smc-26 (facade-create-message-result-content v))
                             (facade-create-message-result-model v) (facade-create-message-result-stop-reason v)
                             (facade-create-message-result-meta v) (facade-create-message-result-result-type v) (facade-create-message-result-rest v)))

;; --- facade-elicit-result (action content meta + result-type 2026-only + rest) ---
(struct facade-elicit-result (action content meta result-type rest) #:transparent)
(define facade-elicit-result/c
  (struct/c facade-elicit-result string? (opt/c json-object?) (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (normalize-facade-elicit-result-from-2025 v)
  (facade-elicit-result (r25:elicit-result-action v) (r25:elicit-result-content v) (r25:elicit-result-meta v) absent-field (r25:elicit-result-rest v)))
(define (normalize-facade-elicit-result-from-2026 v)
  (facade-elicit-result (r26:elicit-result-action v) (r26:elicit-result-content v) (r26:elicit-result-meta v) (r26:elicit-result-result-type v) (r26:elicit-result-rest v)))
(define (denormalize-facade-elicit-result-to-2025 v)
  (refuse-if-present 'denormalize-facade-elicit-result-to-2025 'result-type (facade-elicit-result-result-type v) '2025-11-25)
  (r25:elicit-result (facade-elicit-result-action v) (facade-elicit-result-content v) (facade-elicit-result-meta v) (facade-elicit-result-rest v)))
(define (denormalize-facade-elicit-result-to-2026 v)
  (r26:elicit-result (facade-elicit-result-action v) (facade-elicit-result-content v) (facade-elicit-result-meta v) (facade-elicit-result-result-type v) (facade-elicit-result-rest v)))

;; ============================================================================
;; GROUP 3 — facade-list-roots-result (BARE in 2026; 2025 has meta + rest).
;; meta and rest are BOTH 2025-only (2026 is bare {roots}).
;; ============================================================================
(struct facade-list-roots-result (roots meta rest) #:transparent)
(define facade-list-roots-result/c
  (struct/c facade-list-roots-result (listof facade-root/c) (opt/c json-object?) (opt/c json-object?)))
(define (normalize-facade-list-roots-result-from-2025 v)
  (facade-list-roots-result (map normalize-facade-root-from-2025 (r25:list-roots-result-roots v))
                            (r25:list-roots-result-meta v) (r25:list-roots-result-rest v)))
(define (normalize-facade-list-roots-result-from-2026 v)
  (facade-list-roots-result (map normalize-facade-root-from-2026 (r26:list-roots-result-roots v))
                            absent-field absent-field))  ; bare in 2026
(define (denormalize-facade-list-roots-result-to-2025 v)
  ;; rest is 2025-only here; if absent, supply an empty hasheq (2025 struct requires a hash).
  (r25:list-roots-result (map denormalize-facade-root-to-2025 (facade-list-roots-result-roots v))
                         (facade-list-roots-result-meta v)
                         (let ([r (facade-list-roots-result-rest v)]) (if (present? r) r (hasheq)))))
(define (denormalize-facade-list-roots-result-to-2026 v)
  ;; BARE interface: emit EXACTLY {roots}. A present meta OR a non-empty rest is refused.
  (refuse-if-present 'denormalize-facade-list-roots-result-to-2026 'meta (facade-list-roots-result-meta v) '2026-07-28)
  (let ([r (facade-list-roots-result-rest v)])
    (when (and (present? r) (positive? (hash-count r)))
      (error 'denormalize-facade-list-roots-result-to-2026
             "result-level rest (~a key(s)) absent from revision 2026-07-28 (bare {roots} interface)" (hash-count r))))
  (r26:list-roots-result (map denormalize-facade-root-to-2026 (facade-list-roots-result-roots v))))

;; ============================================================================
;; GROUP 4 — request params (TWO meta shapes).
;; ============================================================================

;; --- Group 4a: facade-request-meta (the CLIENT-request envelope). ---
;; 2025: flat _meta object -> reserved fields absent, flat keys land in `rest`;
;;       progress-token & related-task are shared (carried inside _meta).
;; 2026: the request-meta struct -> reserved fields populated.
(struct facade-request-meta (progress-token protocol-version client-info client-capabilities
                                            log-level related-task rest) #:transparent)
(define facade-request-meta/c
  (struct/c facade-request-meta (opt/c progress-token/c) (opt/c string?) (opt/c any/c)
            (opt/c any/c) (opt/c logging-level/c) (opt/c any/c) json-object?))

;; The reserved _meta key symbols (same as 2026's), to split a flat 2025 _meta.
(define META-PROGRESS-TOKEN 'progressToken)
(define META-RELATED-TASK (string->symbol "io.modelcontextprotocol/related-task"))
(define request-meta-reserved-25 (list META-PROGRESS-TOKEN META-RELATED-TASK))

;; Build a facade-request-meta from a flat 2025 _meta object (may be absent).
(define (facade-request-meta-from-2025-flat flat)
  (define h (if (present? flat) flat (hasheq)))
  (define pt (hash-ref h META-PROGRESS-TOKEN absent))
  (define rt-raw (hash-ref h META-RELATED-TASK absent))
  (define rt (if (present? rt-raw)
                 (r25:related-task-metadata (hash-ref rt-raw 'taskId))
                 absent))
  (facade-request-meta
   pt absent-field absent-field absent-field absent-field rt
   (for/fold ([acc (hasheq)]) ([(k val) (in-hash h)])
     (if (memq k request-meta-reserved-25) acc (hash-set acc k val)))))

;; Build a facade-request-meta from the 2026 request-meta struct.
(define (facade-request-meta-from-2026 rm)
  (facade-request-meta
   (r26:request-meta-progress-token rm)
   (r26:request-meta-protocol-version rm)
   (r26:request-meta-client-info rm)
   (r26:request-meta-client-capabilities rm)
   (r26:request-meta-log-level rm)
   (r26:request-meta-related-task rm)
   (r26:request-meta-rest rm)))

;; Denormalize the envelope back to a flat 2025 _meta object (or absent if empty).
(define (facade-request-meta->2025-flat fm)
  (refuse-if-present 'facade-request-meta->2025-flat 'protocol-version (facade-request-meta-protocol-version fm) '2025-11-25)
  (refuse-if-present 'facade-request-meta->2025-flat 'client-info (facade-request-meta-client-info fm) '2025-11-25)
  (refuse-if-present 'facade-request-meta->2025-flat 'client-capabilities (facade-request-meta-client-capabilities fm) '2025-11-25)
  (refuse-if-present 'facade-request-meta->2025-flat 'log-level (facade-request-meta-log-level fm) '2025-11-25)
  (let* ([h (for/fold ([acc (hasheq)]) ([(k v) (in-hash (facade-request-meta-rest fm))]) (hash-set acc k v))]
         [h (if (present? (facade-request-meta-progress-token fm)) (hash-set h META-PROGRESS-TOKEN (facade-request-meta-progress-token fm)) h)]
         [h (if (present? (facade-request-meta-related-task fm))
                (hash-set h META-RELATED-TASK (hasheq 'taskId (r25:related-task-metadata-task-id (facade-request-meta-related-task fm))))
                h)])
    (if (zero? (hash-count h)) absent h)))

;; Denormalize the envelope back to the 2026 request-meta struct.
(define (facade-request-meta->2026 fm)
  (r26:request-meta
   (facade-request-meta-progress-token fm)
   (facade-request-meta-protocol-version fm)
   (facade-request-meta-client-info fm)
   (facade-request-meta-client-capabilities fm)
   (facade-request-meta-log-level fm)
   (facade-request-meta-related-task fm)
   (facade-request-meta-rest fm)))

;; --- facade-call-tool-request-params ---
(struct facade-call-tool-request-params (name arguments task input-responses request-state meta) #:transparent)
(define facade-call-tool-request-params/c
  (struct/c facade-call-tool-request-params string? (opt/c json-object?) (opt/c any/c)
            (opt/c any/c) (opt/c any/c) (opt/c facade-request-meta/c)))
(define (normalize-facade-call-tool-request-params-from-2025 v)
  (facade-call-tool-request-params (r25:call-tool-request-params-name v) (r25:call-tool-request-params-arguments v)
                                   (r25:call-tool-request-params-task v) absent-field absent-field
                                   (facade-request-meta-from-2025-flat (r25:call-tool-request-params-meta v))))
(define (normalize-facade-call-tool-request-params-from-2026 v)
  (facade-call-tool-request-params (r26:call-tool-request-params-name v) (r26:call-tool-request-params-arguments v)
                                   absent-field (r26:call-tool-request-params-input-responses v) (r26:call-tool-request-params-request-state v)
                                   (facade-request-meta-from-2026 (r26:call-tool-request-params-meta v))))
(define (denormalize-facade-call-tool-request-params-to-2025 v)
  (refuse-if-present 'denormalize-facade-call-tool-request-params-to-2025 'input-responses (facade-call-tool-request-params-input-responses v) '2025-11-25)
  (refuse-if-present 'denormalize-facade-call-tool-request-params-to-2025 'request-state (facade-call-tool-request-params-request-state v) '2025-11-25)
  (r25:call-tool-request-params (facade-call-tool-request-params-name v) (facade-call-tool-request-params-arguments v)
                                (facade-call-tool-request-params-task v)
                                (let ([m (facade-call-tool-request-params-meta v)]) (if (present? m) (facade-request-meta->2025-flat m) absent))))
(define (denormalize-facade-call-tool-request-params-to-2026 v)
  (refuse-if-present 'denormalize-facade-call-tool-request-params-to-2026 'task (facade-call-tool-request-params-task v) '2026-07-28)
  (r26:call-tool-request-params (facade-call-tool-request-params-name v) (facade-call-tool-request-params-arguments v)
                                (facade-call-tool-request-params-input-responses v) (facade-call-tool-request-params-request-state v)
                                (facade-request-meta->2026 (facade-call-tool-request-params-meta v))))

;; --- facade-read-resource-request-params ---
(struct facade-read-resource-request-params (uri input-responses request-state meta) #:transparent)
(define facade-read-resource-request-params/c
  (struct/c facade-read-resource-request-params string? (opt/c any/c) (opt/c any/c) (opt/c facade-request-meta/c)))
(define (normalize-facade-read-resource-request-params-from-2025 v)
  (facade-read-resource-request-params (r25:read-resource-request-params-uri v) absent-field absent-field
                                       (facade-request-meta-from-2025-flat (r25:read-resource-request-params-meta v))))
(define (normalize-facade-read-resource-request-params-from-2026 v)
  (facade-read-resource-request-params (r26:read-resource-request-params-uri v) (r26:read-resource-request-params-input-responses v)
                                       (r26:read-resource-request-params-request-state v)
                                       (facade-request-meta-from-2026 (r26:read-resource-request-params-meta v))))
(define (denormalize-facade-read-resource-request-params-to-2025 v)
  (refuse-if-present 'denormalize-facade-read-resource-request-params-to-2025 'input-responses (facade-read-resource-request-params-input-responses v) '2025-11-25)
  (refuse-if-present 'denormalize-facade-read-resource-request-params-to-2025 'request-state (facade-read-resource-request-params-request-state v) '2025-11-25)
  (r25:read-resource-request-params (facade-read-resource-request-params-uri v)
                                    (let ([m (facade-read-resource-request-params-meta v)]) (if (present? m) (facade-request-meta->2025-flat m) absent))))
(define (denormalize-facade-read-resource-request-params-to-2026 v)
  (r26:read-resource-request-params (facade-read-resource-request-params-uri v) (facade-read-resource-request-params-input-responses v)
                                    (facade-read-resource-request-params-request-state v)
                                    (facade-request-meta->2026 (facade-read-resource-request-params-meta v))))

;; --- facade-get-prompt-request-params ---
(struct facade-get-prompt-request-params (name arguments input-responses request-state meta) #:transparent)
(define facade-get-prompt-request-params/c
  (struct/c facade-get-prompt-request-params string? (opt/c json-object?) (opt/c any/c) (opt/c any/c) (opt/c facade-request-meta/c)))
(define (normalize-facade-get-prompt-request-params-from-2025 v)
  (facade-get-prompt-request-params (r25:get-prompt-request-params-name v) (r25:get-prompt-request-params-arguments v)
                                    absent-field absent-field (facade-request-meta-from-2025-flat (r25:get-prompt-request-params-meta v))))
(define (normalize-facade-get-prompt-request-params-from-2026 v)
  (facade-get-prompt-request-params (r26:get-prompt-request-params-name v) (r26:get-prompt-request-params-arguments v)
                                    (r26:get-prompt-request-params-input-responses v) (r26:get-prompt-request-params-request-state v)
                                    (facade-request-meta-from-2026 (r26:get-prompt-request-params-meta v))))
(define (denormalize-facade-get-prompt-request-params-to-2025 v)
  (refuse-if-present 'denormalize-facade-get-prompt-request-params-to-2025 'input-responses (facade-get-prompt-request-params-input-responses v) '2025-11-25)
  (refuse-if-present 'denormalize-facade-get-prompt-request-params-to-2025 'request-state (facade-get-prompt-request-params-request-state v) '2025-11-25)
  (r25:get-prompt-request-params (facade-get-prompt-request-params-name v) (facade-get-prompt-request-params-arguments v)
                                 (let ([m (facade-get-prompt-request-params-meta v)]) (if (present? m) (facade-request-meta->2025-flat m) absent))))
(define (denormalize-facade-get-prompt-request-params-to-2026 v)
  (r26:get-prompt-request-params (facade-get-prompt-request-params-name v) (facade-get-prompt-request-params-arguments v)
                                 (facade-get-prompt-request-params-input-responses v) (facade-get-prompt-request-params-request-state v)
                                 (facade-request-meta->2026 (facade-get-prompt-request-params-meta v))))

;; --- facade-complete-request-params (ref argument context meta-envelope) ---
(struct facade-complete-request-params (ref argument context meta) #:transparent)
(define facade-complete-request-params/c
  (struct/c facade-complete-request-params any/c json-object? (opt/c json-object?) (opt/c facade-request-meta/c)))
(define (normalize-facade-complete-request-params-from-2025 v)
  (facade-complete-request-params (r25:complete-request-params-ref v) (r25:complete-request-params-argument v)
                                  (r25:complete-request-params-context v) (facade-request-meta-from-2025-flat (r25:complete-request-params-meta v))))
(define (normalize-facade-complete-request-params-from-2026 v)
  (facade-complete-request-params (r26:complete-request-params-ref v) (r26:complete-request-params-argument v)
                                  (r26:complete-request-params-context v) (facade-request-meta-from-2026 (r26:complete-request-params-meta v))))
(define (denormalize-facade-complete-request-params-to-2025 v)
  (r25:complete-request-params (facade-complete-request-params-ref v) (facade-complete-request-params-argument v)
                               (facade-complete-request-params-context v)
                               (let ([m (facade-complete-request-params-meta v)]) (if (present? m) (facade-request-meta->2025-flat m) absent))))
(define (denormalize-facade-complete-request-params-to-2026 v)
  (r26:complete-request-params (facade-complete-request-params-ref v) (facade-complete-request-params-argument v)
                               (facade-complete-request-params-context v)
                               (facade-request-meta->2026 (facade-complete-request-params-meta v))))

;; --- Group 4b: facade-create-message-request-params (PLAIN meta; task 2025-only) ---
(struct facade-create-message-request-params
  (messages model-preferences system-prompt include-context temperature max-tokens
            stop-sequences metadata tools tool-choice task meta) #:transparent)
(define facade-create-message-request-params/c
  (struct/c facade-create-message-request-params
            (listof facade-sampling-message/c) (opt/c facade-model-preferences/c) (opt/c string?)
            (opt/c string?) (opt/c real?) real? (opt/c (listof string?)) (opt/c json-object?)
            (opt/c (listof facade-tool/c)) (opt/c facade-tool-choice/c) (opt/c any/c) (opt/c json-object?)))
(define (normalize-facade-create-message-request-params-from-2025 v)
  (facade-create-message-request-params
   (map normalize-facade-sampling-message-from-2025 (r25:create-message-request-params-messages v))
   (norm-mp-25 (r25:create-message-request-params-model-preferences v))
   (r25:create-message-request-params-system-prompt v) (r25:create-message-request-params-include-context v)
   (r25:create-message-request-params-temperature v) (r25:create-message-request-params-max-tokens v)
   (r25:create-message-request-params-stop-sequences v) (r25:create-message-request-params-metadata v)
   (opt-map-list (r25:create-message-request-params-tools v) normalize-facade-tool-from-2025)
   (norm-tc-25 (r25:create-message-request-params-tool-choice v))
   (r25:create-message-request-params-task v)            ; task: 2025-only
   (r25:create-message-request-params-meta v)))          ; meta: PLAIN, shared
(define (normalize-facade-create-message-request-params-from-2026 v)
  (facade-create-message-request-params
   (map normalize-facade-sampling-message-from-2026 (r26:create-message-request-params-messages v))
   (norm-mp-26 (r26:create-message-request-params-model-preferences v))
   (r26:create-message-request-params-system-prompt v) (r26:create-message-request-params-include-context v)
   (r26:create-message-request-params-temperature v) (r26:create-message-request-params-max-tokens v)
   (r26:create-message-request-params-stop-sequences v) (r26:create-message-request-params-metadata v)
   (opt-map-list (r26:create-message-request-params-tools v) normalize-facade-tool-from-2026)
   (norm-tc-26 (r26:create-message-request-params-tool-choice v))
   absent-field                                          ; task: 2025-only -> absent
   (r26:create-message-request-params-meta v)))          ; meta: PLAIN, shared
(define (denormalize-facade-create-message-request-params-to-2025 v)
  (r25:create-message-request-params
   (map denormalize-facade-sampling-message-to-2025 (facade-create-message-request-params-messages v))
   (denorm-mp-25 (facade-create-message-request-params-model-preferences v))
   (facade-create-message-request-params-system-prompt v) (facade-create-message-request-params-include-context v)
   (facade-create-message-request-params-temperature v) (facade-create-message-request-params-max-tokens v)
   (facade-create-message-request-params-stop-sequences v) (facade-create-message-request-params-metadata v)
   (opt-map-list (facade-create-message-request-params-tools v) denormalize-facade-tool-to-2025)
   (denorm-tc-25 (facade-create-message-request-params-tool-choice v))
   (facade-create-message-request-params-task v) (facade-create-message-request-params-meta v)))
(define (denormalize-facade-create-message-request-params-to-2026 v)
  (refuse-if-present 'denormalize-facade-create-message-request-params-to-2026 'task (facade-create-message-request-params-task v) '2026-07-28)
  (r26:create-message-request-params
   (map denormalize-facade-sampling-message-to-2026 (facade-create-message-request-params-messages v))
   (denorm-mp-26 (facade-create-message-request-params-model-preferences v))
   (facade-create-message-request-params-system-prompt v) (facade-create-message-request-params-include-context v)
   (facade-create-message-request-params-temperature v) (facade-create-message-request-params-max-tokens v)
   (facade-create-message-request-params-stop-sequences v) (facade-create-message-request-params-metadata v)
   (opt-map-list (facade-create-message-request-params-tools v) denormalize-facade-tool-to-2026)
   (denorm-tc-26 (facade-create-message-request-params-tool-choice v))
   (facade-create-message-request-params-meta v)))

;; --- facade-elicit-request-form-params (task AND meta both 2025-only) ---
(struct facade-elicit-request-form-params (mode message requested-schema task meta) #:transparent)
(define facade-elicit-request-form-params/c
  (struct/c facade-elicit-request-form-params (opt/c string?) string? json-object? (opt/c any/c) (opt/c json-object?)))
(define (normalize-facade-elicit-request-form-params-from-2025 v)
  (facade-elicit-request-form-params (r25:elicit-request-form-params-mode v) (r25:elicit-request-form-params-message v)
                                     (r25:elicit-request-form-params-requested-schema v)
                                     (r25:elicit-request-form-params-task v) (r25:elicit-request-form-params-meta v)))
(define (normalize-facade-elicit-request-form-params-from-2026 v)
  (facade-elicit-request-form-params (r26:elicit-request-form-params-mode v) (r26:elicit-request-form-params-message v)
                                     (r26:elicit-request-form-params-requested-schema v)
                                     absent-field absent-field))   ; 2026 has NEITHER task NOR meta
(define (denormalize-facade-elicit-request-form-params-to-2025 v)
  (r25:elicit-request-form-params (facade-elicit-request-form-params-mode v) (facade-elicit-request-form-params-message v)
                                  (facade-elicit-request-form-params-requested-schema v)
                                  (facade-elicit-request-form-params-task v) (facade-elicit-request-form-params-meta v)))
(define (denormalize-facade-elicit-request-form-params-to-2026 v)
  (refuse-if-present 'denormalize-facade-elicit-request-form-params-to-2026 'task (facade-elicit-request-form-params-task v) '2026-07-28)
  (refuse-if-present 'denormalize-facade-elicit-request-form-params-to-2026 'meta (facade-elicit-request-form-params-meta v) '2026-07-28)
  (r26:elicit-request-form-params (facade-elicit-request-form-params-mode v) (facade-elicit-request-form-params-message v)
                                  (facade-elicit-request-form-params-requested-schema v)))

;; --- facade-elicit-request-url-params (task AND meta both 2025-only) ---
(struct facade-elicit-request-url-params (mode message elicitation-id url task meta) #:transparent)
(define facade-elicit-request-url-params/c
  (struct/c facade-elicit-request-url-params (opt/c string?) string? string? string? (opt/c any/c) (opt/c json-object?)))
(define (normalize-facade-elicit-request-url-params-from-2025 v)
  (facade-elicit-request-url-params (r25:elicit-request-url-params-mode v) (r25:elicit-request-url-params-message v)
                                    (r25:elicit-request-url-params-elicitation-id v) (r25:elicit-request-url-params-url v)
                                    (r25:elicit-request-url-params-task v) (r25:elicit-request-url-params-meta v)))
(define (normalize-facade-elicit-request-url-params-from-2026 v)
  (facade-elicit-request-url-params (r26:elicit-request-url-params-mode v) (r26:elicit-request-url-params-message v)
                                    (r26:elicit-request-url-params-elicitation-id v) (r26:elicit-request-url-params-url v)
                                    absent-field absent-field))
(define (denormalize-facade-elicit-request-url-params-to-2025 v)
  (r25:elicit-request-url-params (facade-elicit-request-url-params-mode v) (facade-elicit-request-url-params-message v)
                                 (facade-elicit-request-url-params-elicitation-id v) (facade-elicit-request-url-params-url v)
                                 (facade-elicit-request-url-params-task v) (facade-elicit-request-url-params-meta v)))
(define (denormalize-facade-elicit-request-url-params-to-2026 v)
  (refuse-if-present 'denormalize-facade-elicit-request-url-params-to-2026 'task (facade-elicit-request-url-params-task v) '2026-07-28)
  (refuse-if-present 'denormalize-facade-elicit-request-url-params-to-2026 'meta (facade-elicit-request-url-params-meta v) '2026-07-28)
  (r26:elicit-request-url-params (facade-elicit-request-url-params-mode v) (facade-elicit-request-url-params-message v)
                                 (facade-elicit-request-url-params-elicitation-id v) (facade-elicit-request-url-params-url v)))

;; ============================================================================
;; GROUP 5 — primitives in BOTH revisions, request/notification envelopes.
;; (Method literals identical; bodies differ only via the deltas above.)
;; Modeled here as the request-envelope façades wrapping the params façades.
;; For S1 we expose the params façades (the substance); the request envelopes
;; are thin method+payload wrappers and are provided via the union contracts.
;; ============================================================================

;; --- facade-cancelled-notification-params (identical both revs) ---
(struct facade-cancelled-notification-params (request-id reason meta) #:transparent)
(define facade-cancelled-notification-params/c
  (struct/c facade-cancelled-notification-params (opt/c request-id/c) (opt/c string?) (opt/c json-object?)))
(define (normalize-facade-cancelled-notification-params-from-2025 v)
  (facade-cancelled-notification-params (r25:cancelled-notification-params-request-id v) (r25:cancelled-notification-params-reason v) (r25:cancelled-notification-params-meta v)))
(define (normalize-facade-cancelled-notification-params-from-2026 v)
  (facade-cancelled-notification-params (r26:cancelled-notification-params-request-id v) (r26:cancelled-notification-params-reason v) (r26:cancelled-notification-params-meta v)))
(define (denormalize-facade-cancelled-notification-params-to-2025 v)
  (r25:cancelled-notification-params (facade-cancelled-notification-params-request-id v) (facade-cancelled-notification-params-reason v) (facade-cancelled-notification-params-meta v)))
(define (denormalize-facade-cancelled-notification-params-to-2026 v)
  (r26:cancelled-notification-params (facade-cancelled-notification-params-request-id v) (facade-cancelled-notification-params-reason v) (facade-cancelled-notification-params-meta v)))

;; --- facade-progress-notification-params (identical) ---
(struct facade-progress-notification-params (progress-token progress total message meta) #:transparent)
(define facade-progress-notification-params/c
  (struct/c facade-progress-notification-params progress-token/c real? (opt/c real?) (opt/c string?) (opt/c json-object?)))
(define (normalize-facade-progress-notification-params-from-2025 v)
  (facade-progress-notification-params (r25:progress-notification-params-progress-token v) (r25:progress-notification-params-progress v) (r25:progress-notification-params-total v) (r25:progress-notification-params-message v) (r25:progress-notification-params-meta v)))
(define (normalize-facade-progress-notification-params-from-2026 v)
  (facade-progress-notification-params (r26:progress-notification-params-progress-token v) (r26:progress-notification-params-progress v) (r26:progress-notification-params-total v) (r26:progress-notification-params-message v) (r26:progress-notification-params-meta v)))
(define (denormalize-facade-progress-notification-params-to-2025 v)
  (r25:progress-notification-params (facade-progress-notification-params-progress-token v) (facade-progress-notification-params-progress v) (facade-progress-notification-params-total v) (facade-progress-notification-params-message v) (facade-progress-notification-params-meta v)))
(define (denormalize-facade-progress-notification-params-to-2026 v)
  (r26:progress-notification-params (facade-progress-notification-params-progress-token v) (facade-progress-notification-params-progress v) (facade-progress-notification-params-total v) (facade-progress-notification-params-message v) (facade-progress-notification-params-meta v)))

;; --- facade-logging-message-notification-params (identical) ---
(struct facade-logging-message-notification-params (level logger data meta) #:transparent)
(define facade-logging-message-notification-params/c
  (struct/c facade-logging-message-notification-params logging-level/c (opt/c string?) any/c (opt/c json-object?)))
(define (normalize-facade-logging-message-notification-params-from-2025 v)
  (facade-logging-message-notification-params (r25:logging-message-notification-params-level v) (r25:logging-message-notification-params-logger v) (r25:logging-message-notification-params-data v) (r25:logging-message-notification-params-meta v)))
(define (normalize-facade-logging-message-notification-params-from-2026 v)
  (facade-logging-message-notification-params (r26:logging-message-notification-params-level v) (r26:logging-message-notification-params-logger v) (r26:logging-message-notification-params-data v) (r26:logging-message-notification-params-meta v)))
(define (denormalize-facade-logging-message-notification-params-to-2025 v)
  (r25:logging-message-notification-params (facade-logging-message-notification-params-level v) (facade-logging-message-notification-params-logger v) (facade-logging-message-notification-params-data v) (facade-logging-message-notification-params-meta v)))
(define (denormalize-facade-logging-message-notification-params-to-2026 v)
  (r26:logging-message-notification-params (facade-logging-message-notification-params-level v) (facade-logging-message-notification-params-logger v) (facade-logging-message-notification-params-data v) (facade-logging-message-notification-params-meta v)))

;; ============================================================================
;; GROUP 6 — 2025-only primitives (in superset; refuse denormalize-to-2026).
;; Modeled with one normalizer (from 2025) + one denormalizer (to 2025); the
;; to-2026 direction raises unconditionally.
;; ============================================================================

;; --- facade-initialize-request-params ---
(struct facade-initialize-request-params (protocol-version capabilities client-info meta) #:transparent)
(define facade-initialize-request-params/c
  (struct/c facade-initialize-request-params string? any/c facade-implementation/c (opt/c json-object?)))
(define (normalize-facade-initialize-request-params-from-2025 v)
  (facade-initialize-request-params (r25:initialize-request-params-protocol-version v) (r25:initialize-request-params-capabilities v)
                                    (normalize-facade-implementation-from-2025 (r25:initialize-request-params-client-info v))
                                    (r25:initialize-request-params-meta v)))
(define (denormalize-facade-initialize-request-params-to-2025 v)
  (r25:initialize-request-params (facade-initialize-request-params-protocol-version v) (facade-initialize-request-params-capabilities v)
                                 (denormalize-facade-implementation-to-2025 (facade-initialize-request-params-client-info v))
                                 (facade-initialize-request-params-meta v)))
(define (denormalize-facade-initialize-request-params-to-2026 v)
  (refuse-primitive 'denormalize-facade-initialize-request-params-to-2026 'initialize-request-params '2026-07-28))

;; --- facade-set-level-request-params ---
(struct facade-set-level-request-params (level meta) #:transparent)
(define facade-set-level-request-params/c
  (struct/c facade-set-level-request-params logging-level/c (opt/c json-object?)))
(define (normalize-facade-set-level-request-params-from-2025 v)
  (facade-set-level-request-params (r25:set-level-request-params-level v) (r25:set-level-request-params-meta v)))
(define (denormalize-facade-set-level-request-params-to-2025 v)
  (r25:set-level-request-params (facade-set-level-request-params-level v) (facade-set-level-request-params-meta v)))
(define (denormalize-facade-set-level-request-params-to-2026 v)
  (refuse-primitive 'denormalize-facade-set-level-request-params-to-2026 'set-level-request-params '2026-07-28))

;; --- facade-subscribe-request-params / -unsubscribe-request-params ---
(struct facade-subscribe-request-params (uri meta) #:transparent)
(define facade-subscribe-request-params/c (struct/c facade-subscribe-request-params string? (opt/c json-object?)))
(define (normalize-facade-subscribe-request-params-from-2025 v)
  (facade-subscribe-request-params (r25:subscribe-request-params-uri v) (r25:subscribe-request-params-meta v)))
(define (denormalize-facade-subscribe-request-params-to-2025 v)
  (r25:subscribe-request-params (facade-subscribe-request-params-uri v) (facade-subscribe-request-params-meta v)))
(define (denormalize-facade-subscribe-request-params-to-2026 v)
  (refuse-primitive 'denormalize-facade-subscribe-request-params-to-2026 'subscribe-request-params '2026-07-28))

;; --- facade-tool-execution already defined in Group 1 (2025-only struct) ---

;; --- facade-task (tasks family, 2025-only) ---
(struct facade-task (task-id status status-message created-at last-updated-at ttl poll-interval) #:transparent)
(define facade-task/c
  (struct/c facade-task string? task-status/c (opt/c string?) string? string? (opt/c real?) (opt/c real?)))
(define (normalize-facade-task-from-2025 v)
  (facade-task (r25:task-task-id v) (r25:task-status v) (r25:task-status-message v) (r25:task-created-at v)
               (r25:task-last-updated-at v) (r25:task-ttl v) (r25:task-poll-interval v)))
(define (denormalize-facade-task-to-2025 v)
  (r25:task (facade-task-task-id v) (facade-task-status v) (facade-task-status-message v) (facade-task-created-at v)
            (facade-task-last-updated-at v) (facade-task-ttl v) (facade-task-poll-interval v)))
(define (denormalize-facade-task-to-2026 v)
  (refuse-primitive 'denormalize-facade-task-to-2026 'task '2026-07-28))

;; --- facade-url-elicitation-required-error (2025-only error, code -32042) ---
;; Carried as a thin façade over the 2025 maker/predicate.
(define (make-facade-url-elicitation-required-error . args)
  (apply r25:make-url-elicitation-required-error args))
(define facade-url-elicitation-required-error? r25:url-elicitation-required-error?)

;; ============================================================================
;; GROUP 7 — 2026-only primitives (in superset; refuse denormalize-to-2025).
;; ============================================================================

;; --- facade-discover-request (server/discover) ---
(struct facade-discover-request (method meta) #:transparent)
(define facade-discover-request/c (struct/c facade-discover-request string? facade-request-meta/c))
(define (normalize-facade-discover-request-from-2026 v)
  (facade-discover-request (r26:discover-request-method v) (facade-request-meta-from-2026 (r26:discover-request-meta v))))
(define (denormalize-facade-discover-request-to-2026 v)
  (r26:discover-request (facade-discover-request-method v) (facade-request-meta->2026 (facade-discover-request-meta v))))
(define (denormalize-facade-discover-request-to-2025 v)
  (refuse-primitive 'denormalize-facade-discover-request-to-2025 'discover-request '2025-11-25))

;; --- facade-discover-result ---
(struct facade-discover-result (supported-versions capabilities server-info instructions meta result-type rest) #:transparent)
(define facade-discover-result/c
  (struct/c facade-discover-result (listof string?) any/c facade-implementation/c (opt/c string?)
            (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (normalize-facade-discover-result-from-2026 v)
  (facade-discover-result (r26:discover-result-supported-versions v) (r26:discover-result-capabilities v)
                          (normalize-facade-implementation-from-2026 (r26:discover-result-server-info v))
                          (r26:discover-result-instructions v) (r26:discover-result-meta v)
                          (r26:discover-result-result-type v) (r26:discover-result-rest v)))
(define (denormalize-facade-discover-result-to-2026 v)
  (r26:discover-result (facade-discover-result-supported-versions v) (facade-discover-result-capabilities v)
                       (denormalize-facade-implementation-to-2026 (facade-discover-result-server-info v))
                       (facade-discover-result-instructions v) (facade-discover-result-meta v)
                       (facade-discover-result-result-type v) (facade-discover-result-rest v)))
(define (denormalize-facade-discover-result-to-2025 v)
  (refuse-primitive 'denormalize-facade-discover-result-to-2025 'discover-result '2025-11-25))

;; --- facade-input-required-result ---
(struct facade-input-required-result (input-requests request-state meta result-type rest) #:transparent)
(define facade-input-required-result/c
  (struct/c facade-input-required-result any/c any/c (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (normalize-facade-input-required-result-from-2026 v)
  (facade-input-required-result (r26:input-required-result-input-requests v) (r26:input-required-result-request-state v)
                                (r26:input-required-result-meta v) (r26:input-required-result-result-type v) (r26:input-required-result-rest v)))
(define (denormalize-facade-input-required-result-to-2026 v)
  (r26:input-required-result (facade-input-required-result-input-requests v) (facade-input-required-result-request-state v)
                             (facade-input-required-result-meta v) (facade-input-required-result-result-type v) (facade-input-required-result-rest v)))
(define (denormalize-facade-input-required-result-to-2025 v)
  (refuse-primitive 'denormalize-facade-input-required-result-to-2025 'input-required-result '2025-11-25))

;; --- facade-subscription-filter / subscriptions-listen-request-params (2026-only) ---
(struct facade-subscription-filter (tools-list-changed prompts-list-changed resources-list-changed resource-subscriptions) #:transparent)
(define facade-subscription-filter/c
  (struct/c facade-subscription-filter (opt/c boolean?) (opt/c boolean?) (opt/c boolean?) (opt/c any/c)))
(define (normalize-facade-subscription-filter-from-2026 v)
  (facade-subscription-filter (r26:subscription-filter-tools-list-changed v) (r26:subscription-filter-prompts-list-changed v)
                              (r26:subscription-filter-resources-list-changed v) (r26:subscription-filter-resource-subscriptions v)))
(define (denormalize-facade-subscription-filter-to-2026 v)
  (r26:subscription-filter (facade-subscription-filter-tools-list-changed v) (facade-subscription-filter-prompts-list-changed v)
                           (facade-subscription-filter-resources-list-changed v) (facade-subscription-filter-resource-subscriptions v)))
(define (denormalize-facade-subscription-filter-to-2025 v)
  (refuse-primitive 'denormalize-facade-subscription-filter-to-2025 'subscription-filter '2025-11-25))

;; --- facade typed errors (2026-only predicates, code-pinned, re-exported) ---
(define facade-parse-error? r26:parse-error?)
(define facade-invalid-request-error? r26:invalid-request-error?)
(define facade-method-not-found-error? r26:method-not-found-error?)
(define facade-invalid-params-error? r26:invalid-params-error?)
(define facade-internal-error? r26:internal-error?)
(define (make-facade-unsupported-protocol-version-error . args)
  (apply r26:make-unsupported-protocol-version-error args))
(define facade-unsupported-protocol-version-error? r26:unsupported-protocol-version-error?)
(define (make-facade-missing-required-client-capability-error . args)
  (apply r26:make-missing-required-client-capability-error args))
(define facade-missing-required-client-capability-error? r26:missing-required-client-capability-error?)

;; ============================================================================
;; GROUP 8 — aggregate union contracts + revision-parameterized dispatch.
;; ============================================================================

;; Superset request union: arms from both revisions' params/primitives.
(define facade-client-request/c
  (or/c facade-call-tool-request-params/c facade-read-resource-request-params/c
        facade-get-prompt-request-params/c facade-complete-request-params/c
        facade-initialize-request-params/c facade-set-level-request-params/c
        facade-subscribe-request-params/c facade-discover-request/c))
(define facade-server-request/c
  (or/c facade-create-message-request-params/c facade-elicit-request-form-params/c
        facade-elicit-request-url-params/c facade-list-roots-result/c))
(define facade-client-notification/c
  (or/c facade-cancelled-notification-params/c facade-progress-notification-params/c))
(define facade-server-notification/c
  (or/c facade-cancelled-notification-params/c facade-progress-notification-params/c
        facade-logging-message-notification-params/c))
(define facade-client-result/c
  (or/c facade-list-roots-result/c facade-create-message-result/c facade-elicit-result/c))
(define facade-server-result/c
  (or/c facade-list-tools-result/c facade-call-tool-result/c facade-list-resources-result/c
        facade-list-resource-templates-result/c facade-list-prompts-result/c
        facade-read-resource-result/c facade-get-prompt-result/c facade-complete-result/c
        facade-discover-result/c facade-input-required-result/c))
(define facade-jsonrpc-message/c
  (or/c facade-client-request/c facade-server-request/c
        facade-client-notification/c facade-server-notification/c
        facade-client-result/c facade-server-result/c))

;; ----------------------------------------------------------------------------
;; Revision-parameterized method dispatch.
;; (dispatch-for method revision) -> (cons revision-parser normalizer) | #f
;; A method present in BOTH revisions resolves to the matching revision's
;; (json->X . normalize-X-from-<rev>) pair — ONE method, TWO parsers.
;; Single-revision methods resolve only for their home revision (#f otherwise).
;; ----------------------------------------------------------------------------
(define dispatch-table
  ;; key: (cons method revision) -> (cons parser normalizer)
  (hash
   ;; ---- both revisions ----
   (cons "tools/call" '2025-11-25)       (cons r25:json->call-tool-request-params normalize-facade-call-tool-request-params-from-2025)
   (cons "tools/call" '2026-07-28)       (cons r26:json->call-tool-request-params normalize-facade-call-tool-request-params-from-2026)
   (cons "resources/read" '2025-11-25)   (cons r25:json->read-resource-request-params normalize-facade-read-resource-request-params-from-2025)
   (cons "resources/read" '2026-07-28)   (cons r26:json->read-resource-request-params normalize-facade-read-resource-request-params-from-2026)
   (cons "prompts/get" '2025-11-25)      (cons r25:json->get-prompt-request-params normalize-facade-get-prompt-request-params-from-2025)
   (cons "prompts/get" '2026-07-28)      (cons r26:json->get-prompt-request-params normalize-facade-get-prompt-request-params-from-2026)
   (cons "completion/complete" '2025-11-25) (cons r25:json->complete-request-params normalize-facade-complete-request-params-from-2025)
   (cons "completion/complete" '2026-07-28) (cons r26:json->complete-request-params normalize-facade-complete-request-params-from-2026)
   (cons "sampling/createMessage" '2025-11-25) (cons r25:json->create-message-request-params normalize-facade-create-message-request-params-from-2025)
   (cons "sampling/createMessage" '2026-07-28) (cons r26:json->create-message-request-params normalize-facade-create-message-request-params-from-2026)
   (cons "roots/list" '2025-11-25)       (cons r25:json->list-roots-result normalize-facade-list-roots-result-from-2025)
   (cons "roots/list" '2026-07-28)       (cons r26:json->list-roots-result normalize-facade-list-roots-result-from-2026)
   ;; ---- single-revision (home only) ----
   (cons "initialize" '2025-11-25)       (cons r25:json->initialize-request-params normalize-facade-initialize-request-params-from-2025)
   (cons "logging/setLevel" '2025-11-25) (cons r25:json->set-level-request-params normalize-facade-set-level-request-params-from-2025)
   (cons "resources/subscribe" '2025-11-25) (cons r25:json->subscribe-request-params normalize-facade-subscribe-request-params-from-2025)
   (cons "server/discover" '2026-07-28)  (cons r26:json->discover-request normalize-facade-discover-request-from-2026)))

(define (dispatch-for method revision)
  (hash-ref dispatch-table (cons method revision) #f))

;; ============================================================================
;; Curated public provide (NO all-defined-out).
;; PUBLIC HANDLER-FACING SURFACE: the facade-* structs, predicates, /c
;; contracts, the normalize-*/denormalize-* seam, the union contracts, the
;; dispatch table, and the re-exported `absent` sentinel + shared scalars.
;; ============================================================================
(provide
 ;; revision tag
 revision/c
 ;; --- Group 0 ---
 (struct-out facade-base-metadata) facade-base-metadata/c
 (struct-out facade-icon) facade-icon/c
 normalize-facade-icon-from-2025 normalize-facade-icon-from-2026 denormalize-facade-icon-to-2025 denormalize-facade-icon-to-2026
 (struct-out facade-annotations) facade-annotations/c
 normalize-facade-annotations-from-2025 normalize-facade-annotations-from-2026 denormalize-facade-annotations-to-2025 denormalize-facade-annotations-to-2026
 (struct-out facade-implementation) facade-implementation/c
 normalize-facade-implementation-from-2025 normalize-facade-implementation-from-2026 denormalize-facade-implementation-to-2025 denormalize-facade-implementation-to-2026
 (struct-out facade-text-content) facade-text-content/c
 (struct-out facade-image-content) facade-image-content/c
 (struct-out facade-audio-content) facade-audio-content/c
 (struct-out facade-resource-link) facade-resource-link/c
 (struct-out facade-embedded-resource) facade-embedded-resource/c
 (struct-out facade-tool-use-content) facade-tool-use-content/c
 (struct-out facade-tool-result-content) facade-tool-result-content/c
 facade-content-block/c facade-sampling-message-content-block/c
 normalize-facade-content-block-from-2025 normalize-facade-content-block-from-2026
 denormalize-facade-content-block-to-2025 denormalize-facade-content-block-to-2026
 (struct-out facade-text-resource-contents) facade-text-resource-contents/c
 (struct-out facade-blob-resource-contents) facade-blob-resource-contents/c
 facade-resource-contents/c
 normalize-facade-resource-contents-from-2025 normalize-facade-resource-contents-from-2026
 denormalize-facade-resource-contents-to-2025 denormalize-facade-resource-contents-to-2026
 (struct-out facade-sampling-message) facade-sampling-message/c
 normalize-facade-sampling-message-from-2025 normalize-facade-sampling-message-from-2026
 denormalize-facade-sampling-message-to-2025 denormalize-facade-sampling-message-to-2026
 (struct-out facade-prompt-message) facade-prompt-message/c
 normalize-facade-prompt-message-from-2025 normalize-facade-prompt-message-from-2026
 denormalize-facade-prompt-message-to-2025 denormalize-facade-prompt-message-to-2026
 (struct-out facade-prompt-argument) facade-prompt-argument/c
 normalize-facade-prompt-argument-from-2025 normalize-facade-prompt-argument-from-2026
 denormalize-facade-prompt-argument-to-2025 denormalize-facade-prompt-argument-to-2026
 (struct-out facade-prompt) facade-prompt/c
 normalize-facade-prompt-from-2025 normalize-facade-prompt-from-2026
 denormalize-facade-prompt-to-2025 denormalize-facade-prompt-to-2026
 (struct-out facade-resource) facade-resource/c
 normalize-facade-resource-from-2025 normalize-facade-resource-from-2026
 denormalize-facade-resource-to-2025 denormalize-facade-resource-to-2026
 (struct-out facade-resource-template) facade-resource-template/c
 normalize-facade-resource-template-from-2025 normalize-facade-resource-template-from-2026
 denormalize-facade-resource-template-to-2025 denormalize-facade-resource-template-to-2026
 (struct-out facade-tool-annotations) facade-tool-annotations/c
 (struct-out facade-model-hint) facade-model-hint/c
 (struct-out facade-model-preferences) facade-model-preferences/c
 (struct-out facade-tool-choice) facade-tool-choice/c
 (struct-out facade-resource-template-reference) facade-resource-template-reference/c
 (struct-out facade-prompt-reference) facade-prompt-reference/c
 (struct-out facade-root) facade-root/c
 normalize-facade-root-from-2025 normalize-facade-root-from-2026
 denormalize-facade-root-to-2025 denormalize-facade-root-to-2026
 ;; --- Group 1 ---
 (struct-out facade-tool-execution) facade-tool-execution/c
 (struct-out facade-tool) facade-tool/c
 normalize-facade-tool-from-2025 normalize-facade-tool-from-2026
 denormalize-facade-tool-to-2025 denormalize-facade-tool-to-2026
 ;; --- Group 2 ---
 (struct-out facade-list-tools-result) facade-list-tools-result/c
 normalize-facade-list-tools-result-from-2025 normalize-facade-list-tools-result-from-2026
 denormalize-facade-list-tools-result-to-2025 denormalize-facade-list-tools-result-to-2026
 (struct-out facade-call-tool-result) facade-call-tool-result/c
 normalize-facade-call-tool-result-from-2025 normalize-facade-call-tool-result-from-2026
 denormalize-facade-call-tool-result-to-2025 denormalize-facade-call-tool-result-to-2026
 (struct-out facade-list-resources-result) facade-list-resources-result/c
 normalize-facade-list-resources-result-from-2025 normalize-facade-list-resources-result-from-2026
 denormalize-facade-list-resources-result-to-2025 denormalize-facade-list-resources-result-to-2026
 (struct-out facade-list-resource-templates-result) facade-list-resource-templates-result/c
 normalize-facade-list-resource-templates-result-from-2025 normalize-facade-list-resource-templates-result-from-2026
 denormalize-facade-list-resource-templates-result-to-2025 denormalize-facade-list-resource-templates-result-to-2026
 (struct-out facade-list-prompts-result) facade-list-prompts-result/c
 normalize-facade-list-prompts-result-from-2025 normalize-facade-list-prompts-result-from-2026
 denormalize-facade-list-prompts-result-to-2025 denormalize-facade-list-prompts-result-to-2026
 (struct-out facade-read-resource-result) facade-read-resource-result/c
 normalize-facade-read-resource-result-from-2025 normalize-facade-read-resource-result-from-2026
 denormalize-facade-read-resource-result-to-2025 denormalize-facade-read-resource-result-to-2026
 (struct-out facade-get-prompt-result) facade-get-prompt-result/c
 normalize-facade-get-prompt-result-from-2025 normalize-facade-get-prompt-result-from-2026
 denormalize-facade-get-prompt-result-to-2025 denormalize-facade-get-prompt-result-to-2026
 (struct-out facade-complete-result) facade-complete-result/c
 normalize-facade-complete-result-from-2025 normalize-facade-complete-result-from-2026
 denormalize-facade-complete-result-to-2025 denormalize-facade-complete-result-to-2026
 (struct-out facade-create-message-result) facade-create-message-result/c
 normalize-facade-create-message-result-from-2025 normalize-facade-create-message-result-from-2026
 denormalize-facade-create-message-result-to-2025 denormalize-facade-create-message-result-to-2026
 (struct-out facade-elicit-result) facade-elicit-result/c
 normalize-facade-elicit-result-from-2025 normalize-facade-elicit-result-from-2026
 denormalize-facade-elicit-result-to-2025 denormalize-facade-elicit-result-to-2026
 ;; --- Group 3 ---
 (struct-out facade-list-roots-result) facade-list-roots-result/c
 normalize-facade-list-roots-result-from-2025 normalize-facade-list-roots-result-from-2026
 denormalize-facade-list-roots-result-to-2025 denormalize-facade-list-roots-result-to-2026
 ;; --- Group 4a ---
 (struct-out facade-request-meta) facade-request-meta/c
 (struct-out facade-call-tool-request-params) facade-call-tool-request-params/c
 normalize-facade-call-tool-request-params-from-2025 normalize-facade-call-tool-request-params-from-2026
 denormalize-facade-call-tool-request-params-to-2025 denormalize-facade-call-tool-request-params-to-2026
 (struct-out facade-read-resource-request-params) facade-read-resource-request-params/c
 normalize-facade-read-resource-request-params-from-2025 normalize-facade-read-resource-request-params-from-2026
 denormalize-facade-read-resource-request-params-to-2025 denormalize-facade-read-resource-request-params-to-2026
 (struct-out facade-get-prompt-request-params) facade-get-prompt-request-params/c
 normalize-facade-get-prompt-request-params-from-2025 normalize-facade-get-prompt-request-params-from-2026
 denormalize-facade-get-prompt-request-params-to-2025 denormalize-facade-get-prompt-request-params-to-2026
 (struct-out facade-complete-request-params) facade-complete-request-params/c
 normalize-facade-complete-request-params-from-2025 normalize-facade-complete-request-params-from-2026
 denormalize-facade-complete-request-params-to-2025 denormalize-facade-complete-request-params-to-2026
 ;; --- Group 4b ---
 (struct-out facade-create-message-request-params) facade-create-message-request-params/c
 normalize-facade-create-message-request-params-from-2025 normalize-facade-create-message-request-params-from-2026
 denormalize-facade-create-message-request-params-to-2025 denormalize-facade-create-message-request-params-to-2026
 (struct-out facade-elicit-request-form-params) facade-elicit-request-form-params/c
 normalize-facade-elicit-request-form-params-from-2025 normalize-facade-elicit-request-form-params-from-2026
 denormalize-facade-elicit-request-form-params-to-2025 denormalize-facade-elicit-request-form-params-to-2026
 (struct-out facade-elicit-request-url-params) facade-elicit-request-url-params/c
 normalize-facade-elicit-request-url-params-from-2025 normalize-facade-elicit-request-url-params-from-2026
 denormalize-facade-elicit-request-url-params-to-2025 denormalize-facade-elicit-request-url-params-to-2026
 ;; --- Group 5 ---
 (struct-out facade-cancelled-notification-params) facade-cancelled-notification-params/c
 normalize-facade-cancelled-notification-params-from-2025 normalize-facade-cancelled-notification-params-from-2026
 denormalize-facade-cancelled-notification-params-to-2025 denormalize-facade-cancelled-notification-params-to-2026
 (struct-out facade-progress-notification-params) facade-progress-notification-params/c
 normalize-facade-progress-notification-params-from-2025 normalize-facade-progress-notification-params-from-2026
 denormalize-facade-progress-notification-params-to-2025 denormalize-facade-progress-notification-params-to-2026
 (struct-out facade-logging-message-notification-params) facade-logging-message-notification-params/c
 normalize-facade-logging-message-notification-params-from-2025 normalize-facade-logging-message-notification-params-from-2026
 denormalize-facade-logging-message-notification-params-to-2025 denormalize-facade-logging-message-notification-params-to-2026
 ;; --- Group 6 (2025-only) ---
 (struct-out facade-initialize-request-params) facade-initialize-request-params/c
 normalize-facade-initialize-request-params-from-2025 denormalize-facade-initialize-request-params-to-2025 denormalize-facade-initialize-request-params-to-2026
 (struct-out facade-set-level-request-params) facade-set-level-request-params/c
 normalize-facade-set-level-request-params-from-2025 denormalize-facade-set-level-request-params-to-2025 denormalize-facade-set-level-request-params-to-2026
 (struct-out facade-subscribe-request-params) facade-subscribe-request-params/c
 normalize-facade-subscribe-request-params-from-2025 denormalize-facade-subscribe-request-params-to-2025 denormalize-facade-subscribe-request-params-to-2026
 (struct-out facade-task) facade-task/c
 normalize-facade-task-from-2025 denormalize-facade-task-to-2025 denormalize-facade-task-to-2026
 make-facade-url-elicitation-required-error facade-url-elicitation-required-error?
 ;; --- Group 7 (2026-only) ---
 (struct-out facade-discover-request) facade-discover-request/c
 normalize-facade-discover-request-from-2026 denormalize-facade-discover-request-to-2026 denormalize-facade-discover-request-to-2025
 (struct-out facade-discover-result) facade-discover-result/c
 normalize-facade-discover-result-from-2026 denormalize-facade-discover-result-to-2026 denormalize-facade-discover-result-to-2025
 (struct-out facade-input-required-result) facade-input-required-result/c
 normalize-facade-input-required-result-from-2026 denormalize-facade-input-required-result-to-2026 denormalize-facade-input-required-result-to-2025
 (struct-out facade-subscription-filter) facade-subscription-filter/c
 normalize-facade-subscription-filter-from-2026 denormalize-facade-subscription-filter-to-2026 denormalize-facade-subscription-filter-to-2025
 facade-parse-error? facade-invalid-request-error? facade-method-not-found-error?
 facade-invalid-params-error? facade-internal-error?
 make-facade-unsupported-protocol-version-error facade-unsupported-protocol-version-error?
 make-facade-missing-required-client-capability-error facade-missing-required-client-capability-error?
 ;; --- request-meta envelope seam ---
 facade-request-meta-from-2025-flat facade-request-meta-from-2026
 facade-request-meta->2025-flat facade-request-meta->2026
 ;; --- Group 8 unions + dispatch ---
 facade-client-request/c facade-server-request/c
 facade-client-notification/c facade-server-notification/c
 facade-client-result/c facade-server-result/c facade-jsonrpc-message/c
 dispatch-for)
