# Project Progress: `racket-mcp`

> **Status:** Living progress tracker. Initialized 2026-06-15.
> **Source vision:** `docs/aide/vision.md` (Goals G1–G8, Success Criteria §9).
> **Source roadmap:** `docs/aide/roadmap.md` (Stages S1–S9, modules M1–M17, layers L0–L4).
> **Reference impl:** MCP TypeScript SDK v2 (`typescript-sdk/`).
> **Last updated:** 2026-06-15.

## Legend

| Icon | Meaning |
|------|---------|
| 📋 | Planned — not started |
| 🚧 | In Progress |
| ✅ | Complete — delivered + acceptance criteria pass |
| ⏸️ | Deferred — intentionally postponed (note required) |
| ❌ | Excluded — out of scope (vision §8) |

**Baseline note.** As of initialization no SDK source exists (repo is the Specify template + AIDE docs). Every roadmap deliverable below starts at 📋. Update icons forward only — never revert a ✅/🚧/⏸️/❌ to 📋, and never uncheck a checked acceptance box.

---

## Stage status overview

| Stage | Theme | Modules | Layer | Status |
|-------|-------|---------|-------|--------|
| S1 | Types, constants, guards, errors | M1, M2 | L0 | 📋 |
| S2 | Validators, schema, shared utils | M3, M4, M5a–e | L0 | 📋 |
| S3 | Transport port + in-memory | M6, M10 | L1 | 📋 |
| S4 | Protocol engine | M11 | L2 | 📋 |
| S5 | MVP roles (low-level server + client), Racket-only interop | M12a, M13(core) | L3 | 📋 |
| S6a | Real transports + first cross-SDK leg | M7, M8, M9 | L1 | 📋 |
| S6b | High-level server (static surface) | M12b, M12c | L3 | 📋 |
| S7a | Client-driven primitives | M13 | L3 | 📋 |
| S7b | Server session-state primitives | M12b | L3 | 📋 |
| S8 | OAuth + bearer verification | M14 | cross | 📋 |
| S9 | Examples, docs, conformance, interop | M15, M16, M17 | L4 | 📋 |

---

## Stage S1 — Foundation: types, constants, guards, errors (L0 part 1) — 📋

**Modules:** M1 (Types), M2 (Errors).

### Deliverables
- ✅ `mcp/core/types/constants.rkt` — error codes + `LATEST`/`DEFAULT_NEGOTIATED`/`SUPPORTED_PROTOCOL_VERSIONS`
- ✅ `mcp/core/types/spec-2025-11-25.rkt` — per-revision structs + contracts (item 003)
- ✅ `mcp/core/types/spec-2026-07-28.rkt` — per-revision structs + contracts incl. `_meta` envelope (item 004)
- ✅ `mcp/core/types/types.rkt` — public types + N1 normalized-superset façade (item 005; 58 façade structs, normalize/denormalize seam, revision-parameterized dispatch)
- ✅ `mcp/core/types/guards.rkt` — JSON-RPC predicates (no batch guard, J3)
- ✅ `mcp/core/errors.rkt` — `exn:fail:mcp[:protocol|:auth]`; exn↔JSON-RPC **encode + decode** (item 006 encode + item 007 decode; complete)
- ✅ `mcp/core/types/main.rkt` + `mcp/core/main.rkt` barrels (item 008; `prefix-in r25:/r26:` on the two spec modules, per-module `all-from-out`, no new defines)
- 🚧 `mcp/core/types/test/` + `mcp/core/test/errors-test.rkt` (barrel + transitive portability + curation tests added by item 008 as `mcp/core/test/main-test.rkt`; demo + final closeout by item 009)

### Acceptance criteria
- [ ] `raco test` over `mcp/core/types/` + `mcp/core/errors.rkt` passes
- [x] Error codes + version constants match TS `constants.ts`/`enums.ts` byte-for-byte
- [ ] Each JSON-RPC envelope kind round-trips from TS fixture → struct → identical JSON (G1)
- [ ] Decode: `-32042` → `UrlElicitationRequired`; `-32004` → unsupported-version (vs TS `core/types/errors.ts`)
- [ ] Restricted-namespace load test: no subprocess/socket pulled in (Portability NFR)
- [ ] Parity rows `core/types/*`, `errors/*` marked `partial`
- [ ] Demo: parse `initialize`+`tools/call` from JSON, re-emit, malformed→JSON-RPC error

---

## Stage S2 — Foundation: validators, schema, shared utilities (L0 part 2) — 📋

**Modules:** M3 (Validators), M4 (Schema util), M5a–M5e (Shared).

### Deliverables
- 📋 `mcp/core/validators/provider.rkt` — `gen:`-style validator-provider port
- 📋 `mcp/core/validators/from-json-schema.rkt` — Racket-native default (keywords: `type`, `properties`, `required`, `enum`, `items`, `format` for `date-time`/`uri`/`email`)
- 📋 `mcp/core/util/schema.rkt` — contract-or-JSON-Schema normalization (Standard-Schema analogue)
- 📋 `mcp/core/shared/uri-template.rkt` (M5a) — RFC 6570 subset expand/match
- 📋 `mcp/core/shared/tool-name-validation.rkt` (M5b)
- 📋 `mcp/core/shared/metadata-utils.rkt` (M5c) — reserved `_meta` keys
- 📋 `mcp/core/shared/auth.rkt` (M5d) — `AuthInfo` struct + helpers
- 📋 `mcp/core/shared/stdio.rkt` (M5e) — newline-delimited JSON framing (orphaned until S6a)
- 📋 Tests under `validators/test/`, `util/test/`, `shared/test/`

### Acceptance criteria
- [ ] `raco test` over all S2 modules passes
- [ ] URI template expand/match round-trips TS `uriTemplate.test.ts` fixtures (G1)
- [ ] Tool-name validation matches TS `toolNameValidation` accept/reject set
- [ ] Schema normalization: contract input and equivalent JSON-Schema input accept/reject same values; wire schema matches
- [ ] Validator keyword coverage: ≥1 accept + 1 reject per `type`/`object`/`required`/`enum`/`string-format`, cross-checked vs TS Ajv baseline; unsupported keywords documented
- [ ] stdio framing (M5e) round-trips multi-message + partial-frame buffering, standalone
- [ ] Parity rows `validators/*`, `util/schema`, `uriTemplate`, `toolNameValidation`, `metadataUtils`, `auth` marked `partial`
- [ ] Demo: register schema → validate good/bad; expand+match URI template; encode/decode stdio frame

---

## Stage S3 — Transport port + in-memory adapter (L1 part 1) — 📋

**Modules:** M6 (Transport port), M10 (In-memory transport).

### Deliverables
- 📋 `mcp/transport/transport.rkt` (M6) — `gen:transport` (`start`/`send`/`close`, `on-message`/`on-close`/`on-error`, optional `session-id`, `related-request-id` option)
- 📋 `mcp/transport/in-memory.rkt` (M10) — linked endpoint pair, async delivery
- 📋 `mcp/transport/main.rkt` barrel
- 📋 `mcp/transport/test/in-memory-test.rkt`

### Acceptance criteria
- [ ] `raco test` over `in-memory.rkt` passes
- [ ] Endpoint pair round-trips N concurrent messages, no loss, no HOL blocking; delivery observed async
- [ ] `on-close`/`on-error` fire on both endpoints on close
- [ ] Load test: still no subprocess/socket module pulled in
- [ ] Parity rows `transport.ts`, `inMemory.ts` marked `partial`
- [ ] Demo: wire two endpoints, send each direction, print callback messages in order

---

## Stage S4 — Protocol engine (L2) — 📋

**Module:** M11 (Protocol engine).

### Deliverables
- 📋 `mcp/core/shared/protocol.rkt` — outbound `request`/`notification`; handler registration; handler-context (cancel signal, `send-notification`/`send-request`, request-id, session/HTTP info); capability/version negotiation; in-flight registry + custodian/`cancel-evt` scheduler
- 📋 `mcp/core/shared/test/protocol-test.rkt` — ported subset of TS `protocol.test.ts`

### Acceptance criteria
- [ ] `raco test` passes; ported `protocol.test.ts` cases pass over in-memory (G6)
- [ ] Concurrent in-flight requests resolve independently, no HOL blocking (Concurrency NFR)
- [ ] Timeout → correct SDK error; cancellation propagates + in-flight entry reaped
- [ ] Progress callback fires for correlated `notifications/progress`
- [ ] Capability/version guards reject out-of-capability method; surface `UnsupportedProtocolVersion`
- [ ] Malformed inbound → correct JSON-RPC error, engine keeps running (Reliability NFR)
- [ ] Composition invariant: engine standalone, no role subclassing
- [ ] Parity row `protocol.ts` marked `partial`
- [ ] Demo: two-engine harness — request/reply, out-of-order concurrent, timeout, cancellation

---

## Stage S5 — MVP roles: low-level server + client, Racket-only interop (L3 minimum) — 📋

**Modules:** M12a (low-level `Server`), M13 (`Client` core + middleware skeleton).

### Deliverables
- 📋 `mcp/server/server.rkt` (M12a) — answers inbound `initialize` + server-side negotiation; handler registration; `ping`; `logging/setLevel` **stub** (records level, no filtering)
- 📋 `mcp/client/client.rkt` (M13 core) — `connect`, `ping`, `list-tools`, `call-tool`, capability/version accessors
- 📋 `mcp/client/middleware.rkt` (M13) — interception pipeline (pass-through + example interceptor)
- 📋 `mcp/server/main.rkt`, `mcp/client/main.rkt` barrels
- 📋 `mcp/server/test/`, `mcp/client/test/`

### Acceptance criteria
- [ ] `raco test` over server/client passes
- [ ] Low-level server answers `initialize`, negotiates, returns spec-correct `InitializeResult`; unsupported version → `UnsupportedProtocolVersion`
- [ ] Racket client ↔ Racket low-level server: `initialize`+`tools/list`+`tools/call` over in-memory, negotiation correct both sides
- [ ] `logging/setLevel` records level (no filtering asserted here — S7b)
- [ ] Middleware pipeline wraps outbound request + inbound response in correct order
- [ ] Interop scope is Racket-only here (cross-SDK is an S6a criterion)
- [ ] Parity rows `server.ts`, `client.ts`, `client/middleware.ts` marked `partial`
- [ ] Demo: Racket low-level server (echo tool) + Racket client handshake + call; `logging/setLevel` accepted/recorded

---

## Stage S6a — Real transports: stdio, Streamable HTTP, web-server adapter (L1 part 2) — 📋

**Modules:** M7 (stdio), M8 (Streamable HTTP), M9 (web-server adapter).

### Deliverables
- 📋 `mcp/transport/stdio.rkt` (M7) — client+server, `subprocess`+ports+M5e framing (M5e's first real consumer); `related-request-id` accepted/ignored
- 📋 `mcp/transport/streamable-http.rkt` (M8) — POST parse, SSE streams, session IDs, `Host`/`Origin` validation, bearer-extraction seam; `related-request-id` load-bearing (route server-initiated req/resp onto correct SSE stream); resumption-token mint/validate/replay; pluggable event-store **port** (`append-event`/`replay-after`) + in-memory default
- 📋 `mcp/transport/web-server.rkt` (M9) — `web-server` dispatcher/servlet feeding M8, SSE streaming
- 📋 Tests under `mcp/transport/test/`

### Acceptance criteria
- [ ] `raco test` over transports passes
- [ ] stdio: Racket client launches Racket server as subprocess; `initialize`+`tools/list`+`tools/call` round-trip; M5e handles partial/multi-message reads
- [ ] **Cross-SDK first leg (G2):** Racket client drives a TS SDK example server over stdio; wire byte-for-byte parity vs TS fixtures (G1)
- [ ] Streamable HTTP: POST `initialize` answered, SSE streamed, session IDs maintained, disallowed `Host`/`Origin` rejected (DNS-rebinding)
- [ ] Resumption (N2): resumed SSE stream replays from client token; **seam check** — second event-store impl swapped behind the port, resumption still works, no M8 change
- [ ] Parity rows `stdio.ts`, `streamableHttp.ts`, `middleware/node` `partial`→`done` where fully exercised
- [ ] Demo: (a) stdio server launched by client; (b) Racket client driving TS server over stdio; (c) HTTP server on localhost via curl/client — SSE, rejected cross-origin, resumed stream

---

## Stage S6b — High-level server: `McpServer` + completions (L3 high-level) — 📋

**Modules:** M12b (`McpServer` static surface), M12c (Completable).

### Deliverables
- 📋 `mcp/server/mcp.rkt` (M12b static) — `register-tool`/`register-resource` (static+templated)/`register-prompt` returning `enable`/`disable`/`update`/`remove` handles; M3/M4 schema, M5b names, M5c metadata; cursor-paginated list ops producer side (J2)
- 📋 `mcp/server/completable.rkt` (M12c) — prompt/resource-template arg completions
- 📋 Tests under `mcp/server/test/`

### Acceptance criteria
- [ ] `raco test` over high-level server passes (driven over in-memory)
- [ ] Registering a tool advertises its wire JSON Schema in `tools/list`; call validates input (F8); templated resource resolves via URI-template; prompt returns; completion returns candidates
- [ ] Pagination producer (J2): over-one-page `tools/list` returns `nextCursor`; cursor returns next page; final page omits `nextCursor`
- [ ] Handle lifecycle: `disable` hides, `update` changes schema, `remove` drops
- [ ] Parity rows `mcp.ts`, `completable.ts` `partial`→`done` where exercised (session-state rows stay `partial` until S7b)
- [ ] Demo: register tool/static+templated resource/prompt; list w/ pagination; call valid+invalid; resolve templated; completion

---

## Stage S7a — Client-driven primitives: sampling, elicitation, roots, cursor-following — 📋

**Module:** M13 (Client).

### Deliverables
- 📋 Handler hooks for server-initiated `sampling/createMessage`
- 📋 `elicitation/create` form + URL modes (defaults via M3/M4); client-receive decode of server-sent `-32042` (S1 decode path)
- 📋 `roots/list` exposure + `send-roots-list-changed`
- 📋 List verbs consume opaque cursors (J2 consumer side); remaining verbs: `read-resource`, `subscribe-resource`/`unsubscribe-resource`, `get-prompt`, `complete`, `set-logging-level`
- 📋 `call-tool` progress-callback option + cancellation token (client surface over S4 engine)
- 📋 Tests under `mcp/client/test/`

### Acceptance criteria
- [ ] `raco test` passes for client primitive flows
- [ ] Sampling: server-initiated `sampling/createMessage` answered by client hook, result returns (F3)
- [ ] Elicitation: form mode applies defaults + validates; URL mode decodes server-raised `UrlElicitationRequired` to typed error
- [ ] Roots: client answers `roots/list`; `send-roots-list-changed` reaches server
- [ ] Pagination (J2) client side: follows `nextCursor` to exhaustion vs multi-page S6b server
- [ ] Progress+cancellation: `call-tool` w/ progress callback receives updates; tripping token cancels in-flight
- [ ] Parity rows for client sampling/elicitation/roots/list verbs marked `done`
- [ ] Demo: connect; server-requested sampling answered; form+URL elicitation; paginated `list-tools`; `call-tool` progress then cancel

---

## Stage S7b — Server session-state primitives: subscriptions + J1 fan-out, logging filter — 📋

**Module:** M12b (`McpServer` session-state surface).

### Deliverables
- 📋 Resource-updated emitter (J1) `notifications/resources/updated` + per-session subscription table (create on `subscribe`, drop on `unsubscribe`/close) (F9)
- 📋 List-changed emitters for tool/resource/prompt (on register/enable/disable/update/remove)
- 📋 Per-session logging-level filter (S3) — `send-logging-message` reads S5-recorded level, emits only at/above (consumes S5 stub)
- 📋 Server-raised `UrlElicitationRequired` (`-32042`) when handler needs URL-mode elicitation (item 6)
- 📋 Server progress/cancel surfaces on handler context (cancellation signal + progress emitter)
- 📋 Tests under `mcp/server/test/`

### Acceptance criteria
- [ ] `raco test` passes for server primitive flows
- [ ] Subscriptions (J1, §9.4): two sessions subscribe to different resources; change notifies only subscribed; unsubscribe/close stops (F9)
- [ ] Logging filter (S3): level `warning` suppresses `info`, delivers `warning` — stub→filter contract end to end
- [ ] Server-raised `-32042`: handler triggers raise; wire carries `-32042`; client decodes to typed error
- [ ] Progress+cancellation (server surface): long tool call emits progress via context emitter, observes cancellation signal
- [ ] All §9.4 primitives have passing tests (jointly w/ S7a); server session-state parity rows `done`
- [ ] Demo: two clients subscribe, server mutates one → only subscriber notified; `setLevel warning` suppresses `info`; handler raises `-32042`; progress tool cancelled mid-flight

---

## Stage S8 — Authentication: client OAuth + server bearer verification — 📋

**Module:** M14 (Auth) — client `mcp/client/auth.rkt`, server `mcp/server/auth/`, on shared M5d.

### Deliverables
- 📋 `mcp/client/auth.rkt` — authorize, exchange code (PKCE), refresh, persist tokens (never log secrets), cross-app access; attach tokens to M8 outbound headers (F6)
- 📋 `mcp/server/auth/` — bearer verifier port (token→`AuthInfo`/error), client registry, auth error responses; injects `AuthInfo` into S4 handler context (F7)
- 📋 Tests under `mcp/client/test/auth-test.rkt` + `mcp/server/auth/test/`

### Acceptance criteria
- [ ] `raco test` over auth modules passes
- [ ] Client OAuth: auth-code+PKCE against stub AS; refresh works; tokens persisted + attached to headers; no secret ever logged (assert vs captured logs)
- [ ] Server verification: valid token → `AuthInfo` in handler context; invalid/expired → correct auth error; registry gates unknown clients
- [ ] Authenticated end-to-end HTTP tool call succeeds w/ valid token, rejected without
- [ ] Parity rows `client/auth.ts`, `authExtensions.ts`, `crossAppAccess.ts`, server auth `done`; legacy-SSE auth-router `intentionally-excluded`
- [ ] Demo: HTTP server requiring bearer; client OAuth flow vs local stub AS; authenticated call; rejection path

---

## Stage S9 — Application surface: examples, Scribble docs, conformance + interop closeout (L4) — 📋

**Modules:** M15 (Examples), M16 (Docs), M17 (Conformance & harness).

### Deliverables — curated examples (M15)
- 📋 1. stdio server
- 📋 2. stateful HTTP server
- 📋 3. stateless HTTP server
- 📋 4. OAuth server (S8)
- 📋 5. basic client
- 📋 6. parallel tool calls (no-HOL-blocking)
- 📋 7. resumable HTTP server w/ `inMemoryEventStore` (drops into M8 event-store seam, N2 end to end)

### Deliverables — docs + harness
- 📋 `mcp/scribblings/` (M16) — every public binding documented; `@examples` compile; `raco docs`/`raco scribble` target
- 📋 Conformance harness (M17) — `rackunit` + ported cross-SDK suite; runner over in-memory + real transports, both roles, both spec revisions; interop vs MCP Inspector + TS SDK both directions
- 📋 Packaging — `info.rkt` so `raco pkg install mcp` succeeds on clean install
- 📋 Final parity-matrix pass — all non-excluded `done`; excluded rows `intentionally-excluded`

### Acceptance criteria
- [ ] Conformance suite passes: both spec revisions × both transports × both roles (§9.2; G1,G5,G6)
- [ ] Cross-SDK interop (§9.3, G2): Racket server passes Inspector + driven by TS client over stdio+HTTP; Racket client calls tools/resources/prompts on TS server
- [ ] Installable & documented (§9.6, G7): `raco pkg install` succeeds; `raco docs` builds; every public binding documented; all `@examples` compile
- [ ] All seven curated examples run end-to-end, incl. `inMemoryEventStore` drop-in (no M8 change)
- [ ] Idiomatic API confirmed (§9.7, G4): public-API review — contracts, keywords, structs, no JS-isms
- [ ] Parity matrix complete (§9.1, G3): all non-excluded rows `done`
- [ ] Tool-call-latency baseline benchmark established + recorded (Performance NFR)
- [ ] Demo: Inspector→Racket server; TS client driving Racket over stdio+HTTP; Racket client driving TS server; green `raco test`; `raco docs` opens manual

---

## Vision goal coverage (G1–G8)

| Goal | Description | Primary stages | Status |
|------|-------------|----------------|--------|
| G1 | Wire-protocol parity (both revisions) | S1, S2, S6a, S9 | 📋 |
| G2 | Interoperate with reference clients | S6a, S9 | 📋 |
| G3 | Architectural mirror of TS SDK v2 (parity matrix) | all (closeout S9) | 📋 |
| G4 | Idiomatic Racket public API | all (review S9) | 📋 |
| G5 | Two transports at parity | S6a, S9 | 📋 |
| G6 | Capability-correct protocol layer | S4, S5, S9 | 📋 |
| G7 | Installable via Racket package system | S9 | 📋 |
| G8 | OAuth support for HTTP transport | S8 | 📋 |

## Success criteria coverage (§9)

| # | Criterion | Stage gate | Status |
|---|-----------|-----------|--------|
| §9.1 | Parity matrix complete (all non-excluded `done`) | S9 | 📋 |
| §9.2 | Conformance suite passes (2 revs × 2 transports × 2 roles) | S9 | 📋 |
| §9.3 | Cross-SDK interop demonstrated (Inspector + TS, both dirs) | S6a (first leg), S9 | 📋 |
| §9.4 | All MCP primitives implemented w/ tests | S7a + S7b | 📋 |
| §9.5 | OAuth flows work (client + server) | S8 | 📋 |
| §9.6 | Installable & documented | S9 | 📋 |
| §9.7 | Idiomatic API confirmed | S9 | 📋 |
| §9.8 | Runnable examples end-to-end | S9 | 📋 |

## Non-functional requirement coverage

| NFR | Where verified | Status |
|-----|----------------|--------|
| MCP spec compatibility (negotiate both revs + back-compat list) | S1, S4 | 📋 |
| Interoperability (byte-for-byte JSON-RPC) | S6a, S9 | 📋 |
| Concurrency (no HOL blocking) | S3, S4 | 📋 |
| Performance (latency baseline + regression guard) | S9 | 📋 |
| Security (`Host`/`Origin`, session IDs, bearer, no secret logs) | S6a, S8 | 📋 |
| Reliability (resumption, timeouts, cancel, malformed→error not crash) | S4, S6a | 📋 |
| Portability (core loads w/o subprocess/socket) | S1, S2, S3 | 📋 |
| Minimal dependencies | all | 📋 |
| Documentation completeness | S9 | 📋 |

## Parity matrix progression

Per-stage discipline: each stage flips the `core/types/*`, `errors/*`, `validators/*`, transport, role, and auth rows from `partial`→`done` as it fully exercises them; S9 is the certification pass. Tracked in roadmap §9 parity matrix. Current state: **no rows yet (no source).** 📋

## Intentionally excluded (vision §8) — ❌ / ⏸️

| Excluded item | Status |
|---------------|--------|
| `codemod` equivalent | ❌ Excluded |
| `server-legacy` (HTTP+SSE legacy transport) + legacy-SSE auth-router | ❌ Excluded |
| Per-framework middleware (Express/Hono/Fastify) | ❌ Excluded |
| Zod / external Standard-Schema library compat | ❌ Excluded |
| Browser / Cloudflare Workers / Deno runtime shims + cfWorker validator | ❌ Excluded |
| Embedded LLM client | ❌ Excluded |
