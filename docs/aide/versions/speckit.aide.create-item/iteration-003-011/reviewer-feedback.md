# Reviewer Feedback — Item 011 (Default Racket-native provider `from-json-schema`), iteration 003

**Reviewer role:** testing strategy / prerequisites / edge cases — adversarial "what breaks a validator?" lens.
**Verdict:** `needs_revision: true`, overall **9/10** — but with exactly ONE narrow must-fix (a one-line strike), not a cluster. This iteration resolves the substance of N1–N3 and all of S-a..S-f rigorously. The single remaining issue is *inside* N1: the spec firmly commits to the per-compile-keyed **invariant** and tests it, but still lists **three co-equal encodings "pick one"** — and one of those three (`provider-compile` returns `(values handle warnings)`) directly contradicts item 010's port contract (AC 123) and the spec's own single-value test helpers. Strike that one option and this passes. I came in ready to set `needs_revision:false`; this is the only thing holding it.

I verified against item 010's shipped `provider.rkt` (the generic returns a single `compiled-validator?`) and traced the spec's own helper definitions, not from memory.

---

## N1–N3 + S-a..S-f — resolution audit

| # | iter-002 gap | iter-003 resolution | Resolved? |
|---|---|---|---|
| N1 invariant | warnings had no port-compatible home; single-slot collides with S7 | Committed: per-compile-keyed, NOT a provider-level slot; impossible `compiled-validator-warnings` accessor explicitly dropped; **N1 two-compile fixture** added (h1=minLength/h2=pattern from one provider, each distinct, neither leaks the other) — line 269 | **Invariant YES; encoding list has a trap — see I1** |
| N2 | warn-once only on stderr, "equivalently" | Recorded list is now the **load-bearing** oracle as a **conjunction**: `(= (length (warnings-of h)) n0)` after 3 validates; "equivalently" removed; stderr demoted to supplementary — line 270 | **YES** |
| N3 | `current-error-port` capture vacuous under `log-warning` | Emission pinned to `eprintf`/`current-error-port` for any stderr line; if `log-warning` is used the test MUST count via `make-log-receiver`; recorded-list load-bearing regardless — lines 12, 168, 262 | **YES** |
| S-a | C1×C4 phantom error | `{type:number, minimum:0}` on `"x"` → **exactly 1** error (`(= 1 (length …))`), no `minimum-skipped` pseudo-error — line 271 | **YES** |
| S-b | recording coupled to verdict | `{type:string, format:"ipv4"}` on `42` → exactly 1 (`type`) AND `ipv4` still in `(warnings-of h)`; recording pinned as a **compile-time property** independent of the validate verdict — lines 16, 272 | **YES** |
| S-c | malformed deferred value untested | Chosen branch MUST be tested: `check-exn` if raise, accept+record if ignore — line 300 | **YES** |
| S-d | recursive sub-schema malformation unpinned | `check-schema-shape` recursion policy pinned (recommend recurse → compile-time raise), tested either way — lines 168, 296 | **YES** |
| S-e | nested enum unlocated | `{properties:{color:{enum:…}}}` on `{color:"blue"}` → error path `'("color")` — line 225 | **YES** |
| S-f | empty vs absent `properties` crash | Both branches default-guarded (`(hash-ref schema 'properties #f)`), both accept, both `check-not-exn` — line 282 | **YES** |

The N2 conjunction and the S-b compile-time-recording framing are exactly right; the N1 fixture (line 269) is precisely the test a single-mutable-slot implementation fails while passing every read-right-after-own-compile assertion. The recursion clarification for S-d (folded into the `check-schema-shape` Implementation Step) closes the "deep malformed sub-schema hides until reached" hole. This is a genuinely thorough pass.

---

## Missing Coverage (CRITICAL — the one must-fix)

### I1. N1 still lists THREE encodings "pick one," and one of them (`provider-compile` returns `(values handle warnings)`) violates item 010's port contract AND the spec's own single-value test helpers.

The original N1 defect was *indecision among options, one of which was impossible*. This iteration fixed the impossible one (`compiled-validator-warnings` accessor — correctly dropped) and firmly committed the **invariant**. But for the **encoding**, line 168 (and the warnings-mechanism note, diff) still says:

> "…e.g. by returning it alongside the handle, **or** via a provider-held `(hasheq handle → warnings)` weak map, **or** a `make-racket-native-provider`-level accessor that takes the handle… The implementer picks one and records it in Decisions."

and explicitly: *"or `provider-compile` returns `(values handle warnings)`"*.

The `(values handle warnings)` option is a **trap**, for two independent reasons:

1. **It violates item 010's port contract (AC 123).** AC 123 (unchanged, verified): *"`provider-compile` returns a `compiled-validator?` handle (item-010 type)."* Item 010's `gen:json-schema-validator-provider` generic defines `provider-compile` as returning a **single** value. Making it return `(values handle warnings)` changes the method's arity — which is exactly the "NO new port surface … does NOT widen `provider.rkt`'s exports" the Scope guard (line 115) forbids, since the generic's *signature* is part of the port surface. An implementer who picks this option is non-conformant to the port the item is required to implement as-is.

2. **It crashes the spec's own test helpers.** Lines 185–188 define:
   ```racket
   (define (accepts? schema value)
     (validation-ok? (validate (provider-compile P schema) value)))
   ```
   Here `(provider-compile P schema)` is in **single-value context** (the argument position of `validate`). If `provider-compile` returns two values, this raises `result arity mismatch: expected 1 value, received 2` — every `accepts?`/`rejects?`/`errs` call (i.e. nearly the whole suite) fails to even run. The `(warnings-of h)` abstraction in the helper comment papers over this: `warnings-of` takes a *handle* `h`, which works for the weak-map and `provider-warnings-for` encodings but is **structurally impossible** for the `(values …)` encoding (there, warnings are a second return value at compile time, never recoverable from `h` alone afterward — so `(warnings-of h)` couldn't be implemented).

**Fix (one line):** strike the `(values handle warnings)` option. The two surviving encodings — (a) provider-held `(hasheq handle → warnings)` keyed by the produced handle, and (b) a `(provider-warnings-for provider handle)` accessor — are both port-compatible (single-value `provider-compile`, warnings retrieved later from the handle) and both satisfy `(warnings-of h)`. Better still, **commit to ONE** of those two (recommend the `(hasheq handle → warnings)` weak map held on the `racket-native-provider`, with `provider-warnings-for` as its public read accessor) so "the implementer picks one" no longer reintroduces the indecision the worker's task flagged. The invariant is already pinned; pinning the encoding too removes the last ambiguity.

*(Note: a weak `hasheq` keyed by the handle is the right call over a strong one — otherwise the provider retains every handle it ever compiled, a memory leak when item 012 compiles many schemas through one long-lived provider. Worth a one-line note in Decisions: use a weak map so compiled handles can be GC'd.)*

---

## Missing Coverage (SUGGESTED — optional hardening, not blocking)

### S-g. `(warnings-of h)` membership uses `member` over string keys — pin the element type so the N1/S-b/S3 assertions can't pass on a symbol/string mismatch.
The fixtures assert `(member "minLength" (warnings-of h))`, `(member "ipv4" …)`, `(member "multipleOf" …)` — all **strings**. But the schema's keys are **symbols** (`'minLength`), so if the implementer records the ignored keywords as symbols (the natural thing — they come from `hash-keys`), `(member "minLength" '(minLength …))` is `#f` and the N1/S3 asserts fail (or, worse, a `(member 'minLength …)` written by the implementer passes while the *spec's* string-based fixture is what ships). Pin the recorded element type explicitly: state whether `(warnings-of h)` returns **strings or symbols**, and make every fixture consistent with it. Recommended: symbols (no conversion needed), and rewrite the fixtures as `(member 'minLength (warnings-of h))`. This is the same symbol/string boundary that S8 nailed for `required` — apply the same rigor to the warnings list.

### S-h. N1 fixture: also assert the two handles' warning lists are each length 1 (not just disjoint membership).
Line 269 asserts `minLength ∈ h1`, `pattern ∉ h1`, etc. A subtler single-slot bug — appending to a *shared* list rather than overwriting — would make `(warnings-of h1)` = `("minLength" "pattern")` (both present). The `pattern ∉ h1` assert already catches that exact case, so this is well-covered — but adding `(= 1 (length (warnings-of h1)))` makes the "exactly this handle's keywords, nothing bled in" claim explicit and would also catch a duplicate-recording bug. Cheap, optional.

### S-i. Confirm `validate` does not RAISE when called on a handle whose warnings live in a provider-side map.
Under the `(hasheq handle → warnings)` encoding, `validate` (item 010's module-level proc) applies the handle's closure and never consults the provider — good, that's the N2 "closure never touches the ignore-list" property. But pin one negative: a handle `validate`d *after the provider has compiled other schemas* still validates correctly (the provider's growing warnings map doesn't perturb an old handle's verdict). The S7 statelessness test nearly covers this; one explicit "compile h1, compile h2…h5, then validate h1 — still correct" assertion would close it. Optional.

---

## Concrete must-fix + optional fixtures

| # | Item | Action | Severity |
|---|---|---|---|
| **I1** | `(values handle warnings)` encoding | **Strike it** from the option list (violates AC 123 single-value port contract + crashes `(provider-compile P schema)` helpers); commit to ONE of the two surviving handle-keyed encodings | **must-fix (blocking)** |
| S-g | warnings element type | Pin string-vs-symbol for `(warnings-of h)`; make all `member` fixtures consistent (recommend symbols) | suggested |
| S-h | N1 fixture | add `(= 1 (length (warnings-of h1)))` | optional |
| S-i | post-multi-compile validate | validate an old handle after later compiles — still correct | optional |

---

## Bottom line

The keyword/value/edge-case surface (C1–C6, S1–S8) remains airtight, and N1's **invariant**, N2, N3, and S-a..S-f are now genuinely, falsifiably pinned — the N1 two-compile fixture and the N2 recorded-list conjunction are exactly the right tests. The only thing standing between this and `needs_revision:false` is **I1**: the encoding list still offers three options "pick one," and one of them (`(values handle warnings)`) breaks item 010's single-value `provider-compile` contract and the spec's own test helpers. That is the literal residue of the original N1 "indecision" defect — narrowed to a single bad option among three. Strike it (ideally commit to one of the two good encodings), optionally fold in S-g (the warnings symbol/string element type, a real trap given the schema keys are symbols), and I will pass it. **9/10, one-line revision.**
