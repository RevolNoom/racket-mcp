#lang racket/base

;; Work Item 016 — test suite for mcp/core/shared/stdio.rkt
;;
;; Ports every fixture from `typescript-sdk/packages/core/test/shared/stdio.test.ts`
;; 1:1 (G1 parity), plus queue-mandated additions:
;;   - multi-message round-trip + partial-frame buffering (Part 3)
;;   - multibyte UTF-8 boundary split (Part 3)
;;   - all three envelope kinds (Part 7)
;;   - direct deserialize-message cases (Part 1)
;;   - trailing-garbage / whole-line parse (Part 4, Racket-specific vs JSON.parse)
;;   - false/null/scalar RAISE through read-message! (Part 4)
;;   - invalid-UTF-8 skip (Part 4)
;;   - CRLF non-JSON line skip (Part 4)
;;   - buffer size edge cases (Part 6)
;;
;; No external services — byte stream is synthetic (in-memory bytes).
;; Run: raco test mcp/core/shared/test/stdio-test.rkt

(require rackunit
         json
         (file "../stdio.rkt"))

;; -----------------------------------------------------------------------
;; Small helpers

;; The TS testMessage (a notification — the canonical fixture message)
(define m (hasheq 'jsonrpc "2.0" 'method "foobar"))

;; feed : read-buffer? bytes? ... -> read-buffer?
(define (feed rb . chunks)
  (for ([c chunks]) (read-buffer-append! rb c))
  rb)

;; drain : read-buffer? -> (listof json-object?)
;; Collect all complete messages currently buffered, in order.
(define (drain rb)
  (let loop ([acc '()])
    (define msg (read-buffer-read-message! rb))
    (if msg (loop (cons msg acc)) (reverse acc))))

;; -----------------------------------------------------------------------
;; Part 1 — Encoder + deserialize-message

(test-case "STDIO-DEFAULT-MAX-BUFFER-SIZE = 10 MB"
  (check-equal? STDIO-DEFAULT-MAX-BUFFER-SIZE (* 10 1024 1024))
  (check-equal? STDIO-DEFAULT-MAX-BUFFER-SIZE 10485760))

(test-case "serialize-message produces bytes ending in single \\n"
  (define framed (serialize-message m))
  (check-true (bytes? framed))
  ;; ends in \n (byte 10)
  (check-equal? (bytes-ref framed (sub1 (bytes-length framed))) 10)
  ;; NOT \r\n — second-to-last byte is not \r (byte 13)
  (check-not-equal? (bytes-ref framed (- (bytes-length framed) 2)) 13)
  ;; body decodes back to m
  (define body (subbytes framed 0 (sub1 (bytes-length framed))))
  (check-equal? (string->jsexpr (bytes->string/utf-8 body)) m))

(test-case "serialize-message rejects non-json-object? inputs"
  ;; mutable hash
  (check-exn exn:fail:contract?
             (λ () (serialize-message (make-hasheq '((a . 1))))))
  ;; string
  (check-exn exn:fail:contract?
             (λ () (serialize-message "not a hash")))
  ;; list
  (check-exn exn:fail:contract?
             (λ () (serialize-message '(1 2 3)))))

(test-case "deserialize-message valid string input (notification)"
  (check-equal? (deserialize-message "{\"jsonrpc\":\"2.0\",\"method\":\"foobar\"}") m))

(test-case "deserialize-message valid bytes input (result response)"
  (check-equal?
   (deserialize-message #"{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}")
   (hasheq 'jsonrpc "2.0" 'id 1 'result (hasheq))))

(test-case "deserialize-message invalid-envelope raises — not a message"
  (check-exn exn:fail? (λ () (deserialize-message "{\"not\":\"a message\"}"))))

(test-case "deserialize-message invalid-envelope raises — scalar 42"
  (check-exn exn:fail? (λ () (deserialize-message "42"))))

(test-case "deserialize-message invalid-envelope raises — array"
  (check-exn exn:fail? (λ () (deserialize-message "[1,2,3]"))))

(test-case "deserialize-message invalid-envelope raises — null"
  ;; JSON null -> symbol 'null, not a json-object? -> raises
  (check-exn exn:fail? (λ () (deserialize-message "null"))))

(test-case "deserialize-message non-JSON line raises (no buffer to advance)"
  (check-exn exn:fail? (λ () (deserialize-message "Debug: starting")))
  (check-exn exn:fail? (λ () (deserialize-message ""))))

(test-case "deserialize-message raw-preserve — nested unknown keys survive unchanged"
  ;; TS Zod strips unknown nested keys; Racket returns the raw jsexpr intact.
  (define raw (hasheq 'jsonrpc "2.0" 'id 1 'method "x"
                      'params (hasheq 'known 1 'unknownNested 2)))
  (define framed (serialize-message raw))
  (define body (bytes->string/utf-8 (subbytes framed 0 (sub1 (bytes-length framed)))))
  (check-equal? (deserialize-message body) raw))

;; -----------------------------------------------------------------------
;; Part 2 — Read buffer: init, yield-after-newline, reuse (ported)

(test-case "should have no messages after initialization"
  (check-false (read-buffer-read-message! (make-read-buffer))))

(test-case "should only yield a message after a newline"
  (define rb (make-read-buffer))
  ;; Append JSON bytes without newline — still no message
  (read-buffer-append! rb (string->bytes/utf-8 (jsexpr->string m)))
  (check-false (read-buffer-read-message! rb))
  ;; Append the newline — now a message
  (read-buffer-append! rb #"\n")
  (check-equal? (read-buffer-read-message! rb) m)
  ;; No second message
  (check-false (read-buffer-read-message! rb)))

(test-case "should be reusable after clearing"
  (define rb (make-read-buffer))
  (read-buffer-append! rb #"foobar")
  (read-buffer-clear! rb)
  (check-false (read-buffer-read-message! rb))
  ;; Normal message after clear
  (read-buffer-append! rb (serialize-message m))
  (check-equal? (read-buffer-read-message! rb) m))

;; -----------------------------------------------------------------------
;; Part 3 — Multi-message round-trip + partial-frame buffering

(test-case "multi-message round-trip in order"
  (define m1 (hasheq 'jsonrpc "2.0" 'method "method1"))
  (define m2 (hasheq 'jsonrpc "2.0" 'method "method2"))
  (define m3 (hasheq 'jsonrpc "2.0" 'id 1 'method "ping"))
  (define blob (apply bytes-append (map serialize-message (list m1 m2 m3))))
  (define rb (feed (make-read-buffer) blob))
  (check-equal? (drain rb) (list m1 m2 m3))
  (check-false (read-buffer-read-message! rb)))

(test-case "should preserve incomplete JSON at end of buffer until completed"
  (define rb (make-read-buffer))
  (read-buffer-append! rb #"{\"jsonrpc\": \"2.0\", \"method\": \"test\"")
  (check-false (read-buffer-read-message! rb))
  (read-buffer-append! rb #"}\n")
  (check-equal? (read-buffer-read-message! rb)
                (hasheq 'jsonrpc "2.0" 'method "test")))

(test-case "partial frame split across two reads reassembles"
  (define m1 (hasheq 'jsonrpc "2.0" 'method "split-test"))
  (define f (serialize-message m1))
  (define k (quotient (bytes-length f) 2))
  (define rb (make-read-buffer))
  (read-buffer-append! rb (subbytes f 0 k))
  (check-false (read-buffer-read-message! rb))
  (read-buffer-append! rb (subbytes f k))
  (check-equal? (read-buffer-read-message! rb) m1))

(test-case "split INSIDE a multibyte UTF-8 char reassembles correctly"
  (define mu (hasheq 'jsonrpc "2.0" 'method "x"
                     'params (hasheq 'v "é日本語")))
  (define f (serialize-message mu))
  ;; Locate first 0xC3 byte — lead byte of é (UTF-8: C3 A9)
  (define lead
    (for/first ([b (in-bytes f)] [i (in-naturals)]
                #:when (= b #xC3))
      i))
  ;; The lead byte must be present (é is not escaped by jsexpr->string)
  (check-true (and lead #t))
  ;; Split right after the lead byte so é's two bytes span two chunks
  (define split-pt (add1 lead))
  (define rb (make-read-buffer))
  (read-buffer-append! rb (subbytes f 0 split-pt))
  (check-false (read-buffer-read-message! rb))
  (read-buffer-append! rb (subbytes f split-pt))
  (check-equal? (read-buffer-read-message! rb) mu))

(test-case "embedded newline/CR in string value frames as ONE message"
  ;; The framing premise: jsexpr->string escapes raw \n/\r in values.
  (define em (hasheq 'jsonrpc "2.0" 'method "x"
                     'params (hasheq 'text "line1\nline2\rline3")))
  (define f (serialize-message em))
  ;; Exactly one raw byte 10 (the trailing frame \n), zero raw byte 13
  (check-equal? (for/sum ([b (in-bytes f)] #:when (= b 10)) 1) 1)
  (check-equal? (for/sum ([b (in-bytes f)] #:when (= b 13)) 1) 0)
  ;; Round-trip: one message, then #f
  (define rb (feed (make-read-buffer) f))
  (check-equal? (read-buffer-read-message! rb) em)
  (check-false (read-buffer-read-message! rb)))

;; -----------------------------------------------------------------------
;; Part 4 — Non-JSON line filtering (ported, behaviour-(c) suite)

(test-case "should skip empty lines"
  (define rb (make-read-buffer))
  (read-buffer-append! rb (bytes-append #"\n\n" (serialize-message m) #"\n\n"))
  (check-equal? (drain rb) (list m)))

(test-case "should skip non-JSON lines before a valid message"
  (define rb (make-read-buffer))
  (read-buffer-append! rb
    (bytes-append #"Debug: Starting server\n"
                  #"Warning: Something happened\n"
                  (serialize-message m)))
  (check-equal? (drain rb) (list m)))

(test-case "should skip non-JSON lines interleaved with multiple valid messages"
  (define rb (make-read-buffer))
  (define m1 (hasheq 'jsonrpc "2.0" 'method "method1"))
  (define m2 (hasheq 'jsonrpc "2.0" 'method "method2"))
  (read-buffer-append! rb
    (bytes-append #"Debug line 1\n"
                  (serialize-message m1)
                  #"Debug line 2\n"
                  #"Another non-JSON line\n"
                  (serialize-message m2)))
  (check-equal? (drain rb) (list m1 m2)))

(test-case "should skip lines with unbalanced braces"
  (define rb (make-read-buffer))
  (read-buffer-append! rb
    (bytes-append #"{incomplete\n" #"incomplete}\n" (serialize-message m)))
  (check-equal? (drain rb) (list m)))

(test-case "should skip lines that look like JSON but fail to parse"
  (define rb (make-read-buffer))
  (read-buffer-append! rb
    (bytes-append #"{invalidJson: true}\n" (serialize-message m)))
  (check-equal? (drain rb) (list m)))

(test-case "should tolerate leading/trailing whitespace around valid JSON"
  (define rb (make-read-buffer))
  (define msg (hasheq 'jsonrpc "2.0" 'method "test"))
  (read-buffer-append! rb
    (bytes-append #"  " (string->bytes/utf-8 (jsexpr->string msg)) #"  \n"))
  (check-equal? (read-buffer-read-message! rb) msg))

(test-case "whole-line parse / trailing garbage is skipped (JSON.parse parity)"
  ;; {json}garbage is treated as non-JSON (skipped), not half-accepted.
  (define rb (make-read-buffer))
  (define m1 (hasheq 'jsonrpc "2.0" 'method "after-garbage"))
  (read-buffer-append! rb
    (bytes-append (string->bytes/utf-8 (jsexpr->string m)) #"garbage\n"
                  (serialize-message m1)))
  (check-equal? (drain rb) (list m1)))

(test-case "CRITICAL — valid-JSON-but-invalid-envelope RAISES (not skipped)"
  ;; Falsifier for the forbidden broad-exn:fail? catch defect.
  (define rb (make-read-buffer))
  (read-buffer-append! rb
    (bytes-append (string->bytes/utf-8 "{\"not\": \"a jsonrpc message\"}") #"\n"))
  (check-exn exn:fail? (λ () (read-buffer-read-message! rb))))

(test-case "CRITICAL — valid-JSON scalar 42 RAISES through read-message!"
  (check-exn exn:fail?
             (λ () (read-buffer-read-message! (feed (make-read-buffer) #"42\n")))))

(test-case "CRITICAL — valid-JSON scalar true RAISES through read-message!"
  (check-exn exn:fail?
             (λ () (read-buffer-read-message! (feed (make-read-buffer) #"true\n")))))

(test-case "CRITICAL — valid-JSON scalar null RAISES through read-message!"
  ;; read-json returns symbol 'null — a parse SUCCESS that fails the envelope.
  (check-exn exn:fail?
             (λ () (read-buffer-read-message! (feed (make-read-buffer) #"null\n")))))

(test-case "CRITICAL — JSON false RAISES (not skipped) — ok? flag test"
  ;; JSON false -> Racket #f. A buggy decoder testing value truthiness would
  ;; see #f and wrongly SKIP; a correct decoder keys on ok? flag and RAISES.
  (check-exn exn:fail?
             (λ () (read-buffer-read-message! (feed (make-read-buffer) #"false\n")))))

(test-case "CRITICAL — valid-JSON string \"hi\" RAISES through read-message!"
  (check-exn exn:fail?
             (λ () (read-buffer-read-message! (feed (make-read-buffer) #"\"hi\"\n")))))

(test-case "invalid UTF-8 in a complete line is SKIPPED"
  ;; read-json raises on bad bytes -> parse failure -> skip.
  (define rb (make-read-buffer))
  (read-buffer-append! rb (bytes-append (bytes 255 254) #"\n" (serialize-message m)))
  (check-equal? (drain rb) (list m)))

(test-case "non-JSON CRLF line is still skipped after CR strip"
  (define rb (make-read-buffer))
  (read-buffer-append! rb (bytes-append #"Debug line\r\n" (serialize-message m)))
  (check-equal? (drain rb) (list m)))

;; -----------------------------------------------------------------------
;; Part 5 — CRLF tolerance

(test-case "CRLF-framed message decodes identically to LF-framed"
  (define crlf (bytes-append (string->bytes/utf-8 (jsexpr->string m)) #"\r\n"))
  (define rb (feed (make-read-buffer) crlf))
  (check-equal? (read-buffer-read-message! rb) m))

(test-case "multi-message CRLF blob decodes both messages in order"
  (define m1 (hasheq 'jsonrpc "2.0" 'method "crlf1"))
  (define m2 (hasheq 'jsonrpc "2.0" 'method "crlf2"))
  (define crlf-frame
    (λ (msg) (bytes-append (string->bytes/utf-8 (jsexpr->string msg)) #"\r\n")))
  (define rb (feed (make-read-buffer) (crlf-frame m1) (crlf-frame m2)))
  (check-equal? (drain rb) (list m1 m2)))

;; -----------------------------------------------------------------------
;; Part 6 — Buffer size limit (ported)

(test-case "should throw when buffer exceeds default max size"
  ;; Fill to exactly 10 MB in 1 MB chunks (no throw), then the 11th raises.
  (define rb (make-read-buffer))
  (define chunk (make-bytes (* 1024 1024) 0))   ; 1 MB zero bytes (no \n)
  (define fill-count (quotient STDIO-DEFAULT-MAX-BUFFER-SIZE (bytes-length chunk)))
  (for ([_ fill-count]) (read-buffer-append! rb chunk))
  ;; One more -> exceeds 10 MB -> raises
  (check-exn #rx"ReadBuffer exceeded maximum size"
             (λ () (read-buffer-append! rb chunk))))

(test-case "should throw when buffer exceeds custom max size"
  (define rb (make-read-buffer #:max-buffer-size 100))
  (read-buffer-append! rb (make-bytes 50 0))
  (check-exn #rx"ReadBuffer exceeded maximum size"
             (λ () (read-buffer-append! rb (make-bytes 51 0)))))

(test-case "should allow appending up to exactly the max size"
  (check-not-exn
   (λ () (read-buffer-append! (make-read-buffer #:max-buffer-size 100)
                               (make-bytes 100 0)))))

(test-case "single-shot append larger than max throws"
  ;; Empty buffer + 101 > 100 -> raises immediately
  (check-exn #rx"ReadBuffer exceeded maximum size"
             (λ () (read-buffer-append! (make-read-buffer #:max-buffer-size 100)
                                        (make-bytes 101 0)))))

(test-case "max-buffer-size 0 edge — empty append ok, any byte raises"
  (define rb0 (make-read-buffer #:max-buffer-size 0))
  (check-not-exn (λ () (read-buffer-append! rb0 #"")))   ; 0 + 0 = 0, not > 0
  (check-exn #rx"ReadBuffer exceeded maximum size"
             (λ () (read-buffer-append! rb0 #"x"))))      ; 0 + 1 > 0 -> raise

(test-case "empty-chunk append is a no-op"
  (define rb (make-read-buffer #:max-buffer-size 100))
  (read-buffer-append! rb (make-bytes 50 0))
  (check-not-exn (λ () (read-buffer-append! rb #"")))     ; 50 + 0 = 50, ok
  (check-not-exn (λ () (read-buffer-append! rb (make-bytes 50 0)))))  ; 50 + 50 = 100, ok

(test-case "should clear buffer before throwing on overflow (reusable)"
  (define rb (make-read-buffer #:max-buffer-size 100))
  (read-buffer-append! rb (make-bytes 50 0))
  ;; Overflow -> raises
  (check-exn exn:fail? (λ () (read-buffer-append! rb (make-bytes 51 0))))
  ;; Buffer cleared on throw -> can append again
  (check-not-exn (λ () (read-buffer-append! rb (make-bytes 50 0))))
  ;; No newline in zero-byte chunks -> #f
  (check-false (read-buffer-read-message! rb)))

(test-case "should work with no options (backwards compatible)"
  (define rb (make-read-buffer))
  (read-buffer-append! rb (serialize-message (hasheq 'jsonrpc "2.0" 'method "ping")))
  (check-not-false (read-buffer-read-message! rb)))

;; -----------------------------------------------------------------------
;; Part 7 — All three envelope kinds round-trip

(test-case "request round-trips through serialize -> buffer -> read"
  (define req (hasheq 'jsonrpc "2.0" 'id 1 'method "ping"))
  (define rb (feed (make-read-buffer) (serialize-message req)))
  (check-equal? (read-buffer-read-message! rb) req))

(test-case "notification round-trips through serialize -> buffer -> read"
  (define rb (feed (make-read-buffer) (serialize-message m)))
  (check-equal? (read-buffer-read-message! rb) m))

(test-case "result-response round-trips through serialize -> buffer -> read"
  (define res (hasheq 'jsonrpc "2.0" 'id 1 'result (hasheq)))
  (define rb (feed (make-read-buffer) (serialize-message res)))
  (check-equal? (read-buffer-read-message! rb) res))

(test-case "error-response round-trips through serialize -> buffer -> read"
  (define err (hasheq 'jsonrpc "2.0" 'id 1
                      'error (hasheq 'code -32600 'message "bad")))
  (define rb (feed (make-read-buffer) (serialize-message err)))
  (check-equal? (read-buffer-read-message! rb) err))
