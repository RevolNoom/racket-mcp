# Reviewer feedback — Item 010 (Validator-provider port, M3), iteration-001

Role: Reviewer (testing strategy, prerequisites, edge cases). Verdict: **needs revision** — the spec is strong on structure and portability rigor, but the test plan has real edge-case gaps that would let bugs through, the biggest being **only one provider implementation is exercised** (so the `gen:` swappability — the entire point of a *port* — is never proven). Rating 6/10.

Cross-checks performed (all sources read, claims verified against the checkout, not eyeballed):
- queue-002 item 010 (line 25–26) — split sanctioned; "trivial stub… ok + error… assert result shape" is the testable bar. Spec matches.
- roadmap S2 M3 deliverable (line 111) + S2 testing criteria (line 129–131) — keyword/Ajv parity is explicitly items 011/017/S9, NOT 010. Spec's scope guard is correct.
- progress.md line 71 (`📋 mcp/core/validators/provider.rkt — gen:-style validator-provider port`) — **Completion Reminder line 273 cites "line ~71" and the exact text; verified correct.**
- TS `validators/types.ts` — single fused `getValidator`, `{valid,data,errorMessage}`. Spec's split + path-enrichment mapping (Decisions a/b) is faithful and the divergence is sanctioned by queue header.
- item-008 portability walk — **shipped and passing** at `mcp/core/test/main-test.rkt` (`raco test` → 29 tests passed in this env). Helpers `resolve-mpi`/`dir-of`/`direct-imports`/`transitive-imports`/`banned-hit?`/`check-portable!` exist and are reusable. **008's shipped `banned-module-paths` includes `racket/port`** and the walk passes → S1 core genuinely excludes it.

---

## 1. Testing-strategy gaps

### BLOCKING

**G1 — Only ONE provider implementation is tested; the swap seam is never exercised.** The whole reason this item exists (Description line 16, Decisions c) is dependency inversion: a second provider must be droppable without changing callers. The test plan (Part 1–3) defines exactly one stub and never proves a *second*, differently-built provider compiles+validates through the same `validate` entry point and the same result predicates. A bug where `validate` accidentally closes over the *first* provider, or where `provider-compile`'s dispatch is mis-wired, passes every current assertion. **Add a second stub** (e.g. a `type`-style stub alongside the `const`-style one), compile a handle from each, and assert both flow through the identical `validate`/`validation-result?` surface with correct ok/error outcomes. This is the single most important missing test for a *port*.

**G2 — Handle reuse / "called multiple times" is asserted nowhere.** The TS contract this ports states the validator is *"called multiple times"* (types.ts:34) and the spec leans on it as the entire rationale for the compile/validate split (Decisions a). Yet the test compiles `h` once and calls `validate` on it twice with *different literal call sites* — it never asserts the **same handle** yields a stable, correct result across **repeated** calls, nor that the handle carries no per-call mutable state. Add: compile once, then `(validate h x)` over several ok and several error values in sequence, asserting each independently. Cheap, and it directly tests the headline contract.

**G3 — Compiling the SAME schema twice / one provider compiling MANY schemas is untested.** `provider-compile` returning two independent handles from two calls (no shared mutable state, no handle aliasing) is a classic closure-capture bug surface. Add: `(define h1 (provider-compile stub s1))`, `(define h2 (provider-compile stub s2))` with different expected values, and assert `h1`/`h2` validate *independently* (a value ok for h1 is error for h2). Currently a provider that memoizes the last schema globally would pass.

### SUGGESTED

**G4 — Cross-provider handle confusion is not addressed.** What happens if a handle from provider A is passed to a `validate` that somehow expects B? With the recommended closure-in-handle encoding this is a non-issue (the handle *is* the closure), but the spec offers a second encoding (generic-on-handle, Description §1 alt). Under that encoding the question is live. The spec should either (a) state that `validate` is total over any `compiled-validator?` regardless of originating provider and add an assertion, or (b) note it's out of scope because the recommended encoding makes it vacuous. Right now it's silently unaddressed.

**G5 — `compile` on a garbage/invalid schema is undefined.** The spec says S1 error constructors *may* be used "if a provider wants to raise on a malformed schema" (line 82) but the **test never pins the stub's behavior** for a non-conforming schema argument (e.g. `provider-compile` given `42`, `'()`, a string, or a `hasheq` missing the key the stub reads). This is the "input technically valid Racket but logically impossible schema" case. The stub reads `(hash-ref schema 'const)` — feed it `(hasheq)` (key absent) and `42` (not a hash) and pin the outcome (raise vs error-at-validate vs default). Even for a stub, leaving compile-time error behavior unspecified means item 011 inherits no precedent for the most important real decision it faces.

---

## 2. Edge cases missing

### Result-shape edge cases

**E1 (BLOCKING) — "Zero errors is invalid" is asserted only POSITIVELY, never NEGATIVELY.** Edge-cases bullet (line 148) says `validation-errors` must carry a non-empty list and the test asserts the stub's error case has ≥1 element. But nothing **prevents construction** of `(validation-errors '())`. Since the structs are plain `#:transparent` with no guard, a malformed empty-error result is constructible and would silently pass `validation-errors?`. The spec should decide: either (a) add a struct **guard** (`#:guard`) rejecting an empty list (then test that `(validation-errors '())` raises), or (b) explicitly document that non-emptiness is a *provider contract*, not enforced, and that consumers must not assume it. As written, the "non-empty" acceptance criterion (line 96) is **unfalsifiable** — there is no test that a zero-error result is rejected, only that the stub happens to emit one.

**E2 (SUGGESTED) — MANY-errors case is never built.** Tests cover one root error (Part 1.4) and one nested-path error (Part 1.5), but never an error result with **multiple** `validation-error` elements — which is the realistic item-011 shape (several keyword failures at once). Add an error case with ≥2 elements and assert order + that all are `validation-error?`. Without it, a `validate` that accidentally keeps only the first error passes.

**E3 (SUGGESTED) — accessor totality / variant confusion.** The spec asserts mutual exclusivity (`validation-ok?` xor `validation-errors?`) but never asserts the **negative accessor** failure mode: calling `validation-ok-value` on a `validation-errors` (and vice versa) should raise, not silently return garbage. With plain structs it *will* raise, but pinning it documents that consumers must predicate-dispatch first. One line each.

**E4 (SUGGESTED) — empty vs whitespace `message`, empty `path` vs non-list path.** Root path `'()` is covered (good). But: is `(validation-error '() "")` (empty message) a valid error? Is a `path` of `'("a" 0 "b")` (mixed string/integer segments, per the documented contract line 64) ever exercised? Part 1.5 only uses `'("a" "b")` (all strings). Add one mixed-type path (`'("items" 0 "name")`) to prove the integer-segment branch of the path contract is real, not aspirational — item 011 will emit array indices as integers and this is the only place the shape is pinned before then.

### Value edge cases (the stub should exercise)

**E5 (BLOCKING for completeness) — JSON null / `(json-null)` / absent-vs-present are not in the value matrix.** The task brief explicitly calls these out and the spec ignores them. The stub validates `42` (ok) and `7` (error) — both plain numbers. It never feeds: `(json-null)` (Racket's JSON null, which is `'null` by default — distinct from `#f` and from absent), a `hasheq` value, a `list` value, a string, or `#f`. Since the result *carries the validated value* (`validation-ok-value`), round-tripping a `(json-null)` and a `hasheq` through `validation-ok` matters: a provider that coerces or drops these would be caught. Add at least: validate ok on a `(json-null)`, on a `(hasheq 'a 1)`, and on a `'(1 2 3)`, asserting the value comes back `equal?`. This is the "irregular input" category and it's entirely absent.

**E6 (SUGGESTED) — non-JSON Racket value fed to validate.** Feed the handle a value that is not a `jsexpr` at all (e.g. a `symbol`, a procedure, `(void)`). The port makes no claim that the value is a jsexpr (validate takes "a value"), so it should *not* crash on a non-jsexpr — pin that it returns a result (ok or errors) rather than raising, OR document that validate assumes a jsexpr input. Either way, decide it.

---

## 3. Portability NFR

**Solid, with one fix.** The restricted-load test is concrete: it names the mechanism (`module->imports` transitive walk), names the banned set, mandates a fresh `make-base-namespace`, mandates the 2-hop drift-injection non-vacuity check (line 235), and correctly points at the item-008 precedent — which I verified **ships and passes** (`mcp/core/test/main-test.rkt`, 29 tests). Reusing those helpers is realistic.

**P1 (BLOCKING-minor — internal inconsistency) — the banned set is stated TWO different ways.** Acceptance criterion line 100 lists the banned set **without `racket/port`**: `(racket/system, racket/tcp, racket/udp, net/url, net/http-client, net/sendurl, racket/sandbox)`. But Testing Strategy line 141 and the Manual Checklist line 235 list it **with `racket/port`**. The item-008 shipped helper bans `racket/port` and passes, so the *correct* set includes it. Fix line 100 to add `racket/port` so the AC and the test agree (otherwise an implementer who codes to the AC ships a weaker test than the one the Testing Strategy describes — a silent coverage hole).

**P2 (SUGGESTED) — "test the provider in isolation" is satisfied, but say so explicitly.** The walk starts from `provider.rkt` directly (not from a barrel that also pulls siblings), so it does test the module in isolation — good, and better than waiting for item 017's collection sweep. Worth one sentence stating the walk's entry point is `provider.rkt` itself, not `validators/main.rkt` (which doesn't exist yet), so a future reader doesn't "fix" it to a barrel.

**P3 (SUGGESTED) — test-submodule scope limit not restated.** Item 008 AC (its scope-boundary clause) explicitly notes `module->imports` does NOT see into `(module+ test …)` submodules — so a banned require hidden in provider.rkt's own test submodule would NOT be caught. 010 inherits this exact limit and should restate it (one line) so the portability claim isn't overread.

---

## 4. Acceptance-criteria ↔ test mapping

Mostly tight. Gaps:

| Criterion | Backed by named test? | Issue |
|---|---|---|
| AC line 96 — `validation-errors` carries **non-empty** list | Partially | Only positive (stub emits ≥1). No test rejects `(validation-errors '())`. See **E1**. Unfalsifiable as written. |
| AC line 98 — variants "mutually exclusive **and exhaustive**" | Exclusivity yes (line 150); **exhaustive no** | Nothing asserts `validation-result?` is *exactly* ok|errors and rejects a third thing — e.g. `(check-false (validation-result? 42))`, `(check-false (validation-result? (validation-error '() "x")))` (a bare error is NOT a result). Add it; otherwise "exhaustive/closed" is untested. |
| AC line 100 — banned set | Yes, but | set disagrees with line 141. See **P1**. |
| AC line 95 — handle is **opaque** | Yes (line 151 + checklist 233) | Good — `dynamic-require` of the field accessor → `'not-found`. Well specified, mirrors 008. |
| AC line 101 — stub "satisfies the generic interface" | Yes (Part 3, line 145) | Good — `json-schema-validator-provider?` true on stub, false on `42`. |
| AC line 105 — parity-matrix `validators/*` → `partial` | Reminder only | No *test* (correct — it's a doc edit). Fine. |

**Unfalsifiable / vague items to fix:** AC 96 (non-empty — see E1), AC 98 (exhaustive — add the closed-set negative checks).

---

## 5. Section completeness

All required sections present and correctly adapted for a Racket library: Description, Acceptance Criteria, Implementation Steps, Testing Strategy, Dependencies, Decisions & Trade-offs (a–d), Project-Specific Adaptations, Testing Prerequisites (Required Services / Env Config / Manual Validation Checklist / Expected Outcomes / Validation Results template), Completion Reminder.

- **Completion Reminder progress.md path: CORRECT.** Cited line ~71 and the exact deliverable text both verified against the live `docs/aide/progress.md` (line 71 reads exactly `📋 mcp/core/validators/provider.rkt — gen:-style validator-provider port`). The 📋→🚧→✅ discipline and the explicit warning NOT to claim the keyword box (item 011's) or sibling S2 boxes is accurate against progress.md lines 86/88.
- **Manual Validation Checklist is runnable and specific** — concrete `raco make` / `raco test` paths, a real REPL one-liner (line 230) defining an inline stub and asserting `(#t #t)`, opacity check, drift-injection check. Good. One caveat: the REPL one-liner's `struct … #:methods gen:json-schema-validator-provider [(define (provider-compile p s) …)]` hard-codes the **recommended** encoding/names — flag that it must be adjusted if the implementer picks the alternative encoding (the spec already says this at line 231, good).
- **Expected Outcomes** are concrete and verifiable (exact export list enumerated line 242).

**SUGGESTED S1 — "imports only S1" has a soft escape hatch (line 82): "requiring only `mcp/core/types` (not the full barrel) is acceptable… the restricted-load test is the real gate."** Fine for portability, but it means the *exact* require list is not pinned by an AC — only the negative (no banned modules) is. That's acceptable given the restricted-load gate, but the Validation Results template line 260 asks to "confirm require list is mcp/core/main.rkt (or mcp/core/types)" — so it's captured. No change required; noting it's intentionally loose.

---

## 6. Scope guards

Correct. The spec **avoids** requiring keyword logic (011) and normalization (012) — the stub is explicitly trivial (`const`/`type`), Part 1 forbids "real keyword logic" (line 133), and Decisions d + the Scope guard block (lines 84–88) draw the lines cleanly against roadmap line 129 (keyword/Ajv parity is S2-later, not 010). The path-bearing-error test (Part 1.5) correctly leaves a *seam* item 011 needs (structured path) without requiring 011's logic. Good.

---

## Prioritized fix list

**BLOCKING (gaps that let bugs through):**
1. **G1** — add a SECOND provider impl and prove both swap through the same `validate`/result surface. (Without this the *port* is never tested as a port.)
2. **E1** — decide & test zero-error rejection (struct guard, or document-as-provider-contract); AC line 96 is currently unfalsifiable.
3. **E5** — add JSON-null / hasheq / list / string values to the validate matrix and assert `validation-ok-value` round-trips them `equal?`.
4. **G2** — assert handle reuse: compile once, validate many (the literal TS "called multiple times" contract).
5. **G3** — assert two handles from the same provider are independent (no shared mutable state).
6. **P1** — fix the banned-set inconsistency (AC line 100 must include `racket/port`, matching line 141 and the 008 precedent).
7. **AC-exhaustive** — add closed-set negative checks: `(validation-result? 42)`→#f, a bare `validation-error` is not a result.

**SUGGESTED (robustness):**
8. **G5** — pin stub `compile` behavior on a garbage/invalid schema (raise vs defer).
9. **E2** — a MANY-errors (≥2) result case.
10. **E4** — a mixed string/integer `path` (`'("items" 0 "name")`) to exercise the integer-segment contract.
11. **E3/E6** — negative-accessor raises; non-jsexpr value behavior pinned.
12. **G4** — state cross-provider handle behavior (or note it's vacuous under the recommended encoding).
13. **P2/P3** — state the walk's isolation entry point + restate the test-submodule scope limit.

**Nitpicks:** REPL one-liner is encoding-specific (already flagged in-spec); the "S1 or types-only" require looseness is intentional and captured in Validation Results.
