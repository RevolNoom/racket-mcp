# Work Item 010: Validator-provider port (M3)

> **Queue:** `docs/aide/queue/queue-002.md` — Item 010
> **Stage:** S2 (Foundation: validators, schema, shared utilities — L0 part 2)
> **Module:** M3 (Validators) — the **port** sub-unit (`mcp/core/validators/provider.rkt`); the default provider is item 011, the schema util is item 012.
> **Source vision:** `docs/aide/vision.md` §4.5 (pluggable JSON-Schema validator; Ajv/cfWorker collapse to one Racket-native provider), §8 (Zod/Standard-Schema-lib + cfWorker exclusions), §6 (Portability NFR — core loads without subprocess/socket; Minimal-deps NFR).
> **Source roadmap:** `docs/aide/roadmap.md` Stage S2 → Deliverables line 111 (`mcp/core/validators/provider.rkt` — validator-provider port via `racket/generic`: compile JSON Schema → reusable validator; validate value → ok/errors; mirrors `validators/types.ts`) + Testing/validation criteria.
> **Source architecture:** `docs/aide/architecture.md` M3 (lines 83–88 — Validator-provider port `gen:`-style; default provider implements it; port = dependency-inversion seam), §1.3 (public/internal boundary, curated `main.rkt`), §4.1 (Ports via `racket/generic`; Runtime-neutral core L0–L2 import no subprocess/socket).
> **Reference impl (authoritative):** MCP TypeScript SDK v2 at `typescript-sdk/` — `packages/core/src/validators/types.ts` (the `jsonSchemaValidator` interface — a **single fused method** `getValidator<T>(schema) → (input) => JsonSchemaValidatorResult<T>`); `packages/core/src/validators/fromJsonSchema.ts` (the wrapper); `packages/core/src/validators/types.examples.ts` (the implementer example). **This item asserts NO TS-baseline parity** — keyword semantics + an Ajv-validated baseline are item 011's job. The TS files here are read only for the **interface shape**, not for value-level conformance.
> **Status:** 📋 Planned (see Completion Reminder)

---

## Description

Implement `mcp/core/validators/provider.rkt`, the **pluggable JSON-Schema validator-provider port** for `racket-mcp`. This is the dependency-inversion seam (architecture M3, §4.1) that lets the default Racket-native provider (item 011) and any future vetted-library provider be swapped **without changing callers** (the schema util item 012, and the high-level server in S6b that consumes it via item 012).

The TS source interface (`validators/types.ts`) is a **single fused method**:

```ts
export interface jsonSchemaValidator {
    getValidator<T>(schema: JsonSchemaType): JsonSchemaValidator<T>;
}
// JsonSchemaValidator<T> = (input: unknown) => JsonSchemaValidatorResult<T>
// JsonSchemaValidatorResult<T> =
//   | { valid: true;  data: T;         errorMessage: undefined }
//   | { valid: false; data: undefined; errorMessage: string }
```

`getValidator` does **compile + validate in one** call shape: it takes a schema and returns a *closure* that validates inputs. The Racket port **deliberately splits this into two explicit operations** (see Decisions & Trade-offs (a)):

1. **compile** — `(provider, JSON-Schema) → opaque compiled-validator handle`. Compile once; reuse the handle for many validations.
2. **validate** — `(compiled-handle, value) → result` — an **ok** result carrying the validated value, or an **error** result carrying a list of **structured errors** (each bearing a `path` + `message`).

This factoring (compile-once / validate-many) matches the TS docstring's stated intent — *"Return validator functions that can be called multiple times; handle schema compilation/caching internally"* (`validators/types.ts:33–36`) — while being more idiomatic in Racket and exposing the compiled handle as a first-class value. It is **not** a 1:1 mirror of the fused TS method.

This item ships **only the port + result types + a test stub provider**. It does **not** implement any JSON-Schema keyword evaluation (item 011) and does **not** implement schema normalization (item 012). The module imports **only S1** (`mcp/core/types`, `mcp/core/errors` via `mcp/core/main.rkt`), preserving the Portability NFR.

### The interface, concretely (the build contract — verified against the checkout, DO NOT guess)

All names below are the **recommended** Racket surface, kebab-cased per the established S1 convention (see items 001/008). The implementer may refine names during implementation but MUST keep the two-op split, the structured error shape, and the import restriction.

**1. The generic interface (`racket/generic`).** Define:

```racket
(define-generics json-schema-validator-provider
  ;; provider + JSON Schema (a jsexpr) -> opaque compiled-validator handle
  (provider-compile json-schema-validator-provider schema))
```

> **Design decision — where `validate` lives (see Decisions (a)).** `compile` is a **method on the provider** (it is the provider's job to interpret the schema). `validate` is a **separate operation on the compiled handle**, NOT a second method on the provider. Two acceptable encodings, pick one and document it:
> - **(Recommended) Closure-in-handle.** `provider-compile` returns a `compiled-validator` struct that **carries the validate closure** (`(struct compiled-validator (validate-proc) ...)`), and a module-level `(validate handle value)` procedure applies it. This mirrors the TS "returns a validator function" shape most directly — the handle *is* the closure, wrapped in a struct for opacity + a stable predicate.
> - **(Alternative) Second generic on the handle.** Make the compiled handle itself implement a `gen:compiled-validator` interface with a `(compiled-validate handle value)` method. More machinery; only choose this if a provider needs the handle to dispatch polymorphically. Record the choice in Decisions.

**2. The result type.** Define a closed two-variant result. Recommended as two structs under a common predicate, with accessors and constructors:

```racket
;; ok variant — carries the validated value
(struct validation-ok (value) #:transparent)
;; error variant — carries a non-empty list of structured errors
(struct validation-errors (errors) #:transparent)   ; errors : (listof validation-error)
;; one structured error — path + message (the deliberate Racket enrichment)
(struct validation-error (path message) #:transparent)
;;   path    : (listof (or/c string? exact-nonnegative-integer?))  ; JSON Pointer-ish segments; '() = root
;;   message : string?
```

Provide predicates `validation-ok?` / `validation-errors?` and a `validation-result?` umbrella predicate (`(or/c validation-ok? validation-errors?)`), plus accessors `validation-ok-value`, `validation-errors-errors`, `validation-error-path`, `validation-error-message`.

> **Mapping onto TS `{valid, data, errorMessage}` (see Decisions (b)).** TS returns a single `errorMessage` **string** on failure and `data` on success. The Racket shape is a **superset**: `validation-ok` ↔ `{valid:true, data}`; `validation-errors` ↔ `{valid:false, errorMessage}` but **richer** — a *list* of `validation-error`, each with a structured `path` (which JSON pointer location failed) in addition to the `message`. TS has no `path`; this is a deliberate Racket enhancement that item 011's provider populates (per-keyword failures with their location) and item 012's schema util / S6b's server can surface to callers. A provider that only has a flat message MAY emit a single `(validation-error '() "msg")` (root path) — the shape degrades gracefully to the TS single-string case.

**3. The public `provide` surface (explicit, curated — NO `all-defined-out`).** Exactly:
- the generic: `gen:json-schema-validator-provider` (whatever `define-generics` binds), `json-schema-validator-provider?`, `provider-compile`;
- the validate entry point: `validate` (or `compiled-validate`, per the chosen encoding);
- the compiled-handle predicate: `compiled-validator?` (so callers/tests can assert a handle was produced) — keep the struct's **fields opaque** (do not provide field accessors that leak the closure);
- the result API: `validation-result?`, `validation-ok` / `validation-ok?` / `validation-ok-value`, `validation-errors` / `validation-errors?` / `validation-errors-errors`, `validation-error` / `validation-error?` / `validation-error-path` / `validation-error-message`.

No internal helper (e.g. a closure-builder, a default error formatter) may appear in `provide`.

**4. Imports — S1 ONLY.** The module requires `mcp/core/main.rkt` (the S1 barrel: types M1 + errors M2) and `racket/generic` (+ `racket/contract` if contracts are attached). It MUST NOT require any transport, engine, role, subprocess, or socket module. This is an acceptance criterion enforced by a restricted-load test (mirrors item 008's mechanism).

> **What S1 is actually used for here.** The port itself is largely structural, so the S1 *use* is light: a JSON Schema is a `jsexpr` (the `json-object?`/jsexpr notion from `mcp/core/types`), and a provider that wants to raise on a malformed schema may use `make-mcp-error` / `make-protocol-error` from `mcp/core/errors.rkt`. The point of requiring the S1 barrel (rather than nothing) is (a) to keep the validator collection's dependency story uniform with the rest of L0, and (b) to give item 011 the error constructors it will need without item 011 widening the require list. If the implementer finds the port body needs *no* S1 binding at all, requiring only `mcp/core/types` (not the full barrel) is acceptable — record the final require list in Decisions; the restricted-load test is the real gate.

### Scope guard (explicit — do NOT cross these lines)

- **NO JSON-Schema keyword evaluation** (`type`, `properties`, `required`, `enum`, `items`, `format`, …) — that is the default provider, **item 011**. This item's only concrete validator is a **trivial test stub** living in the test file.
- **NO schema normalization** (contract-or-JSON-Schema bridging, wire-schema emission) — that is **item 012** (`util/schema.rkt`).
- **NO Ajv / TS-baseline parity assertion** — item 010 asserts no behavioural parity with a TS validator; item 011 owns the TS Ajv-validated cross-check. This item's test asserts only *result shape* through a stub.

---

## Acceptance Criteria

- [ ] `mcp/core/validators/provider.rkt` exists as `#lang racket/base` (or `#lang racket`) with an explicit, curated `provide` (no `(provide (all-defined-out))`).
- [ ] A `racket/generic` interface is defined with a **compile** operation `(provider-compile provider schema)` mapping a provider + JSON Schema (a `jsexpr`) to an **opaque compiled-validator handle**.
- [ ] A **validate** operation (`(validate handle value)` or `(compiled-validate handle value)`, per the chosen encoding) maps a compiled handle + value to a `validation-result?` — either `validation-ok` (carrying the value) or `validation-errors` (carrying a non-empty `(listof validation-error)`).
- [ ] The **structured error** shape is `(validation-error path message)` with `path` a list of string/integer segments (`'()` = root) and `message` a string; predicates + accessors are provided.
- [ ] The result type is a closed two-variant set under a `validation-result?` umbrella predicate; `validation-ok?` and `validation-errors?` are mutually exclusive and exhaustive.
- [ ] The compiled handle is **opaque**: `compiled-validator?` is provided, but the struct's internal closure/field is NOT exposed via a provided accessor.
- [ ] The module imports **only S1** (`mcp/core/main.rkt` or `mcp/core/types`, + `racket/generic`/`racket/contract`). It requires NO transport/engine/role/subprocess/socket module. **Verified by a restricted-namespace load test** (mirrors item 008 Part C): a fresh `(make-base-namespace)` requiring `provider.rkt` and walking `module->imports` transitively shows EMPTY intersection with the banned set (`racket/system`, `racket/tcp`, `racket/udp`, `net/url`, `net/http-client`, `net/sendurl`, `racket/sandbox`).
- [ ] A unit test at `mcp/core/validators/test/provider-test.rkt` defines a **trivial stub provider** that satisfies the generic interface (e.g. accepts a value iff it `equal?`s an expected literal, or a trivial `string?`/`number?` type check), `provider-compile`s a schema through it, and `validate`s **both** an ok value and an error value, asserting the result shape (`validation-ok?` + recovered value for the good case; `validation-errors?` + a `validation-error` with the expected `path`/`message` for the bad case).
- [ ] The stub-provider test also asserts the **opacity / shape contract**: a `validation-ok` round-trips its value via `validation-ok-value`; a `validation-errors` exposes `validation-errors-errors` as a non-empty list whose elements are `validation-error?` with string `message` and list `path`.
- [ ] `raco test mcp/core/validators/` passes (exit 0) — module + test compile and run cleanly within the collection.
- [ ] `raco make mcp/core/validators/provider.rkt` exits 0 (compiles clean, no warnings about missing/non-portable modules).
- [ ] Parity-matrix discipline: per Stage S2 the `validators/*` row is advanced toward `partial` (the port + result types exist; full conformance + the default-provider keyword exercise land with items 011/017/018 and S9). Update `docs/aide/progress.md` per the Completion Reminder.

---

## Implementation Steps

1. **Create the collection directories** if absent: `mcp/core/validators/` and `mcp/core/validators/test/`.
2. **Read the TS interface** (`typescript-sdk/packages/core/src/validators/types.ts` + `types.examples.ts`) once more for the **shape** (single fused `getValidator`; the `{valid,data,errorMessage}` result). Confirm you are porting the *shape*, then deliberately split it per Decisions (a).
3. **Write `mcp/core/validators/provider.rkt`.** Use `#lang racket/base`. In order:
   - `(require racket/generic (only-in "../main.rkt" …))` (require the S1 barrel; pull only the error constructors / jsexpr predicate you actually use — record the final list in Decisions). Add `racket/contract` only if you attach `contract-out`.
   - Define the result structs: `validation-error`, `validation-ok`, `validation-errors` (all `#:transparent`); define `validation-result?` as `(or/c validation-ok? validation-errors?)`.
   - Define the generic `(define-generics json-schema-validator-provider (provider-compile json-schema-validator-provider schema))`.
   - Define the compiled handle + `validate` per the chosen encoding (recommended: `(struct compiled-validator (validate-proc) #:transparent)` kept opaque in `provide`, plus `(define (validate handle value) ((compiled-validator-validate-proc handle) value))`).
   - Add the explicit `(provide …)` block enumerating exactly the surface in Description §3.
4. **Write the stub-provider test** `mcp/core/validators/test/provider-test.rkt` (see Testing Strategy). Define a stub struct implementing `gen:json-schema-validator-provider`, compile a schema, validate ok + error values, assert shapes. Add the restricted-load portability sub-test (reuse the item-008 walk helper — copy or factor it).
5. **Run** `raco make mcp/core/validators/provider.rkt` then `raco test mcp/core/validators/`. Fix any failure.
6. **Update progress + parity matrix** (see Completion Reminder).

---

## Testing Strategy

The test is a **shape/contract test through a stub provider** — explicitly NOT a TS-baseline parity test (that is item 011). Two test concerns: (1) the interface round-trips ok/error result shapes; (2) the module is portable (S1-only).

**Test file:** `mcp/core/validators/test/provider-test.rkt` (`#lang racket/base`; `(require rackunit racket/generic (file "../provider.rkt"))` plus `racket/set`/`racket/path` for the portability walk).

### Part 1 — stub provider, compile + validate ok/error

1. **Define a trivial stub provider** implementing `gen:json-schema-validator-provider`. Simplest sufficient stub: a provider whose `provider-compile` reads an expected value out of the schema (e.g. `(hash-ref schema 'const)`) and returns a `compiled-validator` whose validate-proc returns `(validation-ok value)` when `(equal? value expected)`, else `(validation-errors (list (validation-error '() (format "expected ~a, got ~a" expected value))))`. (A `type`-style stub — accept iff `(string? value)` — is equally acceptable; pick one and keep it trivial — NO real keyword logic.)
2. **Compile** a schema through it: `(define h (provider-compile stub (hasheq 'const 42)))`; assert `(compiled-validator? h)`.
3. **Validate ok:** `(define r (validate h 42))`; assert `(validation-ok? r)` and `(check-equal? (validation-ok-value r) 42)`; assert `(validation-result? r)` and `(not (validation-errors? r))`.
4. **Validate error:** `(define e (validate h 7))`; assert `(validation-errors? e)` and `(not (validation-ok? e))`; assert `(validation-errors-errors e)` is a non-empty list; take its first element `ve` and assert `(validation-error? ve)`, `(string? (validation-error-message ve))`, `(list? (validation-error-path ve))` (here `'()` = root). Assert the message mentions the mismatch (substring check).
5. **Path-bearing error (the Racket enrichment):** construct a `(validation-error '("a" "b") "deep failure")` directly (or via a stub that emits a nested path) and assert `(validation-error-path ve)` → `'("a" "b")` — proving the shape carries a structured path, not just a string (Decisions (b)).

### Part 2 — restricted-namespace portability (S1-only)

Reuse the transitive `module->imports` walk from item 008 (Part C) — a fresh `(make-base-namespace)`, `namespace-require` the provider, walk imports with `current-load-relative-directory` threaded per module dir, assert the banned set (`racket/system racket/port racket/tcp racket/udp net/url net/http-client net/sendurl racket/sandbox`) has empty intersection with the visited set. Factor the walk into a small shared helper or copy it inline; record the choice in Decisions. (Item 017 adds the collection-wide S2 portability sweep; this item proves `provider.rkt` itself is clean so item 011 inherits a known-good base.)

### Part 3 — interface conformance

Assert the generic actually dispatches: `(check-true (json-schema-validator-provider? stub))`; assert a non-provider value is rejected: `(check-false (json-schema-validator-provider? 42))`. (Confirms the stub really implements the interface rather than the test accidentally calling a plain procedure.)

**Edge cases the test must cover (do not leave implicit):**
- **Empty error list is invalid:** `validation-errors` must carry a *non-empty* list — assert the stub's error case has `≥1` element. (A failure with zero errors is a malformed result.)
- **Root path is `'()`, not `#f`/`""`:** assert a root-level error's path is the empty list, so consumers can uniformly treat `path` as a segment list.
- **Mutual exclusivity:** `validation-ok?` and `validation-errors?` are never both true for one result.
- **Opacity:** there is no provided accessor that returns the validate closure from a `compiled-validator` (a `dynamic-require` for the field accessor name → `'not-found`, mirroring item 008's curation check).

---

## Dependencies

- **Upstream work items:** Stage S1 items 001–009 (✅ complete) — specifically `mcp/core/main.rkt` (item 008 barrel: types M1 + errors M2). This item requires the S1 public surface and nothing higher.
- **Downstream consumers (informational):**
  - **Item 011** (`from-json-schema.rkt`) — the default Racket-native provider implements THIS port; it populates `validation-error` path+message from real keyword evaluation and is the first item to assert TS Ajv-baseline parity.
  - **Item 012** (`util/schema.rkt`) — the schema-normalization util produces a validation handle that **delegates to this port** (compiles via a provider, validates via the handle).
  - **Item 017** — the S2 collection-wide restricted-load portability sweep includes `mcp/core/validators`.
  - **Item 018** — the S2 demo registers a JSON Schema via the M3 provider and validates a good + bad value (showing structured errors).
  - **S6b** high-level server consumes validation (via item 012) for tool I/O.
- **Tooling/runtime:** Racket ≥ 8.x (`raco`, `rackunit`). The `typescript-sdk/` checkout is present at the repo root but is read for the **interface shape only** — NO parity test reads it for this item (contrast item 001, whose test reads the TS files; item 010 asserts no TS-baseline parity).

---

## Decisions & Trade-offs

To be updated during implementation.

Key up-front design decisions recorded for this item:

**(a) Two-op compile/validate split vs TS's fused single-method `getValidator`.** TS `validators/types.ts` defines ONE method, `getValidator<T>(schema) → (input) => result`, fusing compile and validate. The Racket port **deliberately splits** this into `provider-compile` (provider + schema → handle) and `validate` (handle + value → result). Rationale: (i) the TS docstring itself states the validator function is *"called multiple times"* and the provider *"handles schema compilation/caching internally"* (`types.ts:33–36`) — the compile-once/validate-many separation is already the intent, just folded behind a closure; making it two explicit operations exposes the compiled handle as a first-class, reusable value, which is more idiomatic in Racket and lets item 012 hold a handle in its normalized result. (ii) `compile` is naturally the provider's polymorphic responsibility (a `racket/generic` method); `validate` operates on the produced handle and need not re-dispatch on the provider. This is an intentional, more-idiomatic factoring — **not** a 1:1 mirror of the fused TS method (queue-002 item 010 header note explicitly sanctions this split).

**(b) Structured error shape `(validation-error path message)` vs TS single `errorMessage` string.** TS returns `{valid:false, errorMessage:string}` — one flat string, no location. The Racket result carries a **list** of `validation-error`, each with a structured `path` (a list of JSON-Pointer-ish segments; `'()` = root) **plus** a `message`. This is a deliberate **Racket enhancement**, not present in TS: item 011's provider will populate per-keyword failures with their location (e.g. `("properties" "name")`), and item 012 / S6b can surface precise errors to callers. The shape degrades gracefully — a provider with only a flat message emits one root-path error `(validation-error '() msg)`, recovering the TS single-string case. `validation-ok` carries the validated value (↔ TS `data`).

**(c) `racket/generic` `gen:` interface vs alternatives.** The port uses `racket/generic` (`define-generics json-schema-validator-provider`) per architecture §4.1 ("Ports via `racket/generic` … enabling dependency inversion + test doubles") — the same mechanism chosen for `gen:transport` (M6) and the server token-verifier (M14). Alternatives considered and rejected: a bare struct-of-closures (a `(provider compile-proc)` record) — works but is non-idiomatic and loses the `provider?` predicate + dispatch story the rest of the SDK uses; a parameter/dynamic-binding default — hides the seam and breaks the explicit-injection model. `racket/generic` gives a stable predicate (`json-schema-validator-provider?`), method dispatch, and trivial test doubles (the stub provider), matching the project's port convention exactly.

**(d) This item ships PORT + test stub only.** No JSON-Schema keyword logic (item 011), no schema normalization (item 012), no TS Ajv-baseline parity (item 011). The only concrete validator delivered is a trivial stub inside the test file. This keeps the seam reviewable in isolation and gives item 011 a known-good, portability-clean base to implement against.

---

## Project-Specific Adaptations (Racket / raco / rackunit)

This is a **Racket library, not a service**. The generic "Testing Prerequisites" template (Required Services / database / API endpoint / ports / health checks) does **not** apply and is adapted as follows — these template changes are documented explicitly per the create-item skill:

- **Required Services → None.** Pure Racket library; no external services, databases, message queues, HTTP servers, sockets, subprocesses, or network. The module is L0 and load-portable by construction (and proven so by the restricted-load test).
- **Database / API endpoint / ports sections → N/A.** Removed; replaced by the Racket toolchain row below.
- **Required toolchain:** Racket ≥ 8.x (`raco test`, `rackunit`). Verified present in this environment: **Racket v8.18 [cs]**.
- **TS checkout role:** present at `typescript-sdk/`, but **only needed for parity-claim items**. **Item 010 itself asserts NO TS-baseline parity** — the TS files are read once for interface *shape*, not by any test. (Parity against a TS Ajv baseline is item 011.) So a missing TS checkout would NOT fail this item's tests (contrast item 001, whose test reads the TS source live).
- **Manual Validation Checklist → specialized** to `raco make` / `raco test` + a REPL / stub-provider smoke check (below). No "service started" / "health check" / "screenshots" rows — replaced with N/A or removed.
- **Language/naming:** `#lang racket/base`; kebab-case bindings; explicit `(provide …)` never `all-defined-out` (architecture §1.3); `racket/generic` for the port (architecture §4.1).

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None (pure Racket library; no external services).** No databases, message queues, HTTP servers, sockets, subprocesses, or network dependencies.

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime | compile + run module and tests (`raco`, `rackunit`) | system install (`racket --version` ≥ 8.0; this env: v8.18) | n/a |
| S1 barrel (`mcp/core/main.rkt`) | the module requires the S1 public surface (types + errors) | already present (items 001–008, ✅) | n/a |
| `typescript-sdk/` checkout | read ONCE for interface shape; **NOT** read by any test (item 010 asserts no TS-baseline parity) | already present at repo root | n/a |

### Environment Configuration

- **Environment variables / secrets / config files / free ports:** none required.
- **Racket version:** ≥ 8.x (verified: v8.18 [cs]).
- **Working directory:** run `raco test` from the **repo root** so the `mcp/...` collection path resolves.
- **How to run the tests:**
  - `raco make mcp/core/validators/provider.rkt` — compile the port clean.
  - `raco test mcp/core/validators/` — run all validator-collection tests (picks up `test/provider-test.rkt` recursively), exit 0.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0.
  - `raco make mcp/core/main.rkt` → exit 0 (the S1 barrel this item requires loads clean).

### Manual Validation Checklist

- [ ] **Build/compile succeeds:** `raco make mcp/core/validators/provider.rkt` compiles with no errors/warnings.
- [ ] **Module loads in isolation:** `racket -e '(require (file "mcp/core/validators/provider.rkt"))'` from repo root succeeds.
- [ ] **Tests pass:** `raco test mcp/core/validators/test/provider-test.rkt` → all checks pass, exit 0.
- [ ] **Collection tests pass:** `raco test mcp/core/validators/` → exit 0.
- [ ] **Services started:** N/A (no services — pure library).
- [ ] **Application runs:** N/A (library; "running" = the require + REPL/stub smoke check below).
- [ ] **Feature verified (REPL / stub-provider smoke check):** from repo root, define a one-line stub provider, compile a schema, and validate a good + bad value — e.g.
      `racket -e '(require (file "mcp/core/validators/provider.rkt")) (struct stub () #:methods gen:json-schema-validator-provider [(define (provider-compile p s) (compiled-validator (lambda (v) (if (string? v) (validation-ok v) (validation-errors (list (validation-error (quote ()) "not a string")))))))]) (define h (provider-compile (stub) (hasheq))) (list (validation-ok? (validate h "hi")) (validation-errors? (validate h 5)))'`
      prints `(#t #t)` (ok for a string, errors for a non-string). (Adjust to the chosen encoding if `validate`/`compiled-validator` names differ; record exact transcript in Validation Results.)
- [ ] **Result shape verified:** the bad-value result's `validation-errors-errors` is a non-empty list of `validation-error?` each with a string `message` and list `path`.
- [ ] **Opacity verified:** `(dynamic-require '(file ".../provider.rkt") 'compiled-validator-validate-proc (lambda () 'not-found))` → `'not-found` (the validate closure accessor is NOT provided).
- [ ] **Portability verified:** the restricted-load test passes (no subprocess/socket module in the transitive import closure of `provider.rkt`).
- [ ] **Drift / non-vacuity check (portability):** temporarily add `(require racket/tcp)` to a scratch copy of `provider.rkt`, confirm the restricted-load test FAILS naming `racket/tcp`, then revert — proving the load test is live, not vacuous.
- [ ] **Health checks pass:** N/A (no running service).

### Expected Outcomes

Concrete, verifiable:

- The module **exports exactly** the documented port + result surface: `gen:json-schema-validator-provider` / `json-schema-validator-provider?` / `provider-compile`; `validate` (or `compiled-validate`); `compiled-validator?`; `validation-result?`; `validation-ok` / `validation-ok?` / `validation-ok-value`; `validation-errors` / `validation-errors?` / `validation-errors-errors`; `validation-error` / `validation-error?` / `validation-error-path` / `validation-error-message`. **No internal binding leaks** (the validate-closure field accessor is not provided — verified by a `dynamic-require` → `'not-found` check).
- A **stub provider** (defined in the test) compiles a schema and returns a `validation-ok` (with the recovered value) for a valid value and a `validation-errors` (a non-empty list of `validation-error`, each path+message) for an invalid value; `validation-ok?`/`validation-errors?` are mutually exclusive.
- The module **requires only S1** — a restricted-namespace load test confirms NO subprocess/socket module (`racket/system`, `racket/tcp`, `racket/udp`, `net/*`, `racket/sandbox`) is pulled into the transitive import closure (Portability NFR).
- `raco test mcp/core/validators/` reports all checks passing, 0 failures, 0 errors.

### Validation Results

```markdown
## Validation Results
- [ ] Service started: N/A (pure Racket library, no services)
- [ ] Application started successfully: N/A (library; `require` + REPL/stub smoke check succeeded)
- [ ] Build verified: `raco make mcp/core/validators/provider.rkt` clean (exit 0)
- [ ] Module load verified: `(require (file ".../provider.rkt"))` succeeds
- [ ] Tests verified: `raco test mcp/core/validators/` → 0 failures, 0 errors
- [ ] Stub-provider shape verified: ok value → validation-ok (value recovered); bad value → validation-errors (non-empty path+message list)
- [ ] Opacity verified: validate-closure accessor NOT provided (`dynamic-require` → 'not-found)
- [ ] Portability verified: restricted-load test passes (no subprocess/socket in transitive closure)
- [ ] Portability drift check: injected `(require racket/tcp)` → test FAILED naming racket/tcp, then reverted
- [ ] S1-only imports confirmed: require list is `mcp/core/main.rkt` (or `mcp/core/types`) + racket/generic [+ racket/contract]
- [ ] Database tables verified: N/A
- [ ] Seed data verified: N/A
- [ ] API endpoints verified: N/A
- [ ] Screenshots captured: N/A (no UI)
```

---

## Completion Reminder

On completion, the implementer MUST update **`docs/aide/progress.md`** (Stage S2 section), advancing the icon **📋 → 🚧 → ✅**:

1. Flip the deliverable line **`📋 mcp/core/validators/provider.rkt — gen:-style validator-provider port`** (progress.md line ~71) from 📋 → 🚧 (on start) → ✅ (on delivery + all acceptance criteria pass). Never revert an icon backward.
2. Do **not** check the broad Stage-S2 acceptance boxes that depend on sibling items (the `raco test over all S2 modules`, URI-template, tool-name, schema-normalization, validator **keyword-coverage**, and stdio-framing boxes all belong to items 011–017). The validator-**keyword** acceptance box is item 011's, NOT this item's — this item delivers only the port + result types + stub test.
3. **Parity matrix:** per Stage S2 discipline, advance the `validators/*` row toward `partial` (the port + result types exist; full keyword/conformance exercise lands with items 011/017/018 and S9). Per the project's "each stage flips rows as it fully exercises them" rule, record that the **port** sub-row is satisfied without prematurely marking the default-provider/keyword sub-rows.
4. Leave all other S2 deliverable lines (`from-json-schema.rkt`, `util/schema.rkt`, the `shared/*` utils, tests-under-other-dirs) at their current status — this item delivers only `validators/provider.rkt` + its test.
