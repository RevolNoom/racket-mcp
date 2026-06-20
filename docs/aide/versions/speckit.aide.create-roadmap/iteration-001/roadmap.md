# Development Roadmap: `racket-mcp`

> **Status:** Living roadmap. Iteration 001.
> **Source vision:** `docs/aide/vision.md`.
> **Source architecture:** `docs/aide/architecture.md` (modules M1–M17, layers L0–L4).
> **Reference impl:** MCP TypeScript SDK v2 (`typescript-sdk/`).
> **Target spec revisions:** `2025-11-25`, `2026-07-28`.
> **Last updated:** 2026-06-15.

---

## How to read this roadmap

The roadmap delivers `racket-mcp` in **nine stages**. Each stage:

- builds **only** on lower architecture layers already delivered (dependency direction in architecture §3.1 is never violated — lower layers never import higher ones);
- ends in a **demonstrable artifact** (a `racket`-runnable script, a `raco test` target, or a cross-SDK interop run) that can be shown and tested;
- carries **explicit acceptance criteria** that map to vision Goals (G1–G8) and Success Criteria (§9);
- is sized to be **deployable locally in roughly one week**, assuming most implementation is done by an AI agent with the TS reference checkout as ground truth.

Stage numbering follows the layer build-up: **S1–S2** establish L0 foundation, **S3** the L1 transport port + in-memory adapter, **S4** the L2 protocol engine, **S5** the L3 roles (minimum viable client+server) proven by cross-SDK interop, **S6–S7** the remaining MCP primitives and real transports, **S8** auth, **S9** examples/docs/conformance closeout.

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
            S5 (MVP client + low-level server, in-memory interop)  ◀── first interop milestone
                    │
        ┌───────────┼───────────────┐
        v           v               v
   S6 (stdio    S6 (high-level   (S6 needs S5)
   + streamable  McpServer +
   HTTP + web-   completions +
   server)       full primitives)
        │           │
        └─────┬─────┘
              v
   S7 (sampling/elicitation/roots, subscriptions, pagination, logging, progress, cancel)
              │
              v
   S8 (OAuth client + server bearer verification)   ◀── needs S6 HTTP
              │
              v
   S9 (examples, Scribble docs, full conformance + Inspector/TS interop closeout)
```

`S6` may be split across its two halves (transports vs high-level server) by two agents working in parallel once `S5` lands, since transports (L1, depends only on M6 port + framing) and the high-level server (L3, depends on the engine + foundation) touch disjoint modules.

---

## Stage S1 — Foundation: types, constants, guards, errors (L0 part 1)

**Goal.** Stand up the dependency-free data core: every on-wire JSON-RPC + MCP shape as a Racket struct + flat contract, the error-code constants and protocol-version list, the type-guard predicates, and the `exn`-based error hierarchy with its JSON-RPC mapping. This is the single source of truth every later module imports.

Modules: **M1 (Types)**, **M2 (Errors)**. Mirrors `core/src/types/*` and `errors/sdkErrors.ts` + `auth/errors.ts`.

### Deliverables

- `mcp/core/types/constants.rkt` — error codes (`ParseError -32700` … `InvalidParams -32602`; MCP-specific `ResourceNotFound -32002`, `MissingRequiredClientCapability -32003`, `UnsupportedProtocolVersion -32004`, `UrlElicitationRequired -32042`); `LATEST = 2025-11-25`, `DEFAULT_NEGOTIATED = 2025-03-26`, full `SUPPORTED_PROTOCOL_VERSIONS`. Mirrors `constants.ts` / `enums.ts`.
- `mcp/core/types/spec-2025-11-25.rkt` and `spec-2026-07-28.rkt` — per-revision structs + contracts for every request, response, notification, and error type in each revision.
- `mcp/core/types/types.rkt` — the public protocol types and the **normalized-superset façade** (architecture N1): one internal shape per primitive that is the union of both revisions, with revision-only fields present-or-absent. Mirrors `types.ts`.
- `mcp/core/types/guards.rkt` — predicates (`is-jsonrpc-request?`, `is-jsonrpc-notification?`, `is-jsonrpc-response?`, `is-jsonrpc-error?`, etc.). **No batch guard** (architecture J3 — both target revisions removed JSON-RPC batching).
- `mcp/core/errors.rkt` — `exn:fail:mcp`, `exn:fail:mcp:protocol`, `exn:fail:mcp:auth` subtypes with stable codes; constructors + predicates; the single exn↔JSON-RPC-error conversion point (architecture §4.1 error-to-wire boundary).
- `mcp/core/types/main.rkt` and `mcp/core/main.rkt` barrels — explicit `provide` curated public surface (architecture §1.3 public/internal boundary).
- `mcp/core/types/test/` + `mcp/core/test/errors-test.rkt` — round-trip `read-json`→struct→`write-json` for representative messages; guard truth tables; exn↔JSON-RPC mapping both directions.

### Dependencies
None. This is the bottom of the dependency graph.

### Testing / validation criteria
- `raco test` over `mcp/core/types/` and `mcp/core/errors.rkt` passes.
- Every error code and protocol-version constant matches the TS `constants.ts` / `enums.ts` values byte-for-byte (grep-diff against the checkout).
- A representative message of **each** JSON-RPC envelope kind parses from a TS-SDK-emitted JSON fixture into the correct struct and re-serializes identically (G1 wire-parity, started).
- Loading `mcp/core/types` and `mcp/core/errors.rkt` pulls in **no** subprocess/socket module (Portability NFR — verify with a load test in a restricted namespace).
- Parity matrix rows for `core/types/*`, `errors/*` marked `partial` (structs exist; exercised by conformance later).

**Demo.** A REPL transcript / script that parses a sample `initialize` request and a `tools/call` request from JSON, prints the structs, re-emits JSON, and shows a malformed message converted to a correct JSON-RPC error object.

---

## Stage S2 — Foundation: validators, schema normalization, shared utilities (L0 part 2)

**Goal.** Complete L0: the pluggable JSON-Schema validator provider with a Racket-native default, the dual-form (contract *or* JSON Schema) schema-normalization util, and the cohesive shared-utility modules (URI templates, tool-name validation, `_meta` metadata, shared auth structs, stdio framing).

Modules: **M3 (Validators)**, **M4 (Schema util)**, **M5a–M5e (Shared)**. Mirrors `core/validators/*`, `util/schema.ts` + `standardSchema.ts`, `uriTemplate.ts`, `toolNameValidation.ts`, `metadataUtils.ts`, `auth.ts` + `authUtils.ts`, `stdio.ts`.

### Deliverables

- `mcp/core/validators/provider.rkt` — validator-provider port via `racket/generic` (`gen:`-style): compile JSON Schema → reusable validator; validate value → ok/errors. Mirrors `validators/types.ts`.
- `mcp/core/validators/from-json-schema.rkt` — default Racket-native provider over a documented JSON-Schema subset (the hand-rolled-subset-vs-library decision from architecture §5 is recorded here as a justified Minimal-deps choice; default = hand-rolled subset unless a vetted lib is adopted).
- `mcp/core/util/schema.rkt` — normalize a `racket/contract` flat contract **or** a JSON Schema into (a) a wire JSON Schema for advertisement and (b) a validation handle delegating to M3. Standard-Schema analogue. Mirrors `util/schema.ts` + `standardSchema.ts`.
- `mcp/core/shared/uri-template.rkt` (M5a) — RFC 6570 subset `expand(template, vars)→uri` and `match(template, uri)→vars`.
- `mcp/core/shared/tool-name-validation.rkt` (M5b) — tool-name predicate + normalizer per spec.
- `mcp/core/shared/metadata-utils.rkt` (M5c) — read/write reserved `_meta` keys (protocol version, client info/capabilities, related-task, deprecated log level).
- `mcp/core/shared/auth.rkt` (M5d) — `AuthInfo` struct + token/metadata helpers (shared by client + server auth in S8).
- `mcp/core/shared/stdio.rkt` (M5e) — newline-delimited JSON frame encode/decode over a byte stream (the only M5 module performing I/O).
- Tests per module under `mcp/core/validators/test/`, `mcp/core/util/test/`, `mcp/core/shared/test/`.

### Dependencies
**S1** (imports types M1 + errors M2).

### Testing / validation criteria
- `raco test` over all S2 modules passes.
- URI template expand/match round-trips against the TS `uriTemplate.test.ts` fixtures (G1).
- Tool-name validation accepts/rejects the same names as the TS `toolNameValidation` tests.
- Schema-normalization: a contract input and an equivalent JSON-Schema input both produce a validation handle that accepts the same values and rejects the same values; the emitted wire JSON Schema matches expectation.
- Default validator provider validates representative tool-input documents identically to a TS-validated baseline for the supported subset (document any unsupported keywords explicitly).
- stdio framing round-trips multi-message byte streams including partial-frame buffering.
- Parity matrix rows for `validators/*`, `util/schema`, `uriTemplate`, `toolNameValidation`, `metadataUtils`, `auth` (shared) marked `partial`.

**Demo.** A script that: registers a JSON Schema → validates a good and a bad value; expands and matches a URI template; encodes/decodes a stdio frame buffer.

---

## Stage S3 — Transport port + in-memory adapter (L1 part 1)

**Goal.** Define the hexagonal port every adapter implements, and deliver the first concrete adapter — the in-memory paired transport — which unblocks engine and role development/testing without any OS I/O.

Modules: **M6 (Transport port)**, **M10 (In-memory transport)**. Mirrors `core/shared/transport.ts` and `core/util/inMemory.ts`.

### Deliverables

- `mcp/transport/transport.rkt` (M6) — `gen:transport` interface: `start`, `send` (options: `related-request-id`, resumption-token), `close`; callback sinks `on-message` (with message-extra-info: session, auth, HTTP req info), `on-close`, `on-error`; optional `session-id`.
- `mcp/transport/in-memory.rkt` (M10) — constructor returning a **linked pair** of endpoints relaying messages via channels with **asynchronous delivery** (peer `on-message` invoked on a separate thread, not inline with `send`), so ordering/concurrency match a real transport (architecture M10 communication note).
- `mcp/transport/main.rkt` barrel.
- `mcp/transport/test/in-memory-test.rkt` — pair wiring, async delivery ordering, callback invocation, close/error propagation.

### Dependencies
**S1**, **S2** (types/errors; M5e framing is for stdio in S6, not needed here).

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
  - **Handler-context interface** — per-inbound-request context carrying cancellation signal, `send-notification` / `send-request` (server-initiated requests), request-id, session info, HTTP transport info (absent for stdio). Mirrors `RequestHandlerExtra`.
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

## Stage S5 — MVP roles: low-level server + client, first cross-SDK interop (L3 minimum)

**Goal.** Deliver the smallest end-to-end vertical slice that is **interoperable**: a low-level `Server` and the high-level `Client` wired through the engine, doing `initialize` handshake + `tools/list` + `tools/call` over the in-memory transport, then demonstrating the **first cross-SDK interop** by driving the same flow against a TS SDK endpoint over in-memory/stdio bridging where feasible. This is the project's first interop milestone (G2 begins).

Modules: **M12a (Low-level `Server`)**, **M13 (`Client`)** core verbs + middleware skeleton. Mirrors `server/server.ts` and `client/client.ts` + `client/middleware.ts`.

### Deliverables

- `mcp/server/server.rkt` (M12a) — direct request-handler registration over the engine; owns protocol-utility handlers (`ping` — S2 keepalive; `logging/setLevel` ownership stub). Usable standalone.
- `mcp/client/client.rkt` (M13, core subset) — `connect` (initialize handshake + capability/version negotiation), `ping`, `list-tools`, `call-tool`, capability/version accessors.
- `mcp/client/middleware.rkt` (M13) — request/response interception pipeline (composes around the engine boundary); at minimum a pass-through + one example interceptor.
- `mcp/server/main.rkt`, `mcp/client/main.rkt` barrels.
- `mcp/server/test/`, `mcp/client/test/` — initialize handshake; list-tools/call-tool round-trip over in-memory; ping; middleware ordering.
- An interop harness entry under `mcp/examples/` (or `*/test/`) that runs the Racket client against a **TS SDK example server** for `initialize` + `tools/list` + `tools/call` (G2, first leg).

### Dependencies
**S4** (engine), and transitively S1–S3.

### Testing / validation criteria
- `raco test` over server/client passes.
- Racket client ↔ Racket low-level server complete `initialize` + `tools/list` + `tools/call` over in-memory with correct capability/version negotiation.
- **Cross-SDK (G2, first leg):** the Racket client successfully calls `tools/list` + `tools/call` on a TS SDK example server (over stdio if the real transport lands here, else document the bridge used and defer full stdio to S6). The emitted/consumed JSON-RPC is byte-for-byte parity-checked against TS fixtures (G1).
- Middleware pipeline observably wraps an outbound request and its inbound response in the right order.
- Parity matrix rows for `server.ts`, `client.ts`, `client/middleware.ts` marked `partial`.

**Demo.** A runnable script: start a Racket low-level server exposing one echo tool, connect the Racket client, call the tool, print the result; plus the interop run log showing the Racket client driving the TS example server.

---

## Stage S6 — Real transports + high-level server with full primitives (L1 part 2 + L3 high-level)

**Goal.** Make the SDK usable for real local and remote deployments. Two parallelizable tracks (see stage graph): **(6A) real transports** — stdio and Streamable HTTP + the `web-server` mount adapter; **(6B) high-level server** — `McpServer` with `register-tool` / `register-resource` (static + templated) / `register-prompt` returning live handles, plus completions and the remaining primitive request handlers (resources, prompts, completion).

Modules: **M7 (stdio)**, **M8 (Streamable HTTP)**, **M9 (web-server adapter)**, **M12b (`McpServer`)**, **M12c (Completable)**. Mirrors `{client,server}/stdio.ts`, `{client,server}/streamableHttp.ts`, `middleware/node`, `server/mcp.ts`, `server/completable.ts`.

### Deliverables — Track 6A (transports)

- `mcp/transport/stdio.rkt` (M7) — client + server roles using `racket/system` `subprocess` + ports + M5e framing. Non-portable code isolated here.
- `mcp/transport/streamable-http.rkt` (M8) — client + server roles: POST body parsing, SSE event streams, session IDs, `Host`/`Origin` validation (DNS-rebinding protection, Security NFR), bearer-token extraction seam (feeds S8 verifier). **Resumption obligation (architecture N2):** server mints a resumption token per emitted SSE event and validates/replays from a client-supplied token on reconnect; client presents the last token on reconnect. Token-storage backend = in-memory for this stage (pluggable store deferred).
- `mcp/transport/web-server.rkt` (M9) — produce a `web-server` dispatcher/servlet feeding requests into M8 server handling, including streaming SSE responses.

### Deliverables — Track 6B (high-level server)

- `mcp/server/mcp.rkt` (M12b) — `register-tool` / `register-resource` (static URI + URI-template via M5a) / `register-prompt`, each returning a handle with `enable`/`disable`/`update`/`remove`; uses M4 schema normalization + M3 validators for tool I/O; M5b tool-name validation; M5c metadata. **List ops cursor-paginated** (architecture J2): `tools/list`, `resources/list`, `prompts/list`, `resources/templates/list` emit opaque `nextCursor`.
- `mcp/server/completable.rkt` (M12c) — completions for prompt / resource-template arguments.
- Tests under `mcp/transport/test/` and `mcp/server/test/`.

### Dependencies
**S5** (engine + roles). 6A depends on M6 (S3) + M5e (S2); 6B depends on M12a (S5) + M3/M4/M5 (S2). The two tracks touch disjoint modules and may proceed in parallel; both must land before S7.

### Testing / validation criteria
- `raco test` over transports + high-level server passes.
- **stdio:** Racket server over stdio is launched as a subprocess by the Racket client; full `initialize` + tool/resource/prompt round-trips succeed.
- **Streamable HTTP:** server mounted via the `web-server` adapter answers a POST `initialize`, streams an SSE response, maintains session IDs, and **rejects** a request with a disallowed `Host`/`Origin` (DNS-rebinding test). A resumed SSE stream replays missed events from a client-supplied resumption token (N2).
- **High-level server:** registering a tool advertises its wire JSON Schema in `tools/list`; calling it validates input via the provider (F8); a templated resource resolves via URI-template match; a prompt returns; a completion request returns candidates.
- **Pagination (J2):** a `tools/list` with more entries than one page returns `nextCursor`; following it yields the next page; exhaustion terminates the loop.
- Handle lifecycle: `disable` hides a tool from `tools/list`; `update` changes its schema; `remove` drops it.
- Parity matrix rows for `stdio.ts`, `streamableHttp.ts`, `middleware/node`, `mcp.ts`, `completable.ts` marked `partial`→`done` where fully exercised.

**Demo.** (a) A stdio server script launched by a client script doing a tool call; (b) a Streamable HTTP server started on `localhost`, hit with `curl`/the Racket client for `initialize` + a tool call, showing the SSE stream and a rejected cross-origin request.

---

## Stage S7 — Remaining MCP primitives: sampling, elicitation, roots, subscriptions, pagination-on-client, logging, progress, cancellation

**Goal.** Close out **all** MCP primitives so vision Success Criterion §9.4 ("all primitives implemented") holds: server-initiated sampling/elicitation, client-side roots, resource subscriptions with session-scoped fan-out, client-side cursor following, per-session logging-level filtering, and progress/cancellation across roles.

Modules: **M13 (Client)** handler hooks + list-verb pagination + subscribe/unsubscribe + roots; **M12b (Server)** resource-updated emitter + per-session subscription table + logging-level filter. Mirrors `client/client.ts` (sampling/elicitation/roots) + the J1/S3 server pieces.

### Deliverables

- **Client (M13):**
  - Handler hooks for server-initiated `sampling/createMessage`.
  - `elicitation/create` handling in **form + URL modes**, applying schema defaults via M3/M4; surfaces `UrlElicitationRequired` per spec (2026-07-28).
  - `roots/list` exposure + `send-roots-list-changed`.
  - **List verbs consume opaque cursors** (J2): `list-tools` / `list-resources` / `list-resource-templates` / `list-prompts` auto-paginate or expose the cursor; `read-resource`, `subscribe-resource` / `unsubscribe-resource`, `list-prompts` / `get-prompt`, `complete`, `set-logging-level` completed.
- **Server (M12b):**
  - **Resource-updated emitter (J1):** emits `notifications/resources/updated`; **per-session subscription table** — entries on `resources/subscribe`, removed on `resources/unsubscribe` or session close — so a changed resource fans out only to currently-subscribed sessions (F9).
  - List-changed emitters for `tool` / `resource` / `prompt`.
  - **Per-session logging-level filter (S3 in architecture):** `send-logging-message` emits only at or above the level set via `logging/setLevel`.
- Progress + cancellation exercised end-to-end across both roles (engine support exists from S4; wire the role-level surfaces).
- Tests under `mcp/client/test/` + `mcp/server/test/` for each primitive.

### Dependencies
**S6** (high-level server + transports must exist to subscribe/emit and to carry server-initiated requests over a real transport).

### Testing / validation criteria
- `raco test` passes for all primitive flows.
- **Sampling:** server handler context `send-request` triggers a `sampling/createMessage` that the client sampling hook answers; result returns to the server (F3).
- **Elicitation:** form mode applies schema defaults and validates the user response; URL mode surfaces `UrlElicitationRequired` correctly.
- **Roots:** client answers `roots/list`; `send-roots-list-changed` notification reaches the server.
- **Subscriptions (J1, §9.4):** two sessions subscribe to different resources; a change to one resource notifies **only** the subscribed session; unsubscribe / session-close stop notifications (F9).
- **Pagination (J2) client side:** the client follows `nextCursor` to exhaustion against a multi-page server.
- **Logging filter (S3):** with level set to `warning`, an `info` message is suppressed and a `warning` message is delivered.
- **Progress + cancellation:** a long-running tool call reports progress and is cancellable mid-flight; the server handler observes the cancellation signal.
- All §9.4 primitives have a passing test; parity matrix rows for the relevant client/server features marked `done`.

**Demo.** A scripted scenario: client connects, subscribes to a resource, server mutates it and the client receives the update; server requests sampling and the client answers; an elicitation round-trip; a cancellable progress-reporting tool call.

---

## Stage S8 — Authentication: client OAuth + server bearer verification

**Goal.** Implement the auth layer atop the HTTP transport: client-side OAuth 2.0 authorization-code + PKCE with token storage/refresh and cross-app access, and server-side bearer-token verification via a pluggable verifier port feeding the engine handler context. Satisfies G8 and Success Criterion §9.5.

Module: **M14 (Auth)** — client `mcp/client/auth.rkt`, server `mcp/server/auth/`, building on shared M5d. Mirrors `client/auth.ts` + `authExtensions.ts` + `crossAppAccess.ts` and the OAuth server pieces. (Legacy-SSE auth-router **excluded** per vision §8.)

### Deliverables

- `mcp/client/auth.rkt` (M14 client) — begin authorize, exchange code (PKCE), refresh, persist tokens (never log secrets — Security NFR); cross-app access; tokens attach to M8 outbound headers (F6).
- `mcp/server/auth/` (M14 server) — bearer-token **verifier port** (`racket/generic`): token → `AuthInfo` or auth error; client registry; auth error responses. M8 extracts bearer → verifier → `AuthInfo` placed in engine handler context (F7). Sub-module granularity (verifier vs registry; router excluded) resolved here per architecture §5.
- Tests under `mcp/client/test/auth-test.rkt` + `mcp/server/auth/test/`.

### Dependencies
**S6** (Streamable HTTP transport M8 — auth rides HTTP). Independent of S7.

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

- `mcp/examples/` (M15) — runnable mirrors of the TS examples (`typescript-sdk/examples/`): stdio server, **stateful** + **stateless** HTTP server, OAuth server, basic client, parallel tool calls. Each is `racket`-runnable.
- `mcp/scribblings/` (M16) — Scribble docs: every public binding documented; `@examples` snippets compile (the compile is itself a conformance check). `raco docs` / `raco scribble` build target.
- `mcp/...` conformance harness (M17) — `rackunit` + ported cross-SDK conformance suite; runner driving in-memory (M10) + real (M7/M8) transports for **client and server roles** across **both spec revisions**; interop harness against the **MCP Inspector** and the **TS SDK** (Racket server driven by TS client; Racket client driving TS server).
- Packaging: `info.rkt` files so `raco pkg install mcp` (and sub-collections) succeeds on a clean Racket install.
- Final parity-matrix pass: every non-excluded row `done`; excluded rows (codemod, server-legacy SSE, per-framework middleware, external schema libs, multi-runtime shims, embedded LLM) marked `intentionally-excluded`.

### Dependencies
**S1–S8** (everything; this is the closeout). Examples and docs can begin incrementally during S6–S8 but the full conformance + interop certification requires all primitives (S7) and auth (S8).

### Testing / validation criteria
- **Conformance suite passes** for both spec revisions, both transports (stdio, Streamable HTTP), both roles (client, server) — Success Criterion §9.2 (G1, G5, G6).
- **Cross-SDK interop demonstrated** (§9.3, G2): a `racket-mcp` server passes the MCP Inspector connection flow and is driven by a TS SDK client over stdio **and** HTTP; a `racket-mcp` client calls tools/resources/prompts on a TS SDK example server.
- **Installable & documented** (§9.6, G7): `raco pkg install` succeeds on a clean install; `raco docs` builds; every public binding has a Scribble entry; all `@examples` snippets compile.
- **Runnable examples** (§9.8): all five example categories run end-to-end.
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
| S5 | MVP roles + first interop | M12a, M13(core) | L3 | Racket client drives TS server (`tools/*`) | G2, G6 |
| S6 | Real transports + high-level server | M7, M8, M9, M12b, M12c | L1+L3 | stdio + HTTP round-trips; DNS-rebinding reject; pagination | G3, G5 |
| S7 | All remaining primitives | M12b, M13 | L3 | Sampling/elicitation/roots/subscriptions/logging/progress/cancel | §9.4 |
| S8 | OAuth + bearer verification | M14 | cross | OAuth flow + verifier; no secret logged | G8, §9.5 |
| S9 | Examples, docs, conformance, interop | M15, M16, M17 | L4 | Full conformance ×2 revs ×2 transports ×2 roles; Inspector+TS interop; `raco pkg install` | G2, G3, G7, §9 all |

---

## Notes on sequencing & realism

- **Why S5 is the first interop milestone, not S1.** Interop requires a complete vertical slice (transport→engine→role→handshake). S5 delivers the thinnest such slice (`initialize` + `tools/*`) so risk in wire parity and negotiation surfaces early, before the full primitive set is built.
- **Parallelism.** Only S6's two tracks are explicitly parallelizable (disjoint modules after S5). All other stages are serial along the dependency graph. S8 is independent of S7 (both depend on S6) and could run concurrently with S7 if two agents are available.
- **Per-stage parity-matrix + test-port discipline** keeps G1/G3 continuously satisfied rather than deferring all conformance to S9; S9 is the *certification* pass, not the first time parity is checked.
- **Out-of-scope items** (vision §8) create no stages and no modules: codemod, server-legacy SSE transport, per-framework middleware packages, external JS schema libraries, multi-runtime shims, and an embedded LLM client.
