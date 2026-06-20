# Work Item 005: Public types + normalized-superset façade (N1)

> **Queue:** `docs/aide/queue/queue-001.md` — Item 005
> **Stage:** S1 (Foundation: types, constants, guards, errors — L0 part 1)
> **Module:** M1 (Types) — `types.rkt` sub-unit (the public/normalization surface)
> **Source vision:** `docs/aide/vision.md` §4.1 (versioned-spec → normalization façade;
>   "Versioned spec types … Both `spec.types.2025-11-25` and `spec.types.2026-07-28`
>   represented" → the N1 superset is what handlers see).
> **Source roadmap:** `docs/aide/roadmap.md` Stage S1 → Deliverables line
>   (`mcp/core/types/types.rkt` — public types + N1 normalized-superset façade) and the
>   round-trip / parity discipline.
> **Source architecture:** `docs/aide/architecture.md` §1.3 line 50 (public/internal
>   boundary), line 72 (versioned-spec modules + the normalization seam), and **N1**
>   line 326 (the normalized-superset façade — *the* design constraint for this item).
> **Reference impl (authoritative):** MCP TypeScript SDK v2 at `typescript-sdk/` —
>   `packages/core/src/types/types.ts` (590 lines; the **public re-export / normalization
>   surface** that `Infer<>`s every revision's schema into one `export *` public namespace),
>   `packages/core/src/exports/public/index.ts` (the curated public barrel), plus the two
>   `spec.types.*.ts` revision files unioned underneath.
> **Delivered siblings (the two modules this item UNIONs — template + rigor bar):**
>   `docs/aide/items/003-spec-types-2025-11-25.md` (✅) and
>   `docs/aide/items/004-spec-types-2026-07-28.md` (✅). The Racket modules they produced,
>   `mcp/core/types/spec-2025-11-25.rkt` and `mcp/core/types/spec-2026-07-28.rkt`, are the
>   inputs; this item's façade is their field-by-field union.
> **Status:** 📨 Specified (not yet implemented).

---

## Description

Implement `mcp/core/types/types.rkt`, the **public protocol-types surface** and the
**normalized-superset façade** (architecture **N1**, line 326) for the M1 type layer. Where
items 003/004 each model ONE wire revision, this module exposes **one internal shape per
protocol primitive that is the UNION of both revisions** — the shape every later layer
(transport, the abstract `protocol` engine, `client`, `server`, the handler API) consumes
**regardless of the negotiated protocol version**. Revision-only fields are present-or-absent,
gated by the negotiated version; handlers therefore operate version-agnostically and never
branch on `2025-11-25` vs `2026-07-28`.

This is the Racket analogue of the TS SDK's `packages/core/src/types/types.ts` (the
`Infer<>`-and-`export *` public surface that flattens every revision's Zod schema into one
public type namespace, re-exported through `exports/public/index.ts`). In TS the union is
**static** (the type checker sees both revisions' fields); in Racket — which has no structural
typing — the union must be **realized as concrete code**: one façade struct per primitive whose
field set is `(2025-fields ∪ 2026-fields)`, plus a **normalization seam**
(`normalize-* ` / `denormalize-*` per primitive) that maps a parsed 003 struct OR a parsed 004
struct into the SAME façade struct, with revision-only fields carrying the shared `absent`
sentinel when the source revision lacks them.

The analytical core of this item — and the thing the implementer MUST derive, not hand-wave —
is the **façade inventory** (§4): for each primitive that needs a unified shape, enumerate which
fields are **shared** (present in both revisions), which are **2025-only** (absent on a 2026
message), and which are **2026-only** (absent on a 2025 message). That inventory is the build
contract. It is derived **from the two delivered spec modules + `types.ts`**, field-by-field —
see §4 and the per-primitive tables.

This module sits ABOVE 003 + 004 in the M1 stack and BELOW everything else. It does **no I/O**
and introduces **no new wire shapes** — it only unifies the two revision shapes 003/004 already
produce. It is consumed by item 008 (the `core/types` barrels re-export this module's curated
`provide`), item 009 (the S1 demo will parse an `initialize`/`tools/call` and a 2026
`server/discover`/`tools/call` and see the SAME façade structs), and every S2+ layer.

### A note on scope — what the façade does and does NOT do

- **DOES:** define one superset struct per primitive; provide `normalize-X-from-2025` /
  `normalize-X-from-2026` (per the primitives present in each revision) producing that struct;
  provide `denormalize-X-to-2025` / `denormalize-X-to-2026` producing the right revision struct
  (or **refusing** to emit a field absent from the target revision — the N1 wire-parity rule,
  architecture line 326); provide the façade `…/c` contracts and predicates; provide a curated
  public `(provide …)` that is the M1 public surface.
- **DOES NOT:** parse JSON directly (that is 003/004's `json->X`; the façade composes them —
  `read-json → json->X (per negotiated rev) → normalize-X → façade`), validate per-method
  payload schemas (M3, queue-002), negotiate the version (the `protocol` engine, S3, decides
  which revision is active; the façade is told), or re-litigate strictness (003/004 already
  enforce the three strictness behaviors at the wire boundary).

### Representation conventions (inherited from items 003/004 — non-negotiable)

The façade reuses the EXACT conventions 003/004 established, because it unions their structs:

- **The shared `absent` sentinel.** 003 created `absent` (`(string->uninterned-symbol "absent")`,
  `spec-2025-11-25.rkt`) and provides `absent`/`absent?`/`present?`; 004 imports and re-exports
  the SAME binding. **This item MUST import that one binding** (via `(only-in
  "spec-2025-11-25.rkt" absent absent? present?)` — or `spec-2026-07-28.rkt`, which re-exports
  it; pick ONE and document it) and re-export it. Field-presence in the façade is decided **by
  `(absent? v)`** on the façade struct's fields. A revision-only field on a message from the
  other revision is **`absent`** — never `'null`, never a phantom empty object. This is the
  testability hook the queue's acceptance clause depends on.
- **The union model, per field.** For a façade struct field `f`:
  - If `f` is **shared** (in both 003 and 004's struct for that primitive), `normalize-from-2025`
    and `normalize-from-2026` both copy it through. It is never `absent` solely because of the
    revision.
  - If `f` is **2025-only**, `normalize-from-2025` copies it; `normalize-from-2026` sets it to
    `absent`. `denormalize-to-2026` MUST `(absent? f)` and **refuse** (raise) if a non-absent
    2025-only field is present on a value being emitted as 2026 (wire-parity: a 2026 message
    cannot carry a 2025-only field).
  - If `f` is **2026-only**, symmetric: `normalize-from-2026` copies it; `normalize-from-2025`
    sets it to `absent`; `denormalize-to-2025` refuses a non-absent 2026-only field.
  - The optional-field `absent` for "this revision HAS the field but the message OMITTED it" is
    the SAME sentinel as "this revision LACKS the field". They are indistinguishable at the value
    level — and that is correct for N1: a handler that reads `(façade-X-instructions v)` and gets
    `absent` treats it as "no instructions", whether because a 2026 discover-result omitted it or
    a 2025 revision lacked it. **Distinguishability, when needed, comes from the negotiated
    version tag, NOT from the field value** — see §Decisions "presence vs revision-capability".
- **Wire representation is unchanged.** The façade never touches JSON; objects remain immutable
  symbol-keyed `hasheq`, JSON null is `'null`, lists are lists. Those live in 003/004; the façade
  operates on already-parsed structs.
- **Public surface = explicit `(provide …)`** (never `all-defined-out`), mirroring the TS curated
  `core/public` boundary (architecture §1.3). This module IS the curated boundary for M1 types.

### How the façade decides per-field (the normalization seam)

```
              wire JSON (some revision R)
                       │  read-json  (json library; done by caller/transport)
                       ▼
        ┌──────────────────────────────┐
        │ R = 2025-11-25 ?              │ json->X        (spec-2025-11-25.rkt, item 003)
        │ R = 2026-07-28 ?             ─┤ json->X        (spec-2026-07-28.rkt, item 004)
        └──────────────┬───────────────┘
                       ▼  revision struct (003's X  OR  004's X)
        ┌──────────────────────────────┐
        │ normalize-X-from-2025  /      │   THIS MODULE (types.rkt)
        │ normalize-X-from-2026         │   shared fields copied; revision-only fields
        └──────────────┬───────────────┘   from the OTHER revision set to `absent`
                       ▼
            façade-X struct  ── the ONE shape handlers see ──►  protocol engine / client / server
                       │  denormalize-X-to-<negotiated-rev>
                       ▼   (refuses to emit a field absent from the target revision — N1 parity)
            revision struct ── X->json (003 or 004) ──► wire JSON
```

The negotiated revision is an explicit argument threaded from the protocol engine (S3); the
façade does not guess it. For S1 the demo (item 009) supplies it directly.

---

## Type inventory / façade surface (THE IMPLEMENTATION CONTRACT — enumerate ALL)

This is the analytical core. Each primitive below gets ONE façade struct = the union of 003's
and 004's fields for that primitive. The **Shared / 2025-only / 2026-only** split is derived
field-by-field from the two delivered modules' provided structs (`spec-2025-11-25.rkt` /
`spec-2026-07-28.rkt`) and cross-checked against `types.ts`. Field names are the SAME kebab-case
as 003/004 (so the façade field is the union of identically-named revision fields). Where a
primitive exists in only one revision, the façade still carries it (it is part of the superset);
normalizing a message of the OTHER revision can never produce it, and denormalizing it to the
other revision is refused.

> **Reading guide.** "Shared" = the field appears (same name, compatible shape) in BOTH
> revision structs → copied through by both normalizers. "2025-only"/"2026-only" = present in
> exactly one revision struct → `absent` after normalizing the other revision; refused on
> denormalize to the revision that lacks it.

### Group 0 — primitives shared verbatim (façade = pass-through; no per-field split needed)

These have **identical** shape in 003 and 004 (confirmed: items 003 §M/§N and 004 §P/§O list
them under "UNCHANGED in shape"). The façade re-exports ONE struct definition and normalization
is the identity on the struct (modulo the `meta`/`resultType` additions noted per-group). Because
the structs are shape-identical, the façade MAY alias them directly OR define a fresh façade
struct and copy fields — **Decision (recommended): define a fresh façade struct and copy**, so
the façade owns its public surface and 005 never leaks a 003/004 internal struct type to handlers
(architecture §1.3 boundary). The copy is mechanical.

| Façade struct | Shared fields | Notes |
|---|---|---|
| `facade-implementation` | `name`, `title`, `version`, `description`, `website-url`, `icons` | identical both revs |
| `facade-base-metadata` | `name`, `title` | identical |
| `facade-icon` | `src`, `mime-type`, `sizes`, `theme` | identical |
| `facade-annotations` | `audience`, `priority`, `last-modified` | identical |
| `facade-text-content` | type=`"text"`, `text`, `annotations`, `meta` | content block — identical |
| `facade-image-content` | type=`"image"`, `data`, `mime-type`, `annotations`, `meta` | identical |
| `facade-audio-content` | type=`"audio"`, `data`, `mime-type`, `annotations`, `meta` | identical |
| `facade-resource-link` | resource fields + type=`"resource_link"` | identical |
| `facade-embedded-resource` | type=`"resource"`, `resource`, `annotations`, `meta` | identical |
| `facade-tool-use-content` | type=`"tool_use"`, `id`, `name`, `input`, `meta` | identical |
| `facade-tool-result-content` | type=`"tool_result"`, `tool-use-id`, `content`, `structured-content`, `is-error`, `meta` | identical |
| `facade-prompt`, `facade-prompt-argument`, `facade-prompt-message` | per 003 §H / 004 §L | identical |
| `facade-resource`, `facade-resource-template` | per 003 §G / 004 §J | identical |
| `facade-text-resource-contents`, `facade-blob-resource-contents`, `facade-resource-contents` | identical | union dispatch on `text`/`blob` key |
| `facade-tool-annotations` | `title`, `read-only-hint`, `destructive-hint`, `idempotent-hint`, `open-world-hint` | identical |
| `facade-model-preferences`, `facade-model-hint`, `facade-tool-choice`, `facade-sampling-message` | per 003 §L / 004 §O | identical (sampling-message: `content` is block-or-list both revs) |
| `facade-root` | `uri`, `name`, `meta` | identical |
| the elicitation schema family: `facade-string-schema`, `facade-number-schema`, `facade-boolean-schema`, the 5 enum-schema arms + `facade-primitive-schema-definition/c` + `facade-enum-schema/c` | per 003 §P / 004 §P2 | identical primitive/enum schema shapes |
| the completion refs: `facade-resource-template-reference`, `facade-prompt-reference` | identical | |
| `facade-annotations`, scalar contracts `role/c`, `cursor/c`, `progress-token/c`, `request-id/c`, `logging-level/c` | identical enums | re-export ONE definition |

> The content-block union contracts `content-block/c` and `sampling-message-content-block/c`
> are also shared (same arms both revs). Re-export ONE façade union (`facade-content-block/c`).

### Group 1 — `Tool` (shape diverges: 2025 has `execution`)

| Field | In 2025? | In 2026? | Façade class |
|---|---|---|---|
| `name`, `title`, `description`, `input-schema`, `output-schema`, `annotations`, `icons`, `meta` | ✅ | ✅ | **shared** |
| `execution` (`ToolExecution`, `task-support`) | ✅ (003 §I) | ❌ (004 §M: "NO `execution`/`ToolExecution`") | **2025-only** |

`facade-tool` carries all shared fields + `execution` (façade-tool-execution or `absent`).
`normalize-from-2026` sets `execution` to `absent`; `denormalize-to-2026` refuses a non-absent
`execution`.

### Group 2 — `Result` base + the `resultType` / cacheable / `_meta` additions

The 2026 revision adds `result-type` to EVERY result and `ttl-ms`/`cache-scope` to list/read
results. These are **2026-only** façade fields.

| Façade primitive | Shared fields | 2026-only fields | 2025-only fields |
|---|---|---|---|
| `facade-result` (base) | `meta`, `rest` | `result-type` | — |
| `facade-list-tools-result` | `tools`, `next-cursor`, `meta`, `rest` | `result-type`, `ttl-ms`, `cache-scope` | — |
| `facade-list-resources-result` | `resources`, `next-cursor`, `meta`, `rest` | `result-type`, `ttl-ms`, `cache-scope` | — |
| `facade-list-resource-templates-result` | `resource-templates`, `next-cursor`, `meta`, `rest` | `result-type`, `ttl-ms`, `cache-scope` | — |
| `facade-list-prompts-result` | `prompts`, `next-cursor`, `meta`, `rest` | `result-type`, `ttl-ms`, `cache-scope` | — |
| `facade-read-resource-result` | `contents`, `meta`, `rest` | `result-type`, `ttl-ms`, `cache-scope` | — |
| `facade-call-tool-result` | `content`, `structured-content`, `is-error`, `meta`, `rest` | `result-type` | — |
| `facade-get-prompt-result` | `description`, `messages`, `meta`, `rest` | `result-type` | — |
| `facade-complete-result` | `completion`, `meta`, `rest` | `result-type` | — |
| `facade-create-message-result` | sampling-message fields + `model`, `stop-reason`, `meta`, `rest` | `result-type` | — |
| `facade-elicit-result` | `action`, `content`, `meta` | `result-type` (note: 004 §P2 — confirm if ElicitResult carries it) | — |

> `result-type` is OPTIONAL even within 2026 (004 Decisions "INTENTIONAL ASYMMETRY": absent ⇒
> "complete" for older servers). So in the façade `result-type` is `absent` for a 2025 message
> AND may be `absent` for a 2026 message. A handler MUST NOT infer the revision from
> `(absent? (facade-result-result-type v))` — see §Decisions "presence vs revision-capability".

### Group 3 — `ListRootsResult` (the BARE-interface trap — façade must respect it)

004 §O2 pins `ListRootsResult` as a **bare** interface: `{roots}` ONLY, NO `meta`/`result-type`/
`rest`. 003's `list-roots-result` carries `roots` + `meta`. So:

| Field | 2025? | 2026? | Façade class |
|---|---|---|---|
| `roots` | ✅ | ✅ | **shared** |
| `meta` (on the result) | ✅ (003 §O) | ❌ (004 §O2 BARE) | **2025-only** |

`facade-list-roots-result` carries `roots` + `meta` (or `absent`). `normalize-from-2026` sets
the result-level `meta` to `absent`. `denormalize-to-2026` refuses a non-absent result-level
`meta` and emits EXACTLY `{roots}` (per 004's bare-interface rule). Per-`root` `meta` is on
`facade-root` (Group 0) and is shared — do not confuse the two.

### Group 4 — request params with the `_meta` envelope (2026) vs flat `meta` (2025)

The headline N1 divergence. In 2025 each concrete request params struct has a named `meta`
field holding the `_meta` object (003 §C/§G/§I etc.). In 2026 each concrete request params
struct carries the **`request-meta` envelope struct** (004 §C) in its `meta` field — protocol
version, client info, client capabilities, log level, related-task, progress-token as NAMED
reserved keys, plus 2026 adds `input-responses`/`request-state` to read/get-prompt/tools-call
params (004 §F/§J/§L/§M).

**Façade decision (recommended):** the façade request-params structs carry a single
`request-meta` field whose value is a **`facade-request-meta`** struct (the superset envelope) +
the 2026-only `input-responses`/`request-state` where applicable. The `facade-request-meta`
unions: for a 2025 message, `protocol-version`/`client-info`/`client-capabilities`/`log-level`/
`related-task` are `absent` (2025 carries them via the `initialize` handshake, not `_meta`) and
its `rest` holds the flat 2025 `_meta` keys; `progress-token` is shared (both revs carry it,
003 via `RequestMetaSchema`, 004 as a reserved `_meta` key). For a 2026 message the named
reserved fields are populated.

| Façade params primitive | Shared | 2026-only | 2025-only |
|---|---|---|---|
| `facade-request-meta` | `progress-token`, `related-task` (003 rides it in `_meta`; 004 reserved key), `rest` | `protocol-version`, `client-info`, `client-capabilities`, `log-level` | (the flat 2025 `_meta` map lands in `rest`) |
| `facade-call-tool-request-params` | `name`, `arguments`, `request-meta` | `input-responses`, `request-state` | `task` (003 §I `task?`) |
| `facade-read-resource-request-params` | `uri`, `request-meta` | `input-responses`, `request-state` | — |
| `facade-get-prompt-request-params` | `name`, `arguments`, `request-meta` | `input-responses`, `request-state` | — |
| `facade-complete-request-params` | `ref`, `argument`, `context`, `request-meta` | — | — |
| `facade-create-message-request-params` | `messages`, `model-preferences`, `system-prompt`, `include-context`, `temperature`, `max-tokens`, `stop-sequences`, `metadata`, `tools`, `tool-choice` | — | `task` (003 §L `task?`) |
| `facade-elicit-request-form-params` / `-url-params` | `mode`, `message`, `requested-schema` / `elicitation-id`, `url` | — | `task` (003 §P `task?`) |
| `facade-set-level-request-params` | `level` | — | **whole primitive 2025-only** (see Group 6) |

### Group 5 — primitives present in BOTH revisions but with the `_meta`/`resultType` deltas

Requests/notifications whose method exists in both revisions; the façade unifies them. (Method
literals identical; params bodies differ only by the Group 4 `request-meta` and Group 2
`result-type` deltas already enumerated.)

- `facade-tools-call-request`, `facade-tools-list-request`, `facade-prompts-get-request`,
  `facade-prompts-list-request`, `facade-resources-list-request`,
  `facade-resources-templates-list-request`, `facade-resources-read-request`,
  `facade-completion-complete-request`, `facade-sampling-create-message-request`,
  `facade-roots-list-request`, `facade-elicitation-create-request`.
- Notifications in both: `facade-cancelled-notification`, `facade-progress-notification`,
  `facade-resources-list-changed-notification`, `facade-resources-updated-notification`,
  `facade-prompts-list-changed-notification`, `facade-tools-list-changed-notification`,
  `facade-logging-message-notification` (deprecated in 2026 but in-revision),
  `facade-elicitation-complete-notification`.
- Envelopes (identical both revs): `facade-jsonrpc-request`, `facade-jsonrpc-notification`,
  `facade-jsonrpc-result-response`, `facade-jsonrpc-error-response`, `facade-jsonrpc-error`.

### Group 6 — 2025-ONLY primitives (in the superset; never produced by a 2026 message)

From 003 §C/§D/§J/§K + 004 §Diff "REMOVED in 2026":

- `facade-initialize-request` (+params), `facade-initialize-result`,
  `facade-initialized-notification` (replaced in 2026 by the `_meta` envelope + `server/discover`).
- `facade-ping-request`.
- `facade-set-level-request` (+params) — `logging/setLevel` (replaced by `_meta` logLevel key).
- the entire **tasks** family: `facade-get-task-request`/`-result`,
  `facade-get-task-payload-request`/`-result`, `facade-cancel-task-request`/`-result`,
  `facade-list-tasks-request`/`-result`, `facade-create-task-result`, `facade-task`,
  `facade-task-metadata`, `facade-task-status-notification` (+params), `facade-tool-execution`.
- `facade-subscribe-request`/`facade-unsubscribe-request` (+params) — `resources/subscribe`/
  `unsubscribe` (replaced by `subscriptions/listen`).
- `facade-resources-updated`... (shared — listed in Group 5; NOT 2025-only),
  `facade-roots-list-changed-notification`, `facade-tasks-status-notification`.
- `facade-url-elicitation-required-error` (code `-32042`).

`denormalize-*-to-2026` for any of these is **refused** (the primitive cannot exist on a 2026
wire). Normalizing a 2026 message can never produce them.

### Group 7 — 2026-ONLY primitives (in the superset; never produced by a 2025 message)

From 004 §E/§F/§I/§K/§R + §Diff "ADDED in 2026":

- `facade-discover-request`, `facade-discover-result` (`server/discover`).
- `facade-subscriptions-listen-request` (+params), `facade-subscription-filter`,
  `facade-subscriptions-acknowledged-notification` (+params).
- the **Input / multi-round-trip** family: `facade-input-request/c`, `facade-input-response/c`,
  `facade-input-requests/c`, `facade-input-responses/c`, `facade-input-required-result`.
- `facade-cacheable` fields (`ttl-ms`, `cache-scope`) — modeled as the 2026-only fields on the
  list/read façade results (Group 2), not a standalone struct.
- the typed errors: `parse-error?`…`internal-error?` predicates (code-pinned, over
  `facade-jsonrpc-error`), `make-unsupported-protocol-version-error`/predicate (`-32004`),
  `make-missing-required-client-capability-error`/predicate (`-32003`).
- the `request-meta` reserved fields (`protocol-version`/`client-info`/`client-capabilities`/
  `log-level`) — modeled as the 2026-only fields on `facade-request-meta` (Group 4).
- `result-type` — modeled as the 2026-only field on every façade result (Group 2).

`denormalize-*-to-2025` for any standalone 2026-only primitive is **refused**; the 2026-only
*fields* on shared façade structs are refused on `denormalize-to-2025` if non-absent.

### Group 8 — aggregate union contracts + the protocol type maps (mirrors `types.ts`)

`types.ts` (lines 377–416) exposes `ClientRequest`/`ServerRequest`/`ClientNotification`/… unions
AND the `RequestTypeMap`/`NotificationTypeMap`/`ResultTypeMap` method→type maps. The façade
provides the **superset** unions (union of 003's and 004's arms — e.g. `facade-client-request/c`
includes BOTH `initialize`/`ping`/tasks (2025) AND `server/discover`/`subscriptions/listen`
(2026)) and a method→façade-struct dispatch table so the protocol engine can route by method
without knowing the revision:

- `facade-client-request/c`, `facade-server-request/c`, `facade-client-notification/c`,
  `facade-server-notification/c`, `facade-client-result/c`, `facade-server-result/c`,
  `facade-jsonrpc-message/c`.
- `facade-request-method->struct` / `facade-notification-method->struct` (hash or
  `case`-dispatch from a method string to the façade struct's `json->`/`normalize` pair) — the
  Racket analogue of `RequestTypeMap`. **Decision (recommended):** model as a
  `(hash method-string . (cons revision-aware-parser normalizer))` or a dispatch function; keep
  it data-driven so S3's engine reuses it.

> **Counts to report (test prints exact):** façade structs ≈ **the union of 003's ~70 and
> 004's ~55–60 primitives, deduplicated on shared shapes** → expect **~75–85 façade structs**
> (shared primitives counted once; 2025-only + 2026-only added). Record the exact count in
> Validation Results. The normalizer/denormalizer pair count is roughly 2 × (primitives present
> in each revision).

---

## Acceptance criteria

- [ ] `mcp/core/types/types.rkt` exists as `#lang racket/base` with `(require racket/contract)`,
      `(require (prefix-in r25: "spec-2025-11-25.rkt"))` and
      `(require (prefix-in r26: "spec-2026-07-28.rkt"))` (prefix to disambiguate the
      identically-named revision structs), and an explicit curated `(provide …)` (no
      `all-defined-out`).
- [ ] **The shared `absent` sentinel is imported from ONE place and re-exported** (`absent`,
      `absent?`, `present?`) — the SAME `eq?` binding 003/004 use, so `(absent? façade-field)` is
      the field-presence test across the whole stack.
- [ ] **Every primitive in §4 (Groups 0–8) has a façade struct** (or, for unions/scalars, a
      façade `…/c`), transparent (`#:transparent`), with a predicate and a flat `…/c` contract.
- [ ] **`normalize-X-from-2025` / `normalize-X-from-2026`** exist for every primitive present in
      that revision, producing the façade struct: shared fields copied through; revision-only
      fields from the OTHER revision set to `absent`. (A 2025-only primitive has only a
      `…-from-2025`; a 2026-only primitive only a `…-from-2026`.)
- [ ] **`denormalize-X-to-2025` / `denormalize-X-to-2026`** exist, producing the corresponding
      003/004 revision struct, and **RAISE** (refuse) when asked to emit a field/primitive absent
      from the target revision while it is present (non-`absent`) on the façade value — the N1
      wire-parity rule (architecture line 326).
- [ ] **THE QUEUE'S CORE TESTABLE CLAIM:** a `2025-11-25` message and a `2026-07-28` message of
      the same primitive both normalize into the **same façade struct type**, with the correct
      fields present/absent — for at least `tools/call` request, `tools/list` result, and a
      content block:
      - RC-only fields (`result-type`, `ttl-ms`, `cache-scope`, the `request-meta` reserved
        keys, `input-responses`) are **`absent`** on the façade of the **2025** message and
        **present** on the façade of the **2026** message.
      - 2025-only fields (`task` on `call-tool` params, `execution` on `tool`, result-level
        `meta` on `list-roots-result`) are **`absent`** on the façade of the **2026** message and
        **present** on the façade of the **2025** message.
- [ ] **Round-trip through the façade is lossless per revision:** for each revision R and a
      representative primitive, `(denormalize-X-to-R (normalize-X-from-R (json->X fixtureR)))`
      equals the R revision struct (and re-serializing yields `jsexpr=?` to the fixture). I.e. the
      façade adds no drift on the home revision.
- [ ] **Cross-revision refusal:** `(denormalize-X-to-2026 façade-with-a-2025-only-field-set)`
      raises; `(denormalize-X-to-2025 façade-with-a-2026-only-field-set)` raises. A façade value
      with all revision-only fields `absent` denormalizes to EITHER revision without raising.
- [ ] **Aggregate unions + method dispatch:** `facade-client-request/c` etc. accept the superset
      of arms; the method→façade dispatch resolves `"server/discover"` and `"initialize"` and
      `"tools/call"` to the right façade primitive.
- [ ] **`raco test mcp/core/types/` passes (exit 0)** from repo root — façade module + test
      compile and load cleanly alongside 001/002/003/004. (See Testing Prerequisites for the
      `raco`-is-broken workaround in THIS environment.)
- [ ] **Portability (NFR):** requires only `racket/base`, `racket/contract`, `spec-2025-11-25.rkt`,
      `spec-2026-07-28.rkt` (which transitively need only `constants.rkt` + `json` conventions). No
      subprocess/socket; no I/O at module load.
- [ ] **Public-surface discipline:** `types.rkt`'s `(provide …)` is the M1 public types boundary
      (item 008's barrel re-exports it). It does NOT leak 003/004's internal struct *types* to
      handlers (the façade owns its public structs); it MAY re-export the shared scalar contracts
      and `absent`. A comment documents which symbols are the public handler-facing surface.
- [ ] **Parity-matrix discipline:** progress.md Stage S1 `types.rkt` deliverable line flips
      📋 → ✅ and the `core/types/*` parity row is advanced toward `partial` per the Completion
      Reminder; sibling rows (003/004/constants/guards) untouched.

---

## Implementation steps

1. **Confirm inputs are green:** `mcp/core/types/spec-2025-11-25.rkt` and `spec-2026-07-28.rkt`
   load and their tests pass (run them directly per the `raco`-broken workaround). Re-read their
   `(provide …)` blocks — those exact struct/accessor/`…/c` names are the façade's raw material.
2. **Build the §4 inventory concretely:** for each primitive, list 003's struct fields and 004's
   struct fields side-by-side (the provide blocks + the struct definitions are the source).
   Classify each field shared / 2025-only / 2026-only. THIS is the contract; do not skip it.
3. **Write `mcp/core/types/types.rkt`**, `#lang racket/base`, requiring `racket/contract` and the
   two spec modules with `prefix-in` (`r25:` / `r26:`), and `(only-in "spec-2025-11-25.rkt"
   absent absent? present?)`. Section-comment the file by §4 group.
4. **Define a small façade-helper kit** (internal, not provided): `(copy-opt v)` (identity, but
   documents intent), `(from-2026-only v)` / `(from-2025-only v)` (return `absent` — the OTHER
   revision lacks the field), and a `refuse-if-present` guard used by denormalizers
   (`(when (present? v) (error 'denormalize "field X absent from revision Y"))`).
5. **Group 0 first** (shape-shared primitives): define each `facade-X` struct + `facade-X/c` +
   `normalize-facade-X-from-2025`/`-from-2026` (mechanical field copy) +
   `denormalize-facade-X-to-2025`/`-to-2026`. Establish the per-primitive 4-function pattern here.
6. **Groups 1–5** (diverging shared primitives): same pattern, but the normalizers set the
   revision-only fields to `absent` from the lacking side, and the denormalizers `refuse-if-present`.
7. **Groups 6–7** (single-revision primitives): one normalizer + one denormalizer each; the
   missing-direction denormalizer raises unconditionally ("primitive X does not exist in revision Y").
8. **Group 8** (unions + method dispatch): define the superset `…/c` unions and the
   method→façade dispatch table (data-driven). Reference the façade predicates.
9. **Curated `(provide …)`:** façade structs (`struct-out`) + predicates + `…/c` + the
   normalize/denormalize functions per primitive + the unions + the dispatch table + re-export
   `absent`/`absent?`/`present?` and the shared scalar contracts. NO `all-defined-out`.
10. **Author the test** `mcp/core/types/test/types-test.rkt` (see Testing). Reuse 003/004's
    `jsexpr=?` comparator (copy it into the test — it is test-local in 003/004). Drive fixtures
    from the EXISTING `fixtures/` (003's unprefixed + 004's `2026-` prefixed) — no new fixtures
    needed for the core claim, but add a couple of cross-revision pairs if a primitive lacks both.
11. **Run** the test directly (`racket mcp/core/types/test/types-test.rkt` — see workaround).
    Likely failures: a 2026-only field not set to `absent` by `normalize-from-2025`; a denormalizer
    not refusing; a `prefix-in` collision; a shared field whose 003/004 shape differs subtly.
12. **Update progress.md + parity matrix** (Completion Reminder).

---

## Testing strategy

**Test file:** `mcp/core/types/test/types-test.rkt` (`#lang racket/base`, `require rackunit`,
`json`, `racket/runtime-path` for fixture paths, the façade module, and BOTH spec modules with
`prefix-in` to build inputs). **Copy 003/004's `jsexpr=?` comparator** (unordered object keys;
lists in order; numbers by `=`; `'null` by `eq?`; NOT raw bytes). Six parts.

### Part 1 — the queue's core claim: both revisions normalize to the SAME façade (per primitive)

For each cross-revision primitive pair (at minimum `tools/call` request, `tools/list` result, a
content block):
1. `(define f25 (normalize-X-from-2025 (r25:json->X (read-fx "<2025-fixture>.json"))))`.
2. `(define f26 (normalize-X-from-2026 (r26:json->X (read-fx "2026-<fixture>.json"))))`.
3. Assert `(facade-X? f25)` AND `(facade-X? f26)` — **same struct type**.
4. **Present/absent assertions (the testable clause):**
   - On `f25`: each RC-only field is `(absent? …)` (`result-type`, `ttl-ms`, `cache-scope`,
     `request-meta` reserved fields, `input-responses`).
   - On `f26`: each RC-only field is `(present? …)`.
   - On `f26`: each 2025-only field is `(absent? …)` (`task`, `tool` `execution`,
     `list-roots-result` result-level `meta`).
   - On `f25`: each 2025-only field is `(present? …)` where the fixture set it.
5. Assert the **shared** fields are equal on both façades where the fixtures share a value (e.g.
   the tool `name`).

### Part 2 — façade is lossless on the home revision (no drift)

For each revision R and a representative primitive:
`(jsexpr=? (read-fx F_R) (r{R}:X->json (denormalize-X-to-R (normalize-X-from-R (r{R}:json->X (read-fx F_R))))))`.
Round-trip through the façade and back to the home revision is byte-semantically identical.

### Part 3 — cross-revision refusal (the N1 wire-parity rule)

- A façade `call-tool-request-params` with `task` (2025-only) present →
  `(check-exn exn:fail? (λ () (denormalize-call-tool-request-params-to-2026 it)))`.
- A façade `list-tools-result` with `result-type`/`ttl-ms`/`cache-scope` (2026-only) present →
  `denormalize-…-to-2025` raises.
- A façade `tool` with `execution` present → `denormalize-tool-to-2026` raises.
- A façade `list-roots-result` with result-level `meta` present → `denormalize-…-to-2026` raises
  (and a denormalize-to-2026 with `meta` absent emits EXACTLY `{roots}`).
- A 2025-only standalone primitive (`facade-initialize-request`) has NO `denormalize-…-to-2026`
  (or it raises unconditionally); symmetric for `facade-discover-request` to 2025.
- **Symmetric pass:** a façade value with ALL revision-only fields `absent` denormalizes to BOTH
  revisions without raising.

### Part 4 — aggregate unions + method dispatch

- `(facade-client-request/c)` accepts a normalized `initialize` (2025) AND a normalized
  `server/discover` (2026) AND a normalized `tools/call` (either rev).
- The method→façade dispatch resolves `"initialize"`, `"server/discover"`, `"tools/call"`,
  `"subscriptions/listen"`, `"ping"` to the expected façade primitive (or, for the dispatch that
  needs a revision, the right `(parser . normalizer)` pair).
- `facade-jsonrpc-message/c` accepts a request / notification / response façade value.

### Part 5 — presence-vs-revision-capability (the subtle correctness case)

Document and test the §Decisions point: a 2026 `tools/list` result that legitimately OMITS
`result-type` (absent ⇒ "complete", per 004's asymmetry) normalizes to a façade with
`(absent? result-type)` — the SAME as a 2025 message. Assert that the façade does NOT crash and
does NOT claim the message was 2025. (The negotiated-version tag, not the field value, carries
revision identity — assert the test threads the revision explicitly and the façade respects it.)

### Part 6 — inventory / count report (anti-vacuous)

Print and assert: the number of façade structs, the number of `normalize-*`/`denormalize-*`
pairs, and that every primitive listed in §4 Groups 0–8 has a provided façade `…/c` (introspect
the provided contracts). Record the exact counts in Validation Results so a future drift (a
primitive silently dropped from the union) fails the count assertion.

### Edge cases the test must cover (do not leave implicit)

- **`absent` identity:** the façade's `absent` is `eq?` to 003's and 004's `absent` (import test).
- **Optional-absent vs revision-absent are the same sentinel** — assert a 2026 message that omits
  an OPTIONAL shared field (e.g. `tool.title`) yields `absent`, identical to how a revision-only
  field reads; this is intentional (Part 5).
- **`result-type` open-enum:** a non-standard `result-type` string ("input_required" or a custom
  string) survives normalize→denormalize on 2026.
- **Shared content-block union:** each of the 5 content-block arms normalizes from both revisions
  to the same façade arm and dispatches correctly via `facade-content-block/c`.
- **`request-meta` superset:** a 2026 `request-meta` with all 5 reserved keys normalizes to a
  `facade-request-meta` with each named field `present?`; a 2025 params `meta` normalizes to a
  `facade-request-meta` with the reserved fields `absent` and the flat `_meta` keys in `rest`;
  `progress-token` (shared) survives from both.
- **No phantom keys:** denormalizing a façade value to its home revision and re-serializing does
  not introduce a key the original fixture lacked (reuse 003's absent-vs-null regression check).

---

## Dependencies

- **Upstream work items:** **item 003** (`spec-2025-11-25.rkt`) and **item 004**
  (`spec-2026-07-28.rkt`) — the two delivered revision modules this item UNIONs; their provided
  structs/contracts/`json->`/`->json` and the shared `absent` sentinel are the raw material. Both
  must be green. Transitively **item 001** (`constants.rkt`) and **item 002** (`guards.rkt`)
  conventions (via 003/004). No NEW edit to constants.rkt is required by this item.
- **Operates on:** already-parsed 003/004 revision structs → façade structs, and back. No
  file/network I/O at module load; the test reads fixture files.
- **Downstream consumers (informational):** **item 008** (the `core/types` barrels re-export this
  module's curated `provide` — this IS the M1 public surface); **item 009** (the S1 demo parses an
  `initialize`/`tools/call` (2025) and a `server/discover`/`tools/call` (2026) and observes the
  SAME façade structs); every S2+ layer (protocol engine S3, client/server) consumes ONLY the
  façade, never 003/004 directly (architecture N1).
- **Tooling/runtime:** Racket ≥ 8.x (v9.1 installed; `raco` at `/snap/bin/raco` — **but broken in
  this environment, see Testing Prerequisites**); `rackunit`; the `typescript-sdk/` checkout (read
  by the implementer to cross-check `types.ts`; the test reads only local fixtures).

---

## Project-specific adaptations (Racket / contracts / rackunit)

This is a **pure-data normalization module** — façade structs + flat contracts + per-primitive
normalize/denormalize functions, no external services, no I/O at module load. Adaptations
(identical spirit to 003/004):

- **Language:** `#lang racket/base` + `racket/contract`. Minimal `require`s (Portability NFR).
- **Structs not classes (G4):** transparent façade `struct`s; TS's static `Infer<>` union becomes
  concrete façade structs + normalizers.
- **`prefix-in` for the two revision modules** (`r25:`/`r26:`) — their structs share names, so a
  bare `require` of both collides. This is the key build mechanic of this item.
- **Flat contracts:** `struct/c` / `flat-named-contract` / `(or/c …)` for the façade types and the
  superset unions; the truth is the union of 003/004's contracts.
- **Naming:** `facade-` prefix on the public façade structs to keep them distinct from 003/004's
  bare names (avoid leaking the impression a façade struct IS a revision struct); `normalize-…`/
  `denormalize-…` for the seam; predicates `?`; contracts `/c`. (Final prefix choice recorded in
  Decisions — `facade-` is the recommendation; a shorter prefix is acceptable if consistent.)
- **Public surface:** explicit `(provide …)` — never `all-defined-out`. Internal helpers not
  provided (except the re-exported `absent` sentinel + shared scalar contracts).
- **No services / no I/O:** only file access is the test reading hand-authored fixtures.

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None.** No I/O at module load, no service contacted. External artifacts:

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime (v9.1 installed) | compile + run module/tests; `raco` at `/snap/bin/raco` (**broken — see below**) | system install (`racket --version` ≥ 8.0) | n/a |
| Item 003 `spec-2025-11-25.rkt` | the 2025 revision structs + `absent` sentinel + `json->`/`->json` | item 003 (delivered ✅) | n/a |
| Item 004 `spec-2026-07-28.rkt` | the 2026 revision structs + `json->`/`->json` (re-exports `absent`) | item 004 (delivered ✅) | n/a |
| `typescript-sdk/` checkout | implementer reads `types.ts` (public-surface reference) | already present at repo root | n/a |
| Existing JSON fixtures | `mcp/core/types/test/fixtures/*.json` (003 unprefixed) + `2026-*.json` (004) | already authored by 003/004 | n/a |

No databases, queues, HTTP servers, or network deps. (Harmless `/home/rev/.bash_env: Permission
denied` on stderr — ignore.)

### Environment Configuration

- **Environment variables / secrets / config files:** none.
- **Ports:** none must be free.
- **Working directory:** run tests from the **repo root**
  (`/home/rev/Linux/Projects/racket_mcp`) so the `mcp/...` collection resolves; the test anchors
  fixture paths via `define-runtime-path` so they resolve regardless of cwd.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0.
  - `test -f mcp/core/types/spec-2025-11-25.rkt && test -f mcp/core/types/spec-2026-07-28.rkt` →
    items 003/004 present.
  - `test -d mcp/core/types/test/fixtures` → fixtures present (both 003's and 004's).

### Manual Validation Checklist

- [ ] **`raco` IS BROKEN IN THIS ENVIRONMENT — DO NOT RELY ON `raco test`.** The snap `raco`
      wrapper silently exits 1 (no useful output) in this sandbox. **Run tests instead with
      sandboxed `racket <test-file.rkt>` directly:** the rackunit `check-*` forms run at module
      top level, so a direct file run executes every check; **silence (exit 0, no FAILURE/ERROR
      lines) = pass.** Use, from repo root:
      `racket mcp/core/types/test/types-test.rkt` (a non-zero exit or any `FAILURE`/`check-*`
      failure line = a real failure). Document this so the implementer does not get stuck thinking
      the tests "don't run."
- [ ] **Build/compile (best-effort):** `racket -e '(require (file "mcp/core/types/types.rkt"))'`
      from repo root succeeds (module loads). (`raco make` may also fail via the broken wrapper —
      module load via `racket -e` is the reliable check.)
- [ ] **Module loads in isolation:** the `require` above returns without error.
- [ ] **Tests pass:** `racket mcp/core/types/test/types-test.rkt` → exit 0, no failure lines.
- [ ] **Collection tests pass:** run each test file directly
      (`racket mcp/core/types/test/spec-2025-11-25-test.rkt`,
      `racket mcp/core/types/test/spec-2026-07-28-test.rkt`,
      `racket mcp/core/types/test/types-test.rkt`, plus constants/guards) → all exit 0. (The
      collection `raco test` gate is the nominal acceptance criterion; in this environment it is
      satisfied by the per-file `racket` runs.)
- [ ] **Services started:** N/A.
- [ ] **Application runs:** N/A (library; "running" = require + REPL inspect).
- [ ] **Same-façade verified (REPL):** normalize a 2025 `tools/call` and a 2026 `tools/call`;
      confirm both satisfy `facade-call-tool-request?` and the RC-only fields differ in presence.
- [ ] **Refusal verified (REPL):** `denormalize-…-to-2026` of a façade carrying a 2025-only field
      raises; with the field `absent` it succeeds.
- [ ] **Lossless-on-home-revision verified (REPL):** a 2026 `list-tools-result` round-trips
      `jsexpr=?` through normalize→denormalize-to-2026→`->json`.
- [ ] **`absent` identity verified (REPL):** the façade's `absent` is `eq?` to 003's `absent`.
- [ ] **Drift detection:** flip one present/absent assertion (or drop a primitive from the §4
      provide) and confirm the test FAILS; revert.
- [ ] **Health checks pass:** N/A.

### Expected Outcomes

The module MUST export façade structs + contracts + normalize/denormalize seams for **every**
primitive in §4 (Groups 0–8). The test reports a concrete **inventory + counts**:

- **Façade structs:** ≈ **75–85** (union of 003's ~70 and 004's ~55–60, deduplicated on the
  shape-shared Group-0 primitives; plus 2025-only and 2026-only primitives). Exact count printed
  by the test and recorded in Validation Results.
- **Normalize functions:** ≈ 2 × (primitives present per revision) — one `…-from-2025` per
  primitive that 2025 has, one `…-from-2026` per primitive that 2026 has.
- **Denormalize functions:** symmetric (`…-to-2025` / `…-to-2026`), with the cross-revision ones
  refusing.
- **Aggregate union contracts:** 7 superset unions (`facade-client-request/c`,
  `facade-server-request/c`, `facade-client-notification/c`, `facade-server-notification/c`,
  `facade-client-result/c`, `facade-server-result/c`, `facade-jsonrpc-message/c`) + the
  method→façade dispatch table(s).
- **Re-exported:** `absent`/`absent?`/`present?` (shared sentinel) + the shared scalar contracts
  (`role/c`, `cursor/c`, `progress-token/c`, `request-id/c`, `logging-level/c`).

**Test outcome:** all per-file `racket` test runs → 0 failures, 0 errors. Same-façade checks ≥ 3
primitives × (both-types + present/absent matrix); lossless-on-home checks ≥ 4 (2025 + 2026 ×
request + result); refusal checks ≥ 5; union/dispatch checks ≥ 3; count assertions ≥ 1.

**Total public bindings provided:** the façade structs (~75–85) × (struct + predicate + `…/c`) +
the normalize/denormalize pairs + 7 union contracts + the dispatch table + the re-exported
sentinel/scalars. (Exact count recorded during implementation.)

### Validation Results

```markdown
## Validation Results (to be filled during execute-item)
- [ ] Service started: N/A (pure-data normalization module)
- [ ] Application started: N/A (library; `require` succeeds)
- [ ] Build verified: `racket -e '(require (file ".../types.rkt"))'` succeeds (raco wrapper broken)
- [ ] Module load verified: require returns without error
- [ ] Tests verified: `racket mcp/core/types/test/types-test.rkt` → exit 0, N checks passed (0 fail/err)
- [ ] Collection tests verified: each test file run directly → all exit 0 (001/002/003/004/005)
- [ ] Inventory verified: every primitive in §4 Groups 0–8 has a façade struct/`…/c` +
      normalize/denormalize seam. Façade struct count recorded: ___.
- [ ] SAME-FAÇADE verified (the queue's core claim): 2025 + 2026 `tools/call`, `tools/list`
      result, content block all normalize to the SAME façade struct type
- [ ] PRESENT/ABSENT matrix verified: RC-only fields absent on 2025 façade, present on 2026;
      2025-only fields (task/execution/list-roots meta) absent on 2026 façade, present on 2025
- [ ] Lossless-on-home verified: normalize→denormalize-to-R→->json is jsexpr=? to the fixture
      for 2025 + 2026 × request + result
- [ ] Cross-revision refusal verified: denormalize-to-2026 of a 2025-only-field-bearing façade
      raises; denormalize-to-2025 of a 2026-only-field-bearing façade raises; all-absent denorms
      to both without raising
- [ ] Aggregate unions verified: facade-client-request/c accepts initialize(2025) + discover(2026)
      + tools/call; method→façade dispatch resolves initialize/server/discover/tools/call
- [ ] Presence-vs-revision-capability verified: a 2026 result omitting result-type normalizes to
      absent (same as 2025) without crash; revision identity carried by the version tag, not the field
- [ ] `absent` identity verified: façade absent eq? to 003's/004's absent
- [ ] N1-readiness / boundary verified: façade owns its public structs; does not leak 003/004
      internal struct types to handlers; absent + shared scalars re-exported
- [ ] Drift detection: dropped a §4 primitive from provide / flipped a present/absent assertion →
      test fails; reverted → all pass
- [ ] Database tables verified: N/A
- [ ] API endpoints verified: N/A
- [ ] Screenshots captured: N/A (no UI)
```

---

## Decisions & Trade-offs

**To be updated during implementation.** Genuine N1 design decisions this item must make (with
recommended defaults — settle and record each during execute-item):

- **A primitive absent entirely from one revision (Groups 6/7).** *Recommended:* the primitive
  STILL gets a façade struct (it is part of the superset the handler API exposes), with ONE
  normalizer (from its home revision) and ONE working denormalizer (to its home revision); the
  cross-revision denormalizer either does not exist or raises unconditionally ("primitive X does
  not exist in revision Y"). Rationale: the superset is the handler's whole vocabulary; refusing
  at the wire boundary (not omitting from the API) is the N1 contract (architecture line 326).
- **Per-primitive façade structs vs one mega-struct.** *Recommended:* per-primitive façade
  structs (mirrors 003/004's per-primitive surface and `types.ts`'s per-type exports). A single
  mega-struct with a `kind` tag would force every consumer to re-dispatch and would lose
  contract-level field guarantees. Per-primitive keeps the façade `…/c` contracts meaningful.
- **`resultType` / `_meta` / `CacheableResult` / `InputRequired` — all 2026-only — in the unified
  shape.** *Recommended:* model each as a NAMED 2026-only field on the relevant façade struct
  (`result-type` on every façade result; `ttl-ms`/`cache-scope` on list/read results; the five
  `request-meta` reserved fields on `facade-request-meta`; `input-responses`/`request-state` on
  the read/get-prompt/tools-call params; `facade-input-required-result` as its own 2026-only
  result primitive). `absent` on a 2025-normalized value; populated on a 2026-normalized one.
  Refused on denormalize-to-2025 if present.
- **2025-only `tasks/*` and `-32042`.** *Recommended:* full façade structs for the tasks family
  and `facade-url-elicitation-required-error` (2025-only, Group 6); normalize only from 2025;
  refuse denormalize to 2026. The S1 decode path for `-32042` (progress.md S1 acceptance) is the
  errors module (item 006/007); the façade just carries the type.
- **presence-vs-revision-capability (THE subtle one — record so it is not read as a bug).** A
  field reading `absent` on a façade value is **ambiguous** between "this revision lacks the
  field" and "this revision has it but the message omitted it" (e.g. `result-type` is optional
  even in 2026). This is **intentional and correct for N1:** handlers treat `absent` uniformly as
  "no value". Revision identity is carried by the **negotiated-version tag** threaded from the
  protocol engine, NOT inferred from any field value. The façade therefore takes the revision as
  an explicit argument to normalize/denormalize and never sniffs it. Document this prominently.
- **`prefix-in` (`r25:`/`r26:`) vs a single import.** *Recommended:* `prefix-in` — the two spec
  modules share struct names, so a bare double-require collides. Record the prefix choice.
- **`facade-` name prefix vs aliasing 003/004 structs.** *Recommended:* fresh `facade-` structs
  (own the public boundary; don't leak revision internals). Accept a shorter prefix if applied
  consistently and documented.
- **Where the negotiated version comes from.** *Recommended:* an explicit argument to the
  denormalizers (and, where a method maps to different params bodies, to the dispatch). The
  façade does not own version negotiation (that is S3's protocol engine). For the S1 test/demo,
  pass it directly.
- **Aliasing the shape-shared Group-0 structs vs copying.** *Recommended:* define fresh façade
  structs and copy fields (boundary cleanliness) even though aliasing 003's struct would be less
  code. Record if the implementer chooses aliasing for the truly-identical primitives to cut bulk
  — acceptable as long as the façade still owns the provided name.

---

## Completion Reminder

On completion, the implementer MUST:

1. **Update `docs/aide/progress.md` — the `types.rkt` deliverable row.** Stage S1 Deliverables
   line currently reads `📋 mcp/core/types/types.rkt — public types + N1 normalized-superset
   façade`. Advance it 📋 → 🚧 (when starting) → ✅ (when delivered and acceptance criteria pass).
   Do NOT touch the sibling rows (`constants.rkt`, `spec-2025-11-25.rkt`, `spec-2026-07-28.rkt`,
   `guards.rkt` — all ✅; `errors.rkt`, the barrels, the test dir — owned by other items). Never
   revert an icon backward.
2. **Touch the parity-matrix rows** per Stage S1 discipline (roadmap "Parity discipline applies
   to every stage"): advance the roadmap §9 / progress row for `core/types/*` toward `partial`
   — the façade existing + cross-revision-normalization-tested is a key part of the S1 `partial`
   claim. Per item 009 the broader `core/types/*` flip to `partial` is the S1 closeout's job —
   record only that the `types.rkt` façade sub-row is satisfied; do not prematurely flip sibling
   rows (errors, barrels) or the Stage-S1 acceptance boxes owned by other items.
3. Leave the sibling S1 deliverables (`errors.rkt`, `main.rkt` barrels, `errors-test.rkt`) at
   their current status — this item delivers only `types.rkt` (+ its test).
4. Do NOT check Stage-S1 acceptance boxes owned by other items (error encode/decode, the
   restricted-namespace load test, the demo). Only the `types.rkt` façade deliverable line and
   the `core/types/*` `partial` progression are this item's to touch.
