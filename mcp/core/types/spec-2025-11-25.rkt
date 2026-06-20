#lang racket/base

;; ============================================================================
;; spec-2025-11-25.rkt — pure-data Racket mirror of the MCP `2025-11-25`
;; revision (typescript-sdk/packages/core/src/types/spec.types.2025-11-25.ts +
;; schemas.ts). Item 003 of queue-001 (Stage S1, module M1).
;;
;; For EVERY request / notification / result / error / supporting type of the
;; revision this module provides:
;;   - a transparent `struct`
;;   - a flat contract `name/c`
;;   - `(json->name jsexpr)` deserializer and `(name->json struct)` serializer
;; mapping kebab-case Racket fields <-> the exact camelCase JSON keys.
;;
;; Wire conventions (inherited from guards.rkt / constants.rkt, item 001/002):
;;   - JSON object  = immutable symbol-keyed hasheq (json-object?)
;;   - JSON null    = the symbol 'null
;;   - absent field = the `absent` sentinel; the serializer OMITS the key (it
;;                    never emits "k": null). A present 'null (only Task.ttl)
;;                    serializes to JSON null.
;;
;; THREE distinct strictness behaviors (schemas.ts):
;;   (a) JSON-RPC ENVELOPES are .strict() — extra top-level key REJECTED.
;;   (b) RESULTS are looseObject — they PRESERVE _meta AND unknown extra keys
;;       (kept verbatim in a `rest` hasheq field, re-emitted on serialize).
;;   (c) concrete request/notification PARAMS are BaseRequestParamsSchema =
;;       z.object (NON-loose) extended — they DROP unknown non-_meta keys on
;;       round-trip. Params carry a named `meta` field (for _meta) but NO rest.
;;
;; N1-readiness (architecture line 326): every primitive struct, predicate and
;; per-type `…/c` contract is provided individually (no opaque blob) so item
;; 005's `types.rkt` façade can UNION 003 + 004 field-by-field. The `absent`
;; sentinel is exported for the same reason. Field-presence model: an optional
;; field that was absent on the wire holds `absent`; the façade unions by
;; testing `(absent? v)`.
;;
;; Requires only racket/base + racket/contract + constants.rkt (Portability
;; NFR — no json I/O at module load, no subprocess/socket).
;; ============================================================================

(require racket/contract
         (only-in "constants.rkt"
                  JSONRPC-VERSION
                  URL-ELICITATION-REQUIRED))

;; ----------------------------------------------------------------------------
;; Internal wire helpers (NOT provided, except `absent`).
;; ----------------------------------------------------------------------------

;; The `read-json` object shape: an immutable, symbol-keyed hash.
(define (json-object? v)
  (and (hash? v) (immutable? v) (hash-eq? v)))

;; Absent-optional sentinel. EXPORTED (item 005 reuses it).
(define absent (string->uninterned-symbol "absent"))
(define (absent? v) (eq? v absent))
(define (present? v) (not (eq? v absent)))

;; JSON null.
(define (json-null? v) (eq? v 'null))

;; request-id / progress-token rule (reuse guards' rule).
(define (request-id? x) (or (string? x) (exact-integer? x)))
(define (progress-token? x) (or (string? x) (exact-integer? x)))

;; A jsexpr value: anything read-json can produce.
(define (jsexpr-value? v)
  (or (json-null? v) (boolean? v) (string? v) (number? v)
      (and (list? v) (andmap jsexpr-value? v))
      (and (json-object? v) (for/and ([(_k val) (in-hash v)]) (jsexpr-value? val)))))

;; Fetch an optional key from a read-json hash: returns `absent` if missing.
(define (h-opt h key) (hash-ref h key absent))

;; Fetch a required key; returns `absent` if missing (deserializers validate).
(define (h-req h key) (hash-ref h key absent))

;; Emit a (key . value) into a hasheq only if value is present (not absent).
;; A present 'null IS emitted (as JSON null). conv maps the Racket value -> jsexpr.
(define (put h key val [conv values])
  (if (present? val) (hash-set h key (conv val)) h))

;; Always emit (required field).
(define (put! h key val [conv values]) (hash-set h key (conv val)))

;; Map an optional value through conv only if present.
(define (opt-map val conv) (if (present? val) (conv val) absent))

;; Deserialize a list field (absent stays absent; else map each elt).
(define (opt-list val conv) (opt-map val (lambda (xs) (map conv xs))))
(define (req-list val conv) (map conv val))

;; Split a hash into (named-values-hash . rest-hash) given a list of
;; (racket-field . json-key) pairs. `_meta` is pulled into the named `meta`
;; slot when present in the table; remaining keys -> rest. Used by LOOSE types.
(define (split-loose h table)
  (define known-json-keys (map cdr table))
  (define rest
    (for/fold ([acc (hasheq)]) ([(k v) (in-hash h)])
      (if (memq k known-json-keys) acc (hash-set acc k v))))
  rest)

;; ----------------------------------------------------------------------------
;; PROVIDES (curated; NO all-defined-out).
;; ----------------------------------------------------------------------------
(provide
 ;; sentinel + helpers item 005 needs
 absent absent? present?
 ;; jsexpr value predicate (item 006 reuses it for the error `data` contract)
 jsexpr-value?
 ;; scalar/enum contracts
 role/c cursor/c progress-token/c request-id/c
 task-status/c logging-level/c
 ;; ---- envelopes ----
 (struct-out jsonrpc-request) jsonrpc-request/c json->jsonrpc-request jsonrpc-request->json
 (struct-out jsonrpc-notification) jsonrpc-notification/c json->jsonrpc-notification jsonrpc-notification->json
 (struct-out jsonrpc-result-response) jsonrpc-result-response/c json->jsonrpc-result-response jsonrpc-result-response->json
 (struct-out jsonrpc-error-response) jsonrpc-error-response/c json->jsonrpc-error-response jsonrpc-error-response->json
 (struct-out jsonrpc-error) jsonrpc-error/c json->jsonrpc-error jsonrpc-error->json
 ;; ---- common ----
 (struct-out result) result/c json->result result->json
 (struct-out base-metadata) base-metadata/c
 (struct-out implementation) implementation/c json->implementation implementation->json
 (struct-out icon) icon/c json->icon icon->json
 (struct-out annotations) annotations/c json->annotations annotations->json
 ;; ---- lifecycle ----
 (struct-out client-capabilities) client-capabilities/c json->client-capabilities client-capabilities->json
 (struct-out server-capabilities) server-capabilities/c json->server-capabilities server-capabilities->json
 (struct-out initialize-request-params) initialize-request-params/c json->initialize-request-params initialize-request-params->json
 (struct-out initialize-request) initialize-request/c json->initialize-request initialize-request->json
 (struct-out initialize-result) initialize-result/c json->initialize-result initialize-result->json
 (struct-out initialized-notification) initialized-notification/c json->initialized-notification initialized-notification->json
 ;; ---- ping ----
 (struct-out ping-request) ping-request/c json->ping-request ping-request->json
 ;; ---- progress / cancellation ----
 (struct-out cancelled-notification-params) cancelled-notification-params/c json->cancelled-notification-params cancelled-notification-params->json
 (struct-out cancelled-notification) cancelled-notification/c json->cancelled-notification cancelled-notification->json
 (struct-out progress-notification-params) progress-notification-params/c json->progress-notification-params progress-notification-params->json
 (struct-out progress-notification) progress-notification/c json->progress-notification progress-notification->json
 ;; ---- pagination bases ----
 (struct-out paginated-request-params) paginated-request-params/c json->paginated-request-params paginated-request-params->json
 (struct-out paginated-result) paginated-result/c json->paginated-result paginated-result->json
 ;; ---- resources ----
 (struct-out list-resources-request) list-resources-request/c json->list-resources-request list-resources-request->json
 (struct-out list-resources-result) list-resources-result/c json->list-resources-result list-resources-result->json
 (struct-out list-resource-templates-request) list-resource-templates-request/c json->list-resource-templates-request list-resource-templates-request->json
 (struct-out list-resource-templates-result) list-resource-templates-result/c json->list-resource-templates-result list-resource-templates-result->json
 (struct-out read-resource-request-params) read-resource-request-params/c json->read-resource-request-params read-resource-request-params->json
 (struct-out read-resource-request) read-resource-request/c json->read-resource-request read-resource-request->json
 (struct-out read-resource-result) read-resource-result/c json->read-resource-result read-resource-result->json
 (struct-out subscribe-request-params) subscribe-request-params/c json->subscribe-request-params subscribe-request-params->json
 (struct-out subscribe-request) subscribe-request/c json->subscribe-request subscribe-request->json
 (struct-out unsubscribe-request-params) unsubscribe-request-params/c json->unsubscribe-request-params unsubscribe-request-params->json
 (struct-out unsubscribe-request) unsubscribe-request/c json->unsubscribe-request unsubscribe-request->json
 (struct-out resource-updated-notification-params) resource-updated-notification-params/c json->resource-updated-notification-params resource-updated-notification-params->json
 (struct-out resource-updated-notification) resource-updated-notification/c json->resource-updated-notification resource-updated-notification->json
 (struct-out resource-list-changed-notification) resource-list-changed-notification/c json->resource-list-changed-notification resource-list-changed-notification->json
 (struct-out resource) resource/c json->resource resource->json
 (struct-out resource-template) resource-template/c json->resource-template resource-template->json
 (struct-out text-resource-contents) text-resource-contents/c json->text-resource-contents text-resource-contents->json
 (struct-out blob-resource-contents) blob-resource-contents/c json->blob-resource-contents blob-resource-contents->json
 resource-contents/c json->resource-contents resource-contents->json
 ;; ---- prompts ----
 (struct-out list-prompts-request) list-prompts-request/c json->list-prompts-request list-prompts-request->json
 (struct-out list-prompts-result) list-prompts-result/c json->list-prompts-result list-prompts-result->json
 (struct-out get-prompt-request-params) get-prompt-request-params/c json->get-prompt-request-params get-prompt-request-params->json
 (struct-out get-prompt-request) get-prompt-request/c json->get-prompt-request get-prompt-request->json
 (struct-out get-prompt-result) get-prompt-result/c json->get-prompt-result get-prompt-result->json
 (struct-out prompt) prompt/c json->prompt prompt->json
 (struct-out prompt-argument) prompt-argument/c json->prompt-argument prompt-argument->json
 (struct-out prompt-message) prompt-message/c json->prompt-message prompt-message->json
 (struct-out prompt-list-changed-notification) prompt-list-changed-notification/c json->prompt-list-changed-notification prompt-list-changed-notification->json
 ;; ---- tools ----
 (struct-out list-tools-request) list-tools-request/c json->list-tools-request list-tools-request->json
 (struct-out list-tools-result) list-tools-result/c json->list-tools-result list-tools-result->json
 (struct-out call-tool-request-params) call-tool-request-params/c json->call-tool-request-params call-tool-request-params->json
 (struct-out call-tool-request) call-tool-request/c json->call-tool-request call-tool-request->json
 (struct-out call-tool-result) call-tool-result/c json->call-tool-result call-tool-result->json
 (struct-out tool) tool/c json->tool tool->json
 (struct-out tool-annotations) tool-annotations/c json->tool-annotations tool-annotations->json
 (struct-out tool-execution) tool-execution/c json->tool-execution tool-execution->json
 (struct-out tool-list-changed-notification) tool-list-changed-notification/c json->tool-list-changed-notification tool-list-changed-notification->json
 ;; ---- tasks ----
 (struct-out task-metadata) task-metadata/c json->task-metadata task-metadata->json
 (struct-out related-task-metadata) related-task-metadata/c json->related-task-metadata related-task-metadata->json
 (struct-out task) task/c json->task task->json
 (struct-out create-task-result) create-task-result/c json->create-task-result create-task-result->json
 (struct-out task-id-params) task-id-params/c json->task-id-params task-id-params->json
 (struct-out get-task-request) get-task-request/c json->get-task-request get-task-request->json
 (struct-out get-task-result) get-task-result/c json->get-task-result get-task-result->json
 (struct-out get-task-payload-request) get-task-payload-request/c json->get-task-payload-request get-task-payload-request->json
 (struct-out get-task-payload-result) get-task-payload-result/c json->get-task-payload-result get-task-payload-result->json
 (struct-out cancel-task-request) cancel-task-request/c json->cancel-task-request cancel-task-request->json
 (struct-out cancel-task-result) cancel-task-result/c json->cancel-task-result cancel-task-result->json
 (struct-out list-tasks-request) list-tasks-request/c json->list-tasks-request list-tasks-request->json
 (struct-out list-tasks-result) list-tasks-result/c json->list-tasks-result list-tasks-result->json
 (struct-out task-status-notification-params) task-status-notification-params/c json->task-status-notification-params task-status-notification-params->json
 (struct-out task-status-notification) task-status-notification/c json->task-status-notification task-status-notification->json
 ;; ---- logging ----
 (struct-out set-level-request-params) set-level-request-params/c json->set-level-request-params set-level-request-params->json
 (struct-out set-level-request) set-level-request/c json->set-level-request set-level-request->json
 (struct-out logging-message-notification-params) logging-message-notification-params/c json->logging-message-notification-params logging-message-notification-params->json
 (struct-out logging-message-notification) logging-message-notification/c json->logging-message-notification logging-message-notification->json
 ;; ---- sampling ----
 (struct-out create-message-request-params) create-message-request-params/c json->create-message-request-params create-message-request-params->json
 (struct-out create-message-request) create-message-request/c json->create-message-request create-message-request->json
 (struct-out create-message-result) create-message-result/c json->create-message-result create-message-result->json
 (struct-out tool-choice) tool-choice/c json->tool-choice tool-choice->json
 (struct-out sampling-message) sampling-message/c json->sampling-message sampling-message->json
 (struct-out model-preferences) model-preferences/c json->model-preferences model-preferences->json
 (struct-out model-hint) model-hint/c json->model-hint model-hint->json
 ;; ---- content blocks ----
 content-block/c sampling-message-content-block/c
 json->content-block content-block->json
 json->sampling-message-content-block sampling-message-content-block->json
 (struct-out text-content) text-content/c json->text-content text-content->json
 (struct-out image-content) image-content/c json->image-content image-content->json
 (struct-out audio-content) audio-content/c json->audio-content audio-content->json
 (struct-out resource-link) resource-link/c json->resource-link resource-link->json
 (struct-out embedded-resource) embedded-resource/c json->embedded-resource embedded-resource->json
 (struct-out tool-use-content) tool-use-content/c json->tool-use-content tool-use-content->json
 (struct-out tool-result-content) tool-result-content/c json->tool-result-content tool-result-content->json
 ;; ---- autocomplete ----
 (struct-out complete-request-params) complete-request-params/c json->complete-request-params complete-request-params->json
 (struct-out complete-request) complete-request/c json->complete-request complete-request->json
 (struct-out complete-result) complete-result/c json->complete-result complete-result->json
 (struct-out resource-template-reference) resource-template-reference/c json->resource-template-reference resource-template-reference->json
 (struct-out prompt-reference) prompt-reference/c json->prompt-reference prompt-reference->json
 ;; ---- roots ----
 (struct-out list-roots-request) list-roots-request/c json->list-roots-request list-roots-request->json
 (struct-out list-roots-result) list-roots-result/c json->list-roots-result list-roots-result->json
 (struct-out root) root/c json->root root->json
 (struct-out roots-list-changed-notification) roots-list-changed-notification/c json->roots-list-changed-notification roots-list-changed-notification->json
 ;; ---- elicitation ----
 (struct-out elicit-request-form-params) elicit-request-form-params/c json->elicit-request-form-params elicit-request-form-params->json
 (struct-out elicit-request-url-params) elicit-request-url-params/c json->elicit-request-url-params elicit-request-url-params->json
 elicit-request-params/c json->elicit-request-params elicit-request-params->json
 (struct-out elicit-request) elicit-request/c json->elicit-request elicit-request->json
 (struct-out elicit-result) elicit-result/c json->elicit-result elicit-result->json
 (struct-out elicitation-complete-notification) elicitation-complete-notification/c json->elicitation-complete-notification elicitation-complete-notification->json
 (struct-out string-schema) string-schema/c json->string-schema string-schema->json
 (struct-out number-schema) number-schema/c json->number-schema number-schema->json
 (struct-out boolean-schema) boolean-schema/c json->boolean-schema boolean-schema->json
 primitive-schema-definition/c json->primitive-schema-definition primitive-schema-definition->json
 (struct-out untitled-single-select-enum-schema) untitled-single-select-enum-schema/c json->untitled-single-select-enum-schema untitled-single-select-enum-schema->json
 (struct-out titled-single-select-enum-schema) titled-single-select-enum-schema/c json->titled-single-select-enum-schema titled-single-select-enum-schema->json
 (struct-out untitled-multi-select-enum-schema) untitled-multi-select-enum-schema/c json->untitled-multi-select-enum-schema untitled-multi-select-enum-schema->json
 (struct-out titled-multi-select-enum-schema) titled-multi-select-enum-schema/c json->titled-multi-select-enum-schema titled-multi-select-enum-schema->json
 (struct-out legacy-titled-enum-schema) legacy-titled-enum-schema/c json->legacy-titled-enum-schema legacy-titled-enum-schema->json
 enum-schema/c json->enum-schema enum-schema->json
 ;; ---- specialized error ----
 make-url-elicitation-required-error url-elicitation-required-error?
 ;; ---- aggregate union contracts ----
 client-request/c client-notification/c client-result/c
 server-request/c server-notification/c server-result/c
 jsonrpc-message/c)

;; ============================================================================
;; Scalar / enum contracts (§B, §J, §K)
;; ============================================================================
(define role/c (or/c "user" "assistant"))                       ; Role (1027)
(define cursor/c string?)                                        ; Cursor (36)
(define progress-token/c (flat-named-contract 'progress-token/c progress-token?)) ; (29)
(define request-id/c (flat-named-contract 'request-id/c request-id?))             ; (130)
(define task-status/c                                            ; TaskStatus (1311)
  (or/c "working" "input_required" "completed" "failed" "cancelled"))
(define logging-level/c                                          ; LoggingLevel (1567)
  (or/c "debug" "info" "notice" "warning" "error" "critical" "alert" "emergency"))

;; optional-of helper: a contract that also accepts the absent sentinel.
(define (opt/c c) (or/c absent? c))

;; string-literal contract (the method/type/mode discriminator pins).
(define (lit/c str)
  (flat-named-contract (string->symbol (format "=~s" str))
                       (lambda (x) (equal? x str))))

;; ============================================================================
;; A. JSON-RPC envelopes (4) — schemas.ts:141–192. STRICT top-level keys.
;; ============================================================================

;; JSONRPCRequest (137): id (string|int), method, params (object|absent).
(struct jsonrpc-request (id method params) #:transparent)
(define jsonrpc-request/c
  (struct/c jsonrpc-request request-id? string? (opt/c json-object?)))
(define (json->jsonrpc-request h)
  (define allowed '(jsonrpc id method params))
  (unless (for/and ([k (in-hash-keys h)]) (memq k allowed))
    (error 'json->jsonrpc-request "extra top-level key (strict envelope): ~a" h))
  (jsonrpc-request (h-req h 'id) (h-req h 'method) (h-opt h 'params)))
(define (jsonrpc-request->json s)
  (put (hasheq 'jsonrpc JSONRPC-VERSION
               'id (jsonrpc-request-id s)
               'method (jsonrpc-request-method s))
       'params (jsonrpc-request-params s)))

;; JSONRPCNotification (147): NO id; method, params?.
(struct jsonrpc-notification (method params) #:transparent)
(define jsonrpc-notification/c
  (struct/c jsonrpc-notification string? (opt/c json-object?)))
(define (json->jsonrpc-notification h)
  (define allowed '(jsonrpc method params))
  (unless (for/and ([k (in-hash-keys h)]) (memq k allowed))
    (error 'json->jsonrpc-notification "extra top-level key (strict envelope): ~a" h))
  (jsonrpc-notification (h-req h 'method) (h-opt h 'params)))
(define (jsonrpc-notification->json s)
  (put (hasheq 'jsonrpc JSONRPC-VERSION 'method (jsonrpc-notification-method s))
       'params (jsonrpc-notification-params s)))

;; JSONRPCResultResponse (156): id, result (object, loose).
(struct jsonrpc-result-response (id result) #:transparent)
(define jsonrpc-result-response/c
  (struct/c jsonrpc-result-response request-id? json-object?))
(define (json->jsonrpc-result-response h)
  (define allowed '(jsonrpc id result))
  (unless (for/and ([k (in-hash-keys h)]) (memq k allowed))
    (error 'json->jsonrpc-result-response "extra top-level key (strict envelope): ~a" h))
  (jsonrpc-result-response (h-req h 'id) (h-req h 'result)))
(define (jsonrpc-result-response->json s)
  (hasheq 'jsonrpc JSONRPC-VERSION
          'id (jsonrpc-result-response-id s)
          'result (jsonrpc-result-response-result s)))

;; Error (110): inner object, NOT strict. code, message, data?.
(struct jsonrpc-error (code message data) #:transparent)
(define jsonrpc-error/c
  (struct/c jsonrpc-error exact-integer? string? (opt/c jsexpr-value?)))
(define (json->jsonrpc-error h)
  (jsonrpc-error (h-req h 'code) (h-req h 'message) (h-opt h 'data)))
(define (jsonrpc-error->json s)
  (put (hasheq 'code (jsonrpc-error-code s) 'message (jsonrpc-error-message s))
       'data (jsonrpc-error-data s)))

;; JSONRPCErrorResponse (167): id (string|int|absent), error.
(struct jsonrpc-error-response (id error) #:transparent)
(define jsonrpc-error-response/c
  (struct/c jsonrpc-error-response (or/c absent? request-id?) jsonrpc-error?))
(define (json->jsonrpc-error-response h)
  (define allowed '(jsonrpc id error))
  (unless (for/and ([k (in-hash-keys h)]) (memq k allowed))
    (error 'json->jsonrpc-error-response "extra top-level key (strict envelope): ~a" h))
  (jsonrpc-error-response (h-opt h 'id) (json->jsonrpc-error (h-req h 'error))))
(define (jsonrpc-error-response->json s)
  (put (hasheq 'jsonrpc JSONRPC-VERSION 'error (jsonrpc-error->json (jsonrpc-error-response-error s)))
       'id (jsonrpc-error-response-id s)))

;; ============================================================================
;; B. Common / shared types
;; ============================================================================

;; Result (99): base for all results. LOOSE — `meta` named + `rest` hasheq.
(struct result (meta rest) #:transparent)
(define result/c (struct/c result (opt/c json-object?) json-object?))
(define (json->result h)
  (result (h-opt h '_meta) (split-loose h '((meta . _meta)))))
(define (result->json s)
  (put (hash-merge (result-rest s)) '_meta (result-meta s)))

;; merge a rest hasheq onto a base (base wins for named keys; here rest first).
(define (hash-merge rest [base (hasheq)])
  (for/fold ([acc base]) ([(k v) (in-hash rest)]) (hash-set acc k v)))

;; BaseMetadata (533): name, title?. (mixed in; no own (de)ser — used inline.)
(struct base-metadata (name title) #:transparent)
(define base-metadata/c (struct/c base-metadata string? (opt/c string?)))

;; Icon (469): src, mimeType?, sizes?, theme?.
(struct icon (src mime-type sizes theme) #:transparent)
(define icon/c
  (struct/c icon string? (opt/c string?) (opt/c (listof string?)) (opt/c (or/c "light" "dark"))))
(define (json->icon h)
  (icon (h-req h 'src) (h-opt h 'mimeType) (h-opt h 'sizes) (h-opt h 'theme)))
(define (icon->json s)
  (put (put (put (put! (hasheq) 'src (icon-src s))
                 'mimeType (icon-mime-type s))
            'sizes (icon-sizes s))
       'theme (icon-theme s)))

;; Annotations (1697): audience?, priority?, lastModified?.
(struct annotations (audience priority last-modified) #:transparent)
(define annotations/c
  (struct/c annotations (opt/c (listof role/c)) (opt/c real?) (opt/c string?)))
(define (json->annotations h)
  (annotations (h-opt h 'audience) (h-opt h 'priority) (h-opt h 'lastModified)))
(define (annotations->json s)
  (put (put (put (hasheq) 'audience (annotations-audience s))
            'priority (annotations-priority s))
       'lastModified (annotations-last-modified s)))

;; Implementation (555): BaseMetadata + Icons + version, description?, websiteUrl?.
(struct implementation (name title version description website-url icons) #:transparent)
(define implementation/c
  (struct/c implementation string? (opt/c string?) string?
            (opt/c string?) (opt/c string?) (opt/c (listof icon?))))
(define (json->implementation h)
  (implementation (h-req h 'name) (h-opt h 'title) (h-req h 'version)
                  (h-opt h 'description) (h-opt h 'websiteUrl)
                  (opt-list (h-opt h 'icons) json->icon)))
(define (implementation->json s)
  (put (put (put (put! (put (put! (hasheq) 'name (implementation-name s))
                            'title (implementation-title s))
                       'version (implementation-version s))
                 'description (implementation-description s))
            'websiteUrl (implementation-website-url s))
       'icons (opt-map (implementation-icons s) (lambda (xs) (map icon->json xs)))))

;; ============================================================================
;; C. Lifecycle / initialize
;; ============================================================================

;; ClientCapabilities (315) / ServerCapabilities (391). Deep trees are loose
;; hasheq blobs (Decisions: structs only for the top record). Modeled as a
;; single `rest` hasheq carrying the whole capability object verbatim, so deep
;; nested values (tasks.requests.sampling.createMessage, etc.) round-trip.
(struct client-capabilities (rest) #:transparent)
(define client-capabilities/c (struct/c client-capabilities json-object?))
(define (json->client-capabilities h) (client-capabilities h))
(define (client-capabilities->json s) (client-capabilities-rest s))

(struct server-capabilities (rest) #:transparent)
(define server-capabilities/c (struct/c server-capabilities json-object?))
(define (json->server-capabilities h) (server-capabilities h))
(define (server-capabilities->json s) (server-capabilities-rest s))

;; InitializeRequestParams (260): PARAMS (drops unknown; meta named only).
(struct initialize-request-params (protocol-version capabilities client-info meta) #:transparent)
(define initialize-request-params/c
  (struct/c initialize-request-params string? client-capabilities? implementation? (opt/c json-object?)))
(define (json->initialize-request-params h)
  (initialize-request-params
   (h-req h 'protocolVersion)
   (json->client-capabilities (h-req h 'capabilities))
   (json->implementation (h-req h 'clientInfo))
   (h-opt h '_meta)))
(define (initialize-request-params->json s)
  (put (put! (put! (put! (hasheq) 'protocolVersion (initialize-request-params-protocol-version s))
                   'capabilities (client-capabilities->json (initialize-request-params-capabilities s)))
             'clientInfo (implementation->json (initialize-request-params-client-info s)))
       '_meta (initialize-request-params-meta s)))

;; InitializeRequest (274).
(struct initialize-request (method payload) #:transparent)
(define initialize-request/c
  (struct/c initialize-request (lit/c "initialize") initialize-request-params?))
(define (json->initialize-request h)
  (initialize-request (h-req h 'method) (json->initialize-request-params (h-req h 'params))))
(define (initialize-request->json s)
  (hasheq 'method (initialize-request-method s)
          'params (initialize-request-params->json (initialize-request-payload s))))

;; InitializeResult (284): RESULT (loose). protocolVersion, capabilities,
;; serverInfo, instructions?, meta?, rest.
(struct initialize-result (protocol-version capabilities server-info instructions meta rest) #:transparent)
(define initialize-result/c
  (struct/c initialize-result string? server-capabilities? implementation?
            (opt/c string?) (opt/c json-object?) json-object?))
(define (json->initialize-result h)
  (initialize-result
   (h-req h 'protocolVersion)
   (json->server-capabilities (h-req h 'capabilities))
   (json->implementation (h-req h 'serverInfo))
   (h-opt h 'instructions)
   (h-opt h '_meta)
   (split-loose h '((protocol-version . protocolVersion) (capabilities . capabilities)
                                                         (server-info . serverInfo) (instructions . instructions) (meta . _meta)))))
(define (initialize-result->json s)
  (put (put (put! (put! (put! (hash-merge (initialize-result-rest s))
                              'protocolVersion (initialize-result-protocol-version s))
                        'capabilities (server-capabilities->json (initialize-result-capabilities s)))
                  'serverInfo (implementation->json (initialize-result-server-info s)))
            'instructions (initialize-result-instructions s))
       '_meta (initialize-result-meta s)))

;; InitializedNotification (305): method, params?.
(struct initialized-notification (method params) #:transparent)
(define initialized-notification/c
  (struct/c initialized-notification (lit/c "notifications/initialized") (opt/c json-object?)))
(define (json->initialized-notification h)
  (initialized-notification (h-req h 'method) (h-opt h 'params)))
(define (initialized-notification->json s)
  (put (hasheq 'method (initialized-notification-method s)) 'params (initialized-notification-params s)))

;; ============================================================================
;; D. Ping — line 581. params? is a plain request-params object.
;; ============================================================================
(struct ping-request (method params) #:transparent)
(define ping-request/c (struct/c ping-request (lit/c "ping") (opt/c json-object?)))
(define (json->ping-request h) (ping-request (h-req h 'method) (h-opt h 'params)))
(define (ping-request->json s)
  (put (hasheq 'method (ping-request-method s)) 'params (ping-request-params s)))

;; ============================================================================
;; E. Progress / cancellation
;; ============================================================================

;; CancelledNotificationParams (220): PARAMS (drops unknown). requestId?, reason?, meta?.
(struct cancelled-notification-params (request-id reason meta) #:transparent)
(define cancelled-notification-params/c
  (struct/c cancelled-notification-params (opt/c request-id?) (opt/c string?) (opt/c json-object?)))
(define (json->cancelled-notification-params h)
  (cancelled-notification-params (h-opt h 'requestId) (h-opt h 'reason) (h-opt h '_meta)))
(define (cancelled-notification-params->json s)
  (put (put (put (hasheq) 'requestId (cancelled-notification-params-request-id s))
            'reason (cancelled-notification-params-reason s))
       '_meta (cancelled-notification-params-meta s)))

(struct cancelled-notification (method payload) #:transparent)
(define cancelled-notification/c
  (struct/c cancelled-notification (lit/c "notifications/cancelled") cancelled-notification-params?))
(define (json->cancelled-notification h)
  (cancelled-notification (h-req h 'method) (json->cancelled-notification-params (h-req h 'params))))
(define (cancelled-notification->json s)
  (hasheq 'method (cancelled-notification-method s)
          'params (cancelled-notification-params->json (cancelled-notification-payload s))))

;; ProgressNotificationParams (593): PARAMS. progressToken, progress, total?, message?, meta?.
(struct progress-notification-params (progress-token progress total message meta) #:transparent)
(define progress-notification-params/c
  (struct/c progress-notification-params progress-token? real? (opt/c real?) (opt/c string?) (opt/c json-object?)))
(define (json->progress-notification-params h)
  (progress-notification-params (h-req h 'progressToken) (h-req h 'progress)
                                (h-opt h 'total) (h-opt h 'message) (h-opt h '_meta)))
(define (progress-notification-params->json s)
  (put (put (put (put! (put! (hasheq) 'progressToken (progress-notification-params-progress-token s))
                       'progress (progress-notification-params-progress s))
                 'total (progress-notification-params-total s))
            'message (progress-notification-params-message s))
       '_meta (progress-notification-params-meta s)))

(struct progress-notification (method payload) #:transparent)
(define progress-notification/c
  (struct/c progress-notification (lit/c "notifications/progress") progress-notification-params?))
(define (json->progress-notification h)
  (progress-notification (h-req h 'method) (json->progress-notification-params (h-req h 'params))))
(define (progress-notification->json s)
  (hasheq 'method (progress-notification-method s)
          'params (progress-notification-params->json (progress-notification-payload s))))

;; ============================================================================
;; F. Pagination bases (internal; modeled as structs too for completeness)
;; ============================================================================
(struct paginated-request-params (cursor meta) #:transparent)   ; PARAMS
(define paginated-request-params/c
  (struct/c paginated-request-params (opt/c cursor/c) (opt/c json-object?)))
(define (json->paginated-request-params h)
  (paginated-request-params (h-opt h 'cursor) (h-opt h '_meta)))
(define (paginated-request-params->json s)
  (put (put (hasheq) 'cursor (paginated-request-params-cursor s))
       '_meta (paginated-request-params-meta s)))

(struct paginated-result (next-cursor meta rest) #:transparent) ; RESULT (loose)
(define paginated-result/c
  (struct/c paginated-result (opt/c cursor/c) (opt/c json-object?) json-object?))
(define (json->paginated-result h)
  (paginated-result (h-opt h 'nextCursor) (h-opt h '_meta)
                    (split-loose h '((next-cursor . nextCursor) (meta . _meta)))))
(define (paginated-result->json s)
  (put (put (hash-merge (paginated-result-rest s)) 'nextCursor (paginated-result-next-cursor s))
       '_meta (paginated-result-meta s)))

;; Helper: deserialize/serialize a no-payload params? request (list-style).
;; Used by the simple list requests whose params are optional & untyped here.
(define (json->simple-request h) (cons (h-req h 'method) (h-opt h 'params)))

;; ============================================================================
;; G. Resources
;; ============================================================================

;; ListResourcesRequest (660): method, params? (paginated -> plain object|absent).
(struct list-resources-request (method params) #:transparent)
(define list-resources-request/c
  (struct/c list-resources-request (lit/c "resources/list") (opt/c json-object?)))
(define (json->list-resources-request h)
  (list-resources-request (h-req h 'method) (h-opt h 'params)))
(define (list-resources-request->json s)
  (put (hasheq 'method (list-resources-request-method s)) 'params (list-resources-request-params s)))

;; Resource (807): RESULT-adjacent loose (has _meta passthrough).
(struct resource (name title uri description mime-type annotations size icons meta rest) #:transparent)
(define resource/c
  (struct/c resource string? (opt/c string?) string? (opt/c string?) (opt/c string?)
            (opt/c annotations?) (opt/c real?) (opt/c (listof icon?)) (opt/c json-object?) json-object?))
(define resource-known-table
  '((name . name) (title . title) (uri . uri) (description . description)
                  (mime-type . mimeType) (annotations . annotations) (size . size) (icons . icons) (meta . _meta)))
(define (json->resource h)
  (resource (h-req h 'name) (h-opt h 'title) (h-req h 'uri) (h-opt h 'description)
            (h-opt h 'mimeType) (opt-map (h-opt h 'annotations) json->annotations)
            (h-opt h 'size) (opt-list (h-opt h 'icons) json->icon) (h-opt h '_meta)
            (split-loose h resource-known-table)))
(define (resource->json s)
  (put (put (put (put (put (put (put (put! (put! (hash-merge (resource-rest s))
                                                 'name (resource-name s))
                                           'uri (resource-uri s))
                                     'title (resource-title s))
                                'description (resource-description s))
                           'mimeType (resource-mime-type s))
                      'annotations (opt-map (resource-annotations s) annotations->json))
                 'size (resource-size s))
            'icons (opt-map (resource-icons s) (lambda (xs) (map icon->json xs))))
       '_meta (resource-meta s)))

;; ResourceTemplate (850).
(struct resource-template (name title uri-template description mime-type annotations icons meta rest) #:transparent)
(define resource-template/c
  (struct/c resource-template string? (opt/c string?) string? (opt/c string?) (opt/c string?)
            (opt/c annotations?) (opt/c (listof icon?)) (opt/c json-object?) json-object?))
(define resource-template-known-table
  '((name . name) (title . title) (uri-template . uriTemplate) (description . description)
                  (mime-type . mimeType) (annotations . annotations) (icons . icons) (meta . _meta)))
(define (json->resource-template h)
  (resource-template (h-req h 'name) (h-opt h 'title) (h-req h 'uriTemplate) (h-opt h 'description)
                     (h-opt h 'mimeType) (opt-map (h-opt h 'annotations) json->annotations)
                     (opt-list (h-opt h 'icons) json->icon) (h-opt h '_meta)
                     (split-loose h resource-template-known-table)))
(define (resource-template->json s)
  (put (put (put (put (put (put (put! (put! (hash-merge (resource-template-rest s))
                                            'name (resource-template-name s))
                                      'uriTemplate (resource-template-uri-template s))
                                'title (resource-template-title s))
                           'description (resource-template-description s))
                      'mimeType (resource-template-mime-type s))
                 'annotations (opt-map (resource-template-annotations s) annotations->json))
            'icons (opt-map (resource-template-icons s) (lambda (xs) (map icon->json xs))))
       '_meta (resource-template-meta s)))

;; ListResourcesResult (669): resources, nextCursor?, loose.
(struct list-resources-result (resources next-cursor meta rest) #:transparent)
(define list-resources-result/c
  (struct/c list-resources-result (listof resource?) (opt/c cursor/c) (opt/c json-object?) json-object?))
(define (json->list-resources-result h)
  (list-resources-result (req-list (h-req h 'resources) json->resource)
                         (h-opt h 'nextCursor) (h-opt h '_meta)
                         (split-loose h '((resources . resources) (next-cursor . nextCursor) (meta . _meta)))))
(define (list-resources-result->json s)
  (put (put (put! (hash-merge (list-resources-result-rest s))
                  'resources (map resource->json (list-resources-result-resources s)))
            'nextCursor (list-resources-result-next-cursor s))
       '_meta (list-resources-result-meta s)))

;; ListResourceTemplatesRequest (678).
(struct list-resource-templates-request (method params) #:transparent)
(define list-resource-templates-request/c
  (struct/c list-resource-templates-request (lit/c "resources/templates/list") (opt/c json-object?)))
(define (json->list-resource-templates-request h)
  (list-resource-templates-request (h-req h 'method) (h-opt h 'params)))
(define (list-resource-templates-request->json s)
  (put (hasheq 'method (list-resource-templates-request-method s))
       'params (list-resource-templates-request-params s)))

;; ListResourceTemplatesResult (687).
(struct list-resource-templates-result (resource-templates next-cursor meta rest) #:transparent)
(define list-resource-templates-result/c
  (struct/c list-resource-templates-result (listof resource-template?) (opt/c cursor/c) (opt/c json-object?) json-object?))
(define (json->list-resource-templates-result h)
  (list-resource-templates-result (req-list (h-req h 'resourceTemplates) json->resource-template)
                                  (h-opt h 'nextCursor) (h-opt h '_meta)
                                  (split-loose h '((resource-templates . resourceTemplates) (next-cursor . nextCursor) (meta . _meta)))))
(define (list-resource-templates-result->json s)
  (put (put (put! (hash-merge (list-resource-templates-result-rest s))
                  'resourceTemplates (map resource-template->json (list-resource-templates-result-resource-templates s)))
            'nextCursor (list-resource-templates-result-next-cursor s))
       '_meta (list-resource-templates-result-meta s)))

;; ReadResourceRequestParams (711): PARAMS. uri, meta?.
(struct read-resource-request-params (uri meta) #:transparent)
(define read-resource-request-params/c
  (struct/c read-resource-request-params string? (opt/c json-object?)))
(define (json->read-resource-request-params h)
  (read-resource-request-params (h-req h 'uri) (h-opt h '_meta)))
(define (read-resource-request-params->json s)
  (put (put! (hasheq) 'uri (read-resource-request-params-uri s))
       '_meta (read-resource-request-params-meta s)))

(struct read-resource-request (method payload) #:transparent)
(define read-resource-request/c
  (struct/c read-resource-request (lit/c "resources/read") read-resource-request-params?))
(define (json->read-resource-request h)
  (read-resource-request (h-req h 'method) (json->read-resource-request-params (h-req h 'params))))
(define (read-resource-request->json s)
  (hasheq 'method (read-resource-request-method s)
          'params (read-resource-request-params->json (read-resource-request-payload s))))

;; ResourceContents family (886/907/917). Discriminator: `text` vs `blob` key.
(struct text-resource-contents (uri mime-type text meta) #:transparent)
(define text-resource-contents/c
  (struct/c text-resource-contents string? (opt/c string?) string? (opt/c json-object?)))
(define (json->text-resource-contents h)
  (text-resource-contents (h-req h 'uri) (h-opt h 'mimeType) (h-req h 'text) (h-opt h '_meta)))
(define (text-resource-contents->json s)
  (put (put (put! (put! (hasheq) 'uri (text-resource-contents-uri s))
                  'text (text-resource-contents-text s))
            'mimeType (text-resource-contents-mime-type s))
       '_meta (text-resource-contents-meta s)))

(struct blob-resource-contents (uri mime-type blob meta) #:transparent)
(define blob-resource-contents/c
  (struct/c blob-resource-contents string? (opt/c string?) string? (opt/c json-object?)))
(define (json->blob-resource-contents h)
  (blob-resource-contents (h-req h 'uri) (h-opt h 'mimeType) (h-req h 'blob) (h-opt h '_meta)))
(define (blob-resource-contents->json s)
  (put (put (put! (put! (hasheq) 'uri (blob-resource-contents-uri s))
                  'blob (blob-resource-contents-blob s))
            'mimeType (blob-resource-contents-mime-type s))
       '_meta (blob-resource-contents-meta s)))

(define resource-contents/c (or/c text-resource-contents? blob-resource-contents?))
(define (json->resource-contents h)
  (cond [(hash-has-key? h 'text) (json->text-resource-contents h)]
        [(hash-has-key? h 'blob) (json->blob-resource-contents h)]
        [else (error 'json->resource-contents "neither text nor blob: ~a" h)]))
(define (resource-contents->json s)
  (cond [(text-resource-contents? s) (text-resource-contents->json s)]
        [(blob-resource-contents? s) (blob-resource-contents->json s)]
        [else (error 'resource-contents->json "not a resource-contents: ~a" s)]))

;; ReadResourceResult (728): contents (list of text|blob contents).
(struct read-resource-result (contents meta rest) #:transparent)
(define read-resource-result/c
  (struct/c read-resource-result (listof resource-contents/c) (opt/c json-object?) json-object?))
(define (json->read-resource-result h)
  (read-resource-result (req-list (h-req h 'contents) json->resource-contents)
                        (h-opt h '_meta)
                        (split-loose h '((contents . contents) (meta . _meta)))))
(define (read-resource-result->json s)
  (put (put! (hash-merge (read-resource-result-rest s))
             'contents (map resource-contents->json (read-resource-result-contents s)))
       '_meta (read-resource-result-meta s)))

;; SubscribeRequestParams (748) / SubscribeRequest (755).
(struct subscribe-request-params (uri meta) #:transparent)
(define subscribe-request-params/c
  (struct/c subscribe-request-params string? (opt/c json-object?)))
(define (json->subscribe-request-params h)
  (subscribe-request-params (h-req h 'uri) (h-opt h '_meta)))
(define (subscribe-request-params->json s)
  (put (put! (hasheq) 'uri (subscribe-request-params-uri s)) '_meta (subscribe-request-params-meta s)))
(struct subscribe-request (method payload) #:transparent)
(define subscribe-request/c
  (struct/c subscribe-request (lit/c "resources/subscribe") subscribe-request-params?))
(define (json->subscribe-request h)
  (subscribe-request (h-req h 'method) (json->subscribe-request-params (h-req h 'params))))
(define (subscribe-request->json s)
  (hasheq 'method (subscribe-request-method s)
          'params (subscribe-request-params->json (subscribe-request-payload s))))

;; UnsubscribeRequestParams (766) / UnsubscribeRequest (773).
(struct unsubscribe-request-params (uri meta) #:transparent)
(define unsubscribe-request-params/c
  (struct/c unsubscribe-request-params string? (opt/c json-object?)))
(define (json->unsubscribe-request-params h)
  (unsubscribe-request-params (h-req h 'uri) (h-opt h '_meta)))
(define (unsubscribe-request-params->json s)
  (put (put! (hasheq) 'uri (unsubscribe-request-params-uri s)) '_meta (unsubscribe-request-params-meta s)))
(struct unsubscribe-request (method payload) #:transparent)
(define unsubscribe-request/c
  (struct/c unsubscribe-request (lit/c "resources/unsubscribe") unsubscribe-request-params?))
(define (json->unsubscribe-request h)
  (unsubscribe-request (h-req h 'method) (json->unsubscribe-request-params (h-req h 'params))))
(define (unsubscribe-request->json s)
  (hasheq 'method (unsubscribe-request-method s)
          'params (unsubscribe-request-params->json (unsubscribe-request-payload s))))

;; ResourceUpdatedNotificationParams (783) / Notification (797).
(struct resource-updated-notification-params (uri meta) #:transparent)
(define resource-updated-notification-params/c
  (struct/c resource-updated-notification-params string? (opt/c json-object?)))
(define (json->resource-updated-notification-params h)
  (resource-updated-notification-params (h-req h 'uri) (h-opt h '_meta)))
(define (resource-updated-notification-params->json s)
  (put (put! (hasheq) 'uri (resource-updated-notification-params-uri s))
       '_meta (resource-updated-notification-params-meta s)))
(struct resource-updated-notification (method payload) #:transparent)
(define resource-updated-notification/c
  (struct/c resource-updated-notification (lit/c "notifications/resources/updated") resource-updated-notification-params?))
(define (json->resource-updated-notification h)
  (resource-updated-notification (h-req h 'method) (json->resource-updated-notification-params (h-req h 'params))))
(define (resource-updated-notification->json s)
  (hasheq 'method (resource-updated-notification-method s)
          'params (resource-updated-notification-params->json (resource-updated-notification-payload s))))

;; ResourceListChangedNotification (737).
(struct resource-list-changed-notification (method params) #:transparent)
(define resource-list-changed-notification/c
  (struct/c resource-list-changed-notification (lit/c "notifications/resources/list_changed") (opt/c json-object?)))
(define (json->resource-list-changed-notification h)
  (resource-list-changed-notification (h-req h 'method) (h-opt h 'params)))
(define (resource-list-changed-notification->json s)
  (put (hasheq 'method (resource-list-changed-notification-method s))
       'params (resource-list-changed-notification-params s)))

;; ============================================================================
;; M. Content blocks (defined before L/sampling which references them; and
;; before §H prompt-message which already used content-block/c — Racket allows
;; forward reference inside function bodies since they're not called at load.)
;; ============================================================================

;; TextContent (1739).
(struct text-content (text annotations meta) #:transparent)
(define text-content/c
  (struct/c text-content string? (opt/c annotations?) (opt/c json-object?)))
(define (json->text-content h)
  (text-content (h-req h 'text) (opt-map (h-opt h 'annotations) json->annotations) (h-opt h '_meta)))
(define (text-content->json s)
  (put (put (put! (put! (hasheq) 'type "text") 'text (text-content-text s))
            'annotations (opt-map (text-content-annotations s) annotations->json))
       '_meta (text-content-meta s)))

;; ImageContent (1763).
(struct image-content (data mime-type annotations meta) #:transparent)
(define image-content/c
  (struct/c image-content string? string? (opt/c annotations?) (opt/c json-object?)))
(define (json->image-content h)
  (image-content (h-req h 'data) (h-req h 'mimeType)
                 (opt-map (h-opt h 'annotations) json->annotations) (h-opt h '_meta)))
(define (image-content->json s)
  (put (put (put! (put! (put! (hasheq) 'type "image") 'data (image-content-data s))
                  'mimeType (image-content-mime-type s))
            'annotations (opt-map (image-content-annotations s) annotations->json))
       '_meta (image-content-meta s)))

;; AudioContent (1794).
(struct audio-content (data mime-type annotations meta) #:transparent)
(define audio-content/c
  (struct/c audio-content string? string? (opt/c annotations?) (opt/c json-object?)))
(define (json->audio-content h)
  (audio-content (h-req h 'data) (h-req h 'mimeType)
                 (opt-map (h-opt h 'annotations) json->annotations) (h-opt h '_meta)))
(define (audio-content->json s)
  (put (put (put! (put! (put! (hasheq) 'type "audio") 'data (audio-content-data s))
                  'mimeType (audio-content-mime-type s))
            'annotations (opt-map (audio-content-annotations s) annotations->json))
       '_meta (audio-content-meta s)))

;; ResourceLink (1049): resource fields + type="resource_link".
(struct resource-link (name title uri description mime-type annotations size icons meta rest) #:transparent)
(define resource-link/c
  (struct/c resource-link string? (opt/c string?) string? (opt/c string?) (opt/c string?)
            (opt/c annotations?) (opt/c real?) (opt/c (listof icon?)) (opt/c json-object?) json-object?))
(define resource-link-known-table
  '((name . name) (title . title) (uri . uri) (description . description)
                  (mime-type . mimeType) (annotations . annotations) (size . size) (icons . icons)
                  (meta . _meta) (type . type)))
(define (json->resource-link h)
  (resource-link (h-req h 'name) (h-opt h 'title) (h-req h 'uri) (h-opt h 'description)
                 (h-opt h 'mimeType) (opt-map (h-opt h 'annotations) json->annotations)
                 (h-opt h 'size) (opt-list (h-opt h 'icons) json->icon) (h-opt h '_meta)
                 (split-loose h resource-link-known-table)))
(define (resource-link->json s)
  (put (put (put (put (put (put (put (put! (put! (put! (hash-merge (resource-link-rest s))
                                                       'type "resource_link")
                                                 'name (resource-link-name s))
                                           'uri (resource-link-uri s))
                                      'title (resource-link-title s))
                                 'description (resource-link-description s))
                            'mimeType (resource-link-mime-type s))
                       'annotations (opt-map (resource-link-annotations s) annotations->json))
                  'size (resource-link-size s))
             'icons (opt-map (resource-link-icons s) (lambda (xs) (map icon->json xs))))
       '_meta (resource-link-meta s)))

;; EmbeddedResource (1061): type="resource", resource (text|blob contents).
(struct embedded-resource (resource annotations meta) #:transparent)
(define embedded-resource/c
  (struct/c embedded-resource resource-contents/c (opt/c annotations?) (opt/c json-object?)))
(define (json->embedded-resource h)
  (embedded-resource (json->resource-contents (h-req h 'resource))
                     (opt-map (h-opt h 'annotations) json->annotations) (h-opt h '_meta)))
(define (embedded-resource->json s)
  (put (put (put! (put! (hasheq) 'type "resource")
                  'resource (resource-contents->json (embedded-resource-resource s)))
            'annotations (opt-map (embedded-resource-annotations s) annotations->json))
       '_meta (embedded-resource-meta s)))

(define content-block/c
  (or/c text-content? image-content? audio-content? resource-link? embedded-resource?))
(define (json->content-block h)
  (case (h-req h 'type)
    [("text") (json->text-content h)]
    [("image") (json->image-content h)]
    [("audio") (json->audio-content h)]
    [("resource_link") (json->resource-link h)]
    [("resource") (json->embedded-resource h)]
    [else (error 'json->content-block "unknown content block type: ~a" (h-req h 'type))]))
(define (content-block->json s)
  (cond [(text-content? s) (text-content->json s)]
        [(image-content? s) (image-content->json s)]
        [(audio-content? s) (audio-content->json s)]
        [(resource-link? s) (resource-link->json s)]
        [(embedded-resource? s) (embedded-resource->json s)]
        [else (error 'content-block->json "not a content block: ~a" s)]))

;; SamplingMessageContentBlock union (1690): text|image|audio|tool_use|tool_result.

;; ToolUseContent (1825): type="tool_use", id, name, input, meta?.
(struct tool-use-content (id name input meta) #:transparent)
(define tool-use-content/c
  (struct/c tool-use-content string? string? json-object? (opt/c json-object?)))
(define (json->tool-use-content h)
  (tool-use-content (h-req h 'id) (h-req h 'name) (h-req h 'input) (h-opt h '_meta)))
(define (tool-use-content->json s)
  (put (put! (put! (put! (hasheq 'type "tool_use") 'id (tool-use-content-id s))
                   'name (tool-use-content-name s))
             'input (tool-use-content-input s))
       '_meta (tool-use-content-meta s)))

;; ToolResultContent (1859): type="tool_result", toolUseId, content (list), structuredContent?, isError?, meta?.
(struct tool-result-content (tool-use-id content structured-content is-error meta) #:transparent)
(define tool-result-content/c
  (struct/c tool-result-content string? (listof content-block/c) (opt/c json-object?) (opt/c boolean?) (opt/c json-object?)))
(define (json->tool-result-content h)
  (tool-result-content (h-req h 'toolUseId) (req-list (h-req h 'content) json->content-block)
                       (h-opt h 'structuredContent) (h-opt h 'isError) (h-opt h '_meta)))
(define (tool-result-content->json s)
  (put (put (put (put! (put! (hasheq 'type "tool_result") 'toolUseId (tool-result-content-tool-use-id s))
                       'content (map content-block->json (tool-result-content-content s)))
                 'structuredContent (tool-result-content-structured-content s))
            'isError (tool-result-content-is-error s))
       '_meta (tool-result-content-meta s)))

;; ContentBlock union (1732): text|image|audio|resource_link|resource.
(define sampling-message-content-block/c
  (or/c text-content? image-content? audio-content? tool-use-content? tool-result-content?))
(define (json->sampling-message-content-block h)
  (case (h-req h 'type)
    [("text") (json->text-content h)]
    [("image") (json->image-content h)]
    [("audio") (json->audio-content h)]
    [("tool_use") (json->tool-use-content h)]
    [("tool_result") (json->tool-result-content h)]
    [else (error 'json->sampling-message-content-block "unknown type: ~a" (h-req h 'type))]))
(define (sampling-message-content-block->json s)
  (cond [(text-content? s) (text-content->json s)]
        [(image-content? s) (image-content->json s)]
        [(audio-content? s) (audio-content->json s)]
        [(tool-use-content? s) (tool-use-content->json s)]
        [(tool-result-content? s) (tool-result-content->json s)]
        [else (error 'sampling-message-content-block->json "not a sampling content block: ~a" s)]))

;; ============================================================================
;; H. Prompts
;; ============================================================================
(struct list-prompts-request (method params) #:transparent)
(define list-prompts-request/c
  (struct/c list-prompts-request (lit/c "prompts/list") (opt/c json-object?)))
(define (json->list-prompts-request h) (list-prompts-request (h-req h 'method) (h-opt h 'params)))
(define (list-prompts-request->json s)
  (put (hasheq 'method (list-prompts-request-method s)) 'params (list-prompts-request-params s)))

(struct prompt-argument (name title description required) #:transparent)
(define prompt-argument/c
  (struct/c prompt-argument string? (opt/c string?) (opt/c string?) (opt/c boolean?)))
(define (json->prompt-argument h)
  (prompt-argument (h-req h 'name) (h-opt h 'title) (h-opt h 'description) (h-opt h 'required)))
(define (prompt-argument->json s)
  (put (put (put (put! (hasheq) 'name (prompt-argument-name s))
                 'title (prompt-argument-title s))
            'description (prompt-argument-description s))
       'required (prompt-argument-required s)))

(struct prompt (name title description arguments icons meta rest) #:transparent)
(define prompt/c
  (struct/c prompt string? (opt/c string?) (opt/c string?) (opt/c (listof prompt-argument?))
            (opt/c (listof icon?)) (opt/c json-object?) json-object?))
(define (json->prompt h)
  (prompt (h-req h 'name) (h-opt h 'title) (h-opt h 'description)
          (opt-list (h-opt h 'arguments) json->prompt-argument)
          (opt-list (h-opt h 'icons) json->icon) (h-opt h '_meta)
          (split-loose h '((name . name) (title . title) (description . description)
                                         (arguments . arguments) (icons . icons) (meta . _meta)))))
(define (prompt->json s)
  (put (put (put (put (put! (put (hash-merge (prompt-rest s)) 'title (prompt-title s))
                            'name (prompt-name s))
                      'description (prompt-description s))
                 'arguments (opt-map (prompt-arguments s) (lambda (xs) (map prompt-argument->json xs))))
            'icons (opt-map (prompt-icons s) (lambda (xs) (map icon->json xs))))
       '_meta (prompt-meta s)))

;; ListPromptsResult (941).
(struct list-prompts-result (prompts next-cursor meta rest) #:transparent)
(define list-prompts-result/c
  (struct/c list-prompts-result (listof prompt?) (opt/c cursor/c) (opt/c json-object?) json-object?))
(define (json->list-prompts-result h)
  (list-prompts-result (req-list (h-req h 'prompts) json->prompt) (h-opt h 'nextCursor) (h-opt h '_meta)
                       (split-loose h '((prompts . prompts) (next-cursor . nextCursor) (meta . _meta)))))
(define (list-prompts-result->json s)
  (put (put (put! (hash-merge (list-prompts-result-rest s))
                  'prompts (map prompt->json (list-prompts-result-prompts s)))
            'nextCursor (list-prompts-result-next-cursor s))
       '_meta (list-prompts-result-meta s)))

;; GetPromptRequestParams (950): PARAMS. name, arguments? (string->string), meta?.
(struct get-prompt-request-params (name arguments meta) #:transparent)
(define get-prompt-request-params/c
  (struct/c get-prompt-request-params string? (opt/c json-object?) (opt/c json-object?)))
(define (json->get-prompt-request-params h)
  (get-prompt-request-params (h-req h 'name) (h-opt h 'arguments) (h-opt h '_meta)))
(define (get-prompt-request-params->json s)
  (put (put (put! (hasheq) 'name (get-prompt-request-params-name s))
            'arguments (get-prompt-request-params-arguments s))
       '_meta (get-prompt-request-params-meta s)))
(struct get-prompt-request (method payload) #:transparent)
(define get-prompt-request/c
  (struct/c get-prompt-request (lit/c "prompts/get") get-prompt-request-params?))
(define (json->get-prompt-request h)
  (get-prompt-request (h-req h 'method) (json->get-prompt-request-params (h-req h 'params))))
(define (get-prompt-request->json s)
  (hasheq 'method (get-prompt-request-method s)
          'params (get-prompt-request-params->json (get-prompt-request-payload s))))

;; PromptMessage (1037): role, content (content-block).
(struct prompt-message (role content) #:transparent)
(define prompt-message/c (struct/c prompt-message role/c content-block/c))
(define (json->prompt-message h)
  (prompt-message (h-req h 'role) (json->content-block (h-req h 'content))))
(define (prompt-message->json s)
  (hasheq 'role (prompt-message-role s) 'content (content-block->json (prompt-message-content s))))

;; GetPromptResult (976): description?, messages, loose.
(struct get-prompt-result (description messages meta rest) #:transparent)
(define get-prompt-result/c
  (struct/c get-prompt-result (opt/c string?) (listof prompt-message?) (opt/c json-object?) json-object?))
(define (json->get-prompt-result h)
  (get-prompt-result (h-opt h 'description) (req-list (h-req h 'messages) json->prompt-message)
                     (h-opt h '_meta)
                     (split-loose h '((description . description) (messages . messages) (meta . _meta)))))
(define (get-prompt-result->json s)
  (put (put (put! (hash-merge (get-prompt-result-rest s))
                  'messages (map prompt-message->json (get-prompt-result-messages s)))
            'description (get-prompt-result-description s))
       '_meta (get-prompt-result-meta s)))

;; PromptListChangedNotification (1080).
(struct prompt-list-changed-notification (method params) #:transparent)
(define prompt-list-changed-notification/c
  (struct/c prompt-list-changed-notification (lit/c "notifications/prompts/list_changed") (opt/c json-object?)))
(define (json->prompt-list-changed-notification h)
  (prompt-list-changed-notification (h-req h 'method) (h-opt h 'params)))
(define (prompt-list-changed-notification->json s)
  (put (hasheq 'method (prompt-list-changed-notification-method s))
       'params (prompt-list-changed-notification-params s)))

;; ============================================================================
;; I. Tools
;; ============================================================================
(struct list-tools-request (method params) #:transparent)
(define list-tools-request/c
  (struct/c list-tools-request (lit/c "tools/list") (opt/c json-object?)))
(define (json->list-tools-request h) (list-tools-request (h-req h 'method) (h-opt h 'params)))
(define (list-tools-request->json s)
  (put (hasheq 'method (list-tools-request-method s)) 'params (list-tools-request-params s)))

(struct tool-annotations (title read-only-hint destructive-hint idempotent-hint open-world-hint) #:transparent)
(define tool-annotations/c
  (struct/c tool-annotations (opt/c string?) (opt/c boolean?) (opt/c boolean?) (opt/c boolean?) (opt/c boolean?)))
(define (json->tool-annotations h)
  (tool-annotations (h-opt h 'title) (h-opt h 'readOnlyHint) (h-opt h 'destructiveHint)
                    (h-opt h 'idempotentHint) (h-opt h 'openWorldHint)))
(define (tool-annotations->json s)
  (put (put (put (put (put (hasheq) 'title (tool-annotations-title s))
                      'readOnlyHint (tool-annotations-read-only-hint s))
                 'destructiveHint (tool-annotations-destructive-hint s))
            'idempotentHint (tool-annotations-idempotent-hint s))
       'openWorldHint (tool-annotations-open-world-hint s)))

(struct tool-execution (task-support) #:transparent)
(define tool-execution/c
  (struct/c tool-execution (opt/c (or/c "forbidden" "optional" "required"))))
(define (json->tool-execution h) (tool-execution (h-opt h 'taskSupport)))
(define (tool-execution->json s)
  (put (hasheq) 'taskSupport (tool-execution-task-support s)))

;; Tool (1254): inputSchema/outputSchema are OPEN JSON-Schema fragments — kept
;; as loose hasheq (preserve $schema verbatim, see Decisions).
(struct tool (name title description input-schema exec output-schema annots icons meta rest) #:transparent)
(define (object-schema-fragment? v)
  ;; an open JSON-Schema object; if `type` present it must be "object".
  (and (json-object? v)
       (let ([t (hash-ref v 'type absent)]) (or (absent? t) (equal? t "object")))))
(define tool/c
  (struct/c tool string? (opt/c string?) (opt/c string?) object-schema-fragment?
            (opt/c tool-execution?) (opt/c object-schema-fragment?) (opt/c tool-annotations?)
            (opt/c (listof icon?)) (opt/c json-object?) json-object?))
(define tool-known-table
  '((name . name) (title . title) (description . description) (input-schema . inputSchema)
                  (execution . execution) (output-schema . outputSchema) (annotations . annotations)
                  (icons . icons) (meta . _meta)))
(define (json->tool h)
  (tool (h-req h 'name) (h-opt h 'title) (h-opt h 'description) (h-req h 'inputSchema)
        (opt-map (h-opt h 'execution) json->tool-execution) (h-opt h 'outputSchema)
        (opt-map (h-opt h 'annotations) json->tool-annotations)
        (opt-list (h-opt h 'icons) json->icon) (h-opt h '_meta)
        (split-loose h tool-known-table)))
(define (tool->json s)
  (put (put (put (put (put (put (put! (put! (put (hash-merge (tool-rest s)) 'title (tool-title s))
                                            'name (tool-name s))
                                      'inputSchema (tool-input-schema s))
                                'description (tool-description s))
                           'execution (opt-map (tool-exec s) tool-execution->json))
                      'outputSchema (tool-output-schema s))
                 'annotations (opt-map (tool-annots s) tool-annotations->json))
            'icons (opt-map (tool-icons s) (lambda (xs) (map icon->json xs))))
       '_meta (tool-meta s)))

;; ListToolsResult (1100).
(struct list-tools-result (tools next-cursor meta rest) #:transparent)
(define list-tools-result/c
  (struct/c list-tools-result (listof tool?) (opt/c cursor/c) (opt/c json-object?) json-object?))
(define (json->list-tools-result h)
  (list-tools-result (req-list (h-req h 'tools) json->tool) (h-opt h 'nextCursor) (h-opt h '_meta)
                     (split-loose h '((tools . tools) (next-cursor . nextCursor) (meta . _meta)))))
(define (list-tools-result->json s)
  (put (put (put! (hash-merge (list-tools-result-rest s))
                  'tools (map tool->json (list-tools-result-tools s)))
            'nextCursor (list-tools-result-next-cursor s))
       '_meta (list-tools-result-meta s)))

;; TaskMetadata (1324): ttl? — request-side `task` field.
(struct task-metadata (ttl) #:transparent)
(define task-metadata/c (struct/c task-metadata (opt/c real?)))
(define (json->task-metadata h) (task-metadata (h-opt h 'ttl)))
(define (task-metadata->json s) (put (hasheq) 'ttl (task-metadata-ttl s)))

;; CallToolRequestParams (1142): PARAMS. name, arguments?, task?, meta?.
(struct call-tool-request-params (name arguments task meta) #:transparent)
(define call-tool-request-params/c
  (struct/c call-tool-request-params string? (opt/c json-object?) (opt/c task-metadata?) (opt/c json-object?)))
(define (json->call-tool-request-params h)
  (call-tool-request-params (h-req h 'name) (h-opt h 'arguments)
                            (opt-map (h-opt h 'task) json->task-metadata) (h-opt h '_meta)))
(define (call-tool-request-params->json s)
  (put (put (put (put! (hasheq) 'name (call-tool-request-params-name s))
                 'arguments (call-tool-request-params-arguments s))
            'task (opt-map (call-tool-request-params-task s) task-metadata->json))
       '_meta (call-tool-request-params-meta s)))
(struct call-tool-request (method payload) #:transparent)
(define call-tool-request/c
  (struct/c call-tool-request (lit/c "tools/call") call-tool-request-params?))
(define (json->call-tool-request h)
  (call-tool-request (h-req h 'method) (json->call-tool-request-params (h-req h 'params))))
(define (call-tool-request->json s)
  (hasheq 'method (call-tool-request-method s)
          'params (call-tool-request-params->json (call-tool-request-payload s))))

;; CallToolResult (1109): content, structuredContent?, isError?, loose.
(struct call-tool-result (content structured-content is-error meta rest) #:transparent)
(define call-tool-result/c
  (struct/c call-tool-result (listof content-block/c) (opt/c json-object?) (opt/c boolean?) (opt/c json-object?) json-object?))
(define (json->call-tool-result h)
  (call-tool-result (req-list (h-req h 'content) json->content-block)
                    (h-opt h 'structuredContent) (h-opt h 'isError) (h-opt h '_meta)
                    (split-loose h '((content . content) (structured-content . structuredContent)
                                                         (is-error . isError) (meta . _meta)))))
(define (call-tool-result->json s)
  (put (put (put (put! (hash-merge (call-tool-result-rest s))
                       'content (map content-block->json (call-tool-result-content s)))
                 'structuredContent (call-tool-result-structured-content s))
            'isError (call-tool-result-is-error s))
       '_meta (call-tool-result-meta s)))

;; ToolListChangedNotification (1168).
(struct tool-list-changed-notification (method params) #:transparent)
(define tool-list-changed-notification/c
  (struct/c tool-list-changed-notification (lit/c "notifications/tools/list_changed") (opt/c json-object?)))
(define (json->tool-list-changed-notification h)
  (tool-list-changed-notification (h-req h 'method) (h-opt h 'params)))
(define (tool-list-changed-notification->json s)
  (put (hasheq 'method (tool-list-changed-notification-method s))
       'params (tool-list-changed-notification-params s)))

;; ============================================================================
;; J. Tasks
;; ============================================================================

;; RelatedTaskMetadata (1337): taskId. (rides inside _meta)
(struct related-task-metadata (task-id) #:transparent)
(define related-task-metadata/c (struct/c related-task-metadata string?))
(define (json->related-task-metadata h) (related-task-metadata (h-req h 'taskId)))
(define (related-task-metadata->json s) (hasheq 'taskId (related-task-metadata-task-id s)))

;; Task (1349): ttl is number|null REQUIRED (only |null field).
(struct task (task-id status status-message created-at last-updated-at ttl poll-interval) #:transparent)
(define task/c
  (struct/c task string? task-status/c (opt/c string?) string? string?
            (or/c 'null real?) (opt/c real?)))
(define (json->task h)
  (define ttl (h-req h 'ttl))
  (when (absent? ttl) (error 'json->task "required field ttl missing"))
  (task (h-req h 'taskId) (h-req h 'status) (h-opt h 'statusMessage)
        (h-req h 'createdAt) (h-req h 'lastUpdatedAt) ttl (h-opt h 'pollInterval)))
(define (task->json s)
  ;; ttl is required & nullable: always emit (a present 'null -> JSON null).
  (put (put (put! (put! (put! (put! (put! (hasheq) 'taskId (task-task-id s))
                                    'status (task-status s))
                              'createdAt (task-created-at s))
                        'lastUpdatedAt (task-last-updated-at s))
                  'ttl (task-ttl s))
            'statusMessage (task-status-message s))
       'pollInterval (task-poll-interval s)))

;; Task field table for the intersection flatten (Result & Task).
(define task-fields-table
  '((task-id . taskId) (status . status) (status-message . statusMessage)
                       (created-at . createdAt) (last-updated-at . lastUpdatedAt) (ttl . ttl)
                       (poll-interval . pollInterval) (meta . _meta)))

;; deserialize the flat Task fields from a hash into the 7 task accessors.
(define (read-task-fields h)
  (define ttl (h-req h 'ttl))
  (when (absent? ttl) (error 'read-task-fields "required field ttl missing"))
  (values (h-req h 'taskId) (h-req h 'status) (h-opt h 'statusMessage)
          (h-req h 'createdAt) (h-req h 'lastUpdatedAt) ttl (h-opt h 'pollInterval)))

;; CreateTaskResult (1396): task, loose.
(struct create-task-result (task meta rest) #:transparent)
(define create-task-result/c
  (struct/c create-task-result task? (opt/c json-object?) json-object?))
(define (json->create-task-result h)
  (create-task-result (json->task (h-req h 'task)) (h-opt h '_meta)
                      (split-loose h '((task . task) (meta . _meta)))))
(define (create-task-result->json s)
  (put (put! (hash-merge (create-task-result-rest s)) 'task (task->json (create-task-result-task s)))
       '_meta (create-task-result-meta s)))

;; task-id params (shared shape for get/result/cancel).
(struct task-id-params (task-id meta) #:transparent)
(define task-id-params/c (struct/c task-id-params string? (opt/c json-object?)))
(define (json->task-id-params h) (task-id-params (h-req h 'taskId) (h-opt h '_meta)))
(define (task-id-params->json s)
  (put (put! (hasheq) 'taskId (task-id-params-task-id s)) '_meta (task-id-params-meta s)))

;; GetTaskRequest (1405).
(struct get-task-request (method params) #:transparent)
(define get-task-request/c (struct/c get-task-request (lit/c "tasks/get") task-id-params?))
(define (json->get-task-request h)
  (get-task-request (h-req h 'method) (json->task-id-params (h-req h 'params))))
(define (get-task-request->json s)
  (hasheq 'method (get-task-request-method s)
          'params (task-id-params->json (get-task-request-params s))))

;; GetTaskResult (1420): Result & Task — flattened. Task fields at top level.
(struct get-task-result (task-id status status-message created-at last-updated-at ttl poll-interval meta rest) #:transparent)
(define get-task-result/c
  (struct/c get-task-result string? task-status/c (opt/c string?) string? string?
            (or/c 'null real?) (opt/c real?) (opt/c json-object?) json-object?))
(define (read-task-rest h) (split-loose h task-fields-table))
(define (json->get-task-result h)
  (define-values (id st sm ca lu ttl pi) (read-task-fields h))
  (get-task-result id st sm ca lu ttl pi (h-opt h '_meta) (read-task-rest h)))
(define (emit-task-fields base id st sm ca lu ttl pi meta)
  (put (put (put! (put! (put! (put! (put! base 'taskId id) 'status st) 'createdAt ca)
                        'lastUpdatedAt lu)
                  'ttl ttl)
            'statusMessage sm)
       'pollInterval pi))
(define (get-task-result->json s)
  (put (emit-task-fields (hash-merge (get-task-result-rest s))
                         (get-task-result-task-id s) (get-task-result-status s)
                         (get-task-result-status-message s) (get-task-result-created-at s)
                         (get-task-result-last-updated-at s) (get-task-result-ttl s)
                         (get-task-result-poll-interval s) (get-task-result-meta s))
       '_meta (get-task-result-meta s)))

;; GetTaskPayloadRequest (1427).
(struct get-task-payload-request (method params) #:transparent)
(define get-task-payload-request/c
  (struct/c get-task-payload-request (lit/c "tasks/result") task-id-params?))
(define (json->get-task-payload-request h)
  (get-task-payload-request (h-req h 'method) (json->task-id-params (h-req h 'params))))
(define (get-task-payload-request->json s)
  (hasheq 'method (get-task-payload-request-method s)
          'params (task-id-params->json (get-task-payload-request-params s))))

;; GetTaskPayloadResult (1444): fully open — meta? + rest (holds wrapped result).
(struct get-task-payload-result (meta rest) #:transparent)
(define get-task-payload-result/c (struct/c get-task-payload-result (opt/c json-object?) json-object?))
(define (json->get-task-payload-result h)
  (get-task-payload-result (h-opt h '_meta) (split-loose h '((meta . _meta)))))
(define (get-task-payload-result->json s)
  (put (hash-merge (get-task-payload-result-rest s)) '_meta (get-task-payload-result-meta s)))

;; CancelTaskRequest (1453).
(struct cancel-task-request (method params) #:transparent)
(define cancel-task-request/c
  (struct/c cancel-task-request (lit/c "tasks/cancel") task-id-params?))
(define (json->cancel-task-request h)
  (cancel-task-request (h-req h 'method) (json->task-id-params (h-req h 'params))))
(define (cancel-task-request->json s)
  (hasheq 'method (cancel-task-request-method s)
          'params (task-id-params->json (cancel-task-request-params s))))

;; CancelTaskResult (1468): Result & Task — same shape as get-task-result.
(struct cancel-task-result (task-id status status-message created-at last-updated-at ttl poll-interval meta rest) #:transparent)
(define cancel-task-result/c
  (struct/c cancel-task-result string? task-status/c (opt/c string?) string? string?
            (or/c 'null real?) (opt/c real?) (opt/c json-object?) json-object?))
(define (json->cancel-task-result h)
  (define-values (id st sm ca lu ttl pi) (read-task-fields h))
  (cancel-task-result id st sm ca lu ttl pi (h-opt h '_meta) (read-task-rest h)))
(define (cancel-task-result->json s)
  (put (emit-task-fields (hash-merge (cancel-task-result-rest s))
                         (cancel-task-result-task-id s) (cancel-task-result-status s)
                         (cancel-task-result-status-message s) (cancel-task-result-created-at s)
                         (cancel-task-result-last-updated-at s) (cancel-task-result-ttl s)
                         (cancel-task-result-poll-interval s) (cancel-task-result-meta s))
       '_meta (cancel-task-result-meta s)))

;; ListTasksRequest (1475).
(struct list-tasks-request (method params) #:transparent)
(define list-tasks-request/c
  (struct/c list-tasks-request (lit/c "tasks/list") (opt/c json-object?)))
(define (json->list-tasks-request h) (list-tasks-request (h-req h 'method) (h-opt h 'params)))
(define (list-tasks-request->json s)
  (put (hasheq 'method (list-tasks-request-method s)) 'params (list-tasks-request-params s)))

;; ListTasksResult (1484).
(struct list-tasks-result (tasks next-cursor meta rest) #:transparent)
(define list-tasks-result/c
  (struct/c list-tasks-result (listof task?) (opt/c cursor/c) (opt/c json-object?) json-object?))
(define (json->list-tasks-result h)
  (list-tasks-result (req-list (h-req h 'tasks) json->task) (h-opt h 'nextCursor) (h-opt h '_meta)
                     (split-loose h '((tasks . tasks) (next-cursor . nextCursor) (meta . _meta)))))
(define (list-tasks-result->json s)
  (put (put (put! (hash-merge (list-tasks-result-rest s))
                  'tasks (map task->json (list-tasks-result-tasks s)))
            'nextCursor (list-tasks-result-next-cursor s))
       '_meta (list-tasks-result-meta s)))

;; TaskStatusNotificationParams (1493): NotificationParams & Task — flattened.
(struct task-status-notification-params (task-id status status-message created-at last-updated-at ttl poll-interval meta rest) #:transparent)
(define task-status-notification-params/c
  (struct/c task-status-notification-params string? task-status/c (opt/c string?) string? string?
            (or/c 'null real?) (opt/c real?) (opt/c json-object?) json-object?))
(define (json->task-status-notification-params h)
  (define-values (id st sm ca lu ttl pi) (read-task-fields h))
  (task-status-notification-params id st sm ca lu ttl pi (h-opt h '_meta) (read-task-rest h)))
(define (task-status-notification-params->json s)
  (put (emit-task-fields (hash-merge (task-status-notification-params-rest s))
                         (task-status-notification-params-task-id s) (task-status-notification-params-status s)
                         (task-status-notification-params-status-message s) (task-status-notification-params-created-at s)
                         (task-status-notification-params-last-updated-at s) (task-status-notification-params-ttl s)
                         (task-status-notification-params-poll-interval s) (task-status-notification-params-meta s))
       '_meta (task-status-notification-params-meta s)))

(struct task-status-notification (method payload) #:transparent)
(define task-status-notification/c
  (struct/c task-status-notification (lit/c "notifications/tasks/status") task-status-notification-params?))
(define (json->task-status-notification h)
  (task-status-notification (h-req h 'method) (json->task-status-notification-params (h-req h 'params))))
(define (task-status-notification->json s)
  (hasheq 'method (task-status-notification-method s)
          'params (task-status-notification-params->json (task-status-notification-payload s))))

;; ============================================================================
;; K. Logging
;; ============================================================================
(struct set-level-request-params (level meta) #:transparent)
(define set-level-request-params/c
  (struct/c set-level-request-params logging-level/c (opt/c json-object?)))
(define (json->set-level-request-params h)
  (set-level-request-params (h-req h 'level) (h-opt h '_meta)))
(define (set-level-request-params->json s)
  (put (put! (hasheq) 'level (set-level-request-params-level s)) '_meta (set-level-request-params-meta s)))
(struct set-level-request (method payload) #:transparent)
(define set-level-request/c
  (struct/c set-level-request (lit/c "logging/setLevel") set-level-request-params?))
(define (json->set-level-request h)
  (set-level-request (h-req h 'method) (json->set-level-request-params (h-req h 'params))))
(define (set-level-request->json s)
  (hasheq 'method (set-level-request-method s)
          'params (set-level-request-params->json (set-level-request-payload s))))

;; LoggingMessageNotificationParams (1534): level, logger?, data (REQUIRED any), meta?.
(struct logging-message-notification-params (level logger data meta) #:transparent)
(define logging-message-notification-params/c
  (struct/c logging-message-notification-params logging-level/c (opt/c string?) jsexpr-value? (opt/c json-object?)))
(define (json->logging-message-notification-params h)
  (define data (h-req h 'data))
  (when (absent? data) (error 'json->logging-message-notification-params "required field data missing"))
  (logging-message-notification-params (h-req h 'level) (h-opt h 'logger) data (h-opt h '_meta)))
(define (logging-message-notification-params->json s)
  (put (put (put! (put! (hasheq) 'level (logging-message-notification-params-level s))
                  'data (logging-message-notification-params-data s))
            'logger (logging-message-notification-params-logger s))
       '_meta (logging-message-notification-params-meta s)))
(struct logging-message-notification (method payload) #:transparent)
(define logging-message-notification/c
  (struct/c logging-message-notification (lit/c "notifications/message") logging-message-notification-params?))
(define (json->logging-message-notification h)
  (logging-message-notification (h-req h 'method) (json->logging-message-notification-params (h-req h 'params))))
(define (logging-message-notification->json s)
  (hasheq 'method (logging-message-notification-method s)
          'params (logging-message-notification-params->json (logging-message-notification-payload s))))

;; ============================================================================
;; L. Sampling
;; ============================================================================
(struct model-hint (name) #:transparent)
(define model-hint/c (struct/c model-hint (opt/c string?)))
(define (json->model-hint h) (model-hint (h-opt h 'name)))
(define (model-hint->json s) (put (hasheq) 'name (model-hint-name s)))

(struct model-preferences (hints cost-priority speed-priority intelligence-priority) #:transparent)
(define model-preferences/c
  (struct/c model-preferences (opt/c (listof model-hint?)) (opt/c real?) (opt/c real?) (opt/c real?)))
(define (json->model-preferences h)
  (model-preferences (opt-list (h-opt h 'hints) json->model-hint)
                     (h-opt h 'costPriority) (h-opt h 'speedPriority) (h-opt h 'intelligencePriority)))
(define (model-preferences->json s)
  (put (put (put (put (hasheq) 'hints (opt-map (model-preferences-hints s) (lambda (xs) (map model-hint->json xs))))
                 'costPriority (model-preferences-cost-priority s))
            'speedPriority (model-preferences-speed-priority s))
       'intelligencePriority (model-preferences-intelligence-priority s)))

(struct tool-choice (mode) #:transparent)
(define tool-choice/c (struct/c tool-choice (opt/c (or/c "auto" "required" "none"))))
(define (json->tool-choice h) (tool-choice (h-opt h 'mode)))
(define (tool-choice->json s) (put (hasheq) 'mode (tool-choice-mode s)))

;; SamplingMessage (1678): role, content (block OR list of), meta?.
(struct sampling-message (role content meta) #:transparent)
(define sampling-message-content/c
  (or/c sampling-message-content-block/c (listof sampling-message-content-block/c)))
(define sampling-message/c
  (struct/c sampling-message role/c sampling-message-content/c (opt/c json-object?)))
(define (json->sampling-message h)
  (define c (h-req h 'content))
  (sampling-message (h-req h 'role)
                    (if (list? c)
                        (map json->sampling-message-content-block c)
                        (json->sampling-message-content-block c))
                    (h-opt h '_meta)))
(define (sampling-message->json s)
  (define c (sampling-message-content s))
  (let ([base (put! (hasheq) 'role (sampling-message-role s))])
    (put (hash-set base 'content (if (list? c)
                                     (map sampling-message-content-block->json c)
                                     (sampling-message-content-block->json c)))
         '_meta (sampling-message-meta s))))

;; CreateMessageRequestParams (1575): PARAMS.
(struct create-message-request-params
  (messages model-preferences system-prompt include-context temperature max-tokens
            stop-sequences metadata tools tool-choice task meta) #:transparent)
(define create-message-request-params/c
  (struct/c create-message-request-params
            (listof sampling-message?) (opt/c model-preferences?) (opt/c string?)
            (opt/c (or/c "none" "thisServer" "allServers")) (opt/c real?) real?
            (opt/c (listof string?)) (opt/c json-object?) (opt/c (listof tool?))
            (opt/c tool-choice?) (opt/c task-metadata?) (opt/c json-object?)))
(define (json->create-message-request-params h)
  (define mt (h-req h 'maxTokens))
  (when (absent? mt) (error 'json->create-message-request-params "required field maxTokens missing"))
  (create-message-request-params
   (req-list (h-req h 'messages) json->sampling-message)
   (opt-map (h-opt h 'modelPreferences) json->model-preferences)
   (h-opt h 'systemPrompt) (h-opt h 'includeContext) (h-opt h 'temperature) mt
   (h-opt h 'stopSequences) (h-opt h 'metadata)
   (opt-list (h-opt h 'tools) json->tool)
   (opt-map (h-opt h 'toolChoice) json->tool-choice)
   (opt-map (h-opt h 'task) json->task-metadata) (h-opt h '_meta)))
(define (create-message-request-params->json s)
  (let* ([h (put! (hasheq) 'messages (map sampling-message->json (create-message-request-params-messages s)))]
         [h (put! h 'maxTokens (create-message-request-params-max-tokens s))]
         [h (put h 'modelPreferences (opt-map (create-message-request-params-model-preferences s) model-preferences->json))]
         [h (put h 'systemPrompt (create-message-request-params-system-prompt s))]
         [h (put h 'includeContext (create-message-request-params-include-context s))]
         [h (put h 'temperature (create-message-request-params-temperature s))]
         [h (put h 'stopSequences (create-message-request-params-stop-sequences s))]
         [h (put h 'metadata (create-message-request-params-metadata s))]
         [h (put h 'tools (opt-map (create-message-request-params-tools s) (lambda (xs) (map tool->json xs))))]
         [h (put h 'toolChoice (opt-map (create-message-request-params-tool-choice s) tool-choice->json))]
         [h (put h 'task (opt-map (create-message-request-params-task s) task-metadata->json))]
         [h (put h '_meta (create-message-request-params-meta s))])
    h))
(struct create-message-request (method payload) #:transparent)
(define create-message-request/c
  (struct/c create-message-request (lit/c "sampling/createMessage") create-message-request-params?))
(define (json->create-message-request h)
  (create-message-request (h-req h 'method) (json->create-message-request-params (h-req h 'params))))
(define (create-message-request->json s)
  (hasheq 'method (create-message-request-method s)
          'params (create-message-request-params->json (create-message-request-payload s))))

;; CreateMessageResult (1653): Result & SamplingMessage + model, stopReason?, loose.
;; Flatten SamplingMessage (role, content) at top level.
(struct create-message-result (role content model stop-reason meta rest) #:transparent)
(define create-message-result/c
  (struct/c create-message-result role/c sampling-message-content/c string? (opt/c string?)
            (opt/c json-object?) json-object?))
(define create-message-result-known-table
  '((role . role) (content . content) (model . model) (stop-reason . stopReason) (meta . _meta)))
(define (json->create-message-result h)
  (define c (h-req h 'content))
  (create-message-result (h-req h 'role)
                         (if (list? c) (map json->sampling-message-content-block c)
                             (json->sampling-message-content-block c))
                         (h-req h 'model) (h-opt h 'stopReason) (h-opt h '_meta)
                         (split-loose h create-message-result-known-table)))
(define (create-message-result->json s)
  (define c (create-message-result-content s))
  (let* ([h (hash-merge (create-message-result-rest s))]
         [h (put! h 'role (create-message-result-role s))]
         [h (hash-set h 'content (if (list? c) (map sampling-message-content-block->json c)
                                     (sampling-message-content-block->json c)))]
         [h (put! h 'model (create-message-result-model s))]
         [h (put h 'stopReason (create-message-result-stop-reason s))]
         [h (put h '_meta (create-message-result-meta s))])
    h))

;; ============================================================================
;; N. Autocomplete / completion
;; ============================================================================
(struct resource-template-reference (uri) #:transparent)
(define resource-template-reference/c (struct/c resource-template-reference string?))
(define (json->resource-template-reference h) (resource-template-reference (h-req h 'uri)))
(define (resource-template-reference->json s)
  (hasheq 'type "ref/resource" 'uri (resource-template-reference-uri s)))

(struct prompt-reference (name title) #:transparent)
(define prompt-reference/c (struct/c prompt-reference string? (opt/c string?)))
(define (json->prompt-reference h) (prompt-reference (h-req h 'name) (h-opt h 'title)))
(define (prompt-reference->json s)
  (put (hasheq 'type "ref/prompt" 'name (prompt-reference-name s))
       'title (prompt-reference-title s)))

(define complete-ref/c (or/c prompt-reference? resource-template-reference?))
(define (json->complete-ref h)
  (case (h-req h 'type)
    [("ref/prompt") (json->prompt-reference h)]
    [("ref/resource") (json->resource-template-reference h)]
    [else (error 'json->complete-ref "unknown ref type: ~a" (h-req h 'type))]))
(define (complete-ref->json s)
  (if (prompt-reference? s) (prompt-reference->json s) (resource-template-reference->json s)))

;; CompleteRequestParams (1991): PARAMS. ref, argument {name value}, context? {arguments?}, meta?.
(struct complete-request-params (ref argument context meta) #:transparent)
(define complete-request-params/c
  (struct/c complete-request-params complete-ref/c json-object? (opt/c json-object?) (opt/c json-object?)))
(define (json->complete-request-params h)
  (complete-request-params (json->complete-ref (h-req h 'ref)) (h-req h 'argument)
                           (h-opt h 'context) (h-opt h '_meta)))
(define (complete-request-params->json s)
  (put (put (put! (put! (hasheq) 'ref (complete-ref->json (complete-request-params-ref s)))
                  'argument (complete-request-params-argument s))
            'context (complete-request-params-context s))
       '_meta (complete-request-params-meta s)))
(struct complete-request (method payload) #:transparent)
(define complete-request/c
  (struct/c complete-request (lit/c "completion/complete") complete-request-params?))
(define (json->complete-request h)
  (complete-request (h-req h 'method) (json->complete-request-params (h-req h 'params))))
(define (complete-request->json s)
  (hasheq 'method (complete-request-method s)
          'params (complete-request-params->json (complete-request-payload s))))

;; CompleteResult (2033): completion {values, total?, hasMore?}, meta?, loose.
(struct complete-result (completion meta rest) #:transparent)
(define complete-result/c
  (struct/c complete-result json-object? (opt/c json-object?) json-object?))
(define (json->complete-result h)
  (complete-result (h-req h 'completion) (h-opt h '_meta)
                   (split-loose h '((completion . completion) (meta . _meta)))))
(define (complete-result->json s)
  (put (put! (hash-merge (complete-result-rest s)) 'completion (complete-result-completion s))
       '_meta (complete-result-meta s)))

;; ============================================================================
;; O. Roots
;; ============================================================================
(struct list-roots-request (method params) #:transparent)
(define list-roots-request/c (struct/c list-roots-request (lit/c "roots/list") (opt/c json-object?)))
(define (json->list-roots-request h) (list-roots-request (h-req h 'method) (h-opt h 'params)))
(define (list-roots-request->json s)
  (put (hasheq 'method (list-roots-request-method s)) 'params (list-roots-request-params s)))

(struct root (uri name meta) #:transparent)
(define root/c (struct/c root string? (opt/c string?) (opt/c json-object?)))
(define (json->root h) (root (h-req h 'uri) (h-opt h 'name) (h-opt h '_meta)))
(define (root->json s)
  (put (put (put! (hasheq) 'uri (root-uri s)) 'name (root-name s)) '_meta (root-meta s)))

(struct list-roots-result (roots meta rest) #:transparent)
(define list-roots-result/c
  (struct/c list-roots-result (listof root?) (opt/c json-object?) json-object?))
(define (json->list-roots-result h)
  (list-roots-result (req-list (h-req h 'roots) json->root) (h-opt h '_meta)
                     (split-loose h '((roots . roots) (meta . _meta)))))
(define (list-roots-result->json s)
  (put (put! (hash-merge (list-roots-result-rest s)) 'roots (map root->json (list-roots-result-roots s)))
       '_meta (list-roots-result-meta s)))

(struct roots-list-changed-notification (method params) #:transparent)
(define roots-list-changed-notification/c
  (struct/c roots-list-changed-notification (lit/c "notifications/roots/list_changed") (opt/c json-object?)))
(define (json->roots-list-changed-notification h)
  (roots-list-changed-notification (h-req h 'method) (h-opt h 'params)))
(define (roots-list-changed-notification->json s)
  (put (hasheq 'method (roots-list-changed-notification-method s))
       'params (roots-list-changed-notification-params s)))

;; ============================================================================
;; P. Elicitation + primitive/enum schemas
;; ============================================================================

;; StringSchema (2229).
(struct string-schema (title description min-length max-length format default) #:transparent)
(define string-schema/c
  (struct/c string-schema (opt/c string?) (opt/c string?) (opt/c real?) (opt/c real?)
            (opt/c (or/c "email" "uri" "date" "date-time")) (opt/c string?)))
(define (json->string-schema h)
  (string-schema (h-opt h 'title) (h-opt h 'description) (h-opt h 'minLength)
                 (h-opt h 'maxLength) (h-opt h 'format) (h-opt h 'default)))
(define (string-schema->json s)
  (let* ([h (put! (hasheq) 'type "string")]
         [h (put h 'title (string-schema-title s))]
         [h (put h 'description (string-schema-description s))]
         [h (put h 'minLength (string-schema-min-length s))]
         [h (put h 'maxLength (string-schema-max-length s))]
         [h (put h 'format (string-schema-format s))]
         [h (put h 'default (string-schema-default s))])
    h))

;; NumberSchema (2242): type "number"|"integer".
(struct number-schema (type title description minimum maximum default) #:transparent)
(define number-schema/c
  (struct/c number-schema (or/c "number" "integer") (opt/c string?) (opt/c string?)
            (opt/c real?) (opt/c real?) (opt/c real?)))
(define (json->number-schema h)
  (number-schema (h-req h 'type) (h-opt h 'title) (h-opt h 'description)
                 (h-opt h 'minimum) (h-opt h 'maximum) (h-opt h 'default)))
(define (number-schema->json s)
  (let* ([h (put! (hasheq) 'type (number-schema-type s))]
         [h (put h 'title (number-schema-title s))]
         [h (put h 'description (number-schema-description s))]
         [h (put h 'minimum (number-schema-minimum s))]
         [h (put h 'maximum (number-schema-maximum s))]
         [h (put h 'default (number-schema-default s))])
    h))

;; BooleanSchema (2254).
(struct boolean-schema (title description default) #:transparent)
(define boolean-schema/c
  (struct/c boolean-schema (opt/c string?) (opt/c string?) (opt/c boolean?)))
(define (json->boolean-schema h)
  (boolean-schema (h-opt h 'title) (h-opt h 'description) (h-opt h 'default)))
(define (boolean-schema->json s)
  (let* ([h (put! (hasheq) 'type "boolean")]
         [h (put h 'title (boolean-schema-title s))]
         [h (put h 'description (boolean-schema-description s))]
         [h (put h 'default (boolean-schema-default s))])
    h))

;; EnumSchema family (2266–2441). Discriminate by shape: type "array" =>
;; multi-select; type "string" with oneOf => titled-single; with enumNames =>
;; legacy; with enum (no enumNames) => untitled-single.
(struct untitled-single-select-enum-schema (title description enum default) #:transparent)
(define untitled-single-select-enum-schema/c
  (struct/c untitled-single-select-enum-schema (opt/c string?) (opt/c string?) (listof string?) (opt/c string?)))
(define (json->untitled-single-select-enum-schema h)
  (untitled-single-select-enum-schema (h-opt h 'title) (h-opt h 'description) (h-req h 'enum) (h-opt h 'default)))
(define (untitled-single-select-enum-schema->json s)
  (let* ([h (put! (put! (hasheq) 'type "string") 'enum (untitled-single-select-enum-schema-enum s))]
         [h (put h 'title (untitled-single-select-enum-schema-title s))]
         [h (put h 'description (untitled-single-select-enum-schema-description s))]
         [h (put h 'default (untitled-single-select-enum-schema-default s))])
    h))

(struct titled-single-select-enum-schema (title description one-of default) #:transparent)
(define titled-single-select-enum-schema/c
  (struct/c titled-single-select-enum-schema (opt/c string?) (opt/c string?) (listof json-object?) (opt/c string?)))
(define (json->titled-single-select-enum-schema h)
  (titled-single-select-enum-schema (h-opt h 'title) (h-opt h 'description) (h-req h 'oneOf) (h-opt h 'default)))
(define (titled-single-select-enum-schema->json s)
  (let* ([h (put! (put! (hasheq) 'type "string") 'oneOf (titled-single-select-enum-schema-one-of s))]
         [h (put h 'title (titled-single-select-enum-schema-title s))]
         [h (put h 'description (titled-single-select-enum-schema-description s))]
         [h (put h 'default (titled-single-select-enum-schema-default s))])
    h))

(struct untitled-multi-select-enum-schema (title description min-items max-items items default) #:transparent)
(define untitled-multi-select-enum-schema/c
  (struct/c untitled-multi-select-enum-schema (opt/c string?) (opt/c string?) (opt/c real?) (opt/c real?)
            json-object? (opt/c (listof string?))))
(define (json->untitled-multi-select-enum-schema h)
  (untitled-multi-select-enum-schema (h-opt h 'title) (h-opt h 'description) (h-opt h 'minItems)
                                     (h-opt h 'maxItems) (h-req h 'items) (h-opt h 'default)))
(define (untitled-multi-select-enum-schema->json s)
  (let* ([h (put! (put! (hasheq) 'type "array") 'items (untitled-multi-select-enum-schema-items s))]
         [h (put h 'title (untitled-multi-select-enum-schema-title s))]
         [h (put h 'description (untitled-multi-select-enum-schema-description s))]
         [h (put h 'minItems (untitled-multi-select-enum-schema-min-items s))]
         [h (put h 'maxItems (untitled-multi-select-enum-schema-max-items s))]
         [h (put h 'default (untitled-multi-select-enum-schema-default s))])
    h))

(struct titled-multi-select-enum-schema (title description min-items max-items items default) #:transparent)
(define titled-multi-select-enum-schema/c
  (struct/c titled-multi-select-enum-schema (opt/c string?) (opt/c string?) (opt/c real?) (opt/c real?)
            json-object? (opt/c (listof string?))))
(define (json->titled-multi-select-enum-schema h)
  (titled-multi-select-enum-schema (h-opt h 'title) (h-opt h 'description) (h-opt h 'minItems)
                                   (h-opt h 'maxItems) (h-req h 'items) (h-opt h 'default)))
(define (titled-multi-select-enum-schema->json s)
  (let* ([h (put! (put! (hasheq) 'type "array") 'items (titled-multi-select-enum-schema-items s))]
         [h (put h 'title (titled-multi-select-enum-schema-title s))]
         [h (put h 'description (titled-multi-select-enum-schema-description s))]
         [h (put h 'minItems (titled-multi-select-enum-schema-min-items s))]
         [h (put h 'maxItems (titled-multi-select-enum-schema-max-items s))]
         [h (put h 'default (titled-multi-select-enum-schema-default s))])
    h))

(struct legacy-titled-enum-schema (title description enum enum-names default) #:transparent)
(define legacy-titled-enum-schema/c
  (struct/c legacy-titled-enum-schema (opt/c string?) (opt/c string?) (listof string?) (opt/c (listof string?)) (opt/c string?)))
(define (json->legacy-titled-enum-schema h)
  (legacy-titled-enum-schema (h-opt h 'title) (h-opt h 'description) (h-req h 'enum)
                             (h-opt h 'enumNames) (h-opt h 'default)))
(define (legacy-titled-enum-schema->json s)
  (let* ([h (put! (put! (hasheq) 'type "string") 'enum (legacy-titled-enum-schema-enum s))]
         [h (put h 'enumNames (legacy-titled-enum-schema-enum-names s))]
         [h (put h 'title (legacy-titled-enum-schema-title s))]
         [h (put h 'description (legacy-titled-enum-schema-description s))]
         [h (put h 'default (legacy-titled-enum-schema-default s))])
    h))

(define enum-schema/c
  (or/c untitled-single-select-enum-schema? titled-single-select-enum-schema?
        untitled-multi-select-enum-schema? titled-multi-select-enum-schema?
        legacy-titled-enum-schema?))
(define (json->enum-schema h)
  (cond
    [(equal? (h-req h 'type) "array")
     (if (hash-has-key? (hash-ref h 'items (hasheq)) 'anyOf)
         (json->titled-multi-select-enum-schema h)
         (json->untitled-multi-select-enum-schema h))]
    [(hash-has-key? h 'oneOf) (json->titled-single-select-enum-schema h)]
    [(hash-has-key? h 'enumNames) (json->legacy-titled-enum-schema h)]
    [(hash-has-key? h 'enum) (json->untitled-single-select-enum-schema h)]
    [else (error 'json->enum-schema "cannot discriminate enum schema: ~a" h)]))
(define (enum-schema->json s)
  (cond [(untitled-single-select-enum-schema? s) (untitled-single-select-enum-schema->json s)]
        [(titled-single-select-enum-schema? s) (titled-single-select-enum-schema->json s)]
        [(untitled-multi-select-enum-schema? s) (untitled-multi-select-enum-schema->json s)]
        [(titled-multi-select-enum-schema? s) (titled-multi-select-enum-schema->json s)]
        [(legacy-titled-enum-schema? s) (legacy-titled-enum-schema->json s)]
        [else (error 'enum-schema->json "not an enum schema: ~a" s)]))

;; PrimitiveSchemaDefinition (2224): string|number|boolean|enum.
(define primitive-schema-definition/c
  (or/c string-schema? number-schema? boolean-schema? enum-schema/c))
(define (json->primitive-schema-definition h)
  (case (h-req h 'type)
    [("boolean") (json->boolean-schema h)]
    [("number" "integer") (json->number-schema h)]
    [("array") (json->enum-schema h)]
    [("string")
     (if (or (hash-has-key? h 'enum) (hash-has-key? h 'oneOf) (hash-has-key? h 'enumNames))
         (json->enum-schema h)
         (json->string-schema h))]
    [else (error 'json->primitive-schema-definition "unknown type: ~a" (h-req h 'type))]))
(define (primitive-schema-definition->json s)
  (cond [(string-schema? s) (string-schema->json s)]
        [(number-schema? s) (number-schema->json s)]
        [(boolean-schema? s) (boolean-schema->json s)]
        [else (enum-schema->json s)]))

;; ElicitRequestFormParams (2146): mode?="form", message, requestedSchema (loose), task?, meta?.
(struct elicit-request-form-params (mode message requested-schema task meta) #:transparent)
(define elicit-request-form-params/c
  (struct/c elicit-request-form-params (opt/c (lit/c "form")) string? json-object?
            (opt/c task-metadata?) (opt/c json-object?)))
(define (json->elicit-request-form-params h)
  (elicit-request-form-params (h-opt h 'mode) (h-req h 'message) (h-req h 'requestedSchema)
                              (opt-map (h-opt h 'task) json->task-metadata) (h-opt h '_meta)))
(define (elicit-request-form-params->json s)
  (let* ([h (put! (put! (hasheq) 'message (elicit-request-form-params-message s))
                  'requestedSchema (elicit-request-form-params-requested-schema s))]
         [h (put h 'mode (elicit-request-form-params-mode s))]
         [h (put h 'task (opt-map (elicit-request-form-params-task s) task-metadata->json))]
         [h (put h '_meta (elicit-request-form-params-meta s))])
    h))

;; ElicitRequestURLParams (2176): mode="url" REQUIRED, message, elicitationId, url, task?, meta?.
(struct elicit-request-url-params (mode message elicitation-id url task meta) #:transparent)
(define elicit-request-url-params/c
  (struct/c elicit-request-url-params (lit/c "url") string? string? string?
            (opt/c task-metadata?) (opt/c json-object?)))
(define (json->elicit-request-url-params h)
  (elicit-request-url-params (h-req h 'mode) (h-req h 'message) (h-req h 'elicitationId) (h-req h 'url)
                             (opt-map (h-opt h 'task) json->task-metadata) (h-opt h '_meta)))
(define (elicit-request-url-params->json s)
  (let* ([h (put! (put! (put! (put! (hasheq) 'mode (elicit-request-url-params-mode s))
                              'message (elicit-request-url-params-message s))
                        'elicitationId (elicit-request-url-params-elicitation-id s))
                  'url (elicit-request-url-params-url s))]
         [h (put h 'task (opt-map (elicit-request-url-params-task s) task-metadata->json))]
         [h (put h '_meta (elicit-request-url-params-meta s))])
    h))

;; ElicitRequestParams (2206): discriminate on mode.
(define elicit-request-params/c
  (or/c elicit-request-form-params? elicit-request-url-params?))
(define (json->elicit-request-params h)
  (if (equal? (h-opt h 'mode) "url")
      (json->elicit-request-url-params h)
      (json->elicit-request-form-params h)))
(define (elicit-request-params->json s)
  (if (elicit-request-url-params? s)
      (elicit-request-url-params->json s)
      (elicit-request-form-params->json s)))

(struct elicit-request (method params) #:transparent)
(define elicit-request/c
  (struct/c elicit-request (lit/c "elicitation/create") elicit-request-params/c))
(define (json->elicit-request h)
  (elicit-request (h-req h 'method) (json->elicit-request-params (h-req h 'params))))
(define (elicit-request->json s)
  (hasheq 'method (elicit-request-method s)
          'params (elicit-request-params->json (elicit-request-params s))))

;; ElicitResult (2448): action, content?, meta?, loose.
(struct elicit-result (action content meta rest) #:transparent)
(define elicit-result/c
  (struct/c elicit-result (or/c "accept" "decline" "cancel") (opt/c json-object?) (opt/c json-object?) json-object?))
(define (json->elicit-result h)
  (elicit-result (h-req h 'action) (h-opt h 'content) (h-opt h '_meta)
                 (split-loose h '((action . action) (content . content) (meta . _meta)))))
(define (elicit-result->json s)
  (put (put (put! (hash-merge (elicit-result-rest s)) 'action (elicit-result-action s))
            'content (elicit-result-content s))
       '_meta (elicit-result-meta s)))

;; ElicitationCompleteNotification (2470): params {elicitationId}.
(struct elicitation-complete-notification (method params) #:transparent)
(define elicitation-complete-notification/c
  (struct/c elicitation-complete-notification (lit/c "notifications/elicitation/complete") json-object?))
(define (json->elicitation-complete-notification h)
  (elicitation-complete-notification (h-req h 'method) (h-req h 'params)))
(define (elicitation-complete-notification->json s)
  (hasheq 'method (elicitation-complete-notification-method s)
          'params (elicitation-complete-notification-params s)))

;; ============================================================================
;; Q. Specialized error + aggregate union contracts
;; ============================================================================

;; URLElicitationRequiredError (196): a jsonrpc-error-response whose error.code
;; = URL-ELICITATION-REQUIRED (-32042) and error.data.elicitations is a list of
;; elicit-request-url-params.
(define (make-url-elicitation-required-error id elicitations [message "URL elicitation required"])
  (jsonrpc-error-response
   id
   (jsonrpc-error URL-ELICITATION-REQUIRED message
                  (hasheq 'elicitations (map elicit-request-url-params->json elicitations)))))
(define (url-elicitation-required-error? v)
  (and (jsonrpc-error-response? v)
       (jsonrpc-error? (jsonrpc-error-response-error v))
       (= (jsonrpc-error-code (jsonrpc-error-response-error v)) URL-ELICITATION-REQUIRED)))

;; Aggregate union contracts (R). Members per source |-unions (2482–2559).
(define client-request/c
  (or/c ping-request? initialize-request? complete-request? set-level-request?
        get-prompt-request? list-prompts-request? list-resources-request?
        list-resource-templates-request? read-resource-request? subscribe-request?
        unsubscribe-request? call-tool-request? list-tools-request?
        get-task-request? get-task-payload-request? list-tasks-request? cancel-task-request?))
(define client-notification/c
  (or/c cancelled-notification? progress-notification? initialized-notification?
        roots-list-changed-notification? task-status-notification?))
(define client-result/c
  (or/c result? create-message-result? list-roots-result? elicit-result?
        create-task-result? get-task-result? get-task-payload-result? cancel-task-result?))
(define server-request/c
  (or/c ping-request? create-message-request? list-roots-request? elicit-request?
        get-task-request? get-task-payload-request? list-tasks-request? cancel-task-request?))
(define server-notification/c
  (or/c cancelled-notification? progress-notification? logging-message-notification?
        resource-updated-notification? resource-list-changed-notification?
        tool-list-changed-notification? prompt-list-changed-notification?
        elicitation-complete-notification? task-status-notification?))
(define server-result/c
  (or/c result? initialize-result? complete-result? get-prompt-result? list-prompts-result?
        list-resources-result? list-resource-templates-result? read-resource-result?
        call-tool-result? list-tools-result? create-task-result? get-task-result?
        get-task-payload-result? list-tasks-result? cancel-task-result?))
(define jsonrpc-message/c
  (or/c jsonrpc-request? jsonrpc-notification? jsonrpc-result-response? jsonrpc-error-response?))
