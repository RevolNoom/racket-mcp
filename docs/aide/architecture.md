# Technical Architecture: `racket-mcp`

> **Status:** Living architecture document. Iteration 002.
> **Source vision:** `docs/aide/vision.md`.
> **Reference impl:** MCP TypeScript SDK v2 (`typescript-sdk/`).
> **Target spec revisions:** `2025-11-25`, `2026-07-28`.
> **Last updated:** 2026-06-14.

This document defines the *structural* architecture — modules, interfaces, communication patterns, tech stack. It deliberately stops short of implementation detail (concrete function names, struct field types, control flow); those belong to later steps. Naming shown is illustrative of the *shape* of an interface, not a binding spec.

---

## 1. System Overview

### 1.1 Architectural pattern

`racket-mcp` is a **layered + ports-and-adapters (hexagonal)** library, organized as a single Racket collection (`mcp`) with sub-collections that map 1:1 onto the TS SDK v2 monorepo packages.

Layers, bottom to top:

```
┌───────────────────────────────────────────────────────────────┐
│  L4  APPLICATION SURFACE   examples/, scribblings/              │
├───────────────────────────────────────────────────────────────┤
│  L3  ENDPOINT / ROLE       client/  ·  server/                  │
│      (high-level McpServer, Client; low-level Server)           │
├───────────────────────────────────────────────────────────────┤
│  L2  PROTOCOL ENGINE       core/shared/protocol                 │
│      (correlation, negotiation, progress, cancel, timeouts)     │
├───────────────────────────────────────────────────────────────┤
│  L1  TRANSPORT PORTS+ADAPTERS  transport/ (gen:transport)       │
│      stdio · streamable-http · in-memory · web-server adapter   │
├───────────────────────────────────────────────────────────────┤
│  L0  FOUNDATION  core/types · core/errors · core/validators ·   │
│      core/util · core/shared (auth, uri-template, metadata, …)  │
└───────────────────────────────────────────────────────────────┘
```

**Why layered + hexagonal.**
- The protocol engine (L2) is the stable core. It knows nothing about *how* bytes move — it talks only to the `gen:transport` **port** (L1). stdio / HTTP / in-memory are interchangeable **adapters**. This mirrors the TS `Protocol`/`Transport` split and satisfies the portability NFR (core loads without subprocess/socket deps).
- Roles (L3) are thin specializations of the engine via composition, mirroring TS `Client extends Protocol` / `Server extends Protocol`. Racket uses composition + `racket/generic`, not class inheritance (idiomatic-API goal G4).
- L0 foundation is pure data + contracts, dependency-free, usable in restricted contexts.

### 1.2 Communication style

- **Inbound message flow** is **event-driven**: a transport adapter raises an inbound-message event; the protocol engine dispatches by JSON-RPC method to a registered handler.
- **Outbound request flow** is **async request/response** with correlation by JSON-RPC id, resolved over Racket **channels / synchronizable events**.
- **Concurrency model**: green threads. Each in-flight request tracked in an id-keyed table; responses resolve via `sync` on events; cancellation propagates via a `cancel-evt` + custodian per request. No head-of-line blocking; server-initiated requests (sampling/elicitation) ride the same engine concurrently.

### 1.3 Public / internal boundary

Each sub-collection exposes a curated public API via its `main.rkt` (explicit `provide`). Internal modules `provide` only to siblings inside the collection. Non-portable facilities (subprocess, sockets) live in `transport/` adapters and named submodules so L0–L2 stay runtime-neutral. Mirrors TS `core/public` vs internal barrel.

---

## 2. Module Definitions

Modules grouped by layer. For each: **purpose/scope**, **interfaces** (with responsibilities), and **communication patterns**. "Internal" = interface used inside the module/collection; "External" = interface crossing a module boundary.

The full set below covers every Core Feature §4 and every Appendix-A capability of the vision. Coverage traced in §3.3.

---

### L0 — Foundation (`mcp/core`)

#### M1. Types (`mcp/core/types/`)
- **Purpose/scope.** All on-wire data shapes: JSON-RPC 2.0 envelopes (request/response/notification/error — see batching note below), MCP primitive types (tool, resource, prompt, sampling, elicitation, roots, completion, logging, progress, cancellation), error codes, both versioned spec type sets, type guards/predicates. Mirrors `core/src/types/*`.
- **Interfaces.**
  - *External — Type definitions interface.* Structs + flat contracts for every protocol type. Responsibility: be the single source of truth for wire shapes; consumed by every higher module.
  - *External — Constants/enums interface.* Error codes (`ParseError -32700` … MCP-specific `ResourceNotFound -32002`, `MissingRequiredClientCapability -32003`, `UnsupportedProtocolVersion -32004`, `UrlElicitationRequired -32042`), protocol-version list (`LATEST`, `DEFAULT_NEGOTIATED`, `SUPPORTED_PROTOCOL_VERSIONS`).
  - *External — Guards interface.* Predicates (`is-jsonrpc-request?` etc.) for dispatch + validation.
  - *Internal — Versioned-spec modules.* `spec-2025-11-25`, `spec-2026-07-28` provide per-revision shapes; a normalization seam exposes a version-agnostic façade to the engine (façade strategy — see N1 below and §4.1).
- **J3 — No JSON-RPC batching.** Both targeted spec revisions (`2025-11-25`, `2026-07-28`) **removed** JSON-RPC batch support; the TS SDK v2 reference checkout (`typescript-sdk/`) carries **no** `JSONRPCBatch` type, `isJSONRPCBatch` guard, or batch handling in `protocol.ts` (confirmed by grep over `spec.types.2025-11-25.ts`, `spec.types.2026-07-28.ts`, `types.ts`, `guards.ts`, `protocol.ts`). Therefore M1 defines **no batch envelope** and no module owns batch fan-out/fan-in. Each JSON-RPC message is sent and received singly. (Resolves the J3 inconsistency by removing batch, not by adding an owner.)
- **Communication.** Pure data, no I/O. Consumed by reference (import) only. No callbacks.

#### M2. Errors (`mcp/core/errors.rkt`)
- **Purpose/scope.** `SdkError` exception hierarchy + `ProtocolError` for wire-level faults + auth errors. Mirrors `errors/sdkErrors.ts` + `auth/errors.ts`.
- **Interfaces.**
  - *External — Error-type interface.* Racket `exn` subtypes (`exn:fail:mcp`, `:protocol`, `:auth`) with stable codes; predicates + constructors.
  - *External — Error↔JSON-RPC mapping interface.* Convert an exception into a JSON-RPC error object and back, so the engine never crashes on malformed input (Reliability NFR).
- **Communication.** Raised/caught across all layers; serialized at the protocol boundary.

#### M3. Validators (`mcp/core/validators/`)
- **Purpose/scope.** Validate *user-supplied* tool/resource/prompt JSON-Schema (not the SDK's own types — those use contracts). Pluggable provider with a Racket-native default. Mirrors `core/validators/*`; collapses the Ajv/cfWorker split to one provider (§8 vision).
- **Interfaces.**
  - *External — Validator-provider port (`gen:`-style interface).* Compile a JSON Schema → a reusable validator; validate a value → ok/errors. Lets advanced users swap providers.
  - *Internal — Default JSON-Schema provider.* Implements the port over a Racket-native subset (`from-json-schema`).
- **Communication.** Synchronous call/return; injected into server/client by reference. Port = dependency-inversion seam.

#### M4. Schema util (`mcp/core/util/schema.rkt`)
- **Purpose/scope.** Normalize the two accepted user-schema forms — a `racket/contract` flat contract *or* a JSON Schema — into one internal representation (Standard-Schema analogue). Mirrors `util/schema.ts` + `standardSchema.ts`.
- **Interfaces.**
  - *External — Schema-normalization interface.* Accept either form, emit (a) a wire JSON Schema for advertisement and (b) a validation handle delegating to M3.
- **Communication.** Synchronous; bridges M3 (validators) and L3 (server tool registration).

#### M5. Shared utilities (`mcp/core/shared/`)
Several cohesive single-responsibility modules:
- **M5a. URI templates** (`uri-template.rkt`) — RFC 6570 subset expand/match for templated resources. *External interface:* expand(template, vars)→uri; match(template, uri)→vars.
- **M5b. Tool-name validation** (`tool-name-validation.rkt`) — validate/normalize tool names per spec. *External interface:* predicate + normalizer.
- **M5c. Metadata utils** (`metadata-utils.rkt`) — per-request `_meta` envelope (2026-07-28): reserved keys (protocol version, client info/capabilities, related-task, deprecated log level). *External interface:* read/write reserved meta keys.
- **M5d. Auth shared** (`auth.rkt`) — `AuthInfo`, token/metadata helpers shared by client + server auth. *External interface:* auth-info struct + token/metadata helpers.
- **M5e. stdio framing** (`stdio.rkt`) — newline-delimited JSON framing helpers used by the stdio transport. *External interface:* encode/decode message frames over a byte stream.
- **Communication.** All synchronous; M5a/M5b/M5c are pure functions (no I/O, no state), M5d exposes immutable structs, M5e is the only one performing byte-stream I/O. Consumed by reference.

---

### L1 — Transport Ports & Adapters (`mcp/transport/`)

#### M6. Transport port (`mcp/transport/transport.rkt`)
- **Purpose/scope.** The abstraction every adapter implements — the hexagonal port. Mirrors `core/shared/transport.ts` `Transport` interface.
- **Interfaces.**
  - *External — `gen:transport` interface.* Methods: `start`, `send` (with options: `related-request-id`, resumption-token), `close`. Callback sinks: on-message (with message-extra-info: session, auth, HTTP req info), on-close, on-error. Optional `session-id`. Responsibility: decouple engine from byte movement.
- **Communication.** Engine→adapter: synchronous method calls (`send`/`start`/`close`). Adapter→engine: **callback/event** (on-message/on-close/on-error). This callback inversion is the core eventing seam.

#### M7. stdio transport (`mcp/transport/stdio.rkt`)
- **Purpose/scope.** Local subprocess integration, client + server roles. Mirrors `{client,server}/stdio.ts`.
- **Interfaces.** *External:* implements `gen:transport` (M6). *Internal:* uses M5e framing + Racket `subprocess`/ports.
- **Communication.** Reads stdin / writes stdout (server role) or spawns child + pipes (client role). Inbound bytes → frame → on-message callback. Non-portable; isolated here.

#### M8. Streamable HTTP transport (`mcp/transport/streamable-http.rkt`)
- **Purpose/scope.** Recommended remote transport, client + server roles: SSE streaming, session IDs, resumable streams (resumption tokens). Mirrors `{client,server}/streamableHttp.ts`.
- **Interfaces.**
  - *External:* implements `gen:transport` (M6).
  - *Internal — HTTP request/SSE handling.* Server role: parse POST bodies, manage SSE event streams, session lifecycle, `Host`/`Origin` validation (DNS-rebinding protection, Security NFR), bearer-token extraction → M14. **Resumption obligation (N2):** the server SSE interface MUST **mint a resumption token per emitted SSE event and validate/replay from a client-supplied resumption token** on reconnect (honoring the resumable-streams Reliability NFR, vision line 213). This is a fixed interface obligation; the *token-storage backend* (in-memory vs pluggable store) stays deferred (§5). Client role: POST via HTTP client, consume SSE, and present the last resumption token on reconnect to resume.
- **Communication.** Server role consumes an HTTP request/response from the web-server adapter (M9). Client role drives `net/http-client`/`net/url`. Streaming via SSE events → on-message callbacks. Engine-agnostic.

#### M9. web-server adapter (`mcp/transport/web-server.rkt`)
- **Purpose/scope.** Mount the Streamable HTTP *server* handler onto Racket's built-in `web-server`. Single first-party framework adapter (collapses TS express/hono/fastify/node). Mirrors `middleware/node`.
- **Interfaces.** *External — Mount interface.* Produce a `web-server` dispatcher/servlet that feeds requests into M8's server-side handling and returns responses (incl. streaming SSE responses).
- **Communication.** Bridges `web-server` request lifecycle ↔ M8. Adapter only — no protocol logic.

#### M10. In-memory transport (`mcp/transport/in-memory.rkt`)
- **Purpose/scope.** Same-process paired transport for tests + same-process client↔server wiring. Mirrors `core/util/inMemory.ts`.
- **Interfaces.** *External:* implements `gen:transport` (M6); a constructor returning a linked pair.
- **Communication.** Two endpoints relay messages directly via channels — no serialization required. Delivery is asynchronous (message handed to the peer's on-message callback on a separate thread, not inline with `send`), so request/response ordering and concurrency match a real transport rather than collapsing to synchronous in-line calls.

---

### L2 — Protocol Engine (`mcp/core/shared/protocol.rkt`)

#### M11. Protocol engine
- **Purpose/scope.** The abstract shared base for both roles. Message routing, request/response correlation, capability negotiation, progress callbacks, cancellation, timeouts, transport lifecycle. Mirrors `core/shared/protocol.ts`.
- **Interfaces.**
  - *External — Outbound interface.* `request` (assign id, register response resolver, apply timeout, optional progress callback + cancellation) and `notification`.
  - *External — Handler-registration interface.* Register request handlers + notification handlers keyed by method; engine dispatches inbound messages to them.
  - *External — Handler context interface.* Per-inbound-request context carrying: cancellation signal, `send-notification` / `send-request` (for server-initiated requests), request-id, session info, and HTTP transport info (absent for stdio). Mirrors TS `RequestHandlerExtra`.
  - *External — Capability/version interface.* `assert-capability-for-method`-style guards before issuing/serving; protocol-version negotiation against `SUPPORTED_PROTOCOL_VERSIONS`, surfacing `UnsupportedProtocolVersion`.
  - *Internal — In-flight registry + scheduler.* Id-keyed table of pending requests; thread/channel/`sync` machinery; per-request custodian + `cancel-evt`.
- **Communication.**
  - Engine ↔ Transport (M6): synchronous `send`; inbound via on-message callback.
  - Engine ↔ Roles (M12/M13): roles register handlers + call outbound interface; engine invokes role handlers with the handler context. **Composition, not inheritance.**
  - Concurrency: green threads + channels/events; cancellation via custodian/`cancel-evt`.

---

### L3 — Endpoint / Role (`mcp/client/`, `mcp/server/`)

#### M12. Server role (`mcp/server/`)
Three separable sub-modules (sub-lettered for symmetry with M5; the roadmap may sequence M12a before M12b/M12c):
- **M12a. Low-level `Server`** (`server.rkt`): direct request-handler registration over the engine. Mirrors `server/server.ts`. Usable standalone without M12b.
- **M12b. High-level `McpServer`** (`mcp.rkt`): ergonomic `register-tool` / `register-resource` (static URI + URI-template) / `register-prompt`, each returning a handle supporting enable/disable/update/remove; list-changed notifications (`tool`/`resource`/`prompt`); `send-logging-message`; resource subscriptions. Built on M12a. Mirrors `server/mcp.ts`.
- **M12c. Completable** (`completable.rkt`): completions for prompt/resource-template arguments. Mirrors `server/completable.ts`.
- **Interfaces.**
  - *External — Registration interface (M12b).* register-tool/resource/prompt (keyword-driven, contract-guarded; G4), returning live handles. **List ops are cursor-paginated** (J2): `tools/list`, `resources/list`, `prompts/list`, `resources/templates/list` responses surface an opaque `nextCursor`; the registration/list path slices its registry by an inbound opaque cursor and returns the next page. Preserves wire parity (G1) and TS-client interop (G2).
  - *External — Notification interface (M12b).* (a) list-changed emitters (`tool`/`resource`/`prompt`); (b) `send-logging-message` (server applies the per-session logging-level filter set via `logging/setLevel` — S3, emitting only at or above the client's level); (c) **resource-updated emitter** (J1): emits `notifications/resources/updated` and **tracks active resource subscriptions per session** — entries created on `resources/subscribe`, removed on `resources/unsubscribe` or session close — so a registered resource's change fans out only to currently-subscribed sessions. Completes Success Criterion §9.4.
  - *External — Server-utility responsibility (M12a).* Answer inbound `ping` (S2 — keepalive); the low-level server owns the protocol-utility request handlers (ping, logging/setLevel) shared by all higher registrations.
  - *Internal — Engine-binding.* Translate registrations into engine request/notification handlers; wire completions; use M4 (schema) + M3 (validators) for tool I/O; M5a (URI templates) for templated resources; M5b for tool-name validation; M5c metadata for `_meta` reserved keys.
- **Communication.** Calls down to M11 (handler registration, notifications). Pulls validation from M3/M4, URI/meta from M5. User code injects tool/resource/prompt callbacks (synchronous or thread-spawning).

#### M13. High-level client (`mcp/client/client.rkt`) + middleware (`mcp/client/middleware.rkt`)
- **Purpose/scope.**
  - *`Client`* (`client.rkt`): `connect`, `ping`, list/call-tool, list/read/subscribe/unsubscribe-resource, list-resource-templates, list/get-prompt, `complete`, `set-logging-level`, capability/version accessors, `send-roots-list-changed`; **handles** server-initiated `sampling/createMessage`, `elicitation/create` (form + URL modes, applying schema defaults), and exposes `roots/list`. Mirrors `client/client.ts`.
  - *Middleware* (`middleware.rkt`): request/response interception pipeline (distinct from framework adapters). Mirrors `client/middleware.ts`.
- **Interfaces.**
  - *External — Client API interface.* The verbs above, contract-guarded + keyword-driven. **List verbs consume opaque pagination cursors** (J2): list-tools/list-resources/list-resource-templates/list-prompts accept + follow `nextCursor` (auto-paginate or expose the cursor), matching the server M12b producer side and TS-client behavior (G1/G2). `ping` issues the keepalive request (S2); both roles may answer inbound `ping`.
  - *External — Handler-hook interface.* User-supplied sampling / elicitation / roots handlers.
  - *External — Middleware-pipeline interface.* Compose interceptors around outbound requests / inbound responses.
  - *Internal — Engine-binding.* Map client verbs onto engine outbound requests; register handlers for server-initiated requests; capability guards via M11.
- **Communication.** Calls down to M11; runs middleware pipeline around the engine boundary; uses M5c metadata, M3/M4 for elicitation schema handling.

---

### Auth modules (cross-layer, `mcp/core/shared/auth.rkt`, `mcp/client/auth.rkt`, `mcp/server/auth/`)

#### M14. Auth
- **Purpose/scope.**
  - *Shared* (M5d, `core/shared/auth.rkt`): `AuthInfo`, token/metadata helpers.
  - *Client OAuth* (`client/auth.rkt`): OAuth 2.0 authorization-code + PKCE, token storage/refresh, cross-app access. Mirrors `client/auth.ts` + `authExtensions.ts` + `crossAppAccess.ts`.
  - *Server verification* (`server/auth/`): bearer-token verification provider interface, client registry, auth error responses. (Legacy-SSE auth-router excluded per §8 vision.)
- **Interfaces.**
  - *External — Client OAuth flow interface.* Begin authorize, exchange code, refresh, persist tokens (never log secrets; Security NFR).
  - *External — Server token-verifier port.* Pluggable verifier: token → `AuthInfo` or auth error; client registry.
- **Communication.** Client OAuth: HTTP via `net/url`/`net/http-client`; tokens attach to HTTP transport (M8) outbound headers. Server: M8 extracts bearer → verifier port → `AuthInfo` placed in engine handler context (M11).

---

### L4 — Application surface

#### M15. Examples (`mcp/examples/`)
- **Purpose/scope.** Runnable mirrors of TS `examples/`: stdio server, stateful + stateless HTTP server, OAuth server, basic client, parallel tool calls.
- **Interfaces.** *External:* executable entry points (`raco`/`racket` run).
- **Communication.** Consume public APIs of M12/M13 + transports M7/M8/M9.

#### M16. Documentation (`mcp/scribblings/`)
- **Purpose/scope.** Scribble docs replacing TypeDoc; every public binding documented; example snippets compile (`@examples`).
- **Interfaces.** *External:* Scribble doc build target (`raco scribble` / `raco docs`).
- **Communication.** References public `provide`s of all collections; doc snippets run as a compile-time conformance check.

#### M17. Conformance & test harness (`*/test/`, conformance suite)
- **Purpose/scope.** `rackunit` unit tests + ported cross-SDK conformance suite for both spec revisions × both transports × both roles. Backs success criteria §9 + parity matrix §9 vision.
- **Interfaces.** *External:* `raco test` targets; conformance runner driving in-memory + real transports; interop harness against TS SDK + MCP Inspector.
- **Communication.** Drives public role APIs over M10 (in-memory) and M7/M8 (real); asserts byte-for-byte JSON-RPC parity.

---

## 3. Interface Map

### 3.1 Dependency direction (who imports whom)

Arrows = "depends on / calls". Lower layers never import higher ones.

```
examples (M15) ─┬─> client (M13) ─┐
                └─> server (M12) ─┤
docs (M16) ─────────> [all public provides]
tests (M17) ────────> client/server/transports

client (M13) ──┐
server (M12) ──┼─> protocol engine (M11) ─> transport port (M6)
               │                                   ▲
               ├─> validators (M3), schema (M4)    │ implements
               ├─> shared utils (M5a-e)      ┌─────┴───────────────┐
               └─> errors (M2), types (M1)   │ stdio(M7) http(M8)  │
                                             │ in-mem(M10)         │
auth: client/auth(M14)─> http(M8)            └─────────────────────┘
      server/auth(M14)─> engine context(M11) web-server(M9)─> http(M8)

ALL modules ──> types (M1), errors (M2)        [foundation, no deps up]
```

### 3.2 Data-flow paths (runtime, external communication between modules)

| # | Flow | Path | Pattern |
|---|------|------|---------|
| F1 | **Inbound request** (e.g. `tools/call` at a server) | transport adapter (M7/M8/M10) → on-message callback → engine (M11) dispatch by method → role handler (M12) → validate input (M3/M4) → user tool fn → result → engine → `send` → transport | event-driven in, sync call chain, async result out |
| F2 | **Outbound request** (e.g. client `call-tool`) | client API (M13) → middleware pipeline → engine `request` (M11) assigns id, registers resolver, sets timeout/cancel → transport `send` (M6) → … later inbound response → engine correlates id → resolves channel → returns to caller | async request/response over channel/`sync` |
| F3 | **Server-initiated request** (sampling/elicitation) | server handler context `send-request` (M11) → transport `send` → client engine dispatch → client sampling/elicitation handler (M13) → response back | reverse of F2; same engine, concurrent |
| F4 | **Notification** (list-changed, logging, progress, cancel) | emitter (M12/M13) or engine → engine `notification` → transport `send`; inbound notifications → engine dispatch → notification handler | fire-and-forget event |
| F5 | **HTTP serving** | `web-server` request → adapter (M9) → http transport server handling (M8) → on-message → engine (M11); response/SSE streamed back out | adapter bridge + streaming |
| F6 | **Client OAuth** | client (M13) → client-auth (M14) OAuth flow over HTTP → tokens stored → attached to M8 outbound headers | sync HTTP flow + token store |
| F7 | **Server auth** | http transport (M8) extracts bearer → server-auth verifier port (M14) → `AuthInfo` → engine handler context (M11) → available to user handler | port call, context injection |
| F8 | **Schema advertisement + validation** | register-tool (M12b) → schema normalize (M4) → emits wire JSON Schema (advertised in `tools/list`) + validation handle (M3 provider) applied on inbound `tools/call` | sync; dependency-inversion via provider port |
| F9 | **Resource subscription + update** (J1) | inbound `resources/subscribe` → M12b records (session, uri) in per-session subscription table; later a registered resource changes → M12b resource-updated emitter checks table → engine `notification` `notifications/resources/updated` → transport `send` to each subscribed session only; `resources/unsubscribe`/session-close removes entries | event-driven notify, session-scoped fan-out |
| F10 | **Paginated list** (J2) | client list verb (M13) with optional cursor → engine `request` → M12b slices registry from inbound opaque cursor → returns page + `nextCursor` → client follows cursor until exhausted | request/response, opaque-cursor loop |

### 3.3 Internal vs external communication summary

| Module | Internal comms (within) | External comms (across boundaries) |
|--------|-------------------------|-------------------------------------|
| M1 Types | versioned-spec → normalization façade | data imported by all (by reference) |
| M2 Errors | — | raised/caught everywhere; serialized at protocol edge |
| M3 Validators | default provider impls port | provider port called by M4/M12/M13 |
| M4 Schema | — | normalize for M12; delegates to M3 |
| M5 Shared | per-module helpers (M5a/M5b/M5c pure functions; M5d holds auth-info structs; M5e does byte-stream framing I/O) | imported by M7,M8,M11,M12,M13,M14 |
| M6 Transport port | — | implemented by M7/M8/M10; called by M11 |
| M7 stdio | M5e framing + ports | implements M6; OS subprocess/ports |
| M8 HTTP | HTTP/SSE/session internals | implements M6; consumes M9 reqs; calls M14 verifier; net client |
| M9 web-server | — | bridges `web-server` ↔ M8 |
| M10 in-memory | paired channels | implements M6; used by M17 |
| M11 Engine | in-flight registry, scheduler, threads | port M6 (send/callbacks); handler reg + context to M12/M13 |
| M12 Server | engine-binding, completions wiring, per-session subscription table + logging-level filter | registration/notification API (incl. paginated lists + resource-updated) to users; down to M11,M3,M4,M5 |
| M13 Client | engine-binding, middleware pipeline | client API + handler hooks to users; down to M11,M3,M4,M5 |
| M14 Auth | OAuth state, token store, registry | client→HTTP+M8; server→M8+M11 context |
| M15 Examples | — | use M12/M13/M7/M8/M9 public APIs |
| M16 Docs | — | reference all public provides |
| M17 Tests | conformance runner | drive M12/M13 over M10/M7/M8; interop with TS SDK |

### 3.4 Scope-coverage trace (vision §4 / Appendix A → modules)

| Vision feature | Module(s) |
|----------------|-----------|
| 4.1 Protocol & types layer | M1, M11 |
| 4.2 Transport abstraction | M6, M7, M8, M10 (+M5e) |
| 4.3 High-level server API | M12 (+M5a,M5b,M4,M3) |
| 4.4 High-level client API | M13 |
| 4.5 Validation | M3, M4 |
| 4.6 Authentication | M14 (+M5d) |
| 4.7 Transport/framework adapters | M9 |
| 4.8 Errors | M2 |
| 4.9 Examples & docs | M15, M16 |
| (NFR) conformance/interop | M17 |
| `_meta` envelope | M5c |
| URI templates / tool-name validation | M5a / M5b |
| Resource subscriptions + `notifications/resources/updated` (J1, §9.4) | M12b (per-session subscription table + resource-updated emitter); M13 (subscribe/unsubscribe verbs) |
| List pagination / opaque cursors (J2, G1/G2) | M12b (produces `nextCursor`) ; M13 (consumes/follows cursor) |
| ping keepalive (S2) / logging-level filtering (S3) | M12a answers `ping` + owns `logging/setLevel`; M12b applies per-session level filter; M13 issues `ping` |

Every vision feature + Appendix-A capability maps to ≥1 module; every module traces to vision scope. Excluded (§8 vision): codemod, server-legacy SSE, per-framework middleware, external schema libs, multi-runtime shims, embedded LLM client — **no module created** for these by design.

---

## 4. Tech Stack

| Concern | Choice | Reasoning |
|---------|--------|-----------|
| Language / runtime | Racket CS, `#lang racket`, Racket ≥ 8.x | Target runtime; green threads + contracts fit MCP's concurrent, validated message handling. |
| SDK type validation | `racket/contract` + structs | Native, idiomatic, zero external dep; guards wire input before user handlers (Security NFR). Replaces Zod. |
| User-schema validation | JSON-Schema provider port + Racket-native default | Tool/resource/prompt schemas are JSON Schema on the wire; one provider suffices (collapses Ajv/cfWorker). Port allows future swap. |
| User-schema input form | `racket/contract` flat contract *or* JSON Schema, normalized | Idiomatic dual entry; Standard-Schema analogue without JS libs. |
| JSON | `json` (`read-json`/`write-json`) | Standard library; byte-for-byte JSON-RPC parity is the perf-dominant path. |
| Concurrency | Racket threads, channels, `sync`/events, custodians | Green threads map onto concurrent + server-initiated requests with no head-of-line blocking; custodian/`cancel-evt` for cancellation/timeout. |
| stdio transport | `racket/system` `subprocess` + ports | Standard library; isolated in M7 to keep core portable. |
| HTTP server | `web-server` (built-in) | First-party, dependency-light; single adapter vs TS's many. |
| HTTP client | `net/http-client` / `net/url` | Standard library; covers client HTTP + OAuth flows. |
| SSE streaming | manual SSE over `web-server` streaming responses | Streamable HTTP requires server-sent events; `web-server` supports chunked/streaming output. |
| Packaging | `raco pkg` collections under `mcp` | Native package manager; 1:1 with TS package layout for parity matrix. |
| Docs | Scribble (`@examples`) | Native; compiling snippets double as conformance checks. |
| Tests | `rackunit` + ported conformance suite | Native test framework; conformance/interop = central objective. |
| Dependencies | Standard library only for core/protocol/types/transports; optional dev: JSON-Schema lib (else hand-rolled subset), `rackunit`, `scribble` | Minimal-dependency NFR; each third-party dep must be justified. |
| Module system | `mcp` collection + sub-collections; `main.rkt` public barrels; `racket/generic` for ports (`gen:transport`, validator/verifier providers); composition for roles | Mirrors TS public/internal boundary + ports-and-adapters; idiomatic Racket (no class transliteration, G4). |

### 4.1 Cross-cutting decisions

- **Ports via `racket/generic`.** `gen:transport`, validator provider, and server token-verifier are generic interfaces enabling dependency inversion + test doubles (M10, mock verifiers).
- **Composition over inheritance (S1 — invariant).** Roles (M12/M13) **hold** an engine (M11) instance by composition + `racket/generic`; the engine is never subclassed and roles never reach into engine internals. The only engine↔role coupling is the public outbound/handler-registration/handler-context interfaces (M11). This is a hard invariant, not a stylistic preference — idiomatic Racket, mirrors TS behavior without JS class-isms (G4).
- **Versioned-spec normalization seam (N1 — strategy).** M1 hides `2025-11-25` vs `2026-07-28` behind a **normalized-superset façade**: handlers see one internal shape that is the union of both revisions, with revision-only fields (e.g. the 2026-07-28 `_meta` envelope via M5c, URL-mode elicitation / `UrlElicitationRequired`) present-or-absent and gated by the negotiated version. Handlers therefore operate version-agnostically; the engine negotiates the version once at `initialize` and the façade refuses to emit a field absent from the negotiated revision (preserving wire parity). Version-tagged variants are *not* exposed to handlers — only the superset is.
- **Runtime-neutral core.** L0–L2 import no subprocess/socket modules; all non-portable I/O confined to L1 adapters (Portability NFR).
- **Error-to-wire boundary.** M2 owns the single conversion point exn↔JSON-RPC error so malformed input never crashes the engine (Reliability NFR).

---

## 5. Open Structural Questions (for later steps, not blocking)

- Exact granularity of `server/auth/` sub-modules (verifier vs registry vs router) — deferred to roadmap.
- Whether the JSON-Schema default provider hand-rolls a subset or adopts a vetted Racket lib — a dependency-justification decision (Minimal-deps NFR), not a structural one.
- Resumption-token **storage backend** for resumable SSE (in-memory vs pluggable store) — an M8 internal detail. (The mint/validate *interface obligation* is fixed in M8, N2; only the backend is deferred.)
- Roadmap sequencing of the M12 sub-modules (N3): M12a low-level `Server` is separable and a prerequisite for M12b high-level `McpServer`; M12c completable layers on M12b. The roadmap should treat these as distinct, independently-shippable units.

These are *what-not-yet-decided* items; none change the module/interface decomposition above.
