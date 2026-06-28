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
| S1 | Types, constants, guards, errors | M1, M2 | L0 | ✅ |
| S2 | Validators, schema, shared utils | M3, M4, M5a–e | L0 | ✅ |
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

## Stage S1 — Foundation: types, constants, guards, errors (L0 part 1) — ✅

**Modules:** M1 (Types), M2 (Errors).

### Deliverables
- ✅ `mcp/core/types/constants.rkt` — error codes + `LATEST`/`DEFAULT_NEGOTIATED`/`SUPPORTED_PROTOCOL_VERSIONS`
- ✅ `mcp/core/types/spec-2025-11-25.rkt` — per-revision structs + contracts (item 003)
- ✅ `mcp/core/types/spec-2026-07-28.rkt` — per-revision structs + contracts incl. `_meta` envelope (item 004)
- ✅ `mcp/core/types/types.rkt` — public types + N1 normalized-superset façade (item 005; 58 façade structs, normalize/denormalize seam, revision-parameterized dispatch)
- ✅ `mcp/core/types/guards.rkt` — JSON-RPC predicates (no batch guard, J3)
- ✅ `mcp/core/errors.rkt` — `exn:fail:mcp[:protocol|:auth]`; exn↔JSON-RPC **encode + decode** (item 006 encode + item 007 decode; complete)
- ✅ `mcp/core/types/main.rkt` + `mcp/core/main.rkt` barrels (item 008; `prefix-in r25:/r26:` on the two spec modules, per-module `all-from-out`, no new defines)
- ✅ `mcp/core/types/test/` + `mcp/core/test/errors-test.rkt` (barrel + transitive portability + curation tests added by item 008 as `mcp/core/test/main-test.rkt`; demo `mcp/core/demo/s1-demo.rkt` + final closeout by item 009)

### Acceptance criteria
- [x] `raco test` over `mcp/core/types/` + `mcp/core/errors.rkt` passes
- [x] Error codes + version constants match TS `constants.ts`/`enums.ts` byte-for-byte
- [x] Each JSON-RPC envelope kind round-trips from TS fixture → struct → identical JSON (G1)
- [x] Decode: `-32042` → `UrlElicitationRequired`; `-32004` → unsupported-version (vs TS `core/types/errors.ts`)
- [x] Restricted-namespace load test: no subprocess/socket pulled in (Portability NFR)
- [x] Parity rows `core/types/*`, `errors/*` marked `partial`
- [x] Demo: parse `initialize`+`tools/call` from JSON, re-emit, malformed→JSON-RPC error

---

## Stage S2 — Foundation: validators, schema, shared utilities (L0 part 2) — ✅

**Modules:** M3 (Validators), M4 (Schema util), M5a–M5e (Shared).

### Deliverables
- ✅ `mcp/core/validators/provider.rkt` — `gen:`-style validator-provider port (item 010: port + result types + closure-in-handle; stub-provider shape test; S1-only, portability-clean)
- ✅ `mcp/core/validators/from-json-schema.rkt` — Racket-native default (keywords: `type`, `properties`, `required`, `enum`, `items`, `format` for `date-time`/`uri`/`email`) (item 011: collect-all keyword evaluator + located paths + per-compile weak handle→ignored-keyword warnings; deferred/unknown keywords ignore-with-warning; TS-baseline cross-check; S1+port-only, portability-clean)
- ✅ `mcp/core/util/schema.rkt` — contract-or-JSON-Schema normalization (Standard-Schema analogue) (item 012: dual input forms → uniform `normalized-schema` {wire JSON Schema, M3 `compiled-validator?` handle}; single-delegation-path; form-dependent root `type:"object"` invariant; flat-contract subset map with `and/c`/mixed-`or/c`/`integer?`/higher-order rejected; nested `object-schema/c` recursion + located paths; deferred-keyword Form-A pass-through; `normalized-schema-prompt-arguments`; S1+M3-only, portability-clean. `raco test mcp/core/util/` → 102 checks pass)
- ✅ `mcp/core/shared/uri-template.rkt` (M5a) — RFC 6570 subset expand/match (item 013: TS `uriTemplate.ts` transliteration — `uri-template-expand`/`uri-template-match`/`uri-template?`/`uri-template-variables`; 7-operator subset + multi-name + `*` explode + `?`→`&` continuation; hand-rolled UTF-8-byte `encode-uri`/`encode-uri-component` (NO `net/*`); symbol-keyed immutable result/var hashes; no-match → `#f`; match does not decode; safe `#f`-name empty-expr handling (issue #1); four security caps + CVE-2026-0621 ReDoS-safe regex; S1-only, portability-clean. `raco test mcp/core/shared/` → 108 checks pass)
- ✅ `mcp/core/shared/tool-name-validation.rkt` (M5b) — SEP-986 tool-name conformance (item 014: TS `toolNameValidation.ts` transliteration — `validate-tool-name` struct + `valid-tool-name?` predicate + `issue-tool-name-warning` (module logger, one event per line) + `validate-and-warn-tool-name`; SEP-986 1–128 + `[A-Za-z0-9._-]`; advisory vs invalid distinction; first-seen invalid-char dedup; ASCII-class char predicate (not `char-alphabetic?`); no normalizer (TS has none); base-collections-only, no S1 import. `raco test mcp/core/shared/` → 192 checks pass)
- ✅ `mcp/core/shared/metadata-utils.rkt` (M5c) — reserved `_meta` keys (item 015: TS `metadataUtils.ts` + `constants.ts` port — `get-display-name` precedence over a symbol-keyed hash with the empty-string-title fallthrough + the C1 `(hash? annotations)` crash-guard + the S5 non-string-title divergence (stricter than TS, documented); the 8 reserved `_meta` keys aggregated (5 re-exported from S1 + the 3 SEP-414 unprefixed trace keys `traceparent`/`tracestate`/`baggage` defined here, closing the 5-vs-8 gap); `reserved-meta-key?`/`meta-ref`/`meta-set` (string-or-symbol key normalization, functional set, no-default→#f); the two-notions-of-reserved boundary (`progressToken`→#f) + the S1 `request-meta` envelope round-trip proving the trace keys ride S1's unreserved `rest` passthrough verbatim. S1-only import, no `net/*`. metadata-utils-test = 38 checks)
- ✅ `mcp/core/shared/auth.rkt` (M5d) — `AuthInfo` struct + helpers (item 015: TS `types.ts:435` + `auth.ts`/`authUtils.ts` non-OAuth helpers — `auth-info` 6-field exact surface (`token`/`client-id`/`scopes`/`expires-at`/`resource`/`extra`, `#:transparent`); `make-auth-info` smart constructor contracted via `define/contract` (checked on internal calls too, so `json->auth-info` inherits the type-rejection); `auth-info-expired?` (token helper, `<=`, #f→#f, epoch-0 real-expiry S4) + `auth-info-has-scope?`; `auth-info->json`/`json->auth-info` camelCase wire round-trip with omit-on-#f (0/empty-extra emitted, S4) + the decode-reject discipline (raises on missing/non-string `token`/`clientId` or non-list `scopes`, security-relevant C2); `resource` held as a string — NO `net/url`/tcp (portability); NO OAuth logic. `racket/contract`+S1 import. auth-test = 39 checks)
- ✅ `mcp/core/shared/stdio.rkt` (M5e) — newline-delimited JSON framing (item 016: TS `stdio.ts` transliteration — `serialize-message`/`deserialize-message`/`make-read-buffer`/`read-buffer-append!`/`read-buffer-read-message!`/`read-buffer-clear!`/`STDIO-DEFAULT-MAX-BUFFER-SIZE`; three load-bearing behaviours: overflow-clear-throw `>` strict + CRLF-strip + non-JSON-skip/invalid-envelope-throw; `try-parse-json-line` confines parse-failure handler; `ok?`-flag skip (not value truthiness, `false` test); byte-level buffer, per-complete-line decode for multibyte UTF-8 safety; `json`+S1-only imports, no `net/*`/subprocess/socket. orphaned until S6a. stdio-test.rkt = 48 checks; `raco test mcp/core/shared/` → 317 checks pass)
- ✅ Tests under `validators/test/`, `util/test/`, `shared/test/`
- ✅ `mcp/core/test/s2-portability-test.rkt` — collection-wide S2 restricted-load portability sweep (item 017; stdio.rkt M5e isolated as a root; 63 checks — seven non-I/O roots × banned-module checks + a per-root teeth-proving non-vacuity guard)
- ✅ `mcp/core/demo/s2-demo.rkt` — Stage S2 end-to-end witness (item 018: pure consumer over items 010–017; three arms: M3 validator good/bad + structured error path+message; M5a uri-template expand+match round-trip; M5e stdio serialize+read-buffer round-trip; 16 rackunit checks; closes Stage S2)

### Acceptance criteria
- [x] `raco test` over all S2 modules passes
- [x] URI template expand/match round-trips TS `uriTemplate.test.ts` fixtures (G1)
- [x] Tool-name validation matches TS `toolNameValidation` accept/reject set
- [x] Schema normalization: contract input and equivalent JSON-Schema input accept/reject same values; wire schema matches
- [x] Validator keyword coverage: ≥1 accept + 1 reject per `type`/`object`/`required`/`enum`/`string-format`, cross-checked vs TS Ajv baseline; unsupported keywords documented
- [x] stdio framing (M5e) round-trips multi-message + partial-frame buffering, standalone
- [x] Parity rows `validators/*`, `util/schema`, `uriTemplate`, `toolNameValidation`, `metadataUtils`, `auth` marked `partial`
- [x] Demo: register schema → validate good/bad; expand+match URI template; encode/decode stdio frame

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

Per-stage discipline: each stage flips the `core/types/*`, `errors/*`, `validators/*`, transport, role, and auth rows from `partial`→`done` as it fully exercises them; S9 is the certification pass. Tracked via each stage's roadmap Testing/validation criteria (no separate materialized table until the S9 closeout pass). **Current state (after Stage S1):** `core/types/*` and `errors/*` are **`partial`** — the per-revision structs/contracts (items 003/004), the N1 façade (item 005), the guards (item 002), the constants (item 001), and the bidirectional exn↔JSON-RPC error layer (items 006/007) all exist and round-trip TS-SDK fixtures (witnessed by `mcp/core/demo/s1-demo.rkt`), but full cross-SDK conformance exercise is deferred to S9 (§9.1/§9.2). **Item 010 (Stage S2):** the `validators/*` **port** sub-row advances toward `partial` — `mcp/core/validators/provider.rkt` ships the `gen:json-schema-validator-provider` port + closed result types (`validation-ok`/`validation-errors`/`validation-error`) + closure-in-handle, proven by a stub-provider shape test (66 checks) and a restricted-load portability walk; the default-provider/keyword-coverage sub-rows stay unflipped until items 011/017/018 + S9. **Item 011 (Stage S2):** the `validators/*` **default-provider / keyword-coverage** sub-row is now satisfied — `mcp/core/validators/from-json-schema.rkt` implements the port with a collect-all keyword evaluator (`type`/`properties`/`required`/`enum`/`items`/`format` for date-time/uri/email), located error paths, and the ignore-with-warning policy for deferred/unknown keywords recorded in a per-compile weak handle→ignored-keyword map; proven by a keyword-coverage + TS-baseline cross-check test and a restricted-load walk (`raco test mcp/core/validators/` → 300 checks pass, 0 fail). The collection-wide S2 sweep + full conformance still land with items 017/018 + S9, so `validators/*` stays `partial`. **Item 012 (Stage S2):** the `util/schema` row is now **`partial`** — `mcp/core/util/schema.rkt` ships the contract-or-JSON-Schema normalizer (the Standard-Schema analogue): both input forms (a `racket/contract` flat contract or a parsed JSON Schema) compile through the SAME M3 provider over a derived wire JSON Schema (single delegation path), guaranteeing the dual-form accept/reject + wire match by construction; the form-dependent root `type:"object"` invariant, the flat-contract subset map (with `and/c`/mixed-`or/c`/`integer?`/higher-order rejected, nested `object-schema/c` recursion, deferred-keyword Form-A pass-through), and `normalized-schema-prompt-arguments` are all covered by `raco test mcp/core/util/` → 102 checks pass, 0 fail, plus a restricted-load walk rooted at `schema.rkt` (S1 + M3 only, no `net/url`; drift-checked non-vacuous). The collection-wide sweep + full conformance land with items 017/018 + S9, so `util/schema` stays `partial`. **Item 013 (Stage S2):** the `uriTemplate` row is now **`partial`** — `mcp/core/shared/uri-template.rkt` (M5a, the first `mcp/core/shared/` module) ships the RFC-6570-subset engine transliterated from TS `uriTemplate.ts`: `uri-template-expand`/`uri-template-match`/`uri-template?`/`uri-template-variables` over the seven-operator subset (`+ # . / ? &` + simple) with multi-name, `*` explode, and the `?`→`&` continuation, hand-rolled UTF-8-byte `encode-uri`/`encode-uri-component` (JS-parity, NO `net/url`/`net/uri-codec`), symbol-keyed immutable var/result hashes, no-match → `#f`, no-decode-on-match, the safe `#f`-name empty-expr handling (issue #1), and the four security caps + CVE-2026-0621 ReDoS-safe regex shape; every `uriTemplate.test.ts` fixture is ported 1:1 and the three round-trippable fixtures round-trip (G1). Proven by `raco test mcp/core/shared/` → 108 checks pass, 0 fail, plus a restricted-load walk rooted at `uri-template.rkt` (S1 only, no `net/*`; drift-checked non-vacuous, ReDoS payloads measured 0.12 ms / 0.09 ms). Full RFC-6570 conformance + the collection-wide sweep land with items 017/S9, so `uriTemplate` stays `partial`. **Item 017 (Stage S2):** the collection-wide S2 Portability-NFR obligation is now closed — all six S2 parity rows (`validators/*`, `util/schema`, `uriTemplate`, `toolNameValidation`, `metadataUtils`, `auth`) are **`partial`** (modules exist + round-trip TS fixtures; full cross-SDK conformance deferred to S9). `mcp/core/test/s2-portability-test.rkt` runs the S1 restricted-load walk (copied verbatim from `main-test.rkt:49-105`) over the seven non-I/O roots — each in a fresh base namespace with a per-root `base-dir = (path-only root)` — asserting NO subprocess/socket module (`racket/system`/`port`/`tcp`/`udp`, `net/url`/`http-client`/`sendurl`, `racket/sandbox`) is transitively reachable, plus a teeth-proving non-vacuity guard per root (S1-edge path presence `#rx"core/main\.rkt"`/`#rx"spec-2026"` for the six S1-importers — observed `visited` 220–233; `racket/string`/`list` presence `#rx"/(string|list)\.rkt$"` or `>= 50` for `tool-name-validation` — observed 82). `stdio.rkt` (M5e) is isolated **as a root** (the permitted-I/O carve-out, enumerated literally not globbed; coverage deferred to item 016/S6a). A `racket/tcp` mutation injected into one root (`util/schema.rkt`) flipped the sweep RED then reverted to green, proving the banned assertions bite. Green: `raco test mcp/core/test/s2-portability-test.rkt` (63), `raco test mcp/core/validators/ mcp/core/util/ mcp/core/shared/` (671), `raco test mcp/core/test/` (221, dir-wide superset incl. `main-test.rkt`). Roadmap §9 has **no materialized parity table** — the six row names appear only in the `roadmap.md:131` S2 acceptance line + module bullets — so that acceptance line stands unedited. All remaining rows stay `📋` (no source yet). ✅

## Intentionally excluded (vision §8) — ❌ / ⏸️

| Excluded item | Status |
|---------------|--------|
| `codemod` equivalent | ❌ Excluded |
| `server-legacy` (HTTP+SSE legacy transport) + legacy-SSE auth-router | ❌ Excluded |
| Per-framework middleware (Express/Hono/Fastify) | ❌ Excluded |
| Zod / external Standard-Schema library compat | ❌ Excluded |
| Browser / Cloudflare Workers / Deno runtime shims + cfWorker validator | ❌ Excluded |
| Embedded LLM client | ❌ Excluded |
