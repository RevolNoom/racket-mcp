# Reviewer Feedback — Item 005 (iteration-002): Public types + normalized-superset façade (N1)

**Reviewer:** reviewer (test-edge-case-reviewer, AIDE create-item)
**Date:** 2026-06-19
**Spec:** `docs/aide/versions/speckit.aide.create-item/005-public-types/iteration-002/item.md`
**Prior iteration:** iteration-001 (rated 7/10, needs_revision=true; criticals C1–C5, suggestions
S1/S2/S4/S5, plus the `tool-exec`/Group-6 minors).
**Verdict:** **APPROVE — `needs_revision = false`, overall 9/10.** Every iteration-001 critical is
genuinely and correctly resolved, each one re-verified against the delivered
`spec-2025-11-25.rkt` / `spec-2026-07-28.rkt` structs. Remaining items are minor, non-blocking
nits that an implementer will handle naturally given the operational rules already in the spec.

---

## Re-verification of each prior issue (against delivered code)

### C1 — elicit/sampling params no longer carry a phantom `request-meta`; elicit `meta` is 2025-only ✅
Group 4 is now split into 4a (CLIENT request params → `facade-request-meta`), 4b (server→client +
`create-message` → plain `meta`), and 4c (2025-only). Verified against code:
- `elicit-request-form-params`: 2025 `(mode message requested-schema task meta)`, 2026
  `(mode message requested-schema)`. The spec (line 329) correctly marks **both `task` AND `meta`
  as 2025-only**, requires `normalize-from-2026` to set both `absent`, and requires
  `denormalize-to-2026` to refuse a non-absent `meta` as well as `task` (line 332, Testing Part 3
  line 666). Correct.
- `elicit-request-url-params`: same treatment (line 330). Correct.
- `create-message-request-params`: 2026 `(… tool-choice meta)` with `meta` =
  `(opt/c json-object?)` (verified the contract: last field is `(opt/c json-object?)`), 2025
  `(… tool-choice task meta)`. Spec (line 328) correctly marks `meta` as shared-plain and `task`
  as 2025-only, and explicitly routes it OUT of the envelope group. Correct.

### C2 — per-primitive `meta` shape stated (envelope vs plain object) ✅
Group 4 intro (lines 273–301) names the two shapes and assigns them per primitive; the 4a table's
new `meta`-field-type column and the 4b table both state the type explicitly. Verified: 2026
`call-tool-request-params/c` ends in `request-meta?` (envelope); 2025 `call-tool-request-params/c`
`meta` is `(opt/c json-object?)` (plain). The acceptance criterion (line 479–482) and Testing
Part 1 step 6 (lines 627–632) assert the type directly:
`(facade-request-meta? (facade-call-tool-request-params-meta f26))` true, while the 2026
`create-message` `meta` is plain/absent and NOT `facade-request-meta?`. This is the exact S1 guard
I asked for. Correct.

### C3 — present/absent fixtures explicitly enumerated; 2025-only absence assertions are HARD ✅
New **Testing Part 0** (lines 579–602) enumerates the six fixtures to hand-author with a table
(purpose + pairing), implementation step 10 (lines 544–560) repeats the list, the Required
Services table adds a "NEW hand-authored fixtures" row (line 793), and the acceptance criterion
(lines 475–478) states the 2025-only-field absence assertions are "a HARD requirement, not
optional." Verified my iteration-001 findings are correctly carried in: no `*list-roots*` fixture
exists in either revision; the existing 2025 `tools-call-request.json` has no `params.task`; the
spec correctly flags `2026-input-responses.json` as a MAP, not a `tools/call` params fixture
(line 600–602), and routes the `input-responses` present-test to a proper params fixture. This is
the strongest part of the revision — the vacuous-skip hole is closed.

### C4 — result `rest` cross-revision parity rule + home-revision survival assertion ✅
New Group-2 `rest`-parity callout (lines 245–256) + Decisions entry (lines 964–969) + acceptance
criterion (lines 496–500) + Testing Part 2 mandatory block (lines 640–657). The rule is correct
and well-reasoned: `rest` is shared, NOT revision-gated (loose-result semantics identical in both
revisions), passes through on denormalize to EITHER revision, never refused; the refusal rule
applies only to revision-gated NAMED fields. Verified both result structs carry `rest`
(2025 `list-tools-result (tools next-cursor meta rest)`; 2026 adds `ttl-ms cache-scope result-type`).
The test isolates the behavior well: keep `rest` populated but named 2026-only fields `absent` to
prove `rest` is not refused, contrasted against `ttl-ms` present making denormalize-to-2025 raise.
The empty-`rest`-is-`{}`-not-`absent` + no-phantom-key assertion (S2) is included. Correct.

### C5 — `ElicitResult` `result-type` hedge removed; RESULT vs PARAMS distinguished ✅
Group-2 table row + callout (lines 230–238) and Decisions entry (lines 959–963). Verified: 2026
`(struct elicit-result (action content meta result-type rest))`, 2025
`(struct elicit-result (action content meta rest))`. Spec correctly states
`action`/`content`/`meta`/`rest` shared, `result-type` 2026-only on the RESULT — and explicitly
contrasts it with elicit-PARAMS where `meta` is 2025-only. The "No open questions remain" note
(lines 1004–1006) closes it. Correct.

### S4 — revision-parameterized method→façade dispatch + both-revisions dispatch test ✅
Group-8 dispatch is now `(dispatch-for method revision)` (lines 422–435), with a Decisions entry
(lines 983–988), acceptance criterion (lines 490–495), and Testing Part 4 (lines 676–691)
including the mandatory both-revisions `tools/call` collision test asserting the two
parser/normalizer pairs are DIFFERENT, plus a second both-revisions method. Correctly identifies
the five dual-revision methods and the single-revision-resolves-only-for-home rule. Correct.

### S5 — Group-0 require-both-revisions-convert-to-one-struct-type ✅
Group-0 note (lines 159–167) + edge-case (lines 724–731) + Decisions (lines 989–998). The rule is
exactly right: pure aliasing of a 003 struct without rebuilding 004's values would leave a
2026-normalized value as a 004 struct that FAILS the aliased `facade-X?`, breaking the SAME-façade
core claim. The added S5 test (a 2026-built Group-0 value satisfies the SAME `facade-X?` as the
2025-built one) guards it regardless of modeling choice. Correct.

### Minors ✅
- `tool-exec` accessor: Group-1 source-accessor note (lines 206–211) — verified the 2025 struct
  field is `exec` (accessor `r25:tool-exec`) and there is also a separate `tool-annotations` struct;
  the note also correctly flags `tool-annots` for the `tool` annotations field. Accurate.
- Group-6 garbled fragment: fixed (lines 380–383) — `roots/list_changed` and `tasks/status`
  correctly listed as 2025-only (verified gone in 2026: grep count 0), and `resources/updated`
  correctly excluded as shared (verified present in 2026; both structs are
  `(method payload)`). Accurate.

---

## Remaining nits (non-blocking — do NOT require another iteration)

1. **Group-3 field table omits the 2025 `rest`.** Verified 2025
   `(struct list-roots-result (roots meta rest))` — it has a `rest` field the Group-3 table (line
   265–266) does not list (it shows `roots` + `meta` only). This is NOT a logic gap: the
   `denormalize-to-2026` "emit EXACTLY `{roots}`" rule (lines 269–270, Testing Part 3 line 669–670)
   operationally covers dropping any 2025 `rest`, and `normalize-from-2025` will copy `roots`/`meta`
   into the façade regardless. Recommend a one-line note that 2025 `list-roots-result` also has a
   `rest` (loose) the façade folds into the bare-{roots} emit, for completeness — but this will not
   cause a wrong build. (The Group-2 `facade-list-roots-result` is correctly NOT in the result table
   because it is bare in 2026; just the 2025-side `rest` is under-documented.)

2. **`facade-request-meta` shared `progress-token`/`related-task` extraction is stated but worth a
   test assertion.** The spec correctly says (lines 296–301, 318–319) that for a 2025 client-params
   message the façade must EXTRACT `progress-token`/`related-task` from the flat 2025 `_meta` map
   into the envelope's named shared fields (2025 has no `request-meta` struct — these ride inside
   `_meta`). The edge-case list (lines 718–723) asserts they "survive from both," which covers it,
   but an explicit assertion that a 2025 `call-tool` whose `_meta` carries `progressToken` yields
   `(present? (facade-request-meta-progress-token …))` would make the extraction non-vacuous.
   Suggested, not required.

3. **Count range `~75–85` is wide** but Part 6 records the exact number and the drift-detection
   step makes it self-correcting. No change needed.

---

## Bottom line

The Worker addressed every critical correctly and verifiably — the Group-4 `meta`-shape split
(C1/C2), the hand-authored fixture enumeration with HARD absence assertions (C3), the `rest`-parity
rule with an isolating test (C4), the ElicitResult resolution (C5), the revision-parameterized
dispatch (S4), and the Group-0 conversion rule (S5) are all present, internally consistent, and
match the delivered structs. The §4 inventory is now a trustworthy build contract. The test plan is
non-vacuous (Part 0 fixtures + HARD assertions + Part 6 count + drift-detection). An implementer can
build and test this without guessing. Approving; the two nits above are polish the implementer can
fold in during execute-item.
