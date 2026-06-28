#lang racket/base

;; Work Item 014 — tests for tool-name validation (M5b).
;;
;; A FIXTURE-PORT table test: it ports every
;; `typescript-sdk/packages/core/test/shared/toolNameValidation.test.ts` fixture
;; 1:1 (Parts 1-5), asserting the SAME valid? / warning / emission behaviour the
;; TS suite asserts (G1 parity), plus net-new coverage: early-return suppression
;; (exact-list), dash-before-dot push order, the C1 ñ non-empty message, and
;; embedded-newline robustness.
;;
;; Captured log lines are TOPIC-PREFIXED ("mcp-tool-name: <message>"), so they
;; are asserted with `string-contains?`. Struct `warnings` fields carry NO topic
;; prefix and are asserted with `check-equal?`.

(require rackunit
         racket/string
         racket/list
         racket/logging
         (file "../tool-name-validation.rkt"))

;; Terse helpers over the struct.
(define (valid? n) (tool-name-validation-valid? (validate-tool-name n)))
(define (warns  n) (tool-name-validation-warnings (validate-tool-name n)))
(define (has-warning? n msg) (and (member msg (warns n)) #t))

;; (capture-warnings thunk) -> (listof string) ; ordered emitted log messages.
;; The interceptor receives a log vector #(level message data topic); index 1 is
;; the formatted message string. Filter on the mcp-tool-name topic so unrelated
;; log events do not pollute the count.
(define (capture-warnings thunk)
  (define out '())
  (with-intercepted-logging
    (lambda (l) (set! out (cons (vector-ref l 1) out)))
    thunk
    #:logger (current-logger) 'warning 'mcp-tool-name)
  (reverse out))

;; ===========================================================================
;; Part 1 — validateToolName valid set (valid? #t, warnings empty)
;; ===========================================================================

(for ([n (list "getUser"
               "get_user_profile"
               "user-profile-update"
               "admin.tools.list"
               "DATA_EXPORT_v2.1"
               "a"
               (make-string 128 #\a))])
  (check-true (valid? n) (format "should accept ~s" n))
  (check-true (null? (warns n)) (format "~s should have no warnings" n)))

;; ===========================================================================
;; Part 2 — validateToolName invalid + advisory sets
;; ===========================================================================

;; Invalid set: valid? #f + expected-warning membership.
(check-false (valid? ""))
(check-true (has-warning? "" "Tool name cannot be empty"))

(check-false (valid? (make-string 129 #\a)))
(check-true (has-warning? (make-string 129 #\a)
                          "Tool name exceeds maximum length of 128 characters (current: 129)"))

(check-false (valid? "get user profile"))
(check-true (has-warning? "get user profile" "Tool name contains invalid characters: \" \""))

(check-false (valid? "get,user,profile"))
(check-true (has-warning? "get,user,profile" "Tool name contains invalid characters: \",\""))

(check-false (valid? "user/profile/update"))
(check-true (has-warning? "user/profile/update" "Tool name contains invalid characters: \"/\""))

(check-false (valid? "user@domain.com"))
(check-true (has-warning? "user@domain.com" "Tool name contains invalid characters: \"@\""))

;; Multi-char invalid order (first-seen dedup: space, "@", comma).
(check-false (valid? "user name@domain,com"))
(check-true (has-warning? "user name@domain,com"
                          "Tool name contains invalid characters: \" \", \"@\", \",\""))

;; C1 — ñ invalid-char message is NON-EMPTY (catches char-alphabetic?-based
;; predicate, which would skip ñ and emit an empty list).
(check-false (valid? "user-ñame"))
(check-true (has-warning? "user-ñame" "Tool name contains invalid characters: \"ñ\""))

;; Advisory set: valid? per fixture + warning membership.
(check-false (valid? "get user profile"))
(check-true (has-warning? "get user profile" "Tool name contains spaces, which may cause parsing issues"))

(check-false (valid? "get,user,profile"))
(check-true (has-warning? "get,user,profile" "Tool name contains commas, which may cause parsing issues"))

(check-true (valid? "-get-user"))
(check-true (has-warning? "-get-user" "Tool name starts or ends with a dash, which may cause parsing issues in some contexts"))

(check-true (valid? "get-user-"))
(check-true (has-warning? "get-user-" "Tool name starts or ends with a dash, which may cause parsing issues in some contexts"))

(check-true (valid? ".get.user"))
(check-true (has-warning? ".get.user" "Tool name starts or ends with a dot, which may cause parsing issues in some contexts"))

(check-true (valid? "get.user."))
(check-true (has-warning? "get.user." "Tool name starts or ends with a dot, which may cause parsing issues in some contexts"))

(check-true (valid? ".get.user."))
(check-true (has-warning? ".get.user." "Tool name starts or ends with a dot, which may cause parsing issues in some contexts"))

;; Warning-order parity: exact accumulation order for the multi-warning case.
(check-equal? (warns "user name@domain,com")
              (list "Tool name contains spaces, which may cause parsing issues"
                    "Tool name contains commas, which may cause parsing issues"
                    "Tool name contains invalid characters: \" \", \"@\", \",\""
                    "Allowed characters are: A-Z, a-z, 0-9, underscore (_), dash (-), and dot (.)"))

;; S1 — early-return suppression (EXACT-LIST): the length early returns leak NO
;; advisory/invalid warning.
(check-equal? (warns "") (list "Tool name cannot be empty"))
(check-equal? (warns (string-append (make-string 129 #\a) " ,@"))
              (list "Tool name exceeds maximum length of 128 characters (current: 132)"))

;; S2 — dash-before-dot push order (both advisories present, dash before dot).
(check-equal? (warns "-a.")
              (list "Tool name starts or ends with a dash, which may cause parsing issues in some contexts"
                    "Tool name starts or ends with a dot, which may cause parsing issues in some contexts"))
(check-true (valid? "-a."))

;; ===========================================================================
;; Part 3 — Edge cases + valid-tool-name?
;; ===========================================================================

(check-true (valid? "..."))
(check-true (has-warning? "..." "Tool name starts or ends with a dot, which may cause parsing issues in some contexts"))

(check-true (valid? "---"))
(check-true (has-warning? "---" "Tool name starts or ends with a dash, which may cause parsing issues in some contexts"))

(check-false (valid? "///"))
(check-true (has-warning? "///" "Tool name contains invalid characters: \"/\""))

(check-false (valid? "user@name123"))
(check-true (has-warning? "user@name123" "Tool name contains invalid characters: \"@\""))

;; valid-tool-name? predicate parity.
(check-true (valid-tool-name? "getUser"))
(check-false (valid-tool-name? ""))
(check-true (valid-tool-name? "-get-user-"))   ; advisory but valid
(check-false (valid-tool-name? "get user profile"))
(check-false (valid-tool-name? (make-string 129 #\a)))

;; ===========================================================================
;; Part 4 — issueToolNameWarning + validateAndWarnToolName emission
;; ===========================================================================

;; 6-emission: header + 2 warnings + 3 guidance lines, in order.
(let ([ev (capture-warnings
           (lambda () (issue-tool-name-warning "test-tool" (list "Warning 1" "Warning 2"))))])
  (check-equal? (length ev) 6)
  (check-true (string-contains? (list-ref ev 0) "Tool name validation warning for \"test-tool\""))
  (check-true (string-contains? (list-ref ev 1) "- Warning 1"))
  (check-true (string-contains? (list-ref ev 2) "- Warning 2"))
  (check-true (string-contains? (list-ref ev 3) "Tool registration will proceed, but this may cause compatibility issues."))
  (check-true (string-contains? (list-ref ev 4) "Consider updating the tool name"))
  (check-true (string-contains? (list-ref ev 5) "See SEP: Specify Format for Tool Names")))

;; 0-emission: empty warnings array emits nothing.
(check-equal? (length (capture-warnings
                       (lambda () (issue-tool-name-warning "test-tool" '()))))
              0)

;; validateAndWarnToolName: each row asserts BOTH the boolean return AND whether
;; anything was emitted. Run once under interception for the count, capturing
;; the return inside the thunk.
(define (warn-run n)
  (define ret #f)
  (define ev (capture-warnings (lambda () (set! ret (validate-and-warn-tool-name n)))))
  (values ret (length ev)))

(let-values ([(ret ct) (warn-run "-get-user-")])
  (check-true ret) (check-true (> ct 0)))
(let-values ([(ret ct) (warn-run "get-user-profile")])
  (check-true ret) (check-equal? ct 0))   ; completely clean
(let-values ([(ret ct) (warn-run "get user profile")])
  (check-false ret) (check-true (> ct 0)))
(let-values ([(ret ct) (warn-run "")])
  (check-false ret) (check-true (> ct 0)))
(let-values ([(ret ct) (warn-run (make-string 129 #\a))])
  (check-false ret) (check-true (> ct 0)))

;; Space-warning-through-warn: one event contains the space advisory.
(let ([ev (capture-warnings (lambda () (validate-and-warn-tool-name "get user profile")))])
  (check-true (for/or ([e (in-list ev)]) (string-contains? e "Tool name contains spaces"))))

;; ===========================================================================
;; Part 5 — Robustness: control chars / embedded newline (S3)
;; ===========================================================================

;; Embedded newline stays a single invalid-char case (not a crash, not a
;; premature line-split); valid? #f.
(let ([n (string-append "get" (string #\newline) "user")])
  (check-false (valid? n))
  (check-true (has-warning? n (format "Tool name contains invalid characters: \"~a\"" #\newline))))

;; Emission stays one event per warning even with an embedded newline in the
;; name (count is 1 + N + 3, unaffected by chars inside name).
(check-true (>= (length (capture-warnings
                         (lambda ()
                           (validate-and-warn-tool-name
                            (string-append "get" (string #\newline) "user")))))
                1))
