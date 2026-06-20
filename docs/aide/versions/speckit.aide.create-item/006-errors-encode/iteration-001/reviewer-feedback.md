# Reviewer Feedback — Item 006: Error hierarchy + ENCODE path (exn → JSON-RPC)

**Reviewer specialty:** testing strategy, prerequisites, edge cases.
**Spec reviewed:** `docs/aide/versions/speckit.aide.create-item/006-errors-encode/iteration-001/item.md`
**Verdict:** Strong, implementable spec. Rating 8/10. `needs_revision: false` — the gaps below
are worth folding in but none would cause an implementer to build the wrong thing or omit a
critical test class. They are robustness additions, not corrections.

---

## What I verified against source (claims that hold)

All load-bearing factual claims in the spec check out against the actual repo — this spec is
unusually well-grounded:

- `spec-2025-11-25.rkt:323` — `(struct jsonrpc-error (code message data) #:transparent)`. ✅
- `:324–325` — `jsonrpc-error/c = (struct/c jsonrpc-error exact-integer? string? (opt/c jsexpr-value?))`. ✅
- `:328–330` — `jsonrpc-error->json` uses `put`, which omits `absent` data. ✅
- `:55–57` — `absent` / `absent?` / `present?`, and **all three are `provide`d** (`:108`). ✅
  This matters: the test's `(absent? (jsonrpc-error-data j))` calls and the encoder's import of
  the sentinel will both resolve. Confirmed importable.
- `jsonrpc-error->json`, `jsonrpc-error?`, accessors, `(struct-out jsonrpc-error)` are all
  exported (`:117`). The test's `only-in` import list is satisfiable. ✅
- `guards.rkt:118–121` — `valid-error-object?` checks `json-object?` + exact-integer `code` +
  string `message`; `:126` `is-jsonrpc-error?` with `only-keys? '(jsonrpc id error)`. ✅
- `constants.rkt` exports every code the spec names; numbers match (`-32603/-32602/-32601/`
  `-32600/-32700/-32002/-32003/-32004/-32042`). ✅
- **The `absent`-as-`data` legality question (the one real trap I went hunting for):** `opt/c`
  is *custom-defined* at `spec-2025-11-25.rkt:269` as `(or/c absent? c)`, NOT the stock
  `racket/contract` `opt/c`. So `(jsonrpc-error CODE MSG absent)` is contract-legal, and the
  raw `#:transparent` struct (no `contract-out`) accepts it at construction. **The encoder's
  fallback `(jsonrpc-error INTERNAL-ERROR (exn-message e) absent)` is therefore valid** — no
  contract violation. The spec's Decisions "data carriage" reasoning (same `eq?` sentinel so
  `put` omits it) is correct. Good catch by the author to mandate the *shared* sentinel; a
  locally-redefined `absent` would silently fail to be omitted by `put` and every absent-data
  test would regress to `'data: <some-symbol>`.

---

## Current coverage summary (testing strategy — already well-covered)

The Testing strategy is genuinely thorough and rare in its rigor. It already covers:

- **Happy path:** each subtype constructs with its stable code; encode copies code/message/data.
- **Predicate hierarchy matrix** (Part 2) — the *boundary* cases that usually get missed:
  `protocol-error?` is `#f` on base and on a sibling auth error; generic exn satisfies none.
  This is the single most valuable test class for a struct-subtype hierarchy and it is present
  and concrete (a literal truth table, 5 values × 4 predicates).
- **The -32603 fallback** is explicitly marked HARD and tested with both a synthetic
  `make-exn:fail` AND a real thrown-and-caught generic exn (`vector-ref (vector) 0`). Excellent
  — testing the real-throw path catches the "I only handled the hand-rolled exn" mistake.
- **Absent-vs-null** (Part 4) — `(check-false (hash-has-key? w 'data))` is the correct
  assertion (not `(check-equal? ... 'null)`), and the present-data case is also covered.
- **Anti-magic / codes-are-constants** — asserts `(= code INVALID-PARAMS)` against the import,
  so a constants.rkt drift fails here. This is the anti-vacuous-pass discipline I look for.
- **Anti-vacuous self-check** — the Manual Validation "Drift detection" item (flip an expected
  value, confirm a FAILURE prints) defends against the silent-pass failure mode of the
  `racket <file>` workaround (which exits 0 even on a failed check).
- **Encode↔guard parity** — wrapping the encoded object in a full envelope and asserting
  `is-jsonrpc-error?` proves the encoded object actually composes into a wire-valid response,
  not just that its fields are typed. Strong.

---

## Missing coverage (Critical)

None. There is no test *class* whose absence would let a broken implementation pass. The items
below are Suggested, not Critical.

---

## Missing coverage (Suggested — robustness)

### S1. The constructor's `data` contract boundary is never tested (only the happy `data`)
Decision §"contract-out vs raw" *recommends* `contract-out` on the three `make-*` so a bad
code/message is caught at construction — but **no acceptance criterion or test exercises a
contract violation**. If the implementer takes the recommended `contract-out` path, nothing
proves it works; if they skip it, nothing notices. Add at least one negative assertion so the
"constructor argument validation" decision is not vacuous:

- `(check-exn exn:fail:contract? (λ () (make-mcp-error "not-an-int" "msg")))` — code must be
  an integer.
- `(check-exn exn:fail:contract? (λ () (make-mcp-error INTERNAL-ERROR 42)))` — message must be
  a string.
- Conversely, the *legal* boundary: `(make-mcp-error INTERNAL-ERROR "x" absent)` constructs and
  `(absent? (mcp-error-data ...))` is `#t` — proving `absent` passes the data contract (this is
  the trap I flagged above; worth an explicit assertion so a future stock-`opt/c` regression is
  caught).

Without these, the spec's own "recommend `contract-out` so a bad code/message is caught" claim
is untested. Note the env caveat: `check-exn` on a contract from a *required* module raises
`exn:fail:contract?` — confirm the predicate, since blame errors are still `exn:fail:contract`.

### S2. `data` carrying a falsy/edge jsexpr — spec mandates it in prose but the matrix is thin
The "Edge cases" section names `#f`, `'null`, `0`, `""` as must-be-present, but only writes one
assertion (`'null`). Make the falsy set explicit so "present-but-falsy ≠ absent" is locked for
each, since these are exactly the values a naive `(if data ...)` truthiness check would wrongly
drop:

- `(make-mcp-error INTERNAL-ERROR "x" #f)` → wire hash HAS `'data` `=` `#f`.
- `(make-mcp-error INTERNAL-ERROR "x" 0)` → wire hash HAS `'data` `=` `0`.
- `(make-mcp-error INTERNAL-ERROR "x" "")` → wire hash HAS `'data` `=` `""`.
- (already specified) `'null` → `'data` `=` `'null`.

The danger here is real: if the encoder ever reasoned about presence via truthiness instead of
`present?`/`absent?`, every one of these would be silently dropped and only `'null`/`0`/`""`/`#f`
would expose it. One `'null` assertion alone does not.

### S3. `data` as an empty/nested jsexpr-object (round-trip of structured data)
The only structured-data test uses `(hasheq 'uri "u")`. Add `(hasheq)` (empty object — must
still be PRESENT, not treated as absent) and a nested object/array
(`(hasheq 'elicitations (list (hasheq 'k "v")))`, mirroring the `-32042` shape item 007 will
decode) to prove the encoder copies `data` by reference without inspecting/flattening it.
The empty-hash case is the sharpest: an empty `hasheq` is falsy-adjacent in a careless `hash-empty?`
guard and must not collapse to `absent`.

### S4. The `exn-message` extraction edge: a non-mcp exn with a *structured* message field
The fallback uses `(exn-message e)`. Spec covers `""` (empty). Also worth one assertion that an
exn whose message contains newlines / non-ASCII is carried verbatim (the boundary must not
sanitize — Decision explicitly says message is preserved and redaction is a future additive
change). One check: `(make-exn:fail "line1\nline2" ...)` → encoded message `=` `"line1\nline2"`.
Cheap insurance that the message is passed through, not reformatted.

### S5. Subtype-as-base encode (the inheritance path through the encoder)
Part 3 encodes a `make-protocol-error` and a `make-mcp-error`, but the matrix should assert
that the encoder's single `(mcp-error? e)` branch handles ALL THREE subtypes identically — in
particular that an **auth** error encodes to its own code via the SAME branch (Part 3 has this
for `MISSING-REQUIRED-CLIENT-CAPABILITY` — good) AND that a protocol error encodes its `data`
through (currently only the *base* `make-mcp-error` carries non-absent data in an encode test).
Add: `(exn->jsonrpc-error (make-protocol-error UNSUPPORTED-PROTOCOL-VERSION "old" (hasheq 'supported (list "2025-11-25"))))`
→ code `=` `UNSUPPORTED-PROTOCOL-VERSION`, data preserved. This is the exact shape 007 decodes,
so it doubles as a 007-seam assertion.

### S6. `make-…-error` with `#:marks` is specified but never tested
The signature includes `[#:marks marks]` and the spec says it "defaults to
`(current-continuation-marks)`". No test exercises the explicit-marks path. Low priority, but
if `#:marks` is in the public signature it should have one assertion that a passed marks value
is the one stored (`(eq? (continuation-mark-set->...) ...)` is awkward; simpler:
`(check-true (continuation-mark-set? (exn-continuation-marks (make-mcp-error INTERNAL-ERROR "x"))))`
to prove the default is populated, plus a note that explicit `#:marks` is an advanced path).
Alternatively, **drop `#:marks` from the public surface** if no caller needs it — an untested
public knob is a liability, and item 007's decode does not need it. Recommend the latter unless
S3/the protocol layer has a concrete use.

---

## Edge cases worth an explicit Decision note (not necessarily a test)

1. **What does `exn-message` return for an exn constructed with a non-string message?**
   `make-exn:fail` is contracted to `string?`, so this is unreachable via the normal path — but
   the encoder's `else` branch takes *any* `exn?`. The contract `(-> exn? jsonrpc-error?)`
   guarantees the input is an exn; `exn-message` on any `exn` is a string. Fine — but the spec
   should state plainly that `exn-message` is total over `exn?` so the `else` branch cannot
   produce a non-string `message` (which would violate `jsonrpc-error/c`). Currently implied,
   not stated.

2. **`exn:break` / non-`exn:fail` exns** (Part B last row). The table says these also map to
   -32603. But `exn:break?` is NOT `exn:fail?` — is it even `exn?`? Yes (`exn:break` is an
   `exn`). The `(-> exn? ...)` contract admits it and the `else` branch handles it. Good, but
   note: catching `exn:break` at a protocol boundary is usually a *mistake* (it's a user
   interrupt, not a handler error). The spec is right to map it to -32603 *if it reaches the
   encoder*, but the Decision should add one line: the boundary (S3) is expected to let
   `exn:break` propagate (not feed it to the encoder); the row documents encoder *totality*, not
   a recommendation to swallow breaks. Otherwise an implementer might wrap break-swallowing into
   S3 by reading this row as guidance.

3. **The non-`exn?` raised value.** Spec correctly punts this to the caller (Decision "what
   counts as fallback", contract is `(-> exn? ...)`). The Part-5/edge test that "passes the
   encoder a value that is `exn?` but not `mcp-error?`" is the right scoping — just confirm the
   test does NOT try to pass a non-exn (e.g. `(exn->jsonrpc-error 42)`), which would be a
   contract violation, not a -32603. The edge-case bullet's wording is slightly ambiguous
   ("a raised non-exn value caught and re-wrapped") — clarify that the *test* always passes an
   `exn`, and the re-wrapping is the boundary's job, tested elsewhere (S3), not here.

---

## Testing prerequisites correctness (your focus #3) — accurate

- **Test path** `mcp/core/test/errors-test.rkt` (NOT `types/test/`) — ✅ correct and emphasized
  three times. Confirmed `mcp/core/test/` does not yet exist and `mcp/core/types/test/` does;
  the spec's "create `mcp/core/test/`, NOT `mcp/core/types/test/`" warning is exactly right and
  catches the most likely mistake (the sibling test dir already lives under `types/`).
- **`raco`-broken workaround** — accurately documented: `raco` silently exits 1; run
  `racket <test-file.rkt>`; rackunit checks at module top level; **silence + exit 0 = pass**,
  but a failed check prints FAILURE and STILL exits 0, so scan output for `FAILURE`/`check-`.
  The instruction to NOT disable the sandbox is preserved. This is correct and the Drift-detection
  self-check defends the exit-0-on-failure hazard. ✅
- **Working dir = repo root** so `mcp/...` collection + relative requires resolve. ✅
- One addition: the pre-flight should also `test -f mcp/core/types/guards.rkt` since the test
  imports `is-jsonrpc-error?` from guards for the parity assertion (Part 4 / Dependencies item
  002). It's listed as test-only but not in the pre-flight checklist.

## Implementability (your focus #4) — high

A competent Racket implementer could build and test this without guessing. The struct field
order (`exn:fail` supplies `message`+`continuation-marks`; subtype adds `code`+`data`), the
constructor signature, the encoder `cond`, the `provide` surface, and the relative import path
(`"types/constants.rkt"`, one dir down) are all spelled out, and the "likely failures" list
(wrong super-field order, undefaulted marks, `'data: 'null`, wrong relative path) is a genuine
gift. The one OPEN decision (import `jsonrpc-error` from 003 vs redefine locally) is well-framed
with a clear recommendation (import) and a fallback constraint (identical struct + sentinel
import). Acceptance criteria are concrete and `=`-checkable.

Two small implementability nits:
- The acceptance criterion's `(require (only-in "types/constants.rkt" ...))` lists nine codes
  but the encoder body only *needs* `INTERNAL-ERROR`; the rest are test-side. The spec should
  clarify that `errors.rkt` itself need only import `INTERNAL-ERROR` (the others are imported by
  the *test*), so a "codes-imported-but-unused" lint in errors.rkt isn't flagged. Minor.
- "re-provide accessors under friendly names `mcp-error-code`/`mcp-error-data`" plus
  `(struct-out exn:fail:mcp)` — note `struct-out` already exports `exn:fail:mcp-code`/
  `-data`. The friendly aliases are additional `(define mcp-error-code exn:fail:mcp-code)`.
  Spec implies this but could state it so the implementer doesn't think `struct-out` alone
  suffices for the friendly names.

---

## Summary

This is a high-quality, source-accurate spec with an exceptionally rigorous test plan for a
pure-data module. The hierarchy-boundary matrix, the HARD -32603 fallback (tested via real
throw), absent-vs-null, anti-magic code assertions, and the drift self-check are all the right
instincts. The gaps are robustness additions — constructor contract-violation negatives (S1),
the full falsy-`data` set (S2), empty/nested `data` (S3), and a couple of Decision-note
clarifications around `exn:break`/non-exn totality. None block implementation. Recommend folding
S1 and S2 in (they defend the two subtlest correctness properties — contract enforcement and
present-but-falsy carriage) but shipping is fine.
