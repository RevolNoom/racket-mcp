# Reviewer feedback — Item 009 spec (Stage S1 demo + closeout), iteration 001

**Scale:** 1–10 (10 = ship as-is). **Overall: 6/10. needs_revision: TRUE.**

This spec is *strong* on the high-risk areas the brief flagged — the round-trip/jsexpr trap, the
dropped-key handling, the parity-matrix ambiguity, the progress.md line numbers, and the
demo-location collision are all handled correctly and verified against the live repo. It earns a
solid base score. But it has **one real, code-level blocker**: the malformed-message arm (Arm 3) is
mis-designed and, as sketched, would produce a **vacuously-green test** — exactly the failure mode
the brief asked me to hunt for. I ran the spec's own sketch against the live barrel and fixtures;
the malformed arm does not do what the spec claims. Details below.

---

## What I verified by RUNNING code (not just reading prose)

Racket v8.18 confirmed. From repo root:

- **All 8 barrel names resolve** (`r25:json->initialize-request`, `r25:json->call-tool-request`,
  `r25:json->jsonrpc-error-response`, the three `…->json` serializers, `exn->jsonrpc-error-jsexpr`,
  `make-protocol-error`) and `INTERNAL-ERROR` → `-32603`. The spec's single biggest risk class
  (citing identifiers that don't exist — the thing the item-008 review caught) is **clean here.**
- **All three named fixtures exist** (`initialize-request.json`, `tools-call-request.json`,
  `error-response.json`) with the claimed shapes. `initialize-request.json` does carry
  `"extraUnknownKey": "should-be-dropped-on-params"` in `params` exactly as claimed.
- **No directory collision:** `mcp/examples/`, `mcp/demos/`, and `mcp/core/demo/` all do NOT exist.
  The chosen path `mcp/core/demo/s1-demo.rkt` is genuinely new and out of S9/M15's way. ✔
- **Round-trip arms 1, 2, 4 are correct.** I ran the spec's sketch verbatim:
  - Arm 1 `init vs RAW = #f`, `init vs EXPECT (extraUnknownKey removed) = #t`, idempotent `#t` —
    confirms the spec's central claim that you must compare against the dropped-key `expect`, NOT the
    raw fixture, and that a string/byte compare would be wrong. ✔
  - Arm 2 `tools/call vs RAW = #t`. ✔  Arm 4 `error-response vs RAW = #t`. ✔
- **progress.md line numbers are ACCURATE** against the live file: parity section at `:336`
  ("Current state: **no rows yet (no source).** 📋"), Stage S1 header at `:41` (📋), overview row at
  `:27` (📋), shared test line at `:53` (🚧), acceptance boxes `:56–62` (with `:57` already `[x]`),
  G1 row at `:298` (📋). Every cited line checks out — no stale line numbers. ✔
- **Parity-matrix ambiguity is correctly resolved.** There is indeed no literal §9 table in
  roadmap.md; the only materialized artifact is progress.md's "Parity matrix progression" section.
  The spec's decision to edit `progress.md:336` and NOT invent a roadmap table is right, and the
  `partial` (not `done`) justification matches `roadmap.md:97`. ✔
- **G1 over-claim guard is present and correct** (AC at item.md:344–347, 750–751; Completion
  Reminder §5). S1 is partial G1; the spec explicitly forbids marking G1 ✅. ✔

So 5 of the brief's 6 focus areas are **PASS**. The 6th (the demo's mechanical verification) is
where the blocker lives.

---

## BLOCKER 1 (critical) — Arm 3 malformed-message arm is vacuous as sketched

The spec asserts (item.md:160–168, 301–307, 594–597) that feeding a malformed `tools/call` message
to `r25:json->call-tool-request` inside `with-handlers` proves "item 003's flat contracts reject
malformed input." **This is false for both malformed inputs the spec recommends.** I ran the
decoder against the live barrel:

| Input the spec proposes | Result |
|---|---|
| `(hasheq 'method "tools/call" 'params (hasheq))` — Arm 3's literal sketch (item.md:541), "missing required `name`" | **ACCEPTED** → `#(struct:call-tool-request-params absent absent absent absent)` — does NOT raise |
| `name` of the wrong type (item.md:584's suggested fallback, e.g. `name=42`) | **ACCEPTED** → `#(struct:call-tool-request-params 42 …)` — does NOT raise |

**Root cause (verified in `spec-2025-11-25.rkt`):**
- Line 76: `(define (h-req h key) (hash-ref h key absent))` — "required" field access does **not**
  raise on a missing key; it returns the `absent` sentinel, identical to `h-opt`.
- Line 1139–1140: `json->call-tool-request` is a plain function; `name` flows through `h-req` and
  lands in the struct as `absent` (or `42`) with no validation.
- The `call-tool-request-params/c` contract (line 1127, `(struct/c … string? …)`) that WOULD reject
  a non-string `name` is **not applied by the decoder** — my probe shows `name=42` is accepted and
  returned, so `json->call-tool-request` is not provided via `contract-out` on its result.

**Consequence for the sketch (item.md:540–547):** because the decoder accepts the input, control
reaches the guard line `(error "decoder unexpectedly accepted malformed input")`. The
`with-handlers` then catches *that* exn, and `exn->jsonrpc-error-jsexpr` maps it to `-32603` with
message `"decoder unexpectedly accepted malformed input"`. I ran it: `code: -32603`, `message:
"decoder unexpectedly accepted malformed input"`. **The `module+ test` (item.md:567–574) asserts
only `code == INTERNAL-ERROR` and `message` non-empty — both PASS on this fabricated error.** The
test is GREEN while testing nothing: the "malformed → error" claim is proven by the guard's own
crash, not by any decoder rejection. This is precisely the vacuous-demo failure the brief warned
about; it would ship green and prove nothing.

**The repo already shows the CORRECT mechanism.** `spec-2025-11-25-test.rkt:219–224` rejects a
numeric `name` by explicitly wrapping the decoder output in the contract:
```racket
(check-exn exn:fail?
  (lambda () (contract call-tool-request-params/c
                       (json->call-tool-request-params (hasheq 'name 42 …)) 'pos 'neg))
  "call-tool-request-params/c rejects numeric name")
```
The decoder alone does not reject; `(contract …/c …)` does.

**Required fix (any one, recorded in Decisions):**
1. **Drive rejection through the contract**, mirroring `spec-2025-11-25-test.rkt:219–224`: feed
   `name=42`, then apply `(contract r25:call-tool-request-params/c (r25:json->call-tool-request-params …) 'demo 'demo)`
   inside `with-handlers`. (Requires `r25:json->call-tool-request-params` and
   `r25:call-tool-request-params/c` to be reachable through the barrel — VERIFY, the spec's
   `only-in` list at item.md:211–217 does not currently include the `-params` decoder or the `/c`.)
2. **OR** use an input that genuinely makes the decoder raise on its own. My probe found that
   `params` *missing or non-hash* does raise — `(hasheq 'method "tools/call")` →
   `hash-ref: contract violation … expected: hash? given: 'absent`. This raises a raw `exn:fail`
   (→ `-32603`) but for the wrong reason (the params envelope is absent, not a meaningful "name
   required" rejection) and yields an opaque internal-error message. Acceptable only if Decisions
   states the rejection is "missing params envelope," not "missing/mistyped name."
3. **OR** switch to shape (B) (`make-protocol-error` with `-32600`/`-32602`) AND add a SEPARATE
   inline `with-handlers` check that genuinely exercises rejection via option 1, so the "decoder
   rejects garbage" story is real (the spec gestures at this at item.md:174–176/301–307 but never
   makes it concrete or notes the decoder doesn't self-reject).

**Also required regardless of fix:** the `module+ test` must assert the guard line was NOT reached —
e.g. assert the error `message` is NOT the guard string, or restructure so the guard `(error …)`
cannot be the thing that produces `err-obj`. As written, a future regression that makes the decoder
accept garbage would still pass the test silently.

The spec is partly self-aware here (item.md:582–585 says "if `(hasheq 'method "tools/call" 'params
(hasheq))` is somehow accepted … pick a more clearly-malformed input — e.g. `name` of the wrong
type"). But I verified **`name` of the wrong type is ALSO accepted** by the decoder, so the spec's
own fallback does not work either. The spec must name a malformed input that PROVABLY raises through
the chosen mechanism, not hand the implementer a guess that the brief-level verification shows is
wrong.

---

## ISSUE 2 (minor) — the sketched `jsexpr=?` drops a clause the real comparator has

The spec claims its local `jsexpr=?` has "the same semantics as spec-2025-11-25-test.rkt:45–60"
(item.md:510, 130). The real comparator (verified, line 54) includes
`[(and (number? a) (number? b)) (= a b)]` before the `equal?` fallback; the spec's sketch
(item.md:511–519) omits it. For these three fixtures it happens not to matter (no exact/inexact
numeric mismatch arises — I confirmed all arms pass without it), but the "same semantics" claim is
inaccurate. Either reinstate the `number?` clause for true parity, or drop the "same semantics"
wording. Low priority; not a blocker.

---

## ISSUE 3 (minor) — `raco test` directory-recursion claim is left unverified

The spec repeatedly hedges (item.md:251–256, 308–313) about whether `raco test mcp/core/demo/`
picks up the `module+ test`, and tells the implementer to "verify." That's acceptable as a spec
(outcome-based AC), but the spec mandates a green baseline of "908 tests passed" (item.md:310,
705–706) inherited from item 008 without re-verifying it this session. I did not re-run the full 908
(out of scope for a spec review, and the count is item-008's claim), but the spec should not present
"908" as a re-confirmed fact in its own Test-commands-run block (item.md:794–795) when that block is
a *template to be filled at implementation*. Cosmetic, but the pre-filled "908" in the Validation
Results sketch risks an implementer copying it without re-running. Recommend marking those numbers
as `<to confirm>` placeholders.

---

## What is genuinely solid (do not re-litigate)

- The round-trip arms (1, 2, 4): correct, jsexpr-canonical, dropped-key handled, idempotence
  checked. Verified passing against live fixtures.
- The "identically" trap analysis: accurate and well-argued; matches what I observed
  (`init vs raw = #f`, `init vs expect = #t`).
- Parity-matrix resolution: correct decision, correct line target (`progress.md:336`), correct
  `partial` justification.
- progress.md closeout mapping: every cited line number is accurate; the box→evidence table is
  sound; G1 is correctly kept un-✅.
- Demo location: no collision; new dir; reachable-by-`raco test` caveat handled.
- Fixture reuse: all three fixtures real, correct shapes, already TS-SDK-authoritative.

---

## Verdict

**6/10, needs_revision: TRUE.** One critical blocker (Arm 3 vacuous malformed test — the decoder
does not self-reject either of the spec's proposed malformed inputs, so the demo would prove the
"malformed → error" claim via its own guard crash and pass green). Two minor issues. Everything else
is verified-correct and above the item-008 bar. A single revision cycle fixing Arm 3 (name a
provably-raising malformed input + route it through `(contract …/c …)` per
`spec-2025-11-25-test.rkt:219–224`, and assert the guard line is unreached) would make this an
8–9/10 approve.
