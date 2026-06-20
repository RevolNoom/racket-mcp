# Reviewer feedback — Item 004 (spec-2026-07-28), iteration 001

**Verdict: APPROVE (no revision required). Rating 9/10.**

This is an exceptionally strong spec. I independently pre-computed the full RC diff
(name-diff of every `export interface|type` between the two TS spec files + schemas.ts +
constants.ts + enums.ts) BEFORE reading this document, then cross-checked the spec against
it line-by-line. The inventory is complete, the diff is accurate, the `_meta` envelope is
enumerated verbatim with a dedicated present-and-parsed test, and the testing strategy meets
the item-003 bar. Every line cite I spot-checked was correct. Findings below are refinements,
not gaps.

---

## #1 JOB — COMPLETENESS + DIFF: PASS

### Inventory completeness — COMPLETE
Cross-checked the spec's §A–S inventory against my name-diff (RC=150 exports vs old=145).
Verified directly in `spec.types.2026-07-28.ts`:

- **22 method literals** (`grep -cE "method: '"` = 22) — the spec's count is exact. The 22 =
  10 client requests + 3 InputRequests + 9 notifications. The spec covers all 22 by name.
- **ClientRequest** (2986) = 10 arms — matches §S exactly.
- **ServerNotification** (3007) = 9 arms — matches.
- **ServerResult** (3019) = 11 arms (EmptyResult, DiscoverResult, CompleteResult, GetPromptResult,
  ListPromptsResult, ListResourceTemplatesResult, ListResourcesResult, ReadResourceResult,
  CallToolResult, ListToolsResult, InputRequiredResult) — spec §S says "union over 11" ✓.
  Correctly notes CreateMessage/ListRoots/Elicit results are NOT in ServerResult — they're
  the `input-response/c` arms (438). This is a subtle trap the spec got right.
- **ClientResult** (3002) = `EmptyResult` only — spec §S ✓.
- No removed Task/Subscribe/initialize/ping/setLevel type is carried over. §G explicitly
  removes ping; §N explicitly removes `logging/setLevel`; the Diff §REMOVED is exhaustive
  and matches my list (whole Task subsystem, initialize family, subscribe/unsubscribe,
  URLElicitationRequiredError/-32042, ServerRequest, ToolExecution).
- No added type is missing. Discover (§E), Subscriptions (§K), Input family (§F),
  CacheableResult (§I), resultType (§B), typed errors (§R), `*ResultResponse` wrappers (§S)
  are all present. MetaObject/RequestMetaObject (§B/§C) present.

**Missing types: NONE.**
**Wrongly-carried (removed) types: NONE.**

### Diff accuracy — ACCURATE
- The CHANGED extends-clauses are correctly captured and NOT copied from 003:
  CallToolRequestParams / GetPromptRequestParams / ReadResourceRequestParams now extend
  `InputResponseRequestParams` (add `inputResponses?`+`requestState?`, lose `task?`) — §F/§J/§L/§M
  and Diff §CHANGED ✓. List/read results gain CacheableResult ✓. Tool loses execution ✓.
  CreateMessageResult/SamplingMessage/Elicit*Params lose `task?` ✓.
- The three 003 intersection-type traps (GetTaskResult/CancelTaskResult/TaskStatusNotificationParams
  = `Result & Task`) are correctly called out as NON-EXISTENT in the RC (Diff §REMOVED) — good,
  this was a specific worry and the spec handled it.

### `_meta` reserved-key envelope — VERIFIED VERBATIM
All 5 META_KEY strings match `constants.ts` exactly, with correct line cites:
- `io.modelcontextprotocol/protocolVersion` (PROTOCOL_VERSION_META_KEY, constants.ts:14) ✓
- `io.modelcontextprotocol/clientInfo` (CLIENT_INFO_META_KEY, :19) ✓
- `io.modelcontextprotocol/clientCapabilities` (CLIENT_CAPABILITIES_META_KEY, :27) ✓
- `io.modelcontextprotocol/logLevel` (LOG_LEVEL_META_KEY, :38, deprecated SEP-2577) ✓
- `io.modelcontextprotocol/related-task` (RELATED_TASK_META_KEY, :5) ✓
- `progressToken` (non-prefixed, spec.types:74) ✓
`RequestMetaObject` at line 70 ✓; `progressToken?` 74 ✓; protocolVersion key 83 ✓.
**`RequestParams._meta: RequestMetaObject` is REQUIRED (no `?`) at line 133** — the spec models
it as required and Testing Part 4 + the edge-case list assert "absent `_meta` → rejected". This
IS the distinguishing RC-only-field presence test, and it is present, specific, and correct.

### Testing-prereqs claims I verified independently
- **Error-code constants -32004/-32003 DO exist in `constants.rkt`** (lines 47/48:
  `UNSUPPORTED-PROTOCOL-VERSION -32004`, `MISSING-REQUIRED-CLIENT-CAPABILITY -32003`). The spec's
  Acceptance claim that these come from constants.rkt is CORRECT — no gap. (They're also at
  spec.types:374/366 and enums.ts:24/19.)
- **The `*-META-KEY` constants are NOT yet in `constants.rkt`** (grep confirms absent) — the spec
  correctly requires adding them additively (step 3, Dependencies, Decisions). Accurate.
- **No ready-made JSON fixtures exist.** Confirmed: `examples/` dir does NOT exist under
  `packages/core/src/types/`; all 124 `@includeCode ./examples/...json` refs are dangling; no
  `*2026*.json` anywhere. The spec's "hand-author fixtures, copy camelCase from .ts, 2026- prefix"
  decision is correct and well-justified (belt-and-suspenders with the Part-6 field-mapping test).

---

## Testing strategy review — STRONG

Mirrors 003's six-part structure and adds Part 4 (RC-only-fields present-and-parsed) as its own
part. Specifically good:
- **Canonical `jsexpr=?` (not byte equality)** reused from 003 — correct; explicitly NOT raw bytes.
- **Per-union-arm fixtures** enumerated with exact arm counts (ContentBlock 5, SamplingMessageContentBlock
  5 incl. tool_use/tool_result, PrimitiveSchema 4, EnumSchema 5 incl. legacy, ElicitParams 2,
  ResourceContents 2, InputRequest 3, InputResponse 3 = ≥29). Each arm asserts the exact predicate
  AND round-trips. This is the anti-vacuous discipline I look for.
- **Fixture-independent field-mapping unit test (Part 6)** covering the exact camelCase keys
  (`ttlMs`, `cacheScope`, `resultType`, `inputResponses`, `requestState`, `$schema`, `_meta`) AND
  the 5 prefixed reserved keys, with the copy-from-source process requirement and line-cite
  recording. Exactly right.
- **Params-drop vs results-preserve asymmetry** (Part 2 + Part 5) correctly modeled against the
  three strictness behaviors, with the subtle extra detail that an UNRESERVED `_meta` key inside
  the envelope survives in `request-meta`'s `rest` while an unknown non-`_meta` PARAM key is dropped.
- **Contract-rejection per category** (≥9, each a named check) — meaningful per-type rejections,
  not a token throw.
- **N1-union-compatibility** with 003 addressed via the shared `absent` sentinel (import+re-export)
  + per-primitive struct/predicate/contract provides.
- **Drift-detection / anti-vacuous-pass** present in the Manual Validation Checklist (corrupt a
  reserved `_meta` key string → test must FAIL → revert).

---

## Refinements (NON-blocking — fold into iteration if convenient, or defer to impl)

1. **`resultType` modeled as OPTIONAL while `_meta` is modeled as REQUIRED — make the inconsistency
   explicit.** In the `.d.ts`, BOTH are required-with-no-`?`: `Result.resultType: ResultType`
   (line 187, "Servers MUST include this field") and `RequestParams._meta: RequestMetaObject`
   (line 133). The spec follows the `.d.ts` for `_meta` (required) but deliberately models
   `result-type?` as OPTIONAL (§B line 211; Decisions line 1036-1038, "absent treated as complete").
   That choice is DEFENSIBLE — the resultType JSDoc explicitly sanctions absent-as-"complete" for
   backward compat (lines 182-185), whereas `_meta` has no such allowance — but the spec currently
   states a blanket "follow the .d.ts" rule for `_meta` while silently doing the opposite for
   `resultType`. Add one sentence to Decisions → resultType acknowledging this is an INTENTIONAL
   asymmetry grounded in the resultType backward-compat JSDoc, so the implementer/005 doesn't read
   it as an oversight. (This is the single most substantive item; still not revision-blocking.)

2. **`ListRootsResult` is a BARE interface — resolve the open question now (it is NOT a Result).**
   The spec flags "confirm `_meta` presence during impl" (§O2 line 412-413, Diff line 550-551).
   I resolved it: `ListRootsResult` (line 2556) = `{ roots: Root[] }` ONLY — it does NOT
   `extends Result`, carries NO `_meta`, NO `resultType`, NO loose `rest`. Likewise
   `ListRootsRequest` (2534) is a bare `{ method, params? }` not `extends JSONRPCRequest`.
   Recommend pinning this in §O2 so the implementer does NOT bolt the generic
   `meta?`/`result-type?`/`rest` trio onto `list-roots-result` (which would break round-trip
   parity by emitting phantom keys, and would make it inconsistent with the TS shape). Add an
   explicit "list-roots-result carries `roots` ONLY — no meta/resultType/rest" note + a round-trip
   fixture assertion that a `roots/list` result re-serializes with ONLY the `roots` key.

3. **Minor: `EmptyResult = Result` interaction with the resultType decision.** §B aliases
   `EmptyResult` to `result` and the edge-case list (line 810-812) says treat `result:{}` as
   EmptyResult with absent `resultType` accepted. Consistent with refinement #1, but worth a single
   cross-reference so the empty-result fixture and the resultType-optional decision are obviously
   the same call.

4. **Nit (informational, no action): `progressToken` lives inside `RequestMetaObject`** (line 74),
   i.e. inside `_meta`, same as it effectively was in 003 (`RequestParams._meta.progressToken`).
   The spec models it as a `request-meta` field (§C) — correct. Just confirming this is not a
   relocation that needs a migration note for 005.

None of (1)–(4) blocks approval. (1) and (2) would make the spec airtight; both are de-risking
the implementer rather than fixing an error.

---

## Required create-item sections — ALL PRESENT
Description ✓; Type inventory (§A–S) + Diff §CORE ✓; Acceptance criteria (incl. the RC-only-fields
present assertion) ✓; Implementation steps ✓; Testing strategy (round-trip per envelope + per-arm
+ rejection + RC-field-presence Part 4 + field-mapping Part 6 + fixture-source decision) ✓;
Dependencies ✓; Decisions & Trade-offs (with recommended defaults) ✓; Completion Reminder
(progress.md row 📋→🚧→✅, parity-matrix discipline, additive constants edit, don't touch siblings) ✓;
Project-specific adaptations ✓; **CRITICAL Testing Prerequisites block** — Required Services /
Environment Configuration / Manual Validation Checklist / Expected Outcomes (enumerated inventory +
counts + explicit RC-only field/_meta-key list) / Validation Results template — ✓ all present and
substantive.

## Why 9 and not 10
Only the two `.d.ts`-vs-model asymmetries left implicit (resultType optional; ListRootsResult bare)
keep it off a 10. Both are de-risking refinements, not defects. The spec is implementation-ready
as-is.
