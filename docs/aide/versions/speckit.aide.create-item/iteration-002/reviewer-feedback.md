# Reviewer Feedback — Item 015 iteration-002 (re-review)

**Reviewer focus:** testing strategy, testing prerequisites, edge cases, TS-parity gaps.
**Verdict:** PASS — `needs_revision: false`. All 5 critical (C1–C5) and all 7 suggested (S1–S7) issues from iteration-001 are genuinely closed, not merely claimed. Each fix appears in the pinned design AND a matching acceptance criterion AND an explicit test in the Testing Strategy — the three places that must agree for a fix to survive into the implementation.

I re-verified the load-bearing claims against source rather than trusting the worker's summary (and re-ran the checks I made in round 1).

---

## Per-issue verification (did-not-trust-the-spec)

### C1 — annotations-null crash — CLOSED, verified
- Pinned code now binds `(define annotations (hash-ref md 'annotations #f))` and gates rung 2 on `(hash? annotations)` (lines 59–64). A `null`/non-hash `annotations` falls through to `name` instead of hitting the inner `hash-ref` contract error.
- Prose §70 documents the exact crash mechanism (`read-json` yields `'null`/non-hash → naive inner `hash-ref` raises; TS `?.` tolerates it).
- Acceptance line 202 + test Part 1b assert `(get-display-name (hasheq 'name "n" 'annotations (json-null)))` → `"n"` and the non-hash `"garbage"` case → `"n"`, neither raising. `(require json)` is correctly added to the test (line 277) so `(json-null)` resolves.
- Confirmed the original crash is real and the `(hash? …)` guard is the correct, minimal fix.

### C2 — json->auth-info decode-path adversarial coverage — CLOSED, verified
- §169–172 pin the decode-reject discipline (raise on missing/non-string `token`/`clientId`, non-list `scopes`), with the security rationale (an `#f`-token silently treated as authenticated) made explicit. Implementation note routes required reads through `h-req` and builds via `make-auth-info` so type violations inherit `auth-info/c`.
- Acceptance line 224 + test Part 7 give four `check-exn` cases (missing token, missing clientId, non-string token, scopes-not-a-list). This is exactly the project's decoder-self-reject trap and it is now falsified.

### C3 — make-auth-info/auth-info/c unfalsifiable contract — CLOSED, verified
- §173 mandates the constructor be contracted (via `contract-out`/`define/contract`/explicit guard) and spells out why an unexercised contract on a `#:transparent` struct is indistinguishable from none.
- Acceptance line 219 + test Part 8 require ≥3 `check-exn:fail:contract?` (non-string token, negative expires-at, non-list scopes; optional resource/extra). The `-1` case correctly justifies why the field is `exact-nonnegative-integer?` not bare `integer?`.

### C4 — round-trip vacuity (camelCase) — CLOSED, verified
- §170 + acceptance line 223 + test Part 6 add a literal-wire decode (`(hasheq 'token … 'clientId … 'expiresAt …)` hand-built, NOT via the encoder) asserting equality with the constructed struct. This breaks the encode/decode symmetry and proves the decoder reads `clientId`/`expiresAt`, not kebab-case.

### C5 — Part-4 S1-envelope fixture underspecified — CLOSED, verified against the decoders
- §118–130 pin the exact fixture with valid sub-objects and explain the failure mode (bare-string `clientInfo` crashes `json->implementation`, masking the real assertion).
- **I independently confirmed the pinned fixture passes the S1 decoders:** `json->implementation` (`spec-2026-07-28.rkt:380`) does `(h-req h 'name)` + `(h-req h 'version)` with the rest optional → `(hasheq 'name "c" 'version "1")` is accepted; `json->client-capabilities` (`:398`) is `(client-capabilities h)` (wraps the raw object) → `(hasheq)` is accepted; `protocolVersion` is read by `(h-req h PROTOCOL-VERSION-KEY)` and stored as a string → `"2026-07-28"` is fine. The fixture genuinely exercises trace-key passthrough.
- The spec also correctly instructs the executor to re-confirm `(hasheq)` against `:395-398` before relying on it.

### S1 — two-notions-of-reserved boundary — CLOSED
§114 documents M5c's 8-key set ≠ S1's `request-meta-reserved-keys` (which includes `progressToken`, excludes the 3 trace keys); acceptance line 206 + test Part 2 pin `(check-false (reserved-meta-key? 'progressToken))` with the clarifying comment.

### S2 — accessor key normalization on a PREFIXED key — CLOSED
§109 + acceptance line 208 + test Part 3 pin the string/symbol equivalence on `LOG-LEVEL-META-KEY` (the pipe-quoted-symbol risky case), not just a short word.

### S3 — meta-ref no-default behavior — CLOSED
§110 pins `(meta-ref meta key)` on a missing key → `#f` (probe semantics, no raise); acceptance line 209 + test Part 3 assert both the no-default and explicit-default paths.

### S4 — expiresAt=0 / empty-but-present extra falsy-omit — CLOSED
§166 + §168 pin both; acceptance lines 220/222 + test Parts 3/5 assert `expires-at=0` is expired AND emitted, and an empty `(hasheq)` extra survives round-trip as a present `{}`. Correctly leans on Racket's `0`-is-truthy while still pinning a regression guard.

### S5 — non-string/null title divergence — CLOSED (and honestly relabeled)
§72 + Decisions (b) now explicitly drop the "verbatim TS port" claim for the title rungs and document the deliberate stricter-than-TS `string?` guard; acceptance line 203 + test Part 1b pin `title:(json-null)` → `"n"`.

### S6 — missing-name raises (was unfalsifiable) — CLOSED
§74 + acceptance line 204 + test Part 1b add `(check-exn exn:fail? (λ () (get-display-name (hasheq 'title ""))))`.

### S7 — trace round-trip covered only traceparent — CLOSED
Part-4 fixture now carries `traceparent` + `tracestate` + `baggage` and asserts all three survive (lines 116, 210, 300–305).

---

## Residual (NON-BLOCKING — do not gate on these)

1. **Decode-path bad-`expiresAt` is covered only transitively.** Part 7 rejects bad `token`/`clientId`/`scopes`, but a wire `expiresAt: "100"` (string) or `-1` is caught only because `json->auth-info` builds via `make-auth-info` and inherits `auth-info/c` (C3 tests the contract directly). That is genuinely adequate. If the executor wants belt-and-suspenders, one extra `(check-exn exn:fail? (λ () (json->auth-info (hasheq 'token "t" 'clientId "c" 'scopes '() 'expiresAt "100"))))` would pin the decode→contract path end-to-end. Optional.
2. **Full-`ai` round-trip equality on `extra`/`expiresAt` types** relies on immutable `hasheq` equality and integers surviving the direct hash path (no `write-json`/`read-json` cycle). That holds for the pinned tests; just be aware the suite proves struct-level round-trip, not byte-level JSON serialization (which is correct scope for this item).

Neither blocks. The spec is implementation-ready.

---

## Bottom line
Exemplary revision. Every critical gap is closed in all three layers (pinned design + acceptance criterion + concrete test), the dishonest "verbatim TS" claim was retracted where the port deliberately diverges, and the one fixture I could not take on faith (C5) I verified line-by-line against the actual S1 decoders — it is valid. Approve for execute-item.
