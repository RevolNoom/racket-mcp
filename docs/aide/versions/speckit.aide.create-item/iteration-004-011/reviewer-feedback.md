# Reviewer Feedback — Item 011 (Default Racket-native provider `from-json-schema`), iteration 004

**Reviewer role:** testing strategy / prerequisites / edge cases — adversarial "what breaks a validator?" lens.
**Verdict:** `needs_revision: false`, overall **10/10**. APPROVED. I1 and S-g — the only two items outstanding after iteration 003 — are fully and cleanly resolved, and I verified no new inconsistency was introduced (no stray string-based warnings assertion, no lingering live reference to the struck `(values …)` option or the impossible `compiled-validator-warnings` accessor). The spec is now thorough enough that an implementer could not introduce an untested validator bug across the keyword surface, the wrong-typed-value crash surface, the error-collection policy, OR the warnings side-channel.

I verified by grepping the full warnings surface and reading the committed mechanism + the test helpers directly against item 010's frozen port — not from the worker's report.

---

## I1 (the iter-003 blocker) — RESOLVED

The three-encoding "pick one" menu is gone. The spec now commits to **one** mechanism (item line 61, 169):

> a provider-held **weak** map `(make-weak-hasheq)` from produced **handle → ignored-keyword list**, populated by `provider-compile`, read via a provided accessor `(provider-warnings-for provider handle)`.

And it explicitly **REJECTS** the two bad encodings by name, with the reasons intact:
- `(values handle warnings)` — "changes the item-010 generic's arity (the forbidden 'new port surface'), breaks the spec's own `(validate (provider-compile P schema) value)` helpers with a values-in-single-value-context arity error, and makes `(warnings-of h)` unimplementable";
- a single provider-level mutable slot — "overwritten by the next compile".

I confirmed:
- **The only occurrences of `(values handle warnings)` (lines 61, 169) are in REJECTION context** — not offered as a live option anywhere. No menu remains.
- **`provider-compile` still returns a single `compiled-validator?`** (lines 61, 169) — the item-010 port contract (AC 123) is honored; the `accepts?`/`rejects?` helpers (lines 186–189) that call `provider-compile` in single-value context are now sound.
- **`compiled-validator-warnings`** appears only once (line 60) in the "is impossible and is NOT used" note — correctly dispositioned, not used.
- The **weak** map is the right call and the rationale is recorded ("does NOT retain every handle it ever compiled — a leak when item 012 compiles many schemas through one long-lived provider"), closing the S-i memory-retention concern I raised as optional in iter-003.

The N1 fixture (line 270) is unchanged and still exactly right: `h1`(minLength)/`h2`(pattern) from one provider, each handle's list distinct, neither leaking the other — the test a single-slot impl fails while passing every read-right-after-own-compile assertion.

## S-g (the iter-003 strong-suggestion) — RESOLVED

Warnings element type is pinned to **symbols** (item line 62): *"The committed element type is therefore symbols — `(provider-warnings-for provider handle)` returns e.g. `'(minLength)` / `'(ipv4)` / `'(multipleOf)`."* The rationale ties it to the same symbol/string boundary S8 nailed for `required` (schema keys arrive from Racket's `json` reader as symbols).

I confirmed **every** warnings fixture now uses symbol membership — `(memq 'minLength …)`, `(memq 'ipv4 …)`, `(memq 'multipleOf …)`, `(null? (provider-warnings-for P h))` — across Part 6 (lines 268–275), the unknown-format case (line 259), S-c (line 301), and all the Validation Results checklist rows (lines 394–459). The grep for a stray string-based warnings assertion (`(member "…" (provider-warnings…))`) returned **empty** — none left behind. The accessor signature `(provider-warnings-for provider handle)` returning `(listof symbol?)` is consistent in the helper comment (lines 194–195), the Implementation Step (line 170), the Expected Outcomes (line 417), and the `provide` surface (line 170).

---

## No new inconsistency introduced — verified

The two failure modes the worker's task flagged as risks both came back clean:
- **No stray string-based warnings assertion** — grep empty; every membership check is `memq` on a symbol.
- **No lingering live reference to a struck option** — `(values …)` only in rejection prose; `compiled-validator-warnings` only in the "impossible/not used" note.

The only remaining "implementer picks a branch" phrasings are the two I *explicitly sanctioned* in prior rounds and they are NOT warnings-indecision:
1. **S-c** (line 301) — raise-vs-ignore on a malformed deferred-keyword *value* (`{minLength:"three"}`). This is genuine, bounded implementer latitude (both branches are valid JSON-Schema-provider behaviour), and the spec requires *the chosen branch to be tested either way* — so no path is left uncovered. Correct as-is.
2. **S-g unknown-format marker** (line 62) — the recorded element for an unknown *format* MAY be the bare symbol `'ipv4` or a `'(format . ipv4)`-style marker, "pin the chosen form and keep all fixtures consistent." Both candidate forms are symbol/pair values compatible with the `memq`/membership fixtures, and the test rows consistently hedge "(or the chosen unknown-format marker per S-g)." This is a cosmetic representation choice, not a contract-affecting one — acceptable latitude, distinct from the I1 defect (which was a choice among options *one of which broke the port contract*).

---

## Full-surface confirmation (regression check across all prior rounds)

Spot-checked that the earlier-resolved items did not regress in this edit pass:
- **C1 collect-all** — exact `(= 2 (length …))` counts intact (untouched this round).
- **C2/C3** — `check-not-exn` on every non-object/non-array value + no-`type` variants intact.
- **C4/N2** — recorded-list-length warn-once conjunction intact, now reading via `provider-warnings-for` symbols.
- **C5/C6** — format-on-non-string no-op, unknown-format routing, adversarial rejects + documented per-recognizer limitation intact.
- **S-a/S-b/S-d/S-e/S-f** — zero-error-for-ignored-keyword, compile-time recording, recursive sub-schema malformation, located nested-enum path, empty-vs-absent `properties` default-guard — all intact, with the warnings-reading ones (S-b) updated to symbols.
- **Portability** — restricted-load walk rooted at `from-json-schema.rkt` with the `net/url` ban + drift injection intact. (Note: `make-weak-hasheq` is in `racket/base`, no new import — the weak-map encoding does NOT perturb the portability AC.)

---

## Bottom line

Approved, `needs_revision: false`, **10/10**. Across four iterations this spec closed: the validator crash surface (non-object/non-array under structural keywords), the error-collection policy (collect-all with exact counts), the format recognizer rigor + non-string/unknown handling, the deferred-keyword ignore-with-warning policy (uniform, warn-once on a load-bearing recorded list), and finally the warnings side-channel — now a single, committed, port-compatible weak-map mechanism with a symbol-typed accessor and a two-compile distinctness fixture. An implementer following this spec could not ship an untested validator bug in any of those areas. Ship it.
