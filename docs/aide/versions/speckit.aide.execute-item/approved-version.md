# Reviewer Feedback — queue-001 Item 001 (Error-code and protocol-version constants)

**Iteration:** 001 (FRESH re-review — supersedes the earlier 4/10, which ran in a race before the test file existed)
**Reviewer:** Code Reviewer (aide-execute team)
**Verdict:** APPROVED — no revision required
**Overall rating:** 9/10
**`raco test mcp/core/types/` run by reviewer:** "22 tests passed", EXIT 0.

---

## Summary

Both deliverables are present, correct, and the test is a genuine upstream-drift detector.
I re-read both files on disk, re-ran the suite (22/22, exit 0), and empirically verified the
two anti-vacuous-pass properties (value mismatch → fail; missing TS file → hard fail). The
progress bookkeeping and the spec's Decisions & Trade-offs are finalized correctly. This is a
strong, ship-ready implementation.

---

## Verification performed (this review)

1. **`raco test mcp/core/types/`** → `22 tests passed`, exit 0. Confirmed both
   `constants.rkt` and `constants-test.rkt` compile and load within the collection.
2. **Anti-vacuous (value drift):** temporarily set `PARSE-ERROR` to `-99999` in
   constants.rkt → test FAILED 2/22, at the `PARSE_ERROR (constants.ts)` AND
   `ParseError (enums.ts)` assertions (proving the dual-file cross-check is live).
   Reverted → back to 22/22.
3. **Anti-vacuous (missing checkout):** temporarily renamed `enums.ts` → test FAILED LOUDLY
   with the exact message "TS checkout file missing: …/enums.ts (enums.ts). The parity test
   requires the typescript-sdk/ checkout…" (NOT a skip, NOT a pass). Reverted.
4. **progress.md:** `mcp/core/types/constants.rkt` is now ✅; the single acceptance box
   "Error codes + version constants match TS `constants.ts`/`enums.ts` byte-for-byte" is
   `[x]`; all four sibling `core/types/*` deliverable rows remain 📋 and every other
   acceptance box remains unchecked. Exactly as the Completion Reminder requires.
5. **Decisions & Trade-offs:** filled in (dated 2026-06-16) covering binding names, the
   curated provide, the LATEST splice, the minimal requires, the `define-runtime-path`
   choice (with the rationale for preferring it over `collection-path`), inline extractor
   location, the `regexp`→`pregexp` fix, underscore normalization, and the last-enum-member
   edge case. Honest and complete.

---

## Test-integrity assessment (the core deliverable)

The test is a true file-reading parity test, not value-mirroring. Confirmed each required property:

- **cwd-robust path anchoring:** `define-runtime-path` with a `../../../../` walk to the
  repo root — resolves to source/compiled location, not cwd. (constants-test.rkt:19–22)
- **Loud hard-fail on missing/unreadable file:** `read-ts-source` checks `file-exists?` and
  wraps the read in `exn:fail?` → `(fail …)` naming the path/label. (25–34) Verified live.
- **Underscore normalization:** `parse-ts-int` strips `_` before `string->number`, with an
  explicit regression assertion that `ParseError` reads as `-32700`. (39–40, 108–109)
- **Std codes asserted in BOTH files:** the 5 standard codes are checked against
  `constants.ts` (`ts-const-int`, 112–121) AND `enums.ts` (`ts-enum-int`, 124–133), so an
  upstream divergence between the two files fails.
- **MCP codes in enums.ts only:** the 4 MCP codes checked only via `ts-enum-int`. (136–146)
- **LATEST-appears-twice anchoring:** `ts-const-string` anchors on
  `export const <NAME> =`, so `LATEST_PROTOCOL_VERSION`'s definition is captured rather
  than its bareword reference inside the SUPPORTED array. (77–84) Correct.
- **-32042 last-member, no trailing comma:** `ts-enum-int` uses
  `(?m:^\s*Name\s*=\s*(-?[0-9_]+)\s*(?:,|$))`, so the comma is optional — the final enum
  member is not dropped. (61–64) Directly asserted at 144–146.
- **Doc-comment prose immunity:** the enum regex is line-anchored (`^\s*Name\s*=`), so the
  member names appearing inside JSDoc prose (e.g. "protocol revision 2026-07-28") cannot
  match. (61–63) Correct.
- **Whole-ordered-list SUPPORTED check:** `ts-supported-list` parses the array, resolves the
  leading `LATEST_PROTOCOL_VERSION` reference to its string, and the assertion is a single
  `check-equal?` on the whole 5-element ordered list — order and length both matter.
  (89–105, 155–156)
- **Diagnosable "not found":** every extractor `(fail …)`s with the missing name on no
  match (no silent `#f` that would pass), aiding future-TS-rename diagnosis. (49, 66, 82, 94)
- **Structural self-checks:** length = 5, head = LATEST, all 9 codes negative exact
  integers. (162–171)

22 checks total (≥ 18 expected by the spec). pregexp throughout (correct — plain `regexp`
lacks `\s` in Racket, a subtlety the Worker hit and documented).

## constants.rkt assessment

Unchanged from the prior review and correct: `#lang racket/base`, requires nothing else
(Portability NFR), explicit curated provide of all 13 bindings (no `all-defined-out`), all
9 error codes exact and kebab-case, 4 version/jsonrpc bindings correct,
`SUPPORTED-PROTOCOL-VERSIONS` = 5 ordered entries with head spliced by reference to
`LATEST-PROTOCOL-VERSION`, `_meta` keys correctly omitted (scope guard honored).

---

## Minor / NOTE (non-blocking — do NOT require revision)

- **[NOTE]** `ts-supported-list` hard-codes the `SUPPORTED_PROTOCOL_VERSIONS` name in its
  regex rather than taking a `name` param like the other helpers — fine (only caller), just
  slightly asymmetric. No action needed.
- **[NOTE]** `ts-const-string`'s capture `[^'\"]*` would not handle an embedded quote or
  escape in a version string. Not a concern for date-shaped version literals; flag only if a
  future string constant could contain quotes.
- **[NOTE]** The string-list element parse splits on `,` then validates each element; a
  version string containing a comma would break it. Again not a real risk for these values.

None of these affect correctness for the actual TS source and none warrant revision.

---

## Verdict

All acceptance criteria are met, the test is a rigorous live upstream-drift detector with
both anti-vacuous properties empirically confirmed, and the bookkeeping is finalized exactly
per the Completion Reminder. APPROVED, 9/10.
