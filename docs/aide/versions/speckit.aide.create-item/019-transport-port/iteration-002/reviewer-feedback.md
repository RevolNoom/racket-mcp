# Reviewer Feedback — Item 019: Transport port (M6) — Iteration 002

Canonical spec: `docs/aide/items/019-transport-port.md` (256 lines — within R2 ≤400 budget).
Re-review of the 4 critical gaps + 2 minors raised in iteration 001.

**Verdict: GREEN-LIGHT (implementation-ready).** All four critical gaps are now pinned by falsifiable acceptance criteria backed by concrete tests. No regressions. Rating 9/10.

---

## Iteration-001 gaps — all resolved

### C1 (field contracts decorative) — RESOLVED
- AC line 79/80 now require `make-message-extra-info` and `make-transport-send-options` to be `define/contract` with field contracts enforced, raising `exn:fail:contract?`. Implementation Steps 113–114 cite the house precedent `auth.rkt:81` and spell out the keyword contracts.
- Rejection tests are falsifiable: AC 91 + Testing Part 6 (lines 211–214) cover `#:session 42`, `#:auth "not-auth-info"`, `#:related-request-id 'sym`, `#:resumption-token 99`. A bare constructor would now fail these `check-exn exn:fail:contract?` assertions. Good — the contracts are no longer decorative.

### C2 (default-raise untested) — RESOLVED
- AC line 87 + Testing Part 3 (lines 172–182) add a `partial-transport` stub that omits `transport-send` and assert `(check-exn exn:fail? (λ () (transport-send pt msg)))`. This is the only construction that proves "missing impls are caught early," and it now exists. A non-raising fallback (e.g. returning `(void)`) would fail this test.

### C3 (on-message extra-info shape unasserted) — RESOLVED
- AC line 89 + Testing Part 4 (lines 184–204): handler captures BOTH args, is invoked with a real `make-message-extra-info`, and asserts `check-pred message-extra-info?` on the captured extra plus all three field accessors. The `extra = #f` unauthenticated path is also asserted (`got-extra` becomes `#f`). The `message-extra-info`↔`on-message` linkage that justifies this module is now exercised.

### C4 (send arity + accept-and-ignore unproven) — RESOLVED
- AC line 88 + Testing Part 2 (lines 167–170): `transport-send` tested in BOTH 2-arg and 3-arg forms, with `related-request-id` as a string AND an exact-integer, all `check-not-exn`. This pins arity dispatch and proves port-level accept-and-ignore of a non-`#f` related-request-id.

### Minors — RESOLVED
- Zero-arg `(make-message-extra-info)` → all-`#f`: AC 90 + Testing Part 5 (line 208).
- `session`-field TS divergence: Decisions line 245 now documents it has no TS `MessageExtraInfo` counterpart, is sanctioned by queue-003.md, and is distinct from `transport-session-id` (per-transport vs per-message). Disambiguation is explicit.

---

## Non-blocking implementation hints (do not require another iteration)

1. **`define-generics` optional-arg declaration.** The stub uses `(transport-send t msg [opts #f])`, and the C4 test calls both 2- and 3-arg forms. `racket/generic` method headers don't take Racket-style optional args directly the way a plain `define` does — the worker may need to declare the generic to accept the optional positional (or the concrete supplies the default while the generic header lists `opts`). The C4 test will *catch* a wrong choice (the 3-arg or 2-arg call will error), so the requirement is falsifiable as specified; this is just a heads-up on the mechanism so the worker doesn't burn a cycle.
2. **`on-error` assertion precision.** Testing Part 4 line 204 invokes the error sink with a built `exn:fail` and says "assert captured error." Consider `(check-pred exn:fail? got-err)` rather than a mere truthiness check, so a handler that drops the argument is caught. Optional polish.
3. **Cosmetic:** AC 92 says `#:resumption-token 42` while Testing Part 6 (line 214) uses `#:resumption-token 99`. Both are non-strings, both rejected — no functional difference; align if convenient.

---

## Regression check
- Public `provide` surface unchanged (AC 85). Imports still L0/L1 only (AC 84). Size 256 lines, within R2. Prerequisites (make-auth-info two-required-keyword signature, json-object? via mcp/core/main.rkt) unchanged and still accurate. Nothing removed or weakened.

Ship it.
