# Work Queue 001: `racket-mcp` — Foundation (L0)

> **Source vision:** `docs/aide/vision.md`
> **Source roadmap:** `docs/aide/roadmap.md`
> **Source progress:** `docs/aide/progress.md`
> **Reference impl:** MCP TypeScript SDK v2 (`typescript-sdk/`)
> **Stage focus:** Stage S1 (M1 Types, M2 Errors) in full, then early Stage S2 (M3 Validators, M4 Schema util, M5a–M5e Shared utils).
> **Queue number:** 001 (first queue; items numbered sequentially from 001).
> **Sizing:** ~10 items, each testable locally via `raco test`, batch deliverable in roughly one week.

---

## Why this batch

Progress shows every stage at 📋 (not started), so this queue begins at the bottom of the dependency graph. Stage S1 has **no dependencies** and is the single source of truth every later module imports; Stage S2 depends only on S1. Completing S1 plus the unblocked parts of S2 (validators, schema normalization, and the shared utility modules — all of which import only S1) lays the entire L0 foundation and unblocks S3 (transport port). Items are ordered so each one can be built and tested against the TS checkout as ground truth.

---

### Item 001: Error-code and protocol-version constants
Implement `mcp/core/types/constants.rkt` mirroring TS `constants.ts` / `enums.ts`. Define the JSON-RPC + MCP error codes (`ParseError -32700`, `InvalidRequest -32600`, `MethodNotFound -32601`, `InvalidParams -32602`, `InternalError -32603`; MCP-specific `ResourceNotFound -32002`, `MissingRequiredClientCapability -32003`, `UnsupportedProtocolVersion -32004`, `UrlElicitationRequired -32042`) and the protocol-version constants (`LATEST = 2025-11-25`, `DEFAULT_NEGOTIATED = 2025-03-26`, full `SUPPORTED_PROTOCOL_VERSIONS` list). Provide an explicit `provide`d public surface. Testable: every code and version constant matches the TS checkout byte-for-byte (grep-diff against `typescript-sdk/`), asserted in a unit test under `mcp/core/types/test/`.

### Item 002: JSON-RPC type guards / predicates
Implement `mcp/core/types/guards.rkt` mirroring TS `guards.ts`. Provide predicates `is-jsonrpc-request?`, `is-jsonrpc-notification?`, `is-jsonrpc-response?`, `is-jsonrpc-error?` (and the supporting message-shape checks) operating on parsed JSON (hasheq) values. Per architecture J3 (both target revisions removed JSON-RPC batching), there is **no batch guard**. Testable: a truth-table unit test under `mcp/core/types/test/` exercising each predicate against valid and invalid message shapes (including overlapping/ambiguous shapes) and confirming no batch predicate is exported.

### Item 003: Per-revision spec types (2025-11-25 and 2026-07-28)
Implement `mcp/core/types/spec-2025-11-25.rkt` and `mcp/core/types/spec-2026-07-28.rkt` — per-revision Racket structs + flat contracts for every request, response, notification, and error type in each revision, mirroring the TS `spec.types.2025-11-25.ts` / `spec.types.2026-07-28.ts`. Include `_meta` envelope fields where the revision defines them (2026-07-28 reserved keys). Testable: a `read-json`→struct→`write-json` round-trip test per revision over representative messages, plus a contract-rejection test for malformed inputs, under `mcp/core/types/test/`.

### Item 004: Public types and normalized-superset façade (N1)
Implement `mcp/core/types/types.rkt` mirroring TS `types.ts`: the public protocol types and the **normalized-superset façade** (architecture N1) — one internal shape per primitive that is the union of both revisions, with revision-only fields present-or-absent. This is the shape every later layer consumes regardless of negotiated version. Testable: unit tests showing a 2025-11-25 message and a 2026-07-28 message both normalize into the same façade struct with the correct fields present/absent, under `mcp/core/types/test/`.

### Item 005: Error hierarchy with encode + decode (exn ↔ JSON-RPC)
Implement `mcp/core/errors.rkt` — the `exn:fail:mcp`, `exn:fail:mcp:protocol`, and `exn:fail:mcp:auth` subtypes with stable codes, plus constructors and predicates. Implement the **single bidirectional** exn↔JSON-RPC-error conversion point (architecture §4.1): (a) **encode** — an exn → a JSON-RPC error object; (b) **decode** — a received JSON-RPC error object → the matching typed error (mirrors TS `core/types/errors.ts`), so `-32042` decodes to a `UrlElicitationRequired` error and `-32004` to an unsupported-protocol-version error rather than a generic failure. Testable: `mcp/core/test/errors-test.rkt` asserts both directions, explicitly including the decode of `-32042` → `UrlElicitationRequired` and `-32004` → unsupported-version, cross-checked against TS `core/types/errors.ts` behaviour.

### Item 006: Core barrels and restricted-load portability test
Implement the curated public-surface barrels `mcp/core/types/main.rkt` and `mcp/core/main.rkt` with explicit `provide` (architecture §1.3 public/internal boundary), re-exporting items 001–005. Add a portability load test that requires `mcp/core/types` and `mcp/core/errors.rkt` in a restricted namespace and asserts **no subprocess/socket module** is pulled in (Portability NFR). Add a demo script: parse a sample `initialize` request and a `tools/call` request from JSON, print the structs, re-emit JSON, and show a malformed message converted to a correct JSON-RPC error object. Testable: `raco test` over `mcp/core/types/` and `mcp/core/errors.rkt` passes; the restricted-load test passes; the demo script runs via `racket`. (Completes Stage S1.)

### Item 007: Validator provider port + Racket-native default
Implement `mcp/core/validators/provider.rkt` — the validator-provider port via `racket/generic` (compile JSON Schema → reusable validator; validate value → ok/errors), mirroring TS `validators/types.ts`. Implement `mcp/core/validators/from-json-schema.rkt` — the default Racket-native provider over a documented JSON-Schema subset. **Minimum supported keyword set:** `type` (string/number/integer/boolean/object/array/null), `properties`, `required`, `enum`, `items`, and `format` for common string formats (`date-time`, `uri`, `email`). Any unsupported keyword must be documented and either ignored-with-warning or rejected explicitly — never silently mis-validated. Testable: unit tests under `mcp/core/validators/test/` with ≥1 accept + 1 reject case per `type`/`object`(`properties`)/`required`/`enum`/`string`-`format`, each cross-checked against a TS Ajv-validated baseline for the same schema + value; unsupported keywords listed in module docs.

### Item 008: Dual-form schema normalization (M4)
Implement `mcp/core/util/schema.rkt` mirroring TS `util/schema.ts` + `standardSchema.ts`. Normalize a `racket/contract` flat contract **or** a JSON Schema into (a) a wire JSON Schema for advertisement and (b) a validation handle delegating to the M3 provider (item 007). This is the Standard-Schema analogue. Testable: unit tests under `mcp/core/util/test/` showing a contract input and an equivalent JSON-Schema input both produce a validation handle that accepts the same values and rejects the same values, and that the emitted wire JSON Schema matches expectation.

### Item 009: Shared utilities — URI templates, tool-name validation, metadata (M5a–M5c)
Implement three shared-utility modules: `mcp/core/shared/uri-template.rkt` (M5a) — RFC 6570 subset `expand(template, vars)→uri` and `match(template, uri)→vars`; `mcp/core/shared/tool-name-validation.rkt` (M5b) — tool-name predicate + normalizer per spec; `mcp/core/shared/metadata-utils.rkt` (M5c) — read/write reserved `_meta` keys (protocol version, client info/capabilities, related-task, deprecated log level). Testable: URI template expand/match round-trips the TS `uriTemplate.test.ts` fixtures; tool-name validation accepts/rejects the same names as the TS `toolNameValidation` tests; metadata helpers round-trip each reserved key — all under `mcp/core/shared/test/`.

### Item 010: Shared utilities — auth structs + stdio framing (M5d–M5e)
Implement `mcp/core/shared/auth.rkt` (M5d) — the `AuthInfo` struct + token/metadata helpers (shared by client + server auth in S8). Implement `mcp/core/shared/stdio.rkt` (M5e) — newline-delimited JSON frame encode/decode over a byte stream (the only M5 module performing I/O; **orphaned until S6a** — its first integration consumer is the stdio transport M7, so it is built here for L0 cohesion and unit-tested standalone). Testable: `AuthInfo` construction/accessor unit tests; stdio framing round-trips multi-message byte streams including partial-frame buffering, tested standalone under `mcp/core/shared/test/`. Add the S2 demo script: register a JSON Schema → validate a good and a bad value; expand and match a URI template; encode/decode a stdio frame buffer.
