# Reviewer Feedback — Item 011 (Default Racket-native provider `from-json-schema`), iteration 002

**Reviewer role:** testing strategy / prerequisites / edge cases — adversarial "what breaks a validator?" lens.
**Verdict:** `needs_revision: true`, overall **8/10**. Iteration 001's six critical gaps (C1–C6) and all eight suggested items (S1–S8) are genuinely resolved — not merely named, but pinned with explicit ACs and concrete fixtures using exact assertions (`(= 2 (length …))`, `check-not-exn` on every crash-class value). This is a strong revision. It does **not** pass yet because the new machinery the revision introduced — the **warnings accessor** — collides with item 010's frozen `compiled-validator` struct in a way the spec leaves unresolved, and that hole is large enough that an implementer could ship an untested or contract-violating warnings surface. One more turn fixes it.

I verified the iteration-001 resolutions against the actual fixtures and checked item 010's shipped `provider.rkt` surface directly (not from memory).

---

## Iteration-001 critiques — resolution audit (all genuinely closed)

| # | iter-001 gap | iter-002 resolution | Genuinely resolved? |
|---|---|---|---|
| C1 | collect-all vs short-circuit unpinned | Committed COLLECT-ALL directive (line 44); AC 117; fixture asserts **exactly 2** via `(= 2 (length …))` for `{age:"x"}` and `{type:string,enum}` on `42` | YES — exact count, not `>=1` |
| C2 | non-object → contract crash | Type-guard semantics (lines 40–42); AC 121; Part 2 line 202–203 wraps every value (`42`/`"str"`/list/`(json-null)`) in `check-not-exn` AND the no-`type` variant | YES — `check-not-exn` on each |
| C3 | non-array → iteration crash | AC 126; Part 4 line 219 `check-not-exn` + no-`type` variant + type+enum counts (42→2, "c"→1) | YES |
| C4 | deferred policy slips / non-uniform / warn cardinality | Committed ignore-with-warning (lines 52–62); AC 130 asserts uniformity (`check-not-exn` all five) + warn-once (3 validates → **0** extra) | YES — falsifiable |
| C5 | format-on-non-string + unknown format | Lines 46–48; AC 129; fixtures line 236–238 (no-op accept on `42`, `ipv4` routed through warn policy) | YES |
| C6 | permissive recognizers | Lines 84–93; AC 128; adversarial rejects per format + one documented limitation each (incl. the clever month-13 *accept* to pin the shape-only boundary) | YES |
| S1–S8 | degenerate schemas, empty enum, compound-enum `equal?`, `42.0`, symbol/string keys, annotations, statelessness | All promoted to ACs 119/124/131–134 + fixtures Parts 2,3,6b | YES |

The collect-all/short-circuit distinction (C1) and the leaf-vs-sibling clarification (line 44: "a single scalar leaf MAY stop at first keyword, but siblings/elements/properties are ALL collected") are exactly right and resolve the ambiguity I flagged. The C6 month-13 case is a genuinely good test-design move: it makes the recognizer's documented limitation *falsifiable* rather than letting the docs be vacuous.

---

## Missing Coverage (CRITICAL) — the new gap the warnings machinery introduces

### N1. The warnings accessor has no defined home, because item 010's `compiled-validator` is a frozen single-field struct that item 011 is forbidden to redefine.

This is the central unresolved issue. I checked the shipped port: `mcp/core/validators/provider.rkt` defines

```racket
(struct compiled-validator (validate-proc) #:transparent)   ; line 77 — ONE field
```

and `provider-compile` (the generic) returns a `compiled-validator?`. Item 011's scope guard (line 105) says **"Do NOT redefine the result structs ... `require` them from `provider.rkt`"**, and AC 116 says `provider-compile` returns **"a `compiled-validator?` handle (item-010 type)"**. So the handle the test receives is item-010's struct, which **structurally cannot carry a warnings field**. Yet:

- AC 130 / 129 / 131 require the test to **read recorded warnings off the handle** ("recorded on the handle / a warnings list the test reads").
- Part 5 line 238 asserts "the recorded warnings list (see Part 6) contains `ipv4`".
- Part 6 line 247 asserts "the warnings accessor on **that handle**/provider names the deferred keyword".
- Expected Outcomes line 380 says the module exports "the ignored-keyword warnings accessor".
- Implementation Step line 154 only hand-waves: *"expose it on the provider/handle via a provided read-only accessor, or have `provider-compile` also return it; pick one and record in Decisions. ... a separate `compiled-validator-warnings`-style accessor is acceptable."*

But a `compiled-validator-warnings` accessor **is impossible** without either (a) redefining item-010's struct (forbidden), or (b) item 010 having shipped a warnings field (it did not — it's `(validate-proc)` only). And `provider-compile`'s generic contract returns a bare `compiled-validator?`, so it cannot "also return" a second value without changing the port's arity (also forbidden — "NO new port surface", line 108).

The spec offers three incompatible options without choosing, and at least one of them is unimplementable against the frozen port. **An implementer will discover this only at code time** and may resolve it by silently widening the port, leaking the validate closure, or inventing an untested side-channel. Pin ONE concrete mechanism that is actually compatible with item 010's shipped struct. The viable options, ranked:

1. **(Recommended) Warnings live on the PROVIDER struct, not the handle, and compile is the recording moment via mutation or a fresh provider.** Since `provider-compile` is a method *on the provider*, the `racket-native-provider` struct (item 011's own, freely definable) can carry a `(warnings)` box/field that `provider-compile` fills, with a provided `racket-native-provider-warnings` (or `provider-last-warnings`) read-only accessor. But then **statelessness (S7) and the handle-independence story collide**: if two schemas are compiled from one provider, a single provider-level warnings field is overwritten by the second compile — so the test reading warnings after compiling two different schemas reads the wrong set. This must be pinned: either (i) warnings are keyed per-compile and the accessor takes the handle, or (ii) the test only reads provider-warnings immediately after a single compile. Currently **untested and unspecified** — and it directly contradicts the S7 "two handles from one provider" test that compiles twice.
2. **Wrap the handle.** `provider-compile` returns the item-010 `compiled-validator` (so AC 116 holds), but item 011 *additionally* exposes a separate value/struct (e.g. its own `(compiled-result handle warnings)` returned by a NON-port helper like `make-racket-native-provider`+`compile-with-warnings`) — but this fragments the API and the test's `(provider-compile P schema)` calls would not surface warnings. Messy; flag as discouraged.
3. **Warnings on a weak hash / parameter keyed by the handle.** Over-engineered for this; mention only to reject.

**Required:** choose mechanism (1) with a per-compile keying that survives the S7 two-compile test, write it as an AC, and add a fixture: compile `h1` (with `minLength`) then `h2` (with `pattern`) from the SAME provider, and assert `h1`'s warnings name `minLength` and `h2`'s name `pattern` — **proving warnings are not a single overwritten provider-level slot.** Without this fixture, a provider that stores warnings in one mutable field passes every *current* warnings assertion (each reads right after its own compile) while being broken for any real two-schema caller (item 012 compiles many).

### N2. Warn-once cardinality (C4) is asserted via stderr capture, but the recorded-list path and the stderr path can disagree — and only one is pinned per assertion.

Line 58 commits to warning **both** to stderr (`eprintf`/`log-warning`) **and** recording on a list. Line 249 asserts warn-once by capturing stderr (`current-error-port` → string) for the compile, then 3 validates → 0 extra. Good for the stderr channel. But the **recorded-list** channel's cardinality is never pinned: a buggy implementation could append to the warnings list on every `validate` (growing it) while only `eprintf`-ing at compile. The "equivalently, assert the recorded warnings list does not grow across validates" (line 249) is offered as an *alternative* ("equivalently"), not a conjunction. **Require BOTH:** stderr emits once at compile AND the recorded list has the same length after 3 validates as after 0. These are two independent channels with two independent off-by-one bugs; test each.

### N3. `log-warning` vs `eprintf` choice interacts with the stderr-capture test — the capture method must match the emission method or the warn-once test is vacuous.

Line 58 offers "`log-warning`/`eprintf`" as the emission mechanism and line 249 captures via `(parameterize ([current-error-port (open-output-string)]) …)`. **`log-warning` does NOT write to `current-error-port`** — it writes to the logging system (a `log-receiver` / the `PLTSTDERR` sink), so a `current-error-port` capture of a `log-warning`-based implementation captures **nothing**, and the "exactly one warning" assertion passes vacuously (zero captured = not "more than one"). This is a real trap: the test as written only works if emission is `eprintf` (or `(fprintf (current-error-port) …)`). **Pin the emission mechanism to `eprintf`/`fprintf` to `current-error-port`** (so the capture is valid), OR if `log-warning` is chosen, require the test to attach a `make-log-receiver` and count events there. As written, an implementer choosing `log-warning` gets a green-but-meaningless warn-once test. Given the recorded-list is the primary machine-readable channel anyway, the cleanest fix is: **make the recorded-list assertion the load-bearing warn-once check (count the list), and treat stderr as a documented-but-not-cardinality-tested side effect.**

---

## Missing Coverage (SUGGESTED) — robustness, lower priority

### S-a. Deferred keyword with a co-occurring SUPPORTED failure under collect-all: does the ignored keyword leak a phantom error or get double-counted?
C1 (collect-all) and C4 (deferred ignored) now interact and the interaction is untested. `{type:"number", minimum:0}` on `"x"` (a string): `type` fails (1 error), `minimum` is ignored (0 errors). Assert the count is **exactly 1**, not 2 — i.e. the ignored keyword contributes **zero** errors even while a sibling supported keyword fails. A buggy collector that emits a "minimum: skipped" pseudo-error would push the count to 2. Cheap, pins the C1×C4 corner.

### S-b. Unknown-format under collect-all + a real type failure.
`{type:"string", format:"ipv4"}` on `42`: `type` fails (1), unknown format `ipv4` is ignored (warned, 0 errors). Assert count = 1 AND the warnings list still records `ipv4` even though the value failed `type`. Pins that warning-recording is a *compile-time* property independent of the validate verdict (it should be — warnings are recorded at compile, before any value is seen).

### S-c. Malformed deferred-keyword *value* policy is left as "pick whichever" (line 273) but not required to be tested.
Line 273 says `(hasheq 'minLength "three")` (a non-integer minLength) MAY be malformed-raise OR ignore-warn, "pin whichever is chosen." That's the right freedom, but the spec should require the **chosen** branch to have a test. As written, an implementer can choose without testing, leaving a `provider-compile` path (malformed-deferred-value) entirely uncovered. Add: "the chosen behaviour for a malformed deferred-keyword value is asserted (`check-exn` if raise, or accept+warn if ignore)."

### S-d. `properties` whose sub-schema is itself malformed — when is it caught, compile or validate?
AC 137 fail-fasts on `(hasheq 'properties 5)` (properties not an object). But a `properties` that IS an object-of-subschemas where one *sub*-schema is malformed — e.g. `{properties:{name:{type:"stringg"}}}` (bad nested type) — is it caught at compile (recursive `check-schema-shape`) or only when a value descends into `name`? Part 8 only tests top-level malformation. Pin whether `check-schema-shape` recurses into sub-schemas. Recommended: recurse (fail-fast on any malformed sub-schema at compile), and test `{type:object, properties:{name:{type:"stringg"}}}` raises at compile. Otherwise a malformed deep sub-schema hides until a value happens to reach it.

### S-e. `enum` co-occurring with `properties`/`items` (enum of objects nested in a structural schema).
S4 tests a top-level compound enum member. Not tested: `{type:object, properties:{color:{enum:["red","green"]}}}` on `{color:"blue"}` → the enum failure path must carry the `'("color")` path segment. One fixture confirms enum errors get located like type errors do (a collector might emit enum errors with a root path).

### S-f. Empty `properties` object `{}` vs absent `properties`.
S1 covers `{type:object}` (absent properties). Add `{type:object, properties:{}}` (present-but-empty) on `{anything:1}` → accepts (empty properties constrains nothing; `additionalProperties` is deferred so extras are fine). Distinguishes "no properties key" from "empty properties hash" — a `hash-ref` with no default would crash on the absent case if the code assumes presence.

---

## Concrete Test Case Proposals (the must-add fixtures)

| # | Schema(s) | Value | Expected | Catches |
|---|---|---|---|---|
| **N1** | compile `h1={type:string,minLength:3}` then `h2={type:string,pattern:"x"}` from SAME provider | — | `h1` warnings name `minLength`; `h2` warnings name `pattern` (NOT both, NOT overwritten) | single mutable provider-level warnings slot |
| **N2** | `h={type:string,minLength:3}`, validate 3× | `"ab"` | recorded warnings list length identical after 0 and 3 validates AND stderr emitted once | per-validate warning append (list channel) |
| **N3** | (spec-level) pin emission to `eprintf`/`current-error-port`, or count via `log-receiver` | — | warn-once test is non-vacuous | `log-warning` + `current-error-port` capture = always-green |
| S-a | `{type:number, minimum:0}` | `"x"` | exactly **1** error (type only; minimum contributes 0) | phantom error from ignored keyword |
| S-b | `{type:string, format:"ipv4"}` | `42` | exactly 1 error (type); warnings still record `ipv4` | warning recording coupled to verdict |
| S-c | `{type:string, minLength:"three"}` | (compile) | per documented choice — `check-exn` OR accept+warn (must test the chosen one) | untested malformed-deferred-value path |
| S-d | `{type:object, properties:{name:{type:"stringg"}}}` | (compile) | per documented recursion choice (recommend raise at compile) | malformed deep sub-schema hides until reached |
| S-e | `{type:object, properties:{color:{enum:["red","green"]}}}` | `{color:"blue"}` | `validation-errors`, error path `'("color")` | enum errors not located |
| S-f | `{type:object, properties:{}}` | `(hasheq 'anything 1)` | accept (no crash on empty properties hash) | hash-ref assuming properties present |

---

## Bottom line

The keyword/value/edge-case surface is now genuinely airtight — C1–C6 and S1–S8 are pinned with exact counts and `check-not-exn` crash guards, and I could not find a supported-keyword or wrong-typed-value path an implementer could ship untested. The remaining risk has moved entirely into the **warnings side-channel the revision added**: it has no defined, port-compatible home (N1), its two emission channels have independent untested cardinality bugs (N2), and the stderr-capture test is vacuous under a `log-warning` implementation (N3). N1 in particular is a genuine design hole — the spec lists three options, at least one is unimplementable against item 010's frozen struct, and the S7 two-compile test actively contradicts the simplest (single mutable slot) reading. Resolve N1–N3 (pin one port-compatible warnings mechanism + the two-compile warnings fixture + a non-vacuous warn-once channel) and fold in S-a/S-b (the C1×C4 interaction), and this is ready. Hence `needs_revision: true`, but narrowly — this is an 8/10 one-issue-cluster revision, not a re-architecture.
