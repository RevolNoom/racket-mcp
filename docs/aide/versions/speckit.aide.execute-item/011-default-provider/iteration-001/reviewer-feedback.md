# Reviewer Feedback — Item 011: Default Racket-native provider `from-json-schema` (iteration 001)

**Verdict: APPROVE. Rating 9/10. needs_revision: false.**

Implementation genuinely passes every acceptance criterion with real green tests, verified independently (not trusting the Worker's claims). No bug found across an extensive bug-hunt pass.

---

## 1. Build + tests run independently (not trusted)

- `raco make mcp/core/validators/from-json-schema.rkt` → **exit 0**, no warnings.
- `raco test mcp/core/validators/` → **300 tests passed, 0 failed** (item 011's `from-json-schema-test.rkt` = 234 + item 010's `provider-test.rkt` = 66 = 300, matching the Worker's claim exactly).
- The compile-time `eprintf` lines appear in test output (expected — they are the documented human-facing side effect; the load-bearing oracle is the recorded list, asserted separately).

## 2. Acceptance-criteria audit (AC-by-AC, verified against code+test, not name-matching)

Every AC in the spec is satisfied by genuine code + a genuine assertion:

- **C1 collect-all EXACT counts** — verified exact, not `>=1`: `{type:object,properties:{name,age},required:[name]}` on `{age:"x"}` → `(check-equal? (length es) 2)` (test:128); `{type:string,enum:[a,b]}` on `42` → exactly 2, on `"c"` → exactly 1 (test:199-200). Independently reran: counts are 2/2/1.
- **C2/C3/C5 non-object/non-array/non-string return validation-errors, NOT raise** — guarded in the impl by real `(hash? value)` / `(list? value)` / `(string? value)` checks (impl:329, 351, 360), AND pinned by `check-not-exn` + `rejects?` for every kind incl. the no-`type` self-guard variants (test:132-141, 213-220, 283-285). The structural keywords truly self-guard — no `hash-ref`/`map`/regexp ever touches a wrong-typed value.
- **Double-report guard** — independently verified: `{type:object,properties,required}` on `42` → **count 1** (type fires; structural suppressed via `type-ok?` at impl:344). Same for `{type:array,items}` on a hash → count 1. The no-`type` variant correctly emits exactly one clean "expected object/array". This guard (impl:344, 355) is correct and not over-suppressing: `{type:array,properties}` on a hash still yields 2 (type mismatch + located property error), which is correct collect-all.
- **Deferred-keyword ignore-with-warning uniform across all 5+2** — `deferred-keywords` list (impl:155-156) covers pattern/minLength/maxLength/minimum/maximum/additionalProperties/uniqueItems; the evaluator never references them, so they contribute zero errors; `check-schema-shape` records each (impl:288). All seven exercised uniformly (test:302-332) incl. `check-not-exn` that none is on the reject path.
- **Warnings per-compile via weak `provider-warnings-for` (NOT a single mutable slot)** — impl uses `(make-weak-hasheq)` keyed `handle → (listof symbol?)` (impl:378, 398, 403). N1 two-handle distinctness test (test:334-340) genuinely keys by handle: `h-min` names `'minLength` and NOT `'pattern`; `h-pat` the converse. Reran — distinct. A single-slot impl would fail this; this one passes because it really stores per handle in the weak map. Weak-ness prevents the item-012 long-lived-provider leak.
- **Warnings element type is symbols** — recorded via `(record! k)` on symbol hash-keys and `(string->symbol fmt)` for unknown formats (impl:282, 288); all fixtures assert with `memq 'sym` (test:289, 331, 337, 368, 374).
- **uri recognizer does NOT import net/url** — impl uses a `#rx"^[A-Za-z][A-Za-z0-9+.-]*:"` string regex (impl:177). Confirmed by the portability test (below).
- **symbol/string `required` bridge** — `(hash-has-key? value (string->symbol r))` (impl:339); the silent-total-failure guard is pinned by an explicit ACCEPT test (test:121-125).
- **Located error paths** — `properties` prepends `(symbol->string k)`, `items` prepends integer `i` (impl:335, 353). Nested paths verified: `'(0 "name")` AND `'(1 "name")` both present (test:222-231), `'("color")` for nested enum (test:163-167), `'("data" "items" 0 "name")` deep path (test:238-253).
- **Numeric traps** — `integer = exact-integer?` so `42.0` rejects (impl:201-202, test:89); `number = (and real? rational?)` so `+nan.0`/`+inf.0` reject (impl:198-199, test:97-98). Independently confirmed `42.0` rejects, bignum + `(/ 84 2)` accept.
- **Malformed-shape fail-fast + S-d recursion** — `check-schema-shape` recurses into `properties` values and `items` (impl:265, 268) and raises via `make-protocol-error`; the nested bad-`type` raises at compile (test:499-502). S-c (malformed deferred *value*) chosen as ignore-with-warning and tested (test:504-510), choice recorded in Decisions (e).
- **S-b compile-time recording independent of verdict** — `{type:string,format:ipv4}` on `42` → exactly 1 error, `'ipv4` still recorded (test:365-368). Correct: recording happens in `check-schema-shape` at compile, before any value.

## 3. Bug-hunt (probed beyond the named tests — found nothing)

Independently exercised the highest-risk seams:
- **enum deep `equal?`** — compound `(hasheq 'a 1)` member matches a fresh-but-equal hash; `0` does not match `#t`; `(json-null)` member does not match `#f`. All correct (no `eq?`/`eqv?` membership).
- **format adversarials beyond the TS pair** — `a@@b.com`, `a@`, `@b.com`, `a b@c.com`, `a@b` (no dot) all reject; `a@b.c.d` accepts; date-time without timezone (`2025-10-17T12:00:00`) rejects (regex requires `Z`/offset); month-13 accepts (documented shape-only). The regexes are genuinely restrictive, not passing by luck.
- **No short-circuit where collect-all required** — every sibling/element/property error is appended via `add-all!`/`add!` with no early return.
- **Weak-hash aliasing / leak** — keyed by handle identity (`eq?`), weak; two handles never alias.
- **Warnings recorded at compile, not validate** — N2 test confirms list length is identical after 3 validates as after 0; the closure (impl:393-395) never touches the warnings map.
- **Portability drift non-vacuity** — I injected `(require racket/tcp)` into a scratch copy: the restricted-load test **failed** naming `racket/tcp` ("from-json-schema.rkt transitively imports banned module racket/tcp"), then reverted to green. The walk is real, not vacuous.

## 4. progress.md

- Line 72 `from-json-schema.rkt` flipped 📋→✅ with an accurate, item-011-specific narrative.
- Line 86 "Validator keyword coverage" acceptance box checked `[x]` (this item owns it).
- Line 336 narrative attributes item 011 correctly and keeps `validators/*` at `partial` (correct — full conformance lands with 017/018 + S9).
- No sibling deliverable rows wrongly flipped: `util/schema.rkt` and `shared/*` remain 📋.

## 5. Minor notes (non-blocking — do NOT require revision)

1. **progress.md diff also catches up prior-item rows.** The same diff flips the item-010 `provider.rkt` row (📋→✅) and several Stage-S1 checkboxes (round-trip, decode, restricted-load, demo). These reflect already-shipped prior items (008/010, both ✅ in git history) and are legitimate doc catch-up, not spurious item-011 edits — but they slightly exceed the "THIS item only" instruction. Worth a glance to confirm intended; harmless.
2. **`{required:[]}` (empty, no `type`) on a non-object value rejects.** Because Racket's `'()` is truthy, `(or props req)` enters the structural branch and emits "expected object". The spec only pins empty-required *on objects* (accepts) and required-on-non-object *with members* (rejects cleanly per C2), so this is defensible and consistent with the self-guard rule — not a bug, just an unpinned corner.

Neither warrants a revision cycle.

---

**Bottom line:** Rigorous, faithful implementation of a demanding spec. Real green tests (300), every AC genuinely satisfied, every bug-hunt probe clean, portability drift-check proven non-vacuous. Approved.
