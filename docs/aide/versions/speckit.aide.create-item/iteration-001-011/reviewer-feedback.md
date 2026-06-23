# Reviewer Feedback — Item 011 (Default Racket-native provider `from-json-schema`), iteration 001

**Reviewer role:** testing strategy / prerequisites / edge cases — adversarial "what breaks a validator?" lens.
**Verdict:** `needs_revision: true`, overall **7/10**. The spec is unusually strong on framing, the port relationship, portability, and the supported-keyword accept/reject matrix. But for a *validator* — where bugs hide in the gaps — there are several places an implementer could ship an untested or silently-wrong code path while still passing every named test. Those are enumerated below as Critical / Suggested, with concrete fixtures.

I verified the cross-artifact anchors before writing this: `(json-null)` is `'null` in this env (the spec's representation claim holds); `make-mcp-error`/`make-protocol-error` are reachable through `mcp/core/main.rkt` (so the reject-policy + fail-fast constructors the spec leans on really exist); `provider.rkt` exports exactly the port + result surface the spec says to `require` (not redefine). Those are all sound.

---

## Current Coverage Summary (what is already well-covered)

- **Supported-keyword accept+reject matrix is genuinely complete** per keyword family (`type` ×7, `properties`, `required`, `enum`, `items`, `format` ×3) with the hard semantics pinned: integer-vs-number (`3.14` rejected by `integer`), `null` vs `(json-null)`, empty `required`, heterogeneous enum incl. `(json-null)` member, empty array, nested `'(0 "name")` / `'("data" "items" 0 "name")` path construction. This is the core of the item and it is well-specified.
- **Deferred-keyword policy is correctly framed** — the "forbidden third option" (silently appearing to enforce) is explicitly called out, and the spec demands one assertion per deferred keyword plus a docs-mention check. The hazard is named, not hand-waved.
- **The `net/url` portability trap is caught** — the spec explicitly bans the `uri` recognizer from reaching for `net/url` and requires a string/regex recognizer. This is the single most likely real bug and the spec flags it twice (AC + Part 9).
- **Fail-fast compile policy** is inherited from item 010 with concrete malformed-schema fixtures and `check-exn`.
- **Restricted-load portability** with a non-vacuity (drift-injection) sub-test is present and rooted at `from-json-schema.rkt` itself.
- **TS-baseline scoping is correct** — the spec correctly identifies that Ajv/cfWorker keyword logic is EXCLUDED and that only the wrapper shape + supported-subset *behaviour* is the oracle; it explicitly lists which TS fixtures are NOT to be used as oracles (`minLength`, `pattern`, `allOf`/`anyOf`/`oneOf`/`not`, etc.). The parity methodology does not overclaim.

---

## Missing Coverage (CRITICAL) — gaps that let an untested validator bug ship

### C1. Multi-error collection vs short-circuit is NOT pinned — and the spec's own examples imply opposite behaviours.

The whole point of the item-010 result shape is a *list* of `validation-error`. Item 010's test even pins a "≥2-error, order preserved" case. But Item 011 **never decides whether the evaluator collects all failures or short-circuits on the first**, and worse, its examples are internally inconsistent:

- AC `items` (line 88) and Part 4 (line 157) say "the **first** failing element's index" → implies short-circuit within an array.
- The `properties` case never says what happens when **two** properties both fail (e.g. `{name:123, age:"x"}` against `{name:{type:string}, age:{type:number}}`). Does the result carry one error or two?

This is a load-bearing semantic for a validator and it is currently unfalsifiable. An implementer who short-circuits and one who collects-all both pass every named test. **Pin it:** choose collect-all OR first-error, document it, and add a test with **a value that violates two sibling keywords at once** asserting the exact error count. Concretely:

- Schema `{type:object, properties:{name:{type:string}, age:{type:number}}, required:[name]}`, value `{age:"x"}` — this fails BOTH `required` (name missing) AND `properties` (age wrong type). Assert the documented count (`= 2` if collect-all; `= 1` + which one if short-circuit). Right now neither the count nor *which* error wins is specified.

Recommendation: **collect-all**, because item 010 built a non-empty *list* and a `'(… 0 …)` mixed-path test precisely to exercise multiple/located errors; a first-error provider makes that list machinery vestigial. But either is acceptable if pinned + tested.

### C2. `properties` / `required` against a NON-object value: undefined behaviour, high crash risk.

Every `properties`/`required` test feeds a hash. But what does `(evaluate {type:object, properties:{…}, required:[name]} 42 '())` do? A hand-rolled evaluator that does `(hash-ref value 'name)` or `(hash-has-key? value …)` on a non-hash **will raise a Racket `exn:fail:contract`**, not return a `validation-errors`. That is a validator crashing on adversarial input — the canonical thing this review exists to catch.

The TS "simple object" fixture only ever feeds objects, so the TS baseline won't surface it. Pin it explicitly:

- `{type:object, properties:{name:{type:string}}, required:[name]}` against `42`, against `"str"`, against `'(1 2 3)`, against `(json-null)` → MUST return `validation-errors` (a clean `type`-mismatch), NOT raise. Add an AC + test. (Note the subtlety: if `type:object` is present it catches this first — but a schema with `properties`/`required` and **no** `type` is legal JSON Schema and the TS `enum`/`allOf` fixtures show schemas commonly omit `type`. So also test `{properties:{name:{type:string}}, required:[name]}` (no `type`) against `42`.)

### C3. `items` against a non-array value, and `enum` evaluation order vs `type` — same crash class as C2.

- `{type:array, items:{type:string}}` against `42` or `(hasheq 'a 1)` → must yield `validation-errors`, not raise (`map`/`for/list` over a non-list raises). Test it. And `{items:{type:string}}` **without** `type:array` against a non-list — does the evaluator attempt to iterate? Pin it.
- `enum` ordering: if a schema has BOTH `type` and `enum` (legal), and they disagree, what's the verdict and how many errors? Not addressed. At minimum test `{type:string, enum:["a","b"]}` against `42` (fails both) and against `"c"` (fails enum, passes type).

### C4. The deferred-keyword policy is documented as "implementer chooses ONE" — but the tests for the two policies are mutually exclusive, so the suite cannot be written until the choice is made, and the spec lets the choice slip to implementation time.

This is a process hazard, not just a coverage gap. Part 6 says "under ignore-with-warning… OR under reject…". If the implementer hasn't *committed* before writing tests, there's a real risk of a half-and-half suite (some keywords warned, some rejected) — which is exactly the "uniform policy" the AC forbids, but no test actually proves *uniformity across all five*. **Add an explicit AC: the test asserts the SAME policy for all five deferred keywords** (e.g. if reject, all five `check-exn`; if ignore, all five accepted+warned) — and add a "no keyword silently rejects while another warns" cross-check. Also: the spec should **state a default** (it recommends ignore-with-warning) and require the iteration to commit in the module docs *before* Part 6 is authored.

Additional unpinned sub-case under ignore-with-warning: **is the warning emitted once at compile, or once per `validate` call?** The spec says "once per compile" in one place (line 45) but the test (line 171) captures stderr around a `validate`-shaped flow. If warnings fire per-validate, a hot path spams stderr. Pin "warn once at compile, not per validate" and test that a handle `validate`d 3× emits the warning **0 additional times** after compile.

### C5. `format` keyword interaction with non-string values and with absent `type` is under-specified.

Line 166 says "format applies only when the value is a string". Good — but it's prose, not an AC, and the crash surface is real: a regex recognizer applied to a number raises. Test:

- `{format:"email"}` (no `type`) against `42` → per the stated rule, `format` is skipped (value not a string) so this **accepts** `42`. Is that the intended verdict? That's surprising (a bare `{format:email}` accepting `42`) but matches the rule. Pin it with a test and a doc note, because an implementer might instead reject "non-string under format" and silently diverge.
- `{type:"string", format:"email"}` against `42` → rejects on `type`, and the `format` recognizer must NOT be run on the non-string (no raise). Test it.
- **Unknown `format` value** (e.g. `{type:string, format:"ipv4"}`): is an unrecognized format a deferred-keyword case (ignore/warn or reject), a fail-fast compile error, or silently accepted? Currently the spec only enumerates the three supported formats and says "other format values fall under the deferred policy" (line 38) — but the deferred-keyword *list* (line 42) does NOT include `format`, so the policy machinery in Part 6 won't cover it. **This is a gap:** add either an AC routing unknown-format through the documented deferred policy, or a fail-fast. Pin a test: `{type:string, format:"ipv4"}` on `"1.2.3.4"`.

### C6. Format recognizer reject-cases are too weak to catch a permissive regex — a known validator failure mode.

The accept/reject pairs (`"https://example.com"` vs `"not-a-uri"`, `"user@example.com"` vs `"invalid-email"`) are the TS fixtures, but they're *easy* cases. A recognizer like `(regexp-match? #rx"@" s)` for email passes both TS cases yet accepts `"@"` and `"a@@b"`. The spec should require **at least one adversarial reject per format** beyond the TS pair, to make the "pragmatic recognizer" actually constrain something:

- email: reject `"a@"`, `"@b.com"`, `"a@b"` (no dot in domain — or document that no-dot is accepted), `"a b@c.com"`.
- uri: reject `"://example.com"` (no scheme), `"example.com"` (scheme-less), accept-or-document `"mailto:x@y.com"` and `"urn:isbn:123"`.
- date-time: reject `"2025-13-01T00:00:00Z"` (month 13) **only if** the recognizer claims to validate ranges — otherwise document it's a *shape* check (`\d{4}-\d{2}-\d{2}T…`) that accepts `2025-13-01`. The point is to **document the recognizer's real boundary** so a downstream caller isn't surprised. Right now "limitations noted in module docs" is asked for but no test pins a single concrete limitation, so the docs can be vacuous.

---

## Missing Coverage (SUGGESTED) — robustness improvements

### S1. Empty / degenerate schemas.
- `{}` (empty schema) — JSON Schema says this accepts everything. Does the evaluator? Test `{}` against `42`, `(json-null)`, `(hasheq)`. An implementer might `hash-ref` a missing `type` and misbehave.
- `{type:"object"}` (object type, no `properties`/`required`) against `(hasheq 'whatever 1)` → accept. And against `(hasheq)` (empty hash) → accept.
- `{required:[name]}` with **no `properties`** — legal; does `required` still enforce presence? Test.

### S2. Annotation keys must not affect verdict (spec says ignore, but only `$schema`/`$id` are TS-tested).
The scope guard (line 73) says `$schema`/`$id`/`title`/`description`/`default` are ignored harmlessly. The TS suite only exercises `$schema`/`$id`/`title`/`description`/`default` on *accepting* values. Add a reject-still-rejects test: `{type:string, title:"X", description:"Y", default:"z"}` against `42` still rejects (annotations didn't suppress the `type` failure). Cheap insurance against an evaluator that treats unknown keys as "pass".

### S3. Unknown / unsupported-but-not-deferred keyword.
What about a keyword that is neither supported, deferred, nor annotation — e.g. `{type:string, multipleOf:2}` or `{type:object, propertyNames:{…}}` or `{$ref:"#/x"}`? The scope guard defers `$ref` etc. but the **policy for a genuinely-unknown keyword** isn't stated. Is it ignored, warned, or fail-fast? Pin it — otherwise the "never silently mis-validate" promise has a hole for keywords outside both the supported and deferred lists.

### S4. `enum` edge cases beyond the TS fixture.
- Empty `enum` `[]` — legal JSON Schema, matches nothing → every value rejects. Test `{enum:[]}` against `"x"` rejects. (A naive `member` over `'()` returns `#f` → rejects, which is correct, but pin it.)
- `enum` with duplicate members `["a","a"]` — accepts `"a"`, harmless; one test to prove no crash.
- `enum` member that is itself an object/array: `{enum:[(hasheq 'a 1)]}` against `(hasheq 'a 1)` — `equal?` on hashes. Confirm `equal?`-membership works for compound jsexprs (Racket `equal?` does deep-compare immutable hashes — but pin it; this is exactly where a provider using `eq?`/`eqv?` would silently break).

### S5. Numeric `type` edge cases.
- `42.0` under `{type:integer}` — the spec *mentions* documenting this (line 136) but doesn't make it an AC with a test. Pin: per the recommended `exact-integer?` rule, `42.0` (an inexact) is NOT an integer → rejects. Test both `42` (accepts) and `42.0` (rejects) and `(/ 84 2)`=42 exact (accepts). This is a genuine JSON-vs-Racket numeric-tower trap.
- Very large integers / bignums under `{type:integer}` and `{type:number}` — `(expt 10 100)` accepts. One test.
- `{type:number}` against `+nan.0`/`+inf.0` — these aren't valid JSON but could arrive; document + pin behaviour (likely accept-as-number or document rejection). Low priority but it's a real "technically-arrives" case.

### S6. Path construction under collect-all (depends on C1).
Part 4 tests a single nested failure producing one path. If C1 resolves to collect-all, add a test where **two elements** of an array fail (`[{name:123},{name:456}]`) and assert **both** paths `'(0 "name")` and `'(1 "name")` are present — proving the index isn't hard-coded to the first failure. Currently only "first failing element" is tested, which a buggy collector that always emits index 0 would also pass.

### S7. Provider statelessness across schemas (mirror item 010's "two independent handles" but for the real evaluator).
Item 010 tested two handles from one provider disagreeing. Item 011 should inherit that: compile `h1` from `{type:string}` and `h2` from `{type:number}` from the **same** `make-racket-native-provider` instance; assert `"hi"` is ok for `h1`, errors for `h2`. Cheap, and catches an evaluator that accidentally closes over module-level mutable state or memoizes the last schema. The spec asserts "handle reusable, no per-call state" (AC line 83) but not "two handles from one provider are independent".

### S8. `required` key representation mismatch (symbol vs string) — a real jsexpr footgun.
In Racket's `json`, object **keys are symbols** (`(hasheq 'name …)`), but `required` is a JSON **array of strings** (`["name"]` → Racket `'("name")`). So checking presence means comparing a string from `required` against symbol keys in the value: `(hash-has-key? value (string->symbol req-key))`. An implementer who does `(hash-has-key? value req-key)` with `req-key` a string **will always report the key missing** (no symbol key equals a string), so EVERY object fails `required`. The happy-path test `{name:"John"}` would catch this *only if* it actually asserts accept — which it does — but the spec should **call out the symbol/string boundary explicitly** as a known trap, and the `properties` sub-schema lookup has the identical hazard (`properties` keys in the schema are also symbols, but you iterate the *value's* symbol keys). Add a doc note + ensure the accept test for a present-required-key is present (it is, line 144) so this can't slip.

---

## Concrete Test Case Proposals (input → expected)

Pinning the highest-value gaps as explicit fixtures:

| # | Schema | Value | Expected | Catches |
|---|---|---|---|---|
| C1 | `{type:object, properties:{name:{type:string},age:{type:number}}, required:[name]}` | `{age:"x"}` | `validation-errors`, count = **documented** (2 if collect-all) | collect-all vs short-circuit unpinned |
| C2a | `{type:object, properties:{name:{type:string}}, required:[name]}` | `42` | `validation-errors` (type mismatch), **no raise** | non-object → crash |
| C2b | `{properties:{name:{type:string}}, required:[name]}` (no `type`) | `42` | `validation-errors` or accept-per-documented-rule, **no raise** | `required`/`properties` on non-hash w/o `type` guard |
| C3a | `{type:array, items:{type:string}}` | `(hasheq 'a 1)` | `validation-errors`, **no raise** | non-array → crash |
| C3b | `{type:string, enum:["a","b"]}` | `42` | `validation-errors` (count per C1 policy) | type+enum interaction |
| C5a | `{format:"email"}` (no `type`) | `42` | accept (format skipped, non-string) — **documented** | format-on-non-string verdict |
| C5b | `{type:string, format:"email"}` | `42` | `validation-errors` on `type`, recognizer **not run** (no raise) | format recognizer crash on non-string |
| C5c | `{type:string, format:"ipv4"}` | `"1.2.3.4"` | per documented unknown-format policy (warn/accept or fail-fast) | unknown format unrouted |
| C6-email | `{type:string, format:"email"}` | `"a@"`, `"@b.com"`, `"a b@c.com"` | `validation-errors` each | permissive email regex |
| C6-uri | `{type:string, format:"uri"}` | `"example.com"` (no scheme) | `validation-errors` | scheme-less uri accepted |
| S1a | `{}` | `42`, `(json-null)`, `(hasheq)` | accept all | empty schema |
| S2 | `{type:string, title:"X", default:"z"}` | `42` | `validation-errors` | annotation suppresses failure |
| S4a | `{enum:[]}` | `"x"` | `validation-errors` | empty enum |
| S4b | `{enum:[(hasheq 'a 1)]}` | `(hasheq 'a 1)` | accept (`equal?` deep) | compound-enum membership w/ wrong equality |
| S5a | `{type:integer}` | `42.0` | `validation-errors`; `42` accepts; exact `(/ 84 2)` accepts | inexact-integer trap |
| S6 | `{type:array, items:{type:object, properties:{name:{type:string}}, required:[name]}}` | `[{name:123},{name:456}]` | both `'(0 "name")` and `'(1 "name")` present (collect-all) | hard-coded index-0 |
| S7 | one provider, `h1={type:string}`, `h2={type:number}` | `"hi"` | ok for h1, errors for h2 | shared mutable/memoized state |

---

## Bottom line

Mechanically thorough on the *named* supported keywords, portability, and TS scoping — but a validator's bugs live in the **non-object-under-object-schema crash (C2/C3)**, the **collect-all-vs-short-circuit ambiguity (C1)**, the **format/non-string and unknown-format holes (C5)**, and **permissive recognizers (C6)**. Each of those is currently a code path an implementer can ship untested while passing every listed assertion. Resolve C1–C6 (pin the semantics + add the fixtures above) and this becomes a spec under which a validator bug genuinely can't sneak through. Hence `needs_revision: true`.
