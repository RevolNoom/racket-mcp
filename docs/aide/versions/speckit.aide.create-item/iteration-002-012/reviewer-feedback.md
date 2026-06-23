# Reviewer Feedback — Item 012 (Schema-normalization util, M4) — Iteration 2

**Focus:** verify each iteration-1 key_issue is genuinely closed (decision pinned +
falsifiable test present), then hunt new gaps.
**Verdict:** **APPROVE.** All seven iteration-1 issues are genuinely closed —
each has a pinned decision in the Decisions block AND a falsifiable assertion in
the Part-8 regression table (cross-checked against the actual M3 source). The
two new observations below are an implementability note and a cosmetic nit;
neither lets a bug through. `needs_revision` = false.

---

## Iteration-1 issues — close verification (all CLOSED)

I cross-checked every load-bearing claim against the real M3 source
(`mcp/core/validators/from-json-schema.rkt`, `provider.rkt`), not just the spec
prose. Each fix is real and testable:

1. **Object-root three branches** — CLOSED. 1a array-root `(listof string?)`
   raise, 1b enum-root `(or/c "a" "b")` raise, 1c JSON-Schema `(hasheq 'type
   "array")` raise — all three pinned (Part-8 rows 1a/1b/1c; AC lines 137-138).
   The add-vs-raise rule is now explicitly **form-dependent** (Decisions (c) +
   the root-invariant table lines 93-104). 1b's previously-UNDEFINED branch is
   now a real decision (typeless *contract*-derived root → raise; typeless
   *JSON-Schema* root → add `type:"object"`). I verified the spec's rationale is
   technically correct: item 011 evaluates `enum` independently of `type` via
   `(equal? value m)` against the WHOLE value (from-json-schema.rkt:316-318), so
   an auto-wrapped `{type:"object", enum:[…]}` would indeed reject every object —
   the silent-total-failure the raise avoids is real.

2. **Delegation parity on the POST-normalization wire** — CLOSED. Case 2 now uses
   a **typeless** Form-A input `P = (hasheq 'properties …)` (no root type) and
   compiles `direct` on `(wire nsP)`, NOT raw `P` (Part-3 line 222) — this
   actually exercises normalize-THEN-compile, which the object-rooted `J` passed
   accidentally. Case 2b adds the previously-absent **contract-form
   self-delegation** (`handle-of C` vs `provider-compile prov (wire-of C)`, line
   223). AC line 152 enumerates all three X (object-rooted A, typeless A,
   contract C).

3. **Deferred-keyword Form-A passthrough** — CLOSED. Case 3 asserts (a) wire
   retains `'minLength 3` verbatim, (b) handle accepts `{name:"x"}` (deferred,
   not enforced), (c) `provider-warnings-for` records `'minLength` (lines 202,
   238). Verified against source: `provider-warnings-for` exists
   (from-json-schema.rkt:408) and `format`/deferred keywords are recorded via
   `record!`. The fresh-provider-per-call perf consideration is documented
   (Decisions (j)).

4. **Contract-mapper edge improvisation** — CLOSED. absent-required raises at
   **construction** (case 4, Decisions (a)); single-arm/duplicate `or/c`
   accepted+de-duped, mixed `(or/c "a" string?)` and all-predicate
   `(or/c string? number?)` raise (case 5 + table); `and/c` raises (case 7,
   Decisions (e)). Each has a Part-8 row.

5. **integer 5.0 boundary** — CLOSED. `exact-integer?` pinned, `integer?`
   rejected (Decisions (d)); case 6 pins the `5.0`-rejects assertion. Verified:
   `json-integer?` IS `exact-integer?` (from-json-schema.rkt:201-202), so the
   self-inconsistency the spec describes is real and the pin is correct.

6. **`hash?` over-discrimination** — CLOSED. Detection is now
   `(and (hash? x) (immutable? x) (hash-eq? x))` (Decisions (b)); case 8 raises
   on a string-keyed `equal?`-hash. Verified: item 011 looks up `required` via
   `(hash-has-key? value (string->symbol r))` (line 339) and `properties` by
   symbol key — a string-keyed schema would silently mis-validate exactly as the
   spec warns.

7. **Empty-schema → `validation-ok` not crash** — CLOSED. Case 9 asserts
   `validation-ok?` **explicitly** (not merely no-exn) for both Form-A `(hasheq)`
   and Form-B empty descriptor. Verified: `validation-errors` `#:guard` DOES
   raise on an empty list (provider.rkt:60-63), so the explicit `validation-ok?`
   assertion genuinely falsifies a "build-errors-then-wrap" bug.

---

## New observations (non-blocking)

### N-1 (Suggested — implementability note, not a test gap)

The `or/c` arm-classification (all-literal → `enum`; mixed/all-predicate →
reject; de-dup duplicate members) presumes the implementer can recover the
original arms of an `or/c` value. A compiled `(or/c "a" "b")` introspects only as
`flat-contract? = #t` with `contract-name = (or/c a b)` — there is **no clean
structured API to decompose a compiled `or/c` back into its arms**, so a naive
implementer reaching for `contract-name`-string-parsing will produce something
fragile. The spec's recommended path (a module-defined `object-schema/c` surface
plus identity/eq-based recognition of the small fixed set of supported contract
forms — `string?`, `exact-integer?`, etc. — rather than decompiling arbitrary
contract values) does avoid this, but the spec never states HOW arm
classification is done, and cases 5 + the enum-mapping tests assume it works.
**Recommendation (non-blocking):** add one sentence to Implementation Step 3 /
Decisions noting that supported contracts are recognized by identity/predicate
against a fixed table (not by decompiling arbitrary contract objects), and that
`or/c`/`listof` are recognized by matching the constructor form the caller
supplies — so the implementer does not invent `contract-name`-string parsing.
This is an authoring-clarity gain; the tests are already correct.

### N-2 (Nit — checklist drift, cosmetic)

The "Manual Validation Checklist" and the "Validation Results" template block
still carry a stale **"Dropped-constraint branch verified: `(and/c …)` → pinned
branch (drop+record OR reject) tested"** line (item.md:378, :418). The
drop+record middle path is **superseded** everywhere else in the spec (Decisions
(e): `and/c` is unconditionally rejected). The "(drop+record OR reject)" phrasing
is a leftover from iteration 1 and could mislead the implementer into thinking
drop+record is still a live option. **Fix:** reword both lines to
"`and/c` rejected: `(and/c string? …)` → raises (case 7)." Cosmetic; does not
gate approval.

---

## Testing prerequisites — assessment

Well-adapted and unchanged-in-quality from iteration 1: pure library (no
services), Racket-toolchain row, upstream `raco make` pre-flight for items
010/011, the restricted-load portability walk with the non-vacuity drift check
and the explicit `net/url`-banned guard, and the no-`(module+ test …)` rule that
keeps the walk faithful. Nested-path located-index claim (`'("items" 0 "id")`,
integer index) verified against item 011 (from-json-schema.rkt:352-353 prepends
the integer index for `items`). No prerequisite gaps.
