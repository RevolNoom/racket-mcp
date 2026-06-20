# Work Item 001: Error-code and protocol-version constants

> **Queue:** `docs/aide/queue/queue-001.md` — Item 001
> **Stage:** S1 (Foundation: types, constants, guards, errors — L0 part 1)
> **Module:** M1 (Types) — `constants` sub-unit
> **Source vision:** `docs/aide/vision.md` §4.1, §6 (Portability NFR)
> **Source roadmap:** `docs/aide/roadmap.md` Stage S1 → Deliverables → `mcp/core/types/constants.rkt`
> **Source architecture:** `docs/aide/architecture.md` §1.3 (public/internal boundary), M1
> **Reference impl (authoritative):** MCP TypeScript SDK v2 at `typescript-sdk/`
> **Status:** 📋 Planned (see Completion Reminder)

---

## Description

Implement `mcp/core/types/constants.rkt`, a **pure-data** Racket module mirroring the
TypeScript SDK's `constants.ts` and `enums.ts`. It is the bottom of the entire
dependency graph: every later module (spec types, guards, error layer, protocol
engine, transports, roles) imports its error codes and protocol-version values.

The module defines, with kebab-case Racket names and an explicit `provide`:

1. **JSON-RPC + MCP error codes** — the five standard JSON-RPC codes plus the four
   MCP-specific codes, mirroring the `ProtocolErrorCode` enum in `enums.ts` and the
   standalone code constants in `constants.ts`.
2. **Protocol-version constants** — `LATEST`, `DEFAULT_NEGOTIATED`, and the full
   `SUPPORTED_PROTOCOL_VERSIONS` list, mirroring `constants.ts`.
3. **JSON-RPC version literal** — `JSONRPC_VERSION = "2.0"` (present in `constants.ts`;
   needed by guards/spec types in items 002–005, so it belongs here at the bottom).

This item is **constants only**. It does NOT include the per-request `_meta`
reserved-key constants (`RELATED_TASK_META_KEY`, `PROTOCOL_VERSION_META_KEY`,
`CLIENT_INFO_META_KEY`, `CLIENT_CAPABILITIES_META_KEY`, `LOG_LEVEL_META_KEY`), which
also live in `constants.ts`. See **Decisions & Trade-offs** for why, and the
forward-compat note for how to add them later without breaking this module.

### Exact source values (verified against the checkout — DO NOT guess)

All values below were read from the checkout on the queue date. The test harness
re-verifies them at run time, so they are reproduced here as the implementation
contract, not as a substitute for the test.

**From `typescript-sdk/packages/core/src/types/enums.ts`** (the `ProtocolErrorCode`
enum, lines 5–26):

| TS enum member | TS value (underscore literal) | Decimal | Racket name | Racket value |
|---|---|---|---|---|
| `ParseError` | `-32_700` | `-32700` | `PARSE-ERROR` | `-32700` |
| `InvalidRequest` | `-32_600` | `-32600` | `INVALID-REQUEST` | `-32600` |
| `MethodNotFound` | `-32_601` | `-32601` | `METHOD-NOT-FOUND` | `-32601` |
| `InvalidParams` | `-32_602` | `-32602` | `INVALID-PARAMS` | `-32602` |
| `InternalError` | `-32_603` | `-32603` | `INTERNAL-ERROR` | `-32603` |
| `ResourceNotFound` | `-32_002` | `-32002` | `RESOURCE-NOT-FOUND` | `-32002` |
| `MissingRequiredClientCapability` | `-32_003` | `-32003` | `MISSING-REQUIRED-CLIENT-CAPABILITY` | `-32003` |
| `UnsupportedProtocolVersion` | `-32_004` | `-32004` | `UNSUPPORTED-PROTOCOL-VERSION` | `-32004` |
| `UrlElicitationRequired` | `-32_042` | `-32042` | `URL-ELICITATION-REQUIRED` | `-32042` |

> **Critical wire-format note.** TS source writes these as **underscore-grouped
> numeric literals** (`-32_700`), which is a TypeScript lexical convenience equal to
> `-32700`. Racket has no underscore-grouping in integer literals — the Racket value
> is the plain integer `-32700`. The grep-diff test (below) MUST strip underscores
> from the TS side before comparing, or it will produce false mismatches. This is the
> single most likely cause of a spurious test failure; it is called out explicitly so
> the implementer normalizes both sides.

> **Standard codes also appear in `constants.ts`** (lines 44–48) as
> `PARSE_ERROR`, `INVALID_REQUEST`, `METHOD_NOT_FOUND`, `INVALID_PARAMS`,
> `INTERNAL_ERROR` with the same `-32_700`…`-32_603` values. The five standard codes
> are therefore defined in **both** TS files identically; the four MCP-specific codes
> (`-32002`, `-32003`, `-32004`, `-32042`) appear **only** in `enums.ts`. The test
> must look up each standard code in `constants.ts` and each MCP-specific code in
> `enums.ts` (see Testing Strategy for the exact grep targets).

**From `typescript-sdk/packages/core/src/types/constants.ts`** (lines 1–3, 41):

| TS constant | TS value | Racket name | Racket value |
|---|---|---|---|
| `LATEST_PROTOCOL_VERSION` | `'2025-11-25'` | `LATEST-PROTOCOL-VERSION` | `"2025-11-25"` |
| `DEFAULT_NEGOTIATED_PROTOCOL_VERSION` | `'2025-03-26'` | `DEFAULT-NEGOTIATED-PROTOCOL-VERSION` | `"2025-03-26"` |
| `SUPPORTED_PROTOCOL_VERSIONS` | `[LATEST, '2025-06-18', '2025-03-26', '2024-11-05', '2024-10-07']` | `SUPPORTED-PROTOCOL-VERSIONS` | `'("2025-11-25" "2025-06-18" "2025-03-26" "2024-11-05" "2024-10-07")` |
| `JSONRPC_VERSION` | `'2.0'` | `JSONRPC-VERSION` | `"2.0"` |

> **`SUPPORTED_PROTOCOL_VERSIONS` is order-significant and contains FIVE entries.**
> The first entry is `LATEST_PROTOCOL_VERSION` (`'2025-11-25'`) — in TS it is spliced
> in by variable reference, so the literal list shows four strings preceded by the
> `LATEST` identifier. The Racket list MUST contain `LATEST-PROTOCOL-VERSION` as its
> first element (preferably by reference: `(list LATEST-PROTOCOL-VERSION "2025-06-18"
> "2025-03-26" "2024-11-05" "2024-10-07")`) so a future bump to `LATEST` keeps the
> list head in sync, exactly as the TS source does. Note the queue/vision prose only
> names three versions; the **checkout is authoritative** and lists five. Do not drop
> `2025-06-18`, `2024-11-05`, or `2024-10-07`.

---

## Acceptance criteria

- [ ] `mcp/core/types/constants.rkt` exists as `#lang racket/base` (or `#lang racket`)
      with an explicit, curated `provide` listing every public binding (no
      `(provide (all-defined-out))`).
- [ ] All nine error-code bindings exist with the kebab-case names and exact integer
      values in the table above.
- [ ] All four version/JSON-RPC bindings exist: `LATEST-PROTOCOL-VERSION`,
      `DEFAULT-NEGOTIATED-PROTOCOL-VERSION`, `SUPPORTED-PROTOCOL-VERSIONS`,
      `JSONRPC-VERSION`.
- [ ] `SUPPORTED-PROTOCOL-VERSIONS` is a list of exactly five strings in the exact
      order `("2025-11-25" "2025-06-18" "2025-03-26" "2024-11-05" "2024-10-07")`, with
      element 0 equal to `LATEST-PROTOCOL-VERSION` (assert `(equal? (first SUPPORTED...)
      LATEST-PROTOCOL-VERSION)`).
- [ ] A rackunit test at `mcp/core/types/test/constants-test.rkt` asserts **every**
      error code and version constant matches the `typescript-sdk/` checkout
      **byte-for-byte** by reading the actual TS source files at test time
      (grep/regex-diff against `constants.ts` and `enums.ts`), NOT by hard-coding
      expected values a second time. (Hard-coded mirror values are permitted only as a
      secondary belt-and-suspenders check; the primary assertion reads the TS files.)
- [ ] The test normalizes TS underscore-grouped literals (`-32_700` → `-32700`) before
      comparing.
- [ ] The test fails loudly (not silently skips) if a TS source file is missing,
      unreadable, or a constant name is not found in it — a missing checkout must be a
      hard error, never a passed test.
- [ ] `raco test mcp/core/types/test/constants-test.rkt` passes (exit 0).
- [ ] `raco test mcp/core/types/` passes (exit 0) — confirms the module and its test
      compile and load cleanly within the collection.
- [ ] **Portability:** loading `mcp/core/types/constants.rkt` pulls in no
      subprocess/socket module. (Trivially true for a pure-data module; a dedicated
      restricted-load test is the responsibility of item 008, but this module must not
      introduce any such dependency. Confirm by reading the module's `require` list —
      it should require nothing beyond `racket/base` plus, in the test, `rackunit` and
      string/file utilities.)
- [ ] Parity-matrix discipline: the roadmap §9 / progress.md rows for `constants.ts` /
      `enums.ts` under `core/types/*` are advanced toward `partial` per Stage S1
      discipline on completion (see Completion Reminder).

---

## Implementation steps

1. **Create the collection directories** if absent:
   `mcp/core/types/` and `mcp/core/types/test/`.
2. **Write `mcp/core/types/constants.rkt`.** Use `#lang racket/base`. Define each
   binding with `define`. Define `LATEST-PROTOCOL-VERSION` first, then build
   `SUPPORTED-PROTOCOL-VERSIONS` by reference to it (mirroring the TS splice). Group
   the file with brief section comments matching the TS layout
   (`; --- protocol versions ---`, `; --- JSON-RPC ---`,
   `; --- standard JSON-RPC error codes ---`, `; --- MCP-specific error codes ---`),
   keeping comment density similar to the terse TS source.
3. **Add the explicit `provide`.** List all 13 bindings by name. Do not export
   `all-defined-out`. This is the curated public surface for this module (item 008
   re-exports it via the barrels).
4. **Write the test** `mcp/core/types/test/constants-test.rkt` (see Testing Strategy
   for the algorithm). Locate the TS checkout via a path relative to the test file so
   it works regardless of the invoking cwd:
   resolve `typescript-sdk/packages/core/src/types/{constants,enums}.ts` from the repo
   root (compute the repo root from the test file's path, e.g. with
   `(build-path (collection-path ...) ...)` or a relative `../../../../..` walk —
   prefer a robust path computation over assuming cwd).
5. **Run** `raco test mcp/core/types/` and fix any mismatch. Most-likely failure is
   the underscore-literal normalization (step in Testing Strategy).
6. **Update progress + parity matrix** (see Completion Reminder).

---

## Testing strategy

The required test is a **byte-for-byte parity test against the live TS checkout**, not
a self-consistency test. The point is to fail if the upstream SDK changes a value (the
SDK is pre-alpha and a moving target — vision §7).

**Test file:** `mcp/core/types/test/constants-test.rkt` (`#lang racket/base`,
`require rackunit`, plus `racket/string`, `racket/port`/`racket/file`, `racket/runtime-path`).

**Algorithm:**

1. **Resolve TS source paths** robustly relative to the test file (use
   `define-runtime-path` so the path is anchored to the source location, not cwd):
   - `constants.ts` → `<repo>/typescript-sdk/packages/core/src/types/constants.ts`
   - `enums.ts` → `<repo>/typescript-sdk/packages/core/src/types/enums.ts`
2. **Guard the checkout:** if either file does not exist, `(fail "...")` with a clear
   message naming the missing path. Do **not** skip — a missing checkout is a hard
   failure (acceptance criterion).
3. **Extract TS values with regexes**, normalizing underscores:
   - Helper `(ts-int-named src name)` — finds the assignment for `name` (in `enums.ts`
     the form is `Name = -32_700,`; in `constants.ts` it is
     `export const NAME = -32_700;`), captures the numeric literal, removes `_`
     characters, and parses to an exact integer. Return `#f` / fail if not found.
   - Helper `(ts-string-named src name)` — finds `export const NAME = '...'` /
     `"..."`, captures the quoted contents.
   - Helper `(ts-string-list-named src name)` — finds the `SUPPORTED_PROTOCOL_VERSIONS`
     array literal, resolves the leading `LATEST_PROTOCOL_VERSION` reference to its
     string value, and returns the ordered list of five strings.
4. **Assertions (each its own `check-equal?` with a descriptive message):**
   - Standard codes read from **`constants.ts`**: `PARSE_ERROR`, `INVALID_REQUEST`,
     `METHOD_NOT_FOUND`, `INVALID_PARAMS`, `INTERNAL_ERROR` ⇔ the Racket
     `PARSE-ERROR` … `INTERNAL-ERROR`.
   - The same five standard codes ALSO read from **`enums.ts`** (`ParseError` …
     `InternalError`) ⇔ the Racket bindings — confirming both TS files agree and the
     Racket module matches both.
   - MCP-specific codes read from **`enums.ts`** only: `ResourceNotFound`,
     `MissingRequiredClientCapability`, `UnsupportedProtocolVersion`,
     `UrlElicitationRequired` ⇔ `RESOURCE-NOT-FOUND`,
     `MISSING-REQUIRED-CLIENT-CAPABILITY`, `UNSUPPORTED-PROTOCOL-VERSION`,
     `URL-ELICITATION-REQUIRED`.
   - `LATEST_PROTOCOL_VERSION` (constants.ts) ⇔ `LATEST-PROTOCOL-VERSION`.
   - `DEFAULT_NEGOTIATED_PROTOCOL_VERSION` (constants.ts) ⇔
     `DEFAULT-NEGOTIATED-PROTOCOL-VERSION`.
   - `SUPPORTED_PROTOCOL_VERSIONS` (constants.ts, resolved list) ⇔
     `SUPPORTED-PROTOCOL-VERSIONS` — assert `check-equal?` on the whole list (order
     and length both matter).
   - `JSONRPC_VERSION` (constants.ts) ⇔ `JSONRPC-VERSION`.
5. **Structural self-checks (secondary):**
   - `(check-equal? (length SUPPORTED-PROTOCOL-VERSIONS) 5)`.
   - `(check-equal? (car SUPPORTED-PROTOCOL-VERSIONS) LATEST-PROTOCOL-VERSION)`.
   - `(check-true (for/and ([c (list PARSE-ERROR ...)]) (and (exact-integer? c) (negative? c))))`.

**Edge cases the test must cover (do not leave these implicit):**
- **Underscore literals:** `-32_700` must compare equal to Racket `-32700`. Add an
  explicit regression check that the extractor returns `-32700` for `ParseError`.
- **Standard codes duplicated across two files:** assert both `constants.ts` and
  `enums.ts` independently. A divergence upstream must fail.
- **Missing constant name:** if a regex finds nothing, fail with the name (so a future
  TS rename is diagnosable), not a silent `#f` that passes.
- **List order/length drift:** `SUPPORTED-PROTOCOL-VERSIONS` must be checked as a whole
  ordered list, not membership — a reordering or an added/removed version must fail.
- **`LATEST` splice integrity:** assert the Racket list head is `eq?`/`equal?` to
  `LATEST-PROTOCOL-VERSION`, mirroring the TS reference splice.
- **Negative / sign handling:** ensure the regex captures the leading `-`.

---

## Dependencies

- **Upstream work items:** none. This is the first item in queue-001 and the bottom of
  the entire dependency graph (roadmap S1: "Dependencies: None").
- **Downstream consumers (informational):** item 002 (guards — needs `JSONRPC-VERSION`),
  items 003–005 (spec types / façade), items 006–007 (error layer — need the error
  codes), item 008 (barrels re-export this module's `provide`).
- **Tooling/runtime:** Racket ≥ 8.x (`raco`, `rackunit`); the `typescript-sdk/`
  checkout present at the repo root (required by the parity test, see Testing
  Prerequisites).

---

## Project-specific adaptations (Racket / raco / rackunit)

This template's "Required Services / database / API endpoint" framing does not apply:
**this is a pure-data module with no external services, no I/O at module load, no
network, and no database.** The adaptations are:

- **Language:** `#lang racket/base`; `racket/contract` is **not** needed here (no
  procedures to guard; bare constants). Keep `require`s minimal for the Portability NFR.
- **Naming:** kebab-case for all bindings (`PARSE-ERROR`, `LATEST-PROTOCOL-VERSION`).
  Screaming-kebab (all-caps-kebab) is the idiomatic Racket convention for module-level
  constants and mirrors the TS `SCREAMING_SNAKE_CASE`, so it is used here.
- **Public surface:** explicit `(provide …)` — never `all-defined-out` — to mirror the
  TS curated `core/public` boundary (architecture §1.3).
- **Test framework:** `rackunit`; tests live under `mcp/core/types/test/` and are
  discovered by `raco test`.
- **Parity test is file-reading, not value-mirroring:** the canonical assertion reads
  the actual TS `.ts` files at test time (the "grep-diff against the checkout" the queue
  requires), so the test is a true upstream-drift detector.
- **No `_meta` constants in this item:** those `constants.ts` keys are deferred to the
  S2 `metadata-utils` work (vision §4.1 maps them to
  `mcp/core/shared/metadata-utils.rkt`). This item stays scoped to error codes +
  version constants per the queue text. The module is structured so they can be added
  later with an additive `provide` and no change to existing bindings.

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None.** This module performs no I/O and contacts no service. The only externally
required artifacts are:

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime | compile + run module and tests (`raco`, `rackunit`) | system install (`racket --version` ≥ 8.0) | n/a |
| `typescript-sdk/` checkout | the parity test reads `constants.ts` / `enums.ts` from it | already present at repo root: `typescript-sdk/packages/core/src/types/{constants,enums}.ts` | n/a |

There are explicitly **no** databases, message queues, HTTP servers, or network
dependencies for this item.

### Environment Configuration

- **Environment variables:** none required.
- **Secrets:** none.
- **Config files:** none.
- **Ports:** none must be free.
- **Working directory:** run `raco test` from the **repo root**
  (`/home/rev/Linux/Projects/racket_mcp`) so the `mcp/...` collection path resolves; the
  test itself anchors the TS-checkout path to the test source location, so it does not
  depend on cwd, but `raco test mcp/...` collection resolution does.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0.
  - `test -f typescript-sdk/packages/core/src/types/constants.ts && test -f typescript-sdk/packages/core/src/types/enums.ts` → both exist.

### Manual Validation Checklist

- [ ] **Build/compile succeeds:** `raco make mcp/core/types/constants.rkt` (or load it
      in `racket`) compiles with no errors.
- [ ] **Module loads in isolation:** `racket -e '(require (file "mcp/core/types/constants.rkt"))'`
      run from repo root succeeds.
- [ ] **Tests pass:** `raco test mcp/core/types/test/constants-test.rkt` → all checks
      pass, exit 0.
- [ ] **Collection tests pass:** `raco test mcp/core/types/` → exit 0.
- [ ] **Services started:** N/A (no services).
- [ ] **Application runs:** N/A (library module; "running" = the require + REPL inspect
      below).
- [ ] **Feature verified (REPL):** from repo root,
      `racket -e '(require (file "mcp/core/types/constants.rkt")) (list PARSE-ERROR UNSUPPORTED-PROTOCOL-VERSION URL-ELICITATION-REQUIRED LATEST-PROTOCOL-VERSION SUPPORTED-PROTOCOL-VERSIONS)'`
      prints `(-32700 -32004 -32042 "2025-11-25" ("2025-11-25" "2025-06-18" "2025-03-26" "2024-11-05" "2024-10-07"))`.
- [ ] **Data verified (upstream drift):** temporarily edit a value in the test's
      expected mirror (or the TS file in a scratch copy) and confirm the test FAILS —
      proving the parity assertion is live, not vacuous. Revert after.
- [ ] **Missing-checkout failure path:** temporarily rename the TS file and confirm the
      test FAILS with a clear message (not a pass/skip). Revert after.
- [ ] **Health checks pass:** N/A (no running service).

### Expected Outcomes

Concrete, verifiable results — the module MUST export exactly these bindings with these
values:

**Error codes (9):**
- `PARSE-ERROR` = `-32700`
- `INVALID-REQUEST` = `-32600`
- `METHOD-NOT-FOUND` = `-32601`
- `INVALID-PARAMS` = `-32602`
- `INTERNAL-ERROR` = `-32603`
- `RESOURCE-NOT-FOUND` = `-32002`
- `MISSING-REQUIRED-CLIENT-CAPABILITY` = `-32003`
- `UNSUPPORTED-PROTOCOL-VERSION` = `-32004`
- `URL-ELICITATION-REQUIRED` = `-32042`

**Version / JSON-RPC (4):**
- `LATEST-PROTOCOL-VERSION` = `"2025-11-25"`
- `DEFAULT-NEGOTIATED-PROTOCOL-VERSION` = `"2025-03-26"`
- `SUPPORTED-PROTOCOL-VERSIONS` = `("2025-11-25" "2025-06-18" "2025-03-26" "2024-11-05" "2024-10-07")` (5 elements, ordered, head = `LATEST-PROTOCOL-VERSION`)
- `JSONRPC-VERSION` = `"2.0"`

**Test outcome:** `raco test mcp/core/types/` reports all checks passing, 0 failures, 0
errors; the parity test's check count is ≥ 18 (9 codes × from-enums + 5 codes
from-constants + 3 version/jsonrpc + structural self-checks).

**Total public bindings provided:** 13.

### Validation Results

```markdown
## Validation Results
- [ ] Service started: N/A (pure-data module, no services)
- [ ] Application started successfully: N/A (library; `require` + REPL inspect succeeded)
- [ ] Build verified: `raco make mcp/core/types/constants.rkt` clean
- [ ] Module load verified: `(require (file ".../constants.rkt"))` succeeds
- [ ] Tests verified: `raco test mcp/core/types/` → 0 failures, 0 errors
- [ ] Parity assertion is live: deliberate-mismatch test FAILED as expected, then reverted
- [ ] Missing-checkout path: renamed TS file → test FAILED with clear message, then reverted
- [ ] Constant values verified (13 bindings) against `typescript-sdk/` byte-for-byte
- [ ] Database tables verified: N/A
- [ ] Seed data verified: N/A
- [ ] API endpoints verified: N/A
- [ ] Screenshots captured: N/A (no UI)
```

---

## Decisions & Trade-offs

Recorded during implementation (2026-06-16):

- **Binding names:** Adopted the recommended screaming-kebab spellings verbatim — all 9
  error codes plus `LATEST-PROTOCOL-VERSION`, `DEFAULT-NEGOTIATED-PROTOCOL-VERSION`,
  `SUPPORTED-PROTOCOL-VERSIONS`, `JSONRPC-VERSION` (13 bindings). No changes from the
  table above.
- **`provide`:** Explicit curated `(provide …)` listing all 13 names, grouped by section
  (versions / JSON-RPC / standard codes / MCP-specific codes). No `all-defined-out`.
- **`SUPPORTED-PROTOCOL-VERSIONS` splice:** Built with
  `(list LATEST-PROTOCOL-VERSION "2025-06-18" …)` so the head stays in sync with a future
  `LATEST` bump, mirroring the TS array's variable reference. The structural self-check
  asserts `(car SUPPORTED-PROTOCOL-VERSIONS)` equals `LATEST-PROTOCOL-VERSION`.
- **Requires:** `constants.rkt` requires nothing beyond `#lang racket/base` (Portability
  NFR). The test requires `rackunit`, `racket/file`, `racket/string`, `racket/list`,
  `racket/runtime-path`.
- **TS-checkout path resolution:** Used `define-runtime-path` with a `../../../../`
  relative walk from the test source file to the repo root. `define-runtime-path` anchors
  the path to the source/compiled location rather than the invoking cwd, so the test is
  cwd-robust (only `raco test mcp/...` collection resolution needs the repo root, which
  the spec already requires). Chosen over `collection-path` because no `info.rkt`
  collection is registered yet at this stage.
- **Extractor location:** The regex extractors live **inline** in the test module (only
  used here). Three helpers: `ts-const-int`/`ts-const-string`/`ts-supported-list` for
  `constants.ts` and `ts-enum-int` for `enums.ts`.
- **Regex flavor — implementation note:** Racket's plain `regexp` does NOT support `\s`;
  only `pregexp` does. All four extractors use `pregexp`. (The initial pass used `regexp`
  for the constants.ts helpers and silently matched nothing — caught by the loud
  "not found" failure, which is exactly the diagnosability the spec mandates.)
- **Underscore normalization:** `parse-ts-int` strips `_` before `string->number`, with an
  explicit regression check that `ParseError` reads as `-32700`.
- **Last-enum-member edge case:** `ts-enum-int` anchors on `(?m:^\s*Name\s*=…)` and
  tolerates an optional trailing comma OR end-of-line `(?:,|$)`, so
  `UrlElicitationRequired = -32_042` (no trailing comma) is captured, not dropped.
- **Dual-file standard codes:** The 5 standard codes are asserted against BOTH
  `constants.ts` and `enums.ts` independently (10 checks); the 4 MCP-specific codes
  against `enums.ts` only. Total: 22 live checks.
- **Loud failure:** A missing/unreadable TS file or a not-found constant calls
  `(fail …)` naming the path/constant — verified by renaming the TS file (failed loudly)
  and by mutating a Racket value (drift detected, 2 checks failed), both reverted.
- **Scope guard — no `_meta` constants:** Confirmed NONE of the five `_meta` reserved-key
  constants (`RELATED_TASK_META_KEY`, `PROTOCOL_VERSION_META_KEY`, `CLIENT_INFO_META_KEY`,
  `CLIENT_CAPABILITIES_META_KEY`, `LOG_LEVEL_META_KEY`) were added. They remain deferred to
  the S2 `metadata-utils` work (M5c). The explicit `provide` allows them to be added later
  additively without touching existing bindings.

---

## Completion Reminder

On completion, the implementer MUST:

1. **Update `docs/aide/progress.md`** — advance the `mcp/core/types/constants.rkt`
   deliverable line under Stage S1 from 📋 → 🚧 (when starting) → ✅ (when delivered and
   acceptance criteria pass). Do not check the Stage-S1 *acceptance boxes* that depend
   on other items (round-trip fixtures, decode path, etc.); only the constants-related
   acceptance box ("Error codes + version constants match TS `constants.ts`/`enums.ts`
   byte-for-byte") may be checked once this item's test passes. Never revert an icon
   backward.
2. **Touch the parity-matrix rows** per Stage S1 discipline (roadmap "Parity discipline
   applies to every stage"): advance the roadmap §9 / progress rows for `constants.ts`
   and `enums.ts` (under `core/types/*`) toward `partial` (the structs/constants exist;
   full conformance exercise lands later). Per item 009 the broader `core/types/*` row
   flip to `partial` is the S1 closeout's job, so here record that the constants
   sub-rows are satisfied without prematurely marking sibling rows.
3. Leave the four sibling `core/types/*` deliverables (spec types, façade, guards,
   errors) at their current status — this item delivers only `constants.rkt`.
