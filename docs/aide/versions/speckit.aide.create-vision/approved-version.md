# Vision: `racket-mcp` — A Model Context Protocol SDK for Racket

> **Status:** Living vision document.
> **Reference implementation:** [MCP TypeScript SDK v2.0.0-alpha](https://github.com/modelcontextprotocol/typescript-sdk) (checked out locally at `typescript-sdk/`).
> **Target MCP spec revisions:** `2025-11-25` (latest stable) and `2026-07-28` (release candidate).
> **Last updated:** 2026-06-14.

---

## 1. Project Overview

### 1.1 What

`racket-mcp` is a complete, idiomatic implementation of the [Model Context Protocol](https://modelcontextprotocol.io) (MCP) for the **Racket** programming language. It lets Racket programs act as MCP **servers** (exposing tools, resources, and prompts to LLM applications) and as MCP **clients** (consuming those capabilities from other servers, and providing sampling/elicitation/roots back to servers).

MCP is a JSON-RPC 2.0–based protocol that standardizes how applications supply context to large language models, cleanly separating *context provision* from *LLM interaction*. The protocol defines a small, versioned set of primitives — tools, resources, prompts, sampling, elicitation, roots, completion, logging — carried over pluggable transports (stdio and Streamable HTTP).

This SDK **strictly mirrors the architecture of the official MCP TypeScript SDK (v2)**, translated into Racket idioms. Where the TS SDK uses a pnpm monorepo of packages (`core`, `client`, `server`, `middleware`, `server-legacy`, `codemod`), `racket-mcp` uses a corresponding set of Racket collections under a single `mcp` collection namespace. Where TS uses Zod/Standard Schema and Ajv for validation, `racket-mcp` uses `racket/contract`, structs, and a pluggable JSON-Schema validator. The wire protocol, type definitions, capability negotiation, transport semantics, and high-level helper APIs are intended to be **behaviorally identical** so that a `racket-mcp` server interoperates with any MCP client (Claude Desktop, the TS/Python SDKs, the MCP Inspector) and vice versa.

### 1.2 Why

- **No first-class MCP SDK exists for Racket.** Racket is a strong fit for MCP servers: it has excellent JSON support, a mature contract system, green-thread concurrency, a web server stack, and a tradition of language tooling — all of which map naturally onto MCP's primitives. The Racket and broader Lisp/Scheme community currently has no maintained path to expose tools and data to LLM applications via the standard protocol.
- **Mirroring the TS SDK de-risks design.** The TS SDK is the de-facto reference (alongside the Python SDK). By tracking its v2 architecture closely, `racket-mcp` inherits a battle-tested module decomposition, a clear public/internal API boundary, and a known-correct interpretation of an evolving spec — instead of reinventing those decisions.
- **Interoperability is the whole point of a protocol.** A Racket SDK only delivers value if Racket programs can talk to the existing MCP ecosystem. Conformance to the published spec revisions and to the reference clients is therefore the central objective, not an afterthought.

---

## 2. Goals & Objectives

All objectives are phrased to be measurable and verifiable.

| # | Objective | Measure of success |
|---|-----------|--------------------|
| G1 | **Wire-protocol parity** with MCP spec `2025-11-25` and `2026-07-28`. | Every request, response, notification, and error type in both spec revisions has a corresponding Racket struct + contract, exercised by a conformance suite. |
| G2 | **Interoperate with reference clients.** | A `racket-mcp` server passes the MCP Inspector connection flow and is callable from the TS SDK client over both stdio and Streamable HTTP; a `racket-mcp` client drives a TS SDK example server. |
| G3 | **Architectural mirror of TS SDK v2.** | Collection layout maps 1:1 to the TS package layout (see §5.2); a parity matrix (see §9) tracks each TS module against its Racket counterpart. |
| G4 | **Idiomatic Racket public API.** | High-level server/client APIs use `racket/contract`, keyword arguments, and structs; no literal transliteration of JS classes. Reviewed against Racket style conventions. |
| G5 | **Two transports at parity.** | stdio and Streamable HTTP transports both pass the conformance suite for client and server roles. |
| G6 | **Capability-correct protocol layer.** | Capability negotiation, request/response correlation, progress, cancellation, and timeouts behave identically to the TS `Protocol` class, verified by ported protocol tests. |
| G7 | **Installable via the Racket package system.** | `raco pkg install mcp` (or sub-collections) succeeds on a clean Racket install; documentation builds with Scribble. |
| G8 | **OAuth support for HTTP transport.** | Client-side OAuth 2.0 authorization-code + token-refresh flow and server-side bearer-token verification implemented and tested against the spec's auth model. |

---

## 3. Target Users

| User | Who they are | How they use `racket-mcp` |
|------|--------------|---------------------------|
| **Racket tool authors** | Developers who want to expose Racket functions, datasets, or DSLs to LLM apps. | Use the high-level `mcp/server` API (`register-tool`, `register-resource`, `register-prompt`) and run over stdio for local use or Streamable HTTP for remote. |
| **LLM application developers** | Builders of agents/assistants in Racket who need to consume external MCP servers. | Use the `mcp/client` API (`call-tool`, `list-tools`, `read-resource`, `get-prompt`) plus sampling/elicitation/roots handlers. |
| **Integration engineers** | Teams wiring MCP servers into existing Racket web services. | Use transport adapters that mount the Streamable HTTP handler onto `web-server` (and optionally other Racket HTTP stacks). |
| **Educators & researchers** | People teaching protocol design, language tooling, or agentic systems in a Lisp setting. | Read the Scribble docs and runnable examples; the close TS mirror doubles as a Rosetta-stone reference. |
| **SDK contributors** | Maintainers extending the SDK as the MCP spec evolves. | Rely on the parity matrix and the mirrored module layout to locate the Racket analogue of any TS change. |

---

## 4. Core Features

Each feature below maps an MCP/TS SDK capability to its Racket equivalent. Naming uses Racket conventions (kebab-case, predicates ending in `?`, mutators ending in `!`).

### 4.1 Protocol & Types Layer (mirrors `core/types`, `core/shared/protocol`)

- **JSON-RPC 2.0 message layer.** Requests, responses, notifications, batch handling, error responses with the JSON-RPC + MCP error codes (`ParseError -32700` … `InvalidParams -32602`, plus MCP-specific `ResourceNotFound -32002`, `MissingRequiredClientCapability -32003`, `UnsupportedProtocolVersion -32004`, `UrlElicitationRequired -32042`). → Racket structs + contracts in `mcp/core/types`, mirroring `types/constants.ts`, `types/enums.ts`, `types/types.ts`.
- **Versioned spec types.** Both `spec.types.2025-11-25` and `spec.types.2026-07-28` represented, with the supported-version list and negotiation defaults (`LATEST = 2025-11-25`, `DEFAULT_NEGOTIATED = 2025-03-26`, plus the full `SUPPORTED_PROTOCOL_VERSIONS`). → `mcp/core/types/spec-2025-11-25.rkt`, `spec-2026-07-28.rkt`.
- **Per-request `_meta` envelope (2026-07-28).** Reserved keys for protocol version, client info, client capabilities, related-task, and (deprecated) log level. → constants module + helpers in `mcp/core/shared/metadata-utils.rkt`.
- **Abstract `Protocol`.** Message routing, request/response correlation, capability negotiation, progress callbacks, cancellation, timeouts, and transport lifecycle — the shared base that both client and server build on. → a Racket unit/struct-with-generics `protocol` in `mcp/core/shared/protocol.rkt`; `client` and `server` extend it via composition or `racket/generic`.
- **Type guards / predicates.** `is-jsonrpc-request?`, `is-jsonrpc-notification?`, etc. → `mcp/core/types/guards.rkt`.

### 4.2 Transport Abstraction (mirrors `core/shared/transport`, `stdio`)

- **`Transport` interface** — `start`, `send` (with `relatedRequestId`, resumption-token support), `close`, and `onmessage`/`onclose`/`onerror` callbacks. → a Racket interface (`racket/generic` `gen:transport`) in `mcp/transport/transport.rkt`.
- **stdio transport** (local subprocess integrations). → `mcp/transport/stdio.rkt` (server + client), using Racket subprocess + ports.
- **Streamable HTTP transport** (recommended for remote; supports SSE streaming, session IDs, resumable streams). → `mcp/transport/streamable-http.rkt` (server + client).
- **In-memory transport** for tests and same-process wiring (mirrors `core/util/inMemory`). → `mcp/transport/in-memory.rkt`.

### 4.3 High-Level Server API (mirrors `server/mcp`, `server/server`)

- **`McpServer`** with `register-tool`, `register-resource` (static URI and URI-template), `register-prompt`, each returning a handle supporting `enable`/`disable`/`update`/`remove`. → `mcp/server/mcp.rkt`.
- **Low-level `Server`** for direct request-handler registration. → `mcp/server/server.rkt`.
- **Completions** for prompt/resource-template arguments (mirrors `server/completable`). → `mcp/server/completable.rkt`.
- **List-changed notifications** (`sendToolListChanged`, `sendResourceListChanged`, `sendPromptListChanged`) and `sendLoggingMessage`.
- **URI templates** (RFC 6570 subset) for parameterized resources (mirrors `core/shared/uriTemplate`). → `mcp/core/shared/uri-template.rkt`.
- **Tool-name validation** (mirrors `core/shared/toolNameValidation`). → `mcp/core/shared/tool-name-validation.rkt`.

### 4.4 High-Level Client API (mirrors `client/client`)

- **`Client`** with `connect`, `ping`, `list-tools`, `call-tool`, `list-resources`, `list-resource-templates`, `read-resource`, `subscribe-resource`/`unsubscribe-resource`, `list-prompts`, `get-prompt`, `complete`, `set-logging-level`, capability/version accessors, and `send-roots-list-changed`. → `mcp/client/client.rkt`.
- **Sampling** — client handles server-initiated `sampling/createMessage`. → handler hooks in the client.
- **Elicitation** — client handles `elicitation/create` in form and URL modes, applying schema defaults. → `mcp/client/client.rkt` + elicitation helpers.
- **Roots** — client exposes filesystem roots via `roots/list`.
- **Client middleware** — request/response interception pipeline (mirrors `client/middleware`, distinct from framework adapters). → `mcp/client/middleware.rkt`.

### 4.5 Validation (mirrors `core/validators`, `core/util/schema`)

- **Contract-based validation** replaces Zod for the SDK's own protocol types. → `racket/contract` throughout `mcp/core/types`.
- **Pluggable JSON-Schema validator** for *user-supplied* tool input/output schemas (tools advertise JSON Schema on the wire). A provider interface mirrors `validators/types.ts` with a default implementation. → `mcp/core/validators/` with `from-json-schema.rkt` and a default provider; the Ajv/cfWorker split is collapsed to a single Racket-native provider (see §8).
- **Standard-Schema analogue.** The TS SDK accepts any Standard Schema library for tool schemas. The Racket equivalent accepts either a `racket/contract` flat contract *or* a JSON Schema, normalized internally (mirrors `core/util/standardSchema`). → `mcp/core/util/schema.rkt`.

### 4.6 Authentication (mirrors `core/shared/auth`, `client/auth`, `server-legacy/auth`)

- **Shared auth types & utilities** — `AuthInfo`, token/metadata helpers (mirrors `core/shared/auth`, `authUtils`). → `mcp/core/shared/auth.rkt`.
- **Client OAuth 2.0** — authorization-code flow, PKCE, token storage/refresh, cross-app access (mirrors `client/auth`, `authExtensions`, `crossAppAccess`). → `mcp/client/auth.rkt`.
- **Server bearer-token verification** — provider interface, client registry, error responses (mirrors the OAuth server pieces). → `mcp/server/auth/` (see §8 for the legacy-SSE auth-router exclusion).

### 4.7 Transport/Framework Adapters (mirrors `middleware/*`)

- **`web-server` adapter** — mount the Streamable HTTP handler on Racket's built-in `web-server` (the analogue of `@modelcontextprotocol/node`). → `mcp/transport/web-server.rkt`.
- The TS Express/Hono/Fastify adapters are runtime-specific thin wrappers; their Racket analogue is a single first-party `web-server` adapter, with the door open to community adapters for other Racket HTTP stacks (see §8).

### 4.8 Errors (mirrors `core/errors/sdkErrors`, `core/auth/errors`)

- **`SdkError`** hierarchy with stable error codes, plus `ProtocolError` for wire-level errors. → `mcp/core/errors.rkt` using Racket `exn` subtypes (`exn:fail:mcp`, `exn:fail:mcp:protocol`, `exn:fail:mcp:auth`).

### 4.9 Examples & Documentation

- Runnable examples mirroring `examples/` (stdio server, stateful/stateless HTTP server, OAuth server, basic client, parallel tool calls). → `mcp/examples/`.
- Scribble documentation, replacing TS's TypeDoc, with executable doc snippets where practical (the TS SDK enforces `@example` snippets compile; the Racket analogue uses Scribble `@examples`).

---

## 5. Technical Architecture

### 5.1 Tech Stack

| Concern | TS SDK choice | `racket-mcp` choice | Rationale |
|---------|---------------|---------------------|-----------|
| Language / runtime | TypeScript on Node/Bun/Deno | Racket CS (`#lang racket`), Racket ≥ 8.x | Target runtime for the SDK. |
| Validation of SDK types | Zod v4 | `racket/contract` + structs | Native, idiomatic, no external dep. |
| User-schema validation | Standard Schema + Ajv / cfWorker | JSON-Schema provider interface (Racket-native default) | Tool schemas are JSON Schema on the wire; one provider suffices. |
| JSON | `JSON.parse`/stringify | `json` (`read-json`/`write-json`) | Standard library. |
| Concurrency | Promises / async | Racket threads, channels, `sync`/events | Green threads map cleanly onto MCP's concurrent request handling. |
| HTTP server | external frameworks via middleware | `web-server` (built-in) | First-party, dependency-light. |
| HTTP client | `fetch` | `net/http-client` / `net/url` | Standard library. |
| Subprocess (stdio) | `cross-spawn` / `node:child_process` | `racket/system` `subprocess`, ports | Standard library. |
| Packaging | pnpm monorepo | `raco pkg` collections under `mcp` | Native package manager. |
| Docs | TypeDoc | Scribble | Native documentation tooling. |
| Tests | Vitest + conformance suite | `rackunit` + ported conformance suite | Native test framework. |

### 5.2 Collection Layout (mirrors the TS monorepo)

A single top-level `mcp` collection with sub-collections mapped to TS packages:

```
mcp/
  core/                  ; ↔ packages/core
    types/               ; ↔ core/src/types
      constants.rkt        ; ↔ constants.ts
      enums.rkt            ; ↔ enums.ts (error codes)
      guards.rkt           ; ↔ guards.ts (predicates)
      types.rkt            ; ↔ types.ts (public protocol types)
      spec-2025-11-25.rkt  ; ↔ spec.types.2025-11-25.ts
      spec-2026-07-28.rkt  ; ↔ spec.types.2026-07-28.ts
    shared/              ; ↔ core/src/shared
      protocol.rkt         ; ↔ protocol.ts (abstract Protocol)
      transport.rkt        ; ↔ transport.ts (gen:transport)
      stdio.rkt            ; ↔ stdio.ts (framing helpers)
      uri-template.rkt     ; ↔ uriTemplate.ts
      tool-name-validation.rkt ; ↔ toolNameValidation.ts
      metadata-utils.rkt   ; ↔ metadataUtils.ts
      auth.rkt             ; ↔ auth.ts + authUtils.ts
    errors.rkt           ; ↔ errors/sdkErrors.ts + auth/errors.ts
    validators/          ; ↔ core/src/validators
      provider.rkt         ; ↔ validators/types.ts
      from-json-schema.rkt ; ↔ fromJsonSchema.ts
    util/                ; ↔ core/src/util
      schema.rkt           ; ↔ schema.ts + standardSchema.ts
      in-memory.rkt        ; ↔ inMemory.ts
  transport/             ; (Racket grouping of transport impls)
    stdio.rkt            ; ↔ {client,server}/stdio.ts
    streamable-http.rkt  ; ↔ {client,server}/streamableHttp.ts
    in-memory.rkt        ; ↔ util/inMemory.ts
    web-server.rkt       ; ↔ middleware/node (+ express/hono adapters, collapsed)
  client/                ; ↔ packages/client
    client.rkt           ; ↔ client/client.ts
    middleware.rkt       ; ↔ client/middleware.ts
    auth.rkt             ; ↔ client/auth.ts + authExtensions.ts + crossAppAccess.ts
  server/                ; ↔ packages/server
    server.rkt           ; ↔ server/server.ts (low-level)
    mcp.rkt              ; ↔ server/mcp.ts (high-level McpServer)
    completable.rkt      ; ↔ server/completable.ts
    auth/                ; ↔ OAuth server pieces
  examples/              ; ↔ examples/
  scribblings/           ; ↔ TypeDoc docs
```

**Public/internal boundary.** The TS SDK separates an internal barrel (`core`, `private`) from a curated public surface (`core/public`, re-exported by `client`/`server`). `racket-mcp` mirrors this: each sub-collection's `main.rkt` is the curated public API (explicit `provide`), while internal modules are `provide`d only to sibling modules within the collection. Modules that touch non-portable facilities (subprocess, sockets) live behind named submodules/paths so the core types/protocol stay free of such dependencies — mirroring the TS rule that the root entry must remain runtime-neutral.

### 5.3 Protocol Layer Details

The abstract protocol implements (mirroring `protocol.ts`):

- Outbound: `request` (correlate by id, register response handler, apply timeout, support progress callback, cancellation) and `notification`.
- Inbound: dispatch on method to registered request/notification handlers; build a handler context carrying `signal` (cancellation), `send-notification`/`send-request` (for server-initiated requests like sampling/elicitation), `request-id`, session info, and HTTP transport info (absent for stdio).
- Capability negotiation on `initialize`; `assert-capability-for-method` style checks before issuing/serving a request.
- Protocol-version negotiation against `SUPPORTED_PROTOCOL_VERSIONS`, surfacing `UnsupportedProtocolVersion` when needed.

Concurrency uses Racket threads: each in-flight request is tracked in a hash keyed by request id; responses resolve via channels/`sync`; cancellation is propagated through a `cancel-evt`/custodian.

### 5.4 Dependencies

- **Standard library only** for the core, protocol, types, JSON, stdio subprocess, HTTP client/server (`json`, `racket/system`, `net/url`, `net/http-client`, `web-server`).
- **Optional/dev:** a JSON-Schema validation library if one is adopted for the default provider (otherwise hand-rolled subset); `rackunit` for tests; `scribble` for docs. Minimizing third-party deps is a deliberate non-functional goal (§6).

---

## 6. Non-Functional Requirements

- **MCP spec compatibility.** Must implement and negotiate `2025-11-25` and `2026-07-28`, and accept the older versions in `SUPPORTED_PROTOCOL_VERSIONS` for negotiation/back-compat exactly as the TS SDK lists them.
- **Interoperability.** Byte-for-byte JSON-RPC compatibility with reference implementations; verified by cross-SDK conformance tests.
- **Concurrency.** The protocol layer must handle concurrent in-flight requests and server-initiated requests without head-of-line blocking, using Racket threads and synchronizable events; no shared mutable state without proper synchronization.
- **Performance.** stdio round-trip and HTTP request handling overhead should be dominated by JSON parsing, not SDK bookkeeping; large resource payloads streamed where the transport allows (SSE). Establish a baseline benchmark (tool call latency) and prevent regressions.
- **Security.** Streamable HTTP transport validates `Host`/`Origin` headers (DNS-rebinding protection, as the TS middleware does), enforces session-id handling, and supports bearer-token auth. OAuth client stores tokens securely and never logs secrets. Input from the wire is validated by contract before reaching user handlers.
- **Reliability.** Resumable HTTP streams (resumption tokens), request timeouts, and cancellation must be honored. Malformed messages produce correct JSON-RPC error responses, never crashes.
- **Portability.** Core types/protocol must load without pulling in subprocess/socket modules, so they remain usable in restricted contexts (mirrors TS runtime-neutral root rule).
- **Minimal dependencies.** Prefer the Racket standard library; each added third-party dependency must be justified.
- **Documentation completeness.** Every public binding has a Scribble doc entry; examples compile.

---

## 7. Constraints & Assumptions

**Constraints**
- Must follow MCP spec revisions `2025-11-25` and `2026-07-28` and remain wire-compatible with the TS SDK v2.
- Must mirror the TS SDK's architecture/module decomposition closely enough that the parity matrix (§9) maps cleanly.
- Public API must be idiomatic Racket (contracts, keywords, structs), not a JS transliteration.
- The TS SDK v2 is pre-alpha and the `2026-07-28` spec is a release candidate; both are moving targets, so the SDK must track changes.

**Assumptions**
- Target is Racket CS (Racket ≥ 8.x); the standard library provides adequate JSON, subprocess, threading, and HTTP support.
- Tool/resource/prompt schemas crossing the wire are JSON Schema (per spec); the SDK validates user data against them via the pluggable provider.
- Consumers run trusted server code locally (stdio) or behind their own auth for remote HTTP, with the SDK providing the auth primitives.
- The TS SDK checkout at `typescript-sdk/` is the authoritative reference for any ambiguity.

---

## 8. Out of Scope (with reasons)

| Excluded | Reason |
|----------|--------|
| **`codemod` package equivalent** | The TS `codemod` package automates v1→v2 *TypeScript* migration. `racket-mcp` has no prior version to migrate from; there is nothing to codemod. Revisit only if a future breaking `racket-mcp` release warrants migration tooling. |
| **`server-legacy` (HTTP+SSE legacy transport)** | The deprecated standalone HTTP+SSE transport exists in TS purely for backwards compatibility with pre-Streamable-HTTP servers. A greenfield Racket SDK should ship the recommended Streamable HTTP transport (which subsumes SSE streaming) and skip the legacy variant. Document the decision; reconsider only if real interop with legacy-only servers is required. |
| **Per-framework middleware packages (Express/Hono/Fastify)** | These are Node/JS-ecosystem-specific thin adapters. The Racket analogue is a single first-party `web-server` adapter; other Racket HTTP stacks can be supported by community adapters rather than first-party packages. |
| **Zod / Standard Schema library compatibility** | TS accepts arbitrary Standard Schema libraries because the JS ecosystem has many. Racket's idiom is `racket/contract` plus JSON Schema; supporting external JS schema libraries is meaningless here. |
| **Browser / Cloudflare Workers / Deno runtime targets** | TS maintains shims (`shimsBrowser`, `shimsWorkerd`) and a cfWorker validator for non-Node runtimes. Racket has one primary runtime; the multi-runtime shim layer and cfWorker validator are unnecessary. |
| **Bundling the LLM interaction itself** | MCP deliberately separates context provision from LLM calls. The SDK provides sampling/elicitation *plumbing* but does not embed any model client. |

---

## 9. Success Criteria

The project is successful when all of the following hold:

1. **Parity matrix complete.** A maintained matrix maps every TS SDK module (per §5.2) to its Racket counterpart, with status `done / partial / intentionally-excluded`. All non-excluded rows reach `done`. (Satisfies G3.)
2. **Conformance suite passes** for both spec revisions, both transports (stdio, Streamable HTTP), and both roles (client, server) — ported from / aligned with the TS `test-conformance` suite. (G1, G5, G6.)
3. **Cross-SDK interop demonstrated:**
   - A `racket-mcp` server connects to the MCP Inspector and is driven by a TS SDK client over stdio and HTTP. (G2.)
   - A `racket-mcp` client successfully calls tools/resources/prompts on a TS SDK example server. (G2.)
4. **All MCP primitives implemented:** tools, resources (static + templated), prompts, sampling, elicitation (form + URL), roots, completion, logging, progress, cancellation — each with passing tests. (Core of G1.)
5. **OAuth flows work:** client authorization-code + refresh, server bearer verification, against the spec auth model. (G8.)
6. **Installable & documented:** `raco pkg install` succeeds on a clean install; Scribble docs build with every public binding documented and example snippets compiling. (G7.)
7. **Idiomatic API confirmed:** public API review confirms contract-guarded, keyword-driven, struct-based design with no JS-isms. (G4.)
8. **Runnable examples** mirroring the TS examples set run end-to-end (stdio server, stateful/stateless HTTP server, OAuth server, basic + parallel client).

---

## Appendix A — TS SDK ↔ `racket-mcp` Capability Map (summary)

| MCP capability | TS location | `racket-mcp` location |
|----------------|-------------|------------------------|
| JSON-RPC + protocol types | `core/types/*` | `mcp/core/types/*` |
| Abstract Protocol | `core/shared/protocol.ts` | `mcp/core/shared/protocol.rkt` |
| Transport interface | `core/shared/transport.ts` | `mcp/transport/transport.rkt` (`gen:transport`) |
| stdio transport | `{client,server}/stdio.ts` | `mcp/transport/stdio.rkt` |
| Streamable HTTP transport | `{client,server}/streamableHttp.ts` | `mcp/transport/streamable-http.rkt` |
| In-memory transport | `core/util/inMemory.ts` | `mcp/transport/in-memory.rkt` |
| High-level server | `server/mcp.ts` | `mcp/server/mcp.rkt` |
| Low-level server | `server/server.ts` | `mcp/server/server.rkt` |
| High-level client | `client/client.ts` | `mcp/client/client.rkt` |
| Completions | `server/completable.ts` | `mcp/server/completable.rkt` |
| URI templates | `core/shared/uriTemplate.ts` | `mcp/core/shared/uri-template.rkt` |
| Validation provider | `core/validators/*` | `mcp/core/validators/*` |
| Errors | `core/errors/sdkErrors.ts` | `mcp/core/errors.rkt` |
| Client OAuth | `client/auth.ts`, `authExtensions.ts` | `mcp/client/auth.rkt` |
| Server auth | OAuth server pieces | `mcp/server/auth/` |
| Framework adapters | `middleware/*` | `mcp/transport/web-server.rkt` |
| codemod | `codemod/` | *excluded* (§8) |
| legacy SSE | `server-legacy/` | *excluded* (§8) |
