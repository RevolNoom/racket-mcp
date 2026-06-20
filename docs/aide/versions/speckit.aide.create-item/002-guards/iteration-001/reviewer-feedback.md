# Reviewer feedback — Item 002 (JSON-RPC type guards), iteration-001

**Verdict: NEEDS REVISION (one substantive parity bug). Overall 7/10.**

This is a strong, thorough spec. The Worker faithfully incorporated every ground-truth
correction from the prior round: discrimination cited from `schemas.ts` with correct line
numbers, `.strict()` envelopes, `RequestIdSchema = string|int` (with `'null`/fractional/
boolean rejected), error-response `id` OPTIONAL while request/result `id` required, the
id-less-error trap explicitly in the truth table (item.md:291, 331/#5), five predicates with
`is-jsonrpc-response?` as the union, and the no-batch assertion via `module->exports` with a
positive control. The truth tables are genuinely exhaustive and each row is a named check.

I verified the spec's claims against the actual checkout rather than trusting them. Almost
everything holds. **One row is wrong in a way that breaks wire parity** and must be fixed
before this is implementation-ready; the rest are minor.

---

## CRITICAL (must fix) — Inner `error` object strictness diverges from TS

**The spec mandates the Racket guard be STRICTER than the TS reference, which violates the
wire-parity goal (G1/G2).**

The spec asserts, in three places, that an **unknown key inside the `error` sub-object**
makes `is-jsonrpc-error?` return **false**:

- Truth table row (item.md:301): *"unknown key inside `error` `(… 'error (hasheq 'code 1 'message "m" 'foo 1))` → false (error sub-object strict to {code,message,data})"*
- Edge-case list (item.md:377): *"`error.data` present (allowed) vs an unknown 4th key inside `error` (rejected)."*
- Implementation step (item.md:197): *"… ∧ error sub-object keys ⊆ `{code message data}`."*

**This is wrong.** In `schemas.ts:177-190` the inner error object is:

```ts
error: z.object({
    code: z.number().int(),
    message: z.string(),
    data: z.unknown().optional()
})        // <-- NO .strict()
```

Only the **outer** envelope (`JSONRPCErrorResponseSchema`) is `.strict()` (schemas.ts:192).
The inner `error` object is a plain `z.object` with **no** `.strict()`. The repo uses Zod v4
(`zod: catalog:runtimeShared`), whose default unknown-key behavior for `z.object` is to
**strip** unknown keys, not reject. Therefore in TS:

```
isJSONRPCErrorResponse({ jsonrpc:"2.0", id:1, error:{ code:-32600, message:"x", foo:1 } })
  === true     // the unknown `foo` is silently stripped; the message still parses
```

The spec's Racket guard would return **false** for that same value → a guard that rejects a
message the reference SDK accepts. For an inbound-classification guard this is a real
interop divergence: a peer that sends an error with a vendor extension inside `error` would
be misclassified.

**Required change:** drop the inner-error key-restriction. The inner `error` check must be
"`error` is a json-object with integer `code` and string `message`" — and must NOT constrain
the other keys of the `error` sub-object. Specifically:

- item.md:197 — remove `∧ error sub-object keys ⊆ {code message data}`.
- item.md:301 — flip the expectation: unknown key inside `error` → **true** (extra inner
  keys are allowed/ignored, matching Zod strip). Keep a row proving this parity explicitly
  (it's a good anti-regression row, just with the corrected expectation).
- item.md:377 — reword to "`error.data` present (allowed); an extra unknown key inside
  `error` is also allowed (TS strips it, parity)".
- Acceptance criterion item.md:133-135 is fine as written (it only requires int `code` +
  string `message` + optional `data`); just don't let the implementation add an inner
  `only-keys?` on the error object.

> Note the asymmetry the spec must preserve: the **outer** envelope IS strict (unknown
> TOP-LEVEL keys reject — that part of the spec, including the both-result-and-error and
> id+method+result cases, is correct), but the **inner** `error` object is NOT strict.
> The spec currently applies strictness at both levels; only the top level should be strict.

---

## SUGGESTED (non-blocking)

### 1. The optional TS cross-check covers only 3 of 5 predicates — say so

item.md:207-212 proposes cross-checking against `guards.test.ts:6-77`. I confirmed that file
exists (123 lines) and the cited ranges are accurate: the `isJSONRPCResponse` describe block
is lines 6-77 and the union-identity test is lines 63-76 (item.md:312's "mirrors
guards.test.ts:63-76" is correct). **However**, that test file imports only
`isJSONRPCResultResponse`, `isJSONRPCErrorResponse`, `isJSONRPCResponse`, `isCallToolResult`
— it does **not** exercise `isJSONRPCRequest` or `isJSONRPCNotification` at all. So the
"cross-check" can only validate 3 of the 5 Racket predicates against TS fixtures. The spec
already marks this step "optional (recommended)," which is the right call, but it should add
a sentence noting the request/notification predicates have **no** upstream TS fixture and are
therefore covered by the local truth table only. Don't let a reader assume the cross-check
validates all five.

### 2. Inexact-integer id: pin `1.0` explicitly

item.md:370 says "Inexact vs exact id (`1` vs `1.0` vs `1.5`)". Good instinct. JSON `1.0`
parsed by `read-json` yields the flonum `1.0`, for which `exact-integer?` is `#f` → correctly
rejected by `valid-id?`. JSON `1` yields exact `1`. The spec's `valid-id?` =
`(or (string? x) (exact-integer? x))` is correct. Add `1.0` as its own truth-table row
(currently only `1.5` appears at item.md:253); `1.0` is the sneakier case because it "looks"
integral but is inexact. Cheap, high-value row.

### 3. Malformed `params` value-shape is untested and would be wrongly ACCEPTED

The truth tables never feed a `params` that is present but not an object (e.g.
`'params 5`). In TS, `params` is `BaseRequestParamsSchema.loose().optional()` (schemas.ts:102)
— a scalar `params` fails. The spec's helpers only check key membership, not that `params`
is an object, so the implementation as described would ACCEPT `{jsonrpc,id,method,params:5}`
as a request, whereas TS rejects it. Same class as the Critical issue (an accept TS would
reject), but milder. Either (a) add a `params` object-shape check to request/notification
plus a truth-table row, or (b) explicitly DOCUMENT that the envelope guards intentionally do
NOT validate `params` contents (deferred to per-method spec-type validators in items
003-005) and accept the minor divergence. I lean (b) for an envelope-level guard, but it must
be a stated decision, not an accidental gap.

### 4. "string-keyed hash rejected" — record as a deliberate decision

item.md:177 and 318 reject string-keyed hashes as "not the read-json shape." Correct for the
**default** `read-json` output (symbol keys). Be aware `read-json` has an `#:object-key` hook;
since this module documents it operates on the default output, rejecting string-keyed hashes
is defensible. Capture it in Decisions & Trade-offs so a future caller using a non-default
`read-json` knows why their hash is rejected.

### 5. Decisions & Trade-offs is a stub

item.md:544 — "To be updated during implementation." For parity with item 001's bar this
should pre-record the load-bearing decisions already settled in the spec: the four-vs-five
predicate naming reconciliation, the `only-keys?`-as-`.strict()`-replacement choice
(top-level only — see Critical), the inner-error-NOT-strict parity decision once fixed, the
`valid-id?` exact-integer rule, the `params`-not-validated decision (#3), and the
string-keyed-hash rejection (#4). Fine to leave room for execution-time additions.

---

## Things I verified and found CORRECT (no change needed)

- Line numbers: `JSONRPCRequestSchema` 141-147, `JSONRPCNotificationSchema` 152-157,
  `JSONRPCResultResponseSchema` 162-168, `JSONRPCErrorResponseSchema` 173-192, Message union
  194-199, Response union 201, `RequestIdSchema` 136 — all accurate.
- Outer `.strict()` on all four envelopes (147,157,168,192) — accurate; both-result-and-error
  and id+method+result correctly reject.
- Error-response `id` optional (176) vs required elsewhere — accurate; id-less-error → error
  true / notification false trap is in the table (item.md:291, 331 #5).
- `id` = `'null` rejected even for the optional error id (item.md:294) — matches `.optional()`
  meaning absent, not null.
- `result` must be an object; `result:'null`/`result:5` reject; empty `{}` accepted
  (item.md:281, 339-340) — matches `ResultSchema` looseObject.
- `jsonrpc` must `equal?` the string `"2.0"`; `"1.0"`/number/`2` reject — matches
  `z.literal(JSONRPC_VERSION)`.
- No-batch: `grep -rni batch` over `types/` returns zero (re-verified); `module->exports`
  introspection + positive control + `dynamic-require` exn check (item.md:342-366) is the
  right approach.
- Never-raises set (item.md:314-319) and the union-identity assertion over the full fixture
  set (item.md:312) are exactly right and mirror guards.test.ts:63-76.
- All required create-item sections are present (Description, Acceptance criteria,
  Implementation steps, Testing strategy, Dependencies — Item 001/`JSONRPC-VERSION`
  declared, Project-specific adaptations, the CRITICAL Testing Prerequisites block with
  Required Services / Environment Configuration / Manual Validation Checklist / Expected
  Outcomes / Validation Results template, and the Completion Reminder). Only Decisions &
  Trade-offs is a stub (#5 above).
- Anti-vacuous-pass is satisfied: each predicate has ≥1 true and ≥1 false row, the positive
  control guards the introspection, and the drift-detection manual step (item.md:485-487)
  proves the table is live.

---

## Summary

Fix the inner-`error` strictness (CRITICAL) so the guard accepts what TS accepts; that single
change is what gates revision. Make SUGGESTED #3 (malformed `params`) an explicit stated
decision rather than a silent gap, and fill in Decisions & Trade-offs (#5). The rest are
small hardening rows (#2 `1.0`) and clarifications (#1, #4). Once the inner-error parity is
corrected, this is a green, implementation-ready spec.
