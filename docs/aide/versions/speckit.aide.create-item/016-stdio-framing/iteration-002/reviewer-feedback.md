# Reviewer Feedback — Item 016 (stdio framing, M5e) — iteration-002 re-review

**Verdict:** All eight iteration-001 issues are genuinely resolved — verified against the TS source/test files and the actual Racket S1 modules, not taken on faith. The two CRITICALs are fixed correctly, the MEDIUMs are documented and pinned with tests, and the LOW edge cases are now covered or explicitly deferred with rationale. One small non-blocking coverage suggestion remains. **No revision required.**

---

## Verification of each prior issue

### CRITICAL 1 — default-cap double-`check-exn` → FIXED (verified)
Part 6 (line 284) now fills to exactly 10 MB then makes a **single** `(check-exn #rx"ReadBuffer exceeded maximum size" ...)`, with an explicit WHY note: the overflowing append clears the buffer before raising, so a second `check-exn` on the same `rb` would append to an empty buffer and not throw. It instructs rebuilding a fresh filled buffer if both an `exn:fail?` and a message-regex assertion are wanted. The custom-cap (285), single-shot-over-max (287), and max-size-0 (288) cases all use one `check-exn` each. Arithmetic verified: `(quotient 10485760 1048576) = 10`, so 10×1 MB fills to exactly 10 MB (10th append: 9 MB+1 MB=10 MB, not `>`), and the 11th raises. Correct.

### CRITICAL 2 — skip-vs-throw factoring → FIXED (verified)
Lines 95-130 pin exactly one factoring with concrete code: `try-parse-json-line` confines the parse-failure handler and the envelope check + its `error` sit **outside** it; `read-message!` does **not** call `deserialize-message`. The FORBIDDEN-PATTERN box (line 128) explicitly forbids `(with-handlers ([exn:fail? (λ (_) (loop))]) (deserialize-message line))` and explains it would wrongly skip `{"not":…}`. The public-surface comment (61-68) and Decision-style note (130) clarify `deserialize-message` is a standalone convenience with deliberately different (raise-on-non-JSON) semantics. The pinned `cond` correctly branches on the `ok?` flag (`[(not ok?) (loop)] [(jsonrpc-message? val) val] [else (error …)]`) rather than on `val`'s truthiness — this is the right call and matters (see the `false` note below). Part 4's CRITICAL test is retained as the falsifier.

### MEDIUM 3 — `json-object?` sourcing → FIXED, and my prior claim was WRONG
I re-checked the source: `json-object?` is **defined and `provide`d publicly** at `mcp/core/types/types.rkt:73` and re-exported through `mcp/core/main.rkt` (`main.rkt → types/main.rkt → (all-from-out "types.rkt")`). My iteration-001 assertion that it was private to `guards.rkt` was incorrect — I looked only at the guards.rkt internal copy. The revised spec (line 47) now names the public types.rkt binding, explicitly distinguishes it from guards.rkt's private same-named copy, confirms it is already consumed by item 015's `auth.rkt`, and gives a one-line local-define fallback. Boundary-rejection behaviour (line 48) is now spelled out. Resolved.

### MEDIUM 4 — G1 raw-preserve divergence → DOCUMENTED + TESTED
Decision (j) (line 363) documents that `read-message!`/`deserialize-message` return the **raw** read-json jsexpr (nested unknown keys preserved) whereas TS returns the Zod-normalized/stripped object, with the correct rationale (a revision-agnostic framing layer must not drop wire bytes; normalization is M7's job). Part 1 (line 248) pins it with a nested-`unknownNested`-key request that must come back intact, and correctly notes an extra **top-level** key still fails the strict envelope and raises. The envelope reasoning checks out against `guards.rkt` (nested objects are loose; top-level is `.strict()`).

### MEDIUM 5 — embedded-newline framing premise → TESTED
Part 3 (line 261) adds a message whose string value contains `\n` and `\r`, asserts the serialized frame has **exactly one** raw byte 10 (the delimiter) and **zero** raw byte 13, then round-trips it as one message. The encoder-premise note (line 91) marks this VERIFIED. Correct by JSON escaping (control chars are emitted as `\n`/`\r` escapes, never raw bytes), so the byte-count assertions hold regardless of whether the json lib uses short escapes or `\uXXXX`.

### MEDIUM 6 — multibyte-split non-vacuity → FIXED
Part 3 (line 260) locates the `0xC3` lead byte of `é` with `for/first`, asserts it exists (guarding against a future `\uXXXX`-escaping change that would make the test vacuous), and splits at `(add1 lead)` so the two bytes of the codepoint land in different chunks. This genuinely exercises the byte-level-buffering claim instead of a blind quotient that might land between codepoints.

### MEDIUM 7 — scalar-line raise through `read-message!` → TESTED
Part 4 (line 274) adds `check-exn` for `#"42\n"`, `#"true\n"`, `#"\"hi\"\n"`, and `#"null\n"` driven through `read-message!`, with the subtle and correct note that `null` parses to the symbol `'null` (a parse **success** → envelope check → raise), distinct from the empty-line `eof` → skip. This pins the parse-success-vs-failure boundary inside `try-parse-json-line`.

### LOW 8 — edge notes/tests → ADDED
Invalid-UTF-8-in-a-complete-line skipped (line 275; `(bytes 255 254)` → read-json fails → skip, matching TS `JSON.parse` SyntaxError → continue), non-JSON CRLF line skipped (276), `deserialize-message` on non-JSON raises (247), single-shot-over-max (287), max-size-0 boundary (288), empty-chunk no-op (289). The inherited S1 `id:1.0` divergence (TS `z.number().int()` accepts, Racket `exact-integer?` rejects) is documented in Decision (k) with the right guidance: do not test it as "correct," do not work around it in M5e — it is a `guards.rkt` follow-up if it ever matters. Good handling.

---

## New observations from this revision (non-blocking)

### S1 (suggested test) — add `#"false\n"` to the scalar-raise set
JSON `false` → Racket `read-json` → `#f`. That `#f` **collides with `try-parse-json-line`'s `(values #f #f)` failure sentinel** — the first return value is `#f` for both "JSON false parsed successfully" and "parse failed." The pinned `read-message!` resolves this correctly by branching on the `ok?` flag, so the spec's code is right. But the test set pins `true`/`null`/`42`/`"hi"` and omits `false` — which is precisely the one scalar that would distinguish a correct `ok?`-flag implementation from a buggy `(if val …)` one (the latter would wrongly **skip** `false\n` instead of raising). Adding `(check-exn exn:fail? (λ () (read-buffer-read-message! (feed (make-read-buffer) #"false\n"))))` closes the gap and guards the most error-prone scalar. Worth a one-line addition to Part 4 and a mention of the `false`→`#f` collision in the `try-parse-json-line` NOTE. Not bug-causing as specified, hence non-blocking.

### S2 (wording nit) — `try-parse-json-line` NOTE
The NOTE (line 105) says "only eof counts as a failure," which reads slightly loosely against the function's own contract (lines 101-102: failure = "read-json raises, OR returns eof, OR leaves trailing non-whitespace"). In context it means "among non-raising outcomes, only `eof` is a failure; a real parsed value — including a scalar — is success." Harmless, but tightening the phrasing would prevent an implementer from inferring that trailing-garbage is not a failure (the body and Part 4's trailing-garbage test make clear it is).

---

## Testing strategy / prerequisites assessment

The fixture→test mapping is still 1:1 with `stdio.test.ts`, and the net-new coverage (multi-message order, located-lead-byte multibyte split, embedded-newline framing, raw-preserve, scalar-line raise, invalid-UTF-8/CRLF-non-JSON skip, single-shot/zero/empty-chunk overflow boundaries) is thorough and correct. Prerequisites remain appropriately adapted for a pure Racket library (no services, synthetic in-memory byte stream, `raco make`/`raco test` + REPL smoke check). Acceptance criteria are concrete and 1:1 with testable behaviours. The spec is implementation-ready.
