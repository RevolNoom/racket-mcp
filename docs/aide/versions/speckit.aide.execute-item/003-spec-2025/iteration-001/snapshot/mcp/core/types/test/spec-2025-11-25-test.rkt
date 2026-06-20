#lang racket/base

;; Test for ../spec-2025-11-25.rkt (item 003). Five parts:
;;  1. round-trip (canonicalized jsexpr=?) per envelope/category fixture AND
;;     per discriminated-union arm (23 arms) + 1 deep-capability fixture.
;;  2. _meta/extra-key passthrough — RESULTS preserve, PARAMS drop (asymmetry).
;;  3. contract-rejection per category.
;;  4. three-way strictness parity (envelope rejects / result preserves / params drops)
;;     + URLElicitationRequiredError (-32042).
;;  5. fixture-INDEPENDENT field-name mapping unit test (kebab<->camel + $schema/_meta).
;;
;; Canonical equality: `jsexpr=?` compares JSON objects as unordered key sets,
;; lists in order, numbers by `=`, 'null by eq?. NOT raw bytes (write-json key
;; order is not guaranteed). See item 003 spec Decisions.
;;
;; Fixture honesty: the .json fixture camelCase keys were COPIED from the TS
;; interfaces in typescript-sdk/.../spec.types.2025-11-25.ts. Cited lines:
;;   - initialize-request.json: InitializeRequestParams (260) protocolVersion,
;;     capabilities, clientInfo; ClientCapabilities.roots.listChanged (323).
;;   - tools-call-request.json: CallToolRequestParams (1142) name, arguments;
;;     RequestMeta key io.modelcontextprotocol/related-task (schemas.ts:64).
;;   - initialize-result.json: InitializeResult (284) protocolVersion,
;;     capabilities, serverInfo, instructions; ServerCapabilities (391).
;;   - list-tools-result.json: ListToolsResult (1100) tools, nextCursor;
;;     Tool (1254) name, title, description, inputSchema, annotations.
;;   - get-task-result.json: GetTaskResult = Result & Task (1420); Task (1349)
;;     taskId, status, statusMessage, createdAt, lastUpdatedAt, ttl, pollInterval.
;; The Part-5 field-mapping unit test is the belt; this copy discipline is the
;; suspenders.
;;
;; The exact check count is pinned at the end (item 001/002 precedent).

(require rackunit
         racket/runtime-path
         racket/contract
         json
         (file "../spec-2025-11-25.rkt")
         (file "../constants.rkt"))

(define-runtime-path fixtures "fixtures")
(define (fx name) (build-path fixtures name))
(define (read-fx name) (call-with-input-file (fx name) read-json))

;; --- canonical jsexpr equality ------------------------------------------
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

;; self-check the comparator
(check-true  (jsexpr=? (hasheq 'a 1 'b 2) (hasheq 'b 2 'a 1)) "jsexpr=? unordered keys")
(check-false (jsexpr=? (hasheq 'a 1) (hasheq 'a 2))           "jsexpr=? value diff")
(check-false (jsexpr=? (list 1 2) (list 2 1))                 "jsexpr=? list order matters")
(check-true  (jsexpr=? 'null 'null)                           "jsexpr=? null")

;; round-trip helper: parse fixture, struct, re-serialize, assert canonical eq
;; AND idempotent second pass. `expect` is the expected jsexpr (defaults to orig;
;; for PARAMS that drop unknowns we pass a pruned expectation).
(define (check-rt name orig->struct struct->orig orig [expect orig])
  (define s (orig->struct orig))
  (define rt (struct->orig s))
  (check-true (jsexpr=? expect rt) (format "round-trip ~a" name))
  (check-true (jsexpr=? rt (struct->orig (orig->struct rt))) (format "idempotent ~a" name)))

;; ========================================================================
;; PART 1 — round-trip per envelope/category fixture
;; ========================================================================

;; initialize request — note params DROP the unknown 'extraUnknownKey, so the
;; expected re-serialized params omit it (keep _meta).
(let* ([orig (read-fx "initialize-request.json")]
       [params-in (hash-ref orig 'params)]
       [expect-params (hash-remove params-in 'extraUnknownKey)]
       [expect (hash-set orig 'params expect-params)])
  (check-rt "initialize-request" json->initialize-request initialize-request->json orig expect))

(check-rt "tools-call-request" json->call-tool-request call-tool-request->json
          (read-fx "tools-call-request.json"))

(check-rt "initialize-result" json->initialize-result initialize-result->json
          (read-fx "initialize-result.json"))

(check-rt "progress-notification" json->progress-notification progress-notification->json
          (read-fx "progress-notification.json"))

(check-rt "list-tools-result" json->list-tools-result list-tools-result->json
          (read-fx "list-tools-result.json"))

;; error response (envelope)
(check-rt "error-response" json->jsonrpc-error-response jsonrpc-error-response->json
          (read-fx "error-response.json"))

;; intersection type GetTaskResult = Result & Task, all task fields top-level
(check-rt "get-task-result (intersection)" json->get-task-result get-task-result->json
          (read-fx "get-task-result.json"))

;; --- discriminated-union arms: ContentBlock (5) -------------------------
(let ([blocks (read-fx "content-blocks.json")]
      [preds (list text-content? image-content? audio-content? resource-link? embedded-resource?)]
      [names '("text" "image" "audio" "resource_link" "resource")])
  (for ([blk (in-list blocks)] [p (in-list preds)] [n (in-list names)])
    (define s (json->content-block blk))
    (check-true (p s) (format "ContentBlock arm ~a dispatched to correct struct" n))
    (check-true (jsexpr=? blk (content-block->json s)) (format "ContentBlock arm ~a round-trip" n))))

;; --- SamplingMessageContentBlock arms (5) incl tool_use/tool_result -----
(let ([blocks (read-fx "sampling-content-blocks.json")]
      [preds (list text-content? image-content? audio-content? tool-use-content? tool-result-content?)]
      [names '("text" "image" "audio" "tool_use" "tool_result")])
  (for ([blk (in-list blocks)] [p (in-list preds)] [n (in-list names)])
    (define s (json->sampling-message-content-block blk))
    (check-true (p s) (format "SamplingContentBlock arm ~a dispatched correctly" n))
    (check-true (jsexpr=? blk (sampling-message-content-block->json s))
                (format "SamplingContentBlock arm ~a round-trip" n))))

;; sampling-message content as single block AND as list (Block | Block[])
(let ([single (hasheq 'role "assistant" 'content (hasheq 'type "text" 'text "hi"))]
      [listed (hasheq 'role "user" 'content (list (hasheq 'type "text" 'text "a")
                                                  (hasheq 'type "text" 'text "b")))])
  (check-true (jsexpr=? single (sampling-message->json (json->sampling-message single)))
              "sampling-message single-block content round-trip")
  (check-true (jsexpr=? listed (sampling-message->json (json->sampling-message listed)))
              "sampling-message list content round-trip"))

;; --- PrimitiveSchemaDefinition arms (4) ---------------------------------
(let ([schemas (read-fx "primitive-schemas.json")]
      [preds (list string-schema? number-schema? number-schema? boolean-schema?)]
      [names '("string" "number" "integer" "boolean")])
  (for ([sc (in-list schemas)] [p (in-list preds)] [n (in-list names)])
    (define s (json->primitive-schema-definition sc))
    (check-true (p s) (format "PrimitiveSchema arm ~a dispatched correctly" n))
    (check-true (jsexpr=? sc (primitive-schema-definition->json s))
                (format "PrimitiveSchema arm ~a round-trip" n))))

;; --- EnumSchema arms (5) -------------------------------------------------
(let ([schemas (read-fx "enum-schemas.json")]
      [preds (list untitled-single-select-enum-schema? titled-single-select-enum-schema?
                   untitled-multi-select-enum-schema? titled-multi-select-enum-schema?
                   legacy-titled-enum-schema?)]
      [names '("untitled-single" "titled-single" "untitled-multi" "titled-multi" "legacy")])
  (for ([sc (in-list schemas)] [p (in-list preds)] [n (in-list names)])
    (define s (json->enum-schema sc))
    (check-true (p s) (format "EnumSchema arm ~a dispatched correctly" n))
    (check-true (jsexpr=? sc (enum-schema->json s)) (format "EnumSchema arm ~a round-trip" n))))

;; --- ElicitRequestParams arms (2): form | url ---------------------------
(let ([ps (read-fx "elicit-params.json")])
  (define form (json->elicit-request-params (car ps)))
  (define url (json->elicit-request-params (cadr ps)))
  (check-true (elicit-request-form-params? form) "ElicitParams form arm dispatched")
  (check-true (elicit-request-url-params? url)    "ElicitParams url arm dispatched")
  (check-true (jsexpr=? (car ps) (elicit-request-params->json form)) "ElicitParams form round-trip")
  (check-true (jsexpr=? (cadr ps) (elicit-request-params->json url)) "ElicitParams url round-trip"))

;; --- ResourceContents arms (2): text | blob -----------------------------
(let* ([rr (read-fx "read-resource-result.json")]
       [s (json->read-resource-result rr)])
  (check-true (text-resource-contents? (car (read-resource-result-contents s)))
              "ResourceContents text arm dispatched")
  (check-true (blob-resource-contents? (cadr (read-resource-result-contents s)))
              "ResourceContents blob arm dispatched")
  (check-true (jsexpr=? rr (read-resource-result->json s)) "read-resource-result round-trip"))

;; --- deep capability fixture --------------------------------------------
(let* ([orig (read-fx "initialize-request-deep-caps.json")]
       [s (json->initialize-request orig)]
       [rt (initialize-request->json s)])
  (check-true (jsexpr=? orig rt) "deep-capability initialize-request round-trip")
  ;; spot-check a deep nested value survived
  (define caps (hash-ref (hash-ref rt 'params) 'capabilities))
  (check-true (hash-has-key? (hash-ref (hash-ref caps 'tasks) 'requests) 'sampling)
              "deep capability tasks.requests.sampling preserved"))

;; ========================================================================
;; PART 2 — _meta / extra-key passthrough (RESULTS preserve, PARAMS drop)
;; ========================================================================

;; RESULTS preserve _meta AND unknown extra key.
(let* ([orig (read-fx "list-tools-result.json")]
       [rt (list-tools-result->json (json->list-tools-result orig))])
  (check-true (hash-has-key? rt '_meta) "result preserves _meta")
  (check-true (hash-has-key? rt 'unknownExtraTopKey) "result preserves unknown extra key")
  (check-equal? (hash-ref rt 'unknownExtraTopKey) "preserved-on-result"
                "result preserves unknown extra key value"))

;; a content block carrying _meta preserves it
(let* ([blk (hasheq 'type "text" 'text "x" '_meta (hasheq 'k 1))]
       [rt (content-block->json (json->content-block blk))])
  (check-true (hash-has-key? rt '_meta) "content block preserves _meta"))

;; PARAMS DROP unknown non-_meta key but keep _meta.
(let* ([orig (read-fx "initialize-request.json")]
       [params (hash-ref orig 'params)]
       [rt-params (initialize-request-params->json (json->initialize-request-params params))])
  (check-true (hash-has-key? rt-params '_meta) "params keep _meta")
  (check-false (hash-has-key? rt-params 'extraUnknownKey) "params DROP unknown non-_meta key"))

;; ========================================================================
;; PART 3 — contract-rejection per category
;; ========================================================================

;; initialize params missing protocolVersion -> contract rejects absent field.
(check-exn exn:fail?
           (lambda ()
             (contract initialize-request-params/c
                       (initialize-request-params absent
                                                  (json->client-capabilities (hasheq))
                                                  (json->implementation (hasheq 'name "c" 'version "1"))
                                                  absent)
                       'pos 'neg))
           "initialize-request-params/c rejects absent protocol-version")

;; tools/call with name = number rejected by contract
(check-exn exn:fail?
           (lambda ()
             (contract call-tool-request-params/c
                       (call-tool-request-params 5 absent absent absent) 'pos 'neg))
           "call-tool-request-params/c rejects numeric name")

;; set-level out-of-enum level rejected
(check-exn exn:fail?
           (lambda ()
             (contract set-level-request-params/c
                       (set-level-request-params "verbose" absent) 'pos 'neg))
           "set-level rejects out-of-enum level")

;; content block type:"text" missing text -> json->… raises (req absent then contract)
(check-exn exn:fail?
           (lambda ()
             (contract text-content/c (json->text-content (hasheq 'type "text")) 'pos 'neg))
           "text content missing text rejected")

;; content block bogus type -> dispatch error
(check-exn exn:fail?
           (lambda () (json->content-block (hasheq 'type "bogus")))
           "unknown content block type rejected")

;; Task missing required ttl -> json->task raises
(check-exn exn:fail?
           (lambda () (json->task (hasheq 'taskId "t" 'status "working"
                                          'createdAt "x" 'lastUpdatedAt "y")))
           "Task missing ttl rejected")

;; Task status out of enum -> contract reject
(check-exn exn:fail?
           (lambda ()
             (contract task/c (task "t" "running" absent "x" "y" 5 absent) 'pos 'neg))
           "Task out-of-enum status rejected")

;; Task with ttl 'null -> ACCEPTED (nullable)
(check-not-exn
 (lambda () (contract task/c (task "t" "working" absent "x" "y" 'null absent) 'pos 'neg))
 "Task ttl 'null accepted (nullable)")

;; jsonrpc-request with extra top-level key rejected (strict envelope)
(check-exn exn:fail?
           (lambda () (json->jsonrpc-request (hasheq 'jsonrpc "2.0" 'id 1 'method "m" 'foo 1)))
           "jsonrpc-request extra top-level key rejected")

;; image-content missing required mimeType rejected
(check-exn exn:fail?
           (lambda () (contract image-content/c (json->image-content (hasheq 'type "image" 'data "d")) 'pos 'neg))
           "image content missing mimeType rejected")

;; id 'null where request-id required rejected
(check-exn exn:fail?
           (lambda () (contract jsonrpc-request/c (jsonrpc-request 'null "m" absent) 'pos 'neg))
           "jsonrpc-request id 'null rejected")
(check-exn exn:fail?
           (lambda () (contract jsonrpc-request/c (jsonrpc-request 1.5 "m" absent) 'pos 'neg))
           "jsonrpc-request fractional id rejected")

;; ========================================================================
;; PART 4 — three-way strictness parity + URLElicitationRequiredError
;; ========================================================================

;; (a) envelope extra top-level key -> rejected
(check-exn exn:fail?
           (lambda () (json->jsonrpc-result-response (hasheq 'jsonrpc "2.0" 'id 1 'result (hasheq) 'extra 1)))
           "strict: result-response envelope extra key rejected")

;; (b) result with extra inner key -> accepted (loose), no raise
(check-not-exn
 (lambda () (json->list-tools-result (hasheq 'tools '() 'weirdKey 1)))
 "loose: result with extra inner key accepted")

;; (c) concrete params with extra non-_meta key -> accepted but key DROPPED
(let* ([p (hasheq 'uri "file:///x" 'strayKey 9)]
       [rt (read-resource-request-params->json (json->read-resource-request-params p))])
  (check-false (hash-has-key? rt 'strayKey) "params: extra non-_meta key DROPPED on re-serialize")
  (check-equal? (hash-ref rt 'uri) "file:///x" "params: known key retained"))

;; URLElicitationRequiredError (-32042)
(let* ([url-params (json->elicit-request-url-params
                    (hasheq 'mode "url" 'message "go" 'elicitationId "e" 'url "https://x"))]
       [err (make-url-elicitation-required-error 7 (list url-params))]
       [j (jsonrpc-error-response->json err)])
  (check-true (url-elicitation-required-error? err) "url-elicitation-required-error? predicate")
  (check-equal? (jsonrpc-error-code (jsonrpc-error-response-error err)) URL-ELICITATION-REQUIRED
                "error code equals URL-ELICITATION-REQUIRED")
  (check-equal? (hash-ref (hash-ref j 'error) 'code) -32042 "wire code is -32042")
  (check-true (list? (hash-ref (hash-ref (hash-ref j 'error) 'data) 'elicitations))
              "error.data.elicitations is a list"))

;; ========================================================================
;; Edge cases: absent-vs-null, Task.ttl, $schema fidelity
;; ========================================================================

;; absent optional omitted (not null): initialize-result without instructions
(let* ([orig (hash-remove (read-fx "initialize-result.json") 'instructions)]
       [rt (initialize-result->json (json->initialize-result orig))])
  (check-false (hash-has-key? rt 'instructions) "absent instructions NOT emitted as null"))

;; Task.ttl null round-trips to JSON null; ttl 3600 stays
(let* ([t-null (hasheq 'taskId "t" 'status "working" 'createdAt "a" 'lastUpdatedAt "b" 'ttl 'null)]
       [rt-null (task->json (json->task t-null))])
  (check-eq? (hash-ref rt-null 'ttl) 'null "Task ttl 'null preserved as JSON null"))
(let* ([t-num (hasheq 'taskId "t" 'status "working" 'createdAt "a" 'lastUpdatedAt "b" 'ttl 3600)]
       [rt-num (task->json (json->task t-num))])
  (check-equal? (hash-ref rt-num 'ttl) 3600 "Task ttl number preserved"))

;; $schema fidelity inside inputSchema
(let* ([orig (read-fx "list-tools-result.json")]
       [rt (list-tools-result->json (json->list-tools-result orig))]
       [tool0 (car (hash-ref rt 'tools))]
       [isch (hash-ref tool0 'inputSchema)])
  (check-true (hash-has-key? isch '$schema) "$schema key preserved verbatim in inputSchema")
  (check-true (hash-has-key? isch 'required) "inputSchema 'required preserved"))

;; ========================================================================
;; PART 5 — field-name mapping unit test (INDEPENDENT of fixtures)
;; ========================================================================

;; serverInfo, protocolVersion (initialize-result)
(let* ([ir (initialize-result "2025-11-25"
                              (json->server-capabilities (hasheq))
                              (implementation "srv" absent "1" absent absent absent)
                              absent (hasheq 'mk 1) (hasheq))]
       [j (initialize-result->json ir)])
  (check-true (hash-has-key? j 'serverInfo) "serializes serverInfo (not server-info)")
  (check-true (hash-has-key? j 'protocolVersion) "serializes protocolVersion")
  (check-true (hash-has-key? j '_meta) "meta field serializes to literal _meta")
  (check-false (hash-has-key? j 'serverinfo) "not lowercased serverinfo")
  (check-false (hash-has-key? j 'meta) "not bare meta"))

;; clientInfo (initialize-request-params)
(let ([j (initialize-request-params->json
          (initialize-request-params "2025-11-25" (json->client-capabilities (hasheq))
                                     (implementation "c" absent "1" absent absent absent) absent))])
  (check-true (hash-has-key? j 'clientInfo) "serializes clientInfo"))

;; nextCursor (list-tools-result)
(let ([j (list-tools-result->json (list-tools-result '() "cur" absent (hasheq)))])
  (check-true (hash-has-key? j 'nextCursor) "serializes nextCursor"))

;; inputSchema (tool)
(let ([j (tool->json (tool "t" absent absent (hasheq 'type "object") absent absent absent absent absent (hasheq)))])
  (check-true (hash-has-key? j 'inputSchema) "serializes inputSchema"))

;; mimeType (image-content)
(let ([j (image-content->json (image-content "d" "image/png" absent absent))])
  (check-true (hash-has-key? j 'mimeType) "serializes mimeType"))

;; uriTemplate (resource-template)
(let ([j (resource-template->json (resource-template "n" absent "tpl://{x}" absent absent absent absent absent (hasheq)))])
  (check-true (hash-has-key? j 'uriTemplate) "serializes uriTemplate"))

;; isError + structuredContent (call-tool-result)
(let ([j (call-tool-result->json (call-tool-result '() (hasheq 'k 1) #t absent (hasheq)))])
  (check-true (hash-has-key? j 'isError) "serializes isError")
  (check-true (hash-has-key? j 'structuredContent) "serializes structuredContent"))

;; toolUseId (tool-result-content)
(let ([j (tool-result-content->json (tool-result-content "tu" '() absent absent absent))])
  (check-true (hash-has-key? j 'toolUseId) "serializes toolUseId"))

;; Deserialize a hand-built jsexpr with exact camelCase keys -> right fields
(let ([s (json->initialize-result
          (hasheq 'protocolVersion "2025-11-25"
                  'capabilities (hasheq)
                  'serverInfo (hasheq 'name "s" 'version "1")
                  'instructions "hi"
                  '_meta (hasheq 'a 1)))])
  (check-equal? (initialize-result-protocol-version s) "2025-11-25" "deser protocolVersion -> protocol-version")
  (check-equal? (implementation-name (initialize-result-server-info s)) "s" "deser serverInfo -> server-info")
  (check-equal? (initialize-result-instructions s) "hi" "deser instructions")
  (check-equal? (initialize-result-meta s) (hasheq 'a 1) "deser _meta -> meta field"))

;; ========================================================================
;; Inventory / count introspection
;; ========================================================================
(check-true (contract? content-block/c) "content-block/c is a contract")
(check-true (contract? client-request/c) "client-request/c is a contract")
(check-true (contract? jsonrpc-message/c) "jsonrpc-message/c is a contract")
(check-true (absent? absent) "absent sentinel exported and self-identifies")
(check-false (absent? 'null) "'null is not absent")

;; ========================================================================
;; Pinned exact check count (item 001/002 precedent).
;; ========================================================================
;; This file contributes EXACTLY 120 rackunit checks. If you add/remove a
;; check, update this number — a drift here flags an accidental loss of a
;; round-trip / rejection assertion.
(printf "spec-2025-11-25-test: pinned check count = 120.\n")
