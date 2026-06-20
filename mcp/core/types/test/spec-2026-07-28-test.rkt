#lang racket/base

;; Test for ../spec-2026-07-28.rkt (item 004). Six parts (mirrors item 003 +
;; adds Part 4 for the RC-only fields):
;;  1. round-trip (canonicalized jsexpr=?) per envelope/category fixture AND
;;     per discriminated-union arm + a deep-capability fixture.
;;  2. _meta/extra-key passthrough — RESULTS preserve, PARAMS drop (asymmetry).
;;  3. contract-rejection per category.
;;  4. RC-ONLY-FIELDS PRESENT-AND-PARSED (the distinguishing criterion): the 5
;;     reserved _meta keys -> named request-meta fields re-emitted at the exact
;;     io.modelcontextprotocol/... strings; resultType / ttlMs / cacheScope /
;;     inputRequests / requestState round-trip present.
;;  5. three-way strictness parity + the 2 data-carrying typed errors.
;;  6. fixture-INDEPENDENT field-name mapping unit test (kebab<->camel, $schema,
;;     _meta, and the 5 reserved keys).
;;
;; Canonical equality: `jsexpr=?` (unordered object keys, lists in order,
;; numbers by =, 'null by eq?; NOT raw bytes). Reused from item 003.
;;
;; Fixture honesty: the 2026-*.json camelCase keys + the prefixed _meta keys
;; were COPIED from typescript-sdk/.../spec.types.2026-07-28.ts and constants.ts.
;; Cited lines (read 2026-06-18, frozen commit 9d700ed):
;;   - RequestMetaObject (spec.types:70): progressToken (74),
;;     io.modelcontextprotocol/protocolVersion (83), .../clientInfo (90),
;;     .../clientCapabilities (98), .../logLevel (110); related-task via
;;     constants.ts:5. The five key STRINGS are constants.ts 14/19/27/38/5.
;;   - DiscoverResult (572): supportedVersions, capabilities, serverInfo,
;;     instructions; ServerCapabilities (688) incl. extensions (774).
;;   - CallToolRequestParams (1698): name, arguments; InputResponseRequestParams
;;     (496): inputResponses, requestState.
;;   - ListToolsResult (1614) = PaginatedResult+CacheableResult: tools,
;;     nextCursor (965), ttlMs (986), cacheScope (999); Tool (1808) inputSchema.
;;   - InputRequiredResult (480): inputRequests, requestState.
;;   - UnsupportedProtocolVersionError (387): code -32004 + data{supported,requested}.
;;
;; The exact check count is pinned at the end.

(require rackunit
         racket/runtime-path
         racket/contract
         json
         (file "../spec-2026-07-28.rkt")
         (file "../constants.rkt"))

(define-runtime-path fixtures "fixtures")
(define (fx name) (build-path fixtures name))
(define (read-fx name) (call-with-input-file (fx name) read-json))

;; --- canonical jsexpr equality (reused from item 003) -------------------
(define (jsexpr=? a b)
  (cond
    [(and (hash? a) (hash? b))
     (and (= (hash-count a) (hash-count b))
          (for/and ([(k v) (in-hash a)])
            (and (hash-has-key? b k) (jsexpr=? v (hash-ref b k)))))]
    [(and (list? a) (list? b))
     (and (= (length a) (length b)) (andmap jsexpr=? a b))]
    [(and (number? a) (number? b)) (= a b)]
    [else (equal? a b)]))

(check-true  (jsexpr=? (hasheq 'a 1 'b 2) (hasheq 'b 2 'a 1)) "jsexpr=? unordered keys")
(check-false (jsexpr=? (hasheq 'a 1) (hasheq 'a 2))           "jsexpr=? value diff")
(check-false (jsexpr=? (list 1 2) (list 2 1))                 "jsexpr=? list order matters")
(check-true  (jsexpr=? 'null 'null)                           "jsexpr=? null")

(define (check-rt name orig->struct struct->orig orig [expect orig])
  (define s (orig->struct orig))
  (define rt (struct->orig s))
  (check-true (jsexpr=? expect rt) (format "round-trip ~a" name))
  (check-true (jsexpr=? rt (struct->orig (orig->struct rt))) (format "idempotent ~a" name)))

;; ========================================================================
;; PART 1 — round-trip per envelope/category fixture
;; ========================================================================

;; server/discover request — full _meta envelope (incl. unreserved key in rest).
(check-rt "discover-request" json->discover-request discover-request->json
          (read-fx "2026-discover-request.json"))

;; tools/call request — _meta envelope + inputResponses + requestState.
(check-rt "tools-call-request" json->call-tool-request call-tool-request->json
          (read-fx "2026-tools-call-request.json"))

;; discover result (loose) — populated server capabilities + extensions.
(check-rt "discover-result" json->discover-result discover-result->json
          (read-fx "2026-discover-result.json"))

;; progress notification.
(check-rt "progress-notification" json->progress-notification progress-notification->json
          (read-fx "2026-progress-notification.json"))

;; list-tools result — pagination + ttlMs/cacheScope + _meta + resultType + extra.
(check-rt "list-tools-result" json->list-tools-result list-tools-result->json
          (read-fx "2026-list-tools-result.json"))

;; subscriptions/listen request.
(check-rt "subscriptions-listen-request" json->subscriptions-listen-request
          subscriptions-listen-request->json (read-fx "2026-subscriptions-listen-request.json"))

;; error response (envelope).
(check-rt "error-response" json->jsonrpc-error-response jsonrpc-error-response->json
          (read-fx "2026-error-response.json"))

;; input-required-result — inputRequests (all 3 arms) + requestState.
(check-rt "input-required-result" json->input-required-result input-required-result->json
          (read-fx "2026-input-required-result.json"))

;; --- discriminated-union arms: ContentBlock (5) -------------------------
(let ([blocks (read-fx "2026-content-blocks.json")]
      [preds (list text-content? image-content? audio-content? resource-link? embedded-resource?)]
      [names '("text" "image" "audio" "resource_link" "resource")])
  (for ([blk (in-list blocks)] [p (in-list preds)] [n (in-list names)])
    (define s (json->content-block blk))
    (check-true (p s) (format "ContentBlock arm ~a dispatched correctly" n))
    (check-true (jsexpr=? blk (content-block->json s)) (format "ContentBlock arm ~a round-trip" n))))

;; --- SamplingMessageContentBlock arms (5) incl tool_use/tool_result -----
(let ([blocks (read-fx "2026-sampling-content-blocks.json")]
      [preds (list text-content? image-content? audio-content? tool-use-content? tool-result-content?)]
      [names '("text" "image" "audio" "tool_use" "tool_result")])
  (for ([blk (in-list blocks)] [p (in-list preds)] [n (in-list names)])
    (define s (json->sampling-message-content-block blk))
    (check-true (p s) (format "SamplingContentBlock arm ~a dispatched correctly" n))
    (check-true (jsexpr=? blk (sampling-message-content-block->json s))
                (format "SamplingContentBlock arm ~a round-trip" n))))

;; --- sampling-message content as single block AND as list ----------------
(let ([single (hasheq 'role "user" 'content (hasheq 'type "text" 'text "x"))]
      [aslist (hasheq 'role "user" 'content (list (hasheq 'type "text" 'text "x")
                                                  (hasheq 'type "text" 'text "y")))])
  (check-true (jsexpr=? single (sampling-message->json (json->sampling-message single)))
              "sampling-message content single block round-trip")
  (check-true (jsexpr=? aslist (sampling-message->json (json->sampling-message aslist)))
              "sampling-message content list round-trip"))

;; --- PrimitiveSchemaDefinition arms (4) ----------------------------------
(let ([schemas (read-fx "2026-primitive-schemas.json")]
      [preds (list string-schema? number-schema? number-schema? boolean-schema?)]
      [names '("string" "number" "integer" "boolean")])
  (for ([sc (in-list schemas)] [p (in-list preds)] [n (in-list names)])
    (define s (json->primitive-schema-definition sc))
    (check-true (p s) (format "PrimitiveSchema arm ~a dispatched correctly" n))
    (check-true (jsexpr=? sc (primitive-schema-definition->json s))
                (format "PrimitiveSchema arm ~a round-trip" n))))

;; --- EnumSchema arms (5) -------------------------------------------------
(let ([schemas (read-fx "2026-enum-schemas.json")]
      [preds (list untitled-single-select-enum-schema? titled-single-select-enum-schema?
                   untitled-multi-select-enum-schema? titled-multi-select-enum-schema?
                   legacy-titled-enum-schema?)]
      [names '("untitled-single" "titled-single" "untitled-multi" "titled-multi" "legacy")])
  (for ([sc (in-list schemas)] [p (in-list preds)] [n (in-list names)])
    (define s (json->enum-schema sc))
    (check-true (p s) (format "EnumSchema arm ~a dispatched correctly" n))
    (check-true (jsexpr=? sc (enum-schema->json s))
                (format "EnumSchema arm ~a round-trip" n))))

;; --- ElicitRequestParams arms (2): form, url -----------------------------
(let ([ps (read-fx "2026-elicit-params.json")]
      [preds (list elicit-request-form-params? elicit-request-url-params?)]
      [names '("form" "url")])
  (for ([p* (in-list ps)] [p (in-list preds)] [n (in-list names)])
    (define s (json->elicit-request-params p*))
    (check-true (p s) (format "ElicitRequestParams arm ~a dispatched correctly" n))
    (check-true (jsexpr=? p* (elicit-request-params->json s))
                (format "ElicitRequestParams arm ~a round-trip" n))))

;; --- ResourceContents arms (2): text, blob -------------------------------
(let ([cs (read-fx "2026-resource-contents.json")]
      [preds (list text-resource-contents? blob-resource-contents?)]
      [names '("text" "blob")])
  (for ([c (in-list cs)] [p (in-list preds)] [n (in-list names)])
    (define s (json->resource-contents c))
    (check-true (p s) (format "ResourceContents arm ~a dispatched correctly" n))
    (check-true (jsexpr=? c (resource-contents->json s))
                (format "ResourceContents arm ~a round-trip" n))))

;; --- InputResponse arms (3) inside an inputResponses map -----------------
(let* ([m (read-fx "2026-input-responses.json")]
       [parsed (json->input-responses m)])
  (check-true (create-message-result? (hash-ref parsed 'sample-1)) "InputResponse arm createMessageResult")
  (check-true (list-roots-result? (hash-ref parsed 'roots-1)) "InputResponse arm listRootsResult")
  (check-true (elicit-result? (hash-ref parsed 'elicit-1)) "InputResponse arm elicitResult")
  (check-true (jsexpr=? m (input-responses->json parsed)) "InputResponses map round-trip"))

;; --- InputRequest arms (3) inside the input-required-result inputRequests --
(let* ([irr (json->input-required-result (read-fx "2026-input-required-result.json"))]
       [reqs (input-required-result-input-requests irr)])
  (check-true (elicit-request? (hash-ref reqs 'elicit-1)) "InputRequest arm elicitRequest")
  (check-true (create-message-request? (hash-ref reqs 'sample-1)) "InputRequest arm createMessageRequest")
  (check-true (list-roots-request? (hash-ref reqs 'roots-1)) "InputRequest arm listRootsRequest"))

;; ========================================================================
;; PART 2 — _meta / extra-key passthrough (RESULTS preserve, PARAMS drop)
;; ========================================================================

;; RESULTS preserve: list-tools-result carries _meta + extraUnknownKey; both
;; survive in `rest`.
(let* ([orig (read-fx "2026-list-tools-result.json")]
       [rt (list-tools-result->json (json->list-tools-result orig))])
  (check-true (hash-has-key? rt 'extraUnknownKey) "RESULT preserves unknown extra key")
  (check-true (hash-has-key? rt '_meta) "RESULT preserves _meta"))

;; PARAMS drop: a tools/call params with an unknown non-_meta key -> dropped.
(let* ([params (hasheq 'name "t" 'bogusExtra 99
                       '_meta (hasheq (string->symbol PROTOCOL-VERSION-META-KEY) "2026-07-28"
                                      (string->symbol CLIENT-INFO-META-KEY) (hasheq 'name "c" 'version "1")
                                      (string->symbol CLIENT-CAPABILITIES-META-KEY) (hasheq)))]
       [rt (call-tool-request-params->json (json->call-tool-request-params params))])
  (check-false (hash-has-key? rt 'bogusExtra) "PARAMS drop unknown non-_meta key")
  (check-true (hash-has-key? rt '_meta) "PARAMS keep _meta envelope"))

;; An UNRESERVED _meta key inside the envelope survives in request-meta's rest.
(let* ([rm (json->request-meta
            (hasheq (string->symbol PROTOCOL-VERSION-META-KEY) "2026-07-28"
                    (string->symbol CLIENT-INFO-META-KEY) (hasheq 'name "c" 'version "1")
                    (string->symbol CLIENT-CAPABILITIES-META-KEY) (hasheq)
                    'com.example/trace "t-9"))]
       [rt (request-meta->json rm)])
  (check-equal? (hash-ref (request-meta-rest rm) 'com.example/trace) "t-9"
                "unreserved _meta key lands in request-meta rest")
  (check-equal? (hash-ref rt 'com.example/trace) "t-9"
                "unreserved _meta key re-serialized verbatim"))

;; ========================================================================
;; PART 3 — contract-rejection per category
;; ========================================================================

;; request-meta missing protocolVersion -> reject.
(check-exn exn:fail? (lambda ()
  (json->request-meta (hasheq (string->symbol CLIENT-INFO-META-KEY) (hasheq 'name "c" 'version "1")
                              (string->symbol CLIENT-CAPABILITIES-META-KEY) (hasheq))))
  "request-meta missing protocolVersion rejected")

;; _meta REQUIRED on request params: absent _meta -> reject.
(check-exn exn:fail? (lambda ()
  (json->call-tool-request-params (hasheq 'name "t")))
  "request params with no _meta envelope rejected")

;; tools/call name = number -> contract reject.
(check-exn exn:fail? (lambda ()
  (contract call-tool-request-params/c
            (call-tool-request-params 42 absent absent absent
                                      (request-meta absent "2026-07-28"
                                                    (implementation "c" absent "1" absent absent absent)
                                                    (client-capabilities (hasheq)) absent absent (hasheq)))
            'pos 'neg))
  "tools/call non-string name rejected")

;; out-of-enum cacheScope ("shared") -> reject.
(check-exn exn:fail? (lambda ()
  (contract cache-scope/c "shared" 'pos 'neg))
  "out-of-enum cacheScope rejected")

;; content block {type:"text"} missing text -> reject (contract catches the
;; absent required field; the deserializer is permissive and the /c is the gate).
(check-exn exn:fail? (lambda ()
  (contract text-content/c (json->content-block (hasheq 'type "text")) 'pos 'neg))
  "text content missing text rejected (contract on deser result)")
(check-exn exn:fail? (lambda ()
  (contract text-content/c (text-content absent absent absent) 'pos 'neg))
  "text content missing text rejected (contract)")

;; content block {type:"bogus"} -> reject.
(check-exn exn:fail? (lambda ()
  (json->content-block (hasheq 'type "bogus")))
  "unknown content block type rejected")

;; subscriptions/listen params missing notifications -> reject.
(check-exn exn:fail? (lambda ()
  (json->subscriptions-listen-request-params
   (hasheq '_meta (hasheq (string->symbol PROTOCOL-VERSION-META-KEY) "2026-07-28"
                          (string->symbol CLIENT-INFO-META-KEY) (hasheq 'name "c" 'version "1")
                          (string->symbol CLIENT-CAPABILITIES-META-KEY) (hasheq)))))
  "subscriptions/listen missing notifications rejected")

;; image-content missing mimeType -> reject.
(check-exn exn:fail? (lambda ()
  (contract image-content/c (image-content "data" absent absent absent) 'pos 'neg))
  "image-content missing mimeType rejected")

;; cacheable result missing ttlMs -> reject.
(check-exn exn:fail? (lambda ()
  (json->list-tools-result (hasheq 'tools (list) 'cacheScope "public")))
  "list result missing ttlMs rejected")

;; UnsupportedProtocolVersionError with non-list data.supported -> not recognized.
(check-false (unsupported-protocol-version-error?
              (jsonrpc-error-response 1 (jsonrpc-error UNSUPPORTED-PROTOCOL-VERSION "x"
                                                       (hasheq 'supported "not-a-list" 'requested "v"))))
             "UnsupportedProtocolVersionError with non-list supported not recognized")

;; envelope with extra top-level key -> reject (strict).
(check-exn exn:fail? (lambda ()
  (json->jsonrpc-request (hasheq 'jsonrpc "2.0" 'id 1 'method "x" 'extra 1)))
  "strict envelope rejects extra top-level key")

;; 'null / fractional id where request-id required -> reject.
(check-exn exn:fail? (lambda ()
  (contract jsonrpc-request/c (jsonrpc-request 'null "m" absent) 'pos 'neg))
  "request id 'null rejected")
(check-exn exn:fail? (lambda ()
  (contract jsonrpc-request/c (jsonrpc-request 1.5 "m" absent) 'pos 'neg))
  "request id fractional rejected")

;; ========================================================================
;; PART 4 — RC-ONLY-FIELDS PRESENT-AND-PARSED (the distinguishing criterion)
;; ========================================================================

(let* ([req (json->discover-request (read-fx "2026-discover-request.json"))]
       [m (discover-request-meta req)])
  ;; the 5 reserved keys parsed into named fields (none absent, none in rest)
  (check-true (string? (request-meta-protocol-version m)) "reserved: protocolVersion -> string field")
  (check-equal? (request-meta-protocol-version m) "2026-07-28" "protocolVersion value")
  (check-true (implementation? (request-meta-client-info m)) "reserved: clientInfo -> implementation field")
  (check-true (client-capabilities? (request-meta-client-capabilities m)) "reserved: clientCapabilities field")
  (check-true (and (member (request-meta-log-level m) '("debug" "info" "notice" "warning" "error" "critical" "alert" "emergency")) #t)
              "reserved: logLevel -> enum field")
  (check-true (related-task-metadata? (request-meta-related-task m)) "reserved: related-task -> struct field")
  (check-equal? (related-task-metadata-task-id (request-meta-related-task m)) "task-42" "related-task taskId")
  (check-true (present? (request-meta-progress-token m)) "progressToken present (not absent)")
  ;; unreserved key landed in rest, NOT a named field
  (check-true (hash-has-key? (request-meta-rest m) 'com.example/trace) "unreserved key in request-meta rest")
  ;; re-serialized JSON contains the EXACT reserved key strings
  (let ([j (request-meta->json m)])
    (check-true (hash-has-key? j (string->symbol PROTOCOL-VERSION-META-KEY)) "re-emit io.modelcontextprotocol/protocolVersion")
    (check-true (hash-has-key? j (string->symbol CLIENT-INFO-META-KEY)) "re-emit io.modelcontextprotocol/clientInfo")
    (check-true (hash-has-key? j (string->symbol CLIENT-CAPABILITIES-META-KEY)) "re-emit io.modelcontextprotocol/clientCapabilities")
    (check-true (hash-has-key? j (string->symbol LOG-LEVEL-META-KEY)) "re-emit io.modelcontextprotocol/logLevel")
    (check-true (hash-has-key? j (string->symbol RELATED-TASK-META-KEY)) "re-emit io.modelcontextprotocol/related-task"))
  ;; the reserved key strings ARE the constants
  (check-equal? PROTOCOL-VERSION-META-KEY "io.modelcontextprotocol/protocolVersion" "const protocolVersion")
  (check-equal? CLIENT-INFO-META-KEY "io.modelcontextprotocol/clientInfo" "const clientInfo")
  (check-equal? CLIENT-CAPABILITIES-META-KEY "io.modelcontextprotocol/clientCapabilities" "const clientCapabilities")
  (check-equal? LOG-LEVEL-META-KEY "io.modelcontextprotocol/logLevel" "const logLevel")
  (check-equal? RELATED-TASK-META-KEY "io.modelcontextprotocol/related-task" "const related-task"))

;; resultType parsed + re-emitted on a result.
(let ([r (json->discover-result (read-fx "2026-discover-result.json"))])
  (check-equal? (discover-result-result-type r) "complete" "resultType parsed on result")
  (check-true (hash-has-key? (discover-result->json r) 'resultType) "resultType re-emitted"))

;; ttlMs/cacheScope on a list/read result.
(let ([r (json->list-tools-result (read-fx "2026-list-tools-result.json"))])
  (check-equal? (list-tools-result-ttl-ms r) 60000 "ttlMs parsed")
  (check-equal? (list-tools-result-cache-scope r) "public" "cacheScope parsed")
  (let ([j (list-tools-result->json r)])
    (check-true (hash-has-key? j 'ttlMs) "ttlMs re-emitted")
    (check-true (hash-has-key? j 'cacheScope) "cacheScope re-emitted")))

;; inputRequests/requestState on an InputRequiredResult.
(let ([r (json->input-required-result (read-fx "2026-input-required-result.json"))])
  (check-true (present? (input-required-result-input-requests r)) "inputRequests present")
  (check-equal? (input-required-result-request-state r) "opaque-state" "requestState present")
  (let ([j (input-required-result->json r)])
    (check-true (hash-has-key? j 'inputRequests) "inputRequests re-emitted")
    (check-true (hash-has-key? j 'requestState) "requestState re-emitted")))

;; inputResponses/requestState on a request-params (tools/call).
(let ([p (json->call-tool-request-params (hash-ref (read-fx "2026-tools-call-request.json") 'params))])
  (check-true (present? (call-tool-request-params-input-responses p)) "params inputResponses present")
  (check-equal? (call-tool-request-params-request-state p) "opaque-state-blob" "params requestState present"))

;; ========================================================================
;; PART 5 — three-way strictness parity + data-carrying typed errors
;; ========================================================================

;; (a) envelope with extra top-level key -> rejected (asserted in Part 3 too).
(check-exn exn:fail? (lambda ()
  (json->jsonrpc-result-response (hasheq 'jsonrpc "2.0" 'id 1 'result (hasheq) 'extra 1)))
  "strictness (a): envelope extra key rejected")

;; (b) result with an extra inner key -> accepted (and preserved).
(let ([r (json->complete-result (hasheq 'completion (hasheq 'values (list "a"))
                                        'surprise 1 'resultType "complete"))])
  (check-true (complete-result? r) "strictness (b): result extra key accepted")
  (check-true (hash-has-key? (complete-result->json r) 'surprise) "strictness (b): extra key preserved"))

;; (c) concrete params with extra non-_meta key -> accepted but DROPPED.
(let* ([params (hasheq 'name "t" 'extraDropMe 1
                       '_meta (hasheq (string->symbol PROTOCOL-VERSION-META-KEY) "2026-07-28"
                                      (string->symbol CLIENT-INFO-META-KEY) (hasheq 'name "c" 'version "1")
                                      (string->symbol CLIENT-CAPABILITIES-META-KEY) (hasheq)))]
       [p (json->call-tool-request-params params)])
  (check-true (call-tool-request-params? p) "strictness (c): params extra key accepted")
  (check-false (hash-has-key? (call-tool-request-params->json p) 'extraDropMe) "strictness (c): params extra key dropped"))

;; UnsupportedProtocolVersionError (-32004) round-trips with code + data.
(let* ([e (make-unsupported-protocol-version-error 7 (list "2026-07-28") "1999-01-01")]
       [j (jsonrpc-error-response->json e)])
  (check-true (unsupported-protocol-version-error? e) "UnsupportedProtocolVersionError predicate")
  (check-equal? (jsonrpc-error-code (jsonrpc-error-response-error e)) UNSUPPORTED-PROTOCOL-VERSION "code -32004")
  (check-equal? (hash-ref (hash-ref (hash-ref j 'error) 'data) 'requested) "1999-01-01" "data.requested")
  (check-true (list? (hash-ref (hash-ref (hash-ref j 'error) 'data) 'supported)) "data.supported is list")
  ;; round-trip from the fixture
  (let ([from-fx (json->jsonrpc-error-response (read-fx "2026-error-response.json"))])
    (check-true (unsupported-protocol-version-error? from-fx) "fixture is an UnsupportedProtocolVersionError")))

;; MissingRequiredClientCapabilityError (-32003).
(let* ([e (make-missing-required-client-capability-error 8 (client-capabilities (hasheq 'elicitation (hasheq))))]
       [j (jsonrpc-error-response->json e)])
  (check-true (missing-required-client-capability-error? e) "MissingRequiredClientCapabilityError predicate")
  (check-equal? (jsonrpc-error-code (jsonrpc-error-response-error e)) MISSING-REQUIRED-CLIENT-CAPABILITY "code -32003")
  (check-true (hash-has-key? (hash-ref (hash-ref j 'error) 'data) 'requiredCapabilities) "data.requiredCapabilities"))

;; the 5 code-pinned error predicates.
(check-true (parse-error? (jsonrpc-error PARSE-ERROR "x" absent)) "parse-error? predicate")
(check-true (invalid-request-error? (jsonrpc-error INVALID-REQUEST "x" absent)) "invalid-request-error? predicate")
(check-true (method-not-found-error? (jsonrpc-error METHOD-NOT-FOUND "x" absent)) "method-not-found-error? predicate")
(check-true (invalid-params-error? (jsonrpc-error INVALID-PARAMS "x" absent)) "invalid-params-error? predicate")
(check-true (internal-error? (jsonrpc-error INTERNAL-ERROR "x" absent)) "internal-error? predicate")
(check-false (parse-error? (jsonrpc-error INTERNAL-ERROR "x" absent)) "parse-error? rejects other code")

;; ========================================================================
;; Edge cases: absent-vs-null, bare list-roots-result, ListRootsResult shape
;; ========================================================================

;; absent optional must NOT appear as null after round-trip.
(let* ([orig (hash-remove (read-fx "2026-discover-result.json") 'instructions)]
       [rt (discover-result->json (json->discover-result orig))])
  (check-false (hash-has-key? rt 'instructions) "absent instructions omitted (not null)"))

;; ListRootsResult is BARE: exactly {"roots":[...]}, NO _meta/resultType/rest.
(let* ([orig (hasheq 'roots (list (hasheq 'uri "file:///r" 'name "r" '_meta (hasheq 'k 1))))]
       [s (json->list-roots-result orig)]
       [rt (list-roots-result->json s)])
  (check-equal? (hash-keys rt) '(roots) "list-roots-result emits EXACTLY {roots}")
  (check-true (jsexpr=? orig rt) "list-roots-result round-trip incl per-root _meta"))

;; a stray top-level key on list-roots-result is NOT preserved (no rest).
(let* ([orig (hasheq 'roots (list (hasheq 'uri "file:///r")) 'strayKey 1)]
       [rt (list-roots-result->json (json->list-roots-result orig))])
  (check-false (hash-has-key? rt 'strayKey) "list-roots-result has no rest — stray key dropped"))

;; CacheableResult edge: ttlMs:0 valid; cacheScope public AND private round-trip.
(let ([base (lambda (cs) (hasheq 'tools (list) 'ttlMs 0 'cacheScope cs 'resultType "complete"))])
  (check-true (jsexpr=? (base "public") (list-tools-result->json (json->list-tools-result (base "public"))))
              "cacheScope public + ttlMs:0 round-trip")
  (check-true (jsexpr=? (base "private") (list-tools-result->json (json->list-tools-result (base "private"))))
              "cacheScope private round-trip"))

;; stopReason / resultType open enums accept non-standard strings.
(let ([r (json->discover-result (hash-set (read-fx "2026-discover-result.json") 'resultType "custom_type"))])
  (check-equal? (discover-result-result-type r) "custom_type" "open resultType enum accepts custom string"))

;; ========================================================================
;; PART 6 — fixture-INDEPENDENT field-name mapping unit test
;; ========================================================================

;; Build structs with known values; assert serialized hasheq has the EXACT keys.
(let* ([rm (request-meta absent "2026-07-28"
                         (implementation "c" absent "1" absent absent absent)
                         (client-capabilities (hasheq)) "info"
                         (related-task-metadata "t-1") (hasheq))]
       [j (request-meta->json rm)])
  (check-true (hash-has-key? j (string->symbol PROTOCOL-VERSION-META-KEY)) "field-map: protocolVersion key")
  (check-true (hash-has-key? j (string->symbol CLIENT-INFO-META-KEY)) "field-map: clientInfo key")
  (check-true (hash-has-key? j (string->symbol CLIENT-CAPABILITIES-META-KEY)) "field-map: clientCapabilities key")
  (check-true (hash-has-key? j (string->symbol LOG-LEVEL-META-KEY)) "field-map: logLevel key")
  (check-true (hash-has-key? j (string->symbol RELATED-TASK-META-KEY)) "field-map: related-task key"))

;; discover-result field names.
(let* ([r (discover-result (list "v1") (server-capabilities (hasheq)) (implementation "s" absent "1" absent absent absent)
                           absent absent absent (hasheq))]
       [j (discover-result->json r)])
  (check-true (hash-has-key? j 'supportedVersions) "field-map: supportedVersions")
  (check-true (hash-has-key? j 'serverInfo) "field-map: serverInfo"))

;; tool field names ($schema preserved verbatim, inputSchema).
(let* ([t (tool "x" absent absent (hasheq '$schema "S" 'type "object") absent absent absent absent (hasheq))]
       [j (tool->json t)])
  (check-true (hash-has-key? j 'inputSchema) "field-map: inputSchema")
  (check-true (hash-has-key? (hash-ref j 'inputSchema) '$schema) "field-map: $schema kept verbatim"))

;; list-tools-result field names (nextCursor, ttlMs, cacheScope, resultType).
(let* ([r (list-tools-result (list) "c" 10 "private" absent "complete" (hasheq))]
       [j (list-tools-result->json r)])
  (check-true (hash-has-key? j 'nextCursor) "field-map: nextCursor")
  (check-true (hash-has-key? j 'ttlMs) "field-map: ttlMs")
  (check-true (hash-has-key? j 'cacheScope) "field-map: cacheScope")
  (check-true (hash-has-key? j 'resultType) "field-map: resultType"))

;; call-tool-result field names (isError, structuredContent).
(let* ([r (call-tool-result (list) (hasheq 'k 1) #t absent absent (hasheq))]
       [j (call-tool-result->json r)])
  (check-true (hash-has-key? j 'isError) "field-map: isError")
  (check-true (hash-has-key? j 'structuredContent) "field-map: structuredContent"))

;; tool-use-content / tool-result-content field names (toolUseId).
(let ([j (tool-result-content->json (tool-result-content "tu-1" (list) absent absent absent))])
  (check-true (hash-has-key? j 'toolUseId) "field-map: toolUseId"))

;; resource-template uriTemplate.
(let ([j (resource-template->json (resource-template "n" absent "tmpl" absent absent absent absent absent (hasheq)))])
  (check-true (hash-has-key? j 'uriTemplate) "field-map: uriTemplate"))
(let ([j (image-content->json (image-content "d" "image/png" absent absent))])
  (check-true (hash-has-key? j 'mimeType) "field-map: mimeType"))

;; call-tool-request-params inputResponses / requestState field names.
(let* ([p (call-tool-request-params "x" absent (hasheq) "st"
                                    (request-meta absent "2026-07-28"
                                                  (implementation "c" absent "1" absent absent absent)
                                                  (client-capabilities (hasheq)) absent absent (hasheq)))]
       [j (call-tool-request-params->json p)])
  (check-true (hash-has-key? j 'inputResponses) "field-map: inputResponses")
  (check-true (hash-has-key? j 'requestState) "field-map: requestState")
  (check-true (hash-has-key? j '_meta) "field-map: _meta"))

;; Deserialize a hand-built jsexpr with the exact keys -> right fields.
(define (json-expr-object? v) (and (hash? v) (immutable? v) (hash-eq? v)))
(let ([t (json->tool (hasheq 'name "x" 'inputSchema (hasheq 'type "object")
                             'outputSchema (hasheq 'type "object") 'title "T"))])
  (check-equal? (tool-name t) "x" "field-map deser: name")
  (check-true (json-expr-object? (tool-input-schema t)) "field-map deser: inputSchema is object"))

;; ========================================================================
;; PINNED CHECK COUNT
;; ========================================================================
;; This file reports 176 passing checks (raco test). If you ADD/REMOVE a check,
;; update the literal below (drift detector / item-001 precedent).
(printf "spec-2026-07-28-test: pinned check count = 176.\n")
