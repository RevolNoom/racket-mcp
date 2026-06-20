# Reviewer Feedback — Item 002 (JSON-RPC type guards), iteration-001

**Verdict: APPROVE. No revision required.**
Rating: 9/10. `raco test mcp/core/types/` → **339 tests passed, EXIT=0** (22 item-001 + 317 item-002), reproduced by the reviewer.

## Scope reviewed
- `mcp/core/types/guards.rkt` (140 lines)
- `mcp/core/types/test/guards-test.rkt` (304 lines)
- Cross-referenced against the authoritative TS source `typescript-sdk/packages/core/src/types/schemas.ts` (lines 95–199) and `progress.md`.

## Hard-gate parity properties — ALL PASS

1. **Envelope-only strictness / inner-error non-strict (THE HARD GATE).** Verified PASS.
   - `only-keys?` is applied to top-level keys only and is never recursed.
   - `valid-error-object?` (guards.rkt:118–121) checks only `code` (exact-integer) and `message` (string) presence/type and does NOT key-restrict the inner `error`. So `error:{code,message,foo:1}` → `is-jsonrpc-error?` TRUE (test lines 123, 240–243).
   - Confirmed against TS: `JSONRPCErrorResponseSchema` wraps `error` in a plain `z.object({...})` with NO `.strict()` (schemas.ts:173–192), while the outer envelope IS `.strict()`. Exact match.
   - **Non-vacuity proved:** I temporarily added `(only-keys? e '(code message data))` to the inner error check; the suite produced exactly 3 failures naming the inner-error-extra-key cases, then passed again on revert. The gate is live.

2. **id-less-error TRAP.** PASS. `is-jsonrpc-error?` treats id as optional (`(or (eq? id 'absent) (valid-id? id))`, guards.rkt:128–129); `err/no-id` classifies as error+response and is rejected by notification (no `method` matches, plus error key present). Test asserts all five predicates on `err/no-id` (lines 198–202). Matches `RequestIdSchema.optional()` (schemas.ts:176).

3. **id validity.** PASS. `valid-id?` = `(or (string? x) (exact-integer? x))`. Rejects `'null`, `1.0` (inexact flonum), `1.5`, booleans, objects. All covered (lines 45–48, 213–215). `exact-integer?` correctly rejects `1.0` — matching Zod `.int()`. Matches `z.union([z.string(), z.number().int()])` (schemas.ts:136).

4. **params object handling.** PASS. `params-ok?` requires present params be a `json-object?`; absent is fine; `params:5` and `params:'null` reject (test 51–52, 70, 246–249). Matches `BaseRequestParamsSchema.loose().optional()` / `NotificationsParamsSchema.loose().optional()` (schemas.ts:101–102, 114–115) — a present params must be an object, contents unvalidated.

5. **Non-hash / hostile inputs never crash.** PASS. `json-object?` gate = `(and (hash? v) (immutable? v) (hash-eq? v))` short-circuits before any field access. The hostile-inputs loop (test 160–172) runs all 5 predicates over 14 inputs (numbers, strings, `'null`, lists, vector, box, mutable hash, string-keyed hash, empty/foo hasheq) with `check-not-exn` + `check-false`. String-keyed and mutable hashes correctly rejected as non-read-json shape.

6. **No-batch introspection is non-vacuous.** PASS. Uses `module->exports` with a positive-control loop over the 5 real predicates AND a `(check-equal? (length provided) 5)` anchor (test 255–271). **Non-vacuity proved:** I temporarily added an `is-jsonrpc-batch?` export; the suite produced exactly 4 failures (batch-name memq, batch regex, dynamic-require, and the length=5 count), then passed on revert. Confirms zero `batch` matches in TS too (grep returns nothing).

## Additional correctness confirmed
- **Union identity** `response ≡ (or result-response error)` asserted over the full fixture set including overlapping shapes (test 147–155), plus per-case on the TS cross-check rows.
- **Strict-envelope ambiguity** cases: both `result`+`error` → all three response-side checks false; `id+method+result` → request & result-response & response false (tests 178–187). Correct because `only-keys?` rejects the extra arm.
- **jsonrpc discrimination**: missing / `"1.0"` / `2.0` (flonum) / `2` (int) all rejected by `equal?`-to-string check across all five predicates (tests 217–228).
- **TS parity cross-check** reads the live `guards.test.ts` fixture path and `fail`s loudly if absent (test 278–303) — a genuine upstream behavior check for the 3 response-side predicates.
- **Booleans returned, not truthy values**: every predicate is wrapped with a trailing `#t` / `or`, returning real booleans.
- **Portability**: `guards.rkt` requires only `racket/base` + `(only-in "constants.rkt" JSONRPC-VERSION)`. No subprocess/socket. Explicit curated `provide` of exactly 5 names; no `all-defined-out`. Internal helpers not provided.

## progress.md / parity-matrix
Confirmed correct. `docs/aide/progress.md:49` shows `✅ mcp/core/types/guards.rkt` (📋→✅). Sibling `core/types/*` rows untouched. The Worker's claim that there is no guards-specific S1 acceptance checkbox is **correct** — the S1 acceptance items (line ~125, capability/version guards) are stage-level and depend on later items; none should be checked here, and none were. No icon reverted.

## Minor / non-blocking notes (NOTE severity — do not require revision)
- [NOTE] `valid-jsonrpc?`, `is-jsonrpc-result-response?`, and `valid-error-object?` pass `#f` as the `hash-ref` default for `result`/`error`/`message`, then test the result with `json-object?`/`string?`. This is correct (an absent field → `#f` → fails the type test) and never raises because `valid-jsonrpc?` already guaranteed a hash. Consistent and safe; the mixed use of `#f` vs the `'absent` sentinel is intentional (sentinel only needed where a present `'null` must be distinguished from absent — i.e. `id` and `params`). No action needed.
- [NOTE] The test file's pinned check count is enforced implicitly via the `length provided = 5` and the exhaustive named checks rather than a single integer assert; the spec mentioned an "exact pinned check count." The 339-total / 317-item-002 count is stable and the suite is demonstrably non-vacuous, so this is acceptable. If a literal pinned-integer assert is desired for future drift detection, it could be added, but it is not a correctness gap.

## Conclusion
The implementation is a faithful, parity-correct port of the TS JSON-RPC envelope guards. Every hard-gate property holds and is backed by a live, non-vacuous test (proven by deliberate mutation). No correctness, test-integrity, or wire-parity gaps found. Ship it.
