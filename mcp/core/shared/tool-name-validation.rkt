#lang racket/base

;; Work Item 014 — Tool-name validation (M5b), per SEP-986
;; ("Specify Format for Tool Names").
;;
;; A near-direct TRANSLITERATION of the MCP TypeScript SDK's
;; `packages/core/src/shared/toolNameValidation.ts` (the three exports
;; `validateToolName` / `issueToolNameWarning` / `validateAndWarnToolName`, the
;; `TOOL_NAME_REGEX`, and the warning + guidance strings) into idiomatic Racket.
;; Same rule, same warning order, same warning strings, same accept/reject set,
;; same emission shape. The only adaptations are Racket data shapes: a struct
;; `(tool-name-validation valid? warnings)` instead of a `{isValid, warnings}`
;; object, kebab-case names, and a module logger instead of `console.warn`.
;; Build target: behaviour parity with the TS results for the ported fixtures
;; (vision goal G1).
;;
;; ---------------------------------------------------------------------------
;; SEP-986 rule:
;;   - Tool names SHOULD be 1-128 characters in length (inclusive).
;;   - Tool names are case-sensitive.
;;   - Allowed characters: A-Z, a-z, 0-9, underscore (_), dash (-), dot (.).
;;     Regex: /^[A-Za-z0-9._-]{1,128}$/.
;;   - Tool names SHOULD NOT contain spaces, commas, or other special
;;     characters (these produce ADVISORY warnings, not validation failures).
;;
;; ---------------------------------------------------------------------------
;; Public surface:
;;   (struct tool-name-validation (valid? warnings) #:transparent)
;;   (validate-tool-name          name)          -> tool-name-validation
;;   (valid-tool-name?            name)          -> boolean?
;;   (issue-tool-name-warning     name warnings) -> void
;;   (validate-and-warn-tool-name name)          -> boolean?
;; Internal helpers (`valid-tool-name-char?`, `collect-invalid-chars`, the
;; logger) are NOT provided.
;;
;; ---------------------------------------------------------------------------
;; `validate-tool-name` logic ORDER is load-bearing (early returns vs.
;; accumulated advisory warnings) and ported VERBATIM:
;;   1. length 0      -> early return (#f (list "Tool name cannot be empty")).
;;   2. length > 128  -> early return (#f (list "...exceeds maximum...(current: N)")).
;;   3. else accumulate ADVISORY warnings (do NOT flip valid?) in this order:
;;      contains space; contains comma; starts/ends with dash; starts/ends with dot.
;;   4. regex test against tool-name-rx:
;;      - FAIL -> push invalid-chars message (first-seen-dedup chars, each as
;;        "x", comma-space joined) + allowed-chars message, return valid? = #f.
;;      - PASS -> return valid? = #t (warnings may be non-empty — an advisory
;;        name like "-get-user-" is valid WITH a dash warning).
;; So valid? is determined SOLELY by the length checks + the regex test; the
;; space/comma/dash/dot warnings are advisory and never flip valid?.
;;
;; ---------------------------------------------------------------------------
;; C1 (CRITICAL) — `valid-tool-name-char?` derives from the SAME ASCII class as
;; `tool-name-rx`. There is ONE source of truth for the allowed set:
;; [A-Za-z0-9._-]. The per-char predicate used to collect the invalid-chars
;; message MUST be derived from that exact class (mirrors TS's per-char
;; /[A-Za-z0-9._-]/.test(char)). Racket's `char-alphabetic?` / `char-numeric?`
;; are Unicode-aware and therefore WRONG here: (char-alphabetic? #\ñ) -> #t and
;; (char-numeric? #\٢) -> #t, which would make `collect-invalid-chars` skip `ñ`
;; and emit an empty invalid-chars message (silently breaking the "ñ" fixture
;; even though valid? stays #f via the ASCII regex). The pass/fail regex and the
;; message predicate MUST agree on the same character set.
;;
;; ---------------------------------------------------------------------------
;; Invalid-char collection — FIRST-SEEN dedup. TS does
;;   [...name].filter(invalid).filter((c,i,arr)=>arr.indexOf(c)===i)
;; (filter invalid chars, then dedup keeping the FIRST occurrence). Racket's
;; `remove-duplicates` over the filtered list does exactly this: it keeps the
;; first occurrence and preserves order. Pinned by `user name@domain,com` ->
;; invalid chars in first-seen order are space, "@", comma.
;;
;; ---------------------------------------------------------------------------
;; Warning emission — `issueToolNameWarning` analogue. Racket has no
;; `console.warn`. We use a MODULE LOGGER via (define-logger mcp-tool-name) and
;; emit each line with `log-mcp-tool-name-warning`. Chosen over `eprintf`
;; because logger output is observably interceptable/testable via
;; `racket/logging`'s `with-intercepted-logging` — exactly how the test asserts
;; the emission count + ordering + content. Each line is ONE log event (TS makes
;; 6 separate console.warn calls; this port makes 6 separate
;; log-mcp-tool-name-warning calls), so an interceptor sees `1 + N + 3` ordered
;; events; empty warnings emit NOTHING.
;;
;; ---------------------------------------------------------------------------
;; No NORMALIZER. The queue entry's word "normalizer" is a misnomer: TS
;; `toolNameValidation.ts` never mutates the name — it validates and warns. The
;; closest analogue is `validate-and-warn-tool-name` (validate + warn + boolean
;; combinator the registration path calls). No name-mutating transform is
;; invented here; one would have no TS counterpart and would break G1 parity.
;;
;; ---------------------------------------------------------------------------
;; Unicode — code POINTS, not code UNITS. Racket strings are code-point
;; sequences: `string-length` counts code points and `string->list` yields one
;; char per code point. TS computes `name.length` in UTF-16 code units (an
;; astral char counts as 2) while iterating `[...name]` yields code points — a
;; known internal TS inconsistency. For the BMP (every char the fixtures use,
;; including ñ = U+00F1) the counts are IDENTICAL to JS, so parity is exact. The
;; astral-plane divergence (Racket more consistent) is a documented, acceptable
;; nuance not exercised by any fixture and not reachable through the
;; [A-Za-z0-9._-] rule.
;;
;; ---------------------------------------------------------------------------
;; Imports — NO S1 binding. Unlike item 013, tool-name validation never raises
;; for a `string?` input — it returns a struct/boolean and emits log warnings.
;; It uses no M1 type and no M2 error, so it does NOT require "../main.rkt". It
;; requires only `racket/string` + `racket/list` (+ `racket/base`) — all
;; portable, non-I/O. It MUST NOT require any transport/engine/role/subprocess/
;; socket module, nor net/*, racket/system, racket/tcp/udp, racket/sandbox, or
;; racket/port. (The transitive restricted-load proof is item 017's
;; collection-wide sweep — not duplicated here.)
;;
;; Input domain = `string?` (option (a): document, do not coerce). The
;; "never raises" guarantee holds ONLY for string inputs. A non-string input
;; (e.g. (validate-tool-name 42)) raises a `string-length`/`string->list`
;; contract error from the base ops — that is a caller contract violation, NOT a
;; graceful valid? = #f result. This matches TS, where `name: string` is the
;; static type and a non-string is a type error, not a runtime branch.

(require racket/string
         racket/list)

(provide (struct-out tool-name-validation)
         validate-tool-name
         valid-tool-name?
         issue-tool-name-warning
         validate-and-warn-tool-name)

;; SEP-986 length bound + conformance regex (the single source of truth for the
;; allowed character class).
(define MAX-TOOL-NAME-LENGTH 128)
(define tool-name-rx #px"^[A-Za-z0-9._-]{1,128}$")

;; Module logger — emission is interceptable via racket/logging for testing.
(define-logger mcp-tool-name)

;; Validation result. valid? : boolean?, warnings : (listof string?).
(struct tool-name-validation (valid? warnings) #:transparent)

;; Per-char predicate derived from the SAME ASCII class as `tool-name-rx`
;; (mirrors TS's per-char /[A-Za-z0-9._-]/.test(char)). NOT char-alphabetic?/
;; char-numeric? (Unicode-aware — see C1 above).
(define (valid-tool-name-char? c)
  (and (regexp-match? #px"[A-Za-z0-9._-]" (string c)) #t))

;; Invalid chars in first-seen order, deduplicated (remove-duplicates keeps the
;; first occurrence and preserves order — matches TS's filter+indexOf dedup).
(define (collect-invalid-chars name)
  (remove-duplicates
   (filter (lambda (c) (not (valid-tool-name-char? c)))
           (string->list name))))

;; (validate-tool-name name) -> tool-name-validation
;; name domain = string?. Logic order ported verbatim from TS validateToolName.
(define (validate-tool-name name)
  (define len (string-length name))
  (cond
    ;; 1. Empty -> early return (no advisory accumulation).
    [(= len 0)
     (tool-name-validation #f (list "Tool name cannot be empty"))]
    ;; 2. Over length -> early return (fires BEFORE any advisory accumulation).
    [(> len MAX-TOOL-NAME-LENGTH)
     (tool-name-validation
      #f
      (list (format "Tool name exceeds maximum length of 128 characters (current: ~a)" len)))]
    [else
     ;; 3. Accumulate advisory warnings in order (these do NOT flip valid?).
     (define warnings '())
     (when (string-contains? name " ")
       (set! warnings (cons "Tool name contains spaces, which may cause parsing issues" warnings)))
     (when (string-contains? name ",")
       (set! warnings (cons "Tool name contains commas, which may cause parsing issues" warnings)))
     (when (or (string-prefix? name "-") (string-suffix? name "-"))
       (set! warnings (cons "Tool name starts or ends with a dash, which may cause parsing issues in some contexts" warnings)))
     (when (or (string-prefix? name ".") (string-suffix? name "."))
       (set! warnings (cons "Tool name starts or ends with a dot, which may cause parsing issues in some contexts" warnings)))
     ;; 4. Regex test decides valid?; on fail, append the two invalid-char msgs.
     (cond
       [(not (regexp-match? tool-name-rx name))
        (define joined
          (string-join (map (lambda (c) (format "\"~a\"" c))
                            (collect-invalid-chars name))
                       ", "))
        (set! warnings (cons (format "Tool name contains invalid characters: ~a" joined) warnings))
        (set! warnings (cons "Allowed characters are: A-Z, a-z, 0-9, underscore (_), dash (-), and dot (.)" warnings))
        (tool-name-validation #f (reverse warnings))]
       [else
        (tool-name-validation #t (reverse warnings))])]))

;; (valid-tool-name? name) -> boolean? — terse accept/reject predicate.
(define (valid-tool-name? name)
  (tool-name-validation-valid? (validate-tool-name name)))

;; (issue-tool-name-warning name warnings) -> void
;; Emits header + each warning + 3 fixed guidance lines via the module logger
;; (one event per line); empty warnings emit NOTHING.
(define (issue-tool-name-warning name warnings)
  (when (pair? warnings)
    (log-mcp-tool-name-warning (format "Tool name validation warning for \"~a\":" name))
    (for ([w (in-list warnings)])
      (log-mcp-tool-name-warning (format "  - ~a" w)))
    (log-mcp-tool-name-warning "Tool registration will proceed, but this may cause compatibility issues.")
    (log-mcp-tool-name-warning "Consider updating the tool name to conform to the MCP tool naming standard.")
    (log-mcp-tool-name-warning "See SEP: Specify Format for Tool Names (https://github.com/modelcontextprotocol/modelcontextprotocol/issues/986) for more details.")))

;; (validate-and-warn-tool-name name) -> boolean?
;; Validate, ALWAYS issue warnings (so both invalid AND advisory-valid names
;; emit; a completely clean name emits nothing via the empty-warnings no-op),
;; return valid?.
(define (validate-and-warn-tool-name name)
  (define result (validate-tool-name name))
  (issue-tool-name-warning name (tool-name-validation-warnings result))
  (tool-name-validation-valid? result))
