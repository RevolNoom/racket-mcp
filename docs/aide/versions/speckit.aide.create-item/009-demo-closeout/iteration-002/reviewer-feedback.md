# Reviewer feedback — Item 009 spec (Stage S1 demo + closeout), iteration 002

**Scale:** 1–10 (10 = ship as-is). **Overall: 9/10. needs_revision: FALSE (APPROVE).**

The iteration-001 blocker (vacuous Arm 3 malformed test) is **genuinely resolved** — I re-ran the
rewritten Arm 3 against the live barrel, and also ran the fabricated/bypassed variant to confirm the
non-vacuity assertions actually catch a vacuous case. Both minor issues are fixed. Nothing
previously-solid regressed. This spec is ready to implement.

---

## BLOCKER 1 (Arm 3 vacuous test) — VERIFIED FIXED

I did not trust the worker's "I proved it" claim; I re-ran it myself.

**The real Arm 3 now raises through the CONTRACT, not the decoder or a guard.** Ran the exact
sketch (item.md:612–620) against `mcp/core/main.rkt`:
- `(r25:json->call-tool-request-params (hasheq 'name 42 'arguments (hasheq)))` decodes successfully
  (the decoder does not validate — expected), THEN
- `(contract r25:call-tool-request-params/c <decoded> 'demo 'demo)` **raises** a `string?` contract
  violation, caught by `with-handlers`, encoded by `exn->jsonrpc-error-jsexpr`.
- Result: `err-obj` is a `hash?`, `code = -32603` (= `INTERNAL-ERROR`), `message` begins
  `"…: contract violation\n  expected: string?\n  given: 42…"`. All four module+test assertions
  (`hash?`, integer `code`, `code == INTERNAL-ERROR`, non-empty `message`) pass on the genuine
  rejection, and the two non-vacuity assertions pass too: `#rx"contract violation"` matches,
  `#rx"unexpectedly accepted"` does NOT.

**The not-fabricated assertion genuinely cannot be fooled — I proved it can FAIL.** I simulated the
failure mode where the contract somehow accepts and control reaches the guard `(error 's1-demo
"contract unexpectedly accepted malformed name — Arm 3 is vacuous, FIX")` (item.md:620). When the
guard fires, `err-obj`'s message is `"s1-demo: contract unexpectedly accepted malformed name …"`, so:
- `(check-true (regexp-match? #rx"contract violation" msg))` → **FAILS** (no "contract violation" in
  the guard message), and
- `(check-false (regexp-match? #rx"unexpectedly accepted" msg))` → **FAILS** (the guard message
  DOES contain "unexpectedly accepted").

So a vacuous Arm 3 fails **2/2** assertions — exactly the worker's claim, independently confirmed.
The iteration-001 failure mode (test ships green while proving nothing) is now structurally
impossible: `err-obj` can only be bound from the `(contract …)` raise on a genuine rejection, and if
it is ever bound from the guard instead, the regexp assertions trip.

**Design note (not a defect):** the guard `(error 's1-demo …)` is still INSIDE the `with-handlers`,
so it is caught-and-encoded rather than crashing the run. That is fine and arguably cleaner — the
regexp assertions convert it into a clear, named test failure rather than an opaque uncaught
exception. No change needed.

**Both named bindings are reachable through the barrel** (verified live, not trusted):
`(procedure? r25:json->call-tool-request-params)` → `#t`, `(contract?
r25:call-tool-request-params/c)` → `#t`. Both are present in BOTH `only-in` lists
(item.md:266, 568). The spec correctly documents (item.md:189–191) that these two names were NOT in
the iteration-001 list and had to be added.

The spec also correctly warns (item.md:659–667, 680–684) that the implementer must NOT substitute a
"missing name" `(hasheq …)` or a bare-decoder "wrong type" input — both verified silently accepted —
which is exactly the trap that sank iteration-001. The chosen input + mechanism is the right one.

---

## MINOR 2 (jsexpr=? clause) — FIXED

item.md:585 now has `[(and (number? a) (number? b)) (= a b)]    ; spec-2025-11-25-test.rkt:54`,
matching the real comparator's clause and citing the correct line. "Same semantics" claim is now
accurate.

---

## MINOR 3 (pre-filled 908) — FIXED (appropriately, not over-zealously)

The asserted-as-fact "908" is replaced with `<to confirm — item 008 recorded 908>` placeholders in
the Test-commands-run block (item.md:893,905,908), Validation Results (item.md:873), and Expected
Outcomes (item.md:856), plus an explicit note (item.md:889) that these are placeholders to re-run.
The remaining literal "908" mentions (item.md:372,494,795) are in baseline-instruction context that
correctly cites item-008's recorded result as a target to re-confirm, not as this item's own
measured fact — that is the right call, not a miss.

---

## Spot-check: previously-solid parts NOT regressed

- **Round-trip arms 1/2/4** (item.md:588–605,624–628): byte-identical to the iteration-001 sketch I
  already verified passing (init vs EXPECT with extraUnknownKey removed = #t; tools/call + error-
  response vs raw = #t; idempotence). The `number?` clause addition does not change their results.
- **Parity-matrix resolution**: still edits `progress.md:336`, still no roadmap table, still
  `partial` not `done` (item.md:457,482). Intact.
- **progress.md line numbers**: header `:41`, overview `:27`, test line `:53`, boxes `:56–62`, G1
  `:298`, NFR `:324,330` — all still cited; progress.md is untouched so they remain accurate.
- **G1 over-claim guard**: still present (item.md:407–408 "G1 must NOT be marked ✅ here"). Intact.
- **Demo location**: still `mcp/core/demo/s1-demo.rkt`, no collision (mcp/examples, mcp/demos,
  mcp/core/demo all still absent — re-confirmed). Intact.
- **Fixture reuse**: three fixtures still real with claimed shapes. Intact.

---

## Verdict

**9/10, needs_revision: FALSE — APPROVE.** The one critical blocker is resolved with a mechanism I
independently re-ran and confirmed both raises correctly AND fails-loud on the vacuous case. Both
minor issues fixed cleanly. No regressions in the parts marked solid. The remaining 1 point is just
residual implementer-side risk (the `module+ test` count and `raco test` directory-recursion are
correctly left as "verify at implementation" rather than asserted) — appropriate for a spec, not a
defect. Ready to implement.
