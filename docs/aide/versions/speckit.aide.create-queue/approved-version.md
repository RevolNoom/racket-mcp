# Work Queue 001: `racket-mcp` — Stage S1 Foundation (Types + Errors, L0 part 1)

> **Source vision:** `docs/aide/vision.md`
> **Source roadmap:** `docs/aide/roadmap.md`
> **Source progress:** `docs/aide/progress.md`
> **Reference impl:** MCP TypeScript SDK v2 (`typescript-sdk/`)
> **Stage focus:** Stage S1 **only** — M1 (Types) + M2 (Errors). All of Stage S2 (M3 validators, M4 schema util, M5a–M5e shared utils) is **deferred to queue-002**.
> **Queue number:** 001 (first queue; items numbered sequentially from 001).
> **Sizing:** 9 items, each a genuine S1-sized (sub-multi-day) unit, all testable locally via `raco test`; batch deliverable in roughly one week.

---

## Why this batch

Progress shows every stage at 📋 (not started), so this queue begins at the bottom of the dependency graph. **Stage S1 has no dependencies** and is the single source of truth every later module imports: the on-wire JSON-RPC + MCP shapes as structs + flat contracts, the error-code/protocol-version constants, the type-guard predicates, the N1 normalized-superset façade, and the bidirectional `exn`↔JSON-RPC error layer. Completing S1 in full unblocks Stage S2 (validators/schema/shared utils, which import only S1) and everything above it.

This queue is **scoped to S1 only** — S2's modules (M3/M4/M5a–e) constitute the entirety of Stage S2 and would push the batch to ~two weeks, so they move to queue-002. The old "split-across-both-revisions" spec-types item is now split into one item per spec revision, and the error layer is split into encode and decode paths, so each item is a real sub-multi-day unit.

**Prerequisite for the Worker:** the TS reference checkout at `typescript-sdk/` must be available, since several acceptance criteria assert byte-for-byte constant parity and TS-fixture round-trips against it.

---

### Item 001: Error-code and protocol-version constants
Implement `mcp/core/types/constants.rkt` mirroring TS `constants.ts` / `enums.ts`. Define the JSON-RPC + MCP error codes (`ParseError -32700`, `InvalidRequest -32600`, `MethodNotFound -32601`, `InvalidParams -32602`, `InternalError -32603`; MCP-specific `ResourceNotFound -32002`, `MissingRequiredClientCapability -32003`, `UnsupportedProtocolVersion -32004`, `UrlElicitationRequired -32042`) and the protocol-version constants (`LATEST = 2025-11-25`, `DEFAULT_NEGOTIATED = 2025-03-26`, full `SUPPORTED_PROTOCOL_VERSIONS` list). Provide an explicit `provide`d public surface. Testable: a unit test under `mcp/core/types/test/` asserts every error code and version constant matches the `typescript-sdk/` checkout **byte-for-byte** (grep-diff against `constants.ts` / `enums.ts`); `raco test` passes.

### Item 002: JSON-RPC type guards / predicates (no batch guard)
Implement `mcp/core/types/guards.rkt` mirroring TS `guards.ts`. Provide predicates `is-jsonrpc-request?`, `is-jsonrpc-notification?`, `is-jsonrpc-response?`, `is-jsonrpc-error?` (and the supporting message-shape checks) operating on parsed JSON (hasheq) values. Per architecture **J3** (both target revisions removed JSON-RPC batching), there is **no batch guard** and none is exported. Testable: a truth-table unit test under `mcp/core/types/test/` exercising each predicate against valid and invalid message shapes (including overlapping/ambiguous shapes — e.g. a response-vs-error discriminator) and asserting that no batch predicate is provided; `raco test` passes.

### Item 003: Spec types — revision 2025-11-25
Implement `mcp/core/types/spec-2025-11-25.rkt` — Racket structs + flat contracts for **every** request, response, notification, and error type in the `2025-11-25` revision, mirroring TS `spec.types.2025-11-25.ts`. Testable: under `mcp/core/types/test/`, a `read-json`→struct→`write-json` round-trip test over a representative message of each envelope kind (parsed from a TS-SDK-emitted JSON fixture and re-serialized identically), plus a contract-rejection test confirming malformed inputs are rejected by the flat contracts; `raco test` passes.

### Item 004: Spec types — revision 2026-07-28 (incl. `_meta` envelope)
Implement `mcp/core/types/spec-2026-07-28.rkt` — Racket structs + flat contracts for every request, response, notification, and error type in the `2026-07-28` (RC) revision, mirroring TS `spec.types.2026-07-28.ts`, **including the per-request `_meta` reserved-key envelope** (protocol version, client info, client capabilities, related-task, deprecated log level). Testable: under `mcp/core/types/test/`, a round-trip test per envelope kind against TS fixtures, a contract-rejection test for malformed inputs, **and a test asserting the RC-only fields (the `_meta` reserved keys / `2026-07-28`-only struct fields) are present and parsed**; `raco test` passes.

### Item 005: Public types + normalized-superset façade (N1)
Implement `mcp/core/types/types.rkt` mirroring TS `types.ts`: the public protocol types and the **normalized-superset façade** (architecture **N1**) — one internal shape per primitive that is the union of both revisions (items 003 + 004), with revision-only fields present-or-absent. This is the shape every later layer consumes regardless of negotiated version. Testable: unit tests under `mcp/core/types/test/` showing a `2025-11-25` message and a `2026-07-28` message both normalize into the same façade struct with the correct fields present/absent (RC-only fields absent for the older revision, present for the newer); `raco test` passes.

### Item 006: Error hierarchy + ENCODE path (exn → JSON-RPC)
Implement `mcp/core/errors.rkt` (encode half) — the `exn:fail:mcp`, `exn:fail:mcp:protocol`, and `exn:fail:mcp:auth` subtypes with stable codes, plus constructors and predicates. Implement the **encode** direction of the single exn↔JSON-RPC conversion point (architecture §4.1 error-to-wire boundary): an exn → a correct JSON-RPC error object carrying the right code/message. Testable: `mcp/core/test/errors-test.rkt` asserts each exn subtype constructs with its stable code, the predicates discriminate correctly, and an exn encodes to a spec-correct JSON-RPC error object (e.g. an internal failure → `-32603`); `raco test` passes.

### Item 007: Error DECODE path (JSON-RPC → typed error)
Extend `mcp/core/errors.rkt` with the **decode** direction (mirrors TS `core/types/errors.ts`): a received JSON-RPC error **object** → the matching typed error, so a generic failure is not produced where a specific one is defined. Must cover the spec-significant codes — in particular **`-32042` → `UrlElicitationRequired`** error and **`-32004` → unsupported-protocol-version** error. Testable: `mcp/core/test/errors-test.rkt` asserts the decode of `-32042` → `UrlElicitationRequired` and `-32004` → unsupported-version (and a fall-through for unknown codes → generic typed error), cross-checked against TS `core/types/errors.ts` behaviour; `raco test` passes.

### Item 008: Core barrels + restricted-load portability test
Implement the curated public-surface barrels `mcp/core/types/main.rkt` and `mcp/core/main.rkt` with explicit `provide` (architecture §1.3 public/internal boundary), re-exporting items 001–007. Add the **restricted-namespace portability load test**: require `mcp/core/types` and `mcp/core/errors.rkt` in a restricted namespace and assert **no subprocess/socket module** is pulled in (Portability NFR). Testable: `raco test` over `mcp/core/types/` and `mcp/core/errors.rkt` passes; the restricted-load test passes; the barrels expose only the curated public surface (a test asserts an internal-only binding is not re-exported).

### Item 009: Stage S1 demo + parity-matrix update (closeout)
Add the S1 demo script: parse a sample `initialize` request and a `tools/call` request from JSON, print the resulting structs, re-emit JSON identically, and show a malformed message converted to a correct JSON-RPC error object (exercising items 003–007). Update the roadmap §9 parity-matrix rows for `core/types/*` and `errors/*` to `partial` (structs exist; exercised by conformance later), and update `docs/aide/progress.md` S1 acceptance boxes. Testable: the demo script runs end-to-end via `racket`; `raco test` is green across all of `mcp/core/types/` and `mcp/core/errors.rkt`; the parity-matrix and progress edits are present. (Completes Stage S1; unblocks queue-002 / Stage S2.)
