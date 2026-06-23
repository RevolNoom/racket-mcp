# Reviewer feedback — Item 010 (Validator-provider port, M3), iteration-002 (RE-REVIEW)

Role: Reviewer (testing strategy, prerequisites, edge cases). Verdict: **ready to implement** — every one of the 7 BLOCKING and all 6 SUGGESTED fixes from iteration-001 was applied AND is correct. The revision is internally consistent end-to-end, every acceptance criterion is now backed by a concrete named test, and the one genuinely dangerous new construct (the `#:guard` + struct ordering dependency) is called out explicitly. Rating 9/10, `needs_revision=false`.

Cross-checks re-performed against the live checkout (not eyeballed):
- `docs/aide/progress.md` line 71 reads exactly `📋 mcp/core/validators/provider.rkt — gen:-style validator-provider port` — Completion Reminder cite (line 325) is **correct**.
- queue-002 item 010 (lines 25–26) — the two-op split + stub "ok + error → assert result shape" bar is faithfully matched; the spec stays within the sanctioned scope.
- item-008 shipped helper `mcp/core/test/main-test.rkt`: `banned-module-paths` (line 49–50) **includes `racket/port`** alongside `racket/system racket/tcp racket/udp …`; the helper walks `module->imports` and the source notes the `(module+ test …)` scope limit. The revised spec's banned set + scope-limit caveat now match the shipped helper exactly.
- TS `validators/types.ts` — single fused `getValidator`; `{valid,data,errorMessage}`. The split + path-enrichment superset mapping is faithful and sanctioned by the queue header.

---

## Fix-by-fix verification

### BLOCKING

**1 — Second, differently-built provider stub + identical surface. APPLIED, CORRECT.** AC line 112 now mandates **two** independently-built stubs (a `const`-equality and a `type`-style `string?`), compiles a handle from each, and asserts both flow through the IDENTICAL `validate`/`validation-result?`/`validation-ok?`/`validation-errors?` surface, with the cross-check that a value ok for one is an error for the other (`"hi"` ok for the `type` stub, error for the `const 42` stub). Testing Strategy Part 1 (lines 146–153) spells out the exact stubs, schemas (`(hasheq 'const 42)`, `(hasheq 'type "string")`), and the symmetric assertions. This is the real swap-seam proof the iter-001 critique demanded. Correct.

**2 — Zero-error result handled, falsifiably. APPLIED, CORRECT — and the stronger of the two options was chosen.** The spec adopts a struct `#:guard` (lines 68–74) that raises on an empty list OR a non-`validation-error` element, AC line 107 states non-emptiness is "ENFORCED, not advisory," and Part 4 step 8 (line 166) pins it with `(check-exn exn:fail? (lambda () (validation-errors '())))` PLUS an element-type `check-exn`. The AC wording is now falsifiable (a zero-error result is *rejected*, not merely "the stub happens to emit ≥1"). Decisions (b) line 209 records the rationale and the rejected alternative. Correct.

**3 — Value matrix (json-null, hasheq, list, string) round-tripping equal?. APPLIED, CORRECT — and broadened.** AC line 113 + Part 3 step 7 (line 162) require ok-validations on `(json-null)`, `(hasheq 'a 1)`, `'(1 2 3)`, a string, a number, AND `#t`, each asserting `(check-equal? (validation-ok-value r) <input>)`. The `json` require is correctly added (line 144) "needed for `(json-null)`." Catches a provider that coerces/reserializes/drops a non-numeric jsexpr. Correct.

**4 — Handle reuse (compile once, validate many ok+error in sequence). APPLIED, CORRECT.** AC line 114 + Part 2 step 5 (line 157): one handle `hA`, sequence `42`(ok)/`1`(err)/`42`(ok again)/`2`(err), each asserted independently, with the explicit requirement that the second ok still recovers `42` — directly testing the TS "called multiple times" contract and absence of per-call state. Correct.

**5 — Two independent handles from the same provider. APPLIED, CORRECT.** AC line 115 + Part 2 step 6 (line 158): `h1`/`h2` from `stub-a` with `(hasheq 'const 1)` / `(hasheq 'const 2)`; a value ok for `h1` is an error for `h2` and vice versa. Explicitly framed as catching "global / last-schema closure-memoization." Correct.

**6 — Banned set includes `racket/port` in the AC. APPLIED, CORRECT — inconsistency resolved.** AC line 111, Testing Strategy line 175, and Manual Checklist all now list the full eight-module set ending in `racket/sandbox, racket/port`, and the AC explicitly annotates "note `racket/port` IS included, matching the shipped helper." Verified against `mcp/core/test/main-test.rkt` line 49–50. The iter-001 AC/Testing-Strategy mismatch is gone. Correct.

**7 — Closed-set negatives. APPLIED, CORRECT.** AC line 108 + Part 4 step 9 (line 167): `(check-false (validation-result? 42))` and `(check-false (validation-result? (validation-error '() "x")))` — pinning that a bare error *element* is not a *result*, making "closed/exhaustive" testable. Correct.

### SUGGESTED

**8 — Compile-on-garbage behavior pinned. APPLIED, CORRECT.** Part 6 step 16 (line 180) + Decisions (e) line 216: the stubs **fail-fast** (raise via `make-mcp-error`/`make-protocol-error`) on a missing-key/non-object schema, asserted with `check-exn`; deferral to validate-time is explicitly allowed only "IF tested + documented." Sets the precedent item 011 inherits. Correct.

**9 — ≥2-error result with order. APPLIED, CORRECT.** Part 4 step 12 (line 170) + AC line 117: a two-element `validation-errors`, assert length 2, all `validation-error?`, messages recovered in order `'("e1" "e2")` — catches a `validate` that keeps only the first error. Correct.

**10 — Mixed string/integer path. APPLIED, CORRECT.** AC line 106 + Part 4 step 13 (line 171): `'("items" 0 "name")` round-trips via `validation-error-path`, pinning the integer-index segment branch item 011 emits. Correct.

**11 — Negative-accessor raises + non-jsexpr-value policy. APPLIED, CORRECT.** Accessor mis-dispatch: AC line 110 + Part 4 step 11 (line 169) — `validation-ok-value` on a `validation-errors` (and vice versa) raises via `check-exn`, with the note that pinning it protects against a future single-struct refactor silently changing the behavior. Non-jsexpr policy: Part 6 step 18 (line 182) + Decisions (e) — `validate` assumes a jsexpr, does not police input type, and the stub's actual behavior on `(void)` is pinned. Both decided + tested. Correct.

**12 — Cross-provider handle totality (or vacuous-under-recommended-encoding note). APPLIED, CORRECT.** Part 6 step 17 (line 181) + Decisions (e): under the recommended closure-in-handle encoding `validate` is total over any `compiled-validator?` and this is stated as "vacuous-by-construction," with the alternative `gen:compiled-validate` encoding's cross-provider-dispatch interpretation documented. The "document which applies" instruction is present. Correct.

**13 — Portability walk entry-point = provider.rkt + module+test scope-limit restated. APPLIED, CORRECT.** AC line 111 and Part 5 step 14 (line 175) both state the entry point is "`provider.rkt` ITSELF (there is no `validators/main.rkt` barrel … do NOT 'fix' the walk to start from a barrel)" and restate the item-008 scope limit verbatim: "`module->imports` does NOT see into `(module+ test …)` submodules … do not overread the portability claim." Matches the shipped helper's own caveat. Correct.

---

## New-problem scan (introduced by the revision)

**A — `#:guard` vs opacity / struct ordering. HANDLED, no conflict.** The guard lives on `validation-errors` (a result struct that is intentionally `#:transparent` with provided accessors) — NOT on the opaque `compiled-validator` handle — so there is no clash with the opacity requirement (the handle's closure field is still kept out of `provide`, AC line 109 + opacity checklist). The dangerous ordering dependency (the guard references `validation-error?`, so `validation-error` must be defined first) is called out in THREE places: the inline code comment (line 61 "DEFINE THIS BEFORE validation-errors"), Implementation Step 3 (line 130 "before `validation-errors`"), and Decisions (b) line 209 ("`validation-error` MUST be defined **before** `validation-errors`"). This is exactly the kind of latent compile-order trap that should be flagged, and it is. Good.

**B — Internal consistency across sections.** Re-read Description §3 export list, AC, Testing Strategy Parts 1–6, Manual Checklist, Expected Outcomes, and the Validation Results template against each other. They agree: the same eight-module banned set everywhere; the same two-stub seam; the same value matrix (`json-null`/`hasheq`/list/string/number) in AC line 113, Part 3, checklist line 274, and Validation Results line 306; the same guard/closed-set/mis-dispatch/≥2-order/mixed-path bundle in AC, Part 4, checklist, and Validation Results line 307. The iter-001-class banned-set divergence is the bug to watch for and it is resolved. No new cross-section drift found.

**C — Every AC backed by a concrete named test.** Walked all AC bullets (lines 103–120): each maps to a named Testing-Strategy part/step (seam→Part 1; reuse/independence→Part 2; value matrix→Part 3; guard/closed-set/mis-dispatch/≥2/path→Part 4; portability→Part 5; compile-garbage/cross-provider/non-jsexpr→Part 6; opacity→checklist `dynamic-require`→'not-found; parity-matrix→doc edit, correctly not a test). No vague/unfalsifiable AC remains. The two iter-001 offenders (non-empty errors; exhaustive variant set) are now both falsifiable.

**D — Scope guards intact.** Scope guard block (lines 93–97) still forbids keyword logic (→011), normalization (→012), and TS-baseline parity (→011); Part 1 keeps stubs "NO real keyword logic." Completion Reminder (lines 323–328) still cites progress.md line ~71 with the exact deliverable text (verified live) and still warns NOT to claim the keyword box (011's) or sibling S2 boxes. Intact.

---

## Residual nitpicks (do NOT warrant another round)

- **N1 — third stub for the value matrix.** Part 3 line 162 says use "an 'accept-anything' stub (a third trivial stub, or Stub B with a predicate that always holds)". Fine — but note Stub B is `type`-style reading `(hash-ref schema 'type)`; an "always-true" predicate means compiling it with a `(hasheq 'type "any")`-ish schema whose branch trivially holds. Minor: the implementer should pick the always-hold stub so the value under test is the validated *value*, not the schema. Already adequately hinted; no change required.
- **N2 — REPL one-liner is encoding-specific.** Manual Checklist line 268 hard-codes the recommended `compiled-validator`/`validate` names; line 269 already says "Adjust to the chosen encoding if names differ." Acceptable as-is.
- **N3 — `'null` vs `(json-null)`.** The value matrix relies on `json`'s `(json-null)` (default `'null`). If an implementer parameterizes `json-null`, the `equal?` round-trip still holds (same parameter value in and out), so no hazard — just worth an implementer's awareness. Not blocking.

None of these change behavior or leave a bug-sized hole; they are awareness notes.

---

## Verdict

All 13 prior fixes applied and correct; no new problems introduced; the revision is internally consistent, fully test-backed, scope-clean, and the one risky construct (guard + struct ordering) is explicitly flagged. This spec is ready to implement.

- overall_rating: 9
- needs_revision: false
