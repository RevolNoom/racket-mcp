#lang racket/base

;; ============================================================================
;; spec-2026-07-28.rkt — pure-data Racket mirror of the MCP `2026-07-28`
;; Release-Candidate revision
;; (typescript-sdk/packages/core/src/types/spec.types.2026-07-28.ts +
;; schemas.ts + constants.ts). Item 004 of queue-001 (Stage S1, module M1).
;;
;; SIBLING of item 003 (spec-2025-11-25.rkt). Same conventions:
;;   - transparent `struct` + flat `name/c` + `json->name`/`name->json` triad,
;;   - JSON object = immutable symbol-keyed hasheq (json-object?),
;;   - JSON null = 'null; absent optional = the `absent` sentinel (IMPORTED and
;;     re-exported from 003 so item 005's N1 façade unions both against ONE
;;     eq? sentinel),
;;   - the THREE strictness behaviors (envelopes strict / results loose-via-rest
;;     / concrete params DROP unknown non-_meta keys).
;;
;; THE RC FEATURE — the per-request `_meta` envelope (RequestMetaObject,
;; spec.types:70): every concrete request params struct carries a REQUIRED
;; `request-meta` envelope in its `meta` field. `request-meta` splits the five
;; reserved `io.modelcontextprotocol/...` keys into NAMED fields and keeps any
;; unreserved `_meta` keys in `rest`; the serializer re-emits the reserved keys
;; at their EXACT prefixed strings (sourced from constants.rkt). `_meta` is
;; REQUIRED on request params (absent _meta -> reject). `resultType` is modeled
;; OPTIONAL (the TS .d.ts marks it required, but its own JSDoc sanctions an
;; absent value -> "complete" for older servers — INTENTIONAL ASYMMETRY).
;;
;; REMOVED vs 2025-11-25 (do not look for these here): the `initialize` family
;; (initialize/initialized — replaced by the _meta envelope + server/discover),
;; `ping`, `logging/setLevel` (replaced by the _meta logLevel key), ALL of
;; `tasks/*` (+ Task/TaskMetadata/ToolExecution/task fields), `resources/
;; subscribe`+`unsubscribe` (replaced by `subscriptions/listen` +
;; SubscriptionFilter.resourceSubscriptions), `URLElicitationRequiredError`
;; (-32042), and the `ServerRequest` union (server->client requests live in
;; `input-request/c`).
;;
;; ADDED vs 2025-11-25: `server/discover`, `subscriptions/listen` +
;; SubscriptionFilter + acknowledged notification, typed JSON-RPC error structs
;; (5 code-pinned predicates + 2 data-carrying error responses), the
;; multi-round-trip Input family (InputRequest/Response unions + maps +
;; InputRequiredResult), `CacheableResult` (ttlMs/cacheScope), and the
;; `resultType` discriminator on every Result.
;;
;; Requires only racket/base + racket/contract + constants.rkt + the `absent`
;; sentinel from spec-2025-11-25.rkt (Portability NFR — no json I/O at load).
;; ============================================================================

(require racket/contract
         (only-in "constants.rkt"
                  JSONRPC-VERSION
                  UNSUPPORTED-PROTOCOL-VERSION
                  MISSING-REQUIRED-CLIENT-CAPABILITY
                  PARSE-ERROR INVALID-REQUEST METHOD-NOT-FOUND
                  INVALID-PARAMS INTERNAL-ERROR
                  PROTOCOL-VERSION-META-KEY CLIENT-INFO-META-KEY
                  CLIENT-CAPABILITIES-META-KEY LOG-LEVEL-META-KEY
                  RELATED-TASK-META-KEY)
         ;; Reuse 003's `absent` sentinel — SAME binding so 005 unions 003+004
         ;; against one eq? sentinel. (003 provides absent/absent?/present?.)
         (only-in "spec-2025-11-25.rkt" absent absent? present?))

;; ----------------------------------------------------------------------------
;; Internal wire helpers (NOT provided, except the re-exported `absent`).
;; Duplicated from 003 (Decisions → shared-helpers: only `absent` is shared).
;; ----------------------------------------------------------------------------

(define (json-object? v)
  (and (hash? v) (immutable? v) (hash-eq? v)))

(define (json-null? v) (eq? v 'null))
(define (request-id? x) (or (string? x) (exact-integer? x)))
(define (progress-token? x) (or (string? x) (exact-integer? x)))

(define (jsexpr-value? v)
  (or (json-null? v) (boolean? v) (string? v) (number? v)
      (and (list? v) (andmap jsexpr-value? v))
      (and (json-object? v) (for/and ([(_k val) (in-hash v)]) (jsexpr-value? val)))))

(define (h-opt h key) (hash-ref h key absent))
(define (h-req h key) (hash-ref h key absent))

;; Emit (key . value) only if present; a present 'null IS emitted as JSON null.
(define (put h key val [conv values])
  (if (present? val) (hash-set h key (conv val)) h))
(define (put! h key val [conv values]) (hash-set h key (conv val)))

(define (opt-map val conv) (if (present? val) (conv val) absent))
(define (opt-list val conv) (opt-map val (lambda (xs) (map conv xs))))
(define (req-list val conv) (map conv val))

;; Sweep all keys NOT in `known-json-keys` into a fresh rest hasheq (LOOSE).
(define (split-loose h table)
  (define known-json-keys (map cdr table))
  (for/fold ([acc (hasheq)]) ([(k v) (in-hash h)])
    (if (memq k known-json-keys) acc (hash-set acc k v))))

(define (hash-merge rest [base (hasheq)])
  (for/fold ([acc base]) ([(k v) (in-hash rest)]) (hash-set acc k v)))

;; optional-of: a contract that also accepts the absent sentinel.
(define (opt/c c) (or/c absent? c))

;; string-literal contract (method/type/mode discriminators).
(define (lit/c str)
  (flat-named-contract (string->symbol (format "=~s" str))
                       (lambda (x) (equal? x str))))

;; ----------------------------------------------------------------------------
;; PROVIDES (curated; NO all-defined-out).
;; ----------------------------------------------------------------------------
(provide
 ;; sentinel + helpers item 005 needs (re-exported from 003)
 absent absent? present?
 ;; scalar/enum contracts
 role/c cursor/c progress-token/c request-id/c logging-level/c
 result-type/c cache-scope/c
 ;; ---- envelopes ----
 (struct-out jsonrpc-request) jsonrpc-request/c json->jsonrpc-request jsonrpc-request->json
 (struct-out jsonrpc-notification) jsonrpc-notification/c json->jsonrpc-notification jsonrpc-notification->json
 (struct-out jsonrpc-result-response) jsonrpc-result-response/c json->jsonrpc-result-response jsonrpc-result-response->json
 (struct-out jsonrpc-error-response) jsonrpc-error-response/c json->jsonrpc-error-response jsonrpc-error-response->json
 (struct-out jsonrpc-error) jsonrpc-error/c json->jsonrpc-error jsonrpc-error->json
 ;; ---- common ----
 meta-object/c
 (struct-out result) result/c json->result result->json
 (struct-out base-metadata) base-metadata/c
 (struct-out implementation) implementation/c json->implementation implementation->json
 (struct-out icon) icon/c json->icon icon->json
 (struct-out annotations) annotations/c json->annotations annotations->json
 ;; ---- the RC _meta request envelope ----
 (struct-out related-task-metadata) related-task-metadata/c json->related-task-metadata related-task-metadata->json
 (struct-out request-meta) request-meta/c json->request-meta request-meta->json
 ;; ---- capabilities ----
 (struct-out client-capabilities) client-capabilities/c json->client-capabilities client-capabilities->json
 (struct-out server-capabilities) server-capabilities/c json->server-capabilities server-capabilities->json
 ;; ---- discovery ----
 (struct-out discover-request) discover-request/c json->discover-request discover-request->json
 (struct-out discover-result) discover-result/c json->discover-result discover-result->json
 ;; ---- input / multi-round-trip family ----
 input-request/c input-response/c input-requests/c input-responses/c
 json->input-requests input-requests->json json->input-responses input-responses->json
 (struct-out input-required-result) input-required-result/c json->input-required-result input-required-result->json
 ;; ---- progress / cancellation ----
 (struct-out cancelled-notification-params) cancelled-notification-params/c json->cancelled-notification-params cancelled-notification-params->json
 (struct-out cancelled-notification) cancelled-notification/c json->cancelled-notification cancelled-notification->json
 (struct-out progress-notification-params) progress-notification-params/c json->progress-notification-params progress-notification-params->json
 (struct-out progress-notification) progress-notification/c json->progress-notification progress-notification->json
 ;; ---- resources ----
 (struct-out list-resources-request) list-resources-request/c json->list-resources-request list-resources-request->json
 (struct-out list-resources-result) list-resources-result/c json->list-resources-result list-resources-result->json
 (struct-out list-resource-templates-request) list-resource-templates-request/c json->list-resource-templates-request list-resource-templates-request->json
 (struct-out list-resource-templates-result) list-resource-templates-result/c json->list-resource-templates-result list-resource-templates-result->json
 (struct-out read-resource-request-params) read-resource-request-params/c json->read-resource-request-params read-resource-request-params->json
 (struct-out read-resource-request) read-resource-request/c json->read-resource-request read-resource-request->json
 (struct-out read-resource-result) read-resource-result/c json->read-resource-result read-resource-result->json
 (struct-out resource-updated-notification-params) resource-updated-notification-params/c json->resource-updated-notification-params resource-updated-notification-params->json
 (struct-out resource-updated-notification) resource-updated-notification/c json->resource-updated-notification resource-updated-notification->json
 (struct-out resource-list-changed-notification) resource-list-changed-notification/c json->resource-list-changed-notification resource-list-changed-notification->json
 (struct-out resource) resource/c json->resource resource->json
 (struct-out resource-template) resource-template/c json->resource-template resource-template->json
 (struct-out text-resource-contents) text-resource-contents/c json->text-resource-contents text-resource-contents->json
 (struct-out blob-resource-contents) blob-resource-contents/c json->blob-resource-contents blob-resource-contents->json
 resource-contents/c json->resource-contents resource-contents->json
 ;; ---- subscriptions ----
 (struct-out subscription-filter) subscription-filter/c json->subscription-filter subscription-filter->json
 (struct-out subscriptions-listen-request-params) subscriptions-listen-request-params/c json->subscriptions-listen-request-params subscriptions-listen-request-params->json
 (struct-out subscriptions-listen-request) subscriptions-listen-request/c json->subscriptions-listen-request subscriptions-listen-request->json
 (struct-out subscriptions-acknowledged-notification-params) subscriptions-acknowledged-notification-params/c json->subscriptions-acknowledged-notification-params subscriptions-acknowledged-notification-params->json
 (struct-out subscriptions-acknowledged-notification) subscriptions-acknowledged-notification/c json->subscriptions-acknowledged-notification subscriptions-acknowledged-notification->json
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
 (struct-out tool-list-changed-notification) tool-list-changed-notification/c json->tool-list-changed-notification tool-list-changed-notification->json
 ;; ---- logging (deprecated but in-revision) ----
 (struct-out logging-message-notification-params) logging-message-notification-params/c json->logging-message-notification-params logging-message-notification-params->json
 (struct-out logging-message-notification) logging-message-notification/c json->logging-message-notification logging-message-notification->json
 ;; ---- sampling (deprecated but in-revision) ----
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
 ;; ---- roots (deprecated but in-revision) ----
 (struct-out list-roots-request) list-roots-request/c json->list-roots-request list-roots-request->json
 (struct-out list-roots-result) list-roots-result/c json->list-roots-result list-roots-result->json
 (struct-out root) root/c json->root root->json
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
 ;; ---- typed errors ----
 parse-error? invalid-request-error? method-not-found-error?
 invalid-params-error? internal-error?
 make-unsupported-protocol-version-error unsupported-protocol-version-error?
 make-missing-required-client-capability-error missing-required-client-capability-error?
 ;; ---- aggregate union contracts ----
 client-request/c client-notification/c client-result/c
 server-notification/c server-result/c
 jsonrpc-message/c)

;; ============================================================================
;; Scalar / enum contracts (§B, §N)
;; ============================================================================
(define role/c (or/c "user" "assistant"))                       ; Role (1529)
(define cursor/c string?)                                        ; Cursor (125)
(define progress-token/c (flat-named-contract 'progress-token/c progress-token?)) ; (118)
(define request-id/c (flat-named-contract 'request-id/c request-id?))             ; (214)
;; ResultType (169): open enum; effectively string?.
(define result-type/c (flat-named-contract 'result-type/c string?))
;; CacheableResult.cacheScope (999).
(define cache-scope/c (or/c "public" "private"))
(define logging-level/c                                          ; LoggingLevel (1905)
  (or/c "debug" "info" "notice" "warning" "error" "critical" "alert" "emergency"))
;; MetaObject (61): the looser _meta form (notifications/results).
(define meta-object/c (flat-named-contract 'meta-object/c json-object?))

;; ============================================================================
;; A. JSON-RPC envelopes (4) — spec.types 221–262. STRICT top-level keys.
;; ============================================================================

;; JSONRPCRequest (221).
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

;; JSONRPCNotification (231): NO id.
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

;; JSONRPCResultResponse (240): id, result (object, loose).
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

;; Error (194): inner object, NOT strict. code, message, data?.
(struct jsonrpc-error (code message data) #:transparent)
(define jsonrpc-error/c
  (struct/c jsonrpc-error exact-integer? string? (opt/c jsexpr-value?)))
(define (json->jsonrpc-error h)
  (jsonrpc-error (h-req h 'code) (h-req h 'message) (h-opt h 'data)))
(define (jsonrpc-error->json s)
  (put (hasheq 'code (jsonrpc-error-code s) 'message (jsonrpc-error-message s))
       'data (jsonrpc-error-data s)))

;; JSONRPCErrorResponse (251): id?, error.
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
;; B. Common / shared types — spec.types 169–214, 782–889
;; ============================================================================

;; Result (176): base for all results. LOOSE — meta + result-type named + rest.
;; resultType modeled OPTIONAL (per its backward-compat JSDoc; see file header).
(struct result (meta result-type rest) #:transparent)
(define result/c (struct/c result (opt/c json-object?) (opt/c result-type/c) json-object?))
(define result-base-table '((meta . _meta) (result-type . resultType)))
(define (json->result h)
  (result (h-opt h '_meta) (h-opt h 'resultType) (split-loose h result-base-table)))
(define (result->json s)
  (put (put (hash-merge (result-rest s)) 'resultType (result-result-type s))
       '_meta (result-meta s)))

;; BaseMetadata (846): name, title?. (mixed in; no own (de)ser — used inline.)
(struct base-metadata (name title) #:transparent)
(define base-metadata/c (struct/c base-metadata string? (opt/c string?)))

;; Icon (782).
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

;; Annotations (2087): audience?, priority?, lastModified?.
(struct annotations (audience priority last-modified) #:transparent)
(define annotations/c
  (struct/c annotations (opt/c (listof role/c)) (opt/c real?) (opt/c string?)))
(define (json->annotations h)
  (annotations (h-opt h 'audience) (h-opt h 'priority) (h-opt h 'lastModified)))
(define (annotations->json s)
  (put (put (put (hasheq) 'audience (annotations-audience s))
            'priority (annotations-priority s))
       'lastModified (annotations-last-modified s)))

;; Implementation (868): BaseMetadata + Icons + version, description?, websiteUrl?.
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
;; D. Capabilities — spec.types 614–775. Loose blobs (Decisions: same as 003).
;; ============================================================================
(struct client-capabilities (rest) #:transparent)
(define client-capabilities/c (struct/c client-capabilities json-object?))
(define (json->client-capabilities h) (client-capabilities h))
(define (client-capabilities->json s) (client-capabilities-rest s))

(struct server-capabilities (rest) #:transparent)
(define server-capabilities/c (struct/c server-capabilities json-object?))
(define (json->server-capabilities h) (server-capabilities h))
(define (server-capabilities->json s) (server-capabilities-rest s))

;; ----------------------------------------------------------------------------
;; Input family contracts (§F) defined EARLY so request-params contracts (read-
;; resource/get-prompt/tools-call) can reference them. The per-struct predicates
;; are looked up only at APPLY time (wrapped in a lambda), so referencing the
;; later-defined input request/result structs here is safe at module load.
;; The (de)serializer dispatchers + InputRequiredResult live in §F below.
;; ----------------------------------------------------------------------------
;; InputRequest (435): the 3 server->client requests (lazy union).
(define input-request/c
  (flat-named-contract
   'input-request/c
   (lambda (v) (or (create-message-request? v) (list-roots-request? v) (elicit-request? v)))))
;; InputResponse (438): the 3 results (lazy union).
(define input-response/c
  (flat-named-contract
   'input-response/c
   (lambda (v) (or (create-message-result? v) (list-roots-result? v) (elicit-result? v)))))
;; InputRequests (449) / InputResponses (463): hasheq string-key -> struct.
(define input-requests/c (hash/c symbol? input-request/c))
(define input-responses/c (hash/c symbol? input-response/c))

;; ============================================================================
;; C. The RC `_meta` request envelope (THE FEATURE) — spec.types 61–134
;; ============================================================================

;; RelatedTaskMetadata (schemas.ts:60): taskId. Rides inside _meta.
(struct related-task-metadata (task-id) #:transparent)
(define related-task-metadata/c (struct/c related-task-metadata string?))
(define (json->related-task-metadata h) (related-task-metadata (h-req h 'taskId)))
(define (related-task-metadata->json s) (hasheq 'taskId (related-task-metadata-task-id s)))

;; The reserved _meta key SYMBOLS (read-json symbol-keys everything, so the
;; prefixed strings become single symbol keys). Single-sourced from constants.
(define PROTOCOL-VERSION-KEY (string->symbol PROTOCOL-VERSION-META-KEY))
(define CLIENT-INFO-KEY (string->symbol CLIENT-INFO-META-KEY))
(define CLIENT-CAPABILITIES-KEY (string->symbol CLIENT-CAPABILITIES-META-KEY))
(define LOG-LEVEL-KEY (string->symbol LOG-LEVEL-META-KEY))
(define RELATED-TASK-KEY (string->symbol RELATED-TASK-META-KEY))
(define request-meta-reserved-keys
  (list 'progressToken PROTOCOL-VERSION-KEY CLIENT-INFO-KEY
        CLIENT-CAPABILITIES-KEY LOG-LEVEL-KEY RELATED-TASK-KEY))

;; RequestMetaObject (70): progressToken?, protocolVersion(req), clientInfo(req),
;; clientCapabilities(req), logLevel?(deprecated), related-task?, rest.
(struct request-meta (progress-token protocol-version client-info client-capabilities
                                     log-level related-task rest) #:transparent)
(define request-meta/c
  (struct/c request-meta (opt/c progress-token/c) string? implementation?
            client-capabilities? (opt/c logging-level/c) (opt/c related-task-metadata?)
            json-object?))
(define (json->request-meta h)
  (define pv (h-req h PROTOCOL-VERSION-KEY))
  (define ci (h-req h CLIENT-INFO-KEY))
  (define cc (h-req h CLIENT-CAPABILITIES-KEY))
  (when (absent? pv) (error 'json->request-meta "required reserved _meta key missing: ~a" PROTOCOL-VERSION-META-KEY))
  (when (absent? ci) (error 'json->request-meta "required reserved _meta key missing: ~a" CLIENT-INFO-META-KEY))
  (when (absent? cc) (error 'json->request-meta "required reserved _meta key missing: ~a" CLIENT-CAPABILITIES-META-KEY))
  (request-meta
   (h-opt h 'progressToken)
   pv
   (json->implementation ci)
   (json->client-capabilities cc)
   (h-opt h LOG-LEVEL-KEY)
   (opt-map (h-opt h RELATED-TASK-KEY) json->related-task-metadata)
   ;; unreserved _meta keys pass through verbatim
   (for/fold ([acc (hasheq)]) ([(k v) (in-hash h)])
     (if (memq k request-meta-reserved-keys) acc (hash-set acc k v)))))
(define (request-meta->json s)
  (let* ([h (hash-merge (request-meta-rest s))]
         [h (put! h PROTOCOL-VERSION-KEY (request-meta-protocol-version s))]
         [h (put! h CLIENT-INFO-KEY (implementation->json (request-meta-client-info s)))]
         [h (put! h CLIENT-CAPABILITIES-KEY (client-capabilities->json (request-meta-client-capabilities s)))]
         [h (put h 'progressToken (request-meta-progress-token s))]
         [h (put h LOG-LEVEL-KEY (request-meta-log-level s))]
         [h (put h RELATED-TASK-KEY (opt-map (request-meta-related-task s) related-task-metadata->json))])
    h))

;; Helper: read the REQUIRED request _meta envelope from a params hash.
;; Per spec.types:133 RequestParams._meta is REQUIRED — absent -> reject.
(define (read-request-meta h who)
  (define m (h-req h '_meta))
  (when (absent? m) (error who "required _meta envelope missing on request params"))
  (json->request-meta m))

;; ============================================================================
;; E. Discovery (NEW — replaces 2025 `initialize`) — spec.types 547–607
;; ============================================================================

;; DiscoverRequest (559): params = RequestParams (the _meta envelope only).
;; params holds the request-meta struct directly.
(struct discover-request (method meta) #:transparent)
(define discover-request/c
  (struct/c discover-request (lit/c "server/discover") request-meta?))
(define (json->discover-request h)
  (discover-request (h-req h 'method) (read-request-meta (h-req h 'params) 'json->discover-request)))
(define (discover-request->json s)
  (hasheq 'method (discover-request-method s)
          'params (hasheq '_meta (request-meta->json (discover-request-meta s)))))

;; DiscoverResult (572): RESULT (loose) + supportedVersions, capabilities,
;; serverInfo, instructions?.
(struct discover-result (supported-versions capabilities server-info instructions meta result-type rest) #:transparent)
(define discover-result/c
  (struct/c discover-result (listof string?) server-capabilities? implementation?
            (opt/c string?) (opt/c json-object?) (opt/c result-type/c) json-object?))
(define discover-result-table
  '((supported-versions . supportedVersions) (capabilities . capabilities)
                                             (server-info . serverInfo) (instructions . instructions)
                                             (meta . _meta) (result-type . resultType)))
(define (json->discover-result h)
  (discover-result
   (h-req h 'supportedVersions)
   (json->server-capabilities (h-req h 'capabilities))
   (json->implementation (h-req h 'serverInfo))
   (h-opt h 'instructions) (h-opt h '_meta) (h-opt h 'resultType)
   (split-loose h discover-result-table)))
(define (discover-result->json s)
  (let* ([h (hash-merge (discover-result-rest s))]
         [h (put! h 'supportedVersions (discover-result-supported-versions s))]
         [h (put! h 'capabilities (server-capabilities->json (discover-result-capabilities s)))]
         [h (put! h 'serverInfo (implementation->json (discover-result-server-info s)))]
         [h (put h 'instructions (discover-result-instructions s))]
         [h (put h 'resultType (discover-result-result-type s))]
         [h (put h '_meta (discover-result-meta s))])
    h))

;; ============================================================================
;; H. Progress / cancellation — spec.types 507–545, 891–935
;; ============================================================================

;; CancelledNotificationParams (516): NOTIFICATION params (drops unknown; meta).
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

;; ProgressNotificationParams (901): NOTIFICATION params.
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
;; ResourceContents family (defined early; referenced by embedded-resource).
;; spec.types 1349/1370/1383. Discriminator: text vs blob key.
;; ============================================================================
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

;; ============================================================================
;; Content blocks (defined early; referenced by prompt-message / sampling).
;; §P — spec.types 2080, 2122–2322
;; ============================================================================

;; TextContent (2132).
(struct text-content (text annotations meta) #:transparent)
(define text-content/c
  (struct/c text-content string? (opt/c annotations?) (opt/c json-object?)))
(define (json->text-content h)
  (text-content (h-req h 'text) (opt-map (h-opt h 'annotations) json->annotations) (h-opt h '_meta)))
(define (text-content->json s)
  (put (put (put! (put! (hasheq) 'type "text") 'text (text-content-text s))
            'annotations (opt-map (text-content-annotations s) annotations->json))
       '_meta (text-content-meta s)))

;; ImageContent (2156).
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

;; AudioContent (2187).
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

;; ResourceLink (1554): resource fields + type="resource_link".
(struct resource-link (name title uri description mime-type annotations size icons meta rest) #:transparent)
(define resource-link/c
  (struct/c resource-link string? (opt/c string?) string? (opt/c string?) (opt/c string?)
            (opt/c annotations?) (opt/c real?) (opt/c (listof icon?)) (opt/c json-object?) json-object?))
(define resource-link-table
  '((name . name) (title . title) (uri . uri) (description . description)
                  (mime-type . mimeType) (annotations . annotations) (size . size) (icons . icons)
                  (meta . _meta) (type . type)))
(define (json->resource-link h)
  (resource-link (h-req h 'name) (h-opt h 'title) (h-req h 'uri) (h-opt h 'description)
                 (h-opt h 'mimeType) (opt-map (h-opt h 'annotations) json->annotations)
                 (h-opt h 'size) (opt-list (h-opt h 'icons) json->icon) (h-opt h '_meta)
                 (split-loose h resource-link-table)))
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

;; EmbeddedResource (1569): type="resource", resource (text|blob).
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

;; ToolUseContent (2222): type="tool_use", id, name, input, meta?.
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

;; ToolResultContent (2261): type="tool_result", toolUseId, content, structuredContent?, isError?, meta?.
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

;; SamplingMessageContentBlock (2080): text|image|audio|tool_use|tool_result.
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
;; J. Resources — spec.types 1002–1399
;; ============================================================================

;; Resource (1276).
(struct resource (name title uri description mime-type annotations size icons meta rest) #:transparent)
(define resource/c
  (struct/c resource string? (opt/c string?) string? (opt/c string?) (opt/c string?)
            (opt/c annotations?) (opt/c real?) (opt/c (listof icon?)) (opt/c json-object?) json-object?))
(define resource-table
  '((name . name) (title . title) (uri . uri) (description . description)
                  (mime-type . mimeType) (annotations . annotations) (size . size) (icons . icons) (meta . _meta)))
(define (json->resource h)
  (resource (h-req h 'name) (h-opt h 'title) (h-req h 'uri) (h-opt h 'description)
            (h-opt h 'mimeType) (opt-map (h-opt h 'annotations) json->annotations)
            (h-opt h 'size) (opt-list (h-opt h 'icons) json->icon) (h-opt h '_meta)
            (split-loose h resource-table)))
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

;; ResourceTemplate (1316).
(struct resource-template (name title uri-template description mime-type annotations icons meta rest) #:transparent)
(define resource-template/c
  (struct/c resource-template string? (opt/c string?) string? (opt/c string?) (opt/c string?)
            (opt/c annotations?) (opt/c (listof icon?)) (opt/c json-object?) json-object?))
(define resource-template-table
  '((name . name) (title . title) (uri-template . uriTemplate) (description . description)
                  (mime-type . mimeType) (annotations . annotations) (icons . icons) (meta . _meta)))
(define (json->resource-template h)
  (resource-template (h-req h 'name) (h-opt h 'title) (h-req h 'uriTemplate) (h-opt h 'description)
                     (h-opt h 'mimeType) (opt-map (h-opt h 'annotations) json->annotations)
                     (opt-list (h-opt h 'icons) json->icon) (h-opt h '_meta)
                     (split-loose h resource-template-table)))
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

;; Cacheable+paginated result fields, flattened (CacheableResult 973 / Paginated 960).
;; Each list/read result carries next-cursor? + ttl-ms + cache-scope + meta? + result-type? + rest.
(define cacheable-table
  '((next-cursor . nextCursor) (ttl-ms . ttlMs) (cache-scope . cacheScope)
                               (meta . _meta) (result-type . resultType)))
(define (read-cacheable-fields h who)
  (define ttl (h-req h 'ttlMs))
  (define cs (h-req h 'cacheScope))
  (when (absent? ttl) (error who "required field ttlMs missing"))
  (when (absent? cs) (error who "required field cacheScope missing"))
  (values (h-opt h 'nextCursor) ttl cs (h-opt h '_meta) (h-opt h 'resultType)))
(define (emit-cacheable-fields base next-cursor ttl-ms cache-scope meta result-type)
  (let* ([h (put! base 'ttlMs ttl-ms)]
         [h (put! h 'cacheScope cache-scope)]
         [h (put h 'nextCursor next-cursor)]
         [h (put h 'resultType result-type)]
         [h (put h '_meta meta)])
    h))

;; ListResourcesRequest (1011): paginated request — params has _meta + cursor?.
(struct list-resources-request (method cursor meta) #:transparent)
(define list-resources-request/c
  (struct/c list-resources-request (lit/c "resources/list") (opt/c cursor/c) request-meta?))
(define (json->list-resources-request h)
  (define p (h-req h 'params))
  (list-resources-request (h-req h 'method) (h-opt p 'cursor)
                          (read-request-meta p 'json->list-resources-request)))
(define (list-resources-request->json s)
  (hasheq 'method (list-resources-request-method s)
          'params (put (hasheq '_meta (request-meta->json (list-resources-request-meta s)))
                       'cursor (list-resources-request-cursor s))))

;; ListResourcesResult (1023): resources + cacheable/paginated.
(struct list-resources-result (resources next-cursor ttl-ms cache-scope meta result-type rest) #:transparent)
(define list-resources-result/c
  (struct/c list-resources-result (listof resource?) (opt/c cursor/c) real? cache-scope/c
            (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (json->list-resources-result h)
  (define-values (nc ttl cs meta rt) (read-cacheable-fields h 'json->list-resources-result))
  (list-resources-result (req-list (h-req h 'resources) json->resource) nc ttl cs meta rt
                         (split-loose h (cons '(resources . resources) cacheable-table))))
(define (list-resources-result->json s)
  (emit-cacheable-fields
   (put! (hash-merge (list-resources-result-rest s))
         'resources (map resource->json (list-resources-result-resources s)))
   (list-resources-result-next-cursor s) (list-resources-result-ttl-ms s)
   (list-resources-result-cache-scope s) (list-resources-result-meta s)
   (list-resources-result-result-type s)))

;; ListResourceTemplatesRequest (1047).
(struct list-resource-templates-request (method cursor meta) #:transparent)
(define list-resource-templates-request/c
  (struct/c list-resource-templates-request (lit/c "resources/templates/list") (opt/c cursor/c) request-meta?))
(define (json->list-resource-templates-request h)
  (define p (h-req h 'params))
  (list-resource-templates-request (h-req h 'method) (h-opt p 'cursor)
                                   (read-request-meta p 'json->list-resource-templates-request)))
(define (list-resource-templates-request->json s)
  (hasheq 'method (list-resource-templates-request-method s)
          'params (put (hasheq '_meta (request-meta->json (list-resource-templates-request-meta s)))
                       'cursor (list-resource-templates-request-cursor s))))

;; ListResourceTemplatesResult (1059).
(struct list-resource-templates-result (resource-templates next-cursor ttl-ms cache-scope meta result-type rest) #:transparent)
(define list-resource-templates-result/c
  (struct/c list-resource-templates-result (listof resource-template?) (opt/c cursor/c) real? cache-scope/c
            (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (json->list-resource-templates-result h)
  (define-values (nc ttl cs meta rt) (read-cacheable-fields h 'json->list-resource-templates-result))
  (list-resource-templates-result (req-list (h-req h 'resourceTemplates) json->resource-template) nc ttl cs meta rt
                                  (split-loose h (cons '(resource-templates . resourceTemplates) cacheable-table))))
(define (list-resource-templates-result->json s)
  (emit-cacheable-fields
   (put! (hash-merge (list-resource-templates-result-rest s))
         'resourceTemplates (map resource-template->json (list-resource-templates-result-resource-templates s)))
   (list-resource-templates-result-next-cursor s) (list-resource-templates-result-ttl-ms s)
   (list-resource-templates-result-cache-scope s) (list-resource-templates-result-meta s)
   (list-resource-templates-result-result-type s)))

;; ReadResourceRequestParams (1094): uri + inputResponses? + requestState? + _meta envelope.
(struct read-resource-request-params (uri input-responses request-state meta) #:transparent)
(define read-resource-request-params/c
  (struct/c read-resource-request-params string? (opt/c input-responses/c) (opt/c string?) request-meta?))
(define (json->read-resource-request-params h)
  (read-resource-request-params
   (h-req h 'uri)
   (opt-map (h-opt h 'inputResponses) json->input-responses)
   (h-opt h 'requestState)
   (read-request-meta h 'json->read-resource-request-params)))
(define (read-resource-request-params->json s)
  (let* ([h (put! (hasheq) 'uri (read-resource-request-params-uri s))]
         [h (put h 'inputResponses (opt-map (read-resource-request-params-input-responses s) input-responses->json))]
         [h (put h 'requestState (read-resource-request-params-request-state s))]
         [h (put! h '_meta (request-meta->json (read-resource-request-params-meta s)))])
    h))
(struct read-resource-request (method payload) #:transparent)
(define read-resource-request/c
  (struct/c read-resource-request (lit/c "resources/read") read-resource-request-params?))
(define (json->read-resource-request h)
  (read-resource-request (h-req h 'method) (json->read-resource-request-params (h-req h 'params))))
(define (read-resource-request->json s)
  (hasheq 'method (read-resource-request-method s)
          'params (read-resource-request-params->json (read-resource-request-payload s))))

;; ReadResourceResult (1117): contents + cacheable.
(struct read-resource-result (contents next-cursor ttl-ms cache-scope meta result-type rest) #:transparent)
(define read-resource-result/c
  (struct/c read-resource-result (listof resource-contents/c) (opt/c cursor/c) real? cache-scope/c
            (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (json->read-resource-result h)
  (define-values (nc ttl cs meta rt) (read-cacheable-fields h 'json->read-resource-result))
  (read-resource-result (req-list (h-req h 'contents) json->resource-contents) nc ttl cs meta rt
                        (split-loose h (cons '(contents . contents) cacheable-table))))
(define (read-resource-result->json s)
  (emit-cacheable-fields
   (put! (hash-merge (read-resource-result-rest s))
         'contents (map resource-contents->json (read-resource-result-contents s)))
   (read-resource-result-next-cursor s) (read-resource-result-ttl-ms s)
   (read-resource-result-cache-scope s) (read-resource-result-meta s)
   (read-resource-result-result-type s)))

;; ResourceUpdatedNotificationParams (1246) / Notification (1263).
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

;; ResourceListChangedNotification (1144).
(struct resource-list-changed-notification (method params) #:transparent)
(define resource-list-changed-notification/c
  (struct/c resource-list-changed-notification (lit/c "notifications/resources/list_changed") (opt/c json-object?)))
(define (json->resource-list-changed-notification h)
  (resource-list-changed-notification (h-req h 'method) (h-opt h 'params)))
(define (resource-list-changed-notification->json s)
  (put (hasheq 'method (resource-list-changed-notification-method s))
       'params (resource-list-changed-notification-params s)))

;; ============================================================================
;; K. Subscriptions (NEW) — spec.types 1149–1236
;; ============================================================================
(struct subscription-filter (tools-list-changed prompts-list-changed resources-list-changed resource-subscriptions) #:transparent)
(define subscription-filter/c
  (struct/c subscription-filter (opt/c boolean?) (opt/c boolean?) (opt/c boolean?) (opt/c (listof string?))))
(define (json->subscription-filter h)
  (subscription-filter (h-opt h 'toolsListChanged) (h-opt h 'promptsListChanged)
                       (h-opt h 'resourcesListChanged) (h-opt h 'resourceSubscriptions)))
(define (subscription-filter->json s)
  (put (put (put (put (hasheq) 'toolsListChanged (subscription-filter-tools-list-changed s))
                 'promptsListChanged (subscription-filter-prompts-list-changed s))
            'resourcesListChanged (subscription-filter-resources-list-changed s))
       'resourceSubscriptions (subscription-filter-resource-subscriptions s)))

;; SubscriptionsListenRequestParams (1183): notifications (req) + _meta envelope.
(struct subscriptions-listen-request-params (notifications meta) #:transparent)
(define subscriptions-listen-request-params/c
  (struct/c subscriptions-listen-request-params subscription-filter? request-meta?))
(define (json->subscriptions-listen-request-params h)
  (define n (h-req h 'notifications))
  (when (absent? n) (error 'json->subscriptions-listen-request-params "required field notifications missing"))
  (subscriptions-listen-request-params (json->subscription-filter n)
                                       (read-request-meta h 'json->subscriptions-listen-request-params)))
(define (subscriptions-listen-request-params->json s)
  (put! (put! (hasheq) 'notifications (subscription-filter->json (subscriptions-listen-request-params-notifications s)))
        '_meta (request-meta->json (subscriptions-listen-request-params-meta s))))
(struct subscriptions-listen-request (method payload) #:transparent)
(define subscriptions-listen-request/c
  (struct/c subscriptions-listen-request (lit/c "subscriptions/listen") subscriptions-listen-request-params?))
(define (json->subscriptions-listen-request h)
  (subscriptions-listen-request (h-req h 'method) (json->subscriptions-listen-request-params (h-req h 'params))))
(define (subscriptions-listen-request->json s)
  (hasheq 'method (subscriptions-listen-request-method s)
          'params (subscriptions-listen-request-params->json (subscriptions-listen-request-payload s))))

;; SubscriptionsAcknowledgedNotificationParams (1212): notifications (req) + meta?.
(struct subscriptions-acknowledged-notification-params (notifications meta) #:transparent)
(define subscriptions-acknowledged-notification-params/c
  (struct/c subscriptions-acknowledged-notification-params subscription-filter? (opt/c json-object?)))
(define (json->subscriptions-acknowledged-notification-params h)
  (define n (h-req h 'notifications))
  (when (absent? n) (error 'json->subscriptions-acknowledged-notification-params "required field notifications missing"))
  (subscriptions-acknowledged-notification-params (json->subscription-filter n) (h-opt h '_meta)))
(define (subscriptions-acknowledged-notification-params->json s)
  (put (put! (hasheq) 'notifications (subscription-filter->json (subscriptions-acknowledged-notification-params-notifications s)))
       '_meta (subscriptions-acknowledged-notification-params-meta s)))
(struct subscriptions-acknowledged-notification (method payload) #:transparent)
(define subscriptions-acknowledged-notification/c
  (struct/c subscriptions-acknowledged-notification (lit/c "notifications/subscriptions/acknowledged") subscriptions-acknowledged-notification-params?))
(define (json->subscriptions-acknowledged-notification h)
  (subscriptions-acknowledged-notification (h-req h 'method) (json->subscriptions-acknowledged-notification-params (h-req h 'params))))
(define (subscriptions-acknowledged-notification->json s)
  (hasheq 'method (subscriptions-acknowledged-notification-method s)
          'params (subscriptions-acknowledged-notification-params->json (subscriptions-acknowledged-notification-payload s))))

;; ============================================================================
;; L. Prompts — spec.types 1401–1599
;; ============================================================================
(struct list-prompts-request (method cursor meta) #:transparent)
(define list-prompts-request/c
  (struct/c list-prompts-request (lit/c "prompts/list") (opt/c cursor/c) request-meta?))
(define (json->list-prompts-request h)
  (define p (h-req h 'params))
  (list-prompts-request (h-req h 'method) (h-opt p 'cursor) (read-request-meta p 'json->list-prompts-request)))
(define (list-prompts-request->json s)
  (hasheq 'method (list-prompts-request-method s)
          'params (put (hasheq '_meta (request-meta->json (list-prompts-request-meta s)))
                       'cursor (list-prompts-request-cursor s))))

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

;; ListPromptsResult (1413).
(struct list-prompts-result (prompts next-cursor ttl-ms cache-scope meta result-type rest) #:transparent)
(define list-prompts-result/c
  (struct/c list-prompts-result (listof prompt?) (opt/c cursor/c) real? cache-scope/c
            (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (json->list-prompts-result h)
  (define-values (nc ttl cs meta rt) (read-cacheable-fields h 'json->list-prompts-result))
  (list-prompts-result (req-list (h-req h 'prompts) json->prompt) nc ttl cs meta rt
                       (split-loose h (cons '(prompts . prompts) cacheable-table))))
(define (list-prompts-result->json s)
  (emit-cacheable-fields
   (put! (hash-merge (list-prompts-result-rest s)) 'prompts (map prompt->json (list-prompts-result-prompts s)))
   (list-prompts-result-next-cursor s) (list-prompts-result-ttl-ms s)
   (list-prompts-result-cache-scope s) (list-prompts-result-meta s)
   (list-prompts-result-result-type s)))

;; GetPromptRequestParams (1437): name, arguments? + inputResponses? + requestState? + _meta envelope.
(struct get-prompt-request-params (name arguments input-responses request-state meta) #:transparent)
(define get-prompt-request-params/c
  (struct/c get-prompt-request-params string? (opt/c json-object?) (opt/c input-responses/c) (opt/c string?) request-meta?))
(define (json->get-prompt-request-params h)
  (get-prompt-request-params
   (h-req h 'name) (h-opt h 'arguments)
   (opt-map (h-opt h 'inputResponses) json->input-responses)
   (h-opt h 'requestState)
   (read-request-meta h 'json->get-prompt-request-params)))
(define (get-prompt-request-params->json s)
  (let* ([h (put! (hasheq) 'name (get-prompt-request-params-name s))]
         [h (put h 'arguments (get-prompt-request-params-arguments s))]
         [h (put h 'inputResponses (opt-map (get-prompt-request-params-input-responses s) input-responses->json))]
         [h (put h 'requestState (get-prompt-request-params-request-state s))]
         [h (put! h '_meta (request-meta->json (get-prompt-request-params-meta s)))])
    h))
(struct get-prompt-request (method payload) #:transparent)
(define get-prompt-request/c
  (struct/c get-prompt-request (lit/c "prompts/get") get-prompt-request-params?))
(define (json->get-prompt-request h)
  (get-prompt-request (h-req h 'method) (json->get-prompt-request-params (h-req h 'params))))
(define (get-prompt-request->json s)
  (hasheq 'method (get-prompt-request-method s)
          'params (get-prompt-request-params->json (get-prompt-request-payload s))))

;; PromptMessage (1539): role, content (content-block).
(struct prompt-message (role content) #:transparent)
(define prompt-message/c (struct/c prompt-message role/c content-block/c))
(define (json->prompt-message h)
  (prompt-message (h-req h 'role) (json->content-block (h-req h 'content))))
(define (prompt-message->json s)
  (hasheq 'role (prompt-message-role s) 'content (content-block->json (prompt-message-content s))))

;; GetPromptResult (1469): description?, messages, loose.
(struct get-prompt-result (description messages meta result-type rest) #:transparent)
(define get-prompt-result/c
  (struct/c get-prompt-result (opt/c string?) (listof prompt-message?) (opt/c json-object?) (opt/c result-type/c) json-object?))
(define get-prompt-result-table
  '((description . description) (messages . messages) (meta . _meta) (result-type . resultType)))
(define (json->get-prompt-result h)
  (get-prompt-result (h-opt h 'description) (req-list (h-req h 'messages) json->prompt-message)
                     (h-opt h '_meta) (h-opt h 'resultType)
                     (split-loose h get-prompt-result-table)))
(define (get-prompt-result->json s)
  (put (put (put (put! (hash-merge (get-prompt-result-rest s))
                       'messages (map prompt-message->json (get-prompt-result-messages s)))
                 'description (get-prompt-result-description s))
            'resultType (get-prompt-result-result-type s))
       '_meta (get-prompt-result-meta s)))

;; PromptListChangedNotification (1588).
(struct prompt-list-changed-notification (method params) #:transparent)
(define prompt-list-changed-notification/c
  (struct/c prompt-list-changed-notification (lit/c "notifications/prompts/list_changed") (opt/c json-object?)))
(define (json->prompt-list-changed-notification h)
  (prompt-list-changed-notification (h-req h 'method) (h-opt h 'params)))
(define (prompt-list-changed-notification->json s)
  (put (hasheq 'method (prompt-list-changed-notification-method s))
       'params (prompt-list-changed-notification-params s)))

;; ============================================================================
;; M. Tools — spec.types 1602–1845
;; ============================================================================
(struct list-tools-request (method cursor meta) #:transparent)
(define list-tools-request/c
  (struct/c list-tools-request (lit/c "tools/list") (opt/c cursor/c) request-meta?))
(define (json->list-tools-request h)
  (define p (h-req h 'params))
  (list-tools-request (h-req h 'method) (h-opt p 'cursor) (read-request-meta p 'json->list-tools-request)))
(define (list-tools-request->json s)
  (hasheq 'method (list-tools-request-method s)
          'params (put (hasheq '_meta (request-meta->json (list-tools-request-meta s)))
                       'cursor (list-tools-request-cursor s))))

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

;; Tool (1808): inputSchema/outputSchema are OPEN JSON-Schema fragments — loose
;; hasheq ($schema preserved verbatim). NO execution/ToolExecution (tasks gone).
(define (object-schema-fragment? v)
  (and (json-object? v)
       (let ([t (hash-ref v 'type absent)]) (or (absent? t) (equal? t "object")))))
(struct tool (name title description input-schema output-schema annots icons meta rest) #:transparent)
(define tool/c
  (struct/c tool string? (opt/c string?) (opt/c string?) object-schema-fragment?
            (opt/c object-schema-fragment?) (opt/c tool-annotations?)
            (opt/c (listof icon?)) (opt/c json-object?) json-object?))
(define tool-table
  '((name . name) (title . title) (description . description) (input-schema . inputSchema)
                  (output-schema . outputSchema) (annotations . annotations)
                  (icons . icons) (meta . _meta)))
(define (json->tool h)
  (tool (h-req h 'name) (h-opt h 'title) (h-opt h 'description) (h-req h 'inputSchema)
        (h-opt h 'outputSchema)
        (opt-map (h-opt h 'annotations) json->tool-annotations)
        (opt-list (h-opt h 'icons) json->icon) (h-opt h '_meta)
        (split-loose h tool-table)))
(define (tool->json s)
  (put (put (put (put (put (put! (put! (put (hash-merge (tool-rest s)) 'title (tool-title s))
                                       'name (tool-name s))
                                 'inputSchema (tool-input-schema s))
                           'description (tool-description s))
                      'outputSchema (tool-output-schema s))
                 'annotations (opt-map (tool-annots s) tool-annotations->json))
            'icons (opt-map (tool-icons s) (lambda (xs) (map icon->json xs))))
       '_meta (tool-meta s)))

;; ListToolsResult (1614).
(struct list-tools-result (tools next-cursor ttl-ms cache-scope meta result-type rest) #:transparent)
(define list-tools-result/c
  (struct/c list-tools-result (listof tool?) (opt/c cursor/c) real? cache-scope/c
            (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (json->list-tools-result h)
  (define-values (nc ttl cs meta rt) (read-cacheable-fields h 'json->list-tools-result))
  (list-tools-result (req-list (h-req h 'tools) json->tool) nc ttl cs meta rt
                     (split-loose h (cons '(tools . tools) cacheable-table))))
(define (list-tools-result->json s)
  (emit-cacheable-fields
   (put! (hash-merge (list-tools-result-rest s)) 'tools (map tool->json (list-tools-result-tools s)))
   (list-tools-result-next-cursor s) (list-tools-result-ttl-ms s)
   (list-tools-result-cache-scope s) (list-tools-result-meta s)
   (list-tools-result-result-type s)))

;; CallToolRequestParams (1698): name, arguments? + inputResponses? + requestState? + _meta envelope.
(struct call-tool-request-params (name arguments input-responses request-state meta) #:transparent)
(define call-tool-request-params/c
  (struct/c call-tool-request-params string? (opt/c json-object?) (opt/c input-responses/c) (opt/c string?) request-meta?))
(define (json->call-tool-request-params h)
  (call-tool-request-params
   (h-req h 'name) (h-opt h 'arguments)
   (opt-map (h-opt h 'inputResponses) json->input-responses)
   (h-opt h 'requestState)
   (read-request-meta h 'json->call-tool-request-params)))
(define (call-tool-request-params->json s)
  (let* ([h (put! (hasheq) 'name (call-tool-request-params-name s))]
         [h (put h 'arguments (call-tool-request-params-arguments s))]
         [h (put h 'inputResponses (opt-map (call-tool-request-params-input-responses s) input-responses->json))]
         [h (put h 'requestState (call-tool-request-params-request-state s))]
         [h (put! h '_meta (request-meta->json (call-tool-request-params-meta s)))])
    h))
(struct call-tool-request (method payload) #:transparent)
(define call-tool-request/c
  (struct/c call-tool-request (lit/c "tools/call") call-tool-request-params?))
(define (json->call-tool-request h)
  (call-tool-request (h-req h 'method) (json->call-tool-request-params (h-req h 'params))))
(define (call-tool-request->json s)
  (hasheq 'method (call-tool-request-method s)
          'params (call-tool-request-params->json (call-tool-request-payload s))))

;; CallToolResult (1644): content, structuredContent?, isError?, loose.
(struct call-tool-result (content structured-content is-error meta result-type rest) #:transparent)
(define call-tool-result/c
  (struct/c call-tool-result (listof content-block/c) (opt/c json-object?) (opt/c boolean?)
            (opt/c json-object?) (opt/c result-type/c) json-object?))
(define call-tool-result-table
  '((content . content) (structured-content . structuredContent) (is-error . isError)
                        (meta . _meta) (result-type . resultType)))
(define (json->call-tool-result h)
  (call-tool-result (req-list (h-req h 'content) json->content-block)
                    (h-opt h 'structuredContent) (h-opt h 'isError) (h-opt h '_meta) (h-opt h 'resultType)
                    (split-loose h call-tool-result-table)))
(define (call-tool-result->json s)
  (put (put (put (put (put! (hash-merge (call-tool-result-rest s))
                            'content (map content-block->json (call-tool-result-content s)))
                      'structuredContent (call-tool-result-structured-content s))
                 'isError (call-tool-result-is-error s))
            'resultType (call-tool-result-result-type s))
       '_meta (call-tool-result-meta s)))

;; ToolListChangedNotification (1730).
(struct tool-list-changed-notification (method params) #:transparent)
(define tool-list-changed-notification/c
  (struct/c tool-list-changed-notification (lit/c "notifications/tools/list_changed") (opt/c json-object?)))
(define (json->tool-list-changed-notification h)
  (tool-list-changed-notification (h-req h 'method) (h-opt h 'params)))
(define (tool-list-changed-notification->json s)
  (put (hasheq 'method (tool-list-changed-notification-method s))
       'params (tool-list-changed-notification-params s)))

;; ============================================================================
;; N. Logging (DEPRECATED but in-revision) — spec.types 1847–1905
;; (NO logging/setLevel — replaced by the _meta logLevel envelope key.)
;; ============================================================================
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
;; O. Sampling (DEPRECATED but in-revision) — spec.types 1907–2080, 2324–2407
;; (server->client; plain params, NO _meta envelope, NO task.)
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

;; SamplingMessage (2067): role, content (block OR list), meta?.
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

;; CreateMessageRequestParams (1926): server->client; plain params. NO _meta envelope.
(struct create-message-request-params
  (messages model-preferences system-prompt include-context temperature max-tokens
            stop-sequences metadata tools tool-choice meta) #:transparent)
(define create-message-request-params/c
  (struct/c create-message-request-params
            (listof sampling-message?) (opt/c model-preferences?) (opt/c string?)
            (opt/c (or/c "none" "thisServer" "allServers")) (opt/c real?) real?
            (opt/c (listof string?)) (opt/c json-object?) (opt/c (listof tool?))
            (opt/c tool-choice?) (opt/c json-object?)))
(define (json->create-message-request-params h)
  (define mt (h-req h 'maxTokens))
  (when (absent? mt) (error 'json->create-message-request-params "required field maxTokens missing"))
  (create-message-request-params
   (req-list (h-req h 'messages) json->sampling-message)
   (opt-map (h-opt h 'modelPreferences) json->model-preferences)
   (h-opt h 'systemPrompt) (h-opt h 'includeContext) (h-opt h 'temperature) mt
   (h-opt h 'stopSequences) (h-opt h 'metadata)
   (opt-list (h-opt h 'tools) json->tool)
   (opt-map (h-opt h 'toolChoice) json->tool-choice) (h-opt h '_meta)))
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

;; CreateMessageResult (2032): Result & SamplingMessage + model, stopReason?, loose.
(struct create-message-result (role content model stop-reason meta result-type rest) #:transparent)
(define create-message-result/c
  (struct/c create-message-result role/c sampling-message-content/c string? (opt/c string?)
            (opt/c json-object?) (opt/c result-type/c) json-object?))
(define create-message-result-table
  '((role . role) (content . content) (model . model) (stop-reason . stopReason)
                  (meta . _meta) (result-type . resultType)))
(define (json->create-message-result h)
  (define c (h-req h 'content))
  (create-message-result (h-req h 'role)
                         (if (list? c) (map json->sampling-message-content-block c)
                             (json->sampling-message-content-block c))
                         (h-req h 'model) (h-opt h 'stopReason) (h-opt h '_meta) (h-opt h 'resultType)
                         (split-loose h create-message-result-table)))
(define (create-message-result->json s)
  (define c (create-message-result-content s))
  (let* ([h (hash-merge (create-message-result-rest s))]
         [h (put! h 'role (create-message-result-role s))]
         [h (hash-set h 'content (if (list? c) (map sampling-message-content-block->json c)
                                     (sampling-message-content-block->json c)))]
         [h (put! h 'model (create-message-result-model s))]
         [h (put h 'stopReason (create-message-result-stop-reason s))]
         [h (put h 'resultType (create-message-result-result-type s))]
         [h (put h '_meta (create-message-result-meta s))])
    h))

;; ============================================================================
;; Q. Autocomplete / completion — spec.types 2409–2513
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

;; CompleteRequestParams (2409): ref, argument, context? + _meta envelope.
(struct complete-request-params (ref argument context meta) #:transparent)
(define complete-request-params/c
  (struct/c complete-request-params complete-ref/c json-object? (opt/c json-object?) request-meta?))
(define (json->complete-request-params h)
  (complete-request-params (json->complete-ref (h-req h 'ref)) (h-req h 'argument)
                           (h-opt h 'context) (read-request-meta h 'json->complete-request-params)))
(define (complete-request-params->json s)
  (let* ([h (put! (hasheq) 'ref (complete-ref->json (complete-request-params-ref s)))]
         [h (put! h 'argument (complete-request-params-argument s))]
         [h (put h 'context (complete-request-params-context s))]
         [h (put! h '_meta (request-meta->json (complete-request-params-meta s)))])
    h))
(struct complete-request (method payload) #:transparent)
(define complete-request/c
  (struct/c complete-request (lit/c "completion/complete") complete-request-params?))
(define (json->complete-request h)
  (complete-request (h-req h 'method) (json->complete-request-params (h-req h 'params))))
(define (complete-request->json s)
  (hasheq 'method (complete-request-method s)
          'params (complete-request-params->json (complete-request-payload s))))

;; CompleteResult (2460): completion, meta?, loose.
(struct complete-result (completion meta result-type rest) #:transparent)
(define complete-result/c
  (struct/c complete-result json-object? (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (json->complete-result h)
  (complete-result (h-req h 'completion) (h-opt h '_meta) (h-opt h 'resultType)
                   (split-loose h '((completion . completion) (meta . _meta) (result-type . resultType)))))
(define (complete-result->json s)
  (put (put (put! (hash-merge (complete-result-rest s)) 'completion (complete-result-completion s))
            'resultType (complete-result-result-type s))
       '_meta (complete-result-meta s)))

;; ============================================================================
;; O2. Roots (DEPRECATED but in-revision) — spec.types 2515–2600
;; ============================================================================

;; ListRootsRequest (2534): BARE interface — method + params? (RequestParams).
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

;; ListRootsResult (2556): BARE interface — { roots: Root[] } ONLY.
;; NO meta, NO result-type, NO rest (does NOT extend Result). Serializer emits
;; EXACTLY {"roots":[...]}. (Per-root _meta still round-trips on each `root`.)
(struct list-roots-result (roots) #:transparent)
(define list-roots-result/c (struct/c list-roots-result (listof root?)))
(define (json->list-roots-result h)
  (list-roots-result (req-list (h-req h 'roots) json->root)))
(define (list-roots-result->json s)
  (hasheq 'roots (map root->json (list-roots-result-roots s))))

;; ============================================================================
;; P2. Elicitation — spec.types 2602–2982
;; (server->client; plain params, NO _meta envelope, NO task.)
;; ============================================================================

;; StringSchema (2694).
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

;; NumberSchema (2710): type "number"|"integer".
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

;; BooleanSchema (2734).
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

;; EnumSchema family (2749–2933).
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

;; PrimitiveSchemaDefinition (2686): string|number|integer|boolean|enum.
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

;; ElicitRequestFormParams (2602): mode?="form", message, requestedSchema (loose).
(struct elicit-request-form-params (mode message requested-schema) #:transparent)
(define elicit-request-form-params/c
  (struct/c elicit-request-form-params (opt/c (lit/c "form")) string? json-object?))
(define (json->elicit-request-form-params h)
  (elicit-request-form-params (h-opt h 'mode) (h-req h 'message) (h-req h 'requestedSchema)))
(define (elicit-request-form-params->json s)
  (let* ([h (put! (put! (hasheq) 'message (elicit-request-form-params-message s))
                  'requestedSchema (elicit-request-form-params-requested-schema s))]
         [h (put h 'mode (elicit-request-form-params-mode s))])
    h))

;; ElicitRequestURLParams (2635): mode="url" (req), message, elicitationId, url.
(struct elicit-request-url-params (mode message elicitation-id url) #:transparent)
(define elicit-request-url-params/c
  (struct/c elicit-request-url-params (lit/c "url") string? string? string?))
(define (json->elicit-request-url-params h)
  (elicit-request-url-params (h-req h 'mode) (h-req h 'message) (h-req h 'elicitationId) (h-req h 'url)))
(define (elicit-request-url-params->json s)
  (put! (put! (put! (put! (hasheq) 'mode (elicit-request-url-params-mode s))
                    'message (elicit-request-url-params-message s))
              'elicitationId (elicit-request-url-params-elicitation-id s))
        'url (elicit-request-url-params-url s)))

;; ElicitRequestParams (2665): discriminate on mode.
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

;; ElicitResult (2949): action, content?, meta?, loose.
(struct elicit-result (action content meta result-type rest) #:transparent)
(define elicit-result/c
  (struct/c elicit-result (or/c "accept" "decline" "cancel") (opt/c json-object?) (opt/c json-object?) (opt/c result-type/c) json-object?))
(define (json->elicit-result h)
  (elicit-result (h-req h 'action) (h-opt h 'content) (h-opt h '_meta) (h-opt h 'resultType)
                 (split-loose h '((action . action) (content . content) (meta . _meta) (result-type . resultType)))))
(define (elicit-result->json s)
  (put (put (put (put! (hash-merge (elicit-result-rest s)) 'action (elicit-result-action s))
                 'content (elicit-result-content s))
            'resultType (elicit-result-result-type s))
       '_meta (elicit-result-meta s)))

;; ElicitationCompleteNotification (2974): params {elicitationId}.
(struct elicitation-complete-notification (method params) #:transparent)
(define elicitation-complete-notification/c
  (struct/c elicitation-complete-notification (lit/c "notifications/elicitation/complete") json-object?))
(define (json->elicitation-complete-notification h)
  (elicitation-complete-notification (h-req h 'method) (h-req h 'params)))
(define (elicitation-complete-notification->json s)
  (hasheq 'method (elicitation-complete-notification-method s)
          'params (elicitation-complete-notification-params s)))

;; ============================================================================
;; F. Multi-round-trip / input family (NEW) — spec.types 435–505
;;
;; The InputRequest/InputResponse unions reference structs defined later in the
;; file (create-message-*, list-roots-*, elicit-*), and the input maps are used
;; by request-params contracts defined EARLIER (read-resource/get-prompt/tools-
;; call). To make both directions work despite module load order, the union
;; predicates are wrapped in a lambda (flat-named-contract) so the per-struct
;; predicate identifiers are looked up only when the contract is APPLIED, not at
;; load time. The (de)serializer dispatchers likewise resolve at call time.
;; ============================================================================

;; (input-request/c, input-response/c, input-requests/c, input-responses/c are
;;  defined EARLY — see "Input family contracts" after §D — so the request-params
;;  contracts can reference them.)

;; Dispatch an input-request value (by method) and an input-response (by shape).
(define (json->input-request h)
  (case (h-req h 'method)
    [("sampling/createMessage") (json->create-message-request h)]
    [("roots/list") (json->list-roots-request h)]
    [("elicitation/create") (json->elicit-request h)]
    [else (error 'json->input-request "unknown input request method: ~a" (h-req h 'method))]))
(define (input-request->json s)
  (cond [(create-message-request? s) (create-message-request->json s)]
        [(list-roots-request? s) (list-roots-request->json s)]
        [(elicit-request? s) (elicit-request->json s)]
        [else (error 'input-request->json "not an input request: ~a" s)]))
(define (json->input-response h)
  (cond [(hash-has-key? h 'roots) (json->list-roots-result h)]
        [(hash-has-key? h 'action) (json->elicit-result h)]
        [(hash-has-key? h 'model) (json->create-message-result h)]
        [else (error 'json->input-response "cannot discriminate input response: ~a" h)]))
(define (input-response->json s)
  (cond [(create-message-result? s) (create-message-result->json s)]
        [(list-roots-result? s) (list-roots-result->json s)]
        [(elicit-result? s) (elicit-result->json s)]
        [else (error 'input-response->json "not an input response: ~a" s)]))

(define (json->input-requests h)
  (for/fold ([acc (hasheq)]) ([(k v) (in-hash h)]) (hash-set acc k (json->input-request v))))
(define (input-requests->json m)
  (for/fold ([acc (hasheq)]) ([(k v) (in-hash m)]) (hash-set acc k (input-request->json v))))
(define (json->input-responses h)
  (for/fold ([acc (hasheq)]) ([(k v) (in-hash h)]) (hash-set acc k (json->input-response v))))
(define (input-responses->json m)
  (for/fold ([acc (hasheq)]) ([(k v) (in-hash m)]) (hash-set acc k (input-response->json v))))

;; InputRequiredResult (480): a Result; inputRequests? + requestState? (>=1 present).
(struct input-required-result (input-requests request-state meta result-type rest) #:transparent)
(define input-required-result/c
  (struct/c input-required-result (opt/c input-requests/c) (opt/c string?)
            (opt/c json-object?) (opt/c result-type/c) json-object?))
(define input-required-result-table
  '((input-requests . inputRequests) (request-state . requestState) (meta . _meta) (result-type . resultType)))
(define (json->input-required-result h)
  (input-required-result
   (opt-map (h-opt h 'inputRequests) json->input-requests)
   (h-opt h 'requestState) (h-opt h '_meta) (h-opt h 'resultType)
   (split-loose h input-required-result-table)))
(define (input-required-result->json s)
  (let* ([h (hash-merge (input-required-result-rest s))]
         [h (put h 'inputRequests (opt-map (input-required-result-input-requests s) input-requests->json))]
         [h (put h 'requestState (input-required-result-request-state s))]
         [h (put h 'resultType (input-required-result-result-type s))]
         [h (put h '_meta (input-required-result-meta s))])
    h))

;; ============================================================================
;; R. Typed error structs (NEW) — spec.types 281–424
;; ============================================================================

;; The 5 code-pinned plain errors are just jsonrpc-error with a fixed code.
(define (error-code-pred code)
  (lambda (v) (and (jsonrpc-error? v) (= (jsonrpc-error-code v) code))))
(define parse-error? (error-code-pred PARSE-ERROR))
(define invalid-request-error? (error-code-pred INVALID-REQUEST))
(define method-not-found-error? (error-code-pred METHOD-NOT-FOUND))
(define invalid-params-error? (error-code-pred INVALID-PARAMS))
(define internal-error? (error-code-pred INTERNAL-ERROR))

;; UnsupportedProtocolVersionError (387): error.code=-32004 + data {supported, requested}.
(define (make-unsupported-protocol-version-error id supported requested
                                                 [message "Unsupported protocol version"])
  (jsonrpc-error-response
   id
   (jsonrpc-error UNSUPPORTED-PROTOCOL-VERSION message
                  (hasheq 'supported supported 'requested requested))))
(define (unsupported-protocol-version-error? v)
  (and (jsonrpc-error-response? v)
       (jsonrpc-error? (jsonrpc-error-response-error v))
       (= (jsonrpc-error-code (jsonrpc-error-response-error v)) UNSUPPORTED-PROTOCOL-VERSION)
       (let ([d (jsonrpc-error-data (jsonrpc-error-response-error v))])
         (and (json-object? d)
              (list? (hash-ref d 'supported #f))
              (string? (hash-ref d 'requested #f))))))

;; MissingRequiredClientCapabilityError (414): error.code=-32003 + data {requiredCapabilities}.
(define (make-missing-required-client-capability-error id required-capabilities
                                                       [message "Missing required client capability"])
  (jsonrpc-error-response
   id
   (jsonrpc-error MISSING-REQUIRED-CLIENT-CAPABILITY message
                  (hasheq 'requiredCapabilities (client-capabilities->json required-capabilities)))))
(define (missing-required-client-capability-error? v)
  (and (jsonrpc-error-response? v)
       (jsonrpc-error? (jsonrpc-error-response-error v))
       (= (jsonrpc-error-code (jsonrpc-error-response-error v)) MISSING-REQUIRED-CLIENT-CAPABILITY)
       (let ([d (jsonrpc-error-data (jsonrpc-error-response-error v))])
         (and (json-object? d) (json-object? (hash-ref d 'requiredCapabilities #f))))))

;; ============================================================================
;; S. Aggregate union contracts — spec.types 2986–3030
;; ============================================================================
(define client-request/c
  (or/c discover-request? complete-request? get-prompt-request? list-prompts-request?
        list-resources-request? list-resource-templates-request? read-resource-request?
        subscriptions-listen-request? call-tool-request? list-tools-request?))
(define client-notification/c
  (or/c cancelled-notification? progress-notification?))
;; ClientResult (3002) = EmptyResult only.
(define client-result/c result?)
(define server-notification/c
  (or/c cancelled-notification? progress-notification? resource-list-changed-notification?
        subscriptions-acknowledged-notification? resource-updated-notification?
        prompt-list-changed-notification? tool-list-changed-notification?
        logging-message-notification? elicitation-complete-notification?))
(define server-result/c
  (or/c result? discover-result? complete-result? get-prompt-result? list-prompts-result?
        list-resources-result? list-resource-templates-result? read-resource-result?
        call-tool-result? list-tools-result? create-message-result? list-roots-result?
        elicit-result? input-required-result?))
(define jsonrpc-message/c
  (or/c jsonrpc-request? jsonrpc-notification? jsonrpc-result-response? jsonrpc-error-response?))
