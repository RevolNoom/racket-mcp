# Work Item 004: Spec types — revision 2026-07-28 (incl. `_meta` envelope)

> **Queue:** `docs/aide/queue/queue-001.md` — Item 004
> **Stage:** S1 (Foundation: types, constants, guards, errors — L0 part 1)
> **Module:** M1 (Types) — `spec-2026-07-28` sub-unit (versioned-spec layer)
> **Source vision:** `docs/aide/vision.md` §4.1 (versioned-spec → normalization façade)
> **Source roadmap:** `docs/aide/roadmap.md` Stage S1 → Deliverables
>   (`mcp/core/types/spec-2026-07-28.rkt` — per-revision structs + contracts for every
>   request, response, notification, and error type) and round-trip discipline.
> **Source architecture:** `docs/aide/architecture.md` (Versioned-spec modules),
>   **N1** (normalized-superset façade), §1.3 (public/internal boundary).
> **Reference impl (authoritative):** MCP TypeScript SDK v2 at `typescript-sdk/` —
>   `packages/core/src/types/spec.types.2026-07-28.ts` (**3030 lines**; generated, frozen,
>   commit `9d700ed62dcf86cb77475c9b81930611a9182f46`) and
>   `packages/core/src/types/schemas.ts` (the live Zod shapes) and
>   `packages/core/src/types/constants.ts` (the reserved `_meta` key string constants).
> **SIBLING (template + quality bar):** `docs/aide/items/003-spec-types-2025-11-25.md`
>   (delivered + implemented). This item MIRRORS 003's structure, conventions, helpers, and
>   test rigor; the analytical core of THIS item is the **DIFF** vs 2025-11-25 (§Diff).
> **Status:** 📋 Not started.

---

## Description

Implement `mcp/core/types/spec-2026-07-28.rkt`, a **pure-data** Racket module mirroring the
`2026-07-28` (Release-Candidate) MCP revision as defined in
`typescript-sdk/packages/core/src/types/spec.types.2026-07-28.ts`. It provides a Racket
**struct** + a **flat contract** (`racket/contract`) for **every** request, notification,
result/response, error, and supporting payload type of that revision, plus
`read-json → struct → write-json` (de)serialization that round-trips a TS-SDK-shaped JSON
message back to byte-equivalent JSON (canonicalized — see Testing).

This is the **sibling** of item 003 (`spec-2025-11-25.rkt`, already delivered and
implemented). **Build it structurally parallel to 003** — same `#lang racket/base` +
`racket/contract`, same transparent-struct + `name/c` flat-contract + `json->name` /
`name->json` triad, same wire conventions (immutable symbol-keyed `hasheq`; `'null` for JSON
null; the `absent` sentinel + key omission for absent optionals), same three strictness
behaviors, and the same internal helper set. **003 is the template; read it in full before
starting.** The distinguishing feature of this revision — and the distinguishing acceptance
criterion of this item — is the **per-request `_meta` reserved-key envelope** (`RequestMetaObject`,
spec.types line 70): protocol version, client info, client capabilities, the related-task ref,
and the **deprecated** log level, all carried as reserved keys *inside* `_meta`.

This module is consumed downstream by **item 005** (the **N1 normalized-superset façade** in
`types.rkt`), which will **UNION 003 + 004** into one version-agnostic shape with revision-only
fields present-or-absent. **Design constraint (from N1):** 004's per-primitive surface MUST be
enumerable and union-compatible with 003's parallel primitives — same `absent`-sentinel
field-presence model, same kebab-case field naming, same per-primitive struct/predicate/contract
exports. Where 003 and 004 share a type *shape* (e.g. `Resource`, `Tool`, the content blocks,
the elicitation schema family), the Racket structs MUST be shape-compatible so 005 can union
them field-by-field. See *Decisions & Trade-offs → N1-readiness* and → *shared-helpers*.

> **THIS REVISION IS A MAJOR RESTRUCTURE, NOT A SMALL DELTA.** The file is 3030 lines (vs
> 2559 for 2025-11-25). It REMOVES whole families present in 2025 (`initialize`, `ping`,
> `logging/setLevel`, ALL `tasks/*`, `resources/subscribe`/`unsubscribe`, the
> `URLElicitationRequiredError`, the `ServerRequest` union) and ADDS new ones (`server/discover`,
> `subscriptions/listen`, typed JSON-RPC error structs, the `InputRequest`/`InputRequired`
> multi-round-trip family, `CacheableResult`, the `resultType` discriminator, per-method
> `*ResultResponse` envelope wrappers). The implementer MUST NOT assume a type exists just
> because it exists in 003. **The §Diff section is the contract for what changed; the §Type
> inventory is the contract for what to build.** Do NOT "mirror 003 and tweak" — enumerate from
> the 2026 file.

### Representation conventions (identical to item 003)

Non-negotiable, inherited from `guards.rkt`/`constants.rkt` and item 003 for parity AND so
item 005 can union 003+004 against one model:

- JSON **object** = the `read-json` shape: an **immutable symbol-keyed `hasheq`**
  (`json-object?` — re-implement internally, do not depend on guards' un-provided helper, same
  as 003).
- JSON **null** = the symbol `'null`. Arrays = Racket lists. Strings/numbers/booleans map
  directly.
- An **absent optional field** carries the `absent` sentinel and the serializer **omits the
  key** (never emits `"key": null`). **Reuse 003's `absent` sentinel** — see Decisions
  → *shared-helpers*; the façade (005) unions by testing `(absent? v)`, so 003 and 004 MUST use
  the SAME sentinel binding. A present `'null` value serializes to JSON null. (NOTE: unlike 003,
  2026 has **no `| null` required-nullable field** — 003's `Task.ttl` is gone with tasks; the
  new `CacheableResult.ttlMs` is a plain required `number`, NOT nullable. Confirm during impl.)
- `JSONRPC-VERSION` and the error-code constants come from `constants.rkt`.
- **Strictness — THREE distinct behaviors (carry over from 003 unchanged; verify against
  `schemas.ts`):**
  1. JSON-RPC **envelope** schemas are `.strict()` (`schemas.ts:177`+ region; same as item 002):
     extra top-level key → **rejected**.
  2. **Results are LOOSE.** `ResultSchema = z.looseObject` (`schemas.ts:118`) — results preserve
     `_meta` AND arbitrary unknown keys verbatim. NEW: every result now carries the optional
     `resultType` discriminator (`schemas.ts:124`-ish; spec.types:187) — model it as a named
     field, NOT swept into `rest`.
  3. **Concrete request/notification PARAMS are NOT loose — they STRIP unknown non-`_meta`
     keys.** `BaseRequestParamsSchema = z.object({...})` (`schemas.ts:78`), non-loose; each
     concrete params type is `.extend` of it (e.g. `PaginatedRequestParamsSchema`
     `schemas.ts:649`, the `tools/call`/`resources/read` params at `schemas.ts:727`/`742`), so
     unknown non-`_meta` keys are **dropped** on round-trip. Only the GENERIC envelope's untyped
     `params` is `BaseRequestParamsSchema.loose()` (`schemas.ts:102`).

### `_meta` envelope + additionalProperties passthrough (THE RC feature — parity-critical)

The 2026 revision's headline change is `RequestMetaObject` (spec.types line 70): the per-request
`_meta` is the **transport for version negotiation and per-request client identity**, replacing
the 2025 `initialize` handshake. **`RequestParams._meta` is REQUIRED** in the spec.types `.d.ts`
(line 133: `_meta: RequestMetaObject` — no `?`). The runtime `schemas.ts:78` keeps it
`.optional()` (the live validator is intentionally looser / superset across revisions). **The
`.d.ts` is the source of truth for THIS item; the schemas.ts looseness is noted but the contract
should follow the spec.types declaration — see Decisions → `_meta`-required.**

`RequestMetaObject` reserves these keys (cite spec.types + constants.ts):

| Reserved `_meta` key string | spec.types line | constants.ts const (line) | Type | Optionality |
|---|---|---|---|---|
| `io.modelcontextprotocol/protocolVersion` | 83 | `PROTOCOL_VERSION_META_KEY` (14) | `string` | **required** |
| `io.modelcontextprotocol/clientInfo` | 90 | `CLIENT_INFO_META_KEY` (19) | `Implementation` | **required** |
| `io.modelcontextprotocol/clientCapabilities` | 98 | `CLIENT_CAPABILITIES_META_KEY` (27) | `ClientCapabilities` | **required** |
| `io.modelcontextprotocol/logLevel` | 110 | `LOG_LEVEL_META_KEY` (38) | `LoggingLevel` | optional, **DEPRECATED** (SEP-2577) |
| `io.modelcontextprotocol/related-task` | (via schemas.ts:64) | `RELATED_TASK_META_KEY` (5) | `RelatedTaskMetadata` (`{taskId}`) | optional |
| `progressToken` (non-prefixed) | 74 | — | `ProgressToken` (string\|int) | optional |

**Decision (bake into the spec) — model the request `_meta` envelope as a dedicated struct**
`request-meta` (NOT a raw `hasheq`), with NAMED fields for the reserved keys
(`protocol-version`, `client-info`, `client-capabilities`, `log-level`, `related-task`,
`progress-token`) + a `rest` `hasheq` for any UNRESERVED `_meta` keys (the prefix rules,
spec.types:46–56, allow arbitrary third-party `_meta` keys — those pass through verbatim). The
deserializer splits the reserved keys → named fields and unreserved keys → `rest`; the serializer
re-emits the reserved keys at their EXACT prefixed strings and merges `rest` back. This is the
mechanism that makes the RC-only fields **present and parsed, not silently dropped** — the
distinguishing acceptance criterion of this item (see Acceptance + Testing Part 4).

- **Reserved key strings come from `constants.rkt`, not literals.** `constants.rkt` (item 001)
  does NOT currently define these `*-META-KEY` constants (it predates the RC). **This item ADDS
  the five `*-META-KEY` defines to `constants.rkt`** (additive — does not touch item 001's
  delivered codes/versions) and imports them, so the prefixed strings are single-sourced. See
  Dependencies + Decisions → reserved-key-constants.
- **Results** (every result type) carry a `rest` for `_meta` + unknown extras (loose), PLUS the
  new named `result-type` field. **Notification params** carry a named `meta` field (for `_meta`,
  which here is the looser `MetaObject`, not the full request envelope — NotificationParams
  `_meta?: MetaObject`, spec.types:150) and **drop** other unknowns. **Request params** carry the
  `request-meta` envelope struct in their `meta` field and **drop** other unknown non-`_meta`
  keys.

---

## Type inventory (the implementation contract — enumerate ALL)

Read from `spec.types.2026-07-28.ts` on 2026-06-17 (frozen commit `9d700ed`). Cited line ranges
are in that file unless prefixed `schemas.ts:` or `constants.ts:`. **Naming:** Racket struct =
kebab-case of the TS interface; predicate = `name?`; flat contract = `name/c`; field = kebab-case
of the TS field. The (de)serializer maps Racket kebab ↔ exact JSON camelCase (and the prefixed
`io.modelcontextprotocol/...` literals for the `_meta` envelope) via an explicit per-struct field
table — NOT an automatic transform.

**Counts (verified against the file 2026-06-17 — `grep -nE "method: '"` yields 22 method
literals):**
- **10 distinct client request structs** (the `ClientRequest` union, lines 2986–2996):
  `server/discover` (560), `completion/complete` (2445), `prompts/get` (1457), `prompts/list`
  (1402), `resources/list` (1012), `resources/templates/list` (1048), `resources/read` (1105),
  `subscriptions/listen` (1203), `tools/call` (1718), `tools/list` (1603).
- **3 server→client (InputRequest) request structs** (the `InputRequest` union, line 435 —
  there is NO `ServerRequest` aggregate in this revision): `sampling/createMessage` (2008),
  `roots/list` (2535), `elicitation/create` (2676). All three are **deprecated** (SEP-2577) but
  in-revision — implement them.
- **Total request structs: 13.**
- **9 notifications** (method literals): `notifications/cancelled` (543),
  `notifications/progress` (933), `notifications/resources/list_changed` (1145),
  `notifications/subscriptions/acknowledged` (1234) **[NEW]**,
  `notifications/resources/updated` (1264), `notifications/prompts/list_changed` (1589),
  `notifications/tools/list_changed` (1731), `notifications/message` (1889) **[deprecated]**,
  `notifications/elicitation/complete` (2975). (NOTE: NO `notifications/initialized`,
  `.../roots/list_changed`, or `.../tasks/status` — those 2025 notifications are GONE.)
- **~13 result types**: `EmptyResult` (432, alias of Result), `DiscoverResult` (572) **[NEW]**,
  `CompleteResult` (2460), `GetPromptResult` (1469), `ListPromptsResult` (1413),
  `ListResourcesResult` (1023), `ListResourceTemplatesResult` (1059), `ReadResourceResult`
  (1117), `CallToolResult` (1644), `ListToolsResult` (1614), `CreateMessageResult` (2032),
  `ListRootsResult` (2556), `ElicitResult` (2949), `InputRequiredResult` (480) **[NEW]**.
- **Errors**: the `Error` inner object (194), the `JSONRPCErrorResponse` envelope (251), the
  five typed code-pinned error structs `ParseError`/`InvalidRequestError`/`MethodNotFoundError`/
  `InvalidParamsError`/`InternalError` (281–358) **[NEW as typed structs]**, and the two
  data-carrying error responses `UnsupportedProtocolVersionError` (387) **[NEW]** and
  `MissingRequiredClientCapabilityError` (414) **[NEW]**. (NO `URLElicitationRequiredError`/
  `-32042` in this revision.)
- **Aggregate union contracts: 4** — `client-request/c`, `client-notification/c` (2999),
  `client-result/c` (3002, = EmptyResult only), `server-notification/c` (3007),
  `server-result/c` (3019). (NO `server-request/c` — there is no `ServerRequest` union in
  2026.) Plus `jsonrpc-message/c`.
- **Supporting/common/content/payload types: ~30** (enumerated in §B–§Q below).

> **The exact totals the test must report are in §Expected Outcomes.**

### A. JSON-RPC envelopes (4) — spec.types 221–262, schemas.ts strict region

Identical shape/handling to item 003 (constructible/serializable structs; `.strict()` top-level).

| TS type (line) | Racket struct | Fields | Contract notes |
|---|---|---|---|
| `JSONRPCRequest` (221) | `jsonrpc-request` | `id` (string\|exact-int), `method` (string), `params` (object\|absent) | id required; strict |
| `JSONRPCNotification` (231) | `jsonrpc-notification` | `method`, `params?` | NO id; strict |
| `JSONRPCResultResponse` (240) | `jsonrpc-result-response` | `id`, `result` (object, loose) | strict |
| `JSONRPCErrorResponse` (251) | `jsonrpc-error-response` | `id?` (string\|int\|absent), `error` (`jsonrpc-error`) | id OPTIONAL; strict |

> Provide a thin pairing helper (`request->jsonrpc` etc.) as 003 does, so item 009's demo / item
> 005 can build whole messages. The per-method typed params/result bodies are the bulk.

### B. Common / shared types — lines 61–214, 826–889, 2087

| TS type (line) | Racket struct/contract | Fields (TS optionality) | Notes |
|---|---|---|---|
| `MetaObject` (61) | `meta-object/c` = `json-object?` | — | base `_meta` (notifications/results use this looser form) |
| `RequestMetaObject` (70) | `request-meta` **[RC ENVELOPE — see §R]** | named reserved keys + `rest` | THE RC feature; modeled as a struct |
| `RequestParams` (132) | (base; flattened into each params struct) | `_meta` (request-meta) **required** | base for all request params |
| `NotificationParams` (149) | (base; flattened) | `_meta?` (meta-object) | looser `_meta` |
| `ResultType` (169) | `result-type/c` = `(or/c "complete" "input_required" string?)` | — | open enum (effectively `string?`); NEW |
| `Result` (176) | `result` | `meta?` + `result-type?` + **(loose: `rest`)** | base for all results; NEW `resultType` field |
| `Error` (194) | `jsonrpc-error` | `code` (exact-int), `message` (string), `data?` (any) | inner object NOT strict |
| `RequestId` (214) | `request-id/c` = `(or/c string? exact-integer?)` | — | reuse guards' rule |
| `ProgressToken` (118) | `progress-token/c` = `(or/c string? exact-integer?)` | — | |
| `Cursor` (125) | `cursor/c` = `string?` | — | opaque |
| `Icon` (782) | `icon` | `src`, `mime-type?`, `sizes?` (list string), `theme?` (`"light"`\|`"dark"`) | unchanged from 003 |
| `Icons` (826) | (mixin) | `icons?` (list of `icon`) | flattened into Implementation/Resource/Tool/Prompt |
| `BaseMetadata` (846) | `base-metadata` | `name` (string), `title?` | unchanged |
| `Implementation` (868) | `implementation` | `name`, `title?`, `version`, `description?`, `website-url?`, `icons?` | unchanged from 003 |
| `Annotations` (2087) | `annotations` | `audience?` (list role), `priority?` (number 0–1), `last-modified?` | unchanged |
| `Role` (1529) | `role/c` = `(or/c "user" "assistant")` | — | unchanged |
| `EmptyResult` (432) | alias = `result` | (loose) | `type EmptyResult = Result` |

### C. `_meta` request envelope (THE RC FEATURE) — spec.types 61–134, constants.ts 5/14/19/27/38

See §`_meta` envelope above. Model as a dedicated struct.

| TS type (line) | Racket struct | Fields | Notes |
|---|---|---|---|
| `RelatedTaskMetadata` (schemas.ts:60) | `related-task-metadata` | `task-id` (string) | rides inside `_meta` (carried over from 003) |
| `RequestMetaObject` (70) | `request-meta` | `progress-token?` (progress-token/c), `protocol-version` (string, **required**), `client-info` (`implementation`, **required**), `client-capabilities` (`client-capabilities`, **required**), `log-level?` (logging-level/c, **deprecated**), `related-task?` (`related-task-metadata`), `rest` (hasheq of unreserved `_meta` keys) | reserved key strings from `constants.rkt` (`PROTOCOL-VERSION-META-KEY` etc.); serialize re-emits the exact `io.modelcontextprotocol/...` keys; `rest` passes unreserved keys verbatim |

> **Contract `request-meta/c`** pins the three required reserved keys present and rejects when
> any is absent. Provide `json->request-meta` / `request-meta->json` and `request-meta/c`. This
> struct is the single most important deliverable of this item.

### D. Capabilities — spec.types 614–775, schemas.ts:417/482

| TS type (line) | Racket struct | Fields | Notes |
|---|---|---|---|
| `ClientCapabilities` (614) | `client-capabilities` | modeled as a single loose `rest` hasheq (same verdict as 003) | NEW `extensions`; `tasks` REMOVED; `roots`/`sampling` deprecated. Deep tree → loose hasheq |
| `ServerCapabilities` (688) | `server-capabilities` | single loose `rest` hasheq | NEW `extensions`; `tasks` REMOVED; `logging` deprecated |

> Same Decisions verdict as 003: model capabilities as a TOP-record struct wrapping the WHOLE
> capability object as one loose `hasheq` (`rest`), so deep/unknown nested values round-trip
> verbatim. A populated-capability fixture (Testing Part 1) proves the deep values survive.

### E. Discovery (NEW — replaces 2025 `initialize`) — spec.types 547–607

| TS type (line) | Racket struct | Fields | Notes |
|---|---|---|---|
| `DiscoverRequest` (559) | `discover-request` | method=`"server/discover"`, `params` (RequestParams — has the `_meta` envelope) | server MUST implement |
| `DiscoverResult` (572) | `discover-result` | `supported-versions` (list string), `capabilities` (`server-capabilities`), `server-info` (`implementation`), `instructions?`, `meta?`, `result-type?` + (loose) | the discovery payload |
| `DiscoverResultResponse` (605) | (envelope-wrapper; see §S) | `result` (`discover-result`) | typed `*ResultResponse` wrapper |

### F. Multi-round-trip / input family (NEW) — spec.types 435–505

| TS type (line) | Racket struct/contract | Fields | Notes |
|---|---|---|---|
| `InputRequest` (435) | `input-request/c` = `(or/c create-message-request? list-roots-request? elicit-request?)` | — | union of the 3 server→client requests |
| `InputResponse` (438) | `input-response/c` = `(or/c create-message-result? list-roots-result? elicit-result?)` | — | union of the 3 results |
| `InputRequests` (449) | `input-requests/c` = hash string→`input-request/c` | — | a `hasheq` (string keys) of input-request structs |
| `InputResponses` (463) | `input-responses/c` = hash string→`input-response/c` | — | |
| `InputRequiredResult` (480) | `input-required-result` | `input-requests?` (input-requests), `request-state?` (string), `meta?`, `result-type?` + (loose) | a Result; ≥1 of the two present |
| `InputResponseRequestParams` (496) | (base; flattened into read-resource/get-prompt/tools-call params) | `input-responses?`, `request-state?` (string), + `_meta` envelope | adds two fields to those params |

### G. Ping — REMOVED in 2026. (No `ping-request`.) Note this explicitly in the module comment.

### H. Progress / cancellation — spec.types 507–545, 891–935

| TS type (line) | Racket struct | Fields | Notes |
|---|---|---|---|
| `CancelledNotificationParams` (516) | `cancelled-notification-params` | `request-id?`, `reason?`, `meta?` (MetaObject) — **(params: drops unknown)** | unchanged shape from 003 |
| `CancelledNotification` (542) | `cancelled-notification` | method=`"notifications/cancelled"`, `params` | |
| `ProgressNotificationParams` (901) | `progress-notification-params` | `progress-token` (req), `progress` (number, req), `total?`, `message?`, `meta?` | unchanged from 003 |
| `ProgressNotification` (932) | `progress-notification` | method=`"notifications/progress"`, `params` | |

### I. Pagination + cacheable bases — spec.types 937–1000

| TS type (line) | Racket struct | Fields | Notes |
|---|---|---|---|
| `PaginatedRequestParams` (946) | `paginated-request-params` | `cursor?`, + `_meta` envelope — **(params: drops unknown)** | base; flatten cursor into concrete list-request params |
| `PaginatedResult` (960) | `paginated-result` | `next-cursor?`, `meta?`, `result-type?` (loose) | base for list results |
| `CacheableResult` (973) | `cacheable-result` **[NEW]** | `ttl-ms` (number, **required**), `cache-scope` (`"public"`\|`"private"`, **required**), `meta?`, `result-type?` (loose) | base mixin for list/read results — flatten its 2 fields into each concrete result |

> List/read results below extend BOTH `PaginatedResult` AND `CacheableResult` (TS multiple
> interface inheritance). Racket has no inheritance — **flatten** `next-cursor?` + `ttl-ms` +
> `cache-scope` directly into each concrete result struct (alongside `meta?`/`result-type?`/`rest`).

### J. Resources — spec.types 1002–1399

| TS type (line) | Racket struct | Fields |
|---|---|---|
| `ListResourcesRequest` (1011) | `list-resources-request` | method=`"resources/list"`, `params` (paginated — has `_meta` envelope + `cursor?`) |
| `ListResourcesResult` (1023) | `list-resources-result` | `resources` (list `resource`), `next-cursor?`, `ttl-ms`, `cache-scope`, `meta?`, `result-type?`, (loose) |
| `ListResourceTemplatesRequest` (1047) | `list-resource-templates-request` | method=`"resources/templates/list"`, `params` |
| `ListResourceTemplatesResult` (1059) | `list-resource-templates-result` | `resource-templates` (list `resource-template`), + cacheable/paginated fields |
| `ResourceRequestParams` (1080) | (base; flattened) | `uri` (string), + `_meta` envelope |
| `ReadResourceRequestParams` (1094) | `read-resource-request-params` | `uri` + `input-responses?` + `request-state?` + `_meta` envelope — **(params: drops unknown)** (extends ResourceRequestParams + InputResponseRequestParams) |
| `ReadResourceRequest` (1104) | `read-resource-request` | method=`"resources/read"`, `params` |
| `ReadResourceResult` (1117) | `read-resource-result` | `contents` (list text\|blob contents), + cacheable fields, `meta?`, `result-type?`, (loose) |
| `ResourceListChangedNotification` (1144) | `resource-list-changed-notification` | method=`"notifications/resources/list_changed"`, `params?` (NotificationParams) |
| `ResourceUpdatedNotificationParams` (1246) | `resource-updated-notification-params` | `uri`, `meta?` — **(params: drops unknown)** |
| `ResourceUpdatedNotification` (1263) | `resource-updated-notification` | method=`"notifications/resources/updated"`, `params` |
| `Resource` (1276) | `resource` | `name`, `title?`, `uri`, `description?`, `mime-type?`, `annotations?`, `size?`, `icons?`, `meta?` (loose) | (read the 1276–1316 range to confirm fields match 003) |
| `ResourceTemplate` (1316) | `resource-template` | `name`, `title?`, `uri-template`, `description?`, `mime-type?`, `annotations?`, `icons?`, `meta?` |
| `ResourceContents` (1349) | `resource-contents` (base) | `uri`, `mime-type?`, `meta?` |
| `TextResourceContents` (1370) | `text-resource-contents` | + `text` (string) |
| `BlobResourceContents` (1383) | `blob-resource-contents` | + `blob` (string) |

### K. Subscriptions (NEW — replaces `resources/subscribe`/`unsubscribe`) — spec.types 1149–1236

| TS type (line) | Racket struct | Fields |
|---|---|---|
| `SubscriptionFilter` (1158) | `subscription-filter` | `tools-list-changed?` (bool), `prompts-list-changed?` (bool), `resources-list-changed?` (bool), `resource-subscriptions?` (list string) |
| `SubscriptionsListenRequestParams` (1183) | `subscriptions-listen-request-params` | `notifications` (`subscription-filter`, required), + `_meta` envelope — **(params: drops unknown)** |
| `SubscriptionsListenRequest` (1202) | `subscriptions-listen-request` | method=`"subscriptions/listen"`, `params` |
| `SubscriptionsAcknowledgedNotificationParams` (1212) | `subscriptions-acknowledged-notification-params` | `notifications` (`subscription-filter`, required), `meta?` |
| `SubscriptionsAcknowledgedNotification` (1233) | `subscriptions-acknowledged-notification` | method=`"notifications/subscriptions/acknowledged"`, `params` |

### L. Prompts — spec.types 1401–1599

| TS type (line) | Racket struct | Fields |
|---|---|---|
| `ListPromptsRequest` (1401) | `list-prompts-request` | method=`"prompts/list"`, `params` (paginated) |
| `ListPromptsResult` (1413) | `list-prompts-result` | `prompts` (list `prompt`), + cacheable/paginated fields |
| `GetPromptRequestParams` (1437) | `get-prompt-request-params` | `name`, `arguments?` (object string→string), + `input-responses?` + `request-state?` + `_meta` envelope — **(params: drops unknown)** |
| `GetPromptRequest` (1456) | `get-prompt-request` | method=`"prompts/get"`, `params` |
| `GetPromptResult` (1469) | `get-prompt-result` | `description?`, `messages` (list `prompt-message`), `meta?`, `result-type?`, (loose) |
| `Prompt` (1494) | `prompt` | `name`, `title?`, `description?`, `arguments?` (list `prompt-argument`), `icons?`, `meta?` |
| `PromptArgument` (1513) | `prompt-argument` | `name`, `title?`, `description?`, `required?` (bool) |
| `PromptMessage` (1539) | `prompt-message` | `role`, `content` (`content-block`) |
| `PromptListChangedNotification` (1588) | `prompt-list-changed-notification` | method=`"notifications/prompts/list_changed"`, `params?` |

### M. Tools — spec.types 1602–1845

| TS type (line) | Racket struct | Fields | Notes |
|---|---|---|---|
| `ListToolsRequest` (1602) | `list-tools-request` | method=`"tools/list"`, `params` (paginated) | |
| `ListToolsResult` (1614) | `list-tools-result` | `tools` (list `tool`), + cacheable/paginated fields | |
| `CallToolRequestParams` (1698) | `call-tool-request-params` | `name`, `arguments?` (object), + `input-responses?` + `request-state?` + `_meta` envelope — **(params: drops unknown)** | NO `task?` (tasks removed); extends InputResponseRequestParams |
| `CallToolRequest` (1717) | `call-tool-request` | method=`"tools/call"`, `params` | |
| `CallToolResult` (1644) | `call-tool-result` | `content` (list `content-block`), `structured-content?` (any), `is-error?` (bool), `meta?`, `result-type?`, (loose) | |
| `Tool` (1808) | `tool` | `name`, `title?`, `description?`, `input-schema` (loose `hasheq` w/ `$schema?`/`type:"object"`), `output-schema?` (loose `hasheq`), `annotations?` (`tool-annotations`), `icons?`, `meta?` | NO `execution`/`ToolExecution` (tasks removed) |
| `ToolAnnotations` (1747) | `tool-annotations` | `title?`, `read-only-hint?`, `destructive-hint?`, `idempotent-hint?`, `open-world-hint?` (bool) | confirm fields 1747–1808 |
| `ToolListChangedNotification` (1730) | `tool-list-changed-notification` | method=`"notifications/tools/list_changed"`, `params?` | |

> `Tool.inputSchema`/`outputSchema` are open JSON-Schema fragments — model as loose `hasheq`
> (`$schema` preserved verbatim), exactly the 003 verdict. NO `ToolExecution`/`task-support`.

### N. Logging (DEPRECATED but in-revision) — spec.types 1847–1905

| TS type (line) | Racket struct | Fields | Notes |
|---|---|---|---|
| `LoggingLevel` (1905) | `logging-level/c` = `(or/c "debug" "info" "notice" "warning" "error" "critical" "alert" "emergency")` | — | deprecated; used by the `_meta` logLevel envelope key |
| `LoggingMessageNotificationParams` (1861) | `logging-message-notification-params` | `level` (logging-level/c), `logger?`, `data` (any, required), `meta?` | deprecated |
| `LoggingMessageNotification` (1888) | `logging-message-notification` | method=`"notifications/message"`, `params` | deprecated; client opts in via `_meta` logLevel |

> **There is NO `logging/setLevel` request in 2026** — it is replaced by the `_meta`
> `io.modelcontextprotocol/logLevel` envelope key. Do NOT implement a `set-level-request`. Note
> this removal in the module comment.

### O. Sampling (DEPRECATED but in-revision) — spec.types 1907–2080, 2324–2407

| TS type (line) | Racket struct | Fields | Notes |
|---|---|---|---|
| `CreateMessageRequestParams` (1926) | `create-message-request-params` | `messages` (list `sampling-message`), `model-preferences?`, `system-prompt?`, `include-context?` (`"none"`\|`"thisServer"`\|`"allServers"`; latter two deprecated), `temperature?`, `max-tokens` (number, **required**), `stop-sequences?`, `metadata?` (object), `tools?` (list `tool`), `tool-choice?` (`tool-choice`) | NO `task?`; NO `_meta`/RequestParams base (server→client; plain params) |
| `CreateMessageRequest` (2007) | `create-message-request` | method=`"sampling/createMessage"`, `params` | |
| `CreateMessageResult` (2032) | `create-message-result` | `SamplingMessage` fields (`role`, `content`, `meta?`) + `model` (string), `stop-reason?` (open enum: endTurn\|stopSequence\|maxTokens\|toolUse\|string) | extends SamplingMessage (flatten) |
| `ToolChoice` (1985) | `tool-choice` | `mode?` (`"auto"`\|`"required"`\|`"none"`) | |
| `SamplingMessage` (2067) | `sampling-message` | `role`, `content` (`sampling-message-content-block` OR list of), `meta?` | `content` is Block \| Block[] |
| `ModelPreferences` (2324) | `model-preferences` | `hints?` (list `model-hint`), `cost-priority?`, `speed-priority?`, `intelligence-priority?` (numbers) | confirm 2324–2382 |
| `ModelHint` (2382) | `model-hint` | `name?` (string) | |

### P. Content blocks — spec.types 2080, 2122–2322

Shapes unchanged from 003 (verify the line ranges during impl).

| TS type (line) | Racket struct/contract | Fields |
|---|---|---|
| `ContentBlock` (2122) | `content-block/c` = `(or/c text-content? image-content? audio-content? resource-link? embedded-resource?)` | union |
| `SamplingMessageContentBlock` (2080) | `sampling-message-content-block/c` = `(or/c text-content? image-content? audio-content? tool-use-content? tool-result-content?)` | union |
| `TextContent` (2132) | `text-content` | type=`"text"`, `text`, `annotations?`, `meta?` |
| `ImageContent` (2156) | `image-content` | type=`"image"`, `data`, `mime-type`, `annotations?`, `meta?` |
| `AudioContent` (2187) | `audio-content` | type=`"audio"`, `data`, `mime-type`, `annotations?`, `meta?` |
| `ResourceLink` (1554) | `resource-link` | `resource` fields + type=`"resource_link"` |
| `EmbeddedResource` (1569) | `embedded-resource` | type=`"resource"`, `resource` (text\|blob), `annotations?`, `meta?` |
| `ToolUseContent` (2222) | `tool-use-content` | type=`"tool_use"`, `id`, `name`, `input` (object), `meta?` |
| `ToolResultContent` (2261) | `tool-result-content` | type=`"tool_result"`, `tool-use-id`, `content` (list `content-block`), `structured-content?`, `is-error?`, `meta?` |

> Confirm exact field ranges (`ImageContent` 2156+, `ToolUseContent` 2222+, `ToolResultContent`
> 2261+) against the file; the §P line cites above are interface-start lines, read each body.

### Q. Autocomplete / completion — spec.types 2409–2513

| TS type (line) | Racket struct | Fields |
|---|---|---|
| `CompleteRequestParams` (2409) | `complete-request-params` | `ref` (`prompt-reference`\|`resource-template-reference`), `argument` (`{name value}`), `context?` (`{arguments?}`), + `_meta` envelope — **(params: drops unknown)** |
| `CompleteRequest` (2444) | `complete-request` | method=`"completion/complete"`, `params` |
| `CompleteResult` (2460) | `complete-result` | `completion` (`{values (list string) total? has-more?}`), `meta?`, `result-type?`, (loose) |
| `ResourceTemplateReference` (2496) | `resource-template-reference` | type=`"ref/resource"`, `uri` |
| `PromptReference` (2511) | `prompt-reference` | type=`"ref/prompt"`, `name`, `title?` |

### O2. Roots (DEPRECATED but in-revision) — spec.types 2515–2600

| TS type (line) | Racket struct | Fields |
|---|---|---|
| `ListRootsRequest` (2534) | `list-roots-request` | method=`"roots/list"`, `params?` (RequestParams) |
| `ListRootsResult` (2556) | `list-roots-result` | `roots` (list `root`) ONLY — see BARE-INTERFACE warning |
| `Root` (2572) | `root` | `uri` (string), `name?`, `meta?` (Root DOES carry `_meta?`, line 2580) |

> **BARE-INTERFACE WARNING (round-trip-breaker — PIN THIS):** Unlike every other result in this
> revision, `ListRootsResult` (spec.types:2556) is declared `interface ListRootsResult { roots:
> Root[]; }` — it does **NOT** `extends Result`, so it has **NO `_meta`, NO `resultType`, and NO
> loose `rest`**. Likewise `ListRootsRequest` (2534) is a **bare** interface (`{ method; params?:
> RequestParams }`, NOT `extends JSONRPCRequest`). **The implementer MUST NOT bolt the generic
> `meta?` / `result-type?` / `rest` trio onto `list-roots-result`** — doing so would emit phantom
> `_meta`/`resultType` keys (and absorb stray keys into a non-existent `rest`) and BREAK the
> round-trip against a real `{"roots":[...]}` payload. Model `list-roots-result` as a `struct`
> with the SINGLE field `roots` (no `meta`, no `result-type`, no `rest`); its serializer emits
> EXACTLY `{"roots": [...]}` and nothing else. **NOTE the inner-vs-outer distinction:** the
> `Root` struct itself DOES carry `_meta?` (line 2580) — that `meta` lives on each `root`, not on
> the enclosing `list-roots-result`. The 2025 `roots-list-changed-notification` is GONE.
>
> **Test note (add to Testing Part 1 / Part 4):** `list-roots-result` round-trips with EXACTLY
> `{"roots":[...]}` — assert the re-serialized jsexpr has key-set `'(roots)` only (e.g.
> `(equal? (hash-keys rt) '(roots))`), and that a `list-roots-result` carrying a stray top-level
> key is NOT silently preserved (it has no `rest`). A per-`root` `_meta` inside the list still
> round-trips (it lives on the `root` struct).

### P2. Elicitation — spec.types 2602–2982

| TS type (line) | Racket struct | Fields | Notes |
|---|---|---|---|
| `ElicitRequestFormParams` (2602) | `elicit-request-form-params` | `mode?`=`"form"`, `message`, `requested-schema` (`{$schema? type:"object" properties (string→primitive-schema) required?}`) | NO `task?`, NO `_meta` (plain server→client params) |
| `ElicitRequestURLParams` (2635) | `elicit-request-url-params` | `mode`=`"url"` (req), `message`, `elicitation-id`, `url` | NO `task?` |
| `ElicitRequestParams` (2665) | `elicit-request-params/c` = `(or/c elicit-request-form-params? elicit-request-url-params?)` | discriminate on `mode` |
| `ElicitRequest` (2675) | `elicit-request` | method=`"elicitation/create"`, `params` |
| `ElicitResult` (2949) | `elicit-result` | `action` (`"accept"`\|`"decline"`\|`"cancel"`), `content?` (object string→string\|number\|bool\|list) |
| `ElicitationCompleteNotification` (2974) | `elicitation-complete-notification` | method=`"notifications/elicitation/complete"`, `params` (`{elicitation-id}`) |
| `PrimitiveSchemaDefinition` (2686) | `primitive-schema-definition/c` = union of the 4 | |
| `StringSchema` (2694) | `string-schema` | type=`"string"`, `title?`, `description?`, `min-length?`, `max-length?`, `format?` (`email`\|`uri`\|`date`\|`date-time`), `default?` |
| `NumberSchema` (2710) | `number-schema` | type=`"number"`\|`"integer"`, `title?`, `description?`, `minimum?`, `maximum?`, `default?` |
| `BooleanSchema` (2734) | `boolean-schema` | type=`"boolean"`, `title?`, `description?`, `default?` (bool) |
| `UntitledSingleSelectEnumSchema` (2749) | `untitled-single-select-enum-schema` | type=`"string"`, `title?`, `description?`, `enum` (list string), `default?` |
| `TitledSingleSelectEnumSchema` (2777) | `titled-single-select-enum-schema` | type=`"string"`, …, `one-of` (list `{const title}`), `default?` |
| `SingleSelectEnumSchema` (2810) | (union) = `(or/c untitled-single-select-enum-schema? titled-single-select-enum-schema?)` | |
| `UntitledMultiSelectEnumSchema` (2820) | `untitled-multi-select-enum-schema` | type=`"array"`, `title?`, `description?`, `min-items?`, `max-items?`, `items` (`{type:"string" enum}`), `default?` |
| `TitledMultiSelectEnumSchema` (2862) | `titled-multi-select-enum-schema` | type=`"array"`, …, `items` (`{any-of (list {const title})}`), `default?` |
| `MultiSelectEnumSchema` (2908) | (union) | |
| `LegacyTitledEnumSchema` (2916) | `legacy-titled-enum-schema` | type=`"string"`, `title?`, `description?`, `enum` (list string), `enum-names?` (list string), `default?` — deprecated but in-revision |
| `EnumSchema` (2933) | `enum-schema/c` = union of single\|multi\|legacy | |

### R. Typed error structs (NEW) — spec.types 281–424

| TS type (line) | Racket binding | Notes |
|---|---|---|
| `ParseError` (281) | code-pinned constructor/predicate on `jsonrpc-error` w/ `code = PARSE-ERROR` | provide `make-parse-error`/`parse-error?` (or a generic `code` matcher) |
| `InvalidRequestError` (292) | `code = INVALID-REQUEST` | |
| `MethodNotFoundError` (310) | `code = METHOD-NOT-FOUND` | |
| `InvalidParamsError` (342) | `code = INVALID-PARAMS` | |
| `InternalError` (356) | `code = INTERNAL-ERROR` | |
| `UnsupportedProtocolVersionError` (387) | `jsonrpc-error-response` w/ `error.code = UNSUPPORTED-PROTOCOL-VERSION` (-32004) + `error.data = {supported (list string), requested (string)}` | provide constructor + predicate (mirrors 003's URL-elicit error pattern) |
| `MissingRequiredClientCapabilityError` (414) | `jsonrpc-error-response` w/ `error.code = MISSING-REQUIRED-CLIENT-CAPABILITY` (-32003) + `error.data = {requiredCapabilities (client-capabilities)}` | constructor + predicate |

> The five plain code-pinned errors (`ParseError`…`InternalError`) are just `jsonrpc-error`
> with a fixed `code`; provide predicate helpers but they do NOT each need a distinct struct
> (decide during impl — a single `jsonrpc-error` struct + `code`-matching predicates is cleanest,
> mirroring how item 006/007 will handle the error hierarchy). The two **data-carrying** errors
> DO warrant constructor+predicate+data-shape contracts (parallel to 003's
> `url-elicitation-required-error`).

### S. Result-response envelope wrappers (NEW) + message union aggregates — spec.types 605, 1035–1132, 2986–3030

The 2026 revision adds per-method typed `*ResultResponse` interfaces (e.g.
`ListResourcesResultResponse` (1035), `ReadResourceResultResponse` (1132, = `Result | InputRequiredResult`),
`CallToolResultResponse` (1683), `GetPromptResultResponse` (1485), `DiscoverResultResponse` (605),
etc.). These are just `JSONRPCResultResponse` with a typed `result` body — **do NOT create a
distinct struct per wrapper**; the generic `jsonrpc-result-response` envelope + the typed result
body composes them (same as 003's envelope-composition model). Note the union-typed ones
(`X | InputRequiredResult`) in the `client-result/c`/`server-result/c` aggregates.

| TS type (line) | Racket binding | Members |
|---|---|---|
| `ClientRequest` (2986) | `client-request/c` | union over the 10 client request structs (§ counts) |
| `ClientNotification` (2999) | `client-notification/c` | `(or/c cancelled-notification? progress-notification?)` |
| `ClientResult` (3002) | `client-result/c` | `= result?` (EmptyResult only) |
| `ServerNotification` (3007) | `server-notification/c` | union over 9 (incl. subscriptions-acknowledged) |
| `ServerResult` (3019) | `server-result/c` | union over 11 (incl. `discover-result`, `input-required-result`) |
| `JSONRPCMessage` (34) | `jsonrpc-message/c` | request \| notification \| response |

> There is **NO `server-request/c`** in this revision (no `ServerRequest` union). The three
> server→client requests are captured by `input-request/c` (§F) instead.

---

## Diff vs `2025-11-25` (item 003) — THE ANALYTICAL CORE

This revision is a **major restructure** (3030 vs 2559 lines). Do NOT clone 003 and tweak.

### Headline RC feature: the per-request `_meta` reserved-key envelope
- `RequestMetaObject` (spec.types:70) carries protocol-version, client info, client
  capabilities, the related-task ref, and the **deprecated** log level — replacing the 2025
  `initialize` handshake AND the 2025 `logging/setLevel` RPC. `RequestParams._meta` is
  **required** (spec.types:133). Reserved key strings (constants.ts):
  - `io.modelcontextprotocol/protocolVersion` — `PROTOCOL_VERSION_META_KEY` (constants.ts:14)
  - `io.modelcontextprotocol/clientInfo` — `CLIENT_INFO_META_KEY` (constants.ts:19)
  - `io.modelcontextprotocol/clientCapabilities` — `CLIENT_CAPABILITIES_META_KEY` (constants.ts:27)
  - `io.modelcontextprotocol/logLevel` — `LOG_LEVEL_META_KEY` (constants.ts:38, **deprecated**)
  - `io.modelcontextprotocol/related-task` — `RELATED_TASK_META_KEY` (constants.ts:5)
  - `progressToken` (non-prefixed) — spec.types:74
- Modeled as the `request-meta` struct (§C). **This is the RC-only field set the test MUST
  assert is present and parsed (Acceptance + Testing Part 4).**

### REMOVED in 2026 (present in 003):
- **`initialize`** family entirely: `InitializeRequest`/`InitializeResult`/
  `InitializeRequestParams`/`InitializedNotification` → replaced by `_meta` envelope +
  `server/discover`.
- **`ping`** (`PingRequest`).
- **`logging/setLevel`** (`SetLevelRequest`/`SetLevelRequestParams`) → replaced by `_meta`
  logLevel.
- **ALL tasks**: `tasks/get`|`result`|`list`|`cancel` requests, `Task`, `TaskMetadata`,
  `RelatedTaskMetadata` *struct as a task field* (the `related-task` `_meta` key survives, see
  schemas.ts:60), `CreateTaskResult`, `GetTaskResult`/`CancelTaskResult` (the `Result & Task`
  intersections — GONE), `GetTaskPayloadResult`, `ListTasksResult`, `TaskStatus`,
  `TaskStatusNotification`, `ToolExecution`/`task-support`. **The three intersection-type traps
  from 003 (§J TRAP) DO NOT EXIST here.** The `task?` field is removed from `CallToolRequestParams`,
  `CreateMessageRequestParams`, and `ElicitRequest*Params`.
- **`resources/subscribe`** + **`resources/unsubscribe`** (`SubscribeRequest`/`UnsubscribeRequest`
  + params) → replaced by `subscriptions/listen` + `SubscriptionFilter.resourceSubscriptions`.
- **`URLElicitationRequiredError`** (`-32042`) — not in this revision. (`URL-ELICITATION-REQUIRED`
  constant stays in constants.rkt for 003; just don't use it here.)
- **`notifications/initialized`**, **`notifications/roots/list_changed`**,
  **`notifications/tasks/status`** notifications.
- **The `ServerRequest` union** (no aggregate; server→client requests live in `InputRequest`).

### ADDED in 2026 (not in 003):
- **`server/discover`**: `DiscoverRequest`/`DiscoverResult`/`DiscoverResultResponse` (§E).
- **`subscriptions/listen`**: `SubscriptionsListenRequest`(+Params), `SubscriptionFilter`,
  `SubscriptionsAcknowledgedNotification`(+Params) (§K).
- **Typed JSON-RPC error structs**: `ParseError`/`InvalidRequestError`/`MethodNotFoundError`/
  `InvalidParamsError`/`InternalError` (code-pinned) + the two data-carrying
  `UnsupportedProtocolVersionError` (-32004) and `MissingRequiredClientCapabilityError` (-32003)
  (§R).
- **Multi-round-trip / input family**: `InputRequest`/`InputResponse` unions,
  `InputRequests`/`InputResponses` maps, `InputRequiredResult`, `InputResponseRequestParams` (§F).
- **`CacheableResult`** (`ttlMs` + `cacheScope`) — base mixin flattened into list/read results (§I).
- **`resultType`** discriminator (`ResultType` = `complete`|`input_required`|string) on EVERY
  `Result` (spec.types:187) — model as a named result field, not in `rest`.
- **`ClientCapabilities`/`ServerCapabilities` `extensions` field**; **`tasks` capability removed**;
  `roots`/`sampling`/`logging` capabilities + `logLevel`/sampling/roots types **deprecated**
  (SEP-2577) but in-revision (still implement).
- **Per-method `*ResultResponse` envelope wrappers** (§S) — composed from the generic envelope.
- Several results typed `X | InputRequiredResult` (read/get-prompt/tools-call responses).

### CHANGED (same name, different shape):
- **`Result`** gains `resultType?` (§B).
- **`CallToolRequestParams`/`GetPromptRequestParams`/`ReadResourceRequestParams`** now extend
  `InputResponseRequestParams` → add `inputResponses?` + `requestState?`; lose `task?`.
- **List/read results** (`ListResourcesResult`, `ListResourceTemplatesResult`, `ListToolsResult`,
  `ListPromptsResult`, `ReadResourceResult`) now extend `CacheableResult` → add
  `ttlMs` + `cacheScope`.
- **`Tool`** loses `execution`/`ToolExecution`.
- **`SamplingMessage`/`CreateMessageRequestParams`** lose `task?`.
- **`ElicitRequest*Params`** lose `task?`.
- **`ListRootsRequest`/`ListRootsResult`** declared as plain interfaces (NOT `extends
  JSONRPCRequest`/`Result`) — confirm `_meta` presence during impl.

### UNCHANGED in shape (port 003's structs ~verbatim, modulo `resultType`/`_meta` additions):
Content blocks (text/image/audio/resource_link/resource/tool_use/tool_result), `Annotations`,
`Icon`/`Icons`, `BaseMetadata`, `Implementation`, `Resource`/`ResourceTemplate`,
`Text`/`BlobResourceContents`, `Prompt`/`PromptArgument`/`PromptMessage`, `ToolAnnotations`,
`ModelPreferences`/`ModelHint`/`ToolChoice`/`SamplingMessage`, the elicitation primitive/enum
schema family, the completion refs, `Role`/`LoggingLevel` enums, `CancelledNotificationParams`,
`ProgressNotificationParams`. (Verify each against the 2026 line cites — do not assume.)

---

## Acceptance criteria

- [ ] `mcp/core/types/spec-2026-07-28.rkt` exists as `#lang racket/base` with
      `(require racket/contract)` and an explicit curated `(provide …)` (no `(all-defined-out)`),
      mirroring item 003's surface style (raw transparent structs + provided `…/c` contracts).
- [ ] **Every** type in §Type inventory (A–S) is implemented: a transparent `struct` per object
      type, a flat `…/c` contract per type (incl. string-enum + union contracts), kebab-case
      fields mapped to the EXACT JSON camelCase keys (and the prefixed
      `io.modelcontextprotocol/...` literals for the `_meta` envelope).
- [ ] Structs are `#:transparent`; predicates provided; each `…/c` is `contract?`-true and
      rejects malformed inputs (wrong type, missing required field, wrong literal `type`/`method`,
      out-of-enum).
- [ ] **`request-meta` envelope struct** is implemented with NAMED fields for the reserved keys
      (`protocol-version`, `client-info`, `client-capabilities`, `log-level`, `related-task`,
      `progress-token`) + a `rest` for unreserved `_meta` keys; `request-meta/c` requires the
      three required reserved keys present; `json->request-meta`/`request-meta->json` round-trip
      the exact `io.modelcontextprotocol/...` key strings. Reserved key strings imported from
      `constants.rkt` (`*-META-KEY` constants added by this item).
- [ ] **Deserialization** `(json->X jsexpr)` for each top-level message type maps a `read-json`
      jsexpr into the struct, splitting unknown/`_meta` keys into `rest` for loose types and into
      the `request-meta` envelope for request params.
- [ ] **Serialization** `(X->json struct)`: omits absent optionals (NO `"k": null`); merges
      `rest`/`_meta` back verbatim; emits the reserved `_meta` keys at their exact prefixed
      strings; maps kebab fields back to the exact camelCase / `$schema` / `_meta` keys; emits
      `resultType` for results that carry it.
- [ ] **Round-trip parity** for a representative message of **each envelope kind** (request,
      notification, result-response, error-response) — at minimum: a `server/discover` request
      (with a full `_meta` envelope), a `tools/call` request (with `_meta` envelope +
      `inputResponses`), a `discover` result, a `notifications/progress` notification, a
      `tools/list` result with pagination + `ttlMs`/`cacheScope` + `_meta` + `resultType`, a
      `subscriptions/listen` request, and an error response — parse→struct→re-serialize yields
      JSON **semantically identical** to the fixture (canonical `jsexpr=?`, unordered object keys;
      NOT raw bytes; reuse 003's comparator).
- [ ] **RC-ONLY-FIELDS PRESENT-AND-PARSED (the distinguishing criterion):** a request fixture
      carrying the full `_meta` envelope round-trips with the FIVE reserved keys present and
      parsed into the `request-meta` named fields — assert
      `(request-meta-protocol-version …)`, `client-info`, `client-capabilities`, `log-level`,
      `related-task` are the expected values (NOT `absent`, NOT swept into `rest`, NOT dropped),
      AND the re-serialized JSON contains the exact `io.modelcontextprotocol/...` key strings.
      Also assert: a result carries `resultType` round-tripped; a list/read result carries
      `ttlMs`/`cacheScope`; an `InputRequiredResult` round-trips its `inputRequests`/`requestState`.
- [ ] **`_meta`/extra-key passthrough (RESULTS ONLY):** a result fixture with `_meta` + an unknown
      extra key round-trips with BOTH preserved (in `rest`). **Request/notification PARAMS DROP**
      an unknown non-`_meta` key on round-trip (non-loose `BaseRequestParamsSchema`); only the
      `_meta` envelope (named field) survives. An UNRESERVED `_meta` key inside the envelope
      survives (in `request-meta`'s `rest`).
- [ ] **Contract-rejection** per category: e.g. a `request-meta` missing `protocolVersion` →
      rejected; `tools/call` with non-string `name` → rejected; `cacheable` result missing
      `ttlMs` → rejected (or absent → handled per the required-field rule); a content block
      `type:"text"` missing `text` → rejected; `subscriptions/listen` missing `notifications` →
      rejected; `UnsupportedProtocolVersionError` with non-list `data.supported` → rejected; an
      out-of-enum `cacheScope` ("shared") → rejected.
- [ ] **Three-way strictness parity:** (a) envelope with extra top-level key → **rejected**;
      (b) result with extra inner key → **accepted + preserved**; (c) concrete params with extra
      non-`_meta` key → **accepted but key DROPPED** on re-serialize.
- [ ] The error codes / `JSONRPC-VERSION` come from `constants.rkt` (not re-literaled);
      `UnsupportedProtocolVersionError` uses `UNSUPPORTED-PROTOCOL-VERSION` (-32004);
      `MissingRequiredClientCapabilityError` uses `MISSING-REQUIRED-CLIENT-CAPABILITY` (-32003).
      The five reserved `_meta` key strings come from the new `*-META-KEY` constants.
- [ ] `raco test mcp/core/types/` passes (exit 0) from repo root — module + test compile and load
      cleanly alongside items 001/002/003.
- [ ] **Portability (NFR):** the module requires only `racket/base`, `racket/contract`, `json`
      (jsexpr conventions; no I/O at load), and `constants.rkt` (+ optionally `spec-2025-11-25.rkt`
      for shared helpers — see Decisions). No subprocess/socket module.
- [ ] **N1-readiness:** per-primitive structs + union contracts individually provided; the
      `absent` sentinel reused from 003 (or re-exported consistently) so 005 can union 003+004
      field-by-field. A comment documents the field-presence model + the union-compatibility
      decision with 003.
- [ ] **Parity-matrix discipline:** the progress row for `spec-2026-07-28.rkt` advances
      📋→🚧→✅ (the row was already SPLIT from 003's by item 003 — see Completion Reminder);
      sibling rows (`spec-2025-11-25`, `types.rkt`, errors) untouched.

---

## Implementation steps

1. **Confirm collection dirs** exist (`mcp/core/types/`, `mcp/core/types/test/` — created by item
   001/003).
2. **Re-read `spec.types.2026-07-28.ts` IN FULL** against §Type inventory + §Diff — verify every
   line citation and that nothing changed upstream since 2026-06-17 (frozen commit `9d700ed`).
   **Read `spec.types.2025-11-25.ts` + `spec-2025-11-25.rkt` + its test side-by-side** as the
   template. Read `schemas.ts` (esp. `RequestMetaSchema` :64, `BaseRequestParamsSchema` :78,
   `ResultSchema` :118) and `constants.ts` (the 5 `*_META_KEY` strings).
3. **Add the five `*-META-KEY` constants to `constants.rkt`** (additive): `PROTOCOL-VERSION-META-KEY`,
   `CLIENT-INFO-META-KEY`, `CLIENT-CAPABILITIES-META-KEY`, `LOG-LEVEL-META-KEY`,
   `RELATED-TASK-META-KEY` — exact strings from constants.ts; add to its `provide`. Do NOT touch
   item 001's existing codes/versions.
4. **Decide shared-helpers strategy** (Decisions → shared-helpers): either (a) `(require (only-in
   "spec-2025-11-25.rkt" absent absent? present? …))` and reuse 003's `absent` sentinel + any
   helpers it provides, or (b) duplicate the internal helper block. **The `absent` sentinel MUST
   be the SAME binding 005 unions against** — prefer importing/re-exporting 003's. Record the
   choice.
5. **Write `mcp/core/types/spec-2026-07-28.rkt`**, `#lang racket/base`, requiring `racket/contract`
   + the `constants.rkt` codes/versions/META-KEYs. Group with section comments matching §A–S, and
   add a top-of-file comment listing the REMOVED 2025 families (initialize/ping/setLevel/tasks/
   subscribe) so a reader isn't surprised by their absence. For each type: transparent struct →
   `name/c` → `json->name` / `name->json`.
6. **Implement the `request-meta` envelope FIRST** (it is referenced by every request params
   struct): named reserved-key fields + `rest`; split/merge against the `*-META-KEY` constants;
   `request-meta/c` requires the 3 required keys.
7. **Reuse 003's helper patterns** (`json-object?`, `h-opt`/`h-req`, `put`/`put!`, `opt-map`,
   `opt-list`/`req-list`, `split-loose`, `hash-merge`, `lit/c`, `opt/c`) — copy or import.
8. **Dispatch deserializers** for the unions (`content-block`, `sampling-message-content-block`,
   `primitive-schema-definition`, `enum-schema`, `elicit-request-params`, `input-request`,
   `input-response`) on their discriminator (`type`/`mode`/shape).
9. **Add the explicit `provide`** (structs, predicates, `…/c`, `json->`/`->json` per top-level
   type, the `request-meta` triad, the aggregate union contracts, the error
   constructors/predicates, the `absent` sentinel — re-exported if imported from 003).
10. **Author JSON fixtures** under `mcp/core/types/test/fixtures/` with a `2026-` prefix to avoid
    colliding with 003's fixtures (e.g. `2026-discover-request.json`) — hand-authored, camelCase
    copied from the `.ts` (NO ready-made fixtures exist; see Testing).
11. **Write the test** `mcp/core/types/test/spec-2026-07-28-test.rkt` (round-trip + RC-field-presence
    + passthrough + rejection + strictness + field-mapping — see Testing). Reuse 003's `jsexpr=?`
    comparator.
12. **Run** `raco test mcp/core/types/` from repo root; fix mismatches. Likely failures:
    `_meta` reserved-key string mapping; required-vs-absent on the envelope; `resultType`/
    `ttlMs`/`cacheScope` on results; union dispatch.
13. **Update progress + parity matrix** (Completion Reminder).

---

## Testing strategy

**Test file:** `mcp/core/types/test/spec-2026-07-28-test.rkt` (`#lang racket/base`, `require
rackunit`, `json`, `racket/runtime-path`, the module under test). **Reuse item 003's `jsexpr=?`
comparator verbatim** (unordered object keys; lists in order; numbers by `=`; `'null` by `eq?`;
NOT raw bytes). Six parts (mirrors 003 + adds Part 4 for the RC fields).

### Fixture source decision (CALLED OUT)

**No ready-made JSON fixtures exist** for this revision in the TS checkout (confirmed
2026-06-17): the `@includeCode ./examples/...` paths in the JSDoc have **no backing `.json`
files** under `packages/core/src/types/` (the `examples/` dir referenced doesn't exist there);
`specTypeSchema.examples.ts` is JSDoc-snippet bait; no `*2026*.json` anywhere under `packages/
core`. **Therefore hand-author the fixtures** from the exact TS type shapes (each field a valid
example, camelCase copied from the `.ts` with line cites in the test header), stored as `.json`
under `mcp/core/types/test/fixtures/` with a **`2026-` filename prefix** so they don't collide
with 003's fixtures in the shared dir. Belt: the test validates each fixture against its struct's
contract; suspenders: the copy-from-source discipline + the Part-6 field-mapping unit test.

### Part 1 — round-trip per envelope kind (the queue's core requirement)

For each fixture `F` (at minimum: `2026-discover-request.json`, `2026-tools-call-request.json`,
`2026-discover-result.json`, `2026-progress-notification.json`, `2026-list-tools-result.json`
(with `nextCursor` + `ttlMs` + `cacheScope` + `_meta` + `resultType` + a tool with `inputSchema`),
`2026-subscriptions-listen-request.json`, `2026-error-response.json`, **plus**
`2026-input-required-result.json` (with `inputRequests` + `requestState`), **plus** one
discriminated-union fixture per arm):
1. `(define orig (read-fx F))`; 2. `(define s (json->X orig))`; 3. `(define rt (X->json s))`;
4. assert `(jsexpr=? orig rt)`; 5. belt: `(jsexpr=? (X->json (json->X rt)) rt)`.

**Discriminated-union coverage — ONE round-trip fixture (or sub-value) PER ARM:**
- **`ContentBlock`** (2122) — 5: text, image, audio, resource_link, resource.
- **`SamplingMessageContentBlock`** (2080) — 5: text, image, audio, **tool_use**, **tool_result**
  (the last two never appear in the general ContentBlock test) + a `sampling-message` whose
  `content` is a single block AND one whose `content` is a LIST (Block\|Block[]).
- **`PrimitiveSchemaDefinition`** (2686) — 4: string, number, integer, boolean.
- **`EnumSchema`** (2933) — 5: untitled-single (`enum`), titled-single (`oneOf`), untitled-multi
  (`type:"array"`+`items.enum`), titled-multi (`items.anyOf`), legacy (`enumNames`).
- **`ElicitRequestParams`** (2665) — 2: form, url.
- **`ResourceContents`** — 2: TextResourceContents, BlobResourceContents.
- **`InputRequest`** (435) — 3: createMessage, listRoots, elicit (inside an `inputRequests` map).
- **`InputResponse`** (438) — 3: createMessageResult, listRootsResult, elicitResult (inside an
  `inputResponses` map on a params fixture).
Each arm asserts the EXACT struct predicate (e.g. `(tool-use-content? …)`) AND round-trips.

**Populated capability fixture (HARD MINIMUM):** a `discover-result` whose `ServerCapabilities`
populates `prompts.listChanged`, `resources.{subscribe,listChanged}`, `tools.listChanged`,
`completions`, `logging`, `experimental`, AND the NEW `extensions` map (e.g.
`{"io.modelcontextprotocol/tasks":{}}`); and a `_meta` envelope whose `clientCapabilities`
populates `sampling.{context,tools}`, `elicitation.{form,url}`, `experimental`, and `extensions`.
Assert the deep nested values + the `extensions` map survive round-trip (they live in the loose
capability `hasheq`).

### Part 2 — `_meta` / additionalProperties passthrough (RESULTS preserve, PARAMS drop)

- **Results preserve:** a result fixture (e.g. `2026-list-tools-result.json`) carrying `_meta`
  plus an unknown extra top-level key round-trips with BOTH preserved (`rest`). A content block
  carrying `_meta` preserves it.
- **Params DROP:** a request-params fixture carrying the `_meta` envelope AND an unknown
  non-`_meta` top-level key in `params` round-trips with the `_meta` envelope SURVIVING but the
  unknown key **GONE**.

### Part 3 — contract-rejection (the queue's second requirement)

≥1 reject per category, each a named check: `request-meta` missing `protocolVersion`; `tools/call`
`name`=number; out-of-enum `cacheScope`; content block `{type:"text"}` missing `text` and
`{type:"bogus"}`; `subscriptions/listen` params missing `notifications`; `image-content` missing
`mimeType`; `UnsupportedProtocolVersionError` with non-list `data.supported`; envelope with an
extra top-level key (strict); an `id` of `'null`/`1.5` where a request-id is required.

### Part 4 — RC-ONLY-FIELDS PRESENT-AND-PARSED (THE DISTINGUISHING CRITERION — its own part)

This is what separates item 004 from item 003. Using `2026-discover-request.json` (or a dedicated
`2026-request-meta-envelope.json`) whose `params._meta` carries ALL the reserved keys:
- Assert `json->request-meta` parses each reserved key into its NAMED field:
  `(string? (request-meta-protocol-version m))`,
  `(implementation? (request-meta-client-info m))`,
  `(client-capabilities? (request-meta-client-capabilities m))`,
  `(member (request-meta-log-level m) '("debug" …))`,
  `(related-task-metadata? (request-meta-related-task m))`,
  and `(present? …)` on each (NONE is `absent`, NONE landed in `rest`).
- Assert an UNRESERVED `_meta` key (e.g. `"com.example/trace"`) lands in `request-meta`'s `rest`
  and survives round-trip.
- Assert the re-serialized JSON contains the EXACT key strings `io.modelcontextprotocol/protocolVersion`,
  `…/clientInfo`, `…/clientCapabilities`, `…/logLevel`, `…/related-task` (and that those equal the
  `*-META-KEY` constants).
- Assert `resultType` is parsed + re-emitted on a result; `ttlMs`/`cacheScope` on a list/read
  result; `inputRequests`/`requestState` on an `InputRequiredResult`. These are the 2026-only
  struct fields; none may be silently dropped.

### Part 5 — three-way strictness parity

- Envelope with extra top-level key → **rejected**.
- Result with extra inner key → **accepted AND preserved** (assert acceptance here; Part 2 asserts
  preservation).
- Concrete params with extra non-`_meta` key → **accepted but DROPPED** on re-serialize.
- `UnsupportedProtocolVersionError` round-trips with `error.code = -32004`
  (== `UNSUPPORTED-PROTOCOL-VERSION`) + `error.data.{supported,requested}`;
  `MissingRequiredClientCapabilityError` with `error.code = -32003` +
  `error.data.requiredCapabilities`.

### Part 6 — field-name mapping unit test (anti-vacuous; INDEPENDENT of fixtures)

A standalone test (no fixture files): construct structs with known values, serialize, assert the
output `hasheq` has the EXACT JSON keys: `supportedVersions`, `serverInfo`, `clientInfo` (via the
`_meta` envelope literal `io.modelcontextprotocol/clientInfo`), `inputSchema`, `nextCursor`,
`ttlMs`, `cacheScope`, `resultType`, `mimeType`, `uriTemplate`, `isError`, `structuredContent`,
`toolUseId`, `inputResponses`, `requestState`, `_meta`, `$schema` (verbatim), and the FIVE reserved
`io.modelcontextprotocol/...` keys. Deserialize a hand-built jsexpr with those exact keys; assert
each maps to the right field. **Anti-vacuous (process):** fixture camelCase + the prefixed `_meta`
keys MUST be COPIED from `spec.types.2026-07-28.ts` / `constants.ts`, not retyped from memory;
record in Validation Results which lines were cited.

### Edge cases the test must cover (do not leave implicit)

- **Absent vs null:** an absent optional must NOT appear as `null` after round-trip (regression
  assertion: `(hash-has-key? rt 'instructions)` is `#f` when the source omitted it).
- **`_meta` required-ness:** a request params with NO `_meta` → rejected by `…-params/c` (the
  envelope is required per spec.types:133). A request params with `_meta` missing a REQUIRED
  reserved key → rejected by `request-meta/c`.
- **`$schema` / `_meta` key fidelity:** `Tool.inputSchema` carrying `$schema` round-trips with the
  literal `$schema` (kept in the loose schema fragment); the reserved `_meta` keys round-trip at
  their exact prefixed strings.
- **Union discriminators:** each content-block / enum-schema / elicit-mode / input-request arm
  dispatches to the right struct; `sampling-message.content` as single block AND list both
  round-trip.
- **Empty objects:** `result:{}` (EmptyResult — but note results now SHOULD carry `resultType`;
  treat absent `resultType` as accepted, mirroring TS "treat absent as complete"); `params._meta`
  with only the 3 required keys.
- **Number types:** `priority`/`temperature`/`ttlMs` survive `jsexpr=?` (numbers by `=`).
- **`stopReason` / `resultType` open enums:** a non-standard string is accepted.
- **`CacheableResult`:** `ttlMs:0` (valid), `cacheScope:"public"` and `"private"` both round-trip;
  `cacheScope:"shared"` → rejected.

---

## Dependencies

- **Upstream work items:** **item 001** (`constants.rkt` — `JSONRPC-VERSION`, plus the error codes
  `UNSUPPORTED-PROTOCOL-VERSION` (-32004) and `MISSING-REQUIRED-CLIENT-CAPABILITY` (-32003) which
  **already exist** in `constants.rkt` lines 47–48 — verified, no addition needed; this item only
  **ADDS the five new `*-META-KEY` constants**) and **item 002** (`guards.rkt` — the
  jsexpr/`'null`/request-id conventions, re-implemented internally). **item 003**
  (`spec-2025-11-25.rkt`) — the structural template AND the source of the shared `absent` sentinel
  + internal helpers (import or duplicate — see Decisions). All must be green first.
- **Operates on:** parsed JSON (`read-json` jsexpr) → `write-json`-ready jsexpr. No file/network
  I/O at module load; the test reads fixture files.
- **Downstream consumers (informational):** **item 005** (`types.rkt` N1 façade — UNIONs 003 +
  004; this item's per-primitive surface + `absent` sentinel MUST be union-compatible with 003);
  **item 006/007** (errors — will reuse the typed error structs / codes from §R); item 008
  (barrels re-export this module); item 009 (S1 demo).
- **Tooling/runtime:** Racket ≥ 8.x (v9.1 installed; `raco` at `/snap/bin/raco`); `rackunit`; the
  `typescript-sdk/` checkout (read by the implementer; the test reads only local fixtures).

---

## Project-specific adaptations (Racket / contracts / rackunit)

This is a **pure-data module** — structs + flat contracts + jsexpr (de)serialization, no external
services, no I/O at module load, no network, no database. Adaptations (identical to item 003):

- **Language:** `#lang racket/base` + `racket/contract` + `json` (conventions only). Minimal
  `require`s (Portability NFR).
- **Structs not classes (G4):** transparent `struct`s; TS `extends` (incl. multiple inheritance
  like `PaginatedResult, CacheableResult`) flattened into each concrete struct.
- **Flat contracts:** `struct/c` / `flat-named-contract` / `(or/c …)`; the truth is `schemas.ts`;
  round-trip + rejection tests keep the hand-written contracts honest.
- **Naming:** kebab-case structs/fields; predicates `?`; contracts `/c`; screaming-kebab for the
  new `*-META-KEY` constants.
- **Public surface:** explicit `(provide …)` — never `all-defined-out`. Internal helpers not
  provided (except the `absent` sentinel, deliberately re-exported for 005).
- **jsexpr representation:** JSON object = immutable symbol-keyed `hasheq`; null = `'null`; absent
  optional = `absent` sentinel + key omission. **The prefixed `_meta` reserved keys are symbols**
  on the jsexpr side (read-json produces symbol keys), e.g. `(string->symbol
  PROTOCOL-VERSION-META-KEY)` — the (de)serializer must `string->symbol`/`symbol->string` at the
  envelope boundary. **Confirm during impl** that read-json renders `io.modelcontextprotocol/...`
  as a single symbol key (it does — read-json symbol-keys everything).
- **No services / no I/O:** only file access is the test reading hand-authored fixtures.

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None.** No I/O at module load, no service contacted. External artifacts:

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime (v9.1 installed) | compile + run module/tests; `raco` at `/snap/bin/raco` | system install (`racket --version` ≥ 8.0) | n/a |
| Item 001 `constants.rkt` | imports codes + the new `*-META-KEY` constants (added by this item) | item 001 (+ this item's additive edit) | n/a |
| Item 002 `guards.rkt` (conventions only) | shared jsexpr/`'null`/request-id conventions (re-implemented) | item 002 | n/a |
| Item 003 `spec-2025-11-25.rkt` | shared `absent` sentinel + helper patterns (import or duplicate) | item 003 (delivered) | n/a |
| `typescript-sdk/` checkout | implementer reads `spec.types.2026-07-28.ts` + `schemas.ts` + `constants.ts` to build inventory/fixtures | already present at repo root | n/a |
| Hand-authored JSON fixtures | `mcp/core/types/test/fixtures/2026-*.json` — the round-trip inputs | created in step 10 (no ready-made TS fixtures exist) | n/a |

No databases, queues, HTTP servers, or network deps. (Harmless `/home/rev/.bash_env: Permission
denied` on stderr — ignore.)

### Environment Configuration

- **Environment variables / secrets / config files:** none.
- **Ports:** none must be free.
- **Working directory:** run `raco test` from the **repo root**
  (`/home/rev/Linux/Projects/racket_mcp`); the test anchors fixture paths via
  `define-runtime-path` so fixtures resolve regardless of cwd.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0.
  - `test -f mcp/core/types/constants.rkt && test -f mcp/core/types/guards.rkt && test -f mcp/core/types/spec-2025-11-25.rkt` → items 001/002/003 present.
  - `test -d mcp/core/types/test/fixtures` → fixtures dir present.
  - `grep -q PROTOCOL-VERSION-META-KEY mcp/core/types/constants.rkt` → step 3 done.

### Manual Validation Checklist

- [ ] **Build/compile:** `raco make mcp/core/types/spec-2026-07-28.rkt` compiles clean.
- [ ] **Module loads in isolation:** `racket -e '(require (file "mcp/core/types/spec-2026-07-28.rkt"))'` succeeds.
- [ ] **Tests pass:** `raco test mcp/core/types/test/spec-2026-07-28-test.rkt` → exit 0.
- [ ] **Collection tests pass:** `raco test mcp/core/types/` → exit 0 (items 001+002+003+004).
- [ ] **Services started:** N/A.
- [ ] **Application runs:** N/A (library; "running" = require + REPL inspect).
- [ ] **`_meta` envelope verified (REPL):** parse a `server/discover` request whose `params._meta`
      has all 5 reserved keys → `request-meta` with each named field populated; re-serialize →
      exact `io.modelcontextprotocol/...` keys present.
- [ ] **RC-only fields verified (REPL):** a result's `resultType`, a list result's `ttlMs`/
      `cacheScope`, an `InputRequiredResult`'s `inputRequests` all round-trip present.
- [ ] **`_meta` passthrough verified (REPL):** a result with `_meta` + unknown key round-trips
      both; a request params with unknown non-`_meta` key drops it.
- [ ] **Absent-vs-null verified (REPL):** a `discover-result` without `instructions` re-serializes
      WITHOUT an `instructions` key.
- [ ] **Contract-rejection verified (REPL):** `request-meta` missing `protocolVersion` raises;
      `cacheScope:"shared"` raises.
- [ ] **Strict-envelope verified (REPL):** a request jsexpr with an extra top-level key is
      rejected; a result with an extra inner key is accepted.
- [ ] **Drift detection:** flip one expected assertion (or corrupt a fixture's reserved `_meta`
      key string) and confirm the test FAILS; revert.
- [ ] **Health checks pass:** N/A.

### Expected Outcomes

The module MUST export structs + contracts + (de)serializers for **every** type in §A–S. The
test reports a concrete **inventory + counts**:

- **JSON-RPC envelopes:** 4 (request, notification, result-response, error-response).
- **Requests:** **13** = 10 client (`server/discover`, `completion/complete`, `prompts/get`,
  `prompts/list`, `resources/list`, `resources/templates/list`, `resources/read`,
  `subscriptions/listen`, `tools/call`, `tools/list`) + 3 server→client InputRequests
  (`sampling/createMessage`, `roots/list`, `elicitation/create`). (No `ServerRequest` aggregate.)
- **Notifications:** **9** — `cancelled`, `progress`, `resources/list_changed`,
  `subscriptions/acknowledged` (NEW), `resources/updated`, `prompts/list_changed`,
  `tools/list_changed`, `message` (deprecated), `elicitation/complete`.
- **Result types:** **~14** — `EmptyResult`, `DiscoverResult` (NEW), `CompleteResult`,
  `GetPromptResult`, `ListPromptsResult`, `ListResourcesResult`, `ListResourceTemplatesResult`,
  `ReadResourceResult`, `CallToolResult`, `ListToolsResult`, `CreateMessageResult`,
  `ListRootsResult`, `ElicitResult`, `InputRequiredResult` (NEW). (No task results; no
  intersection-type traps.)
- **Errors:** the `jsonrpc-error` inner object + `jsonrpc-error-response` envelope + the 5
  code-pinned predicates (`ParseError`…`InternalError`) + the 2 data-carrying error responses
  `UnsupportedProtocolVersionError` (-32004) and `MissingRequiredClientCapabilityError` (-32003).
- **THE RC envelope:** `request-meta` struct with the 6 named fields (5 reserved `_meta` keys +
  `progressToken`) + `rest`; reserved key strings == the 5 `*-META-KEY` constants.
- **Supporting/common/content/payload types:** ~30 (Result, MetaObject, RequestMeta,
  RelatedTaskMetadata, BaseMetadata, Implementation, Icon, Annotations, Resource, ResourceTemplate,
  Text/BlobResourceContents, Prompt, PromptArgument, PromptMessage, Tool, ToolAnnotations,
  SubscriptionFilter, CacheableResult fields, the 5 content blocks, ModelPreferences, ModelHint,
  ToolChoice, SamplingMessage, the elicitation primitive/enum schema family (~9), the completion
  refs (2), Root, capability structs (2), InputRequired/InputResponse family).
- **Aggregate union contracts:** **6** — `client-request/c`, `client-notification/c`,
  `client-result/c`, `server-notification/c`, `server-result/c`, `jsonrpc-message/c` (NO
  `server-request/c`). Plus `input-request/c`, `input-response/c`.
- **Total named struct types:** **≈ 55–60** (the test prints the exact count; record in Validation
  Results). (Fewer than 003's ~70 because tasks/initialize/ping/setLevel/subscribe are gone,
  partly offset by discover/subscriptions/input/cacheable/error additions.)

**Test outcome:** `raco test mcp/core/types/` → all checks pass, 0 failures, 0 errors. Round-trip
checks ≥ 8 (one per envelope/category fixture); arm fixtures ≥ 29 (5+5+2 content/sampling, 4
primitive, 5 enum, 2 elicit, 2 resource-contents, 3 input-request, 3 input-response); RC-field
checks ≥ 5 (envelope 5 keys + resultType + ttlMs/cacheScope + inputRequests); rejection ≥ 9;
passthrough ≥ 2; strict/loose ≥ 3.

**Total public bindings provided:** the struct types (~55–60) × (struct + predicate + `…/c`) + the
`json->`/`->json` pairs + the 6 union contracts + the `request-meta` triad + the error
constructors/predicates + the re-exported `absent` sentinel. (Exact count recorded during impl.)

### Validation Results

```markdown
## Validation Results (to be filled during execute-item)
- [ ] Service started: N/A (pure-data module)
- [ ] Application started: N/A (library; `require` succeeds)
- [ ] Build verified: `raco make mcp/core/types/spec-2026-07-28.rkt` clean
- [ ] Module load verified: `(require (file ".../spec-2026-07-28.rkt"))` succeeds
- [ ] Tests verified: `raco test mcp/core/types/` → exit 0, N tests passed (0 fail/err)
- [ ] Inventory verified: every type in §A–S implemented (4 envelopes, 13 requests, 9
      notifications, ~14 results, error structs, request-meta envelope, all union arms,
      supporting/content/schema types). Provided group count recorded.
- [ ] constants.rkt META-KEY additions verified: 5 `*-META-KEY` constants present + provided
- [ ] Round-trip verified: discover req/result, tools/call req, progress notif, list-tools
      result, subscriptions/listen req, error response, input-required-result all jsexpr=?
- [ ] RC-FIELDS PRESENT-AND-PARSED verified: request-meta 5 reserved keys parsed to named
      fields + re-emitted at exact prefixed strings; resultType/ttlMs/cacheScope/inputRequests
      round-trip present (NOT dropped)
- [ ] Passthrough verified (RESULTS): _meta + unknown key PRESERVED; unreserved _meta key in
      envelope preserved in request-meta rest
- [ ] Drop verified (PARAMS): unknown non-_meta key DROPPED; _meta envelope survives
- [ ] Absent-vs-null verified: absent `instructions` omitted (not null)
- [ ] Contract-rejection verified: ≥9 malformed inputs rejected (missing protocolVersion,
      numeric name, out-of-enum cacheScope, missing text/mimeType/notifications, non-list
      supported, extra envelope key, 'null/fractional id)
- [ ] Three-way strictness verified: envelope-extra rejected; result-extra preserved;
      params-extra dropped
- [ ] Per-arm union fixtures verified: ≥29 arms each dispatch to correct struct + round-trip
- [ ] Populated capability fixture verified: deep caps + extensions map round-trip
- [ ] Field-mapping unit test verified (fixture-independent): supportedVersions/serverInfo/
      inputSchema/nextCursor/ttlMs/cacheScope/resultType/isError/structuredContent/toolUseId/
      inputResponses/requestState/_meta/$schema + 5 reserved keys exact; keys copied from TS
      source (lines cited in test header)
- [ ] Error structs verified: UnsupportedProtocolVersionError code=-32004 + data.{supported,
      requested}; MissingRequiredClientCapabilityError code=-32003 + data.requiredCapabilities
- [ ] N1-readiness verified: per-primitive structs + union contracts provided; `absent`
      sentinel shared with 003 (imported/re-exported); union-compatibility note present
- [ ] Drift detection: corrupted reserved _meta key string → test exit 1; reverted → all pass
- [ ] Database tables verified: N/A
- [ ] API endpoints verified: N/A
- [ ] Screenshots captured: N/A (no UI)
```

---

## Decisions & Trade-offs

**To be updated during implementation.** Open decisions to settle (with recommended defaults):

- **shared-helpers (003 import vs duplicate):** *Recommended:* `(require (only-in
  "spec-2025-11-25.rkt" absent absent? present?))` and **re-export** them, so 003 and 004 share
  ONE `absent` sentinel binding (item 005 unions both against the same `eq?` sentinel). Duplicate
  the small internal helpers (`json-object?`, `put`, `split-loose`, `lit/c`, `opt/c`, etc.) inline
  OR import the un-provided ones is not possible (003 doesn't provide them) — so either duplicate
  them or have 003 additively provide them. *Recommended:* duplicate the tiny helpers inline (keeps
  004 self-contained; only the `absent` sentinel MUST be shared). Record the final choice and
  whether 003 was touched.
- **`_meta` envelope required-ness:** the spec.types `.d.ts` makes `RequestParams._meta` required
  (line 133) but the runtime `schemas.ts:78` keeps it `.optional()`. *Recommended:* follow the
  `.d.ts` — `request-meta` is REQUIRED on concrete request params (`…-params/c` rejects its
  absence), and `request-meta/c` requires the 3 required reserved keys. Note the schemas.ts
  looseness as a known divergence (the live validator is a cross-revision superset). Revisit if
  the round-trip fixtures (copied from real spec examples) turn out to omit `_meta`.
  **INTENTIONAL ASYMMETRY (record so it is not read as an inconsistency):** both `RequestParams._meta`
  (line 133) and `Result.resultType` (line 187) are declared required (no `?`) in the `.d.ts`, yet
  this spec models `_meta` as REQUIRED but `result-type` as OPTIONAL. This is deliberate, not an
  oversight: `Result.resultType`'s own JSDoc (lines 183–186) explicitly sanctions an absent value
  ("when a client receives a result from a server implementing an earlier protocol version … the
  client MUST treat the absent field as `\"complete\"`") — so absence is a valid, defined on-wire
  state for `resultType` and the contract must accept it. `_meta` has NO such allowance (its
  reserved keys ARE the version-negotiation payload), so it is enforced as required. Net: follow
  the `.d.ts` required-ness for `_meta`; relax `resultType` to optional per its backward-compat
  clause.
- **reserved-key constants location:** add the 5 `*-META-KEY` defines to `constants.rkt` (additive)
  vs define them locally in `spec-2026-07-28.rkt`. *Recommended:* add to `constants.rkt` (single
  source; item 005/006/007 may also need them). Record whether constants.rkt was edited.
- **typed error structs (5 code-pinned):** one `jsonrpc-error` struct + `code`-matching predicates
  vs a distinct struct per error. *Recommended:* reuse the single `jsonrpc-error` struct + provide
  `parse-error?`/`invalid-request-error?`/… predicates that check `code`; only the 2 data-carrying
  errors get constructor+predicate+data-contract (mirrors 003's `url-elicitation-required-error`).
- **`resultType` modeling:** named `result-type` field on every result struct (NOT in `rest`), so
  005 can union it. *Recommended:* yes — named field, `opt/c result-type/c`, absent treated as
  "complete" per TS backward-compat note.
- **`CacheableResult`/`PaginatedResult` flatten:** flatten `ttlMs`/`cacheScope`/`nextCursor` into
  each concrete result (no inheritance). *Recommended:* yes — centralize via
  `read-cacheable-fields`/`emit-cacheable-fields` helpers (parallel to how 003 centralized the
  task-fields flatten).
- **capabilities as loose blob:** same verdict as 003 (top-record struct wrapping the whole cap
  object as one `rest` hasheq). *Recommended:* yes — preserves the NEW `extensions` map + deep
  trees verbatim.
- **`*ResultResponse` wrappers:** compose from the generic `jsonrpc-result-response` envelope +
  typed body; do NOT make a struct per wrapper. *Recommended:* yes (same as 003).
- **fixture filename prefix:** `2026-` prefix on all fixtures to coexist with 003's fixtures in the
  shared `fixtures/` dir. *Recommended:* yes.
- **Canonical equality:** reuse 003's `jsexpr=?` (unordered object keys, lists in order, numbers by
  `=`, `'null` by `eq?`; NOT raw bytes). Settled (003 precedent).

---

## Completion Reminder

On completion, the implementer MUST:

1. **Update `docs/aide/progress.md` — the `spec-2026-07-28.rkt` row.** Item 003 already SPLIT the
   bundled `spec-2025-11-25.rkt + spec-2026-07-28.rkt` deliverable line into two separate rows.
   This item advances the **`spec-2026-07-28.rkt`** row 📋 → 🚧 (when starting) → ✅ (when delivered
   and acceptance criteria pass). **If item 003 did NOT actually split the row** (verify), do the
   split first (two lines), then advance only the 2026 row. Do NOT touch the `spec-2025-11-25.rkt`
   row (already ✅) or any other deliverable. Do not check Stage-S1 acceptance boxes owned by other
   items (façade normalization, error encode/decode). Never revert an icon backward.
2. **Touch the parity-matrix rows** per Stage S1 discipline: advance the roadmap §9 / progress row
   for `spec.types.2026-07-28` (under `core/types/*`) toward `partial` (structs/contracts exist +
   round-trip-tested; full conformance lands later). Per item 009 the broader `core/types/*` flip
   to `partial` is the S1 closeout's job — record only that the `spec-2026-07-28` sub-row is
   satisfied; do not prematurely flip sibling rows.
3. **Record the `constants.rkt` additive edit** (5 `*-META-KEY` constants) in this item's
   Validation Results and Decisions — note that item 001's deliverable was extended additively (its
   row stays ✅; the addition is in-scope for this item per Dependencies).
4. Leave the sibling `core/types/*` deliverables (`constants` — extended but ✅; `guards`,
   `spec-2025-11-25` — ✅; `types.rkt` façade, errors — untouched) at their current status. This
   item delivers only `spec-2026-07-28.rkt` (+ the additive constants edit).
