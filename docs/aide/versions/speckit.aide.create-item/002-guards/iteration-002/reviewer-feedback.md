# Reviewer feedback — Item 002 (JSON-RPC type guards), iteration-002

**Verdict: APPROVED. Overall 9.5/10. needs_revision = false.**

The gating inner-`error`-strictness bug is fully and consistently fixed, and all four
non-blocking items from iteration-001 are addressed. I re-verified the changes against the
actual `typescript-sdk/` checkout (not just the spec's claims). This is implementation-ready.

---

## Gating fix — VERIFIED fully and consistently applied

The iteration-001 critical bug (inner `error` object wrongly key-restricted, making the
Racket guard stricter than TS) is corrected with no lingering contradiction. I grepped the
whole document for any surviving inner-error restriction (`sub-object keys ⊆`,
`⊆ {code message data}`, etc.) — **none remain**. Every one of the eleven places that touch
inner-`error` handling now consistently states unknown inner keys are **ALLOWED → true**:

- Schema table (item.md:78): error row now reads `.strict() (OUTER only)` … `extra inner
  keys allowed` … forbidden = `any extra top-level key … (NOT extra keys inside error)`.
- Discriminator subtlety #1 (item.md:98-104): "Strictness is ENVELOPE-LEVEL ONLY and is
  NEVER recursed into nested objects … inner `error` … plain `z.object` WITHOUT `.strict()`
  … Zod v4 strips them."
- Dedicated acceptance criterion (item.md:163-167): `error:{code,message,foo:1}` is
  **accepted**; "must NOT reject it — doing so would be stricter than the reference SDK and
  break G1/G2."
- Implementation step (item.md:249-254): explicit "The `error` sub-object is NOT
  key-restricted … Check only `code`/`message` … ignore any other inner keys."
- Truth-table row (item.md:370): unknown key inside `error` → **true** (flipped from
  iteration-001's wrong "false").
- Ambiguous-shapes #12 (item.md:413-417): contrasts the inner-error extra key (true) with a
  top-level extra key #10 (false) — the exact distinction that was conflated before.
- Edge-case list (item.md:458-459), REPL validation step (item.md:567-569), Expected
  Outcomes invariant (item.md:599-600), and a Decisions entry (item.md:655-663) that
  explicitly records "This corrects the iteration-001 draft, which wrongly key-locked the
  inner `error` object."

I independently confirmed `schemas.ts:177-190`: the inner `error` is `z.object({code,
message, data?})` with **no** `.strict()`; only the outer `JSONRPCErrorResponseSchema` has
`.strict()` (schemas.ts:192). Repo is Zod v4, which strips unknown keys on non-strict
objects. So TS `isJSONRPCErrorResponse({jsonrpc, id, error:{code, message, foo:1}})` is
**true** — exactly what the spec now mandates for the Racket guard. Parity restored.

The asymmetry is captured correctly: **outer envelope strict** (top-level extra keys reject,
both-result-and-error rejects, id+method+result rejects) while **inner `error`/`result`/
`params` non-strict** (their inner keys are unrestricted). This is the right model and the
`only-keys?` helper is correctly scoped to top-level keys only (item.md:226-230).

---

## Non-blocking items from iteration-001 — all addressed

1. **Malformed `params` (was SUGGESTED #3, the most important non-blocker).** Now fully
   handled as the precise parity middle-ground. New `params-ok?` helper (item.md:231-236):
   present `params` must be a `json-object?`, absent is fine, inner contents not validated.
   Truth-table rows added for request (item.md:319-321: object→true, `params:5`→false,
   `params:'null`→false) and notification (item.md:337). Ambiguous-shapes #13 (item.md:418)
   and edge-case list (item.md:460-461) reinforce it. A Decisions entry (item.md:664-670)
   records it as the deliberate "between ignore-entirely and validate-contents" choice.
   **I verified against TS:** `RequestSchema.params = BaseRequestParamsSchema.loose().optional()`
   (schemas.ts:102) and `NotificationSchema.params = NotificationsParamsSchema.loose().optional()`
   (schemas.ts:115) — both loose **objects**, optional, so a scalar `params` fails in TS.
   The spec's cited lines 102/115 are accurate and the behavior matches.

2. **TS cross-check 3-of-5 limitation.** Noted explicitly at item.md:269-274: the fixture
   "only exercises `isJSONRPCResponse`/`ResultResponse`/`ErrorResponse` (and
   `isCallToolResult`) — it has no `isJSONRPCRequest`/`isJSONRPCNotification` cases … only
   covers 3 of the 5 predicates; the request/notification predicates … are covered solely by
   this item's own truth table, which is therefore the authoritative coverage." Matches what
   I found in `guards.test.ts` (it imports only those four guards).

3. **`1.0` inexact-id row.** Added at item.md:315 (request truth table, explicitly false via
   `exact-integer?`), plus edge-case list (item.md:449), Expected-Outcomes invariant
   (item.md:596), Validation-Results line (item.md:625), and the id-type Decision
   (item.md:677-680, noting JSON `1.0` parses to an inexact flonum and is correctly
   rejected). Correct: Racket `(exact-integer? 1.0)` is `#f`, mirroring Zod `.int()`.

4. **Decisions & Trade-offs stub.** Filled with seven substantive, settled decisions
   (item.md:645-687): five-predicate naming map, envelope-only strictness (with the
   iteration-001 correction recorded), `params` handling, jsexpr representation incl. the
   `(hash-ref m 'id 'absent)` absent-vs-`'null` sentinel technique, id type, no-contracts,
   no-batch. This now meets item 001's bar.

---

## Carried-forward correct items (re-confirmed, no change)

All schemas.ts/guards.ts line numbers accurate; outer `.strict()` on all four envelopes;
error-response id optional vs required elsewhere; the id-less-error TRAP explicitly asserted
across all five predicates (item.md:333, 399-403); `id`=`'null`/fractional/boolean rejected;
`result` must be an object; `jsonrpc` must `equal?` the string `"2.0"`; no-batch via
`module->exports` with a positive control and `dynamic-require` exn check; never-raises set;
union identity over the full fixture set (mirrors guards.test.ts:63-76). All required
create-item sections present, including the CRITICAL Testing Prerequisites block. Anti-vacuous
-pass satisfied (each predicate has true and false rows; positive control guards the
introspection; drift-detection manual step proves the table is live).

---

## Two micro-nits (NON-blocking, do not gate; implementer's discretion)

- **n1 — `json-object?` tolerance note (item.md:219-222).** The helper text says "Be
  tolerant: also accept any `hash?` keyed by symbols if you prefer" while the surrounding
  spec firmly rejects mutable/string-keyed hashes. The two are slightly in tension. Since
  `read-json` always yields immutable `hasheq`, I'd drop the "be tolerant" aside and keep the
  strict `(and (hash? v) (immutable? v) (hash-eq? v))` so the string-keyed/mutable-hash
  reject rows (item.md:386-387, 454-456) are unambiguously enforced. Purely editorial.
- **n2 — exact check count.** Expected Outcomes says "≳ 50 individual `check-*`"
  (item.md:608). Item 001 set a precedent of stating exact counts. Not worth a revision, but
  the implementer could pin the exact number in the Validation Results once written, to keep
  the anti-vacuous discipline crisp.

Neither affects correctness or parity. Ship it.

---

## Summary

The single gating bug is fixed correctly and consistently; the inner-vs-outer strictness
model now matches the TS Zod-v4 reference exactly, and the `params` handling I flagged is
resolved with verified TS parity. needs_revision = false; rating 9.5/10 (the 0.5 is the two
editorial micro-nits, which need no re-review). Approved for execute-item.
