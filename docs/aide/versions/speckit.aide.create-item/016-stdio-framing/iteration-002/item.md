# Work Item 016: stdio framing — newline-delimited JSON (M5e, orphaned until S6a)

> **Queue:** `docs/aide/queue/queue-002.md` — Item 016
> **Stage:** S2 (Foundation: validators, schema, shared utilities — L0 part 2)
> **Module:** **M5e** (stdio framing) — `mcp/core/shared/stdio.rkt`. Newline-delimited JSON **frame encode/decode over a byte stream**, mirroring TS `stdio.ts` (its `ReadBuffer` class + `serializeMessage`/`deserializeMessage`). This is the **last** M5 shared-util module and the **only** M5 module concerned with byte-stream framing. It has **NO consumer inside S2** — its first real consumer is the **stdio transport (M7) in S6a**; it is built now for L0 cohesion (architecture groups it under M5) and **unit-tested standalone** against a synthetic byte stream, with integration coverage arriving alongside M7.
> **Source vision:** `docs/aide/vision.md` §6 (Portability NFR — core L0–L2 loads without subprocess/socket; the buffer is pure byte/bytes manipulation, NOT real device I/O), G1 (wire/behaviour parity with the TS SDK — the framing, the CRLF tolerance, the non-JSON-line skip, and the max-buffer DoS guard must match TS `ReadBuffer`).
> **Source roadmap:** `docs/aide/roadmap.md` Stage S2 → Deliverables (`mcp/core/shared/stdio.rkt` (M5e) — newline-delimited JSON framing) + Testing/validation criterion (`stdio framing (M5e) round-trips multi-message + partial-frame buffering, standalone`).
> **Source architecture:** `docs/aide/architecture.md` M5e (shared util; depends on S1 only), §1.3 (public/internal boundary, explicit `provide`), §4.1 (Runtime-neutral core L0–L2 import no subprocess/socket).
> **Reference impl (authoritative):** MCP TypeScript SDK v2 at `typescript-sdk/`:
>   - `packages/core/src/shared/stdio.ts` — the `ReadBuffer` class (`append` / `readMessage` / `clear`), `STDIO_DEFAULT_MAX_BUFFER_SIZE = 10 * 1024 * 1024`, `serializeMessage`, `deserializeMessage`. **Transliterate its behaviour.**
>   - `packages/core/test/shared/stdio.test.ts` — the fixture suite this item ports 1:1.
> **Source (S1):** `mcp/core/types/guards.rkt` — the shallow JSON-RPC envelope predicates `is-jsonrpc-request?` / `is-jsonrpc-notification?` / `is-jsonrpc-response?` (the `JSONRPCMessageSchema.parse` analogue; see "The `deserializeMessage` analogue" below). `mcp/core/main.rkt` — the S1 barrel (re-exports the guards + the errors M2 for raising). `mcp/core/types/constants.rkt` — `JSONRPC-VERSION` (`"2.0"`).
> **Status:** 📋 Not started — spec ready for `execute-item`. (Acceptance boxes below are `[ ]`; flip on delivery.)

---

## Description

Implement `mcp/core/shared/stdio.rkt`, the **newline-delimited JSON framing** layer for `racket-mcp`. MCP's stdio transport frames each JSON-RPC message as one line of UTF-8 JSON terminated by a single `\n`; the receiver buffers a continuous byte stream (which arrives in arbitrary chunk boundaries) and re-assembles it into discrete messages. This module provides exactly that, in two halves:

1. **Encoder** — `serialize-message`: a JSON-RPC message envelope (a `jsexpr` JSON object) → **framed bytes** (`JSON.stringify(message) + '\n'`, UTF-8). Mirrors TS `serializeMessage`.
2. **Decoder / read buffer** — a `ReadBuffer` analogue that **buffers a byte stream** fed to it in arbitrary chunks and yields complete messages one at a time, **buffering partial frames** across reads. Mirrors TS `ReadBuffer` (`append` / `readMessage` / `clear`).

This module is the **direct transliteration of `stdio.ts`** — same framing, same default max-buffer size, same three load-bearing `ReadBuffer` behaviours (below). It is **NOT** a redesign; the queue is explicit that the three behaviours must be **mirrored and NOT "fixed."**

### Framing — the three `ReadBuffer` behaviours that MUST be mirrored (do NOT omit, do NOT "fix")

These three are PINNED by the queue as deliberate behaviours an implementer might wrongly "correct." Port each verbatim:

**(a) Max-buffer-size enforcement — a DoS guard that THROWS on overflow.** A configurable cap with default `STDIO-DEFAULT-MAX-BUFFER-SIZE = (* 10 1024 1024)` (10 MB). `append` computes `new-size = (+ current-length chunk-length)`; if `new-size > max` it **clears the buffer and raises** (`exn:fail?`). This is an intentional denial-of-service guard against an unbounded line with no newline — do **NOT** "fix" it to silently truncate, drop the chunk, or grow without bound. Two pinned sub-behaviours (from the TS fixtures):
- **`>` not `>=`** — a buffer filled to *exactly* `max` does **not** throw; only the append that would *exceed* `max` throws (TS test `should allow appending up to exactly the max size`).
- **clear-before-throw** — on overflow the buffer is cleared *before* the raise, so the buffer is **reusable** afterward (TS test `should clear buffer before throwing on overflow`: after the throw, a fresh `append` + `read` works normally).

**(b) CRLF tolerance — strip a trailing `\r` before parse.** A line may be `\r\n`-framed (e.g. a peer on Windows, or a tool that emits CRLF). Before parsing a line, strip a single trailing `\r` (byte `13`) if present (TS: `.replace(/\r$/, '')`). A `\r\n`-framed message MUST decode **identically** to its `\n`-framed form. Do **NOT** treat the `\r` as part of the JSON.

**(c) Skip non-JSON lines — continue, do NOT throw.** A line that fails to **parse as JSON** (e.g. `Debug: Starting server`, `Warning: …`, an unbalanced-brace fragment, an empty line) is **skipped** — `readMessage` continues to the next line rather than raising. This is intentional (hot-reload tools like `tsx`/`nodemon` write plain-text debug output to stdout interleaved with the protocol stream). Do **NOT** "correct" this to a hard error.
> **CRITICAL distinction — non-JSON-skip vs invalid-envelope-throw (PINNED).** Skipping applies ONLY when the line fails to **parse as JSON**. A line that **parses as valid JSON but is not a well-formed JSON-RPC message** (e.g. `{"not": "a jsonrpc message"}`) MUST **raise**, NOT be skipped — TS test `should still throw on valid JSON that fails schema validation`. The TS code distinguishes these by `error instanceof SyntaxError`: a `JSON.parse` `SyntaxError` → `continue` (skip); a schema-validation error → re-`throw`. The Racket port mirrors this exactly: a `read-json` parse failure (or an empty/whitespace-only line) → skip; a successfully parsed value that fails the JSON-RPC envelope check → raise. **Getting this distinction wrong (skipping the invalid-envelope case, or throwing on the non-JSON case) is the single most likely defect for this item.**

### The `deserializeMessage` analogue — what counts as a "message" (PINNED, read carefully)

TS `deserializeMessage(line)` = `JSONRPCMessageSchema.parse(JSON.parse(line))`. Two facts pin the Racket port:

1. **The frame payload is a `jsexpr` JSON-RPC envelope (a `json-object?`), NOT a method-dispatched MCP facade struct.** TS's `ReadBuffer` yields a `JSONRPCMessage` — the **shallow** JSON-RPC envelope (request / notification / response / error), validated structurally; it does **NOT** perform MCP-method-specific param parsing (that is the `Protocol` layer's job, after the message is routed). The Racket port mirrors this: `serialize-message` takes, and `read-message!` yields, the **`read-json`-shaped `jsexpr`** (a symbol-keyed immutable `hasheq` — the wire form). **Method-specific dispatch belongs to M7 / the protocol engine, which needs a *negotiated revision* (S1's `dispatch-for` is keyed by `(method . revision)`); the framing layer is revision-agnostic and never decides a revision.** This is the central framing decision — do NOT pull the S1 revision dispatch or facade `normalize-*` seam into M5e.

2. **The envelope validation reuses S1's `guards.rkt`.** S1 already ships the `JSONRPCMessageSchema.parse` analogue as three shallow structural predicates: `is-jsonrpc-request?`, `is-jsonrpc-notification?`, `is-jsonrpc-response?` (the last is itself `result-response ∨ error-response`). A parsed value is a valid JSON-RPC **message** iff it satisfies `(or (is-jsonrpc-request? v) (is-jsonrpc-notification? v) (is-jsonrpc-response? v))`. `deserialize-message` runs this check and **raises** when it fails (the invalid-envelope-throw of behaviour (c)). Do NOT re-implement the envelope rules — reuse the S1 guards (single source of truth; keeps M5e in parity with the rest of the core).

> **The object-shape predicate — use the S1-barrel `json-object?` (PINNED, VERIFIED).** `mcp/core/types/types.rkt` defines and **`provide`s** a public `json-object?` (`(and (hash? v) (immutable? v) (hash-eq? v))` — the `read-json` shape: an immutable symbol-keyed `hasheq`), re-exported through `mcp/core/main.rkt`. **Verified resolvable via the barrel** (`(require "core/main.rkt") json-object?` → a procedure; `(json-object? (hasheq 'a 1))` → `#t`), and already consumed by item 015's `auth.rkt` for its `extra`/`->json` contracts. Use **this** public `json-object?` for the `serialize-message` input contract and the read-result shape. **NB — it is NOT the same binding as the private `json-object?` inside `guards.rkt`** (guards.rkt has an internal, un-`provide`d copy by the same name); name the barrel one, not the guards one. *(Acceptable fallback if a future S1 change ever drops the public export: M5e defines a one-line local `(define (json-object? v) (and (hash? v) (immutable? v) (hash-eq? v)))`. Either way the predicate exists; the spec does not depend on which.)*
> **Boundary rejection (PINNED).** `serialize-message`'s input is contracted to `json-object?`, so a **non-object** — a mutable hash, a string-keyed hash, a list, a number, a string — is **rejected at the boundary** (`exn:fail:contract?`), never silently framed. On the read side, a line that parses to a non-object (e.g. `42`, `"hi"`, `[1,2,3]`, the symbol `'null`) is a *parse success* that **fails the envelope check and RAISES** (it is not a `json-object?`, so all three `is-jsonrpc-*` predicates are `#f`) — see behaviour (c) and Testing Strategy Part 4.

> **Whole-line parse (PINNED — match `JSON.parse(line)`).** TS `JSON.parse(line)` consumes the **entire** line as one JSON value; trailing non-whitespace makes it throw (→ skip). Racket `read-json` reads **one** value and stops, ignoring trailing bytes. To match TS, `deserialize-message` MUST parse the line as a *whole* JSON value: read one `jsexpr`, then confirm the remainder of the (CRLF-stripped) line is **whitespace-only / EOF**; if trailing non-whitespace remains, treat the line as **non-JSON** (skip, like a `SyntaxError`). This keeps `{...}garbage` a skipped line, not a half-accepted message. (The fixtures do not directly probe trailing garbage, but this is the faithful reading of `JSON.parse(line)`; pin it with one test — see Testing Strategy Part 4.)

> **Empty / whitespace-only line → skip (PINNED).** `read-json` on `""` or `"   "` returns `eof` (it skips leading whitespace and finds no value). An `eof` (no value) line is treated as **non-JSON → skip**, matching TS where `JSON.parse("")` throws `SyntaxError` → `continue` (TS test `should skip empty lines`: `\n\n{msg}\n\n` yields just the one message). Leading/trailing whitespace *around* a valid value is tolerated (`read-json` skips leading whitespace; the trailing-whitespace-only remainder passes the whole-line check) — TS test `should tolerate leading/trailing whitespace around valid JSON`.

### Public surface (PINNED)

```racket
;; --- encoder ---
(serialize-message msg)                 ; json-object? -> bytes?   ; JSON + "\n", UTF-8 framed bytes

;; --- decoder convenience (the deserializeMessage analogue) ---
(deserialize-message line)              ; (or/c bytes? string?) -> json-object?
                                        ;   parse one whole JSON value + envelope-validate;
                                        ;   RAISES on BOTH a non-JSON line AND a
                                        ;   valid-JSON-but-invalid-envelope line.
                                        ;   STANDALONE convenience for direct callers/tests —
                                        ;   read-message! does NOT route through it (see Decoder
                                        ;   details: read-message! must SKIP non-JSON, which
                                        ;   deserialize-message raises on).

;; --- read buffer (the ReadBuffer analogue) ---
(make-read-buffer [#:max-buffer-size STDIO-DEFAULT-MAX-BUFFER-SIZE])  ; -> read-buffer?
(read-buffer? v)                        ; -> boolean?
(read-buffer-append! rb chunk)          ; read-buffer? bytes? -> void  ; RAISES on overflow (clears first)
(read-buffer-read-message! rb)          ; read-buffer? -> (or/c json-object? #f)
                                        ;   #f when no COMPLETE frame is buffered yet (TS null);
                                        ;   skips non-JSON lines; RAISES on a complete invalid-envelope line.
(read-buffer-clear! rb)                 ; read-buffer? -> void

STDIO-DEFAULT-MAX-BUFFER-SIZE           ; = (* 10 1024 1024)  (10485760)
```

- **The "no complete message" return is `#f` (PINNED).** TS `readMessage` returns `null` when the buffer holds no newline-terminated line yet. The Racket analogue is **`#f`** (consistent with item 013's no-match → `#f` convention). A decoded message is always a `json-object?` (a hash), never `#f`, so the result is unambiguous: `#f` ⇔ "no complete frame available; feed more bytes." Pin with a test (`(read-buffer-read-message! (make-read-buffer))` → `#f` on a fresh buffer).
- **`append!` / `read-message!` / `clear!` are stateful (`!` suffix).** The `read-buffer` is a small mutable struct holding the accumulated bytes + the max-size cap. This faithfully mirrors TS's mutable `ReadBuffer` (the transport feeds it chunks as they arrive off the port). Use a `(struct read-buffer ([bytes #:mutable] max-size))` (or a boxed bytes field). The buffered bytes default to empty (`#""`); `clear!` resets to empty.
- **`append!` takes `bytes?` (PINNED).** The wire is bytes (TS `Buffer`); the transport reads raw bytes off the port and feeds them in. Do NOT make `append!` take a string (that would force a premature, possibly mid-multibyte-codepoint UTF-8 decode at a chunk boundary). Decoding to text happens **per line**, after a full newline-terminated line is isolated — so a multibyte character split across two chunks reassembles correctly at the byte level before any decode. `serialize-message` returns `bytes?` symmetrically.
- **Internal buffer representation (PINNED).** A mutable bytes field; `append!` sets it to `(bytes-append current chunk)` (or `chunk` when empty); `read-message!` scans for the first newline byte (`10`), and on a hit `subbytes` the line out (`[0, idx)`) and replaces the field with the remainder (`[idx+1, end)`). This mirrors TS's `Buffer.concat` + `subarray`. (O(n) concat like TS; M7 may optimize with a smarter accumulator later if a profile demands — out of scope here. Note it in Decisions.)

### Encoder details (PINNED)

`serialize-message msg`: `(bytes-append (string->bytes/utf-8 (jsexpr->string msg)) #"\n")`. Mirrors TS `JSON.stringify(message) + '\n'`. **Does NOT validate** the envelope (TS `serializeMessage` does not either — it trusts its caller, the `Protocol` layer, to hand it a well-formed message). Contract the input to `json-object?` so a non-object is caught at the boundary (see "Boundary rejection" above), but do not run the `is-jsonrpc-*` predicates here. The newline is a single `\n` (byte `10`), never `\r\n` — the encoder always emits the canonical `\n` framing; CRLF tolerance is a *receiver*-side accommodation only.

> **The framing premise — a `\n`/`\r` INSIDE a JSON string value is escaped, never a raw delimiter byte (PINNED, VERIFIED).** `jsexpr->string` (like JS `JSON.stringify`) emits a control character inside a string value as a **two-char escape** (`\n` → `\n`, `\r` → `\r`), so the serialized message contains **no raw byte `10` or `13` other than the trailing frame `\n`**. Verified: `(jsexpr->string (hasheq 'jsonrpc "2.0" 'method "x" 'params (hasheq 'text "line1\nline2\rline3")))` contains neither a raw byte `10` nor a raw byte `13`. This is the foundation of newline-delimited framing — a message whose payload contains newlines/carriage-returns still occupies exactly **one** frame. It is the single most load-bearing premise of the whole module, so it is **pinned with a test** (Testing Strategy Part 1: an embedded-`\n`/`\r` value round-trips as one frame).

### Decoder details (PINNED — port `ReadBuffer.readMessage`)

**The mechanism is PINNED — ONE factoring, do NOT deviate (this is the item's highest-risk defect).** `read-message!` is built on an internal helper `try-parse-json-line` that confines the parse-failure handler, and runs the envelope check **outside** any handler. It does **NOT** call `deserialize-message` (which raises on non-JSON and so could not skip). Concretely:

```racket
;; try-parse-json-line : bytes? -> (values (or/c jsexpr #f) boolean?)
;;   (values value #t) IFF the whole (CRLF-stripped) line parses as ONE JSON
;;   value with only trailing whitespace; (values #f #f) on ANY parse failure
;;   (read-json raises, OR returns eof [empty/whitespace-only line], OR leaves
;;   trailing non-whitespace). Catches ONLY the read-json parse exn — NEVER an
;;   envelope error (the envelope is not consulted here).
;;   NOTE: a non-eof scalar (the symbol 'null, a number, a string, an array) is
;;   a parse SUCCESS -> (values that-value #t); only eof counts as a failure.
(define (try-parse-json-line line) ....)

(define (read-buffer-read-message! rb)
  (let loop ()
    (define buf (read-buffer-bytes rb))
    (define idx (bytes-index-of-newline buf))          ; first byte 10, or #f
    (cond
      [(not idx) #f]                                    ; (1) incomplete frame -> #f (TS null)
      [else
       (define line (strip-trailing-cr (subbytes buf 0 idx)))   ; (3) CRLF tolerance (byte 13)
       (set-read-buffer-bytes! rb (subbytes buf (add1 idx)))    ; (2) advance past the \n
       (define-values (val ok?) (try-parse-json-line line))     ; (4) parse, handler-confined
       (cond
         [(not ok?) (loop)]                             ;   parse failure -> SKIP (continue)
         [(jsonrpc-message? val) val]                   ;   valid envelope -> YIELD
         [else                                          ;   parse-ok BUT bad envelope -> RAISE
          (error 'read-buffer-read-message!
                 "not a valid JSON-RPC message: ~e" val)])])))
```

where `jsonrpc-message?` (internal, not provided) = `(or (is-jsonrpc-request? v) (is-jsonrpc-notification? v) (is-jsonrpc-response? v))`.

> **FORBIDDEN PATTERN (the exact pinned defect).** Do **NOT** write `read-message!` as `(with-handlers ([exn:fail? (λ (_) (loop))]) (deserialize-message line))` or any broad `exn:fail?`-catch around the envelope step. That would catch the invalid-envelope `error` and **wrongly SKIP** `{"not":"a jsonrpc message"}` — the precise behaviour the queue forbids "fixing." The parse handler MUST be confined to `try-parse-json-line` (catching only `read-json`'s read exn), and the envelope check + its `error` MUST sit OUTSIDE that handler. This mirrors TS's `try { return deserializeMessage(line) } catch (e) { if (e instanceof SyntaxError) continue; else throw }` — the `instanceof SyntaxError` test is exactly this skip-vs-rethrow split. Part 4's CRITICAL test (`{"not":…}` → raises, contrasted with the skip cases) falsifies the broad-catch defect; it MUST be present.

> **`deserialize-message` is the standalone convenience, NOT on `read-message!`'s path.** `deserialize-message line` shares `try-parse-json-line` but raises on a parse failure too (it has no buffer to advance / no next line to skip to): parse-failure → raise a parse error; parse-ok-but-bad-envelope → raise the envelope `error`; parse-ok-and-valid → return the `json-object?`. Direct callers/tests use it to assert both raise paths (Part 1). Keeping it off `read-message!`'s path is what lets `read-message!` skip non-JSON while `deserialize-message` raises on it — the two have deliberately different non-JSON semantics.

### `append!` overflow details (PINNED — port `ReadBuffer.append`)

```racket
;; new-size = current-length + chunk-length; if new-size > max: clear THEN raise.
(define (read-buffer-append! rb chunk)
  (define new-size (+ (bytes-length (read-buffer-bytes rb)) (bytes-length chunk)))
  (when (> new-size (read-buffer-max-size rb))
    (read-buffer-clear! rb)                     ; clear BEFORE raising (reusable after)
    (error 'read-buffer-append! "ReadBuffer exceeded maximum size of ~a bytes"
           (read-buffer-max-size rb)))
  (set-read-buffer-bytes! rb (bytes-append (read-buffer-bytes rb) chunk)))
```
- `>` (strict) so exactly-`max` is allowed.
- clear-before-raise so the buffer is reusable.
- The raised error MUST be an `exn:fail?` whose message mentions the max size (so a test can assert it like TS's `/ReadBuffer exceeded maximum size/` regex). A plain `(error …)` suffices; an S1 error-layer constructor (`make-protocol-error`/`make-mcp-error`) is also acceptable if the implementer prefers consistency with item 013's raise-on-malformed style — either way it MUST be `exn:fail?` and carry the size in the message. (Decisions records which was shipped.)

### Imports + portability (PINNED)

- The module requires: `mcp/core/main.rkt` (the S1 barrel — the `is-jsonrpc-request?` / `is-jsonrpc-notification?` / `is-jsonrpc-response?` guards + `JSONRPC-VERSION` + the errors M2 if used for the raise) and `json` (`read-json` / `jsexpr->string` / `string->jsexpr`). The in-memory byte ports (`open-input-bytes`) and bytes ops (`bytes-append`, `subbytes`, `bytes-length`, the newline scan) are **`racket/base`**.
- **No subprocess, no socket, no real device I/O.** Although the queue frames M5e as "the only M5 module that performs I/O," the `ReadBuffer`/encoder are mechanically **pure byte manipulation** — the buffer never reads stdin or spawns a subprocess; the *transport (M7)* owns the actual port reads/writes and feeds bytes to this buffer. So this module pulls **no** `racket/system` / `racket/tcp` / `racket/udp` / `net/*` / subprocess / socket module — it stays portability-clean by construction. (`json` is a core, socket-free collection.)
> **Item 017 still ISOLATES this module from the S2 restricted-load sweep (PINNED — honor the queue's framing).** The queue + item 017 designate `shared/stdio.rkt` as "the only S2 module permitted to touch I/O" and have item 017's collection-wide restricted-namespace sweep **isolate** it (the non-I/O modules — `uri-template`/`tool-name-validation`/`metadata-utils`/`auth` — are swept; stdio is the carve-out). This item therefore does **NOT** add a per-module `module->imports` restricted-load test (consistent with items 014/015). It honors the no-subprocess/no-socket import discipline (and its actual closure happens to be clean), but the formal sweep + the isolation carve-out are item 017's job. Do not duplicate them here.

### Scope guards (explicit — do NOT cross these lines)

- **Mirror, do NOT "fix" the three behaviours.** Max-buffer overflow → THROW (not truncate); CRLF → strip trailing `\r` (not reject); non-JSON line → skip (not error). The invalid-*envelope* line still THROWS. These are PINNED by the queue.
- **No real device I/O / no transport.** This module is the framing buffer + codec ONLY. It does NOT read stdin, write stdout, spawn a subprocess, open a socket, or own a port loop — that is M7 (S6a), the consumer. Do NOT import `racket/system`, sockets, or `net/*`.
- **No method-specific MCP parsing / no revision dispatch.** The frame payload is the shallow `jsexpr` JSON-RPC envelope (validated via the S1 guards), NOT a `dispatch-for`/`normalize-*` facade struct. The framing layer is revision-agnostic. (M7/the engine routes + normalizes after framing.)
- **No re-implementation of the envelope rules.** Reuse S1's `is-jsonrpc-request?` / `is-jsonrpc-notification?` / `is-jsonrpc-response?`. Do not hand-roll a parallel JSON-RPC validator.
- **Encoder always emits `\n`.** Never `\r\n`. CRLF is receiver-side tolerance only.
- **No `(module+ test …)`** in `stdio.rkt` — tests live under `mcp/core/shared/test/` (consistent with items 010–015).
- **Explicit `provide`** — never `(all-defined-out)` (architecture §1.3). No internal helper (the line-scan, the parse helper) leaks.

---

## Acceptance Criteria

- [ ] `mcp/core/shared/stdio.rkt` exists as `#lang racket/base` with an explicit, curated `provide` (no `(provide (all-defined-out))`). It lives in the existing `mcp/core/shared/` collection (created by item 013).
- [ ] The module exports exactly: `serialize-message`, `deserialize-message`, `make-read-buffer`, `read-buffer?`, `read-buffer-append!`, `read-buffer-read-message!`, `read-buffer-clear!`, and `STDIO-DEFAULT-MAX-BUFFER-SIZE`. It does NOT leak internal line-scan / parse helpers.
- [ ] **`STDIO-DEFAULT-MAX-BUFFER-SIZE` constant.** `(= STDIO-DEFAULT-MAX-BUFFER-SIZE (* 10 1024 1024))` → `#t` (`10485760`), matching TS `STDIO_DEFAULT_MAX_BUFFER_SIZE`.
- [ ] **Encoder framing.** `(serialize-message (hasheq 'jsonrpc "2.0" 'method "foobar"))` → a `bytes?` ending in a single `\n` (byte `10`); decoding it back (`(string->jsexpr (bytes->string/utf-8 (subbytes framed 0 (sub1 (bytes-length framed)))))`) reconstructs the message. The frame ends in `\n`, never `\r\n`.
- [ ] **Fresh buffer yields no message.** `(read-buffer-read-message! (make-read-buffer))` → `#f` (TS `should have no messages after initialization`).
- [ ] **Yield only after a newline (partial-frame buffering, core G1).** Appending `(serialize-message msg)` WITHOUT a trailing newline (i.e. the JSON bytes only) → `read-message!` returns `#f`; then appending `#"\n"` → `read-message!` returns the message, and a subsequent `read-message!` returns `#f`. (Ports `should only yield a message after a newline`.)
- [ ] **Multi-message round-trip in order (the queue headline).** Encode N (≥ 3) distinct messages, concatenate their framed bytes, `append!` the whole blob, then `read-message!` N times → the N messages come back **in order**, and the (N+1)th `read-message!` → `#f`. (Encode→feed→decode-all parity.)
- [ ] **Partial frame split across two reads reassembles.** Split one framed message's bytes at an arbitrary mid-frame offset; `append!` the first half → `read-message!` → `#f`; `append!` the second half (including the `\n`) → `read-message!` → the message. Also exercise a split that lands **inside a multibyte UTF-8 character** (e.g. a message whose value contains `"é"`/`"日本語"`, split between the two UTF-8 bytes of a codepoint) → the message still reassembles and decodes correctly (proves byte-level buffering, not premature per-chunk text decode). (Ports `should preserve incomplete JSON at end of buffer until completed`, extended for the multibyte-boundary case.)
- [ ] **Reusable after clear.** `append!` `#"foobar"` (garbage), `clear!`, `read-message!` → `#f`; then `append!` a valid framed message → `read-message!` → the message. (Ports `should be reusable after clearing`.)
- [ ] **Max-buffer overflow throws — default cap.** A `make-read-buffer` (default 10 MB) filled with 1 MB chunks up to 10 MB does NOT throw; the next 1 MB `append!` **raises** `exn:fail?` with a message matching `ReadBuffer exceeded maximum size`. (Ports `should throw when buffer exceeds default max size`.)
- [ ] **Max-buffer overflow throws — custom cap.** `(make-read-buffer #:max-buffer-size 100)`: `append!` 50 bytes (ok), then `append!` 51 bytes → **raises**. (Ports `should throw when buffer exceeds custom max size`.)
- [ ] **`>` not `>=` (exactly-at-max allowed).** `(make-read-buffer #:max-buffer-size 100)`: `append!` exactly 100 bytes → does **NOT** raise. (Ports `should allow appending up to exactly the max size`.)
- [ ] **Clear-before-throw (reusable after overflow).** `(make-read-buffer #:max-buffer-size 100)`: `append!` 50, then `append!` 51 → raises; afterward `append!` 50 again succeeds and `read-message!` → `#f` (buffer was cleared, not left poisoned). (Ports `should clear buffer before throwing on overflow`.)
- [ ] **CRLF tolerance — `\r\n` decodes identically to `\n`.** A message framed with `\r\n` (`(bytes-append (string->bytes/utf-8 (jsexpr->string msg)) #"\r\n")`) `append!`'d and read → the SAME `json-object?` as the `\n`-framed form (`check-equal?`). The trailing `\r` is stripped, not parsed. (Ports the CRLF accommodation.)
- [ ] **Skip empty lines.** `append!` `(bytes-append #"\n\n" (serialize-message msg) #"\n\n")` → `read-message!` → the message; next `read-message!` → `#f` (the empty lines are skipped, not errors). (Ports `should skip empty lines`.)
- [ ] **Skip non-JSON lines before a valid message.** `append!` `Debug: Starting server\nWarning: Something happened\n` + a framed message → `read-message!` → the message; next → `#f`. (Ports `should skip non-JSON lines before a valid message`.)
- [ ] **Skip non-JSON lines interleaved with multiple valid messages.** `Debug line 1\n` + frame(m1) + `Debug line 2\nAnother non-JSON line\n` + frame(m2) → `read-message!` → m1, → m2, → `#f`. (Ports `should skip non-JSON lines interleaved with multiple valid messages`.)
- [ ] **Skip unbalanced-brace / JSON-looking-but-invalid lines.** `{incomplete\nincomplete}\n` + frame(msg) → the msg (the two malformed lines skipped); and `{invalidJson: true}\n` (unquoted key, valid-looking but not JSON) + frame(msg) → the msg. (Ports `should skip lines with unbalanced braces` + `should skip lines that look like JSON but fail to parse`.)
- [ ] **Tolerate whitespace around valid JSON.** `append!` `(bytes-append #"  " (string->bytes/utf-8 (jsexpr->string msg)) #"  \n")` → `read-message!` → the message. (Ports `should tolerate leading/trailing whitespace around valid JSON`.)
- [ ] **Non-JSON-skip vs invalid-envelope-THROW distinction (CRITICAL).** A line that is **valid JSON but not a JSON-RPC message** raises, it is NOT skipped: `append!` `(bytes-append (string->bytes/utf-8 "{\"not\": \"a jsonrpc message\"}") #"\n")` → `read-message!` **raises** `exn:fail?`. (Ports `should still throw on valid JSON that fails schema validation`.) Contrast with the skip cases above (which do NOT raise).
- [ ] **`deserialize-message` validates the envelope.** `(deserialize-message "{\"jsonrpc\":\"2.0\",\"method\":\"foobar\"}")` → `(hasheq 'jsonrpc "2.0" 'method "foobar")`; `(deserialize-message #"{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}")` → the result-response envelope; `(check-exn exn:fail? (λ () (deserialize-message "{\"not\":\"a message\"}")))`; `(check-exn exn:fail? (λ () (deserialize-message "42")))` (valid JSON, not an envelope). Accepts both `string?` and `bytes?` input.
- [ ] **All three envelope kinds round-trip.** A request (`(hasheq 'jsonrpc "2.0" 'id 1 'method "ping")`), a notification (`(hasheq 'jsonrpc "2.0" 'method "foobar")`), and a response (`(hasheq 'jsonrpc "2.0" 'id 1 'result (hasheq))`) each survive `serialize-message` → buffer → `read-message!` → `check-equal?` to the original. (Proves the guard union accepts request/notification/response.)
- [ ] **Imports = S1 only (+ `json`).** The module requires only `mcp/core/main.rkt` + `json` (+ `racket/base`). It requires NO transport/engine/role module, NO `racket/system`/subprocess, NO socket, NO `net/*`. (The transitive restricted-load proof — with stdio carved out as the I/O module — is item 017's collection-wide sweep; not duplicated here.)
- [ ] **No `(module+ test …)`** in `stdio.rkt` — tests live in `mcp/core/shared/test/stdio-test.rkt`.
- [ ] `raco make mcp/core/shared/stdio.rkt` exits 0 (compiles clean, no warnings).
- [ ] `raco test mcp/core/shared/` passes (exit 0) — the new module + test compile and run cleanly alongside the existing `uri-template` (013), `tool-name-validation` (014), `metadata-utils` + `auth` (015) suites. Sibling suites `raco test mcp/core/validators/` and `raco test mcp/core/util/` remain green (this item touches neither).
- [ ] **Progress** (`docs/aide/progress.md`): flip the `mcp/core/shared/stdio.rkt` (M5e) Stage-S2 deliverable line (📋 → 🚧 → ✅) AND check the Stage-S2 acceptance box `[ ] stdio framing (M5e) round-trips multi-message + partial-frame buffering, standalone` (this item owns it). The parity-matrix rows + the catch-all `raco test over all S2 modules` / demo boxes belong to items 017/018 — do NOT check those here (see Completion Reminder).

---

## Implementation Steps

1. **Re-read the references** for shape + behaviour:
   - `typescript-sdk/packages/core/src/shared/stdio.ts` — the `ReadBuffer` (`append` overflow-clear-throw with `>` ; `readMessage` newline-scan + `\r`-strip + `try { deserialize } catch (SyntaxError → continue; else throw)`; `clear`), `STDIO_DEFAULT_MAX_BUFFER_SIZE`, `serializeMessage` (`JSON.stringify + '\n'`), `deserializeMessage` (`JSONRPCMessageSchema.parse(JSON.parse(line))`).
   - `typescript-sdk/packages/core/test/shared/stdio.test.ts` — every fixture (enumerate the groups: init/null, yield-after-newline, reusable-after-clear, `non-JSON line filtering` (empty / before-valid / interleaved / incomplete-preserved / unbalanced / looks-like-JSON / whitespace / still-throw-on-schema-fail), `buffer size limit` (default / custom / clear-before-throw / exactly-max / no-options)).
   - `mcp/core/types/guards.rkt` — `is-jsonrpc-request?` / `is-jsonrpc-notification?` / `is-jsonrpc-response?` (the envelope predicates the decoder reuses), and the doc note that a `read-json` object is a symbol-keyed immutable `hasheq` (so the test fixtures use `(hasheq 'jsonrpc "2.0" …)`).
   - `mcp/core/types/constants.rkt` — `JSONRPC-VERSION` = `"2.0"`.
2. **The design decisions are PINNED** (do not re-decide): message = shallow `jsexpr` envelope validated by the S1 guards (no revision dispatch / no facade struct); `read-buffer` is a mutable struct; `read-message!` → `#f` on incomplete; `append!` takes bytes, overflow → clear-then-raise with `>`; CRLF strip trailing `\r`; non-JSON line → skip, invalid-envelope line → raise; encoder always `\n`; imports S1 + `json` only.
3. **Write `mcp/core/shared/stdio.rkt`** (`#lang racket/base`):
   - `(require json "../main.rkt")` (relative S1 barrel — matching the `util/schema.rkt` / item-015 convention; `mcp/core/main.rkt` is not a registered collection path). NO `racket/system`, NO sockets, NO `net/*`.
   - A module-level **doc block** recording: the transliteration framing (port of TS `stdio.ts`); the three load-bearing behaviours (overflow-throw / CRLF-strip / non-JSON-skip) and the **non-JSON-skip-vs-invalid-envelope-throw distinction**; that the frame payload is the **shallow `jsexpr` envelope** validated via the S1 guards (revision-agnostic; method dispatch is M7's job); the `#f`-on-incomplete convention; that the buffer is pure byte manipulation (no real device I/O — M7 owns the port loop) and the orphaned-until-S6a note.
   - `STDIO-DEFAULT-MAX-BUFFER-SIZE` = `(* 10 1024 1024)`.
   - `serialize-message` (`(bytes-append (string->bytes/utf-8 (jsexpr->string msg)) #"\n")`; input contracted to `json-object?`; no envelope validation).
   - An internal **`jsonrpc-message?`** helper = `(or (is-jsonrpc-request? v) (is-jsonrpc-notification? v) (is-jsonrpc-response? v))` (NOT provided).
   - An internal **`try-parse-json-line`** (line bytes → `(values jsexpr #t)` on a clean whole-value parse, `(values #f #f)` on parse failure / eof / trailing-garbage). Use `(open-input-bytes line)` + `read-json`; on the `read-json` value, peek/read the remainder and confirm whitespace-only/eof; wrap `read-json` in a handler catching its read exn.
   - `deserialize-message` (accept `bytes?` or `string?`; CRLF-strip not needed here since callers pass a single line, but be liberal — strip a trailing `\r` defensively; parse via `try-parse-json-line`; on parse failure raise a parse error; on success, envelope-check and **raise** if invalid; return the `json-object?`).
   - `(struct read-buffer ([bytes #:mutable] max-size))`; `make-read-buffer` (keyword `#:max-buffer-size`, default the constant; initial bytes `#""`); `read-buffer-clear!` (set bytes to `#""`).
   - `read-buffer-append!` (overflow guard `>`, clear-then-raise; else `bytes-append`).
   - `read-buffer-read-message!` (loop: find byte `10`; none → `#f`; else split, strip trailing `13`, `try-parse-json-line` → parse-fail → continue (skip); parse-success → envelope-check → invalid → raise, valid → return). **The two failure modes MUST stay distinct** (skip parse failures; raise envelope failures) — mirror TS's `instanceof SyntaxError` branch.
   - Explicit `(provide …)` block (the eight names above).
4. **Write the test** `mcp/core/shared/test/stdio-test.rkt` (see Testing Strategy). Port EVERY `stdio.test.ts` fixture 1:1, plus the multi-message-round-trip + multibyte-split + all-three-envelope-kinds + `deserialize-message` direct cases.
5. **Run** `raco make mcp/core/shared/stdio.rkt` then `raco test mcp/core/shared/`. Fix any failure. Confirm `raco test mcp/core/validators/` and `raco test mcp/core/util/` still pass (this item touches neither).
6. **Update progress** (see Completion Reminder).

---

## Testing Strategy

The test is a **fixture-port + framing-round-trip harness**: it ports each `stdio.test.ts` fixture 1:1, asserting the SAME behaviour the TS suite asserts (G1 parity), plus the queue-mandated multi-message round-trip and partial-frame buffering, the multibyte-boundary split, the all-three-envelope-kinds round-trip, and direct `deserialize-message` cases. No external services; `raco test` only; the byte stream is **synthetic** (constructed in-test), so no real stdio/subprocess is needed.

**Test file:** `mcp/core/shared/test/stdio-test.rkt` (`#lang racket/base`; `(require rackunit json (file "../stdio.rkt"))`). `json` for building wire hashes / decoding framed bytes in assertions. No transport, no subprocess.

Small helpers keep assertions terse:
```racket
(define m  (hasheq 'jsonrpc "2.0" 'method "foobar"))           ; the TS testMessage (a notification)
(define (feed rb . chunks) (for ([c chunks]) (read-buffer-append! rb c)) rb)
;; (drain rb) -> list of all complete messages currently buffered, in order.
(define (drain rb)
  (let loop ([acc '()])
    (define msg (read-buffer-read-message! rb))
    (if msg (loop (cons msg acc)) (reverse acc))))
```

### Part 1 — Encoder + `deserialize-message`

- `(check-equal? STDIO-DEFAULT-MAX-BUFFER-SIZE (* 10 1024 1024))`.
- **Framing:** `(define framed (serialize-message m))` → `(check-true (bytes? framed))`; `(check-equal? (bytes-ref framed (sub1 (bytes-length framed))) 10)` (ends in `\n`); `(check-not-equal? (bytes-ref framed (- (bytes-length framed) 2)) 13)` (NOT `\r\n`); decoding the body (`(string->jsexpr (bytes->string/utf-8 (subbytes framed 0 (sub1 (bytes-length framed)))))`) `check-equal?`s `m`.
- **`deserialize-message` valid:** `(check-equal? (deserialize-message "{\"jsonrpc\":\"2.0\",\"method\":\"foobar\"}") m)`; bytes input `(check-equal? (deserialize-message #"{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}") (hasheq 'jsonrpc "2.0" 'id 1 'result (hasheq)))`.
- **`deserialize-message` invalid-envelope raises:** `(check-exn exn:fail? (λ () (deserialize-message "{\"not\":\"a message\"}")))`; `(check-exn exn:fail? (λ () (deserialize-message "42")))` (valid JSON scalar, not an envelope); `(check-exn exn:fail? (λ () (deserialize-message "[1,2,3]")))` (array, not an envelope); `(check-exn exn:fail? (λ () (deserialize-message "null")))` (parses to the symbol `'null`, not an object → raise).
- **`deserialize-message` on a non-JSON line raises (NOT skip — it has no buffer to advance).** `(check-exn exn:fail? (λ () (deserialize-message "Debug: starting")))`; `(check-exn exn:fail? (λ () (deserialize-message "")))` (empty → eof → parse failure → raise). This is the deliberate split vs `read-message!`, which SKIPS these same lines (Part 4). (Asserts the two helpers' different non-JSON semantics — the reason `read-message!` is NOT built on `deserialize-message`.)
- **Raw-preserve — nested unknown keys survive UNCHANGED (G1 divergence from TS, pinned).** Build a request with an extra *nested* key inside `params`: `(define raw (hasheq 'jsonrpc "2.0" 'id 1 'method "x" 'params (hasheq 'known 1 'unknownNested 2)))`; `(check-equal? (deserialize-message (bytes->string/utf-8 (subbytes (serialize-message raw) 0 (sub1 (bytes-length (serialize-message raw)))))) raw)` — the `unknownNested` key is **preserved verbatim** (the Racket port returns the raw `read-json` jsexpr; it does NOT strip unknown nested keys the way TS's Zod-normalized `deserializeMessage` does). (See Decisions (j). Note: an extra *top-level* key would instead FAIL the strict envelope and RAISE — Part 4 covers the top-level case implicitly via the invalid-envelope test.)

### Part 2 — Read buffer: init, yield-after-newline, reuse (ported)

- **Init → `#f`:** `(check-false (read-buffer-read-message! (make-read-buffer)))` (`should have no messages after initialization`).
- **Yield only after newline:** build `rb`; `append!` `(string->bytes/utf-8 (jsexpr->string m))` (no newline) → `(check-false (read-buffer-read-message! rb))`; `append!` `#"\n"` → `(check-equal? (read-buffer-read-message! rb) m)`; `(check-false (read-buffer-read-message! rb))`. (`should only yield a message after a newline`.)
- **Reusable after clear:** `append!` `#"foobar"`; `clear!`; `(check-false (read-buffer-read-message! rb))`; `append!` `(serialize-message m)`; `(check-equal? (read-buffer-read-message! rb) m)`. (`should be reusable after clearing`.)

### Part 3 — Multi-message round-trip + partial-frame buffering (the queue headline)

- **Multi-message in order:** `(define m1 (hasheq 'jsonrpc "2.0" 'method "method1"))` … `m2` … `m3` (and/or a request + response); `(define blob (apply bytes-append (map serialize-message (list m1 m2 m3))))`; `(define rb (feed (make-read-buffer) blob))`; `(check-equal? (drain rb) (list m1 m2 m3))`; `(check-false (read-buffer-read-message! rb))`.
- **Partial frame split across two reads:** `(define f (serialize-message m1))`; pick a mid-frame split `k` (e.g. `(quotient (bytes-length f) 2)`); `(define rb (make-read-buffer))`; `append!` `(subbytes f 0 k)` → `(check-false (read-buffer-read-message! rb))`; `append!` `(subbytes f k)` → `(check-equal? (read-buffer-read-message! rb) m1)`. (`should preserve incomplete JSON at end of buffer until completed`.)
- **Split INSIDE a multibyte UTF-8 char (NON-vacuous — split at a LOCATED lead byte).** `(define mu (hasheq 'jsonrpc "2.0" 'method "x" 'params (hasheq 'v "é日本語")))`; `(define f (serialize-message mu))`. **First assert a multibyte byte actually exists** so the test cannot pass vacuously if `jsexpr->string` ever changed to `\uXXXX`-escape non-ASCII: `(define lead (for/first ([b (in-bytes f)] [i (in-naturals)] #:when (= b #xC3)) i))` then `(check-true (and lead #t))` (the `é` UTF-8 lead byte `0xC3` is present; `é` = bytes `#xC3 #xA9`). Split **right after** the located lead byte (`(add1 lead)`), so the two bytes of `é` land in different chunks: `(define rb (make-read-buffer))`; `(read-buffer-append! rb (subbytes f 0 (add1 lead)))` → `(check-false (read-buffer-read-message! rb))`; `(read-buffer-append! rb (subbytes f (add1 lead)))` → `(check-equal? (read-buffer-read-message! rb) mu)`. (Proves byte-level buffering: a naive per-chunk `bytes->string/utf-8` would raise/corrupt on the split codepoint; the byte buffer + per-complete-line decode does not. The located-lead-byte split makes the test genuinely exercise the boundary, not a blind quotient that might land between codepoints.)
- **Embedded `\n`/`\r` in a string value frames as ONE message (the framing premise).** `(define em (hasheq 'jsonrpc "2.0" 'method "x" 'params (hasheq 'text "line1\nline2\rline3")))`; `(define f (serialize-message em))`; **assert the encoded frame has exactly one raw byte `10` (the trailing delimiter) and zero raw byte `13`**: `(check-equal? (for/sum ([b (in-bytes f)] #:when (= b 10)) 1) 1)` and `(check-equal? (for/sum ([b (in-bytes f)] #:when (= b 13)) 1) 0)` (the value's `\n`/`\r` were JSON-escaped, not emitted raw); then round-trip: `(define rb (feed (make-read-buffer) f))`; `(check-equal? (read-buffer-read-message! rb) em)`; `(check-false (read-buffer-read-message! rb))`. (Pins the load-bearing premise that newline-delimited framing is safe for payloads containing newlines/CRs — see Encoder details.)

### Part 4 — Non-JSON line filtering (ported, the behaviour-(c) suite)

Each builds a buffer, feeds a blob, and asserts the surviving message(s) + a trailing `#f`:
- **Empty lines:** `(feed rb (bytes-append #"\n\n" (serialize-message m) #"\n\n"))` → `(check-equal? (drain rb) (list m))`. (`should skip empty lines`.)
- **Non-JSON before valid:** `(feed rb (bytes-append #"Debug: Starting server\n" #"Warning: Something happened\n" (serialize-message m)))` → `(check-equal? (drain rb) (list m))`. (`should skip non-JSON lines before a valid message`.)
- **Interleaved with multiple valid:** `(feed rb (bytes-append #"Debug line 1\n" (serialize-message m1) #"Debug line 2\n" #"Another non-JSON line\n" (serialize-message m2)))` → `(check-equal? (drain rb) (list m1 m2))`. (`should skip non-JSON lines interleaved with multiple valid messages`.)
- **Unbalanced braces:** `(feed rb (bytes-append #"{incomplete\n" #"incomplete}\n" (serialize-message m)))` → `(check-equal? (drain rb) (list m))`. (`should skip lines with unbalanced braces`.)
- **Looks-like-JSON-but-invalid:** `(feed rb (bytes-append #"{invalidJson: true}\n" (serialize-message m)))` → `(check-equal? (drain rb) (list m))`. (`should skip lines that look like JSON but fail to parse`.)
- **Whitespace around valid JSON:** `(feed rb (bytes-append #"  " (string->bytes/utf-8 (jsexpr->string m)) #"  \n"))` → `(check-equal? (read-buffer-read-message! rb) m)`. (`should tolerate leading/trailing whitespace around valid JSON`.)
- **Whole-line parse / trailing garbage (the PINNED `JSON.parse(line)` semantics):** `(feed rb (bytes-append (string->bytes/utf-8 (jsexpr->string m)) #"garbage\n" (serialize-message m1)))` → the trailing-garbage line is treated as non-JSON (skipped); `(check-equal? (drain rb) (list m1))`. (Pins that a value with trailing non-whitespace is rejected like TS `JSON.parse`, not half-accepted.)
- **CRITICAL — valid-JSON-but-invalid-envelope RAISES (not skip):** `(feed rb (bytes-append (string->bytes/utf-8 "{\"not\": \"a jsonrpc message\"}") #"\n"))`; `(check-exn exn:fail? (λ () (read-buffer-read-message! rb)))`. (`should still throw on valid JSON that fails schema validation`.) Contrast asserted directly against the skip cases above — this is the falsifier for the FORBIDDEN broad-catch defect.
- **CRITICAL — a valid-JSON SCALAR line RAISES through `read-message!` (MEDIUM 7 — parse-success, not skip).** A bare scalar parses cleanly (it is NOT a `read-json` failure) but is not an object, so it fails the envelope and must RAISE, not skip: `(check-exn exn:fail? (λ () (read-buffer-read-message! (feed (make-read-buffer) #"42\n"))))`; likewise `#"true\n"`, `#"\"hi\"\n"`, and **`#"null\n"`** (`read-json` returns the symbol `'null` — a parse SUCCESS, so it reaches the envelope check and raises; do NOT conflate it with the empty-line `eof` skip). This pins the parse-success-vs-parse-failure boundary inside `try-parse-json-line`: only `eof` (empty/whitespace) skips; every non-eof value goes to the envelope check.
- **Invalid UTF-8 in a complete line is SKIPPED (both TS + Racket skip).** `(feed rb (bytes-append (bytes 255 254) #"\n" (serialize-message m)))` → `(check-equal? (drain rb) (list m))` — `read-json` raises on the bad bytes (a parse failure → skip), exactly as TS's `JSON.parse` throws `SyntaxError` → continue. The surrounding valid frame still decodes.
- **A non-JSON CRLF line is still skipped (CRLF-strip then skip).** `(feed rb (bytes-append #"Debug line\r\n" (serialize-message m)))` → `(check-equal? (drain rb) (list m))` — the trailing `\r` is stripped, the remaining `Debug line` is non-JSON → skipped.

### Part 5 — CRLF tolerance

- `(define crlf (bytes-append (string->bytes/utf-8 (jsexpr->string m)) #"\r\n"))`; `(define rb (feed (make-read-buffer) crlf))`; `(check-equal? (read-buffer-read-message! rb) m)` — IDENTICAL to the `\n`-framed decode (the trailing `\r` is stripped). Also a multi-message CRLF blob: two `\r\n`-framed messages → `(drain rb)` → both.

### Part 6 — Buffer size limit (ported)

- **Default cap overflow — SINGLE `check-exn` after the fill (CRITICAL — do NOT do two `check-exn` on the same buffer).** `(define rb (make-read-buffer))`; `(define chunk (make-bytes (* 1024 1024) 0))` (1 MB of zero bytes); loop `(quotient STDIO-DEFAULT-MAX-BUFFER-SIZE (bytes-length chunk))` = 10 times `(read-buffer-append! rb chunk)` (fills to exactly 10 MB, no raise); then **ONE** assertion that both throws and matches the message: `(check-exn #rx"ReadBuffer exceeded maximum size" (λ () (read-buffer-append! rb chunk)))`. (`should throw when buffer exceeds default max size`.) **WHY single:** the overflowing append CLEARS the buffer before raising (clear-before-throw), so a *second* `check-exn` on the same `rb` would append 1 MB to an EMPTY buffer (1 MB ≤ 10 MB) and **NOT** throw — the test would fail. If you want both an `exn:fail?` assertion and the message-regex assertion, rebuild a fresh filled buffer for the second one; do NOT reuse `rb`. **Note:** the zero-byte chunk never contains a newline (`10`), so the buffer cannot drain — this faithfully drives the overflow.
- **Custom cap overflow:** `(define rb (make-read-buffer #:max-buffer-size 100))`; `(read-buffer-append! rb (make-bytes 50 0))` (ok); `(check-exn #rx"ReadBuffer exceeded maximum size" (λ () (read-buffer-append! rb (make-bytes 51 0))))`. (`should throw when buffer exceeds custom max size`.) (One `check-exn` — same clear-before-throw caveat applies.)
- **`>` not `>=` — exactly-at-max allowed:** `(check-not-exn (λ () (read-buffer-append! (make-read-buffer #:max-buffer-size 100) (make-bytes 100 0))))`. (`should allow appending up to exactly the max size`.)
- **Single-shot append larger than max throws:** `(check-exn #rx"ReadBuffer exceeded maximum size" (λ () (read-buffer-append! (make-read-buffer #:max-buffer-size 100) (make-bytes 101 0))))` — one over-cap chunk in a single call (empty buffer + 101 > 100) raises. (Guards the `new-size > max` arithmetic for the from-empty case.)
- **`max-buffer-size 0` edge:** `(define rb0 (make-read-buffer #:max-buffer-size 0))`; `(check-not-exn (λ () (read-buffer-append! rb0 #"")))` (0 + 0 = 0, not `> 0` → ok); `(check-exn #rx"ReadBuffer exceeded maximum size" (λ () (read-buffer-append! rb0 #"x")))` (0 + 1 > 0 → raise). (Confirms the `>` boundary at zero.)
- **Empty-chunk append is a no-op (no raise, no state change):** `(define rb (make-read-buffer #:max-buffer-size 100))`; `(read-buffer-append! rb (make-bytes 50 0))`; `(check-not-exn (λ () (read-buffer-append! rb #"")))`; `(check-not-exn (λ () (read-buffer-append! rb (make-bytes 50 0))))` (still exactly 100 → ok). (An empty chunk adds 0 bytes; it must neither raise nor corrupt the accumulated bytes.)
- **Clear-before-throw (reusable):** `(define rb (make-read-buffer #:max-buffer-size 100))`; `(read-buffer-append! rb (make-bytes 50 0))`; `(check-exn exn:fail? (λ () (read-buffer-append! rb (make-bytes 51 0))))`; THEN `(check-not-exn (λ () (read-buffer-append! rb (make-bytes 50 0))))`; `(check-false (read-buffer-read-message! rb))` (buffer was cleared on the throw, so it holds only the post-throw 50 zero-bytes with no newline). (`should clear buffer before throwing on overflow`.)
- **No-options backwards-compat:** `(define rb (make-read-buffer))`; `(read-buffer-append! rb (serialize-message (hasheq 'jsonrpc "2.0" 'method "ping")))`; `(check-not-false (read-buffer-read-message! rb))`. (`should work with no options`.)

### Part 7 — All three envelope kinds round-trip

- **Request:** `(define req (hasheq 'jsonrpc "2.0" 'id 1 'method "ping"))`; serialize→buffer→read→`check-equal?`.
- **Notification:** `m` (above) → round-trips.
- **Result response:** `(define res (hasheq 'jsonrpc "2.0" 'id 1 'result (hasheq)))` → round-trips.
- **Error response:** `(define err (hasheq 'jsonrpc "2.0" 'id 1 'error (hasheq 'code -32600 'message "bad")))` → round-trips. (Proves the guard union accepts request / notification / result-response / error-response.)

### Fixture → ported-test mapping (1:1, the G1 contract)

| TS `test`/`describe` group | Ported Racket part |
|---|---|
| `should have no messages after initialization` | Part 2 |
| `should only yield a message after a newline` | Part 2 |
| `should be reusable after clearing` | Part 2 |
| `non-JSON line filtering` → `skip empty lines` | Part 4 |
| `non-JSON line filtering` → `skip non-JSON lines before a valid message` | Part 4 |
| `non-JSON line filtering` → `skip … interleaved with multiple valid messages` | Part 4 |
| `non-JSON line filtering` → `preserve incomplete JSON at end of buffer until completed` | Part 3 |
| `non-JSON line filtering` → `skip lines with unbalanced braces` | Part 4 |
| `non-JSON line filtering` → `skip lines that look like JSON but fail to parse` | Part 4 |
| `non-JSON line filtering` → `tolerate leading/trailing whitespace around valid JSON` | Part 4 |
| `non-JSON line filtering` → `still throw on valid JSON that fails schema validation` | Part 4 (CRITICAL) |
| `buffer size limit` → default / custom / clear-before-throw / exactly-max / no-options | Part 6 |
| (multi-message round-trip — queue headline) | Part 3 |
| (multibyte-boundary split — byte-buffer proof) | Part 3 |
| (CRLF tolerance — queue behaviour (b)) | Part 5 |
| (all-three-envelope-kinds — guard-union proof) | Part 7 |
| (encoder framing + direct `deserialize-message`) | Part 1 |

### Fixture provenance

- The framing, max-buffer, CRLF, and non-JSON-skip behaviours + the still-throw-on-schema-fail case are lifted from `typescript-sdk/packages/core/test/shared/stdio.test.ts` (transcribed into Racket assertions; the Racket test does NOT parse the `.ts` at runtime). The multi-message-round-trip, multibyte-split, all-three-envelope-kinds, and trailing-garbage cases are net-new Racket assertions covering the queue's testable bullets + the `read-json`-vs-`JSON.parse` whole-line difference (record this in the test header).

---

## Dependencies

- **Upstream work items:**
  - **Stage S1 items 001–009** (✅ complete) — `mcp/core/main.rkt` (item 008 barrel) re-exports the `guards.rkt` envelope predicates `is-jsonrpc-request?` / `is-jsonrpc-notification?` / `is-jsonrpc-response?` (item 002) used by `deserialize-message`, plus `JSONRPC-VERSION` (item 001) and the errors M2 (items 006/007) if the overflow raise uses the S1 error layer. This is the ONLY project dependency.
  - **Item 013** created the `mcp/core/shared/` + `mcp/core/shared/test/` collection directories, into which this module + its test are added.
- **Downstream consumers (informational):**
  - **S6a stdio transport (`mcp/transport/stdio.rkt`, M7)** — M5e's **first real consumer**: M7 owns the `subprocess` + the stdin/stdout port loop, reads raw bytes off the port, `read-buffer-append!`s them, drains `read-buffer-read-message!` until `#f`, and `serialize-message`s outbound messages to the port. **This module has NO consumer inside S2** — it is built ahead of its S6a consumer (built now for L0 cohesion; ships fully tested standalone against a synthetic byte stream; integration coverage — partial/multi-message reads over a real subprocess, cross-SDK stdio parity — arrives with M7 in S6a).
  - **Item 017** — the S2 collection-wide restricted-load portability sweep **isolates** `shared/stdio.rkt` as the one I/O-permitted module (the non-I/O `shared/*` utils are swept). This item does NOT add a per-module sweep.
  - **Item 018** — the S2 demo encodes/decodes a stdio frame buffer (round-trips messages through `serialize-message` + a `read-buffer`), printing the recovered messages.
- **Tooling/runtime:** Racket ≥ 8.x (`raco`, `rackunit`, the core `json` collection). The `typescript-sdk/` checkout MUST be present for **authoring** — the behaviour is lifted from `shared/stdio.ts` and the fixtures from `test/shared/stdio.test.ts`. The Racket test does NOT parse the `.ts` at runtime (fixtures transcribed into Racket assertions), so a missing checkout would not break the running test but would make the fixture-port un-reproducible.

---

## Decisions & Trade-offs

To be updated during implementation.

The **design decisions below are PINNED at spec time** (real choices, not options). The **post-build outcome** (require list as built, exact check count, the overflow-error mechanism shipped) is *to be updated during implementation*.

**(a) The frame payload is the shallow `jsexpr` JSON-RPC envelope, validated by the S1 guards — NOT a method-dispatched facade struct.** TS `ReadBuffer` yields a `JSONRPCMessage` (the shallow envelope), not an MCP-method-parsed result; method dispatch needs a *negotiated revision* and belongs to M7 / the protocol engine. `serialize-message` takes, and `read-message!` yields, the `read-json`-shaped symbol-keyed `hasheq`. `deserialize-message` reuses `is-jsonrpc-request?` / `is-jsonrpc-notification?` / `is-jsonrpc-response?` (the `JSONRPCMessageSchema.parse` analogue) rather than re-implementing the envelope rules. **To be updated during implementation.**

**(b) `read-message!` → `#f` on an incomplete frame (TS `null`); a complete message is always a `json-object?`, so `#f` is unambiguous.** Consistent with item 013's no-match → `#f`. The buffer/append/clear are a small mutable struct (`!`-suffixed ops), faithfully mirroring TS's mutable `ReadBuffer`. **To be updated during implementation.**

**(c) The three queue-pinned behaviours are mirrored verbatim, NOT "fixed."** Max-buffer overflow → clear-then-THROW (`>` strict, so exactly-max is allowed; reusable after); CRLF → strip a single trailing `\r` before parse; non-JSON line → skip (continue). **The CRITICAL distinction:** a valid-JSON-but-invalid-*envelope* line still THROWS (mirrors TS's `instanceof SyntaxError ? continue : throw`). Getting the skip-vs-throw split wrong is the most likely defect; it is pinned with explicit contrasting tests. **To be updated during implementation.**

**(d) `append!` takes bytes; the buffer is byte-level; decode happens per complete line.** The wire is bytes (TS `Buffer`); decoding to text per-chunk would corrupt a multibyte UTF-8 codepoint split across a chunk boundary. Byte-level buffering + per-complete-line `read-json` avoids this (pinned with a multibyte-split test). The encoder emits canonical `\n` framing (never `\r\n`); CRLF is receiver-side tolerance only. **To be updated during implementation.**

**(e) Whole-line parse to match `JSON.parse(line)`.** Racket `read-json` reads one value and ignores trailing bytes; TS `JSON.parse(line)` rejects trailing non-whitespace. `deserialize-message` reads one value then confirms the remainder is whitespace-only/EOF, else treats the line as non-JSON (skip). Empty/whitespace-only lines (`read-json` → `eof`) are likewise non-JSON → skip. **To be updated during implementation.**

**(f) Pure byte manipulation — no real device I/O — despite the queue's "only M5 module that performs I/O" framing.** The `ReadBuffer`/codec never read stdin, write stdout, spawn a subprocess, or open a socket — the *transport (M7)* owns the port loop and feeds bytes in. So the actual import closure is `json` + S1 + `racket/base` byte ports — no `racket/system`/socket/`net/*`. Item 017 still *isolates* this module as the designated I/O carve-out per the queue; this item honors the no-subprocess/no-socket discipline but defers the formal sweep + isolation to 017 (no per-module walk here, consistent with items 014/015). **To be updated during implementation.**

**(g) Overflow-error mechanism.** The overflow raise is an `exn:fail?` whose message mentions the max size (so a test can assert `#rx"ReadBuffer exceeded maximum size"` like TS's regex). Either a plain `(error …)` or an S1 error-layer constructor (`make-protocol-error`/`make-mcp-error`) is acceptable; **record which shipped** (and whether the invalid-envelope raise uses the same mechanism). **To be updated during implementation.**

**(h) No `(module+ test …)` in `stdio.rkt`** — tests live in `test/stdio-test.rkt` (consistent with items 010–015; keeps the test-only `rackunit` require out of the module's closure).

**(j) `read-message!` / `deserialize-message` return the RAW `read-json` jsexpr — nested unknown keys are PRESERVED, NOT stripped (a documented G1 divergence from TS).** TS `deserializeMessage` returns the **Zod-normalized** object, which **strips unknown keys** inside the loose nested objects (`params` / `result` / `error`). The Racket port returns the raw `read-json` value unchanged: the S1 `is-jsonrpc-*` guards are **predicates** (they validate, they do not transform), so a message with an extra *nested* key (e.g. `params: {known, unknownNested}`) is accepted **and re-yielded with `unknownNested` intact**. This is the correct choice for a revision-agnostic framing layer — M5e must not silently drop wire bytes; method-specific normalization (which may legitimately strip/relocate keys) happens later at M7 / the protocol engine once a revision is known. (An extra *top-level* key still fails the strict envelope and RAISES — only nested keys ride through.) Pinned with the raw-preserve test in Part 1. Note this so a future cross-SDK conformance pass (S9) does not flag the non-stripping as a bug. **To be updated during implementation.**

**(k) Inherited S1 envelope strictness — `id: 1.0` is accepted by TS but REJECTED by the Racket guards (NOT M5e's to fix).** TS `RequestIdSchema = z.union([z.string(), z.number().int()])`; in JS `1.0 === 1`, so a JSON `id: 1.0` is an integer and TS accepts it. Racket `read-json` parses `1.0` to the **inexact** `1.0`, and S1's `valid-id?` (`guards.rkt`) uses `exact-integer?`, which **rejects** `1.0` → the envelope check fails → `read-message!` would RAISE on such a message where TS would accept. This is an **inherited S1 guard behaviour**, not introduced or fixable by M5e (M5e only *reuses* the S1 predicate). It is recorded here so the divergence is not mis-attributed to M5e at S9; if it matters, it is an S1 (`guards.rkt`) follow-up, not a stdio-framing change. Do NOT add a test pinning the divergent behaviour as "correct," and do NOT work around it in M5e. **To be updated during implementation.**

**(i) Post-build outcomes (recorded at implementation).**
- **Require list as built:** [e.g. `(require json "../main.rkt")` — S1 + `json`; NO `net/*`/subprocess/socket. Note any `(only-in …)` narrowing.]
- **Exact check count:** `raco test mcp/core/shared/` → [N checks pass, 0 failures, 0 errors] (the new `stdio-test.rkt` suite added to items 013–015's [prior count]). Sibling suites: `raco test mcp/core/validators/` → [300]; `raco test mcp/core/util/` → [102].
- **`raco make`:** `raco make mcp/core/shared/stdio.rkt` → [exit 0, clean].
- **Overflow-error mechanism shipped:** [plain `error` | S1 `make-protocol-error` | …]; message form: [the `~a`-formatted size string].
- **Frame payload form:** [shallow `jsexpr` envelope via S1 guards — confirmed; no revision dispatch pulled in].
- **No `(module+ test …)`** in `stdio.rkt` (confirmed by grep); tests in `test/stdio-test.rkt`.

---

## Project-Specific Adaptations (Racket / raco / rackunit)

This is a **Racket library, not a service** — same adaptation pattern as items 010–015. The generic "Testing Prerequisites" template (Required Services / database / API endpoint / ports / health checks) does **not** apply and is adapted as follows (documented explicitly per the create-item skill):

- **Required Services → None.** Pure Racket library; no external services, databases, message queues, HTTP servers, sockets, subprocesses, or network. The `ReadBuffer`/codec are byte manipulation over **in-memory** bytes — the synthetic byte stream in the test is constructed in-process; **no real stdio / subprocess is touched.** (M7 in S6a is the module that performs real device I/O; M5e is its pure framing helper.)
- **Database / API endpoint / ports sections → N/A.** Removed; replaced by the Racket toolchain row below.
- **Required toolchain:** Racket ≥ 8.x (`raco test`, `rackunit`, the core `json` collection). (This env: Racket v8.18 [cs], per items 013–015.)
- **TS checkout role:** present at `typescript-sdk/`; **required for authoring** (behaviour from `shared/stdio.ts`; fixtures from `test/shared/stdio.test.ts`, transcribed into Racket assertions). Not parsed at test runtime.
- **Manual Validation Checklist → specialized** to `raco make` / `raco test` + a REPL encode/decode smoke check (below). No "service started" / "health check" / "screenshots" rows — replaced with N/A or removed.
- **Language/naming:** `#lang racket/base`; kebab-case bindings; `!`-suffixed stateful ops (`append!`/`read-message!`/`clear!`); explicit `(provide …)` never `all-defined-out` (architecture §1.3); S1+`json`-only imports, no `net/*`/subprocess/socket (architecture §4.1 portability).
- **Collection directory:** `mcp/core/shared/` + `mcp/core/shared/test/` already exist (item 013). This item adds `stdio.rkt` + `test/stdio-test.rkt`.
- **No-consumer-in-S2 note:** like items 013–015, this module has NO S2 consumer; it ships fully tested standalone (against a synthetic byte stream) and is wired up by M7 in S6a. The S2 demo (item 018) exercises it.

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None (pure Racket library; no external services).** No databases, message queues, HTTP servers, sockets, subprocesses, or network dependencies. No real device I/O whatsoever — the buffer manipulates in-memory bytes; the test's byte stream is synthetic. The TS checkout is a **parity reference** read while authoring, not a runtime dependency.

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime | compile + run module and tests (`raco`, `rackunit`, core `json`) | system install (`racket --version` ≥ 8.0; this env: v8.18) | n/a |
| S1 barrel (`mcp/core/main.rkt`) | the module requires the S1 envelope guards (`is-jsonrpc-request?` etc.) + `JSONRPC-VERSION` | already present (items 001–008, ✅) | n/a |
| `typescript-sdk/` checkout | read while authoring to lift behaviour from `shared/stdio.ts` and the fixtures from `test/shared/stdio.test.ts` (G1 fixture parity) | already present at repo root | n/a |

### Environment Configuration

- **Environment variables / secrets / config files / free ports:** none required.
- **Racket version:** ≥ 8.x (verified for items 013–015: v8.18 [cs]).
- **Working directory:** run `raco test` from the **repo root** so the `mcp/...` collection path resolves.
- **How to run the tests:**
  - `raco make mcp/core/shared/stdio.rkt` — compile the stdio module clean.
  - `raco test mcp/core/shared/` — run all shared-collection tests (picks up `test/stdio-test.rkt` recursively), exit 0.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0.
  - `raco test mcp/core/shared/` (pre-change) → green (items 013–015's checks pass) so the baseline is known.

### Manual Validation Checklist

*(Not yet built — leave UNCHECKED until implementation completes.)*

- [ ] **Build/compile succeeds:** `raco make mcp/core/shared/stdio.rkt` compiles with no errors/warnings.
- [ ] **Module loads in isolation:** `racket -e '(require (file "mcp/core/shared/stdio.rkt"))'` from repo root succeeds.
- [ ] **Tests pass:** `raco test mcp/core/shared/test/stdio-test.rkt` → all checks pass, exit 0.
- [ ] **Collection tests pass:** `raco test mcp/core/shared/` → exit 0 (new + existing 013–015 suites).
- [ ] **M3/M4 untouched:** `raco test mcp/core/validators/` AND `raco test mcp/core/util/` → still exit 0 (this item modifies neither).
- [ ] **Services started:** N/A (no services — pure library, no real device I/O).
- [ ] **Application runs:** N/A (library; "running" = the require + REPL encode/decode smoke check below).
- [ ] **Feature verified (REPL encode/decode smoke check):** from repo root, encode a message and read it back through a buffer — e.g.
      `racket -e '(require (file "mcp/core/shared/stdio.rkt")) (define rb (make-read-buffer)) (read-buffer-append! rb (serialize-message (hasheq (quote jsonrpc) "2.0" (quote method) "foobar"))) (read-buffer-read-message! rb)'`
      prints `'#hasheq((jsonrpc . "2.0") (method . "foobar"))` (encode frames it, the buffer recovers it). (Record exact transcript in Validation Results.)
- [ ] **`STDIO-DEFAULT-MAX-BUFFER-SIZE` verified:** `= (* 10 1024 1024)` = `10485760`.
- [ ] **Encoder framing verified:** `serialize-message` ends in a single `\n` (byte 10), not `\r\n`; decoding the body recovers the message.
- [ ] **Fresh buffer → `#f` verified;** yield-only-after-newline verified (no newline → `#f`; add `\n` → message → `#f`).
- [ ] **Multi-message round-trip verified:** N≥3 framed messages concatenated → drained in order → trailing `#f`.
- [ ] **Partial-frame buffering verified:** mid-frame split across two appends reassembles; a split INSIDE a multibyte UTF-8 char still reassembles + decodes.
- [ ] **Reusable-after-clear verified:** garbage + `clear!` → `#f`; then valid frame → message.
- [ ] **Max-buffer overflow verified:** default 10 MB cap throws on the over-cap append (message matches `ReadBuffer exceeded maximum size`); custom-100 cap throws on 51-over-50; **`>` not `>=`** (exactly 100 → no throw); clear-before-throw (reusable after overflow); no-options small append works.
- [ ] **CRLF tolerance verified:** a `\r\n`-framed message decodes `check-equal?` to its `\n`-framed form.
- [ ] **Non-JSON-skip verified:** empty lines, debug/warning lines, unbalanced braces, looks-like-JSON-but-invalid, surrounding whitespace — all skipped; surrounding valid frames still decode.
- [ ] **Trailing-garbage (whole-line parse) verified:** `{json}garbage\n` skipped (not half-accepted).
- [ ] **CRITICAL — invalid-envelope THROW verified:** `{"not":"a jsonrpc message"}\n` → `read-message!` raises (NOT skipped); contrasted against the skip cases.
- [ ] **`deserialize-message` verified:** valid request/notification/response → the envelope; `{"not":"a message"}` / `42` / `[1,2,3]` → raise; accepts string AND bytes input.
- [ ] **All three envelope kinds round-trip verified:** request, notification, result-response, error-response each serialize→buffer→read→`check-equal?`.
- [ ] **No `(module+ test …)` in `stdio.rkt` confirmed:** tests live in `test/stdio-test.rkt`.
- [ ] **S1+`json`-only imports confirmed:** require list = `json` + `../main.rkt` (no `net/*`, no `racket/system`, no subprocess/socket). (Transitive sweep is item 017.)
- [ ] **Health checks pass:** N/A (no running service).

### Expected Outcomes

Concrete, verifiable:

- The module **exports** `serialize-message`, `deserialize-message`, `make-read-buffer`, `read-buffer?`, `read-buffer-append!`, `read-buffer-read-message!`, `read-buffer-clear!`, `STDIO-DEFAULT-MAX-BUFFER-SIZE` (and NO internal helpers). `STDIO-DEFAULT-MAX-BUFFER-SIZE` = `10485760`.
- **N messages round-trip in order:** encoding N (≥3) messages, feeding the concatenated bytes, and draining yields the same N `json-object?`s in order, then `#f`.
- **Partial-frame buffering works:** a frame split across two `append!`s (including a split inside a multibyte UTF-8 codepoint) reassembles and decodes to the original message; a buffer with no newline yields `#f`.
- **Overflow raises:** appending past the (default 10 MB or a small custom) cap raises `exn:fail?` ("ReadBuffer exceeded maximum size"); exactly-at-cap does NOT raise; the buffer is cleared on the raise and is reusable afterward.
- **CRLF-framed decodes identically:** a `\r\n`-framed message `check-equal?`s its `\n`-framed decode.
- **Non-JSON line skipped, surrounding frames decode:** a non-JSON (or empty, or trailing-garbage) line between two valid frames is skipped; both valid frames still decode. A valid-JSON-but-invalid-**envelope** line **raises** (the one non-skip failure mode).
- The module **requires only S1** (+ the core `json` collection) — no subprocess/socket/`net/*` (the transitive proof, with stdio as the I/O carve-out, is item 017's collection-wide sweep).
- `raco test mcp/core/shared/` reports all checks passing, 0 failures, 0 errors; `raco test mcp/core/validators/` and `raco test mcp/core/util/` still green (M3/M4 untouched).

### Validation Documentation Template

Record at completion (fill the bracketed values):

```
Item 016 — validation record
- Racket version: [racket --version output]
- raco make (stdio.rkt): [exit code; warnings?]
- raco test mcp/core/shared/   : [N checks passed / 0 failed]
    - stdio-test.rkt alone:      [N]
    - (existing 013+014+015:     [prior count])
- raco test mcp/core/validators/ : [300 expected]
- raco test mcp/core/util/       : [102 expected]
- STDIO-DEFAULT-MAX-BUFFER-SIZE = 10485760:                 [yes/no]
- encoder frames with single \n (not \r\n):                 [pass/fail]
- fresh buffer → #f; yield-only-after-newline:              [pass/fail]
- multi-message round-trip in order (N≥3):                  [pass/fail]
- partial-frame split across two reads reassembles:         [pass/fail]
- multibyte UTF-8 boundary split reassembles:               [pass/fail]
- reusable after clear:                                     [pass/fail]
- overflow throws — default 10MB cap:                       [pass/fail]
- overflow throws — custom cap (51 over 50):                [pass/fail]
- > not >= (exactly-at-max allowed):                        [pass/fail]
- clear-before-throw (reusable after overflow):             [pass/fail]
- CRLF decodes identically to \n:                           [pass/fail]
- skip: empty / debug / unbalanced / looks-like-JSON / whitespace: [pass/fail]
- whole-line parse (trailing garbage skipped):              [pass/fail]
- CRITICAL invalid-envelope THROWS (not skipped):           [pass/fail]
- deserialize-message valid + raise cases (string + bytes): [pass/fail]
- all 3 envelope kinds round-trip (req/notif/response/error): [pass/fail]
- overflow-error mechanism shipped:                         [plain error | S1 error]
- frame payload = shallow jsexpr envelope (no revision dispatch): [yes/no]
- (module+ test …) present:                                 [no expected]
- require list (S1 + json only; no net/* | subprocess | socket): [list]
- Decisions & Trade-offs (i) updated with as-built require list + counts: [yes/no]
```

---

## Completion Reminder

On completion, **`docs/aide/progress.md` MUST be updated** (the icon discipline is forward-only — 📋 → 🚧 → ✅, never reverted):

1. Flip the **Stage S2 deliverable line** `📋 mcp/core/shared/stdio.rkt (M5e) — newline-delimited JSON framing (orphaned until S6a)` from 📋 → 🚧 (on start) → ✅ (on delivery + all acceptance criteria pass), with a one-line as-built summary mirroring the items 013–015 deliverable lines (transliteration source, key decisions, check count). Never revert an icon backward.
2. **Check the Stage-S2 acceptance box** `[ ] stdio framing (M5e) round-trips multi-message + partial-frame buffering, standalone` — **this box belongs to THIS item** (it owns the stdio-framing deliverable). Check it on delivery.
3. Do **not** check the other broad Stage-S2 acceptance boxes that depend on sibling items: the `[ ] raco test over all S2 modules passes`, `[ ] Parity rows … marked partial`, and `[ ] Demo: …` boxes belong to items 017/018. The URI-template / tool-name / schema-normalization / validator-keyword boxes are already checked (items 012–014) — leave them.
4. **Parity matrix:** this item does **NOT** flip a parity-matrix row — there is no `stdio`/`shared` row to advance in S2 (the M5e module is orphaned until S6a, and its parity is exercised with M7's `stdio.ts` row in S6a/S9). The collection-wide restricted-load sweep that *isolates* stdio is item 017. Do not touch parity rows here.
5. Leave all other S2 deliverable lines (`validators/*` ✅; `util/schema.rkt` ✅; `uri-template`/`tool-name-validation`/`metadata-utils`/`auth` ✅; tests-under-other-dirs) at their current status — this item delivers only `stdio.rkt` + its test, completing the M5 shared-util set.
