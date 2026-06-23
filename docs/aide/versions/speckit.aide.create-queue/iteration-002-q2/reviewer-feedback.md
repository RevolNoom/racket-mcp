# Reviewer Feedback — Work Queue 002 (Stage S2 Foundation) — Iteration 002 (RE-REVIEW)

**Artifact under review:** `docs/aide/versions/speckit.aide.create-queue/iteration-002-q2/queue-002.md`
**Prior critique:** `docs/aide/versions/speckit.aide.create-queue/iteration-001-q2/reviewer-feedback.md` (7/10, needs_revision, 7 fixes).
**Reviewer role:** Reviewer in the AIDE create-queue workflow.
**Date:** 2026-06-22.
**Verdict:** All 7 prior fixes applied AND verified factually correct against the `typescript-sdk/`
checkout. No regression in scope, numbering, sizing, or format. No new blocking issues. **Ready for
create-item.** `needs_revision=false`.

---

## Fix-by-fix verification (applied? correct?)

### Fix 1 — `*.test.ts` paths → `packages/core/test/{shared,validators}/…` — APPLIED, CORRECT
Header line 6 now lists every fixture under `packages/core/test/`: `test/shared/uriTemplate.test.ts`,
`test/shared/toolNameValidation.test.ts`, `test/shared/stdio.test.ts`, `test/shared/auth.test.ts`,
`test/shared/authUtils.test.ts`, `test/validators/validators.test.ts`. Items 013/014/016 echo the
`test/shared/…` form. Verified against the checkout: the `test/shared/` tree contains exactly these
files (plus `traceContextMeta.test.ts`), and `test/validators/validators.test.ts` exists. Confirmed
**no** `*.test.ts` sits under `src/` (`ls src/shared/*.test.ts` → no such file). Source paths and test
paths are now cleanly separated. Resolved.

### Fix 2 — Item 011 reframed (net-new Racket-native, not a `fromJsonSchema.ts` mirror) — APPLIED, CORRECT
Item 011 now states `fromJsonSchema.ts` is a "~43-line, keyword-**free** wrapper" mirrored only for the
**wrapper shape**, while keyword semantics are "net-new Racket-native design (the Ajv/cfWorker collapse
per §4.5/§8)" targeting `validators.test.ts` behaviour. Verified: `fromJsonSchema.ts` is 43 lines and
contains no keyword evaluation; vision §8 excludes Ajv/cfWorker. The framing is now accurate — a Worker
opening the 43-line wrapper will no longer expect keyword logic there. Resolved.

### Fix 3 — Item 015 `AuthInfo` → `types/types.ts:435` with exact field surface — APPLIED, CORRECT
Item 015(2) now states "`AuthInfo` shape itself is defined in TS at `types/types.ts:435` (not in
`auth.ts`)" and reserves the `auth.ts`/`authUtils.ts` pointer for "token/metadata helpers only." Field
surface listed: `token`, `clientId`, `scopes`, optional `expiresAt`, optional `resource` (a URL),
optional `extra`. Verified against the checkout: `AuthInfo` is at `types/types.ts:435`; fields match
(`token: string`, `clientId: string`, `scopes: string[]`, `expiresAt?: number`, and downstream
`resource?`/`extra?`). The acceptance test in 015(c) asserts exactly this surface, so it is now
checkable. Resolved.

### Fix 4 — Item 016 max-buffer-overflow + CRLF + skip-non-JSON behaviours — APPLIED, CORRECT
Item 016 now mandates all three `ReadBuffer` behaviours in both deliverable and tests:
(a) max-buffer enforcement with `STDIO_DEFAULT_MAX_BUFFER_SIZE = 10 MB` (`10 * 1024 * 1024`), append
past it **throws**; (b) CRLF tolerance (strip trailing `\r`); (c) skip non-JSON lines (continue, NOT a
hard error — explicitly flagged so the Worker doesn't "correct" it to a throw). Verified against
`shared/stdio.ts`: constant is `10 * 1024 * 1024`, `append` throws on overflow, parse line does
`.replace(/\r$/, '')`, and a `SyntaxError` triggers `continue`. The acceptance harness adds overflow,
CRLF, and non-JSON-skip cases. Resolved — and the "do not fix" flag on skip-non-JSON is exactly the
right call.

### Fix 5 — Item 011 named deferred keywords + per-keyword policy assertion — APPLIED, CORRECT
Item 011 now names the deferred-but-common keywords explicitly: `pattern`, `minLength`/`maxLength`,
`minimum`/`maximum`, `additionalProperties`, `uniqueItems` — each handled per a single documented policy
(ignore-with-warning OR reject), "never silently mis-validated." The acceptance criteria upgrade from
"an unsupported keyword" (singular) to "**each** of the named deferred keywords … is handled per the
documented unsupported-keyword policy and is listed in the module docs." This is the conscious, named cut
the prior review asked for, and it keeps 011 week-sized. Resolved.

### Fix 6 — Item 015 `get-display-name` added AND 5-vs-8 reserved-key reconciled — APPLIED, CORRECT
Item 015(1) now provides `get-display-name` with the exact precedence `title → annotations.title → name`
and notes M12b/S6b needs it. Verified: `metadataUtils.ts` is 26 lines containing only `getDisplayName`
with that precedence (incl. empty-string-title fallthrough). The acceptance test 015(a) asserts the
precedence including the empty-string case. 5-vs-8 reconciled: the item documents that `constants.ts`
defines **eight** keys — the five S1 captured plus three W3C trace-context keys
`traceparent`/`tracestate`/`baggage` (SEP-414) — and resolves it by defining the three constants in M5c
(or scoping out with an explicit S1 follow-up), with the discrepancy documented either way. Verified:
`constants.ts` defines all eight (`TRACEPARENT_META_KEY`/`TRACESTATE_META_KEY`/`BAGGAGE_META_KEY`), and
S1 `mcp/core/types/constants.rkt` captures only the five `io.modelcontextprotocol/*` keys (lines 60–64,
trace-context absent). The discrepancy is real and now explicitly handled, not silently dropped.
Resolved.

### Fix 7 — Item 010 deliberate compile/validate split vs TS `getValidator` — APPLIED, CORRECT
Item 010 now states the TS `jsonSchemaValidator` is a "single fused method `getValidator(schema) →
(input) => result`" and that the Racket port "**deliberately splits this into two ops**" (compile →
handle, validate → result) — "an intentional, more-idiomatic factoring … **not** a 1:1 mirror." Verified:
`validators/types.ts` exposes `interface jsonSchemaValidator { getValidator<T>(schema): JsonSchemaValidator<T> }`
where `JsonSchemaValidator<T> = (input) => result`, i.e. compile+validate fused. The S9 parity reviewer
is now forewarned. Resolved.

---

## Regression check

- **Scope (S2 only).** Header line 7 still confines to M3/M4/M5a–M5e and explicitly defers all S3+
  modules (M6/M10/M7/M8/M9/M11/M12/M13) to queue-003+. M5e/`stdio.rkt` orphaned-until-S6a discipline
  preserved in three places (header, "Why", item 016). No S3 bleed introduced by the revision.
- **Numbering.** Items 010–018, sequential, no gaps. S1 owns 001–009 (confirmed against
  `docs/aide/items/`). No duplicates. Header still states "continuing after queue-001's item 009."
- **Sizing.** Still 9 items, week-sized. The Fix-5 bounding keeps item 011 from overrunning. Item 015
  grew (get-display-name + AuthInfo surface + 3 trace constants) but remains a cohesive small-module
  pairing — still fits. No split needed.
- **Format.** `### Item NNN: Title` + prose, no in-item checkbox lists, "Why this batch" preamble,
  portability item (017) + demo/closeout item (018) mirroring queue-001's 008/009. Consistent.

## New issues introduced by the revision

None blocking. Minor nitpicks only (do not force another round):
- Item 015 offers the implementer a choice (define the 3 trace constants in M5c **or** file an S1
  follow-up). This is acceptable latitude, but create-item should pin one path so the acceptance test
  ("assert the three trace-context constants exist OR the S1 follow-up is filed") is deterministic. A
  spec-time decision, not a queue defect.
- Item 011's supported `format` set (`date-time`/`uri`/`email`) is narrower than the full TS format
  surface, but it is now explicitly bounded and policy-tested — acceptable week-1 cut.

## Bottom line

All 7 fixes landed and check out against the checkout. The parity pointers are now true and the
acceptance criteria match the TS baselines they invoke. Scope, numbering, sizing, and format are sound.
Queue is ready for create-item.
