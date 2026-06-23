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
;; one structured error — path + message (the deliberate Racket enrichment).
;; DEFINE THIS BEFORE validation-errors, since validation-errors' guard references it.
(struct validation-error (path message) #:transparent)
;;   path    : (listof (or/c string? exact-nonnegative-integer?))  ; JSON Pointer-ish segments; '() = root
;;   message : string?
;; error variant — carries a NON-EMPTY list of structured errors.
;; A #:guard ENFORCES non-emptiness (and element type) so (validation-errors '()) RAISES —
;; see Decisions (b) + Acceptance Criteria; this makes the "non-empty" claim falsifiable, not advisory.
(struct validation-errors (errors)
  #:transparent
  #:guard (lambda (errors _type-name)
            (unless (and (pair? errors) (andmap validation-error? errors))
              (error 'validation-errors
                     "errors must be a non-empty list of validation-error; got: ~e" errors))
            errors))
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
- [ ] The **structured error** shape is `(validation-error path message)` with `path` a list of string/integer segments (`'()` = root) and `message` a string; predicates + accessors are provided. The path contract admits BOTH string keys and integer array indices — a `'("items" 0 "name")`-style mixed path is valid (tested).
- [ ] **`validation-errors` non-emptiness is ENFORCED, not advisory** (Decisions (b)): the struct carries a `#:guard` that rejects an empty (or non-`validation-error`) list, so `(validation-errors '())` **raises**. This is asserted falsifiably by a `check-exn` test — NOT merely "the stub happens to emit ≥1".
- [ ] The result type is a **closed** two-variant set under a `validation-result?` umbrella predicate; `validation-ok?` and `validation-errors?` are mutually exclusive and exhaustive. Tested with closed-set **negatives**: `(validation-result? 42)` → `#f`, and a bare `(validation-error '() "x")` element is NOT itself a `validation-result?` (an error *element* is not a *result*).
- [ ] The compiled handle is **opaque**: `compiled-validator?` is provided, but the struct's internal closure/field is NOT exposed via a provided accessor.
- [ ] **Accessor mis-dispatch raises:** `validation-ok-value` applied to a `validation-errors` (and `validation-errors-errors` applied to a `validation-ok`) **raises** — consumers MUST predicate-dispatch first (tested via `check-exn`). (This is automatic for distinct `#:transparent` structs; the test pins it so a future refactor to a single struct can't silently change it.)
- [ ] The module imports **only S1** (`mcp/core/main.rkt` or `mcp/core/types`, + `racket/generic`/`racket/contract`). It requires NO transport/engine/role/subprocess/socket module. **Verified by a restricted-namespace load test** (mirrors item 008 Part C) whose entry point is **`provider.rkt` itself** (there is no `validators/main.rkt` barrel at this stage — do NOT change the entry point to a barrel): a fresh `(make-base-namespace)` requiring `provider.rkt` and walking `module->imports` transitively shows EMPTY intersection with the banned set `racket/system, racket/tcp, racket/udp, net/url, net/http-client, net/sendurl, racket/sandbox, racket/port` (the full set the item-008 helper bans — note `racket/port` IS included, matching the shipped helper).
- [ ] **Provider-swap seam proven (the port's whole point):** the test defines **TWO independently-built stub providers** (e.g. a `const`-equality stub and a `type`-style `string?` stub), compiles a handle from EACH, and asserts both flow through the IDENTICAL `validate` / `validation-result?` / `validation-ok?` / `validation-errors?` surface with correct per-provider outcomes. A value ok for one provider is an error for the other.
- [ ] **Value matrix round-trips** through `validation-ok-value`: ok-validations on `(json-null)`, a `(hasheq 'a 1)`, a `'(1 2 3)`, a string, AND a number each recover the SAME value `equal?` (catches a provider that coerces or drops non-numeric jsexprs).
- [ ] **Handle reuse ("called multiple times"):** ONE compiled handle, `validate`d over several ok values and several error values in sequence, each asserted independently — proving the handle carries no per-call mutable state.
- [ ] **Two independent handles, same provider:** `h1`/`h2` compiled from the same provider with DIFFERENT expected schemas; a value ok for `h1` is an error for `h2` (catches global / last-schema closure-memoization bugs).
- [ ] A unit test at `mcp/core/validators/test/provider-test.rkt` defines the stub provider(s), `provider-compile`s schemas, and `validate`s ok + error values, asserting result shape (`validation-ok?` + recovered value for good; `validation-errors?` + a `validation-error` with expected `path`/`message` for bad).
- [ ] The stub-provider test also asserts the **shape contract**: a `validation-ok` round-trips its value via `validation-ok-value`; a `validation-errors` exposes `validation-errors-errors` as a non-empty list whose elements are `validation-error?` with string `message` and list `path`; a **≥2-error** case preserves element order and all are `validation-error?`.
- [ ] `raco test mcp/core/validators/` passes (exit 0) — module + test compile and run cleanly within the collection.
- [ ] `raco make mcp/core/validators/provider.rkt` exits 0 (compiles clean, no warnings about missing/non-portable modules).
- [ ] Parity-matrix discipline: per Stage S2 the `validators/*` row is advanced toward `partial` (the port + result types exist; full conformance + the default-provider keyword exercise land with items 011/017/018 and S9). Update `docs/aide/progress.md` per the Completion Reminder.

---

## Implementation Steps

1. **Create the collection directories** if absent: `mcp/core/validators/` and `mcp/core/validators/test/`.
2. **Read the TS interface** (`typescript-sdk/packages/core/src/validators/types.ts` + `types.examples.ts`) once more for the **shape** (single fused `getValidator`; the `{valid,data,errorMessage}` result). Confirm you are porting the *shape*, then deliberately split it per Decisions (a).
3. **Write `mcp/core/validators/provider.rkt`.** Use `#lang racket/base`. In order:
   - `(require racket/generic (only-in "../main.rkt" …))` (require the S1 barrel; pull only the error constructors / jsexpr predicate you actually use — record the final list in Decisions). Add `racket/contract` only if you attach `contract-out`.
   - Define the result structs **in this order**: `validation-ok` (`#:transparent`); `validation-error` (`#:transparent`) — **before** `validation-errors`; then `validation-errors` with the `#:guard` that rejects an empty / non-`validation-error` list (Decisions (b)). Define `validation-result?` as `(or/c validation-ok? validation-errors?)`.
   - Define the generic `(define-generics json-schema-validator-provider (provider-compile json-schema-validator-provider schema))`.
   - Define the compiled handle + `validate` per the chosen encoding (recommended: `(struct compiled-validator (validate-proc) #:transparent)` kept opaque in `provide`, plus `(define (validate handle value) ((compiled-validator-validate-proc handle) value))`).
   - Add the explicit `(provide …)` block enumerating exactly the surface in Description §3.
4. **Write the test** `mcp/core/validators/test/provider-test.rkt` (see Testing Strategy — six parts). Define **TWO** stub structs implementing `gen:json-schema-validator-provider` (a `const`-style and a `type`-style), prove the swap seam, exercise handle reuse + independent handles, the value matrix, the struct-contract checks (zero-error guard, closed-set negatives, accessor mis-dispatch, ≥2-error order, mixed path), the compile-on-garbage policy, and the restricted-load portability sub-test (reuse the item-008 walk helper — copy or factor it; entry point is `provider.rkt` itself).
5. **Run** `raco make mcp/core/validators/provider.rkt` then `raco test mcp/core/validators/`. Fix any failure.
6. **Update progress + parity matrix** (see Completion Reminder).

---

## Testing Strategy

The test is a **shape/contract test through stub providers** — explicitly NOT a TS-baseline parity test (that is item 011). Concerns: (1) ok/error result shapes round-trip; (2) the `gen:` provider-swap SEAM works (≥2 independent providers); (3) the compiled handle behaves like a reusable validator function; (4) the result/error structs enforce their contract; (5) the module is portable (S1-only).

**Test file:** `mcp/core/validators/test/provider-test.rkt` (`#lang racket/base`; `(require rackunit racket/generic json (file "../provider.rkt"))` plus `racket/set`/`racket/path` for the portability walk). `json` is needed for `(json-null)`.

### Part 1 — TWO stub providers (the swap seam — most important test)

The port's whole purpose is provider interchangeability, so the test MUST exercise **two differently-built stubs**, not one:

1. **Stub A — `const`-equality.** `provider-compile` reads `(hash-ref schema 'const)` → `expected`; the handle's validate-proc returns `(validation-ok v)` when `(equal? v expected)`, else `(validation-errors (list (validation-error '() (format "expected ~e, got ~e" expected v))))`.
2. **Stub B — `type`-style.** `provider-compile` reads `(hash-ref schema 'type)` (e.g. `"string"`) → a predicate; the handle returns `(validation-ok v)` when the predicate holds, else `(validation-errors (list (validation-error '() (format "not a ~a" t))))`. Keep both trivial — NO real keyword logic.
3. **Both flow through the IDENTICAL surface.** Compile `hA` from Stub A `(hasheq 'const 42)` and `hB` from Stub B `(hasheq 'type "string")`. Assert `(compiled-validator? hA)` and `(compiled-validator? hB)`. Then run BOTH through the same assertions: `(validation-ok? (validate hA 42))`, `(validation-ok? (validate hB "hi"))`; `(validation-errors? (validate hA 7))`, `(validation-errors? (validate hB 5))`. Cross-check: a value ok for one is an error for the other — `"hi"` is `validation-errors?` for `hA` (≠ 42) but `validation-ok?` for `hB`. This proves the seam, and would catch a `validate` that secretly hard-codes one provider's logic.
4. **Interface conformance.** `(check-true (json-schema-validator-provider? stub-a))`, `(check-true (json-schema-validator-provider? stub-b))`, `(check-false (json-schema-validator-provider? 42))` — confirms the stubs really implement `gen:`, not that the test called a bare procedure.

### Part 2 — handle reuse + independence (the "called multiple times" TS contract)

5. **One handle, many calls, no mutable state.** Take `hA`; in sequence `(validate hA 42)` (ok), `(validate hA 1)` (err), `(validate hA 42)` (ok again), `(validate hA 2)` (err) — assert each result independently. The second ok MUST still recover `42`; proves the handle holds no per-call state.
6. **Two independent handles from the SAME provider.** `(define h1 (provider-compile stub-a (hasheq 'const 1)))` / `(define h2 (provider-compile stub-a (hasheq 'const 2)))`. Assert `(validation-ok? (validate h1 1))`, `(validation-errors? (validate h2 1))`, `(validation-ok? (validate h2 2))`, `(validation-errors? (validate h1 2))` — a value ok for `h1` is an error for `h2`. Catches global/last-schema memoization in the closure.

### Part 3 — value matrix (the result carries the validated value)

7. **Round-trip every jsexpr kind** through `validation-ok-value`. Use an "accept-anything" stub (a third trivial stub, or Stub B with a predicate that always holds) and validate each of: `(json-null)`, `(hasheq 'a 1)`, `'(1 2 3)`, `"str"`, `42`, `#t`. For each, assert `(validation-ok? r)` and `(check-equal? (validation-ok-value r) <input>)` — the SAME value `equal?`. Catches a provider/validate path that coerces, JSON-reserializes, or drops a non-numeric jsexpr.

### Part 4 — result/error struct contract (falsifiable)

8. **Zero-error result RAISES** (the `#:guard`, Decisions (b)): `(check-exn exn:fail? (lambda () (validation-errors '())))` — proves non-emptiness is enforced, not merely "the stub happened to emit ≥1". Also `(check-exn exn:fail? (lambda () (validation-errors (list "not-a-validation-error"))))` — element-type enforced.
9. **Closed-set negatives.** `(check-false (validation-result? 42))`; `(check-false (validation-result? (validation-error '() "x")))` — an error *element* is not a *result*. Pins the variant set as exactly `ok | errors`.
10. **Mutual exclusivity.** For any built result, `validation-ok?` and `validation-errors?` are never both true.
11. **Accessor mis-dispatch RAISES.** `(check-exn exn:fail? (lambda () (validation-ok-value (validation-errors (list (validation-error '() "x"))))))` and `(check-exn exn:fail? (lambda () (validation-errors-errors (validation-ok 1))))` — consumers MUST predicate-dispatch first.
12. **Many-errors result (≥2), order preserved.** Build `(validation-errors (list (validation-error '("a") "e1") (validation-error '("b") "e2")))`; assert `(length (validation-errors-errors r))` = 2, all elements `validation-error?`, and the messages come back in order `'("e1" "e2")` — catches a `validate` that keeps only the first error.
13. **Path contract — root, all-string, mixed string/integer.** Assert a root error's path is `'()` (not `#f`/`""`). Assert an all-string path `'("a" "b")` round-trips. Assert a **mixed** path `'("items" 0 "name")` (integer array-index segment) round-trips via `validation-error-path` — pins the integer-segment branch item 011 will emit.

### Part 5 — restricted-namespace portability (S1-only)

14. Reuse the transitive `module->imports` walk from item 008 (Part C) — a fresh `(make-base-namespace)`, `namespace-require` the provider, walk imports with `current-load-relative-directory` threaded per module dir, assert the FULL banned set (`racket/system racket/tcp racket/udp net/url net/http-client net/sendurl racket/sandbox racket/port`) has empty intersection with the visited set. **Entry point is `provider.rkt` ITSELF** — there is no `validators/main.rkt` barrel at this stage; do NOT "fix" the walk to start from a barrel. **Scope limit (inherited from item 008):** `module->imports` does NOT see into `(module+ test …)` submodules, so this proves the *module's own* phase-0/1 import graph is clean, NOT that a test submodule avoids banned modules — do not overread the portability claim. Factor the walk into a shared helper or copy inline; record the choice in Decisions. (Item 017 adds the collection-wide S2 sweep; this proves `provider.rkt` itself is clean so item 011 inherits a known-good base.)
15. **Non-vacuity (drift):** temporarily inject `(require racket/tcp)` into a scratch copy of `provider.rkt`, confirm the walk FAILS naming `racket/tcp`, revert. (1-hop is sufficient here since `provider.rkt` is the walk's own entry point — but keep the item-008 fix in the helper so it stays correct if the require graph deepens.)

### Part 6 — compile-on-garbage + cross-provider handle (precedent for item 011)

16. **Compile on a non-conforming schema.** Pin the stub's behavior when `provider-compile` gets garbage (`42`, `'()`, or a `hasheq` missing the key it reads). **Decision to make + document:** raise immediately via an S1 error constructor (`make-mcp-error` / `make-protocol-error`) vs defer the failure to `validate` time. **Recommended:** the `const`/`type` stubs RAISE at compile on a missing key (fail-fast), asserted with `check-exn` — set the fail-fast precedent item 011 inherits. (If a stub instead defers, document that and assert the deferred behavior; either is acceptable IF tested + documented.)
17. **Cross-provider handle totality.** Under the recommended **closure-in-handle** encoding, `validate` is total over ANY `compiled-validator?` regardless of which provider built it (it just applies the carried closure) — assert a handle from Stub A and a handle from Stub B both `validate` without error through the SAME `validate` entry point. (State explicitly: this is vacuous-by-construction under closure-in-handle; under the alternative `gen:compiled-validate` encoding it would instead test cross-provider dispatch. Document which applies.)
18. **Non-jsexpr input to `validate`.** Pin behavior when a non-jsexpr value (a `symbol`, `(void)`) reaches `validate`: returns a result vs raises. **Decision:** `validate` assumes a jsexpr input (the port does not police input type — that is the provider's concern); document this, and assert the stub's actual behavior on a `(void)` input so the contract is pinned rather than incidental.

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

**(b) Structured error shape `(validation-error path message)` vs TS single `errorMessage` string.** TS returns `{valid:false, errorMessage:string}` — one flat string, no location. The Racket result carries a **list** of `validation-error`, each with a structured `path` (a list of JSON-Pointer-ish segments — string keys AND integer array indices, e.g. `("items" 0 "name")`; `'()` = root) **plus** a `message`. This is a deliberate **Racket enhancement**, not present in TS: item 011's provider will populate per-keyword failures with their location, and item 012 / S6b can surface precise errors to callers. The shape degrades gracefully — a provider with only a flat message emits one root-path error `(validation-error '() msg)`, recovering the TS single-string case. `validation-ok` carries the validated value (↔ TS `data`).

> **Non-emptiness is ENFORCED, not advisory.** Because the structs are plain `#:transparent`, `(validation-errors '())` would be silently constructible and would defeat the "non-empty errors" acceptance criterion (the AC could pass merely because a stub happens to emit ≥1). So `validation-errors` carries a `#:guard` that raises on an empty list or a non-`validation-error` element. This makes the AC **falsifiable** — a `check-exn` test asserts `(validation-errors '())` raises. (Alternative considered: leave it a documented-but-unenforced provider contract — rejected per the reviewer's preference (a) because an unfalsifiable AC lets the malformed-result bug through.) Consequence: `validation-error` MUST be defined **before** `validation-errors` in the module (the guard references `validation-error?`).

**(c) `racket/generic` `gen:` interface vs alternatives.** The port uses `racket/generic` (`define-generics json-schema-validator-provider`) per architecture §4.1 ("Ports via `racket/generic` … enabling dependency inversion + test doubles") — the same mechanism chosen for `gen:transport` (M6) and the server token-verifier (M14). Alternatives considered and rejected: a bare struct-of-closures (a `(provider compile-proc)` record) — works but is non-idiomatic and loses the `provider?` predicate + dispatch story the rest of the SDK uses; a parameter/dynamic-binding default — hides the seam and breaks the explicit-injection model. `racket/generic` gives a stable predicate (`json-schema-validator-provider?`), method dispatch, and trivial test doubles (the stub provider), matching the project's port convention exactly.

**(d) This item ships PORT + test stub only.** No JSON-Schema keyword logic (item 011), no schema normalization (item 012), no TS Ajv-baseline parity (item 011). The only concrete validator delivered is a trivial stub inside the test file. This keeps the seam reviewable in isolation and gives item 011 a known-good, portability-clean base to implement against.

**(e) Failure-timing + input-policing precedents (set here so item 011 inherits them).**
- **compile-on-garbage:** a provider's `provider-compile` SHOULD **fail-fast** — raise (via an S1 error constructor `make-mcp-error`/`make-protocol-error`) on a non-conforming schema (missing required key, non-object) rather than defer to validate time. The stubs in the test follow this so item 011's real provider has a documented precedent. (Deferring to validate is acceptable only if explicitly documented + tested; the recommended default is fail-fast.)
- **`validate` does NOT police input type:** the port treats the value as opaque and applies the provider's logic; it ASSUMES a jsexpr input and does not raise on a non-jsexpr (`symbol`, `(void)`) by itself — input-type policing is the provider's concern (and, upstream, the contract layer's). The test pins the stub's actual behavior on a `(void)` input so this is contractual, not incidental.
- **Cross-provider handle totality:** under the recommended **closure-in-handle** encoding, the single `validate` entry point is total over any `compiled-validator?` regardless of originating provider (it applies the carried closure) — this is vacuous-by-construction and stated so a reader doesn't add spurious dispatch. Under the alternative `gen:compiled-validate` encoding, `validate` instead dispatches per-handle; whichever encoding is chosen, document it and assert handles from BOTH stubs flow through the same entry point.

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
- [ ] **Swap seam verified:** two differently-built stubs (`const`-style + `type`-style) both flow through the same `validate`/`validation-result?` surface; a value ok for one is an error for the other.
- [ ] **Handle reuse verified:** one handle validated over several ok + error values in sequence; each independently correct (no per-call state).
- [ ] **Independent handles verified:** two handles from the same provider with different schemas disagree on the same value.
- [ ] **Value matrix verified:** `(json-null)`, `(hasheq 'a 1)`, `'(1 2 3)`, a string, a number each round-trip `equal?` through `validation-ok-value`.
- [ ] **Zero-error guard verified:** `(validation-errors '())` RAISES (check-exn); element-type guard also raises on a non-`validation-error` element.
- [ ] **Closed-set verified:** `(validation-result? 42)` → `#f`; a bare `validation-error` is NOT a `validation-result?`.
- [ ] **Accessor mis-dispatch verified:** `validation-ok-value` on a `validation-errors` (and vice versa) RAISES.
- [ ] **Mixed path verified:** `'("items" 0 "name")` round-trips via `validation-error-path` (integer-index segment).
- [ ] **compile-on-garbage verified:** `provider-compile` on a missing-key/non-object schema behaves per the documented policy (recommended: raises via S1 error ctor).
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
- [ ] Swap seam verified: two stubs through identical surface; ok-for-one is error-for-other
- [ ] Handle reuse + independent handles verified (no per-call/global state)
- [ ] Value matrix verified: json-null / hasheq / list / string / number round-trip equal?
- [ ] Struct contract verified: (validation-errors '()) raises; closed-set negatives; accessor mis-dispatch raises; ≥2-error order; mixed string/int path
- [ ] compile-on-garbage policy verified (recommended: raises via S1 error ctor)
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
