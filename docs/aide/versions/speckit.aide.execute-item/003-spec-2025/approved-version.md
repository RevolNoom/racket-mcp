# Reviewer Feedback — Item 003 (spec-2025-11-25), Iteration 001 (RE-REVIEW)

> Supersedes the earlier 1/10, which was a race against an incomplete tree. The
> implementation is now fully on disk and reviewed in depth below.

## Verdict: APPROVE — rating 9/10, needs_revision = false

A complete, parity-faithful implementation of the 2025-11-25 revision. Completeness,
the three strictness behaviors, canonical round-tripping, union-arm coverage, and an
anti-vacuous field-mapping test all check out under adversarial probing.

## raco test (run from repo root, myself)

`raco test mcp/core/types/` → **459 tests passed, EXIT 0**
(339 baseline items 001+002 still pass + 120 new; pinned count printed = 120). The
`/home/rev/.bash_env: Permission denied` stderr noise is ignored.

## Completeness (my #1 job) — PASS

Cross-checked the implementation against both the spec inventory (§A–Q) and the real
`typescript-sdk/packages/core/src/types/spec.types.2025-11-25.ts`:

- **Method literals: 31/31.** `grep "method: '"` in the TS yields exactly 31 (20
  requests + 11 notifications). Every one is pinned in the impl via `(lit/c "...")` —
  verified by diffing the two literal sets; they match exactly (plus `form`/`url` mode
  discriminators = 33 total literal pins).
- **18 result types:** all present (`initialize-result`, `complete-result`,
  `get-prompt-result`, `list-*-result` ×6, `call-tool-result`, `read-resource-result`,
  `create-task-result`, `get-task-result`, `get-task-payload-result`, `list-tasks-result`,
  `cancel-task-result`, `create-message-result`, `elicit-result`, `list-roots-result`) plus
  the internal `result`/`paginated-result` bases.
- **4 JSON-RPC envelopes + inner `jsonrpc-error` + specialized
  `url-elicitation-required-error`** (constructor + predicate, code via
  `URL-ELICITATION-REQUIRED` from constants.rkt; wire test asserts -32042).
- **The 3 TS type-intersections** (the silent-omission trap) are all present and
  flattened: `GetTaskResult = Result & Task` (TS 1420), `CancelTaskResult = Result & Task`
  (TS 1468), `TaskStatusNotificationParams = NotificationParams & Task` (TS 1493) →
  `get-task-result`, `cancel-task-result`, `task-status-notification-params`, each carrying
  the 7 Task fields at top level + `meta` + loose `rest`. The `get-task-result.json` fixture
  proves the flatten is lossless (all Task fields top-level + `_meta` + an extra loose key).
- **All 7 aggregate union contracts** (`client-request/c`, `client-notification/c`,
  `client-result/c`, `server-request/c`, `server-notification/c`, `server-result/c`,
  `jsonrpc-message/c`) provided.
- Totals: **114 structs, 135 `…/c` contracts** — comfortably above the ~70/~70 floor.
  No missing types.

## Three strictness behaviors (hard gate) — PASS

Read both the impl and schemas.ts semantics:
1. **Envelopes strict.** `json->jsonrpc-{request,notification,result-response,error-response}`
   each reject any top-level key outside their `allowed` set (Part 3/4 tests confirm).
2. **Results preserve unknown keys.** Every result deserializer calls `split-loose` and
   stores leftovers in a `rest` hasheq, re-merged on serialize. Part 2 asserts an unknown
   top-level key AND `_meta` survive on `list-tools-result`; the `get-task-result.json`
   intersection fixture additionally carries `extraResultKey` to prove loose preservation on
   an intersection result.
3. **Params DROP unknown non-`_meta` keys.** Params structs have a named `meta` field but NO
   `rest`; the deserializer simply ignores unknown keys. Part 2 + Part 4(c) assert
   `extraUnknownKey`/`strayKey` are GONE after round-trip while `_meta` survives. No
   params-preserve and no results-drop bug. This is the load-bearing asymmetry and it is
   correct.

## Round-trip discipline — PASS

`jsexpr=?` is a recursive comparator: objects compared as unordered key sets, lists in
order, numbers by `=`, `'null` by `eq?`. It is self-checked (4 asserts at top). NOT
byte-equality. Absent→key omitted (Part edge test: absent `instructions` not emitted);
`Task.ttl` is the only required-nullable and a present `'null` serializes to JSON null
(asserted both ways).

## Union-arm coverage (23 arms) — PASS

Every arm fixture deserializes AND asserts the exact struct predicate, so a mis-dispatch
fails loudly:
- ContentBlock ×5 (text/image/audio/resource_link/resource).
- SamplingMessageContentBlock ×5 incl. the sampling-only **tool_use** and **tool_result**
  (which never appear in the general ContentBlock test) + single-block AND list shapes.
- PrimitiveSchemaDefinition ×4 (string/number/integer/boolean).
- EnumSchema ×5 (untitled-single/titled-single/untitled-multi/titled-multi/legacy).
- ElicitRequestParams ×2 (form/url).
- ResourceContents ×2 (text/blob).
Plus the deep nested-capability fixture asserting `tasks.requests.sampling` survives.

## Anti-vacuity — PASS (probed two ways, adversarially)

- **Fixture coupling:** I corrupted `inputSchema → input_schema` in
  `list-tools-result.json`; the suite went to 3/120 failures (round-trip + $schema-fidelity
  break). The fixtures genuinely drive the assertions — not vacuous.
- **Field-map independence:** I corrupted the impl's serializer (`'serverInfo →
  'server-info`); the suite went to 3/120 failures **including the Part-5
  fixture-independent field-mapping test**, which constructs structs directly and pins the
  exact camelCase keys. So a wrong field map fails even where a hand-authored fixture +
  matching wrong struct would have round-tripped green. This is exactly the belt-and-
  suspenders the spec demanded.
- **Fixture key honesty:** spot-checked fixture camelCase against the real .ts:
  `protocolVersion`/`capabilities`/`clientInfo` (TS 264–267), `name`/`arguments` (TS
  1146/1150), Task `taskId`/`status`/`statusMessage`/`createdAt`/`lastUpdatedAt`/`ttl`
  (number|null)/`pollInterval` (TS 1349–1392), and the `_meta` key
  `io.modelcontextprotocol/related-task` in tools-call-request.json. All match.

## Contract-rejection — PASS

Meaningful per-category rejects (Part 3): missing `protocolVersion`; numeric tool `name`;
out-of-enum `level`; text content missing `text`; bogus content `type`; Task missing `ttl`;
out-of-enum Task `status`; Task `ttl:'null` ACCEPTED; strict-envelope extra key; image
missing `mimeType`; `id` of `'null` and `1.5` rejected. Not a single-token reject.

## progress.md — PASS

Row was split: `spec-2025-11-25.rkt` advanced to ✅ (item 003); `spec-2026-07-28.rkt` left
at 📋 (item 004). Sibling rows untouched.

## Minor (non-blocking) observations — no revision required

1. `emit-task-fields` (used by the 3 intersection serializers) accepts a `meta` argument it
   never uses — the enclosing `(put … '_meta …)` already emits `_meta`. Dead parameter;
   harmless. Cosmetic cleanup only.
2. `EmptyResult` is intentionally treated as ordinary `result` (no `.strict()` enforcement),
   exactly as the spec's settled verdict defers it to a later additive change. Correct, but
   worth a one-line code comment near `result` flagging the known deferred gap for item 005.
3. `h-req` returns `absent` for a missing required key rather than raising at the fetch
   site; required-ness is enforced downstream by the `…/c` contract (or an explicit `when
   (absent? …)` for `ttl`/`data`/`maxTokens`). Consistent and tested, just noting the
   pattern is contract-driven, not fetch-driven.

These are cosmetic; the module meets every acceptance criterion. Approve.
