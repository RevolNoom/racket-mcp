#lang racket/base

;; Pure-data constants mirroring the MCP TypeScript SDK's
;; `core/src/types/constants.ts` and `core/src/types/enums.ts`.
;; This module is the bottom of the dependency graph: it requires nothing
;; beyond racket/base (Portability NFR) and contains no I/O.

(provide
 ;; protocol versions
 LATEST-PROTOCOL-VERSION
 DEFAULT-NEGOTIATED-PROTOCOL-VERSION
 SUPPORTED-PROTOCOL-VERSIONS
 ;; JSON-RPC
 JSONRPC-VERSION
 ;; standard JSON-RPC error codes
 PARSE-ERROR
 INVALID-REQUEST
 METHOD-NOT-FOUND
 INVALID-PARAMS
 INTERNAL-ERROR
 ;; MCP-specific error codes
 RESOURCE-NOT-FOUND
 MISSING-REQUIRED-CLIENT-CAPABILITY
 UNSUPPORTED-PROTOCOL-VERSION
 URL-ELICITATION-REQUIRED
 ;; reserved `_meta` keys for the per-request envelope (revision 2026-07-28)
 PROTOCOL-VERSION-META-KEY
 CLIENT-INFO-META-KEY
 CLIENT-CAPABILITIES-META-KEY
 LOG-LEVEL-META-KEY
 RELATED-TASK-META-KEY)

;; --- protocol versions ---
(define LATEST-PROTOCOL-VERSION "2025-11-25")
(define DEFAULT-NEGOTIATED-PROTOCOL-VERSION "2025-03-26")
;; Head spliced by reference, mirroring the TS array literal, so a bump to
;; LATEST-PROTOCOL-VERSION keeps the list head in sync.
(define SUPPORTED-PROTOCOL-VERSIONS
  (list LATEST-PROTOCOL-VERSION "2025-06-18" "2025-03-26" "2024-11-05" "2024-10-07"))

;; --- JSON-RPC ---
(define JSONRPC-VERSION "2.0")

;; --- standard JSON-RPC error codes ---
(define PARSE-ERROR -32700)
(define INVALID-REQUEST -32600)
(define METHOD-NOT-FOUND -32601)
(define INVALID-PARAMS -32602)
(define INTERNAL-ERROR -32603)

;; --- MCP-specific error codes ---
(define RESOURCE-NOT-FOUND -32002)
(define MISSING-REQUIRED-CLIENT-CAPABILITY -32003)
(define UNSUPPORTED-PROTOCOL-VERSION -32004)
(define URL-ELICITATION-REQUIRED -32042)

;; --- reserved `_meta` keys (revision 2026-07-28, SEP-2577) ---
;; Verbatim from constants.ts (lines 5/14/19/27/38). The per-request `_meta`
;; envelope carries version negotiation and per-request client identity here.
(define RELATED-TASK-META-KEY "io.modelcontextprotocol/related-task")
(define PROTOCOL-VERSION-META-KEY "io.modelcontextprotocol/protocolVersion")
(define CLIENT-INFO-META-KEY "io.modelcontextprotocol/clientInfo")
(define CLIENT-CAPABILITIES-META-KEY "io.modelcontextprotocol/clientCapabilities")
(define LOG-LEVEL-META-KEY "io.modelcontextprotocol/logLevel") ; deprecated
