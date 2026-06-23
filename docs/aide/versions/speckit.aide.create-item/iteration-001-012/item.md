# Work Item 012: Schema-normalization util — contract-or-JSON-Schema (M4)

> **Queue:** `docs/aide/queue/queue-002.md` — Item 012
> **Stage:** S2 (Foundation: validators, schema, shared utilities — L0 part 2)
> **Module:** M4 (Schema util) — `mcp/core/util/schema.rkt`. The Standard-Schema analogue. It bridges a `racket/contract` flat contract **or** a JSON Schema into (a) a **wire JSON Schema** for advertisement and (b) a **validation handle** delegating to the M3 provider (items 010/011). It is consumed by the high-level server (S6b) for tool I/O.
> **Source vision:** `docs/aide/vision.md` §4.5 (pluggable JSON-Schema validator; the schema util sits ABOVE the M3 provider and delegates to it), §6 (Portability NFR — core loads without subprocess/socket; Minimal-deps NFR — no external schema library), §8 (Zod / external Standard-Schema-library compat **excluded** — this module is the Racket-native analogue, not a Standard-Schema vendoring).
> **Source roadmap:** `docs/aide/roadmap.md` Stage S2 → Deliverables line (`mcp/core/util/schema.rkt` — contract-or-JSON-Schema normalization, Standard-Schema analogue) + Testing/validation criteria (contract input and equivalent JSON-Schema input accept/reject same values; wire schema matches).
> **Source architecture:** `docs/aide/architecture.md` M4 (schema util consumes the M3 port; depends on S1 + M3 only), §1.3 (public/internal boundary, curated `main.rkt`, explicit `provide`), §4.1 (Runtime-neutral core L0–L2 import no subprocess/socket).
> **Reference impl (authoritative):** MCP TypeScript SDK v2 at `typescript-sdk/` — `packages/core/src/util/schema.ts` (the Zod-internal `AnySchema`/`parseSchema` helper — mirror only the **role**: a thin schema→validate-result helper) and `packages/core/src/util/standardSchema.ts` (the Standard-Schema bridge: `standardSchemaToJsonSchema` produces a wire JSON Schema for advertisement; `validateStandardSchema` produces a validate result; `promptArgumentsFromStandardSchema` extracts arg shape). **Framing:** the TS module bridges *Standard-Schema library objects* (Zod/Valibot/ArkType) to (wire JSON Schema + validate-fn). Vision §8 EXCLUDES that library ecosystem; the Racket analogue bridges the two NATIVE schema forms a Racket caller already has — a `racket/contract` flat contract OR a parsed JSON Schema (jsexpr) — to the same pair (wire JSON Schema + validation handle). So the **shape/role is ported; the input forms are net-new Racket-native**.
> **Status:** 📋 Planned — not started.

---

## Description

Implement `mcp/core/util/schema.rkt`, the **schema-normalization util** for `racket-mcp`. Given a tool's argument schema in EITHER of two native Racket forms — a **`racket/contract` flat contract** OR a **JSON Schema** (a parsed jsexpr `hasheq`) — it produces a single uniform **normalized schema** value carrying:

1. a **wire JSON Schema** (a jsexpr `hasheq` with `type:"object"` at the root) suitable for advertisement in `tools/list` / prompt-argument lists; and
2. a **validation handle** — an item-010 `compiled-validator?` produced by compiling the wire JSON Schema through the **M3 provider** (default: item 011's `make-racket-native-provider`) — that `validate`s incoming tool arguments.

This is the Racket-native **Standard-Schema analogue**: TS `util/standardSchema.ts` bridges Standard-Schema library objects (Zod/Valibot/ArkType) to `(jsonSchema, validate-fn)`; this module bridges the two native Racket schema forms to `(wire-json-schema, validation-handle)`. The high-level server (S6b) consumes the normalized result for tool/prompt I/O: it advertises the wire schema and validates arguments through the handle.

### Framing — what is ported vs net-new (read carefully)

The TS source has two relevant pieces, and this item relates to them by **role**, not transliteration:

1. **`util/schema.ts`** is a ~33-line Zod-internal helper: `AnySchema`/`AnyObjectSchema` aliases + `parseSchema(schema, data) → {success, data}|{success, error}`. We mirror only its **role** — a thin "schema in, validate-result out" helper — and we realize "validate-result out" via the item-010 result API (`validation-ok`/`validation-errors`) rather than a Zod `safeParse` shape.
2. **`util/standardSchema.ts`** is the substantive analogue. Its three load-bearing functions map directly:
   - `standardSchemaToJsonSchema(schema, io) → Record<string,unknown>` — **convert a schema to a wire JSON Schema** for advertisement; **forces `type:"object"` at the root** (MCP requires object-typed tool/prompt schemas; it throws on an explicit non-object root `type`). → our `normalized-schema-wire` (a jsexpr `hasheq` with root `type:"object"`).
   - `validateStandardSchema(schema, data) → {success,data}|{success,error}` — **validate a value**. → our validation handle delegating to the M3 provider.
   - `promptArgumentsFromStandardSchema(schema)` — extract `{name, description?, required}` per top-level property. → an **optional** helper `normalized-schema-prompt-arguments` (mirrors the role; see Scope guard for whether it ships here).

Vision §8 EXCLUDES the Zod/Valibot/ArkType Standard-Schema ecosystem `standardSchema.ts` bridges, so the **input forms** here are net-new: a `racket/contract` flat contract or a parsed JSON Schema. The **output pair** and the **`type:"object"`-at-root invariant** are ported faithfully.

### The two input forms (the build contract)

**Form A — JSON Schema (a parsed jsexpr `hasheq`).** The caller already has a JSON Schema (e.g. lifted from a spec, or hand-written). Normalization here is near-identity:
- the wire JSON Schema is the input schema with `type:"object"` ensured at the root (per the TS `{ type: 'object', ...result }` rule — if the root already has `type:"object"`, unchanged; if the root has NO `type`, `type:"object"` is added; if the root has an explicit **non-object** `type`, **reject** — mirrors TS `standardSchemaToJsonSchema`'s throw);
- the validation handle is `(provider-compile provider wire-schema)` through the M3 provider.

**Form B — a `racket/contract` flat contract.** The caller has a Racket contract describing a single argument value or (in the common tool-argument case) an object of named arguments. Normalization maps the contract to an equivalent wire JSON Schema, then compiles that schema through the M3 provider (so BOTH forms share the SAME validation path — the handle always delegates to the provider over a JSON Schema, never to an ad-hoc contract checker). The **contract→JSON-Schema mapping is a documented, deliberately-limited subset** (see below).

> **Single delegation path (committed design directive).** BOTH input forms produce a validation handle by compiling a **wire JSON Schema** through the M3 provider. Form B does NOT validate by applying the raw `racket/contract` at validate time. Rationale: (1) the dual-form acceptance criterion requires that a contract input and an equivalent JSON-Schema input accept/reject the **same** values — guaranteed-by-construction when both compile to a JSON Schema and validate through the same provider; (2) it keeps the validate path single, portable, and provider-swappable (the whole point of the M3 port); (3) it avoids a second, divergent validation semantics. The contract is used ONLY to *derive the wire schema* (a compile-time mapping), not as a runtime validator. (Document this explicitly; it is the linchpin of the dual-form guarantee.)

### Contract → JSON-Schema mapping (Form B) — the supported subset + its limits

The mapping accepts a curated set of **flat** contracts (single-level — NOT arbitrary higher-order/dependent contracts) and an **object descriptor** built from them. The supported mapping, keyed to the M3 provider's supported keyword subset (item 011: `type`/`properties`/`required`/`enum`/`items`/`format`), is:

| Racket contract form | Wire JSON-Schema fragment |
|---|---|
| `string?` | `{ "type": "string" }` |
| `exact-integer?` | `{ "type": "integer" }` |
| `real?` / `rational?` / `number?` | `{ "type": "number" }` |
| `boolean?` | `{ "type": "boolean" }` |
| `(listof <flat>)` | `{ "type": "array", "items": <map(flat)> }` |
| `(or/c "a" "b" …)` (string/number/bool/null literals) | `{ "enum": ["a","b", …] }` |
| `(or/c <flat> <flat>)` of TYPE predicates | **rejected** (no single-`type` JSON-Schema equivalent in the M3 subset — see edge cases) |
| an **object descriptor** (a structured field→`(flat-contract . required?)` declaration) | `{ "type":"object", "properties": {…}, "required": [required-field-names] }` |

The exact **surface for declaring an object descriptor** is an implementation choice (recommended: a small helper/struct, e.g. `(object-schema (field 'name string? #:required #t) (field 'age exact-integer?))` or an assoc-list convention `'((name string? #t) (age exact-integer? #f))`) — **pin the chosen surface in Decisions and document it**. Whatever the surface, the mapping MUST yield wire `properties` keyed by **symbol** field names and a wire `required` array of **string** field names (matching item 011's symbol/string boundary).

**Documented mapping limits (Form B):**
- **Flat only.** Higher-order contracts (`->`, `->*`, `case->`), dependent contracts (`->i`), struct/`struct/c`, parametric contracts, and arbitrary opaque predicates (e.g. `even?`, a custom `(flat-named-contract …)` over a lambda) have **no JSON-Schema equivalent in the M3 subset** → such a contract is **rejected at normalization** with a clear S1 error (NOT silently mapped to an empty/`{}` schema that would accept everything). This is the "contract with no JSON-Schema equivalent" edge case.
- **No constraint keywords.** A contract like `(and/c string? (string-len/c 10))` maps only its `type` part (`string`) — the length constraint has **no M3-supported keyword** (`minLength`/`maxLength` are item-011 *deferred* keywords). Policy: **map the type, drop the constraint, and record/document the dropped constraint** (do NOT reject outright, and do NOT silently pretend it is enforced) — mirroring item 011's ignore-with-warning stance for constraints the provider cannot enforce. Pin the chosen surfacing (recommended: a `normalized-schema-dropped` accessor or a one-line `eprintf` at normalize, consistent with item 011's `provider-warnings-for` channel). **Alternative permitted:** reject `and/c`-with-constraint outright; whichever is chosen is documented + tested.
- **Format contracts.** A contract carrying a recognized format (e.g. a documented `email-string?` / `uri-string?` / `date-time-string?` predicate the module itself exports, OR an explicit `(format/c "email")`-style annotation) maps to `{ "type":"string", "format":"email" }`. Bare opaque predicates are NOT inferred as formats (no heuristic guessing). Pin the chosen format-annotation surface in Decisions.

### The normalized result (the uniform output)

`normalize-schema` accepts `(input #:provider [provider (make-racket-native-provider)])` where `input` is EITHER a parsed JSON Schema (`hash?`) OR a contract/object-descriptor (the Form-B surface), and returns a **`normalized-schema`** value (a `struct`, opaque-ish — curated accessors only) carrying:
- `normalized-schema-wire` → the wire JSON Schema (jsexpr `hasheq`, root `type:"object"`);
- `normalized-schema-handle` → the item-010 `compiled-validator?` (compiled through the provider);
- (helper) `normalized-schema-validate` → `(normalized-schema-validate ns value)` = `(validate (normalized-schema-handle ns) value)` → a `validation-result?` (sugar so callers don't reach through to the handle);
- (optional) `normalized-schema-prompt-arguments` → arg entries derived from the wire `properties`/`required` (mirrors TS `promptArgumentsFromStandardSchema`) — ships here IFF the Scope guard keeps it.

> **Form detection.** Input that is a `hash?` is treated as Form A (a parsed JSON Schema). Input that is the Form-B surface (the object-descriptor struct/convention, or a bare flat contract) is treated as Form B. The detection rule MUST be unambiguous (a JSON Schema is always a `hash?`; the Form-B object descriptor is a distinct struct/representation — do NOT make a bare `hasheq` ambiguous between the two). Pin the detection rule in Decisions. A bare single flat-contract input (not wrapped in an object descriptor) is mapped, then handled per the root-`type:"object"` invariant below.

> **Root `type:"object"` invariant (ported from TS).** MCP tool/prompt schemas MUST be object-typed at the root. So `normalize-schema`:
> - Form A with root `type:"object"` (or no root `type`) → ensures/sets `type:"object"`;
> - Form A with an explicit non-object root `type` (e.g. `{type:"string"}`) → **rejected** (mirrors the TS throw) — a tool schema cannot be a bare string;
> - Form B object descriptor → already produces a root `type:"object"`;
> - Form B bare flat contract (e.g. just `string?`) → **rejected** for the same reason (a tool argument schema must be an object) UNLESS wrapped in an object descriptor. (Pin: recommended is REJECT a bare non-object Form-B input, matching TS; document the choice.)

### "Equivalent" — what the dual-form test asserts

Two inputs are **equivalent** when the contract Form-B input and the JSON-Schema Form-A input describe the SAME object shape — e.g. the object descriptor `{name: string? (required), age: exact-integer? (optional)}` and the JSON Schema `{type:"object", properties:{name:{type:"string"}, age:{type:"integer"}}, required:["name"]}`. The dual-form test compiles BOTH, then asserts:
- **same accepts:** a set of values that should pass (e.g. `{name:"a", age:5}`, `{name:"a"}`) are `validation-ok?` under BOTH handles;
- **same rejects:** a set of values that should fail (e.g. `{age:5}` missing name, `{name:5}` wrong type, `{name:"a", age:"x"}` wrong type) are `validation-errors?` under BOTH handles;
- **wire-schema match:** `(normalized-schema-wire ns-contract)` `equal?` `(normalized-schema-wire ns-jsonschema)` (after the root-`type:"object"` normalization) — the contract form emits the SAME wire JSON Schema the hand-written form does. (If exact `equal?` is too strict due to hash ordering, assert structural equality field-by-field — pin the chosen comparison.)

### Imports — S1 + M3 ONLY

The module requires:
- `mcp/core/main.rkt` (the S1 barrel: types M1 + errors M2 — for the `jsexpr` notion / `(json-null)` if needed, and the error constructors `make-mcp-error` / `make-protocol-error` for rejecting un-mappable contracts and non-object root schemas); and
- the M3 surface: `mcp/core/validators/provider.rkt` (item-010 port — `provider-compile`, `validate`, `compiled-validator?`, the result API) and `mcp/core/validators/from-json-schema.rkt` (item-011 default provider — `make-racket-native-provider`, used as the default `#:provider`).
- `racket/contract` to **introspect/recognize** the supported flat-contract forms (the module reasons over contracts but does NOT attach `contract-out` for the mapping — see Scope guard).

It MUST NOT require any transport, engine, role, subprocess, or socket module. Restricted-load portability MUST stay clean (no subprocess/socket pulled in) — the item-008/010/011 walk mechanism is reused (this item's test runs a `schema.rkt`-rooted load check; item 017 adds the collection-wide sweep). **Specifically:** the contract→JSON-Schema mapping MUST NOT reach for `net/url` (banned) for any format handling — all format checking happens inside the M3 provider's recognizers, not here.

### Scope guard (explicit — do NOT cross these lines)

- **Consumes M3 AS-IS.** Do NOT redefine the result structs, the port generic, or the keyword evaluator — `require` them from `provider.rkt` / `from-json-schema.rkt`. This module derives a wire JSON Schema and delegates ALL validation to the provider.
- **Single delegation path.** Form B does NOT validate by applying the raw `racket/contract` at validate time; it compiles a derived JSON Schema through the provider (the dual-form guarantee).
- **Flat-contract subset ONLY.** The supported mapping is the table above. Higher-order/dependent/struct/parametric/opaque-predicate contracts are **rejected at normalization** (clear S1 error), NOT silently mapped to `{}`.
- **No new validator semantics.** This module adds NO keyword evaluation — all accept/reject behaviour comes from the M3 provider over the derived JSON Schema. Constraint keywords the provider defers (`minLength` etc.) stay deferred; this module does NOT re-implement them.
- **No transport/engine/role/server logic.** The high-level server (S6b) is the CONSUMER; this module is L0 and stops at `(wire-schema, handle)`.
- **`promptArgumentsFromStandardSchema` analogue is OPTIONAL here.** It may ship now (cheap, a pure function of the wire schema) or be deferred to S6b. Pin the choice in Decisions; if shipped, test it; if deferred, note the follow-up. (Default recommendation: ship it — S6b needs it and it has no extra dependency.)

---

## Acceptance Criteria

- [ ] `mcp/core/util/schema.rkt` exists as `#lang racket/base` (or `#lang racket`) with an explicit, curated `provide` (no `(provide (all-defined-out))`). The `mcp/core/util/` collection directory is created by this item.
- [ ] The module exports `normalize-schema` (the entry point), the `normalized-schema` struct **predicate** + curated **accessors** (`normalized-schema-wire`, `normalized-schema-handle`, `normalized-schema-validate`), and the Form-B **object-descriptor surface** (the chosen struct/constructor + `field` helper, or the documented convention). It does NOT re-export the M3 result API (callers `require` `provider.rkt` for `validation-ok?` etc.) and does NOT leak internal mapping helpers.
- [ ] **Form A — JSON Schema input → wire + handle.** `(normalize-schema (hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string")) 'required '("name")))` returns a `normalized-schema?` whose `normalized-schema-wire` has root `type:"object"` and whose `normalized-schema-handle` is a `compiled-validator?`. `(normalized-schema-validate ns (hasheq 'name "John"))` → `validation-ok?`; `(normalized-schema-validate ns (hasheq))` → `validation-errors?`.
- [ ] **Form A — root `type:"object"` invariant.** A Form-A schema with NO root `type` gets `type:"object"` added to its wire schema. A Form-A schema with root `type:"object"` is unchanged (modulo the ensured key). A Form-A schema with an explicit **non-object** root `type` (e.g. `(hasheq 'type "string")`) is **rejected** at `normalize-schema` (`check-exn`, via an S1 error) — mirrors TS `standardSchemaToJsonSchema`'s throw.
- [ ] **Form B — flat-contract object descriptor → wire + handle.** Normalizing the object descriptor `{name: string? (required), age: exact-integer? (optional)}` (in the chosen surface) yields a wire JSON Schema `equal?` (or structurally equal, per the pinned comparison) to `(hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string") 'age (hasheq 'type "integer")) 'required '("name"))`, and a handle that accepts `{name:"a", age:5}` and `{name:"a"}` and rejects `{age:5}` and `{name:5}`.
- [ ] **Form B — supported flat-contract scalar mappings.** Each of `string?`→`{type:"string"}`, `exact-integer?`→`{type:"integer"}`, `real?`/`number?`→`{type:"number"}`, `boolean?`→`{type:"boolean"}` maps as tabled (verified by inspecting the wire fragment a one-field object descriptor produces). `(listof string?)`→`{type:"array", items:{type:"string"}}`. A string/number/bool/null-literal `or/c` (e.g. `(or/c "red" "green")`) → `{enum:["red","green"]}`.
- [ ] **Dual-form equivalence (the headline criterion, queue-mandated).** A Form-B contract input and an *equivalent* Form-A JSON-Schema input (per "Equivalent" above) produce handles that **accept the same set of values and reject the same set of values**: for the agreed accept-set, BOTH handles return `validation-ok?`; for the agreed reject-set, BOTH return `validation-errors?`. **AND** the two emitted **wire JSON Schemas match** (`equal?` / structural equality, after root-`type:"object"` normalization). Assert both halves (same verdicts + same wire) explicitly. This is the queue's key testable.
- [ ] **Contract with no JSON-Schema equivalent → rejected (edge case).** A higher-order/dependent/opaque contract — e.g. `(-> string? string?)`, an `(->i …)`, a `struct/c`, or a bare opaque predicate like `even?` used as a field contract — causes `normalize-schema` to **raise a clear S1 error** (`check-exn`), NOT to silently produce `{}` (which would accept everything) and NOT to crash with a raw Racket contract/internal error. The error message names the un-mappable contract/field.
- [ ] **Optional vs required fields (edge case).** In a Form-B object descriptor, a field marked required appears in the wire `required` array (as a **string**); a field marked optional does NOT. The handle then: rejects an object missing a required field; accepts an object missing an optional field; and (per item 011 `properties` semantics) validates an optional field's type *when present* (so `{name:"a", age:"x"}` rejects on `age`'s type even though `age` is optional). Pin all three.
- [ ] **Nested / non-flat rejection (edge case).** A nested object descriptor — a field whose contract is *itself* an object descriptor — is handled per the pinned policy: **recommended** is to support one documented level of nesting (a field mapping to a nested `{type:"object", properties:…}` wire fragment) OR to reject nested descriptors as out-of-the-flat-subset. **Pin and test whichever is chosen.** A genuinely non-flat *Racket* contract (higher-order, e.g. `(listof (-> any/c any/c))`) is **always rejected** (it falls under "no JSON-Schema equivalent"). Document the boundary between "nested object descriptor" (a structured input this module may support) and "non-flat Racket contract" (always rejected).
- [ ] **Empty schema (edge case).** Form A `(hasheq)` (empty JSON Schema) normalizes to a wire schema with root `type:"object"` added; its handle **accepts every object** (per item 011's empty-`{type:"object"}` semantics) — pin `(normalized-schema-validate ns (hasheq 'anything 1))` → `validation-ok?`. A Form-B empty object descriptor (no fields) likewise normalizes to `{type:"object", properties:{}, required:[]}` (or `{type:"object"}`) and accepts any object — pin no crash on the empty-properties case (item 011 S-f).
- [ ] **Dropped-constraint policy (and/c with a non-mappable constraint).** A field contract like `(and/c string? <length-constraint>)` maps its `type` part to `{type:"string"}`, **drops** the un-mappable constraint, and **surfaces the drop** per the pinned channel (a `normalized-schema-dropped` accessor or an `eprintf` line) — OR is rejected outright (the permitted alternative). The chosen branch is tested: if drop-and-record, assert the wire is `{type:"string"}` AND the dropped constraint is recorded; if reject, `check-exn`. (Record the choice in Decisions.)
- [ ] **Provider injection + default.** `normalize-schema` accepts `#:provider`. With no `#:provider`, it defaults to `(make-racket-native-provider)` (item 011). When a custom provider is supplied, the handle is compiled through THAT provider (verified with a stub provider OR by observing the default's `provider-warnings-for` for a deferred keyword routed through the wire schema). The provider is the M3 port — the module never validates outside it.
- [ ] **`normalized-schema-validate` sugar.** `(normalized-schema-validate ns v)` equals `(validate (normalized-schema-handle ns) v)` for representative `v` (a convenience that does not introduce a second validation path).
- [ ] **(If shipped) prompt-arguments helper.** `normalized-schema-prompt-arguments` over a wire schema with `properties {name, age}` and `required ["name"]` returns entries naming each property with its required flag (`name`→required, `age`→optional), mirroring TS `promptArgumentsFromStandardSchema`. (If deferred to S6b, this criterion is struck and a one-line follow-up note is added to Decisions.)
- [ ] **Imports = S1 + M3 ONLY.** The module requires only `mcp/core/main.rkt`, `mcp/core/validators/provider.rkt`, `mcp/core/validators/from-json-schema.rkt`, and `racket/contract` (+ `json` if `(json-null)` is used directly). It requires NO transport/engine/role/subprocess/socket module and NOT `net/url`. **Verified by a restricted-namespace load test** rooted at `schema.rkt` itself: a fresh `(make-base-namespace)` requiring it and walking `module->imports` transitively shows EMPTY intersection with the banned set (`racket/system racket/tcp racket/udp net/url net/http-client net/sendurl racket/sandbox racket/port`).
- [ ] `raco test mcp/core/util/` passes (exit 0) — module + new test compile and run cleanly within the new collection.
- [ ] `raco make mcp/core/util/schema.rkt` exits 0 (compiles clean, no warnings about missing/non-portable modules).
- [ ] Parity-matrix discipline: the `util/schema` row advances to `partial` (the dual-form normalization now exists; full conformance lands with items 017/018 + S9). Update `docs/aide/progress.md` per the Completion Reminder — flip the `util/schema.rkt` deliverable line AND check the Stage-S2 **schema-normalization** acceptance box (this item owns it).

---

## Implementation Steps

1. **Re-read the framing sources for shape + role:** `typescript-sdk/packages/core/src/util/standardSchema.ts` (the `standardSchemaToJsonSchema` root-`type:"object"` rule + throw-on-non-object; `validateStandardSchema` result shape; `promptArgumentsFromStandardSchema` extraction) and `util/schema.ts` (the thin schema→result role). Re-read item 011's `from-json-schema.rkt` public surface (`make-racket-native-provider`, `provider-warnings-for`) and item 010's `provider.rkt` (`provider-compile`, `validate`, `compiled-validator?`, the result API) so you require, not redefine, M3.
2. **Decide + pin the Form-B object-descriptor surface** (a `struct`/`field` helper vs an assoc-list convention) and the **form-detection rule** (`hash?` → Form A; the descriptor representation → Form B; bare flat contract → Form B-then-wrap-or-reject). Record both in Decisions BEFORE writing the mapping.
3. **Write `mcp/core/util/schema.rkt`.** Use `#lang racket/base`. In order:
   - `(require racket/contract racket/list "../main.rkt" "../validators/provider.rkt" "../validators/from-json-schema.rkt")` plus `json` if `(json-null)` is needed.
   - A module-level **doc block** recording: the role-port framing (Standard-Schema analogue, input forms net-new per §8); the two input forms; the **contract→JSON-Schema mapping table + its documented limits** (flat-only; dropped-constraint policy; format-annotation surface; reject-on-un-mappable); the **single-delegation-path** directive; the root-`type:"object"` invariant; and the symbol/string field-name boundary (wire `properties` keys = symbols, wire `required` members = strings — matching item 011).
   - The **`normalized-schema` struct** (`wire`, `handle`, and whatever the dropped-constraint channel needs) with curated accessors only.
   - The **Form-A path** `(json-schema->wire schema)`: ensure root `type:"object"` (add if absent; reject if explicit non-object); return the wire schema.
   - The **Form-B mapping** `(descriptor->wire descriptor)`: walk the object descriptor's fields, mapping each flat contract via a `(flat-contract->fragment c)` cond over the supported table; collect `properties` (symbol-keyed) + `required` (string list of required fields); reject (via `make-protocol-error`/`make-mcp-error`) any un-mappable contract; surface dropped constraints per the pinned channel.
   - **`normalize-schema`** `(input #:provider [provider (make-racket-native-provider)])`: detect the form, produce the wire schema (Form A or Form B), `(provider-compile provider wire)` for the handle, construct + return the `normalized-schema`.
   - `normalized-schema-validate` sugar; the optional `normalized-schema-prompt-arguments`; the explicit `(provide …)` block (entry point + struct predicate/accessors + Form-B surface; NOT internal mapping helpers; NOT a re-export of the M3 result API).
4. **Write the test** `mcp/core/util/test/schema-test.rkt` (see Testing Strategy). Cover both forms (A + B), the dual-form equivalence (same accepts/rejects + same wire), the root-`type:"object"` invariant (add / unchanged / reject-non-object), every supported scalar/array/enum mapping, optional-vs-required, the un-mappable-contract reject, nested/non-flat policy, the empty-schema case, the dropped-constraint branch, provider injection + default, the `validate` sugar, the optional prompt-arguments helper, and the restricted-load portability sub-test (reuse the item-008/010/011 walk helper; entry point = `schema.rkt`).
5. **Run** `raco make mcp/core/util/schema.rkt` then `raco test mcp/core/util/`. Fix any failure. Confirm `raco test mcp/core/validators/` still passes (this item does not touch M3).
6. **Update progress + parity matrix** (see Completion Reminder).

---

## Testing Strategy

The test is a **dual-form normalization test**: it proves a contract input and an equivalent JSON-Schema input produce the same validation behaviour and the same wire schema, plus per-form mapping coverage, the root-`type:"object"` invariant, the documented edge cases, and the restricted-load portability sub-test. Validation *verdict* mechanics (the keyword semantics) are already exhaustively covered by item 011's `from-json-schema-test.rkt` and are NOT re-litigated here — this test asserts that normalization wires the RIGHT schema into the provider, not that the provider validates correctly.

**Test file:** `mcp/core/util/test/schema-test.rkt` (`#lang racket/base`; `(require rackunit json racket/contract "../schema.rkt" "../../validators/provider.rkt" "../../validators/from-json-schema.rkt")` plus `racket/set`/`racket/path` for the portability walk). `json` is needed for `(json-null)` (null-literal enum + null value cases); `provider.rkt` for `validation-ok?`/`validation-errors?`; `from-json-schema.rkt` for the default provider + `provider-warnings-for` (provider-injection check).

Small helpers keep assertions terse:
```racket
(define (ok? ns v)   (validation-ok? (normalized-schema-validate ns v)))
(define (bad? ns v)  (validation-errors? (normalized-schema-validate ns v)))
(define (wire ns)    (normalized-schema-wire ns))
;; (same-verdicts ns-a ns-b accepts rejects) -> asserts every v in accepts is ok? under BOTH,
;;   and every v in rejects is bad? under BOTH (the dual-form core).
```

### Part 1 — Form A (JSON Schema input)

- **Identity + handle:** `(define ns (normalize-schema (hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string")) 'required '("name"))))` — `(normalized-schema? ns)` → `#t`; `(hash-ref (wire ns) 'type)` → `"object"`; `(compiled-validator? (normalized-schema-handle ns))` → `#t`; `(ok? ns (hasheq 'name "John"))` → `#t`; `(bad? ns (hasheq))` → `#t` (missing required).
- **Root `type:"object"` added when absent:** `(normalize-schema (hasheq 'properties (hasheq 'x (hasheq 'type "string"))))` → wire root `type` is `"object"`.
- **Root unchanged when already object:** the wire equals the input (modulo the ensured `type`).
- **Non-object root rejected:** `(check-exn exn:fail? (lambda () (normalize-schema (hasheq 'type "string"))))` — mirrors the TS throw.
- **Empty schema:** `(define ns (normalize-schema (hasheq)))` — wire root `type` is `"object"`; `(ok? ns (hasheq 'anything 1))` → `#t`; `(ok? ns (hasheq))` → `#t`; no crash.

### Part 2 — Form B (flat-contract object descriptor)

- **Object descriptor → wire:** build the descriptor `{name: string? (required), age: exact-integer? (optional)}` in the chosen surface; assert `(wire ns)` equals (or is structurally equal to) `(hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string") 'age (hasheq 'type "integer")) 'required '("name"))`. **`required` members are STRINGS, `properties` keys are SYMBOLS** — assert both explicitly.
- **Scalar mappings:** for a one-field descriptor, assert the produced `properties` fragment for each of `string?`→`{type:"string"}`, `exact-integer?`→`{type:"integer"}`, `real?`/`number?`→`{type:"number"}`, `boolean?`→`{type:"boolean"}`.
- **Array mapping:** `(listof string?)` → `{type:"array", items:{type:"string"}}` (assert the `items` sub-fragment).
- **Enum mapping:** `(or/c "red" "green")` → `{enum:["red","green"]}`; a mixed-literal `(or/c "x" 42 #t)` → `{enum:["x",42,#t]}` (literal members carried through; assert membership). A null-literal `(or/c "x" (json-null))` carries `(json-null)` as a member.
- **Optional vs required:** the handle rejects `{age:5}` (missing required `name`); accepts `{name:"a"}` (optional `age` absent); rejects `{name:"a", age:"x"}` (optional `age` present-but-wrong-type — item 011 `properties` validates present optionals).

### Part 3 — Dual-form equivalence (the headline)

- Build `ns-contract` from the Form-B descriptor `{name: string? (required), age: exact-integer? (optional)}` and `ns-json` from the equivalent Form-A `(hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string") 'age (hasheq 'type "integer")) 'required '("name"))`.
- **Same accepts:** `(hasheq 'name "a" 'age 5)`, `(hasheq 'name "a")` → BOTH `ok?`.
- **Same rejects:** `(hasheq 'age 5)` (no name), `(hasheq 'name 5)` (wrong-type name), `(hasheq 'name "a" 'age "x")` (wrong-type age) → BOTH `bad?`.
- **Same wire:** `(equal? (wire ns-contract) (wire ns-json))` → `#t` (or structural equality per the pinned comparison — assert field-by-field if hash-ordering makes `equal?` brittle; pin which).
- Run all three assertions via the `same-verdicts` helper + an explicit wire-equality check.

### Part 4 — Edge cases

- **No-JSON-Schema-equivalent contract → reject:** `(check-exn exn:fail? (lambda () (normalize-schema <descriptor-with (-> string? string?)>)))`; same for an `(->i …)`, a `struct/c`, and a bare opaque predicate `even?` as a field contract. Assert the error is an S1 error type (not a raw Racket contract error) and (optionally) that its message names the offending field/contract.
- **Nested / non-flat policy:** test the PINNED choice — if one nesting level is supported, a field whose contract is a nested object descriptor produces a `{type:"object", properties:…}` wire fragment and the handle validates the nested object; if nesting is rejected, `check-exn`. Additionally, a non-flat *Racket* contract (`(listof (-> any/c any/c))`) is **always rejected** (`check-exn`).
- **Dropped-constraint branch:** test the PINNED choice for `(and/c string? <length-constraint>)` — if drop-and-record, assert `(wire …)` field is `{type:"string"}` AND the dropped constraint is surfaced (via the accessor or a captured `eprintf` line); if reject, `check-exn`.
- **Empty Form-B descriptor:** a no-field descriptor → wire `{type:"object", properties:{}, required:[]}` (or `{type:"object"}`); `(ok? ns (hasheq 'anything 1))` → `#t`, no crash (item 011 S-f).

### Part 5 — Provider injection + default + sugar

- **Default provider:** with no `#:provider`, `(normalize-schema (hasheq 'type "object"))` compiles through `(make-racket-native-provider)` — `(compiled-validator? (normalized-schema-handle ns))` → `#t`.
- **Custom provider:** pass an explicit `(make-racket-native-provider)` (or a trivial stub provider satisfying `gen:json-schema-validator-provider`) via `#:provider`; assert the handle came from THAT provider. With the default provider, route a deferred keyword through a Form-A wire schema (`(hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string" 'minLength 3)))`) and assert `(provider-warnings-for the-provider (normalized-schema-handle ns))` records `'minLength` — proving the module compiled through the provider (not an ad-hoc checker).
- **`normalized-schema-validate` sugar:** `(equal? (normalized-schema-validate ns v) (validate (normalized-schema-handle ns) v))` for an ok value and a bad value (structural equality on the result — or assert both are `validation-ok?` / both `validation-errors?`).

### Part 6 — (If shipped) prompt-arguments helper

- For a wire schema with `properties {name, age}` + `required ["name"]`, `(normalized-schema-prompt-arguments ns)` returns two entries; `name` is required, `age` is not; descriptions (if the wire `properties` carry `description`) are surfaced. Mirrors TS `promptArgumentsFromStandardSchema`. (Struck if the helper is deferred to S6b — note the follow-up in Decisions.)

### Part 7 — restricted-namespace portability (S1 + M3 only)

Reuse the transitive `module->imports` walk from item 008/010/011 — fresh `(make-base-namespace)`, `namespace-require` `schema.rkt`, walk imports threading `current-load-relative-directory` per module dir, assert the FULL banned set (`racket/system racket/tcp racket/udp net/url net/http-client net/sendurl racket/sandbox racket/port`) has empty intersection with the visited set. **Entry point is `schema.rkt` ITSELF.** This proves the schema util (and, transitively, the M3 modules it requires) is portability-clean. **Specifically guards** that the contract→JSON-Schema mapping did not reach for `net/url` (banned) for any format handling. **Non-vacuity (drift):** temporarily inject `(require racket/tcp)` into a scratch copy, confirm the walk FAILS naming `racket/tcp`, then revert. (Scope note inherited from item 008: `module->imports` does not see into `(module+ test …)` submodules — proves the module's own import graph, not a test submodule's.)

---

## Dependencies

- **Upstream work items:**
  - **Item 010** (`mcp/core/validators/provider.rkt`, ✅ complete) — this item REQUIRES the port: `provider-compile`, `validate`, `compiled-validator?`, and the result API `validation-ok` / `validation-errors` / `validation-error` (+ predicates/accessors). The validation handle IS a `compiled-validator?` produced via `provider-compile`.
  - **Item 011** (`mcp/core/validators/from-json-schema.rkt`, ✅ complete) — the **default provider**: `make-racket-native-provider` (the `#:provider` default) and `provider-warnings-for` (used by the provider-injection test). BOTH input forms compile their derived wire JSON Schema through this provider.
  - **Stage S1 items 001–009** (✅ complete) — `mcp/core/main.rkt` (item 008 barrel: types M1 + errors M2). Provides the `jsexpr` notion, `(json-null)`, and `make-mcp-error` / `make-protocol-error` for rejecting un-mappable contracts + non-object root schemas.
- **Downstream consumers (informational):**
  - **S6b** high-level server (`mcp/server/mcp.rkt`, M12b) — consumes `normalize-schema` for tool/prompt I/O: advertises `normalized-schema-wire` in `tools/list` / prompt-argument lists and validates incoming arguments through `normalized-schema-handle` (and uses `normalized-schema-prompt-arguments` if shipped here).
  - **Item 017** — the S2 collection-wide restricted-load portability sweep includes `mcp/core/util/schema.rkt` (this module).
  - **Item 018** — the S2 demo registers a schema and validates a good + bad value (via the M3 provider directly; this module is the production path S6b uses).
- **Tooling/runtime:** Racket ≥ 8.x (`raco`, `rackunit`). The `typescript-sdk/` checkout MUST be present for **authoring** — the role/shape is lifted from `util/standardSchema.ts` (the root-`type:"object"` rule, the validate-result shape, the prompt-argument extraction). The Racket test does NOT parse the `.ts` at runtime; the parity here is structural (the output pair + the object-root invariant), not a fixture port, so a missing checkout would not break the running test but would make the role-mapping un-reproducible.

---

## Decisions & Trade-offs

To be updated during implementation.

*(Record at minimum: the chosen Form-B object-descriptor surface (struct/`field` vs convention); the form-detection rule; the dropped-constraint policy branch (drop-and-record vs reject) + its surfacing channel; the nested-descriptor policy (one level supported vs rejected); the bare-non-object Form-B input policy (reject vs auto-wrap); the format-annotation surface for Form B; the wire-schema comparison used in the dual-form test (`equal?` vs structural); whether `normalized-schema-prompt-arguments` ships here or defers to S6b; and the require list with each import's justification + the restricted-load drift result.)*

---

## Project-Specific Adaptations (Racket / raco / rackunit)

This is a **Racket library, not a service** — same adaptation pattern as items 010/011. The generic "Testing Prerequisites" template (Required Services / database / API endpoint / ports / health checks) does **not** apply and is adapted as follows (documented explicitly per the create-item skill):

- **Required Services → None.** Pure Racket library; no external services, databases, message queues, HTTP servers, sockets, subprocesses, or network. The module is L0 and load-portable by construction (and proven so by the restricted-load test). **Note:** any format handling MUST go through the M3 provider's recognizers — this module MUST NOT use `net/url` (banned by the portability NFR).
- **Database / API endpoint / ports sections → N/A.** Removed; replaced by the Racket toolchain row below.
- **Required toolchain:** Racket ≥ 8.x (`raco test`, `rackunit`). Verified present in this environment: **Racket v8.18 [cs]**.
- **TS checkout role:** present at `typescript-sdk/`; **required for authoring** (the role/shape is lifted from `util/standardSchema.ts` — root-`type:"object"` rule, validate-result shape, prompt-argument extraction). Unlike a fixture-parity item, the parity here is structural, not a hard-coded fixture port.
- **Manual Validation Checklist → specialized** to `raco make` / `raco test` + a REPL / normalize smoke check (below). No "service started" / "health check" / "screenshots" rows — replaced with N/A or removed.
- **Language/naming:** `#lang racket/base`; kebab-case bindings; explicit `(provide …)` never `all-defined-out` (architecture §1.3); consumes the M3 port via `provider-compile`/`validate` (architecture §4.1).
- **New collection directory:** this item creates `mcp/core/util/` and `mcp/core/util/test/` (they do not yet exist) — the first M4 module.

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None (pure Racket library; no external services).** No databases, message queues, HTTP servers, sockets, subprocesses, or network dependencies.

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime | compile + run module and tests (`raco`, `rackunit`) | system install (`racket --version` ≥ 8.0; this env: v8.18) | n/a |
| S1 barrel (`mcp/core/main.rkt`) | the module requires the S1 public surface (types + errors) | already present (items 001–008, ✅) | n/a |
| Item-010 port (`mcp/core/validators/provider.rkt`) | the validation handle is a `compiled-validator?` produced via `provider-compile` | already present (item 010, ✅) | n/a |
| Item-011 default provider (`mcp/core/validators/from-json-schema.rkt`) | the `#:provider` default + `provider-warnings-for` for the injection test | already present (item 011, ✅) | n/a |
| `typescript-sdk/` checkout | read while authoring to lift the role/shape from `util/standardSchema.ts` (structural parity) | already present at repo root | n/a |

### Environment Configuration

- **Environment variables / secrets / config files / free ports:** none required.
- **Racket version:** ≥ 8.x (verified: v8.18 [cs]).
- **Working directory:** run `raco test` from the **repo root** so the `mcp/...` collection path resolves.
- **How to run the tests:**
  - `raco make mcp/core/util/schema.rkt` — compile the schema util clean.
  - `raco test mcp/core/util/` — run all util-collection tests (picks up `test/schema-test.rkt` recursively), exit 0.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0.
  - `raco make mcp/core/validators/from-json-schema.rkt` → exit 0 (the item-011 provider this item requires loads clean).
  - `raco make mcp/core/validators/provider.rkt` → exit 0 (the item-010 port loads clean).

### Manual Validation Checklist

*(Not yet built — leave UNCHECKED until implementation completes.)*

- [ ] **Build/compile succeeds:** `raco make mcp/core/util/schema.rkt` compiles with no errors/warnings.
- [ ] **Module loads in isolation:** `racket -e '(require (file "mcp/core/util/schema.rkt"))'` from repo root succeeds.
- [ ] **Tests pass:** `raco test mcp/core/util/test/schema-test.rkt` → all checks pass, exit 0.
- [ ] **Collection tests pass:** `raco test mcp/core/util/` → exit 0.
- [ ] **M3 untouched:** `raco test mcp/core/validators/` → still exit 0 (this item does not modify M3).
- [ ] **Services started:** N/A (no services — pure library).
- [ ] **Application runs:** N/A (library; "running" = the require + REPL/normalize smoke check below).
- [ ] **Feature verified (REPL / normalize smoke check):** from repo root, normalize a JSON Schema and validate a good + bad value — e.g.
      `racket -e '(require (file "mcp/core/util/schema.rkt") (file "mcp/core/validators/provider.rkt")) (define ns (normalize-schema (hasheq (quote type) "object" (quote properties) (hasheq (quote name) (hasheq (quote type) "string")) (quote required) (list "name")))) (list (validation-ok? (normalized-schema-validate ns (hasheq (quote name) "John"))) (validation-errors? (normalized-schema-validate ns (hasheq))))'`
      prints `(#t #t)` (ok for `{name:"John"}`, errors for `{}` — missing required). (Adjust to the chosen accessor names; record exact transcript in Validation Results.)
- [ ] **Form A verified:** JSON-Schema input → wire (root `type:"object"`) + handle; ok/bad values validate.
- [ ] **Form A root invariant verified:** no-root-`type` → `type:"object"` added; object root → unchanged; non-object root (`{type:"string"}`) → rejected (raise).
- [ ] **Form B object descriptor verified:** `{name:string?(req), age:exact-integer?(opt)}` → wire equals the equivalent JSON Schema; `properties` keys are symbols, `required` members are strings.
- [ ] **Form B scalar/array/enum mappings verified:** string/integer/number/boolean; `(listof string?)`→array+items; `(or/c "red" "green")`→enum.
- [ ] **Dual-form equivalence verified (headline):** contract input and equivalent JSON-Schema input accept the same value set + reject the same value set, AND emit the same wire schema.
- [ ] **No-equivalent contract rejected:** `(-> string? string?)` / `(->i …)` / `struct/c` / bare `even?` as a field contract → `normalize-schema` raises an S1 error (not silent `{}`, not a raw contract crash).
- [ ] **Optional vs required verified:** required field in wire `required` (string); optional absent OK; optional-present-wrong-type rejects.
- [ ] **Nested/non-flat policy verified:** the pinned choice (one nesting level supported OR nested-descriptor rejected) is tested; a non-flat Racket contract is always rejected.
- [ ] **Empty schema verified:** Form-A `(hasheq)` → wire `type:"object"`, accepts any object; Form-B empty descriptor → accepts any object, no crash (S-f).
- [ ] **Dropped-constraint branch verified:** `(and/c string? <len>)` → pinned branch (drop+record OR reject) tested.
- [ ] **Provider injection + default verified:** default `make-racket-native-provider`; custom provider routed; deferred-keyword `provider-warnings-for` proves compile-through-provider.
- [ ] **`normalized-schema-validate` sugar verified:** equals `(validate (normalized-schema-handle ns) v)`.
- [ ] **(If shipped) prompt-arguments helper verified:** entries per property with required flags; mirrors TS.
- [ ] **Portability verified:** the restricted-load test passes (no subprocess/socket — incl. NO `net/url` — in the transitive import closure of `schema.rkt`).
- [ ] **Drift / non-vacuity check (portability):** temporarily add `(require racket/tcp)` to a scratch copy, confirm the load test FAILS naming `racket/tcp`, then revert.
- [ ] **Health checks pass:** N/A (no running service).

### Expected Outcomes

Concrete, verifiable:

- The module **exports** `normalize-schema` (entry point), the `normalized-schema` struct predicate + curated accessors (`normalized-schema-wire`, `normalized-schema-handle`, `normalized-schema-validate`), and the Form-B object-descriptor surface (chosen struct/constructor + `field` helper, or the documented convention). It does NOT re-export the M3 result API and does NOT leak internal mapping helpers. `(normalized-schema? (normalize-schema (hasheq 'type "object")))` → `#t`.
- A Form-A JSON-Schema input and an equivalent Form-B contract input produce **the same wire JSON Schema** and **handles that accept the same values and reject the same values** (the dual-form guarantee).
- An un-mappable contract (higher-order/dependent/opaque) is **rejected with a clear S1 error**, not silently mapped to an accept-everything schema.
- A non-object root JSON Schema is **rejected** (root-`type:"object"` invariant, ported from TS).
- The module **requires only S1 + M3** (+ `racket/contract`, + `json` if used) — a restricted-namespace load test confirms NO subprocess/socket module (`racket/system`, `racket/tcp`, `racket/udp`, `net/*`, `racket/sandbox`, `racket/port`) is pulled in (Portability NFR).
- `raco test mcp/core/util/` reports all checks passing, 0 failures, 0 errors; `raco test mcp/core/validators/` still green (M3 untouched).

### Validation Results

*(Populated post-build — fill with the actual `raco make` / `raco test` transcript, the normalize smoke-check output, the portability drift result, and the final check counts. Mirror the item-011 Validation Results block format.)*

```markdown
## Validation Results
- [ ] Service started: N/A (pure Racket library, no services)
- [ ] Application started successfully: N/A (library; `require` + normalize smoke check → `(#t #t)`)
- [ ] Build verified: `raco make mcp/core/util/schema.rkt` clean (exit 0, no warnings)
- [ ] Module load verified: `(require (file ".../schema.rkt"))` succeeds
- [ ] Tests verified: `raco test mcp/core/util/` → <N> checks pass, 0 failures, 0 errors
- [ ] M3 untouched: `raco test mcp/core/validators/` → still exit 0
- [ ] Form A verified: JSON-Schema input → wire (root type:object) + handle; ok/bad validate
- [ ] Form A root invariant: no-type→added; object→unchanged; non-object→rejected
- [ ] Form B object descriptor verified: wire equals equivalent JSON Schema; properties symbol-keyed, required string members
- [ ] Form B scalar/array/enum mappings verified
- [ ] Dual-form equivalence verified (headline): same accepts + same rejects + same wire
- [ ] No-equivalent contract rejected: higher-order/dependent/opaque → S1 error (not silent {})
- [ ] Optional vs required verified
- [ ] Nested/non-flat policy verified (pinned choice tested)
- [ ] Empty schema verified: Form-A {} + Form-B empty descriptor accept any object, no crash
- [ ] Dropped-constraint branch verified (drop+record OR reject)
- [ ] Provider injection + default verified (provider-warnings-for proves compile-through-provider)
- [ ] normalized-schema-validate sugar verified
- [ ] (If shipped) prompt-arguments helper verified
- [ ] Portability verified: restricted-load walk over schema.rkt — empty intersection with banned set (incl. no net/url)
- [ ] Portability drift check: injected (require racket/tcp) → walk FAILED naming racket/tcp, then reverted
- [ ] S1 + M3 imports confirmed: require list = racket/contract + ../main.rkt + ../validators/provider.rkt + ../validators/from-json-schema.rkt (+ json if used)
- [ ] Database tables verified: N/A
- [ ] Seed data verified: N/A
- [ ] API endpoints verified: N/A
- [ ] Screenshots captured: N/A (no UI)
```

---

## Completion Reminder

On completion, the implementer MUST update **`docs/aide/progress.md`** (Stage S2 section), advancing the icon **📋 → 🚧 → ✅**:

1. Flip the deliverable line **`📋 mcp/core/util/schema.rkt — contract-or-JSON-Schema normalization (Standard-Schema analogue)`** (progress.md line ~73) from 📋 → 🚧 (on start) → ✅ (on delivery + all acceptance criteria pass). Never revert an icon backward.
2. **Check the Stage-S2 schema-normalization acceptance box** — **`[ ] Schema normalization: contract input and equivalent JSON-Schema input accept/reject same values; wire schema matches`** (progress.md line ~85). **This box belongs to THIS item** (it owns the dual-form normalization deliverable). Check it on delivery.
3. Do **not** check the other broad Stage-S2 acceptance boxes that depend on sibling items (the `raco test over all S2 modules`, URI-template, tool-name, validator-keyword-coverage, and stdio-framing boxes belong to items 010/011/013–018).
4. **Parity matrix:** per Stage S2 discipline, advance the **`util/schema` row to `partial`** (the dual-form normalization now exists; full conformance + the collection-wide sweep land with items 017/018 and S9). Add a sentence to the parity-matrix progression paragraph recording that the `util/schema` row is now `partial` (mirroring the item-010/011 entries for `validators/*`).
5. Leave all other S2 deliverable lines (`validators/*` already ✅; the `shared/*` utils; tests-under-other-dirs) at their current status — this item delivers only `util/schema.rkt` + its test (and creates the `mcp/core/util/` collection).
