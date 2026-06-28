# Reviewer Feedback — Item 016: stdio framing (M5e)

**Verdict:** Strong, unusually thorough spec — the three pinned `ReadBuffer` behaviours are correctly identified and the skip-vs-throw distinction is called out as the headline risk, which is exactly right. But there is **one test-strategy defect that will literally fail when implemented verbatim**, **one factoring ambiguity that invites the exact pinned defect the spec warns against**, and a handful of genuine coverage/parity gaps. Recommend revision before execute-item.

I cross-checked against the real TS source (`packages/core/src/shared/stdio.ts`), the fixture file (`test/shared/stdio.test.ts`), and `mcp/core/types/guards.rkt`, and verified the S1 barrel re-exports.

---

## What's already well-covered (do not lose)

- All 13 `stdio.test.ts` fixtures are mapped 1:1 with a provenance table — init/null, yield-after-newline, reusable-after-clear, the full `non-JSON line filtering` group, and the `buffer size limit` group.
- The **skip-vs-throw distinction** (non-JSON line → skip; valid-JSON-but-invalid-envelope → raise) is correctly identified as the single most likely defect, with TS's `instanceof SyntaxError ? continue : throw` cited precisely.
- The `>` not `>=` overflow boundary, clear-before-throw reusability, and CRLF `\r`-strip are all pinned with the right TS fixture references.
- Net-new coverage beyond the TS suite is well-chosen: multi-message round-trip, multibyte-UTF-8-boundary split, all-three-envelope-kinds, whole-line/trailing-garbage parse, direct `deserialize-message`.
- The `append!`-takes-bytes / decode-per-complete-line decision is correct and the rationale (no premature mid-codepoint decode) is sound. Byte-10 / byte-13 scanning is safe because UTF-8 never emits a `<0x80` byte mid-codepoint — the spec relies on this correctly.
- Dependency claim verified: `mcp/core/main.rkt` → `types/main.rkt` re-exports the `is-jsonrpc-*` guards and `JSONRPC-VERSION`. The union `(or is-jsonrpc-request? is-jsonrpc-notification? is-jsonrpc-response?)` correctly covers request/notification/result-response/error-response.

---

## Missing Coverage (Critical)

### C1. Part 6 default-cap test will FAIL as written — clear-before-throw breaks the double `check-exn`

Part 6 (and the prose at line 242) does:

```
... fill rb to 10 MB ...
(check-exn exn:fail?                          (λ () (read-buffer-append! rb chunk)))   ; first overflow
(check-exn #rx"ReadBuffer exceeded maximum size" (λ () (read-buffer-append! rb chunk)))  ; "on a fresh near-full buffer"
```

The **first** `check-exn` triggers the overflow, which (per the spec's own pinned behaviour) **clears the buffer before raising**. The buffer is now `#""`. The **second** `check-exn` appends 1 MB to an empty buffer → `1 MB ≤ 10 MB` → **no throw** → the second `check-exn` fails (expected exn, got none). The parenthetical "(on a fresh near-full buffer)" acknowledges the buffer must be re-filled, but the written sequence never re-fills it.

This is the spec's own clear-before-throw guarantee biting the test. Fix: use a **single** assertion — `(check-exn #rx"ReadBuffer exceeded maximum size" (λ () (read-buffer-append! rb chunk)))` already asserts both `exn:fail?` and the message — or rebuild a freshly-filled buffer before the message-regex assertion. Audit every place that does two `check-exn`s against the same buffer (the custom-cap and clear-before-throw tests are fine because they each throw once / deliberately re-append after clear).

### C2. Factoring ambiguity invites the exact pinned defect (skip the invalid-envelope case)

The public surface (line 61) says `deserialize-message` is "Used internally by `read-message!`", but Implementation Steps (line 176/180) route `read-message!` through `try-parse-json-line` + an envelope check. These are two different designs and the spec endorses both.

The danger: an implementer who takes the "deserialize-message used internally" line literally writes

```racket
(with-handlers ([exn:fail? (λ (_) (continue))])   ; WRONG
  (deserialize-message line))
```

Since `deserialize-message` raises `exn:fail?` for **both** parse-failure **and** invalid-envelope, this handler **skips the invalid-envelope case** — precisely the defect the spec spends a whole CRITICAL box warning against. Pin exactly one mechanism and make it unambiguous:

- **Preferred:** `read-message!` calls `try-parse-json-line` (parse failure → skip) and runs the envelope check **outside** any parse handler (envelope-invalid → raise). `deserialize-message` is then a *separate* public convenience, NOT on the `read-message!` path — fix the line-61 wording to say so.
- **Or:** `deserialize-message` raises **two distinguishable exn types** (a parse exn vs an envelope exn) and `read-message!` catches **only** the parse exn. Then the line-61 wording is accurate, but the spec must mandate the distinct types.

Either way, forbid a single broad `exn:fail?` handler around the whole deserialize.

---

## Missing Coverage (Suggested)

### S1. `json-object?` is not exported by S1 — the named contract is unavailable

The spec contracts `serialize-message` input and `deserialize-message` output to `json-object?` (lines 55/58/82). But `json-object?` is a **private** helper inside `guards.rkt` (line 41) and is **not** in the barrel's `provide` (verified). M5e therefore cannot reuse it — it must define its own `(and/c hash? immutable? hash-eq?)` (or fall back to `hash?`). State which, and whether `serialize-message` on a mutable or string-keyed hash is rejected at the boundary. Otherwise the acceptance criterion "non-object is caught at the boundary" is unimplementable as written.

### S2. Undocumented G1 divergence: TS returns the Zod-stripped object, Racket returns the raw jsexpr

TS `deserializeMessage` returns `JSONRPCMessageSchema.parse(...)` — Zod **strips unknown nested keys** (inside `params`/`result`/`error`) and returns a normalized object. The Racket port returns the **raw `read-json` jsexpr** (the guards are pure predicates; they don't transform). For a message with extra nested keys, TS's returned message and Racket's differ. The round-trip tests don't probe this (their fixtures have no extra nested keys), so it slips through silently. For a framing layer, raw-preserve is defensible — but it is a real G1 deviation and should be **documented in Decisions**, ideally pinned with a test (`deserialize-message` on `{"jsonrpc":"2.0","id":1,"result":{"x":1,"unknown":2}}` preserves `unknown`).

### S3. Embedded-newline-in-string-value round-trip is untested (the framing premise itself)

The whole one-message-per-line scheme depends on the encoder **escaping** an embedded `\n` inside a string value as `\n` (two chars), never a raw byte 10. No test asserts this. Add: a message like `(hasheq 'jsonrpc "2.0" 'method "x" 'params (hasheq 'v "line1\nline2"))` → `serialize-message` → buffer → `read-message!` returns it as **one** message (the embedded newline did not split the frame). Add an embedded-`\r` variant too (proves CRLF-strip doesn't corrupt internal `\r`). This is the strongest adversarial framing case and it's missing.

### S4. Multibyte-split test risks being vacuous

`(quotient (bytes-length f) 2)` may not land inside the codepoint, and if `jsexpr->string` ever escaped non-ASCII to `\uXXXX` the serialized bytes would contain **no** `≥0x80` byte and the "split inside a multibyte char" claim would be vacuously satisfied. Harden: assert `(for/or ([b (in-bytes f)]) (>= b #x80))` before splitting, locate the `0xC3` lead byte of `é`, and split immediately after it (the spec's "loop over offsets" idea is good — keep it, but anchor at least one split to a known lead byte).

### S5. Valid-JSON scalar lines through `read-message!` (not just `deserialize-message`)

`deserialize-message` is tested with `42` and `[1,2,3]`, but the **buffer path** is not tested with a scalar line. Add: `(feed rb #"42\n" (serialize-message m))` → `read-message!` **raises** (42 parses cleanly → not skipped → envelope-invalid → raise), distinct from the `{"not":...}` object case. Also worth one for `null\n`: `read-json` on `"null"` returns the symbol `'null` — a *successful* parse, so it must **raise**, whereas `""`/`"   "` return `eof` → **skip**. That `'null`-vs-eof boundary is subtle and currently only implied.

### S6. Low-risk edges that match TS but go untested (mention in Decisions, optional tests)

- Genuinely **invalid UTF-8** in a *complete* line: TS `toString('utf8')` → U+FFFD → `JSON.parse` fails → skip; Racket port `open-input-bytes`+`read-json` decodes permissively → parse fails → skip. Both skip; harmless but worth one assertion.
- `deserialize-message` on **non-JSON** input (`"Debug: foo"`) should raise (only invalid-*envelope* raises are tested).
- **Empty-chunk** append (`#""`), **single-shot over-max** append (101 into empty, max 100), and **`max-buffer-size 0`** — all match TS (no validation); note them.
- Non-JSON line framed with **CRLF** (`Debug: x\r\n`) is still skipped — combines (b) and (c); cheap to add.

### S7. Inherited S1 guard divergence (not M5e's to fix, but note it)

The envelope parity is only as faithful as the S1 guards, which have a known gap: JSON `id: 1.0` → TS `JSON.parse` yields `1`, `z.number().int()` accepts → **valid**; Racket `read-json` yields inexact `1.0`, `exact-integer?` rejects → envelope-invalid → **raise**. A `\n`-framed `{"jsonrpc":"2.0","id":1.0,"result":{}}` would round-trip differently across SDKs. This is inherited from S1 (correctly reused as single source of truth), not introduced here — but a one-line Decisions note keeps the divergence from being silently attributed to M5e at S9 parity time.

---

## Testing Prerequisites / acceptance assessment

Prerequisites are concrete and correct for a pure Racket library (no services, synthetic in-memory byte stream, `raco make` + `raco test` + a REPL smoke check). The "Required Services → None" adaptation is justified. Acceptance criteria are mostly 1:1 with testable behaviours — the gaps are the **double-`check-exn`** wording (C1), the **`json-object?` contract** (S1), and the **embedded-newline / scalar-line / non-vacuous-multibyte** cases (S3–S5). Fixing C1, C2, S1, and adding S3 are the bar for revision; S2 and S4–S7 are quality.
