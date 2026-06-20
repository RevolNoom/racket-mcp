# Development Roadmap: `racket-mcp`

> **Status:** Living roadmap. Iteration 002.
> **Source vision:** `docs/aide/vision.md`.
> **Source architecture:** `docs/aide/architecture.md` (modules M1–M17, layers L0–L4).
> **Reference impl:** MCP TypeScript SDK v2 (`typescript-sdk/`).
> **Target spec revisions:** `2025-11-25`, `2026-07-28`.
> **Last updated:** 2026-06-15.

---

## How to read this roadmap

The roadmap delivers `racket-mcp` in **ten stages** (S6 and S7 are each split into two independently-shippable halves). Each stage:

- builds **only** on lower architecture layers already delivered (dependency direction in architecture §3.1 is never violated — lower layers never import higher ones);
- ends in a **demonstrable artifact** (a `racket`-runnable script, a `raco test` target, or a cross-SDK interop run) that can be shown and tested;
- carries **explicit acceptance criteria** that map to vision Goals (G1–G8) and Success Criteria (§9);
- is sized to be **deployable locally in roughly one week**, assuming most implementation is done by an AI agent with the TS reference checkout as ground truth.

Stage numbering follows the layer build-up: **S1–S2** establish L0 foundation, **S3** the L1 transport port + in-memory adapter, **S4** the L2 protocol engine, **S5** the L3 roles (minimum viable client+server) proven by Racket-only interop, **S6a** the real transports and **S6b** the high-level server (both build on S5; both land before S7), **S7a** the client-driven primitives and **S7b** the server session-state primitives, **S8** auth, **S9** examples/docs/conformance closeout.

**Parity discipline (applies to every stage).** Each stage updates the §9 parity matrix rows it touches (`done / partial / intentionally-excluded`) and ports the corresponding TS tests where they exist. The TS checkout at `typescript-sdk/` is authoritative for any wire ambiguity.

---

## Dependency graph (stage level)

```
S1 (types/errors L0) ──> S2 (validators/schema/shared utils L0)
        │                         │
        └───────────┬─────────────┘
                    v
            S3 (transport port + in-memory L1)
                    │
                    v
            S4 (protocol engine L2)
                    │
                    v
            S5 (Client + low-level Server, Racket-only in-memory interop)
                    │
        ┌───────────┴───────────────┐
        v                           v
   S6a (stdio M7 +            S6b (high-level McpServer M12b
   streamable-HTTP M8 +            + completable M12c)
   web-server M9)                  [L3]
   [L1] ◀── first cross-SDK leg     │
        │                           │
        └─────────────┬─────────────┘   (both need S5; both land before S7)
                      v
        ┌─────────────┴─────────────┐
        v                           v
   S7a (client-driven:         S7b (server session-state:
   sampling, elicitation,           subscription table + J1 fan-out,
   roots, client cursor-            S3 logging filter,
   following)                       progress/cancel role surfaces,
   [M13]                            server-raised -32042)  [M12b]
        │                           │
        └─────────────┬─────────────┘
                      v
   S8 (OAuth client + server bearer verification)
       ◀── needs S4 handler-context + S6a M8 bearer seam (NOT S7)
                      │
                      v
   S9 (examples, Scribble docs, full conformance + Inspector/TS interop closeout)
```

**Parallelism after S5.** `S6a` (transports, L1 — depends only on the M6 port from S3 + M5e framing from S2) and `S6b` (high-level server, L3 — depends on M12a from S5 + M3/M4/M5 from S2) touch disjoint modules and may proceed in parallel by two agents. Both must land before S7. Likewise `S7a` (client-only verbs/hooks) and `S7b` (server session-state) touch disjoint role modules and may run in parallel. `S8` depends on the S4 handler-context plumbing and the S6a M8 bearer-extraction seam — **not** on S7 — so it may run concurrently with S7a/S7b once S6a lands.

---

## Stage S1 — Foundation: types, constants, guards, errors (L0 part 1)

**Goal.** Stand up the dependency-free data core: every on-wire JSON-RPC + MCP shape as a Racket struct + flat contract, the error-code constants and protocol-version list, the type-guard predicates, and the `exn`-based error hierarchy with its JSON-RPC mapping. This is the single source of truth every later module imports.

Modules: **M1 (Types)**, **M2 (Errors)**. Mirrors `core/src/types/*` and **three** distinct TS error modules: `errors/sdkErrors.ts` (SDK exception hierarchy), `auth/errors.ts` (auth errors), and `core/types/errors.ts` (the **wire-error decode** module that turns a received JSON-RPC error *object* back into a typed error — e.g. `-32042` → `UrlElicitationRequiredError`, `-32004` → unsupported-version error, see `errors.ts:23-26,46-48`).

### Deliverables

- `mcp/core/types/constants.rkt` — error codes (`ParseError -32700` … `InvalidParams -32602`; MCP-specific `ResourceNotFound -32002`, `MissingRequiredClientCapability -32003`, `UnsupportedProtocolVersion -32004`, `UrlElicitationRequired -32042`); `LATEST = 2025-11-25`, `DEFAULT_NEGOTIATED = 2025-03-26`, full `SUPPORTED_PROTOCOL_VERSIONS`. Mirrors `constants.ts` / `enums.ts`.
- `mcp/core/types/spec-2025-11-25.rkt` and `spec-2026-07-28.rkt` — per-revision structs + contracts for every request, response, notification, and error type in each revision.
- `mcp/core/types/types.rkt` — the public protocol types and the **normalized-superset façade** (architecture N1): one internal shape per primitive that is the union of both revisions, with revision-only fields present-or-absent. Mirrors `types.ts`.
- `mcp/core/types/guards.rkt` — predicates (`is-jsonrpc-request?`, `is-jsonrpc-notification?`, `is-jsonrpc-response?`, `is-jsonrpc-error?`, etc.). **No batch guard** (architecture J3 — both target revisions removed JSON-RPC batching).
- `mcp/core/errors.rkt` — `exn:fail:mcp`, `exn:fail:mcp:protocol`, `exn:fail:mcp:auth` subtypes with stable codes; constructors + predicates; the single exn↔JSON-RPC-error conversion point (architecture §4.1 error-to-wire boundary). Covers **both directions**: (a) *encode* — an exn → a JSON-RPC error object; (b) *decode* — a received JSON-RPC error object → the matching typed error (mirrors `core/types/errors.ts`), so `-32042` decodes to a `UrlElicitationRequired` error and `-32004` to an unsupported-protocol-version error rather than a generic failure.
- `mcp/core/types/main.rkt` and `mcp/core/main.rkt` barrels — explicit `provide` curated public surface (architecture §1.3 public/internal boundary).
- `mcp/core/types/test/` + `mcp/core/test/errors-test.rkt` — round-trip `read-json`→struct→`write-json` for representative messages; guard truth tables; exn↔JSON-RPC mapping in **both** directions, explicitly including the **decode** direction (`-32042` → `UrlElicitationRequired` error; `-32004` → unsupported-version error).

### Dependencies
None. This is the bottom of the dependency graph.

### Testing / validation criteria
- `raco test` over `mcp/core/types/` and `mcp/core/errors.rkt` passes.
- Every error code and protocol-version constant matches the TS `constants.ts` / `enums.ts` values byte-for-byte (grep-diff against the checkout).
- A representative message of **each** JSON-RPC envelope kind parses from a TS-SDK-emitted JSON fixture into the correct struct and re-serializes identically (G1 wire-parity, started).
- **Decode direction (item 5):** a JSON-RPC error object with code `-32042` decodes to a `UrlElicitationRequired` typed error, and `-32004` decodes to an unsupported-protocol-version typed error — asserted against TS `core/types/errors.ts` behaviour, not just the encode path.
- Loading `mcp/core/types` and `mcp/core/errors.rkt` pulls in **no** subprocess/socket module (Portability NFR — verify with a load test in a restricted namespace).
- Parity matrix rows for `core/types/*`, `errors/*` marked `partial` (structs exist; exercised by conformance later).

**Demo.** A REPL transcript / script that parses a sample `initialize` request and a `tools/call` request from JSON, prints the structs, re-emits JSON, and shows a malformed message converted to a correct JSON-RPC error object.

---

## Stage S2 — Foundation: validators, schema normalization, shared utilities (L0 part 2)

**Goal.** Complete L0: the pluggable JSON-Schema validator provider with a Racket-native default, the dual-form (contract *or* JSON Schema) schema-normalization util, and the cohesive shared-utility modules (URI templates, tool-name validation, `_meta` metadata, shared auth structs, stdio framing).

Modules: **M3 (Validators)**, **M4 (Schema util)**, **M5a–M5e (Shared)**. Mirrors `core/validators/*`, `util/schema.ts` + `standardSchema.ts`, `uriTemplate.ts`, `toolNameValidation.ts`, `metadataUtils.ts`, `auth.ts` + `authUtils.ts`, `stdio.ts`.

### Deliverables

- `mcp/core/validators/provider.rkt` — validator-provider port via `racket/generic` (`gen:`-style): compile JSON Schema → reusable validator; validate value → ok/errors. Mirrors `validators/types.ts`.
- `mcp/core/validators/from-json-schema.rkt` — default Racket-native provider over a documented JSON-Schema subset (the hand-rolled-subset-vs-library decision from architecture §5 is recorded here as a justified Minimal-deps choice; default = hand-rolled subset unless a vetted lib is adopted). **Minimum supported keyword set (item 8):** `type` (string/number/integer/boolean/object/array/null), `properties`, `required`, `enum`, `items`, and `format` for the common string formats (`date-time`, `uri`, `email`). Any unsupported keyword is documented and either ignored-with-warning or rejected explicitly — never silently mis-validated.
- `mcp/core/util/schema.rkt` — normalize a `racket/contract` flat contract **or** a JSON Schema into (a) a wire JSON Schema for advertisement and (b) a validation handle delegating to M3. Standard-Schema analogue. Mirrors `util/schema.ts` + `standardSchema.ts`.
- `mcp/core/shared/uri-template.rkt` (M5a) — RFC 6570 subset `expand(template, vars)→uri` and `match(template, uri)→vars`.
- `mcp/core/shared/tool-name-validation.rkt` (M5b) — tool-name predicate + normalizer per spec.
- `mcp/core/shared/metadata-utils.rkt` (M5c) — read/write reserved `_meta` keys (protocol version, client info/capabilities, related-task, deprecated log level).
- `mcp/core/shared/auth.rkt` (M5d) — `AuthInfo` struct + token/metadata helpers (shared by client + server auth in S8).
- `mcp/core/shared/stdio.rkt` (M5e) — newline-delimited JSON frame encode/decode over a byte stream (the only M5 module performing I/O). **Orphaned until S6a:** this module has *no consumer in S2* — its first real consumer is the stdio transport (M7) in **S6a**. It is built here for L0 cohesion (architecture groups it under M5) and unit-tested standalone; integration coverage arrives with M7. (Implementers who prefer to defer it may move M5e beside M7 in S6a without affecting any other S2 deliverable.)
- Tests per module under `mcp/core/validators/test/`, `mcp/core/util/test/`, `mcp/core/shared/test/`.

### Dependencies
**S1** (imports types M1 + errors M2).

### Testing / validation criteria
- `raco test` over all S2 modules passes.
- URI template expand/match round-trips against the TS `uriTemplate.test.ts` fixtures (G1).
- Tool-name validation accepts/rejects the same names as the TS `toolNameValidation` tests.
- Schema-normalization: a contract input and an equivalent JSON-Schema input both produce a validation handle that accepts the same values and rejects the same values; the emitted wire JSON Schema matches expectation.
- Default validator provider validates representative tool-input documents identically to a TS-validated baseline for the supported subset. **Keyword coverage (item 8):** the suite includes at least one accept + one reject case for each of `type`, `object`/`properties`, `required`, `enum`, and `string`-`format`, each cross-checked against a TS Ajv-validated baseline for the same schema + value; any keyword outside the supported set is listed in the module docs as unsupported.
- stdio framing (M5e) round-trips multi-message byte streams including partial-frame buffering, tested standalone (its first integration consumer, M7, arrives in S6a — see the orphaned-until-S6a note above).
- Parity matrix rows for `validators/*`, `util/schema`, `uriTemplate`, `toolNameValidation`, `metadataUtils`, `auth` (shared) marked `partial`.

**Demo.** A script that: registers a JSON Schema → validates a good and a bad value; expands and matches a URI template; encodes/decodes a stdio frame buffer.

---

## Stage S3 — Transport port + in-memory adapter (L1 part 1)

**Goal.** Define the hexagonal port every adapter implements, and deliver the first concrete adapter — the in-memory paired transport — which unblocks engine and role development/testing without any OS I/O.

Modules: **M6 (Transport port)**, **M10 (In-memory transport)**. Mirrors `core/shared/transport.ts` and `core/util/inMemory.ts`.

### Deliverables

- `mcp/transport/transport.rkt` (M6) — `gen:transport` interface: `start`, `send` (options: `related-request-id`, resumption-token), `close`; callback sinks `on-message` (with message-extra-info: session, auth, HTTP req info), `on-close`, `on-error`; optional `session-id`. **`related-request-id` (item 10):** defined on the port here but **first load-bearing in S6a/M8** — Streamable HTTP uses it to route a server-initiated request (and its response) onto the correct client-opened SSE stream; it becomes essential in S7b when server-initiated sampling/elicitation runs over HTTP. In-memory (S3) and stdio (S6a) ignore it (single bidirectional channel), so the port shape is only *validated by a real consumer* once M8 lands — flagged here so the option is not mistaken for dead weight.
- `mcp/transport/in-memory.rkt` (M10) — constructor returning a **linked pair** of endpoints relaying messages via channels with **asynchronous delivery** (peer `on-message` invoked on a separate thread, not inline with `send`), so ordering/concurrency match a real transport (architecture M10 communication note).
- `mcp/transport/main.rkt` barrel.
- `mcp/transport/test/in-memory-test.rkt` — pair wiring, async delivery ordering, callback invocation, close/error propagation.

### Dependencies
**S1**, **S2** (types/errors; M5e framing is for stdio in S6a, not needed here).

### Testing / validation criteria
- `raco test` over `mcp/transport/in-memory.rkt` passes.
- A pair of in-memory endpoints round-trips N concurrent messages with no loss and no head-of-line blocking; delivery is observed to be asynchronous (a `send` returns before the peer handler runs).
- `on-close` / `on-error` fire on both endpoints when one side closes.
- Loading the transport port + in-memory adapter still pulls in no subprocess/socket module.
- Parity matrix rows for `transport.ts`, `inMemory.ts` marked `partial`.

**Demo.** A script wiring two in-memory endpoints, sending raw JSON-RPC messages each direction, and printing the callback-received messages in order.

---

## Stage S4 — Protocol engine (L2)

**Goal.** Implement the abstract shared engine that both roles compose: outbound `request`/`notification`, inbound dispatch by method to registered handlers, request/response correlation, capability + protocol-version negotiation, progress, cancellation, timeouts, and the per-request handler context.

Module: **M11 (Protocol engine)**. Mirrors `core/shared/protocol.ts`.

### Deliverables

- `mcp/core/shared/protocol.rkt` (M11):
  - **Outbound interface** — `request` (assign id, register response resolver, apply timeout, optional progress callback + cancellation) and `notification`.
  - **Handler-registration interface** — register request + notification handlers keyed by method.
  - **Handler-context interface** — per-inbound-request context carrying cancellation signal, `send-notification` / `send-request` (server-initiated requests), request-id, session info, HTTP transport info (absent for stdio). Mirrors `RequestHandlerExtra`. This is the context into which **S8 server auth injects `AuthInfo`** (F7) and over which **S7b server-initiated requests** flow (the `send-request` here is what sets `related-request-id` on the transport `send` once M8 makes it load-bearing).
  - **Capability/version interface** — `assert-capability-for-method`-style guards; protocol-version negotiation against `SUPPORTED_PROTOCOL_VERSIONS`, surfacing `UnsupportedProtocolVersion`; negotiation happens once at `initialize` and gates the N1 façade.
  - **Internal** — id-keyed in-flight registry; thread/channel/`sync` scheduler; per-request custodian + `cancel-evt`.
- `mcp/core/shared/test/protocol-test.rkt` — ported subset of TS `protocol.test.ts`: correlation, timeout, cancellation, progress, concurrent in-flight requests, server-initiated requests, malformed-input → JSON-RPC error (no crash).

### Dependencies
**S1**, **S2**, **S3** (binds the M6 port; tests run over the M10 in-memory pair).

### Testing / validation criteria
- `raco test` passes; ported `protocol.test.ts` cases pass over the in-memory transport (G6).
- Concurrent in-flight requests resolve independently with **no head-of-line blocking** (Concurrency NFR).
- A request that times out rejects with the correct SDK error; cancellation propagates via `cancel-evt`/custodian and the in-flight entry is reaped.
- A progress callback fires for `notifications/progress` correlated to the originating request.
- Capability/version guards reject an out-of-capability method and surface `UnsupportedProtocolVersion` for an unknown version.
- Malformed inbound message produces a correct JSON-RPC error response and the engine keeps running (Reliability NFR).
- **Composition invariant (S1 in architecture §4.1):** the engine is a standalone composable unit — no role subclassing; verified by the test harness constructing the engine directly.
- Parity matrix row for `protocol.ts` marked `partial`.

**Demo.** A two-engine in-memory harness: one engine issues a request, the other dispatches to a registered handler and replies; show a concurrent second request resolving out of order, a timeout, and a cancellation.

---

## Stage S5 — MVP roles: low-level server + client, Racket-only in-memory interop (L3 minimum)

**Goal.** Deliver the smallest end-to-end vertical slice: a low-level `Server` and the high-level `Client` wired through the engine, completing the `initialize` handshake + `tools/list` + `tools/call` over the **in-memory** transport. Interop in this stage is **Racket-only** (client ↔ server in one process); the first *cross-SDK* leg moves to **S6a**, where a real transport (stdio) exists to bridge to a TS SDK endpoint. (Per reviewer item 4 the cross-SDK claim is now binary — no "where feasible" / "else defer".)

Modules: **M12a (Low-level `Server`)**, **M13 (`Client`)** core verbs + middleware skeleton. Mirrors `server/server.ts` and `client/client.ts` + `client/middleware.ts`.

### Deliverables

- `mcp/server/server.rkt` (M12a):
  - **`initialize` handler ownership (item 1).** The low-level server **answers the inbound `initialize` request** and runs **server-side capability/version negotiation** — choosing the negotiated protocol version against `SUPPORTED_PROTOCOL_VERSIONS`, advertising server capabilities, and returning the `InitializeResult` (mirrors TS `server.ts:108,363`). The S4 engine provides the negotiation *machinery*; this handler is the server-role piece that actually answers `initialize`, without which the S5 demo cannot run.
  - Direct request-handler registration over the engine; usable standalone.
  - Owns the protocol-utility handlers: `ping` (S2 keepalive — answers inbound `ping`); and the **`logging/setLevel` handler in stub form (item 7).** The S5 stub **accepts and records** the requested level per session as a no-op — it stores the level but performs **no filtering** of outgoing log messages. The at-or-above-level gating that consumes this stored value is added in **S7b** (see the S5-stub→S7b-filter contract below).
- `mcp/client/client.rkt` (M13, core subset) — `connect` (initialize handshake + client-side capability/version negotiation), `ping`, `list-tools`, `call-tool`, capability/version accessors.
- `mcp/client/middleware.rkt` (M13) — request/response interception pipeline (composes around the engine boundary); at minimum a pass-through + one example interceptor.
- `mcp/server/main.rkt`, `mcp/client/main.rkt` barrels.
- `mcp/server/test/`, `mcp/client/test/` — initialize handshake (incl. server-side negotiation); list-tools/call-tool round-trip over in-memory; ping; `logging/setLevel` records the level (no filtering yet); middleware ordering.

**`logging/setLevel` stub→filter contract (item 7).** S5 (`server.rkt`, M12a) **owns** the `logging/setLevel` request handler and **stores** the client-requested level in per-session state, but applies **no** filter — every `send-logging-message` still emits. S7b (`mcp.rkt`, M12b) **reads** that stored per-session level and adds **at-or-above-level gating** to `send-logging-message`, suppressing messages below the level. The wire handler lives in M12a from S5; the filtering behaviour is layered on in S7b. Tests in S5 assert the level is recorded; tests in S7b assert suppression.

### Dependencies
**S4** (engine), and transitively S1–S3.

### Testing / validation criteria
- `raco test` over server/client passes.
- **`initialize` (item 1):** the low-level server answers an inbound `initialize`, performs server-side capability/version negotiation, and returns a spec-correct `InitializeResult`; an `initialize` requesting an unsupported version surfaces `UnsupportedProtocolVersion`.
- Racket client ↔ Racket low-level server complete `initialize` + `tools/list` + `tools/call` over in-memory with correct negotiation on **both** sides.
- **`logging/setLevel` (item 7):** the server handler accepts a `logging/setLevel` request and records the level; no filtering is asserted at this stage (filtering is an S7b criterion).
- Middleware pipeline observably wraps an outbound request and its inbound response in the right order.
- **Interop scope (item 4):** S5 interop is **Racket-only** (in-memory client↔server); no cross-SDK assertion is made here. The first cross-SDK leg is an S6a acceptance criterion.
- Parity matrix rows for `server.ts`, `client.ts`, `client/middleware.ts` marked `partial`.

**Demo.** A runnable script: start a Racket low-level server exposing one echo tool, connect the Racket client (full `initialize` handshake), call the tool, print the result; show `logging/setLevel` being accepted and the level recorded (with log messages still flowing, filtering deferred to S7b).

---

## Stage S6a — Real transports: stdio, Streamable HTTP, web-server adapter (L1 part 2)

**Goal.** Deliver the real transports so the SDK runs over local subprocess (stdio) and remote HTTP. This is also where the **first cross-SDK interop leg** lands (item 4): with stdio in hand, the Racket client/server can bridge to a TS SDK endpoint.

Modules: **M7 (stdio)**, **M8 (Streamable HTTP)**, **M9 (web-server adapter)**. Mirrors `{client,server}/stdio.ts`, `{client,server}/streamableHttp.ts`, `middleware/node`.

### Deliverables

- `mcp/transport/stdio.rkt` (M7) — client + server roles using `racket/system` `subprocess` + ports + **M5e framing (its first real consumer — item 10).** Non-portable code isolated here. `related-request-id` is accepted but ignored (single bidirectional pipe).
- `mcp/transport/streamable-http.rkt` (M8) — client + server roles: POST body parsing, SSE event streams, session IDs, `Host`/`Origin` validation (DNS-rebinding protection, Security NFR), and the **bearer-token extraction seam** that S8 server auth consumes (token → handler context). This is where **`related-request-id` first becomes load-bearing** (item 10): server-initiated requests/responses are routed onto the correct SSE stream by `related-request-id`.
  - **Resumption obligation (architecture N2):** server **mints a resumption token per emitted SSE event** and **validates/replays from a client-supplied token** on reconnect; client presents the last token on reconnect.
  - **Pluggable event-store seam (detail requirement):** the resumption-token store is a **port** (a `gen:`-style event-store interface — `append-event` / `replay-after`), *part of the M8 interface*, with an in-memory implementation as the default. The seam — not just the in-memory impl — is delivered here so that S9's `inMemoryEventStore` example (and any future persistent store) drops in **without an M8 code change**.
- `mcp/transport/web-server.rkt` (M9) — produce a `web-server` dispatcher/servlet feeding requests into M8 server handling, including streaming SSE responses.
- Tests under `mcp/transport/test/`.

### Dependencies
**S5** (the roles to drive the transports), **S3** (M6 port), **S2** (M5e framing). Parallel with **S6b** (disjoint modules).

### Testing / validation criteria
- `raco test` over transports passes.
- **stdio:** Racket server over stdio is launched as a subprocess by the Racket client; full `initialize` + `tools/list` + `tools/call` round-trips succeed; M5e framing handles partial/multi-message reads.
- **Cross-SDK first leg (item 4, G2):** the Racket client drives a **TS SDK example server** over stdio for `initialize` + `tools/list` + `tools/call`, with the wire JSON-RPC byte-for-byte parity-checked against TS fixtures (G1). This is the project's first cross-SDK interop assertion.
- **Streamable HTTP:** server mounted via the `web-server` adapter answers a POST `initialize`, streams an SSE response, maintains session IDs, and **rejects** a request with a disallowed `Host`/`Origin` (DNS-rebinding test).
- **Resumption (N2):** a resumed SSE stream replays missed events from a client-supplied resumption token. **Seam check:** a test substitutes a second event-store implementation behind the M8 event-store port and resumption still works with **no change to M8** — proving S9's `inMemoryEventStore` example is a drop-in.
- Parity matrix rows for `stdio.ts`, `streamableHttp.ts`, `middleware/node` marked `partial`→`done` where fully exercised.

**Demo.** (a) A stdio server script launched by a client script doing a tool call; (b) the Racket client driving a TS example server over stdio (interop log); (c) a Streamable HTTP server on `localhost`, hit with `curl`/the Racket client for `initialize` + a tool call, showing the SSE stream, a rejected cross-origin request, and a resumed stream after a forced reconnect.

---

## Stage S6b — High-level server: `McpServer` + completions (L3 high-level)

**Goal.** Deliver the ergonomic server API on top of the low-level `Server` (M12a) from S5: `register-tool` / `register-resource` (static + templated) / `register-prompt` returning live handles, plus completions. Static (non-session-state) primitives only — resource subscriptions, the logging-level filter, and progress/cancel role surfaces are S7b.

Modules: **M12b (`McpServer`)**, **M12c (Completable)**. Mirrors `server/mcp.ts`, `server/completable.ts`.

### Deliverables

- `mcp/server/mcp.rkt` (M12b, static surface) — `register-tool` / `register-resource` (static URI + URI-template via M5a) / `register-prompt`, each returning a handle with `enable`/`disable`/`update`/`remove`; uses M4 schema normalization + M3 validators for tool I/O; M5b tool-name validation; M5c metadata. **List ops cursor-paginated, server/producer side** (architecture J2): `tools/list`, `resources/list`, `prompts/list`, `resources/templates/list` slice the registry by an inbound opaque cursor and emit `nextCursor`. (The session-state pieces of M12b — subscription table, logging filter, list-changed-on-mutation — are deferred to **S7b**.)
- `mcp/server/completable.rkt` (M12c) — completions for prompt / resource-template arguments.
- Tests under `mcp/server/test/`.

### Dependencies
**S5** (M12a low-level server) + **S2** (M3/M4/M5). Parallel with **S6a** (disjoint modules). Both S6a and S6b must land before S7.

### Testing / validation criteria
- `raco test` over the high-level server passes (driven over the in-memory transport; real transports come from S6a but are not required for these unit tests).
- **High-level server:** registering a tool advertises its wire JSON Schema in `tools/list`; calling it validates input via the provider (F8); a templated resource resolves via URI-template match; a prompt returns; a completion request returns candidates.
- **Pagination producer (J2):** a `tools/list` with more entries than one page returns `nextCursor`; supplying that cursor returns the next page; the final page omits `nextCursor`.
- Handle lifecycle: `disable` hides a tool from `tools/list`; `update` changes its schema; `remove` drops it.
- Parity matrix rows for `mcp.ts`, `completable.ts` marked `partial`→`done` where fully exercised (session-state rows remain `partial` until S7b).

**Demo.** A script registering a tool, a static resource, a templated resource, and a prompt; listing each (showing pagination with `nextCursor`); calling the tool with valid + invalid input (validation reject); resolving a templated resource; and requesting a completion.

---

## Stage S7a — Client-driven primitives: sampling, elicitation, roots, client cursor-following

**Goal.** Implement the client-role primitives: handling server-initiated sampling and elicitation (form + URL modes), exposing roots, and following pagination cursors. Touches only the client module (M13), so it runs in parallel with the server-side S7b.

Module: **M13 (Client)**. Mirrors `client/client.ts` (sampling/elicitation/roots, list verbs).

### Deliverables

- Handler hooks for server-initiated `sampling/createMessage`.
- `elicitation/create` handling in **form + URL modes**, applying schema defaults via M3/M4. On the **client-receive** side, a server-sent `UrlElicitationRequired` (`-32042`) error is **decoded** to the typed error via the S1 decode path and surfaced to the caller. (The *server-raise* side of `-32042` is named in S7b — see item 6.)
- `roots/list` exposure + `send-roots-list-changed`.
- **List verbs consume opaque cursors** (J2, client/consumer side): `list-tools` / `list-resources` / `list-resource-templates` / `list-prompts` auto-paginate (or expose the cursor) and follow `nextCursor` to exhaustion against the S6b producer; remaining client verbs completed: `read-resource`, `subscribe-resource` / `unsubscribe-resource` (wire verbs; their server-side fan-out is S7b), `get-prompt`, `complete`, `set-logging-level`.
- **Progress + cancellation — client role surface (detail requirement):** `call-tool` exposes a **progress callback** option (invoked on correlated `notifications/progress`) and a **cancellation token** the caller can trip to cancel an in-flight request. (Engine support exists from S4; this is the concrete client-facing surface.)
- Tests under `mcp/client/test/`.

### Dependencies
**S6a** (a real transport to carry server-initiated sampling/elicitation, which need `related-request-id` over HTTP) + **S6b** (a producing server to paginate against). Parallel with **S7b**.

### Testing / validation criteria
- `raco test` passes for the client primitive flows.
- **Sampling:** a server-initiated `sampling/createMessage` is answered by the client sampling hook; result returns to the server (F3).
- **Elicitation:** form mode applies schema defaults and validates the user response; URL mode receives a server-raised `UrlElicitationRequired` and decodes it to the typed error (consuming the S1 decode path).
- **Roots:** client answers `roots/list`; `send-roots-list-changed` reaches the server.
- **Pagination (J2) client side:** the client follows `nextCursor` to exhaustion against a multi-page S6b server.
- **Progress + cancellation (client surface):** a `call-tool` with a progress callback receives progress updates; tripping the cancellation token cancels the in-flight request.
- Parity matrix rows for the client sampling/elicitation/roots/list verbs marked `done`.

**Demo.** A script: client connects; server requests sampling and the client answers; a form-mode elicitation round-trip and a URL-mode elicitation surfacing the typed `UrlElicitationRequired`; a paginated `list-tools` walked to exhaustion; a `call-tool` reporting progress then cancelled mid-flight.

---

## Stage S7b — Server session-state primitives: subscriptions + J1 fan-out, logging filter, progress/cancel surfaces

**Goal.** Implement the server-role session-state primitives on `McpServer` (M12b): the resource subscription table with J1 session-scoped fan-out, the S3 per-session logging-level filter (consuming the S5 `logging/setLevel` stub), the server-side progress/cancel surfaces, and the server *raising* `UrlElicitationRequired` (item 6). Completes vision Success Criterion §9.4.

Module: **M12b (`McpServer`, session-state surface)**. Mirrors the J1/S3 server pieces + `mcp.ts:156` (server-raised `-32042`).

### Deliverables

- **Resource-updated emitter (J1):** emits `notifications/resources/updated`; **per-session subscription table** — entries created on `resources/subscribe`, removed on `resources/unsubscribe` or session close — so a changed resource fans out only to currently-subscribed sessions (F9).
- List-changed emitters for `tool` / `resource` / `prompt` (fired on register/enable/disable/update/remove from S6b handles).
- **Per-session logging-level filter (S3) — consumes the S5 stub (item 7):** `send-logging-message` now **reads the per-session level recorded by the S5 `logging/setLevel` handler** and emits only at or above that level. This is the filtering half of the S5-stub→S7b-filter contract stated in S5.
- **Server-raised `UrlElicitationRequired` (item 6):** the high-level server **raises** the `-32042` `UrlElicitationRequired` error when a tool/handler requires URL-mode elicitation (mirrors TS `mcp.ts:156`); the engine serializes it via the M2 encode path and the client decodes it via the S1 decode path (the receive side handled in S7a). This stage owns the **raise** side.
- **Progress + cancellation — server role surface (detail requirement):** the server handler context exposes a **cancellation signal** (the handler can observe a client `notifications/cancelled`) and a **progress emitter** (the handler can send correlated `notifications/progress`). (Engine support from S4; this is the concrete server-facing surface, complementing the S7a client surface.)
- Tests under `mcp/server/test/`.

### Dependencies
**S6b** (the high-level server these primitives extend) + **S6a** (real transport to fan out over multiple sessions and carry server-initiated progress). Parallel with **S7a**.

### Testing / validation criteria
- `raco test` passes for the server primitive flows.
- **Subscriptions (J1, §9.4):** two sessions subscribe to different resources; a change to one resource notifies **only** the subscribed session; `resources/unsubscribe` / session-close stop notifications (F9).
- **Logging filter (S3, item 7):** with the level set to `warning` via the S5 `logging/setLevel` handler, an `info` message is suppressed and a `warning` message is delivered — exercising the stub→filter contract end to end.
- **Server-raised `-32042` (item 6):** a handler requiring URL-mode elicitation causes the server to raise `UrlElicitationRequired`; on the wire it carries code `-32042` and the client decodes it to the typed error.
- **Progress + cancellation (server surface):** a long-running tool call emits progress via the handler-context progress emitter and observes the cancellation signal when the client cancels mid-flight.
- All §9.4 primitives now have a passing test (jointly with S7a); parity matrix rows for the server session-state features marked `done`.

**Demo.** A scripted scenario: two clients subscribe to different resources, the server mutates one and only the subscribed client receives the update; `logging/setLevel warning` suppresses an `info` message; a handler raises `UrlElicitationRequired` and the client surfaces it; a progress-reporting tool call is cancelled mid-flight and the handler observes it.

---

## Stage S8 — Authentication: client OAuth + server bearer verification

**Goal.** Implement the auth layer atop the HTTP transport: client-side OAuth 2.0 authorization-code + PKCE with token storage/refresh and cross-app access, and server-side bearer-token verification via a pluggable verifier port feeding the engine handler context. Satisfies G8 and Success Criterion §9.5.

Module: **M14 (Auth)** — client `mcp/client/auth.rkt`, server `mcp/server/auth/`, building on shared M5d. Mirrors `client/auth.ts` + `authExtensions.ts` + `crossAppAccess.ts` and the OAuth server pieces. (Legacy-SSE auth-router **excluded** per vision §8.)

### Deliverables

- `mcp/client/auth.rkt` (M14 client) — begin authorize, exchange code (PKCE), refresh, persist tokens (never log secrets — Security NFR); cross-app access; tokens attach to M8 outbound headers (F6).
- `mcp/server/auth/` (M14 server) — bearer-token **verifier port** (`racket/generic`): token → `AuthInfo` or auth error; client registry; auth error responses. The S6a M8 bearer-extraction seam hands the token to the verifier → `AuthInfo` is placed into the **S4 engine handler context** (F7) for user handlers to read. Sub-module granularity (verifier vs registry; router excluded) resolved here per architecture §5.
- Tests under `mcp/client/test/auth-test.rkt` + `mcp/server/auth/test/`.

### Dependencies
**Two concrete dependencies, both pre-S7 (item 11):** (1) **S4** — the engine **handler-context** interface into which server auth injects `AuthInfo` (F7, built in S4); (2) **S6a/M8** — the Streamable HTTP transport's **bearer-extraction seam** and outbound-header attachment (auth rides HTTP). It depends on **neither S6b nor S7** — no primitive, subscription, or high-level-server feature is required. This is what makes the "independent of S7 / parallel with S7a–S7b" claim auditable: S8 can start as soon as S6a lands.

### Testing / validation criteria
- `raco test` over auth modules passes.
- **Client OAuth:** authorization-code + PKCE flow completes against a stub authorization server; token refresh works; tokens are persisted and attached to outbound HTTP headers; **no secret is ever logged** (assert against captured log output).
- **Server verification:** a valid bearer token resolves to `AuthInfo` available in the handler context; an invalid/expired token yields the correct auth error response; the client registry gates unknown clients.
- An authenticated end-to-end HTTP tool call succeeds with a valid token and is rejected (correct error) without one.
- Parity matrix rows for `client/auth.ts`, `authExtensions.ts`, `crossAppAccess.ts`, server auth marked `done`; legacy-SSE auth-router row marked `intentionally-excluded`.

**Demo.** A script starting an HTTP server requiring bearer auth, a client performing the OAuth flow against a local stub authorization server, then making an authenticated tool call; show the rejection path with no/invalid token.

---

## Stage S9 — Application surface: examples, Scribble docs, full conformance + interop closeout (L4)

**Goal.** Reach all remaining Success Criteria: runnable examples mirroring the TS set, complete Scribble documentation with compiling snippets, `raco pkg install` on a clean install, and the **full conformance suite** (both spec revisions × both transports × both roles) plus end-to-end interop against the MCP Inspector and the TS SDK in both directions. This stage flips the parity matrix to all-`done` (non-excluded) and certifies the project complete.

Modules: **M15 (Examples)**, **M16 (Docs)**, **M17 (Conformance & test harness)**. Mirrors `examples/`, TypeDoc→Scribble, and `test-conformance`.

### Deliverables

- `mcp/examples/` (M15) — a **curated subset** of runnable examples (item 9 — explicitly *not* a full mirror of the ~17 TS server examples; this set is chosen to exercise every transport, role, and the resumption seam, and may grow later). The curated set:
  1. **stdio server** — exposes a tool over stdio.
  2. **stateful HTTP server** — session-bearing Streamable HTTP server.
  3. **stateless HTTP server** — sessionless Streamable HTTP server.
  4. **OAuth server** — HTTP server behind bearer auth (exercises S8).
  5. **basic client** — connects + calls a tool.
  6. **parallel tool calls** — client issuing concurrent tool calls (exercises no-head-of-line-blocking).
  7. **resumable HTTP server with `inMemoryEventStore`** — wires the in-memory event-store implementation into the M8 **pluggable event-store seam** from S6a, exercising N2 resumption end to end and proving the seam is a drop-in (no M8 change). Mirrors the TS `inMemoryEventStore` example.

  Each is `racket`-runnable.
- `mcp/scribblings/` (M16) — Scribble docs: every public binding documented; `@examples` snippets compile (the compile is itself a conformance check). `raco docs` / `raco scribble` build target.
- `mcp/...` conformance harness (M17) — `rackunit` + ported cross-SDK conformance suite; runner driving in-memory (M10) + real (M7/M8) transports for **client and server roles** across **both spec revisions**; interop harness against the **MCP Inspector** and the **TS SDK** (Racket server driven by TS client; Racket client driving TS server).
- Packaging: `info.rkt` files so `raco pkg install mcp` (and sub-collections) succeeds on a clean Racket install.
- Final parity-matrix pass: every non-excluded row `done`; excluded rows (codemod, server-legacy SSE, per-framework middleware, external schema libs, multi-runtime shims, embedded LLM) marked `intentionally-excluded`.

### Dependencies
**S1–S8** (everything; this is the closeout). Examples and docs can begin incrementally during S6a/S6b–S8, but the full conformance + interop certification requires all primitives (S7a + S7b) and auth (S8).

### Testing / validation criteria
- **Conformance suite passes** for both spec revisions, both transports (stdio, Streamable HTTP), both roles (client, server) — Success Criterion §9.2 (G1, G5, G6).
- **Cross-SDK interop demonstrated** (§9.3, G2): a `racket-mcp` server passes the MCP Inspector connection flow and is driven by a TS SDK client over stdio **and** HTTP; a `racket-mcp` client calls tools/resources/prompts on a TS SDK example server.
- **Installable & documented** (§9.6, G7): `raco pkg install` succeeds on a clean install; `raco docs` builds; every public binding has a Scribble entry; all `@examples` snippets compile.
- **Runnable examples** (§9.8): all seven curated examples run end-to-end, including the `inMemoryEventStore` resumable-HTTP example dropped into the M8 event-store seam with no M8 change.
- **Idiomatic API confirmed** (§9.7, G4): a public-API review confirms contract-guarded, keyword-driven, struct-based design with no JS-isms.
- **Parity matrix complete** (§9.1, G3): all non-excluded rows `done`.
- Establish the tool-call-latency **baseline benchmark** (Performance NFR) and record it for regression tracking.

**Demo.** (a) MCP Inspector connecting to a `racket-mcp` server; (b) a TS SDK client log driving the Racket server over stdio and HTTP; (c) the Racket client log driving a TS example server; (d) `raco test` green across the conformance suite; (e) `raco docs` opening the built Scribble manual.

---

## Stage summary table

| Stage | Theme | Modules | Layer | Key acceptance gate | Vision goals |
|-------|-------|---------|-------|---------------------|--------------|
| S1 | Types, constants, guards, errors | M1, M2 | L0 | Wire structs round-trip TS fixtures; restricted-load test | G1 |
| S2 | Validators, schema, shared utils | M3, M4, M5a–e | L0 | URI/tool-name/schema parity with TS tests | G1, G4 |
| S3 | Transport port + in-memory | M6, M10 | L1 | Async paired delivery, no HOL blocking | G5 (port) |
| S4 | Protocol engine | M11 | L2 | Ported `protocol.test.ts`; concurrency/cancel/timeout | G6 |
| S5 | MVP roles (incl. `initialize` handler + `logging/setLevel` stub), Racket-only interop | M12a, M13(core) | L3 | Server answers `initialize` + negotiates; in-memory `tools/*` round-trip | G6 |
| S6a | Real transports + first cross-SDK leg | M7, M8, M9 | L1 | stdio + HTTP round-trips; DNS-rebinding reject; N2 resumption + event-store seam; Racket client drives TS server | G2, G5 |
| S6b | High-level server (static surface) | M12b, M12c | L3 | register-tool/resource/prompt; pagination producer; completions | G3 |
| S7a | Client-driven primitives | M13 | L3 | Sampling/elicitation(form+URL receive)/roots; client cursor-follow; call-tool progress+cancel | §9.4 (client) |
| S7b | Server session-state primitives | M12b | L3 | Subscriptions+J1 fan-out; S3 logging filter; server-raised `-32042`; server progress/cancel surface | §9.4 (server) |
| S8 | OAuth + bearer verification | M14 | cross | OAuth flow + verifier; no secret logged (deps: S4 ctx + S6a M8 seam) | G8, §9.5 |
| S9 | Examples, docs, conformance, interop | M15, M16, M17 | L4 | Full conformance ×2 revs ×2 transports ×2 roles; Inspector+TS interop; `raco pkg install` | G2, G3, G7, §9 all |

---

## Notes on sequencing & realism

- **Why the vertical slice lands at S5/S6a, not S1.** Interop requires a complete vertical slice (transport→engine→role→handshake). S5 delivers the thinnest *Racket-only* slice (`initialize` + `tools/*` over in-memory), which de-risks negotiation and wire parity; the **first cross-SDK leg** lands one stage later in **S6a**, the moment a real transport (stdio) exists to bridge to a TS endpoint (reviewer item 4 — the cross-SDK claim is binary and lives where a real transport makes it true).
- **Parallelism (auditable).** Three explicit parallel opportunities, all after S5: **S6a ∥ S6b** (transports vs high-level server — disjoint modules; both must land before S7); **S7a ∥ S7b** (client verbs/hooks vs server session-state — disjoint role surfaces); and **S8 ∥ S7a/S7b** (S8's only deps are the S4 handler-context and the S6a/M8 bearer seam — *not* S7 — so once S6a lands, auth can proceed alongside the S7 halves). All other stages are serial along the dependency graph.
- **Per-stage parity-matrix + test-port discipline** keeps G1/G3 continuously satisfied rather than deferring all conformance to S9; S9 is the *certification* pass, not the first time parity is checked.
- **Out-of-scope items** (vision §8) create no stages and no modules: codemod, server-legacy SSE transport, per-framework middleware packages, external JS schema libraries, multi-runtime shims, and an embedded LLM client.
