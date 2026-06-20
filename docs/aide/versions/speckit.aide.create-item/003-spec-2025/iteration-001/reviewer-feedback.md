# Reviewer feedback — Item 003: Spec types, revision 2025-11-25 (iteration 001)

**Reviewer role:** QA / edge-case + testing-strategy review, with the team-lead's #1 mandate
(type-inventory completeness) cross-checked against the live TS source.
**Verdict:** **8.5 / 10 — APPROVE (no revision required).** This is a strong, unusually
rigorous spec. The findings below are refinements to fold into Decisions during
implementation, not blocking gaps.

---

## 1. Type-inventory completeness (the #1 job) — PASS

I cross-checked the spec's §A–Q inventory against
`typescript-sdk/packages/core/src/types/spec.types.2025-11-25.ts` line-by-line. **Every line
citation in the inventory is accurate** (I verified ~120 cited line numbers individually).
**No type from my pre-extracted authoritative inventory is missing.**

- **Requests — 20 distinct structs present.** All of `ClientRequest` (16) ∪ `ServerRequest`
  (8), de-duplicated (ping + 4 task requests shared) = 20: ping, initialize, complete,
  setLevel, getPrompt, listPrompts, listResources, listResourceTemplates, readResource,
  subscribe, unsubscribe, callTool, listTools, getTask, getTaskPayload(`tasks/result`),
  listTasks, cancelTask, createMessage, listRoots, elicit. The spec's "18 distinct request
  structs" headline counts the method-bearing request structs differently (it folds ping +
  4 task requests once) — the underlying coverage is complete; the count framing is fine.
- **Notifications — 11 present.** cancelled, progress, initialized, message(logging),
  resources/updated, resources/list_changed, tools/list_changed, prompts/list_changed,
  roots/list_changed, elicitation/complete, tasks/status. Complete.
- **Results — 18 present.** Empty, Initialize, Complete, GetPrompt, ListPrompts,
  ListResources, ListResourceTemplates, ReadResource, CallTool, ListTools, CreateMessage,
  ListRoots, Elicit, CreateTask, GetTask, GetTaskPayload, ListTasks, CancelTask. Complete.
  (Spec says "~17-18"; the actual count is exactly 18 incl. CreateTaskResult — see §6.)
- **The 3 intersection types are present AND correctly flagged** as the silent-omission trap
  I worried about: `GetTaskResult = Result & Task` (1420), `CancelTaskResult = Result & Task`
  (1468), `TaskStatusNotificationParams = NotificationParams & Task` (1493). The spec flattens
  Task's fields into each (matching the wire shape) and documents the decision. Excellent.
- **Discriminated-union arms — all present:** ContentBlock (text/image/audio/resourceLink/
  embeddedResource), SamplingMessageContentBlock (text/image/audio/toolUse/toolResult),
  PrimitiveSchemaDefinition (string/number/boolean/enum), EnumSchema (untitled+titled single,
  untitled+titled multi, legacy = 5 arms), ElicitRequestParams (form/url),
  ResourceContents (text/blob). Every arm has its own struct + the union is a `(or/c …)`.
- **URLElicitationRequiredError (-32042)** present with constructor + predicate, code sourced
  from `constants.rkt`. The aggregate union contracts (client/server × request/notification/
  result + jsonrpc-message) are all enumerated. Complete.

**Bottom line: the inventory is the most thorough part of the spec and has zero omissions.**

---

## 2. Round-trip edge handling — PASS (this is the spec's strongest QA section)

The three classic round-trip traps are all explicitly handled, correctly:

- **Key order:** `jsexpr=?` compares objects as unordered key sets, lists in order, numbers by
  `=`, `'null` by `eq?`; raw-byte comparison explicitly rejected. This is exactly right — a
  naive string round-trip would be a bug, and the spec calls that out by name (Decisions +
  Testing Strategy Part 1.4).
- **Absent vs `'null`:** the `absent` sentinel + key-omission-on-serialize rule is specified
  per-field, with a dedicated regression assertion (`(hash-has-key? rt 'instructions)` is
  `#f`). The one genuinely-nullable field (`Task.ttl: number | null`, REQUIRED) is correctly
  isolated and tested both ways (null preserved; absent rejected). I verified `Task.ttl` is
  indeed the only `| null` field and that it is required — accurate.
- **Unknown-key / `_meta` passthrough:** the `rest`-hasheq design preserves leftover keys and
  merges them back; tested for both a result and a content block. This is the correct fix for
  the "struct drops unknown keys → round-trip fails" trap.

Number-type handling (inexact flonums for `priority`/`temperature` compared by `=`), the
`stop-reason` open enum (verified: `… | string`, line 1670), and `SamplingMessage.content`
being `Block | Block[]` (verified line 1680 — single-or-list, tested both ways) are all
covered. This section anticipates the failures a less careful implementer would hit.

---

## 3. Hand-authored fixture plan — ADEQUATE, with two reinforcements

The fixture-source decision is correct and well-justified: I confirmed
`specTypeSchema.examples.ts` is JSDoc-snippet bait (not JSON data), the
`*.test.ts` is a static type-assignability test (not fixtures), and **no `*.json` fixtures
exist** under `packages/core` for these types. Hand-authoring is the only option. The
honesty mechanism — validating each fixture against its struct contract so a drifted fixture
fails — is the right safeguard against the #1 hand-fixture risk (a fixture that silently
encodes the *implementer's* misreading rather than the spec). Good.

Two reinforcements to fold in (non-blocking):
- **(R1) Anti-vacuous-pass for fixtures.** A hand-authored fixture + a hand-authored struct
  written by the same person can agree on a *wrong* field name and still round-trip green
  (the error cancels out). The contract-validation step catches type errors but NOT a
  consistently-wrong camelCase key (e.g. both sides use `inputSchema` vs the spec's required
  `inputSchema`→`input-schema` map). Mitigation already half-present: the drift-detection
  checklist item (corrupt a fixture field name → expect FAIL). Strengthen it to require that
  at least the camelCase keys in each fixture are **copied from the TS interface**, not
  retyped — and that the field-mapping table (kebab↔camel) is asserted in a unit test
  independent of the fixtures (e.g. assert `(initialize-result->json …)` emits the literal
  key `serverInfo`, not `server-info` or `serverinfo`).
- **(R2) Coverage of union arms in fixtures.** Part 1's named fixtures (6) cover envelope
  kinds but not every discriminated-union arm. The edge-case list does say "a prompt-message
  whose content is each of the 5 content-block variants round-trips" and "enum schema family"
  — keep that as a hard requirement, not a "should": the spec should state a **minimum of one
  round-trip fixture per union arm** (5 ContentBlock + 5 SamplingMessageContentBlock + 5
  EnumSchema + 2 ElicitRequestParams + 2 ResourceContents + 4 PrimitiveSchema). Otherwise an
  arm can be declared but never exercised — the exact "declared-but-untested" gap this review
  exists to catch.

---

## 4. SUBSTANTIVE TECHNICAL FINDING — request-params are NOT loose (fold into Decisions)

This is the one place the spec makes a claim that does not match `schemas.ts`, and it affects
the `rest`/passthrough design. The spec's §"Strictness" states *"Payload/result/params
objects are LOOSE"* and marks **every** request-params struct **(loose: has `rest`)**.

Verified in `schemas.ts`:
- `ResultSchema = z.looseObject(...)` (118) — **results ARE loose.** ✅ (spec correct)
- `EmptyResultSchema = ResultSchema.strict()` (207) — **the one strict result.** ✅
- `GetTaskPayloadResultSchema = ResultSchema.loose()` (753) — fully open. ✅
- BUT `BaseRequestParamsSchema = z.object({ _meta })` (78) — a plain **`z.object`, NOT
  loose**. Every concrete request-params schema is `BaseRequestParamsSchema.extend({...})`
  (InitializeRequestParams 463, CallToolRequestParams 1463, etc.), so they inherit
  `z.object` semantics: **unknown non-`_meta` keys are STRIPPED, not preserved.** The
  `.loose()` appears at exactly two generic sites — `RequestSchema.params` (102) and
  `NotificationSchema.params` (115) — but each concrete request schema *overrides* `params`
  with its strict concrete schema (e.g. `RequestSchema.extend({ params:
  InitializeRequestParamsSchema })`, 476), so the generic `.loose()` does not apply.

**Implication:** TS does NOT round-trip an arbitrary unknown key inside `initialize` params —
it drops it. A Racket struct that captures it in `rest` and re-emits it round-trips *more*
than TS does. This will NOT fail the proposed tests (the fixtures contain no stray param
keys), so it is **not a blocking bug** — but it is a **parity divergence** the spec asserts
the opposite of. `_meta` itself is a *named* field on `BaseRequestParamsSchema`, so `_meta`
passthrough on params is fine either way; the divergence is only for non-`_meta` extras.

**Recommendation (record in Decisions, do not require a revision):** Either (a) give request
*params* structs a `rest` field anyway (harmless superset; simpler/uniform code; document
that this is intentionally more lenient than TS), OR (b) model request-params as
*non-loose* (strip unknown non-`_meta` keys, keep only a `meta` field) to match TS exactly,
and reserve `rest` for the genuinely-loose **results** and the `looseObject` capability
trees. Option (a) is the pragmatic S1 choice given item 005 wants a uniform field-presence
model; just label the leniency explicitly so item 004 mirrors the *same* choice. The
contract-rejection tests should then NOT assert that an extra param key is rejected (it
isn't, under either reading — z.object strips silently, it doesn't throw).

A second precision note: Part 4 says "Result/params object with an extra inner key →
**accepted** and preserved." For **results** that is correct (looseObject preserves). For
**request params** under TS semantics it is "accepted and *stripped*," not preserved — so the
"preserved" assertion should be scoped to results (and looseObject capability blobs), not
applied to request params. Tighten the test wording accordingly.

---

## 5. Verdicts on the Worker's 4 flagged ambiguities

1. **progress.md:47 bundles spec-2025 + spec-2026 on one row.** *Verdict: handled correctly,
   no change needed.* I confirmed line 47 reads
   `📋 spec-2025-11-25.rkt + spec-2026-07-28.rkt`. The Completion Reminder already instructs
   not flipping the combined row to ✅ until item 004 lands, and to split the line so this
   item's half can advance to 🚧/✅ independently. That is exactly the right call — splitting
   the row is cleaner than a half-checked combined row. **Recommend: split the line now** as
   part of this item so 004 inherits a clean single-deliverable row.

2. **`$schema` / `_meta` field-name mapping.** *Verdict: real issue, spec handles it, pick one
   and pin it in a test.* Verified `Tool.inputSchema` and `outputSchema` both carry `$schema?`
   (lines 1267/1286) and `_meta` is pervasive. `$` and `_` are not kebab identifiers. The
   spec offers `schema-uri` (field) or "keep in `rest`" for `$schema`, and `meta` for `_meta`.
   *Recommendation:* keep `$schema` in `rest` (it lives inside the open JSON-Schema fragment,
   which you're already modeling as a loose object — no reason to promote it to a named field),
   and map `_meta`→`meta` as a named field everywhere. Whichever is chosen, add the explicit
   assertion that the **literal** `$schema` / `_meta` keys survive verbatim (the edge-case
   list already has the `$schema` fidelity check — keep it mandatory).

3. **EmptyResult is `.strict()` while other results are loose.** *Verdict: accurate; the
   spec's "enforcement optional for S1" stance is acceptable but make the test direction
   explicit.* Confirmed `EmptyResultSchema = ResultSchema.strict()` (207). The pragmatic
   "treat as `result`, document the nuance" is fine for S1. One caveat: because EmptyResult is
   strict, an EmptyResult fixture carrying an unknown key would be *rejected* by TS — so do
   **not** include a stray-key passthrough fixture on an EmptyResult (use a CallToolResult or
   ListToolsResult for the passthrough test, which the spec already does). If strictness isn't
   enforced in S1, add a one-line note that EmptyResult passthrough is intentionally untested
   until later, so a future reader doesn't read the gap as an oversight.

4. **Deeply-nested capability trees as loose hasheq vs sub-structs.** *Verdict: agree with the
   spec's recommendation — loose `hasheq` for the deep trees.* Confirmed the tasks-capability
   sub-objects are `z.looseObject` (schemas.ts:351, 364, 369, 377, 388, 401, 406) — they are
   open by design, so sub-structs would be both lossy (drop unknown sub-keys) and high-churn.
   Top-level `ClientCapabilities`/`ServerCapabilities` as explicit structs with the deep trees
   as loose `hasheq` (carried in their field or in `rest`) is correct. *One requirement to
   add:* a round-trip fixture with a populated nested capability (e.g.
   `tasks.requests.callTool` present) to prove the deep loose blob survives — the edge-case
   list only tests `roots:{listChanged:true}`, which is shallow.

---

## 6. Minor accuracy nits (cosmetic; fix in place, not blocking)

- **Result count.** §Expected Outcomes says "~17" and the headline says "~17-18". The exact
  count is **18** (the 17 listed + `CreateTaskResult`, which the inventory §J includes at line
  1396 but the Expected-Outcomes result list omits — CreateTaskResult IS a Result subtype,
  line 1396 `extends Result`). Either add CreateTaskResult to the Expected-Outcomes result
  enumeration or note it's counted under "task results." Right now §J lists it but §Expected
  Outcomes' results bullet doesn't, a small internal inconsistency. (The struct itself is
  covered, so this is wording only.)
- **`SamplingMessageContentBlock` arm count.** Inventory is correct (5 arms incl. toolUse +
  toolResult). Just ensure the *fixture* set exercises toolUse/toolResult content, which only
  appear in sampling, not in the general ContentBlock union — easy to forget since the
  `prompt-message` content test uses the *other* union.
- **`stopReason` line cite.** Spec says line 1670; the field is at 1670-ish inside
  CreateMessageResult (1653-1672) — accurate enough; the open-enum behavior is verified.
- **Counts framing.** "16 client + 8 server = 18 distinct" arithmetic is confusing on its
  face (16+8≠18); it's correct only because 6 are shared (ping + 4 task + … ). Consider
  restating as "20 distinct request structs (16 client ∪ 8 server, 4 shared)" to match the
  actual union math and avoid a reviewer flagging it as an error later.

---

## 7. Required-sections audit — PASS

All create-item sections present and substantive: Description, Representation conventions,
Type inventory (the contract), Acceptance criteria, Implementation steps, Testing strategy
(4 parts + explicit edge-case list), Dependencies, Project-specific adaptations, the CRITICAL
Testing Prerequisites block (Required Services / Environment Configuration / Manual Validation
Checklist / Expected Outcomes / Validation Results template all present), Decisions &
Trade-offs (with open decisions enumerated), and the Completion Reminder with progress/
parity-matrix discipline. The "pure-data module → no services" adaptation of the
services-oriented template is handled honestly rather than left as boilerplate.

---

## Summary of recommended (non-blocking) edits before implementation

1. Fold the **request-params loose-vs-strict** finding (§4) into Decisions; pick option (a) or
   (b) explicitly and scope the "extra inner key preserved" assertion to results only.
2. Make **one round-trip fixture per discriminated-union arm** a hard minimum (§3 R2), incl.
   toolUse/toolResult sampling content and a populated nested capability (§5.4).
3. Add a **field-mapping unit test** (kebab↔camel, esp. `$schema`/`_meta`/`serverInfo`/
   `inputSchema`) independent of fixtures (§3 R1, §5.2).
4. **Split progress.md:47** into two deliverable rows (§5.1).
5. Fix the **result-count wording** (18 incl. CreateTaskResult) and the "16+8=18" phrasing
   (§6).

None of these block implementation; the spec is implementation-ready as written.
