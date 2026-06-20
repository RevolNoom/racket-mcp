# Reviewer Feedback — Work Item 001: Error-code and protocol-version constants

**Reviewer specialty:** testing strategy, testing prerequisites, edge cases.
**Snapshot reviewed:** `docs/aide/versions/speckit.aide.create-item/iteration-001/item.md`
**Ground truth cross-checked against:** `typescript-sdk/packages/core/src/types/constants.ts` and `enums.ts` (read directly at review time).
**Overall rating:** 8/10 — **needs_revision: false** (ship-able; the issues below are refinements, not blockers).

---

## Current coverage summary (what is already well-covered)

This is an unusually strong spec. Every one of the five ground-truth facts I verified independently is present and correct, and several are called out *more* sharply than I would have:

1. **Two-file / two-naming-style codes — CORRECT and well-handled.** The spec correctly states the five standard JSON-RPC codes live in BOTH `constants.ts` (as `PARSE_ERROR` consts) and `enums.ts` (as `ParseError` enum members), and that the four MCP-specific codes (`-32002/-32003/-32004/-32042`) live ONLY in `enums.ts`. Critically, the Testing Strategy requires asserting the standard codes against *both* files independently (Testing Strategy §4 bullets 1–2; Edge Cases "Standard codes duplicated across two files"). This means a future upstream divergence between the two files fails the test rather than silently passing. This is exactly the right design and matches the actual source (enums.ts:7–25, constants.ts:44–48).

2. **Ordered 5-entry `SUPPORTED_PROTOCOL_VERSIONS` — CORRECT.** The spec pins the exact ordered list `("2025-11-25" "2025-06-18" "2025-03-26" "2024-11-05" "2024-10-07")`, explicitly flags that the queue/vision prose only names three and that "the checkout is authoritative," names the three easily-dropped versions (`2025-06-18`, `2024-11-05`, `2024-10-07`), requires whole-list `check-equal?` (not membership), and adds a length-5 self-check. Verified against constants.ts:3 — exact match including order.

3. **`JSONRPC_VERSION = "2.0"` — CAPTURED.** The queue omitted it; the spec adds it (Description §3, binding count 13, constants.ts:41 confirmed).

4. **`DEFAULT_NEGOTIATED='2025-03-26'` older-than-`LATEST` — CAPTURED as intentional.** Both values pinned correctly; the list-head invariant (`head == LATEST`, with DEFAULT being the 3rd entry, not the head) is asserted. Confirmed constants.ts:1–2.

5. **Underscore-literal `-32_700` grep gotcha + vacuous-pass guard — EXEMPLARY.** The "Critical wire-format note" calls underscore normalization "the single most likely cause of a spurious test failure"; the algorithm strips `_` before parsing; there's a dedicated regression check that the extractor returns `-32700` for `ParseError`; and the vacuous-pass concern is handled three ways: (a) hard-fail if a TS file is missing/unreadable, (b) hard-fail if a constant name is not found (so a rename is diagnosable, not a silent `#f`), and (c) a manual-validation step that deliberately mutates a value and confirms the test FAILS, plus a rename-the-file step confirming a loud failure. The "primary assertion reads the TS files; hard-coded mirror is only belt-and-suspenders" framing is precisely the anti-vacuous design I'd ask for.

All required create-item sections are present: Description, Acceptance criteria, Implementation steps, Testing strategy, Dependencies, Decisions & Trade-offs, Completion Reminder, project-specific (Racket/raco/rackunit) adaptations, and the full Testing Prerequisites block (Required Services / Environment Configuration / Manual Validation Checklist / Expected Outcomes / Validation Results template). Line-number citations in the spec (enums 5–26, constants 1–3/41/44–48) all match the real files.

---

## Missing coverage (Suggested — refinements, none blocking)

These are extraction-robustness edge cases. The algorithm is correct in intent; these pin down places where a *carelessly written regex* could pass or fail wrongly. None rise to needs_revision, but folding them into the Testing Strategy would harden the test and pre-empt implementer mistakes.

### S1. `LATEST_PROTOCOL_VERSION` appears TWICE in `constants.ts` — concrete extraction trap (highest-value addition)

I verified this directly: `LATEST_PROTOCOL_VERSION` occurs on line 1 (its `export const` definition) AND on line 3 (referenced inside the `SUPPORTED_PROTOCOL_VERSIONS` array literal). `grep -c` returns 2.

Consequences the spec should pin:
- The `ts-string-named` helper for `LATEST_PROTOCOL_VERSION` MUST anchor on `export const LATEST_PROTOCOL_VERSION =` (start-of-declaration), not a bare `LATEST_PROTOCOL_VERSION.*'(...)'`. A greedy/dotall regex that doesn't anchor to `export const` risks matching across line 3 and capturing `'2025-06-18'` (the first quoted string after the reference) instead of `'2025-11-25'`.
- The `ts-string-list-named` helper must *resolve the leading bareword reference* `LATEST_PROTOCOL_VERSION` to its string value. The spec says to do this (Testing Strategy §3, third helper) but does not warn that the array element is an identifier, not a quoted string — so a regex that only captures `'...'` quoted entries will return FOUR strings, not five, and the length-5 self-check will (correctly) fail, but with a confusing message. Recommend: explicitly state the first array element is the identifier `LATEST_PROTOCOL_VERSION` and must be substituted, and add a check that the resolved list length is 5 *before* comparing, with a message distinguishing "extracted 4, reference not resolved" from "upstream changed the list."

This is the single most likely place a competent implementer still writes a subtly wrong test. Worth a sentence.

### S2. Regex word-boundary / substring discipline for enum members

In `enums.ts`, anchor each member match on a word boundary. `InvalidRequest`/`InvalidParams` share the `Invalid` prefix; `MethodNotFound`/`ResourceNotFound` share `NotFound`; `UnsupportedProtocolVersion` contains `ProtocolVersion` which also appears in the doc-comment prose (enums.ts:21 "protocol version"). A regex like `/ParseError\s*=\s*(-?[\d_]+)/` is fine, but the spec should state: match on `^\s*<Name>\s*=` (member-assignment form), case-sensitively, to avoid catching the substring inside a comment or a longer identifier. I confirmed the comment lines 16–17, 21 contain `clientCapabilities` / `protocol version` text — harmless for the `Name =` form, but only because the assignment anchor excludes them. Make the anchor explicit so the implementer doesn't drop it.

### S3. Trailing-comma vs no-trailing-comma in the enum

`UrlElicitationRequired = -32_042` (enums.ts:25) has NO trailing comma (it's the last member); the other eight DO. A numeric-capture regex that assumes a trailing `,` (e.g. `=\s*(-?[\d_]+),`) will FAIL to extract the last MCP-specific code — and `-32042` is exactly the spec-significant `UrlElicitationRequired`. The capture must tolerate an optional trailing comma / end-of-line. Add this to the edge-case list; it's a real, code-confirmed asymmetry.

### S4. Make the "≥18 checks" Expected-Outcome count exact, or drop the lower bound

Expected Outcomes says "check count is ≥ 18 (9 codes × from-enums + 5 codes from-constants + 3 version/jsonrpc + structural self-checks)." A `≥` bound can pass even if a whole category of assertions was accidentally omitted (e.g. the from-constants duplicate-check), as long as enough other checks exist. Since the assertions are fully enumerable, give an EXACT expected count (or assert each named category is present). This converts "enough checks ran" into "the right checks ran" — directly in the spirit of the anti-vacuous design the rest of the spec already embraces.

### S5. `DEFAULT_NEGOTIATED` not-in-head / ordering relationship is unasserted

The spec correctly pins DEFAULT and LATEST as distinct values and asserts `head == LATEST`. It does NOT assert that `DEFAULT-NEGOTIATED-PROTOCOL-VERSION` is a *member* of `SUPPORTED-PROTOCOL-VERSIONS` (it is — it's the 3rd entry, "2025-03-26"). A cheap, meaningful invariant: `(check-true (member DEFAULT-NEGOTIATED-PROTOCOL-VERSION SUPPORTED-PROTOCOL-VERSIONS))`. If a future upstream bump ever leaves DEFAULT pointing at a version no longer supported, that's a real negotiation bug this one-liner would catch. Optional but cheap and on-theme.

---

## Concrete test-case proposals (for the implementer's `constants-test.rkt`)

1. **Trailing-comma extraction (S3):** assert `(ts-int-named enums-src "UrlElicitationRequired")` returns `-32042` — the last, comma-less member. This is the regression that proves the regex isn't comma-dependent.
2. **Double-occurrence anchoring (S1):** assert `(ts-string-named constants-src "LATEST_PROTOCOL_VERSION")` returns `"2025-11-25"` (NOT `"2025-06-18"`), proving the extractor matched the `export const` on line 1, not the array reference on line 3.
3. **List-length-before-compare (S1):** assert the resolved `SUPPORTED_PROTOCOL_VERSIONS` list has length 5 with a message "reference splice unresolved?" before the whole-list `check-equal?`.
4. **DEFAULT membership (S5):** `(check-true (and (member DEFAULT-NEGOTIATED-PROTOCOL-VERSION SUPPORTED-PROTOCOL-VERSIONS) #t))`.
5. **Both-file agreement (already specified — keep):** `(check-equal? (ts-int-named constants-src "PARSE_ERROR") (ts-int-named enums-src "ParseError"))` and equal to Racket `PARSE-ERROR` — three-way.
6. **Negative-checkout (already specified — keep):** rename TS file → expect a `fail` with the path named, not a skip.

---

## Verdict

**8/10. needs_revision: false.** The spec is implementation-ready and gets all five ground-truth facts right, with a parity test designed to detect upstream drift and to fail loudly rather than vacuously. The five suggestions above (S1 the double-occurrence trap and S3 the trailing-comma asymmetry are the highest-value, both code-confirmed) would harden the extraction regexes against the specific shapes of the real TS files. They are refinements an implementer would ideally fold in, not gaps that should block execution. If the team prefers a hard gate on test robustness, fold S1 and S3 into the Testing Strategy edge-case list before execute-item; otherwise they can be addressed inline during implementation and recorded in Decisions & Trade-offs.
