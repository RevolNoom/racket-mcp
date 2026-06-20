#lang racket/base

;; Byte-for-byte parity test against the live TypeScript SDK checkout.
;; This is a true upstream-drift detector: it READS the actual .ts source
;; files at test time and compares the extracted values to the Racket
;; bindings in ../constants.rkt. It is NOT a self-consistency test.

(require rackunit
         racket/file
         racket/string
         racket/list
         racket/runtime-path
         (file "../constants.rkt"))

;; --- TS checkout paths, anchored to THIS source file (cwd-robust) ---
;; This file lives at <repo>/mcp/core/types/test/constants-test.rkt, so the
;; repo root is four directories up.  define-runtime-path resolves relative
;; to the source location regardless of the invoking working directory.
(define-runtime-path ts-constants-path
  "../../../../typescript-sdk/packages/core/src/types/constants.ts")
(define-runtime-path ts-enums-path
  "../../../../typescript-sdk/packages/core/src/types/enums.ts")

;; --- checkout guard: a missing/unreadable file is a HARD failure ---
(define (read-ts-source path label)
  (unless (file-exists? path)
    (fail (format "TS checkout file missing: ~a (~a). The parity test requires the typescript-sdk/ checkout at the repo root." path label)))
  (with-handlers ([exn:fail? (lambda (e)
                               (fail (format "TS checkout file unreadable: ~a (~a): ~a"
                                             path label (exn-message e))))])
    (file->string path)))

(define constants-src (read-ts-source ts-constants-path "constants.ts"))
(define enums-src (read-ts-source ts-enums-path "enums.ts"))

;; --- extractors -----------------------------------------------------------

;; Strip TS underscore-grouping (`-32_700` -> `-32700`) and parse to integer.
(define (parse-ts-int s)
  (string->number (string-replace s "_" "")))

;; Integer assigned to an `export const NAME = ...` in constants.ts.
;; Numeric capture tolerates the trailing `;`.
(define (ts-const-int src name where)
  (define m (regexp-match
             (pregexp (string-append "export const " (regexp-quote name)
                                     "\\s*=\\s*(-?[0-9_]+)"))
             src))
  (unless m
    (fail (format "constant `~a` not found in ~a (TS rename or drift?)" name where)))
  (define n (parse-ts-int (cadr m)))
  (unless (exact-integer? n)
    (fail (format "constant `~a` in ~a did not parse to an integer: ~s" name where (cadr m))))
  n)

;; Integer assigned to an enum member `^  Name = -32_700,` in enums.ts.
;; Anchored on `^\s*Name\s*=` (word-boundary, case-sensitive) so it never
;; matches the name appearing inside doc-comment prose.  The numeric capture
;; tolerates an OPTIONAL trailing comma / end-of-line, so the last member
;; (`UrlElicitationRequired = -32_042` with NO trailing comma) is not dropped.
(define (ts-enum-int src name where)
  (define m (regexp-match
             (pregexp (string-append "(?m:^\\s*" (regexp-quote name)
                                     "\\s*=\\s*(-?[0-9_]+)\\s*(?:,|$))"))
             src))
  (unless m
    (fail (format "enum member `~a` not found in ~a (TS rename or drift?)" name where)))
  (define n (parse-ts-int (cadr m)))
  (unless (exact-integer? n)
    (fail (format "enum member `~a` in ~a did not parse to an integer: ~s" name where (cadr m))))
  n)

;; String assigned to an `export const NAME = '...'` (single or double quoted)
;; in constants.ts.  Anchored on `export const <NAME> =` so for
;; LATEST_PROTOCOL_VERSION (which also appears as a bareword inside the
;; SUPPORTED array) we capture the DEFINITION, not the array reference.
(define (ts-const-string src name where)
  (define m (regexp-match
             (pregexp (string-append "export const " (regexp-quote name)
                                     "\\s*=\\s*['\"]([^'\"]*)['\"]"))
             src))
  (unless m
    (fail (format "string constant `~a` not found in ~a (TS rename or drift?)" name where)))
  (cadr m))

;; The SUPPORTED_PROTOCOL_VERSIONS array literal, resolved to a list of five
;; strings.  The leading bareword `LATEST_PROTOCOL_VERSION` reference is
;; resolved to its string value so the result has 5 entries, not 4.
(define (ts-supported-list src where)
  (define m (regexp-match
             (pregexp (string-append "export const SUPPORTED_PROTOCOL_VERSIONS"
                                     "\\s*=\\s*\\[([^\\]]*)\\]"))
             src))
  (unless m
    (fail (format "SUPPORTED_PROTOCOL_VERSIONS array not found in ~a" where)))
  (define raw-elems (map string-trim (string-split (cadr m) ",")))
  (define latest (ts-const-string src "LATEST_PROTOCOL_VERSION" where))
  (for/list ([e (in-list raw-elems)])
    (cond
      [(string=? e "LATEST_PROTOCOL_VERSION") latest]
      [else
       (define sm (regexp-match #rx"^['\"]([^'\"]*)['\"]$" e))
       (unless sm
         (fail (format "SUPPORTED_PROTOCOL_VERSIONS element not a resolvable string in ~a: ~s" where e)))
       (cadr sm)])))

;; --- regression: underscore-literal normalization ------------------------
(check-equal? (ts-enum-int enums-src "ParseError" "enums.ts") -32700
              "underscore-literal normalization: -32_700 must read as -32700")

;; --- standard error codes from constants.ts ------------------------------
(check-equal? (ts-const-int constants-src "PARSE_ERROR" "constants.ts") PARSE-ERROR
              "PARSE_ERROR (constants.ts) vs PARSE-ERROR")
(check-equal? (ts-const-int constants-src "INVALID_REQUEST" "constants.ts") INVALID-REQUEST
              "INVALID_REQUEST (constants.ts) vs INVALID-REQUEST")
(check-equal? (ts-const-int constants-src "METHOD_NOT_FOUND" "constants.ts") METHOD-NOT-FOUND
              "METHOD_NOT_FOUND (constants.ts) vs METHOD-NOT-FOUND")
(check-equal? (ts-const-int constants-src "INVALID_PARAMS" "constants.ts") INVALID-PARAMS
              "INVALID_PARAMS (constants.ts) vs INVALID-PARAMS")
(check-equal? (ts-const-int constants-src "INTERNAL_ERROR" "constants.ts") INTERNAL-ERROR
              "INTERNAL_ERROR (constants.ts) vs INTERNAL-ERROR")

;; --- standard error codes ALSO from enums.ts (both files must agree) ------
(check-equal? (ts-enum-int enums-src "ParseError" "enums.ts") PARSE-ERROR
              "ParseError (enums.ts) vs PARSE-ERROR")
(check-equal? (ts-enum-int enums-src "InvalidRequest" "enums.ts") INVALID-REQUEST
              "InvalidRequest (enums.ts) vs INVALID-REQUEST")
(check-equal? (ts-enum-int enums-src "MethodNotFound" "enums.ts") METHOD-NOT-FOUND
              "MethodNotFound (enums.ts) vs METHOD-NOT-FOUND")
(check-equal? (ts-enum-int enums-src "InvalidParams" "enums.ts") INVALID-PARAMS
              "InvalidParams (enums.ts) vs INVALID-PARAMS")
(check-equal? (ts-enum-int enums-src "InternalError" "enums.ts") INTERNAL-ERROR
              "InternalError (enums.ts) vs INTERNAL-ERROR")

;; --- MCP-specific error codes from enums.ts only --------------------------
(check-equal? (ts-enum-int enums-src "ResourceNotFound" "enums.ts") RESOURCE-NOT-FOUND
              "ResourceNotFound (enums.ts) vs RESOURCE-NOT-FOUND")
(check-equal? (ts-enum-int enums-src "MissingRequiredClientCapability" "enums.ts")
              MISSING-REQUIRED-CLIENT-CAPABILITY
              "MissingRequiredClientCapability (enums.ts) vs MISSING-REQUIRED-CLIENT-CAPABILITY")
(check-equal? (ts-enum-int enums-src "UnsupportedProtocolVersion" "enums.ts")
              UNSUPPORTED-PROTOCOL-VERSION
              "UnsupportedProtocolVersion (enums.ts) vs UNSUPPORTED-PROTOCOL-VERSION")
(check-equal? (ts-enum-int enums-src "UrlElicitationRequired" "enums.ts")
              URL-ELICITATION-REQUIRED
              "UrlElicitationRequired (enums.ts, last member, no trailing comma) vs URL-ELICITATION-REQUIRED")

;; --- version + JSON-RPC constants from constants.ts -----------------------
(check-equal? (ts-const-string constants-src "LATEST_PROTOCOL_VERSION" "constants.ts")
              LATEST-PROTOCOL-VERSION
              "LATEST_PROTOCOL_VERSION (constants.ts) vs LATEST-PROTOCOL-VERSION")
(check-equal? (ts-const-string constants-src "DEFAULT_NEGOTIATED_PROTOCOL_VERSION" "constants.ts")
              DEFAULT-NEGOTIATED-PROTOCOL-VERSION
              "DEFAULT_NEGOTIATED_PROTOCOL_VERSION (constants.ts) vs DEFAULT-NEGOTIATED-PROTOCOL-VERSION")
(check-equal? (ts-supported-list constants-src "constants.ts") SUPPORTED-PROTOCOL-VERSIONS
              "SUPPORTED_PROTOCOL_VERSIONS (constants.ts, ordered, resolved) vs SUPPORTED-PROTOCOL-VERSIONS")
(check-equal? (ts-const-string constants-src "JSONRPC_VERSION" "constants.ts")
              JSONRPC-VERSION
              "JSONRPC_VERSION (constants.ts) vs JSONRPC-VERSION")

;; --- structural self-checks (secondary) -----------------------------------
(check-equal? (length SUPPORTED-PROTOCOL-VERSIONS) 5
              "SUPPORTED-PROTOCOL-VERSIONS has exactly 5 entries")
(check-equal? (car SUPPORTED-PROTOCOL-VERSIONS) LATEST-PROTOCOL-VERSION
              "SUPPORTED-PROTOCOL-VERSIONS head is LATEST-PROTOCOL-VERSION (splice integrity)")
(check-true (for/and ([c (in-list (list PARSE-ERROR INVALID-REQUEST METHOD-NOT-FOUND
                                        INVALID-PARAMS INTERNAL-ERROR RESOURCE-NOT-FOUND
                                        MISSING-REQUIRED-CLIENT-CAPABILITY
                                        UNSUPPORTED-PROTOCOL-VERSION URL-ELICITATION-REQUIRED))])
              (and (exact-integer? c) (negative? c)))
            "all nine error codes are negative exact integers")
