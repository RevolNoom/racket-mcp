# Reviewer Feedback — Item 012 (Schema-normalization util, M4)

**Focus:** testing strategy, testing prerequisites, edge cases.
**Verdict:** Strong spec — among the most thorough in the queue. The dual-form
equivalence is pinned correctly (asserts agreement on *both* accepts and
rejects, which kills the map-to-`(hasheq)` bug), the per-form wire assertion is
correctly separated from validation behaviour, the delegation-parity and
injection-seam tests are well-conceived, and the portability walk includes a
non-vacuity drift check. The gaps below are real but mostly narrow:
a few edge cases at the **object-root boundary** and the **delegation-parity
schema identity** are load-bearing and currently unfalsifiable. `needs_revision`
is set true on the strength of issues #1 and #2 — both let real bugs through.

---

## Missing Coverage (Critical)

### 1. Object-root rule has THREE untested branches, and one is undefined behaviour

The spec tests only two object-root reject paths: a non-object **JSON-Schema**
root (`{type:"string"}` → raise, Part 5) and a **scalar contract** root
(`string?` → raise, Part 5). But the contract mapper produces several other
root shapes that hit the object-root normalizer, and the spec pins none of them:

- **(a) Array contract at root.** `(listof string?)` at the root maps to
  `(hasheq 'type "array" 'items …)`. That is an *explicit non-object root
  `type`* → per the TS rule (`standardSchemaToJsonSchema`: throws when
  `result.type !== undefined && result.type !== 'object'`) it MUST raise. The
  spec's mapper table happily produces it and no test asserts the raise. A naive
  implementer will `ensure-object-root` it and either raise (correct, untested)
  or — worse — wrap it. **Pin: `(check-exn exn:fail? (λ () (normalize-schema (listof string?))))`.**

- **(b) Enum contract at root — UNDEFINED in the spec.** `(or/c "a" "b")` at the
  root maps to `(hasheq 'enum '("a" "b"))` — a schema with **no `type` key at
  all**. The spec's `ensure-object-root` rule is "add `type:"object"` when the
  root `type` is absent." Mechanically that turns a root enum into
  `(hasheq 'enum '("a" "b") 'type "object")` — silently advertising "an object"
  for what the author wrote as a two-value enum, and the handle would then
  reject every string (it's not an object). This is the exact silent-correctness
  hole the no-equivalent policy exists to prevent, reintroduced at the root.
  The TS reference *does* blindly add `type:"object"` to a typeless root (it's
  designed for Zod discriminated unions emitting `{oneOf}`), but a root enum is
  not a tool input shape. **The spec must DECIDE: does a typeless non-object
  contract-derived root (enum) raise, or get wrapped? Pin the chosen branch.**
  My recommendation: raise for the contract form (an MCP tool input must be an
  object; a root enum has no object semantics), while still adding `type:"object"`
  for a *JSON-Schema* input that omits type (TS parity for the `{oneOf}` case).
  Note this makes the add-vs-raise rule **form-dependent**, which the spec
  currently does not acknowledge.

- **(c) JSON-Schema root with explicit `type:"array"` (or any non-object
  non-string).** Part 5 only tests `{type:"string"}`. The TS check is generic
  (`!== 'object'`), so `{type:"array"}`, `{type:"number"}`, `{type:"null"}`
  should all raise. One representative non-string case (`{type:"array"}`) should
  be pinned so the test isn't accidentally string-specific.

### 2. Delegation-parity test does not pin WHICH schema the direct provider compiles

Part 6 / AC line 118 say the handle's verdicts must equal
`(provider-compile (make-racket-native-provider) <the-same-wire-schema>)`. For
the JSON-Schema `J` chosen in Part 4, `J` already has an object root, so
`direct` compiled on raw `J` happens to match. But the load-bearing claim is
"compiled on the **post-normalization wire schema**," not the raw input. If an
implementer writes `(provider-compile prov J)` (raw) instead of
`(provider-compile prov (wire-of J))`, the test passes for object-root inputs
and silently fails to cover the normalization-then-compile path — precisely
where a root-add bug would hide. **Pin explicitly: `direct` is compiled on
`(wire-of X)`, and add a delegation-parity case for an input that is NOT already
object-rooted (e.g. `(hasheq 'properties …)` with no root type) so the
"normalize THEN compile" identity is actually exercised.** Same for the contract
form: parity must be vs `(provider-compile prov (wire-of C))`, and the spec
never states a contract-form delegation-parity case at all — only the
dual-form *cross*-equivalence (C-vs-J). A contract whose wire schema is correct
but whose handle was compiled on a *different* schema than its own wire would
pass dual-form (if J matched the bug too) but is caught only by an explicit
`handle-of C` vs `provider-compile prov (wire-of C)` assertion. Add it.

### 3. Provider-warnings / weak-map interaction with handle reuse and many-compiles is untested

Item 011's provider keys a **weak** `handle → ignored-keywords` map and the
module docs flag that "item 012 compiles many schemas through one provider."
The util's default path creates a *fresh* `(make-racket-native-provider)` per
`normalize-schema` call (AC line 119: "omitting `#:provider` uses a fresh
`(make-racket-native-provider)`"). That means: (a) every `normalize-schema`
allocates a new provider — fine, but untested that two `normalize-schema` calls
don't share/leak a provider; and (b) if the wire schema contains a **deferred
keyword** (it never should from the contract mapper, but a JSON-Schema *input*
can carry `minLength`, `pattern`, etc.), `provider-compile` emits a stderr
warn-once and records it. The spec never tests that a JSON-Schema input
carrying a deferred keyword (i) still normalizes, (ii) advertises that keyword
in the wire schema as-is (the util must NOT strip it — it only adds the object
root), and (iii) the handle ignores it per item 011's policy. **This is a
realistic author input** (a hand-written schema with `minLength`) and the util's
"advertise as-is" contract is unverified for it. **Pin: a JSON-Schema input
`{type:"object", properties:{name:{type:"string", minLength:3}}}` → wire schema
retains `minLength:3` (advertised) AND the handle accepts `{name:"x"}` (deferred,
not enforced).** This is the single most likely real-world surprise.

---

## Missing Coverage (Suggested)

### 4. `required` for a field NOT in `properties` (contract mapper invariant)

The object-shape helper takes `(hash 'field contract …)` + `#:required '(…)`.
What if `#:required '(ghost)` names a field absent from the field hash? Two
behaviours possible: emit `required:["ghost"]` with no matching property (the
provider would then reject every object for missing `ghost` — a footgun), or
raise at `object-schema/c` construction. The spec is silent. **Pin the chosen
behaviour** — I'd argue `object-schema/c` should raise on a required key with no
field (mirrors item 010/011's "make the invariant falsifiable via a guard").

### 5. Duplicate / degenerate enum and single-element forms

- `(or/c "a")` (single literal) → `{enum:["a"]}` — does the mapper require ≥2
  arms, or accept one? `or/c` with one arm is legal Racket.
- `(or/c "a" "a")` — duplicate literals. Provider uses `equal?` membership so
  harmless, but the emitted wire schema would carry `["a","a"]` — worth a note.
- **Mixed-form `or/c`**: `(or/c "a" string?)` — a literal mixed with a predicate.
  This is NOT a clean enum (one arm is a type, not a datum). Does it map to enum
  (wrong), raise as no-equivalent, or map to something else? **This is a real
  ambiguity in "or/c of literal datums" — the table says "over literal datums"
  but never tests the mixed case that violates that precondition.** Pin a raise.

### 6. Non-string scalar values inside enum / the integer-vs-number S5 decision

AC line 46 defers `exact-integer?` vs `integer?` to "pin which (S5 note)" but
the test plan never asserts the boundary that distinguishes them: does
`{n: exact-integer?}` accept `5.0` (a float that is integer-valued)? Item 011's
`json-integer?` is `exact-integer?`, so `5.0` rejects. If the contract uses
`integer?` (which accepts `5.0` in Racket), the mapping to `{type:"integer"}`
would create a **contract/wire divergence**: the contract accepts `5.0`, the
derived handle (via provider) rejects it. **This breaks dual-form equivalence
for the contract's own self-consistency.** Pin `exact-integer?` AND add a test
that `5.0` rejects through the integer field handle, documenting why `integer?`
is NOT used (it would diverge from the provider).

### 7. Empty `or/c` / `and/c`, and `and/c` generally

The mapping table has no row for `and/c`. `(and/c string? …)` is a common flat
contract. Is it no-equivalent (raise) or does the mapper try the first
recognizable arm? Spec should explicitly state `and/c` is **out of the supported
table → raise** (no clean single-keyword JSON-Schema analogue), and pin it,
otherwise an implementer may improvise.

### 8. Non-`hasheq` hash inputs (hash vs hasheq, immutable vs mutable)

Discrimination is "`hash?` → JSON-Schema branch." But `hash?` is true for
`hasheq`, `hash` (equal-based), AND mutable hashes. A mutable hash or an
`equal?`-keyed hash with **string keys** (not symbol keys) would pass `hash?`,
take the JSON-Schema branch, and then the provider's symbol-keyed lookups (item
011 docs: "a caller passing a string-keyed hash is out of contract") would
silently mis-validate (`required` checks `string->symbol`, properties are
symbol-keyed). **Pin: at minimum document that the JSON-Schema input must be a
parsed-jsexpr `hasheq` with symbol keys; ideally the wire/handle path is only
asserted for `hasheq`.** A string-keyed-hash input is a plausible mistake that
produces silent total-failure (every `required` fails), exactly the bug item 011
calls out.

### 9. `validation-errors` non-empty guard interaction with collect-all empty result

Not item 012's bug, but worth one assertion: confirm the normalized handle
returns `validation-ok` (not `validation-errors` with `'()`, which would *raise*
via item 010's guard) on the empty-object accept case. The empty-schema accept
path (Part 9) is the most likely place a "build errors list, wrap it" bug yields
an empty `validation-errors` and crashes instead of returning ok.

---

## Concrete Test Case Proposals

| # | Input | Expected |
|---|---|---|
| 1a | `(normalize-schema (listof string?))` | raises (array root is non-object) |
| 1b | `(normalize-schema (or/c "a" "b"))` (root enum contract) | **DECIDE + pin**: raise (recommended) |
| 1c | `(normalize-schema (hasheq 'type "array"))` | raises (non-object JSON-Schema root) |
| 2  | `(define direct (provider-compile (make-racket-native-provider) (wire-of P)))` for `P = (hasheq 'properties (hasheq 'name (hasheq 'type "string")))` (no root type) | `direct` and `(handle-of P)` agree on `{name:"x"}` and `{}` — exercises normalize-THEN-compile |
| 2b | `(handle-of C)` vs `(provider-compile (make-racket-native-provider) (wire-of C))` for the Part-4 `C` | agree on the full sample set (contract-form self-delegation) |
| 3  | `J = (hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string" 'minLength 3)))` | `(hash-ref (hash-ref (wire-of J) 'properties) 'name)` still has `'minLength 3`; `(accepts? J (hasheq 'name "x"))` → `#t` (deferred, not enforced) |
| 4  | `(object-schema/c (hash 'name string?) #:required '(missing))` | raises at construction (required names absent field) |
| 5  | `(normalize-schema (object-schema/c (hash 'x (or/c "a" string?)) #:required '(x)))` | raises (mixed literal/predicate `or/c` is not a clean enum) |
| 6  | integer field handle on `5.0` | rejects (pins `exact-integer?`, documents why not `integer?`) |
| 7  | `(normalize-schema (object-schema/c (hash 'x (and/c string? immutable?)) #:required '(x)))` | raises (`and/c` not in supported table) |
| 8  | `(normalize-schema (hash "type" "object"))` (string-keyed, equal-hash) | document/raise — NOT silently mis-validated |
| 9  | `(validation-ok? (validate (handle-of (object-schema/c (hash) #:required '())) (hasheq)))` | `#t` (empty schema → ok, NOT an empty `validation-errors` crash) |

---

## Testing Prerequisites — assessment

Prerequisites are well-adapted (pure library, no services, toolchain row, the
upstream `raco make` pre-flight checks for items 010/011 are correct). One gap:
the Manual Validation Checklist's REPL smoke check uses `validation-ok?` /
`validation-errors?` from `provider.rkt` but the require line in the smoke
command only requires `schema.rkt` + `provider.rkt` — that is correct, but the
checklist should also confirm the **fresh-provider-per-call** behaviour isn't a
performance trap if S6b calls `normalize-schema` per tool registration (not a
test gap, a documentation note for the Decisions block).

The portability walk is correctly specified with the non-vacuity drift check.
One nit: the scope note (inherited from item 008) that `module->imports` does
not see into `(module+ test …)` submodules means the test's OWN `rackunit` /
`racket/path` requires are invisible to the walk — good, but confirm `schema.rkt`
itself puts nothing portability-relevant in a `module+ test` (it shouldn't have
one; tests live in the separate `test/` file).
