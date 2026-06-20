#lang racket/base

;; Test for ../types.rkt (item 005) — the N1 normalized-superset façade.
;; Seven parts (Part 0 fixtures + Parts 1–6) per the item spec:
;;   1. the queue's core claim: both revisions normalize to the SAME façade,
;;      with the correct present/absent matrix (RC-only & 2025-only fields).
;;   2. façade is lossless on the home revision (incl. the `rest` field, C4).
;;   3. cross-revision refusal (the N1 wire-parity rule).
;;   4. aggregate unions + revision-parameterized method dispatch (S4).
;;   5. presence-vs-revision-capability.
;;   6. inventory / count report.
;; Run directly: `racket mcp/core/types/test/types-test.rkt` (raco wrapper is
;; broken in this env; silence + exit 0 = pass).

(require rackunit
         racket/runtime-path
         racket/contract
         json
         (file "../types.rkt")
         (prefix-in r25: (file "../spec-2025-11-25.rkt"))
         (prefix-in r26: (file "../spec-2026-07-28.rkt")))

(define-runtime-path fixtures "fixtures")
(define (fx name) (build-path fixtures name))
(define (read-fx name) (call-with-input-file (fx name) read-json))

;; --- canonical jsexpr equality (reused from items 003/004) --------------
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

;; ========================================================================
;; PART 0 — confirm the hand-authored fixtures load (sanity).
;; ========================================================================
(check-true (hash? (read-fx "list-roots-result.json")) "P0 list-roots 2025")
(check-true (hash? (read-fx "2026-list-roots-result.json")) "P0 list-roots 2026")
(check-true (hash? (read-fx "tools-call-request-task.json")) "P0 task-bearing tools/call")
(check-true (hash? (read-fx "tool-with-exec.json")) "P0 tool with execution")
(check-true (hash? (read-fx "2026-tool-no-exec.json")) "P0 2026 tool no execution")
(check-true (hash? (read-fx "elicit-form-params.json")) "P0 elicit form 2025")
(check-true (hash? (read-fx "2026-elicit-form-params.json")) "P0 elicit form 2026")
(check-true (hash? (read-fx "create-message-params.json")) "P0 create-message 2025")
(check-true (hash? (read-fx "2026-create-message-params.json")) "P0 create-message 2026")

;; ========================================================================
;; PART 1 — both revisions normalize to the SAME façade (per primitive).
;; ========================================================================

;; --- tools/call request params -----------------------------------------
;; 2025 (task-bearing); 2026 (inputResponses/requestState/request-meta envelope).
(define cc25
  (normalize-facade-call-tool-request-params-from-2025
   (r25:json->call-tool-request-params (hash-ref (read-fx "tools-call-request-task.json") 'params))))
(define cc26
  (normalize-facade-call-tool-request-params-from-2026
   (r26:json->call-tool-request-params (hash-ref (read-fx "2026-tools-call-request.json") 'params))))

;; same struct type
(check-true (facade-call-tool-request-params? cc25))
(check-true (facade-call-tool-request-params? cc26))
;; RC-only (2026-only) fields: absent on 2025, present on 2026
(check-true (absent? (facade-call-tool-request-params-input-responses cc25)) "input-responses absent 2025")
(check-true (absent? (facade-call-tool-request-params-request-state cc25)) "request-state absent 2025")
(check-true (present? (facade-call-tool-request-params-input-responses cc26)) "input-responses present 2026")
(check-true (present? (facade-call-tool-request-params-request-state cc26)) "request-state present 2026")
;; 2025-only field `task`: present on 2025, absent on 2026
(check-true (present? (facade-call-tool-request-params-task cc25)) "task present 2025")
(check-true (absent? (facade-call-tool-request-params-task cc26)) "task absent 2026")
;; shared field name equal where set
(check-equal? (facade-call-tool-request-params-name cc25) "get_weather")
(check-equal? (facade-call-tool-request-params-name cc26) "calculator")

;; --- meta-field TYPE check (C2/S1): both metas are facade-request-meta ----
(check-true (facade-request-meta? (facade-call-tool-request-params-meta cc26)) "2026 call-tool meta is envelope")
(check-true (facade-request-meta? (facade-call-tool-request-params-meta cc25)) "2025 call-tool meta is also the envelope shape")
;; 2026 reserved fields populated (RC-only on the envelope)
(define m26 (facade-call-tool-request-params-meta cc26))
(check-true (present? (facade-request-meta-protocol-version m26)) "envelope protocol-version present 2026")
(check-true (present? (facade-request-meta-client-info m26)) "envelope client-info present 2026")
(check-true (present? (facade-request-meta-client-capabilities m26)) "envelope client-capabilities present 2026")
;; 2025 envelope reserved fields absent
(define m25 (facade-call-tool-request-params-meta cc25))
(check-true (absent? (facade-request-meta-protocol-version m25)) "envelope protocol-version absent 2025")
(check-true (absent? (facade-request-meta-client-info m25)) "envelope client-info absent 2025")
;; NAMED ASSERTION (team-lead nit #2): a 2025 _meta progressToken lands in the
;; envelope's progress-token field directly.
(check-equal? (facade-request-meta-progress-token m25) "p-7" "2025 _meta progressToken -> facade-request-meta-progress-token")
;; related-task is shared: present on the 2025 envelope (from the flat _meta)
(check-true (present? (facade-request-meta-related-task m25)) "2025 related-task survives into envelope")

;; --- tools/list result --------------------------------------------------
(define lt25 (normalize-facade-list-tools-result-from-2025 (r25:json->list-tools-result (read-fx "list-tools-result.json"))))
(define lt26 (normalize-facade-list-tools-result-from-2026 (r26:json->list-tools-result (read-fx "2026-list-tools-result.json"))))
(check-true (facade-list-tools-result? lt25))
(check-true (facade-list-tools-result? lt26))
;; RC-only fields: absent on 2025, present on 2026
(check-true (absent? (facade-list-tools-result-result-type lt25)) "result-type absent 2025")
(check-true (absent? (facade-list-tools-result-ttl-ms lt25)) "ttl-ms absent 2025")
(check-true (absent? (facade-list-tools-result-cache-scope lt25)) "cache-scope absent 2025")
(check-true (present? (facade-list-tools-result-result-type lt26)) "result-type present 2026")
(check-true (present? (facade-list-tools-result-ttl-ms lt26)) "ttl-ms present 2026")
(check-true (present? (facade-list-tools-result-cache-scope lt26)) "cache-scope present 2026")

;; --- a content block (Group-0 aliasing-trap guard, S5) ------------------
(define tc25 (normalize-facade-content-block-from-2025 (r25:json->content-block (hasheq 'type "text" 'text "hi"))))
(define tc26 (normalize-facade-content-block-from-2026 (r26:json->content-block (hasheq 'type "text" 'text "hi"))))
(check-true (facade-text-content? tc25) "2025-built text-content satisfies facade predicate")
(check-true (facade-text-content? tc26) "2026-built text-content satisfies SAME facade predicate")
(check-equal? (facade-text-content-text tc25) (facade-text-content-text tc26))

;; --- facade-tool execution (2025-only) ----------------------------------
(define tool25 (normalize-facade-tool-from-2025 (r25:json->tool (read-fx "tool-with-exec.json"))))
(define tool26 (normalize-facade-tool-from-2026 (r26:json->tool (read-fx "2026-tool-no-exec.json"))))
(check-true (facade-tool? tool25))
(check-true (facade-tool? tool26))
(check-true (present? (facade-tool-exec tool25)) "tool execution present 2025")
(check-true (absent? (facade-tool-exec tool26)) "tool execution absent 2026")

;; --- list-roots-result (result-level meta 2025-only) --------------------
(define lr25 (normalize-facade-list-roots-result-from-2025 (r25:json->list-roots-result (read-fx "list-roots-result.json"))))
(define lr26 (normalize-facade-list-roots-result-from-2026 (r26:json->list-roots-result (read-fx "2026-list-roots-result.json"))))
(check-true (facade-list-roots-result? lr25))
(check-true (facade-list-roots-result? lr26))
(check-true (present? (facade-list-roots-result-meta lr25)) "list-roots result-meta present 2025")
(check-true (absent? (facade-list-roots-result-meta lr26)) "list-roots result-meta absent 2026")
;; Group-3 nit #1: 2025 carries a result-level `rest`; 2026 does not.
(check-true (present? (facade-list-roots-result-rest lr25)) "list-roots rest present 2025")
(check-true (absent? (facade-list-roots-result-rest lr26)) "list-roots rest absent 2026")

;; --- elicit-request-form-params (BOTH task AND meta 2025-only, C1) -------
(define ef25 (normalize-facade-elicit-request-form-params-from-2025 (r25:json->elicit-request-form-params (read-fx "elicit-form-params.json"))))
(define ef26 (normalize-facade-elicit-request-form-params-from-2026 (r26:json->elicit-request-form-params (read-fx "2026-elicit-form-params.json"))))
(check-true (facade-elicit-request-form-params? ef25))
(check-true (facade-elicit-request-form-params? ef26))
(check-true (present? (facade-elicit-request-form-params-task ef25)) "elicit task present 2025")
(check-true (present? (facade-elicit-request-form-params-meta ef25)) "elicit meta present 2025")
(check-true (absent? (facade-elicit-request-form-params-task ef26)) "elicit task absent 2026")
(check-true (absent? (facade-elicit-request-form-params-meta ef26)) "elicit meta absent 2026")
;; the elicit meta is NOT the request-meta envelope
(check-false (facade-request-meta? (facade-elicit-request-form-params-meta ef25)) "elicit meta is plain, not envelope")

;; --- create-message-request-params (plain meta shared; task 2025-only) ---
(define cm25 (normalize-facade-create-message-request-params-from-2025 (r25:json->create-message-request-params (read-fx "create-message-params.json"))))
(define cm26 (normalize-facade-create-message-request-params-from-2026 (r26:json->create-message-request-params (read-fx "2026-create-message-params.json"))))
(check-true (facade-create-message-request-params? cm25))
(check-true (facade-create-message-request-params? cm26))
(check-true (present? (facade-create-message-request-params-task cm25)) "create-message task present 2025")
(check-true (absent? (facade-create-message-request-params-task cm26)) "create-message task absent 2026")
;; meta is a plain json-object (shared), NOT the request-meta envelope
(check-true (present? (facade-create-message-request-params-meta cm26)) "create-message meta present 2026")
(check-false (facade-request-meta? (facade-create-message-request-params-meta cm26)) "create-message meta is plain, not envelope")
(check-true (json-object? (facade-create-message-request-params-meta cm26)) "create-message meta is a plain json object")

;; ========================================================================
;; PART 2 — façade is lossless on the home revision (no drift), incl. rest.
;; ========================================================================
(define (roundtrip-25-list-tools fxname)
  (r25:list-tools-result->json
   (denormalize-facade-list-tools-result-to-2025
    (normalize-facade-list-tools-result-from-2025
     (r25:json->list-tools-result (read-fx fxname))))))
(define (roundtrip-26-list-tools fxname)
  (r26:list-tools-result->json
   (denormalize-facade-list-tools-result-to-2026
    (normalize-facade-list-tools-result-from-2026
     (r26:json->list-tools-result (read-fx fxname))))))
(check-true (jsexpr=? (read-fx "list-tools-result.json") (roundtrip-25-list-tools "list-tools-result.json")) "P2 2025 list-tools lossless")
(check-true (jsexpr=? (read-fx "2026-list-tools-result.json") (roundtrip-26-list-tools "2026-list-tools-result.json")) "P2 2026 list-tools lossless")

;; request round-trip on home revision
(check-true
 (jsexpr=? (hash-ref (read-fx "tools-call-request-task.json") 'params)
           (r25:call-tool-request-params->json
            (denormalize-facade-call-tool-request-params-to-2025
             (normalize-facade-call-tool-request-params-from-2025
              (r25:json->call-tool-request-params (hash-ref (read-fx "tools-call-request-task.json") 'params))))))
 "P2 2025 call-tool params lossless")
(check-true
 (jsexpr=? (hash-ref (read-fx "2026-tools-call-request.json") 'params)
           (r26:call-tool-request-params->json
            (denormalize-facade-call-tool-request-params-to-2026
             (normalize-facade-call-tool-request-params-from-2026
              (r26:json->call-tool-request-params (hash-ref (read-fx "2026-tools-call-request.json") 'params))))))
 "P2 2026 call-tool params lossless")

;; rest survival: the unknown top-level key AND _meta survive (both revs)
(let ([rt (roundtrip-25-list-tools "list-tools-result.json")])
  (check-true (hash-has-key? rt 'unknownExtraTopKey) "P2 2025 unknown key survives")
  (check-true (hash-has-key? rt '_meta) "P2 2025 _meta survives"))
(let ([rt (roundtrip-26-list-tools "2026-list-tools-result.json")])
  (check-true (hash-has-key? rt 'extraUnknownKey) "P2 2026 unknown key survives")
  (check-true (hash-has-key? rt '_meta) "P2 2026 _meta survives"))

;; rest passes through on CROSS-revision denormalize (C4): a façade list-tools
;; normalized from 2026 but with the named 2026-only fields cleared still keeps
;; rest, and denormalize-to-2025 does NOT raise; the rest keys survive.
(let* ([base (normalize-facade-list-tools-result-from-2026 (r26:json->list-tools-result (read-fx "2026-list-tools-result.json")))]
       [cleared (struct-copy facade-list-tools-result base
                             [ttl-ms absent] [cache-scope absent] [result-type absent])]
       [down (denormalize-facade-list-tools-result-to-2025 cleared)]
       [j (r25:list-tools-result->json down)])
  (check-true (hash-has-key? j 'extraUnknownKey) "P2 C4 cross-revision rest passes through")
  (check-true (hash-has-key? j '_meta) "P2 C4 cross-revision _meta passes through"))

;; empty rest is {} not absent, no phantom keys: a result with only known keys.
(let* ([minimal (hasheq 'tools '() 'nextCursor 'null)]
       ;; build a 2025 list-tools-result from a minimal object (no _meta/unknown)
       [parsed (r25:json->list-tools-result (hasheq 'tools '()))]
       [fac (normalize-facade-list-tools-result-from-2025 parsed)])
  (check-true (hash? (facade-list-tools-result-rest fac)) "P2 S2 empty rest is a hash")
  (check-equal? (hash-count (facade-list-tools-result-rest fac)) 0 "P2 S2 empty rest has zero keys")
  (let ([j (r25:list-tools-result->json (denormalize-facade-list-tools-result-to-2025 fac))])
    (check-false (hash-has-key? j '_meta) "P2 S2 no phantom _meta introduced")))

;; ========================================================================
;; PART 3 — cross-revision refusal (the N1 wire-parity rule).
;; ========================================================================
;; task (2025-only) present -> denormalize-to-2026 raises
(check-exn exn:fail? (λ () (denormalize-facade-call-tool-request-params-to-2026 cc25)) "P3 task refused to-2026")
;; 2026-only named fields present -> denormalize-to-2025 raises
(check-exn exn:fail? (λ () (denormalize-facade-list-tools-result-to-2025 lt26)) "P3 ttl-ms/result-type refused to-2025")
;; tool execution present -> denormalize-to-2026 raises
(check-exn exn:fail? (λ () (denormalize-facade-tool-to-2026 tool25)) "P3 execution refused to-2026")
;; elicit-form task/meta present -> denormalize-to-2026 raises
(check-exn exn:fail? (λ () (denormalize-facade-elicit-request-form-params-to-2026 ef25)) "P3 elicit task/meta refused to-2026")
;; with both absent: emit exactly {mode,message,requestedSchema}
(let ([j (r26:elicit-request-form-params->json (denormalize-facade-elicit-request-form-params-to-2026 ef26))])
  (check-equal? (sort (map symbol->string (hash-keys j)) string<?) '("message" "mode" "requestedSchema") "P3 2026 elicit bare shape"))
;; list-roots result-level meta present -> denormalize-to-2026 raises
(check-exn exn:fail? (λ () (denormalize-facade-list-roots-result-to-2026 lr25)) "P3 list-roots meta refused to-2026")
;; list-roots to-2026 with meta absent emits EXACTLY {roots}
(let ([j (r26:list-roots-result->json (denormalize-facade-list-roots-result-to-2026 lr26))])
  (check-equal? (hash-keys j) '(roots) "P3 2026 list-roots emits exactly {roots}"))
;; a 2025-only standalone primitive: denormalize-to-2026 raises
(let ([init (normalize-facade-initialize-request-params-from-2025
             (r25:json->initialize-request-params (hash-ref (read-fx "initialize-request.json") 'params)))])
  (check-exn exn:fail? (λ () (denormalize-facade-initialize-request-params-to-2026 init)) "P3 initialize refused to-2026"))
;; a 2026-only standalone primitive: denormalize-to-2025 raises
(let ([disc (normalize-facade-discover-request-from-2026 (r26:json->discover-request (read-fx "2026-discover-request.json")))])
  (check-exn exn:fail? (λ () (denormalize-facade-discover-request-to-2025 disc)) "P3 discover refused to-2025"))
;; symmetric pass: a façade with all revision-only fields absent denormalizes
;; to BOTH revisions without raising.
(check-not-exn (λ () (denormalize-facade-elicit-request-form-params-to-2026 ef26)) "P3 all-absent to-2026 ok")
(check-not-exn (λ () (denormalize-facade-elicit-request-form-params-to-2025 ef26)) "P3 all-absent to-2025 ok")

;; ========================================================================
;; PART 4 — aggregate unions + revision-parameterized dispatch (S4).
;; ========================================================================
;; union accepts initialize(2025) + discover(2026) + tools/call(either)
(define init-fac (normalize-facade-initialize-request-params-from-2025
                  (r25:json->initialize-request-params (hash-ref (read-fx "initialize-request.json") 'params))))
(define disc-fac (normalize-facade-discover-request-from-2026 (r26:json->discover-request (read-fx "2026-discover-request.json"))))
(check-true (contract-first-order-passes? facade-client-request/c init-fac) "P4 union accepts initialize")
(check-true (contract-first-order-passes? facade-client-request/c disc-fac) "P4 union accepts discover")
(check-true (contract-first-order-passes? facade-client-request/c cc25) "P4 union accepts tools/call 2025")
(check-true (contract-first-order-passes? facade-client-request/c cc26) "P4 union accepts tools/call 2026")

;; single-revision dispatch resolves only for the home revision.
(check-true (pair? (dispatch-for "initialize" '2025-11-25)) "P4 initialize@2025 resolves")
(check-true (pair? (dispatch-for "server/discover" '2026-07-28)) "P4 discover@2026 resolves")
(check-false (dispatch-for "server/discover" '2025-11-25) "P4 discover@2025 #f")
(check-false (dispatch-for "initialize" '2026-07-28) "P4 initialize@2026 #f")

;; both-revisions dispatch: tools/call resolves to DIFFERENT pairs per revision.
(define d25 (dispatch-for "tools/call" '2025-11-25))
(define d26 (dispatch-for "tools/call" '2026-07-28))
(check-true (pair? d25))
(check-true (pair? d26))
(check-false (eq? (cdr d25) (cdr d26)) "P4 tools/call has TWO different normalizers")
(check-false (eq? (car d25) (car d26)) "P4 tools/call has TWO different parsers")
;; each pair produces the correct revision-shaped façade.
(let* ([parse (car d25)] [norm (cdr d25)]
       [fac (norm (parse (hash-ref (read-fx "tools-call-request-task.json") 'params)))])
  (check-true (present? (facade-call-tool-request-params-task fac)) "P4 2025 dispatch yields task-bearing façade"))
(let* ([parse (car d26)] [norm (cdr d26)]
       [fac (norm (parse (hash-ref (read-fx "2026-tools-call-request.json") 'params)))])
  (check-true (present? (facade-call-tool-request-params-input-responses fac)) "P4 2026 dispatch yields input-responses façade"))
;; one more both-revisions method: roots/list resolves both.
(check-true (pair? (dispatch-for "roots/list" '2025-11-25)) "P4 roots/list@2025 resolves")
(check-true (pair? (dispatch-for "roots/list" '2026-07-28)) "P4 roots/list@2026 resolves")
;; named extraction nit (#2) via dispatch path: 2025 progressToken -> envelope field.
(let* ([d (dispatch-for "tools/call" '2025-11-25)]
       [fac ((cdr d) ((car d) (hash-ref (read-fx "tools-call-request-task.json") 'params)))])
  (check-equal? (facade-request-meta-progress-token (facade-call-tool-request-params-meta fac)) "p-7"
                "P4 dispatch path: 2025 progressToken -> facade-request-meta-progress-token"))

;; ========================================================================
;; PART 5 — presence-vs-revision-capability.
;; A 2026 result that legitimately OMITS result-type normalizes to absent
;; (same as 2025) without crashing; revision identity is NOT inferred.
;; ========================================================================
(let* ([j (hasheq 'tools '() 'ttlMs 1000 'cacheScope "public")] ; 2026 result, no resultType
       [parsed (r26:json->list-tools-result j)]
       [fac (normalize-facade-list-tools-result-from-2026 parsed)])
  (check-true (facade-list-tools-result? fac) "P5 2026-without-result-type normalizes fine")
  (check-true (absent? (facade-list-tools-result-result-type fac)) "P5 omitted result-type is absent (same as 2025)")
  ;; it still denormalizes back to 2026 without claiming it was 2025
  (check-not-exn (λ () (denormalize-facade-list-tools-result-to-2026 fac)) "P5 denormalize-to-2026 ok"))

;; ========================================================================
;; Edge cases:
;; - absent identity: façade absent eq? to 003's/004's absent
;; - optional-absent vs revision-absent are the same sentinel
;; ========================================================================
(check-eq? absent r25:absent "absent eq? to 003's absent")
(check-eq? absent r26:absent "absent eq? to 004's absent")
;; a 2026 message omitting an OPTIONAL shared field (tool.title) yields absent,
;; identical sentinel to a revision-only absent.
(let ([t (normalize-facade-tool-from-2026 (r26:json->tool (hasheq 'name "x" 'inputSchema (hasheq 'type "object"))))])
  (check-eq? (facade-tool-title t) absent "optional-absent == revision-absent (same sentinel)"))

;; ========================================================================
;; PART 6 — inventory / count report (anti-vacuous).
;; ========================================================================
(define facade-predicates
  (list facade-base-metadata? facade-icon? facade-annotations? facade-implementation?
        facade-text-content? facade-image-content? facade-audio-content? facade-resource-link?
        facade-embedded-resource? facade-tool-use-content? facade-tool-result-content?
        facade-text-resource-contents? facade-blob-resource-contents?
        facade-sampling-message? facade-prompt-message? facade-prompt-argument? facade-prompt?
        facade-resource? facade-resource-template? facade-tool-annotations?
        facade-model-hint? facade-model-preferences? facade-tool-choice?
        facade-resource-template-reference? facade-prompt-reference? facade-root?
        facade-tool-execution? facade-tool?
        facade-list-tools-result? facade-call-tool-result? facade-list-resources-result?
        facade-list-resource-templates-result? facade-list-prompts-result? facade-read-resource-result?
        facade-get-prompt-result? facade-complete-result? facade-create-message-result? facade-elicit-result?
        facade-list-roots-result?
        facade-request-meta? facade-call-tool-request-params? facade-read-resource-request-params?
        facade-get-prompt-request-params? facade-complete-request-params?
        facade-create-message-request-params? facade-elicit-request-form-params? facade-elicit-request-url-params?
        facade-cancelled-notification-params? facade-progress-notification-params?
        facade-logging-message-notification-params?
        facade-initialize-request-params? facade-set-level-request-params? facade-subscribe-request-params? facade-task?
        facade-discover-request? facade-discover-result? facade-input-required-result? facade-subscription-filter?))
(define facade-struct-count (length facade-predicates))
(check-equal? facade-struct-count 58 "P6 exactly 58 façade structs (pinned for anti-drift)")
(printf "types-test: façade struct predicates counted = ~a~n" facade-struct-count)

;; pinned check count sentinel.
(printf "types-test: pinned check count = 95.~n")
