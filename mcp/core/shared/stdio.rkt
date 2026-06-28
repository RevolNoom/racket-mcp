#lang racket/base

;; Work Item 016 — stdio framing, newline-delimited JSON (M5e).
;;
;; A direct TRANSLITERATION of the MCP TypeScript SDK's
;; `packages/core/src/shared/stdio.ts` `ReadBuffer` class + `serializeMessage`
;; / `deserializeMessage` into Racket. Same framing, same default max-buffer
;; size, same three load-bearing behaviours:
;;
;;   (a) Max-buffer overflow — clear-then-THROW (`>` strict; reusable after).
;;   (b) CRLF tolerance — strip a single trailing \r before parse.
;;   (c) Non-JSON line skip — continue; invalid-*envelope* line THROWS.
;;
;; CRITICAL distinction (c): TS distinguishes `instanceof SyntaxError` (skip)
;; vs any other error (rethrow). Racket port: `read-json` parse failure / eof /
;; trailing-garbage -> skip; parse-success-but-bad-envelope -> raise.
;; Getting this wrong (broad exn:fail? catch around the envelope step) would
;; wrongly SKIP {"not":"a jsonrpc message"} — forbidden.
;;
;; Frame payload: shallow `jsexpr` JSON-RPC envelope (symbol-keyed hasheq),
;; validated by S1 guards (is-jsonrpc-request? / is-jsonrpc-notification? /
;; is-jsonrpc-response?). NOT method-dispatched — revision-agnostic; M7/the
;; engine routes + normalizes after framing.
;;
;; read-message! -> #f on incomplete frame (TS null); a complete message is
;; always a json-object?, so #f is unambiguous (consistent with item 013).
;;
;; Buffer: pure byte manipulation — no real device I/O. M7 (S6a stdio transport)
;; owns the port loop and feeds bytes here. Orphaned until S6a; unit-tested
;; standalone against a synthetic byte stream.

(require json
         "../main.rkt")

(provide
 serialize-message
 deserialize-message
 make-read-buffer
 read-buffer?
 read-buffer-append!
 read-buffer-read-message!
 read-buffer-clear!
 STDIO-DEFAULT-MAX-BUFFER-SIZE)

;; -----------------------------------------------------------------------
;; Constants

;; TS: STDIO_DEFAULT_MAX_BUFFER_SIZE = 10 * 1024 * 1024 (10 MB)
(define STDIO-DEFAULT-MAX-BUFFER-SIZE (* 10 1024 1024))

;; -----------------------------------------------------------------------
;; Internal helpers (NOT provided)

;; jsonrpc-message? : any -> boolean
;; Union of all three JSON-RPC envelope kinds, reusing S1 guards.
(define (jsonrpc-message? v)
  (or (is-jsonrpc-request? v)
      (is-jsonrpc-notification? v)
      (is-jsonrpc-response? v)))

;; strip-trailing-cr : bytes? -> bytes?
;; Remove a single trailing \r (byte 13) — CRLF tolerance, receiver side.
(define (strip-trailing-cr line)
  (define n (bytes-length line))
  (if (and (> n 0) (= (bytes-ref line (sub1 n)) 13))
      (subbytes line 0 (sub1 n))
      line))

;; try-parse-json-line : bytes? -> (values (or/c jsexpr #f) boolean?)
;;
;; Parse `line` as ONE complete JSON value (mirrors TS JSON.parse(line)):
;;   - read-json raises -> parse failure -> (values #f #f)
;;   - read-json returns eof (empty/whitespace-only) -> (values #f #f)
;;   - trailing non-whitespace after the value -> (values #f #f)
;;   - clean whole-value parse -> (values parsed-value #t)
;;
;; The ok? flag (second value) is the SOLE skip decision key. JSON `false`
;; parses to Racket #f — a parse SUCCESS: (values #f #t). A buggy decoder
;; testing the value's truthiness would wrongly SKIP `false`.
;;
;; The envelope check + its raise live OUTSIDE this helper. This confines
;; the parse-failure handler, mirroring TS `instanceof SyntaxError` split.
(define (try-parse-json-line line)
  (define p (open-input-bytes line))
  (define val
    (with-handlers ([exn:fail? (λ (_) 'PARSE-FAIL)])
      (read-json p)))
  (cond
    [(eq? val 'PARSE-FAIL) (values #f #f)]
    [(eof-object? val)     (values #f #f)]
    [else
     ;; Confirm remainder is whitespace-only / EOF (whole-line parse parity
     ;; with JSON.parse — {..}garbage would be rejected, not half-accepted).
     (define rest (read-bytes (expt 2 20) p))  ; read remaining bytes
     (define rest-bytes (if (eof-object? rest) #"" rest))
     (if (regexp-match? #rx#"^[ \t\r\n]*$" rest-bytes)
         (values val #t)
         (values #f #f))]))

;; -----------------------------------------------------------------------
;; Encoder

;; serialize-message : json-object? -> bytes?
;; JSON.stringify(message) + '\n', UTF-8 framed. Does NOT validate the
;; JSON-RPC envelope (trusts its caller, the Protocol layer). Contracted
;; to json-object? so a non-object is caught at the boundary.
(define (serialize-message msg)
  (unless (json-object? msg)
    (raise-argument-error 'serialize-message "json-object?" msg))
  (bytes-append (string->bytes/utf-8 (jsexpr->string msg)) #"\n"))

;; -----------------------------------------------------------------------
;; Decoder convenience (the deserializeMessage analogue)

;; deserialize-message : (or/c bytes? string?) -> json-object?
;; Parse one whole JSON value + envelope-validate. RAISES on BOTH a
;; non-JSON line AND a valid-JSON-but-invalid-envelope line.
;; STANDALONE — read-message! does NOT call this (it needs skip-on-parse-
;; fail semantics; this fn always raises on parse failure).
(define (deserialize-message line)
  (define line-bytes
    (cond
      [(bytes? line)  line]
      [(string? line) (string->bytes/utf-8 line)]
      [else (raise-argument-error 'deserialize-message "(or/c bytes? string?)" line)]))
  ;; Strip trailing \r defensively (liberal on input).
  (define stripped (strip-trailing-cr line-bytes))
  (define-values (val ok?) (try-parse-json-line stripped))
  (unless ok?
    (error 'deserialize-message "not valid JSON: ~e"
           (bytes->string/utf-8 line-bytes (integer->char #\?))))
  (unless (jsonrpc-message? val)
    (error 'deserialize-message "not a valid JSON-RPC message: ~e" val))
  val)

;; -----------------------------------------------------------------------
;; Read buffer (the ReadBuffer analogue)

;; read-buffer struct: mutable bytes field + immutable max-size cap.
(struct read-buffer ([bytes #:mutable] max-size) #:transparent)

;; make-read-buffer : [#:max-buffer-size exact-nonnegative-integer?] -> read-buffer?
(define (make-read-buffer #:max-buffer-size [max-size STDIO-DEFAULT-MAX-BUFFER-SIZE])
  (read-buffer #"" max-size))

;; read-buffer-clear! : read-buffer? -> void
(define (read-buffer-clear! rb)
  (set-read-buffer-bytes! rb #""))

;; read-buffer-append! : read-buffer? bytes? -> void
;; RAISES exn:fail? on overflow (clears before raising — reusable after).
;; Uses `>` (strict), so appending exactly max-size bytes does NOT raise.
(define (read-buffer-append! rb chunk)
  (define new-size (+ (bytes-length (read-buffer-bytes rb)) (bytes-length chunk)))
  (when (> new-size (read-buffer-max-size rb))
    (read-buffer-clear! rb)
    (error 'read-buffer-append!
           "ReadBuffer exceeded maximum size of ~a bytes"
           (read-buffer-max-size rb)))
  (set-read-buffer-bytes! rb (bytes-append (read-buffer-bytes rb) chunk)))

;; read-buffer-read-message! : read-buffer? -> (or/c json-object? #f)
;; #f when no complete frame is buffered (TS null). Skips non-JSON lines.
;; RAISES on a complete valid-JSON-but-invalid-envelope line.
;;
;; try-parse-json-line confines the parse-failure handler. The envelope
;; check + its raise sit OUTSIDE any handler — FORBIDDEN to wrap them in
;; exn:fail?, which would wrongly skip invalid envelopes.
(define (read-buffer-read-message! rb)
  (let loop ()
    (define buf (read-buffer-bytes rb))
    ;; Find first \n byte (10).
    (define idx
      (let scan ([i 0])
        (cond
          [(= i (bytes-length buf)) #f]
          [(= (bytes-ref buf i) 10) i]
          [else (scan (add1 i))])))
    (cond
      [(not idx) #f]   ; no complete frame yet -> #f (TS null)
      [else
       ;; Extract line [0, idx), strip trailing \r, advance buffer past \n.
       (define line (strip-trailing-cr (subbytes buf 0 idx)))
       (set-read-buffer-bytes! rb (subbytes buf (add1 idx)))
       (define-values (val ok?) (try-parse-json-line line))
       (cond
         [(not ok?)              (loop)]          ; parse failure -> SKIP (continue)
         [(jsonrpc-message? val) val]              ; valid envelope -> YIELD
         [else                                    ; parse-ok BUT bad envelope -> RAISE
          (error 'read-buffer-read-message!
                 "not a valid JSON-RPC message: ~e" val)])])))
