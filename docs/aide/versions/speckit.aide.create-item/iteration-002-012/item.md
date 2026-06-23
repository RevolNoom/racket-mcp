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

> **Deferred keywords in a Form-A input pass through UNTOUCHED — advertised as-is, enforced per item 011 (pinned, issue #3).** A hand-written JSON Schema commonly carries keywords item 011 *defers* (`minLength`, `pattern`, `minimum`, `additionalProperties`, `uniqueItems`) — this is the realistic Form-A case. This module does **NOT** strip, rewrite, or reject them: the **wire schema retains the keyword verbatim** (so a client sees the full advertised schema, and a future vetted-library provider could enforce it), and the **handle's accept/reject behaviour is exactly item 011's** — the deferred keyword is ignored-with-warning and recorded in the provider's per-compile weak handle→ignored-keyword map (readable via `provider-warnings-for`). Concretely: `(normalize-schema (hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string" 'minLength 3))))` → the wire `properties.name` STILL contains `'minLength 3`, and the handle **accepts** `{name:"x"}` (minLength not enforced — deferred). This means the util's **default fresh-provider-per-call** path exercises item 011's warn-once/weak-map machinery once per normalization; see the Decisions note on fresh-provider-per-call (a perf consideration if S6b normalizes per tool registration). Pinned (case 3).

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
| `(or/c <lit> <lit> …)` where **every** arm is a string/number/bool/null **literal datum** | `{ "enum": [<lit>, …] }` |
| `(or/c <flat> <flat>)` containing any **type predicate** (`(or/c string? number?)`) | **rejected** (no single-`type` JSON-Schema equivalent in the M3 subset) |
| `(or/c <lit> <predicate>)` **mixed** literal+predicate (`(or/c "a" string?)`) | **rejected** (NOT a clean enum — see "or/c arm rules" below) |
| `(and/c …)` (any) | **rejected** (no clean single-fragment equivalent — see "and/c is rejected" below) |
| an **object descriptor** (a structured field→`(flat-contract . required?)` declaration) | `{ "type":"object", "properties": {…}, "required": [required-field-names] }` |

> **`exact-integer?` is PINNED for `integer` — `integer?` is REJECTED (self-consistency with item 011, S5).** Racket's `integer?` is `#t` for `5.0` (an inexact integer), but item 011's `json-integer?` recognizer is `exact-integer?` (a JSON integer is exact — `5.0` is a JSON *number*, not an *integer*). If the mapper recognized `integer?` and emitted `{type:"integer"}`, the contract author would believe `5.0` is in-bounds while the **derived handle rejects it** — a self-inconsistency (the util's advertised contract disagrees with the validator it itself compiled). To keep the contract form and its own derived handle in lockstep, **only `exact-integer?` maps to `{type:"integer"}`**; `integer?` (and `(and/c …)` wrapping it) is **rejected** as un-mappable. Pinned by the `5.0`-rejects test (case 6) and documented in Decisions.

> **`or/c` arm rules (pinned).** (a) **All-literal** `or/c` → `enum` (the only clean mapping; JSON-Schema `enum` *is* a closed set of literal members). (b) **Single-arm** `(or/c "a")` → `{enum:["a"]}` (degenerate but valid; accepted). (c) **Duplicate members** `(or/c "a" "a")` → the literal members are **de-duplicated** in the emitted `enum` (`{enum:["a"]}`) — item 011's `enum` accepts a duplicate member list without crashing, but the wire schema is de-duplicated for cleanliness; pin the de-dup. (d) **Mixed literal+predicate** `(or/c "a" string?)` and (e) **any predicate arm** `(or/c string? number?)` → **REJECTED** (the table's "mixed"/"type predicate" rows). Rationale: the "literal datums" precondition for a clean `enum` is violated the moment a non-literal arm appears; there is no single M3-supported keyword that means "string OR the literal 'a'", and silently emitting `{enum:["a"]}` (dropping the `string?` arm) would *narrow* the advertised contract (rejecting strings the author meant to allow). REJECT surfaces the gap.

> **`and/c` is REJECTED (pinned).** `and/c` has **no clean single-fragment JSON-Schema equivalent** in the M3 subset: its non-`type` conjuncts are exactly the constraint keywords item 011 *defers* (`(and/c string? (string-len/c 10))` → a `minLength`/`maxLength`-shaped constraint the provider cannot enforce). Rather than the earlier "map the type, drop the constraint, surface the drop" middle path — which is **superseded** — `and/c` is **rejected at normalization** with a clear S1 error naming the offending field. This is simpler, falsifiable, and avoids advertising a `{type:"string"}` that silently discards the length bound the author wrote. (The reviewer's case 7 pins this.) **Supersedes the dropped-constraint policy** described earlier in this spec's history; there is now ONE policy for `and/c`: reject. (A contract author who wants a length-bounded string supplies a JSON Schema directly — where item 011's deferred-keyword ignore-with-warning applies and the keyword at least round-trips in the wire schema for a future provider.)

The **surface for declaring an object descriptor is PINNED** as a module-defined constructor `(object-schema/c field-hash #:required req-list)` where `field-hash` is a `hasheq` of `field-symbol → flat-contract` and `req-list` is a list of field symbols required (the rest optional). (This is recommended over an assoc-list because it makes the field→contract map and the required-set explicit and introspectable.) Whatever the surface, the mapping MUST yield wire `properties` keyed by **symbol** field names and a wire `required` array of **string** field names (matching item 011's symbol/string boundary).

> **`object-schema/c` raises when `#:required` names an absent field (pinned, issue #4 case 4).** `(object-schema/c (hash 'name string?) #:required '(missing))` — where `missing` is not a key of the field hash — **raises at construction** (a clear S1/`exn:fail` error naming the absent field), NOT at normalize and NOT silently. Rationale: a required-but-undeclared field is a programmer error (the emitted `required:["missing"]` would reference a property with no schema, advertising a self-contradictory schema and rejecting *every* object on the missing field). Fail at the earliest point — descriptor construction. Pinned (case 4).

**Documented mapping limits (Form B):**
- **Flat only.** Higher-order contracts (`->`, `->*`, `case->`), dependent contracts (`->i`), struct/`struct/c`, parametric contracts, and arbitrary opaque predicates (e.g. `even?`, a custom `(flat-named-contract …)` over a lambda) have **no JSON-Schema equivalent in the M3 subset** → such a contract is **rejected at normalization** with a clear S1 error (NOT silently mapped to an empty/`{}` schema that would accept everything). This is the "contract with no JSON-Schema equivalent" edge case.
- **No constraint keywords → `and/c` is REJECTED (pinned, see the mapping table note).** A contract like `(and/c string? (string-len/c 10))` has no clean single-fragment equivalent — its constraint conjunct maps to an item-011 *deferred* keyword (`minLength`/`maxLength`). Policy (**decided**): **reject `and/c` at normalization** with a clear S1 error naming the field. This supersedes any "map-the-type-drop-the-constraint" middle path: dropping a constraint would advertise a `{type:"string"}` that silently discards the bound the author wrote (a contract narrower than advertised). A contract author who needs a length-bounded string supplies a JSON Schema directly (Form A), where item 011's deferred-keyword ignore-with-warning applies and the keyword round-trips in the wire schema for a future provider.
- **Format contracts → NOT produced from Form B in this iteration (decided).** There is no clean flat-contract analogue for a JSON-Schema `format`, and inferring one from a bare opaque predicate would be heuristic guessing (forbidden — a bare predicate is rejected as un-mappable, not silently treated as a format). So the **contract form never emits `format`**; a tool author who wants a `format` constraint supplies a **Form-A JSON Schema** (`{type:"string", format:"email"}`), where item 011's format recognizers apply. Documented limitation (consistent with the "no format from contracts" framing); no `(format/c …)` surface ships here. (Revisitable in a later item if a format-contract surface proves needed.)

### The normalized result (the uniform output)

`normalize-schema` accepts `(input #:provider [provider (make-racket-native-provider)])` where `input` is EITHER a parsed JSON Schema (`hash?`) OR a contract/object-descriptor (the Form-B surface), and returns a **`normalized-schema`** value (a `struct`, opaque-ish — curated accessors only) carrying:
- `normalized-schema-wire` → the wire JSON Schema (jsexpr `hasheq`, root `type:"object"`);
- `normalized-schema-handle` → the item-010 `compiled-validator?` (compiled through the provider);
- (helper) `normalized-schema-validate` → `(normalized-schema-validate ns value)` = `(validate (normalized-schema-handle ns) value)` → a `validation-result?` (sugar so callers don't reach through to the handle);
- `normalized-schema-prompt-arguments` → arg entries derived from the wire `properties`/`required` (mirrors TS `promptArgumentsFromStandardSchema`). **Decided: ships here** (it is a pure function of the wire schema, has no extra dependency, and S6b needs it) — tested in Part 6.

> **Form detection (pinned) — JSON-Schema input MUST be an `immutable?` `hasheq` with SYMBOL keys.** The detection rule: input that satisfies `(and (hash? x) (immutable? x) (hash-eq? x))` is Form A (a parsed JSON Schema); input that is the Form-B object-descriptor struct (a distinct, module-defined `struct` — NOT a hash) is Form B; a bare flat contract (a procedure/`flat-contract?`) is Form B-bare. Anything else **raises** a clear S1 error.
>
> **Why the stricter `hash-eq?`/`immutable?` guard, not bare `hash?` (issue #6 — silent-total-failure guard).** Racket's `json` reader produces an **immutable `hasheq`** (symbol keys). A bare `(hash? x)` test would ALSO accept a mutable hash, an `equal?`-keyed hash, or — critically — a **string-keyed** hash (`(hash "type" "object")`). A string-keyed hash routed into the M3 provider mis-validates silently: item 011 looks up `required` members and `properties` via **symbol** keys (`(hash-has-key? value (string->symbol req))`), so against a string-keyed schema **every `required` check and every `properties` descent fails to find its key** — the exact silent-total-failure bug item 011's docs warn about. So Form A input is required to be a `hasheq` with symbol keys (what `read-json`/`string->jsexpr` produce); a string-keyed or `equal?`-keyed hash is **out of contract → rejected** (case 8). The Form-B object descriptor is a distinct struct precisely so a `hasheq` is never ambiguous between the two forms. Pinned in Decisions + tested (case 8). A bare single flat-contract input (not wrapped in an object descriptor) is mapped, then handled per the root-`type:"object"` invariant below (a bare scalar/array/enum root → reject).

> **Root `type:"object"` invariant (ported from TS) — the rule is DELIBERATELY FORM-DEPENDENT (pinned).** MCP tool/prompt schemas MUST be object-typed at the root. The TS `standardSchemaToJsonSchema` does `return { type: 'object', ...result }` — it **adds** `type:"object"` to a *typeless* result (e.g. a Zod discriminated union that emits `{oneOf:…}` with no root `type`) and only **throws** on an *explicit non-object* root `type`. We mirror that for Form A, but a *contract-derived* typeless root is treated differently — a contract author who writes a root enum or array contract has **explicitly** asked for a non-object root, so there is no "library quirk to paper over" and silently wrapping it as an object would misadvertise the tool. So:
>
> | Input | Root `type` | Verdict |
> |---|---|---|
> | **Form A** (JSON Schema) | `"object"` | ensured/unchanged → **accept** |
> | **Form A** | **absent (typeless)** | **add** `type:"object"` (TS parity for `{oneOf:…}`) → **accept** |
> | **Form A** | explicit non-object (`"string"`, **`"array"`**, `"number"`, …) | **REJECT** (mirrors the TS throw) |
> | **Form B** object descriptor | (always `"object"`) | → **accept** |
> | **Form B** bare scalar contract (`string?`, `exact-integer?`) | maps to non-object `type` | **REJECT** (a tool argument schema must be an object) |
> | **Form B** root array contract (`(listof string?)`) | maps to `type:"array"` | **REJECT** (array root is non-object) |
> | **Form B** root enum contract (`(or/c "a" "b")`) | maps to a **typeless** `{enum:…}` | **REJECT** — see below |
>
> **The form-dependence is intentional and documented:** a *typeless* root from **Form A** gets `type:"object"` added (TS parity); a *typeless* root derived from **Form B** (a root enum contract) is **REJECTED**, not auto-wrapped. Rationale: a contract author selecting `(or/c "a" "b")` as the whole tool schema is unambiguously asking for a non-object root, whereas a typeless JSON Schema is the known Zod-discriminated-union case the TS add-rule exists to handle. Auto-wrapping a root enum into `{type:"object", enum:[…]}` would (a) advertise a nonsense schema and (b) make the handle accept any object (item 011 evaluates `enum` against the whole object, which never matches a string member, so it would reject *everything* — a silent total-failure). REJECT is the only safe choice. Pinned + tested (cases 1a/1b/1c in the Testing Strategy).

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
- **`promptArgumentsFromStandardSchema` analogue SHIPS here (decided).** It is a pure function of the wire schema with no extra dependency, and S6b needs it, so `normalized-schema-prompt-arguments` ships in this item and is tested (Part 6).

---

## Acceptance Criteria

- [ ] `mcp/core/util/schema.rkt` exists as `#lang racket/base` (or `#lang racket`) with an explicit, curated `provide` (no `(provide (all-defined-out))`). The `mcp/core/util/` collection directory is created by this item.
- [ ] The module exports `normalize-schema` (the entry point), the `normalized-schema` struct **predicate** + curated **accessors** (`normalized-schema-wire`, `normalized-schema-handle`, `normalized-schema-validate`), the `normalized-schema-prompt-arguments` helper, and the Form-B **object-descriptor surface** `object-schema/c` (+ its predicate). It does NOT re-export the M3 result API (callers `require` `provider.rkt` for `validation-ok?` etc.) and does NOT leak internal mapping helpers.
- [ ] **Form A — JSON Schema input → wire + handle.** `(normalize-schema (hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string")) 'required '("name")))` returns a `normalized-schema?` whose `normalized-schema-wire` has root `type:"object"` and whose `normalized-schema-handle` is a `compiled-validator?`. `(normalized-schema-validate ns (hasheq 'name "John"))` → `validation-ok?`; `(normalized-schema-validate ns (hasheq))` → `validation-errors?`.
- [ ] **Form A — root `type:"object"` invariant (all branches pinned).** A Form-A schema with NO root `type` gets `type:"object"` added (TS `{type:"object", ...result}` parity). A Form-A schema with root `type:"object"` is unchanged (modulo the ensured key). A Form-A schema with an explicit **non-object** root `type` is **rejected** at `normalize-schema` (`check-exn`, via an S1 error) — tested with **`(hasheq 'type "string")` AND a representative non-string non-object `(hasheq 'type "array")`** (case 1c), so the reject path is not string-specific.
- [ ] **Form B — root rule is form-dependent (pinned).** A bare scalar contract root (`string?`) → **reject**; a root **array** contract `(listof string?)` → **reject** (case 1a, array root non-object); a root **enum** contract `(or/c "a" "b")` → **reject** (case 1b — a typeless contract-derived root is NOT auto-wrapped, unlike a typeless Form-A input which gets `type:"object"` added). The form-dependence (Form-A typeless → wrap; Form-B typeless → reject) is documented in Decisions.
- [ ] **Form B — flat-contract object descriptor → wire + handle.** Normalizing the object descriptor `{name: string? (required), age: exact-integer? (optional)}` (in the chosen surface) yields a wire JSON Schema `equal?` (or structurally equal, per the pinned comparison) to `(hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string") 'age (hasheq 'type "integer")) 'required '("name"))`, and a handle that accepts `{name:"a", age:5}` and `{name:"a"}` and rejects `{age:5}` and `{name:5}`.
- [ ] **Form B — supported flat-contract scalar mappings.** Each of `string?`→`{type:"string"}`, `exact-integer?`→`{type:"integer"}`, `real?`/`number?`→`{type:"number"}`, `boolean?`→`{type:"boolean"}` maps as tabled (verified by inspecting the wire fragment a one-field object descriptor produces). `(listof string?)`→`{type:"array", items:{type:"string"}}`. A string/number/bool/null-literal `or/c` (e.g. `(or/c "red" "green")`) → `{enum:["red","green"]}`.
- [ ] **Dual-form equivalence (the headline criterion, queue-mandated).** A Form-B contract input and an *equivalent* Form-A JSON-Schema input (per "Equivalent" above) produce handles that **accept the same set of values and reject the same set of values**: for the agreed accept-set, BOTH handles return `validation-ok?`; for the agreed reject-set, BOTH return `validation-errors?`. **AND** the two emitted **wire JSON Schemas match** (`equal?` / structural equality, after root-`type:"object"` normalization). Assert both halves (same verdicts + same wire) explicitly. This is the queue's key testable.
- [ ] **Contract with no JSON-Schema equivalent → rejected (edge case).** A higher-order/dependent/opaque contract — e.g. `(-> string? string?)`, an `(->i …)`, a `struct/c`, or a bare opaque predicate like `even?` used as a field contract — causes `normalize-schema` to **raise a clear S1 error** (`check-exn`), NOT to silently produce `{}` (which would accept everything) and NOT to crash with a raw Racket contract/internal error. The error message names the un-mappable contract/field.
- [ ] **Optional vs required fields (edge case).** In a Form-B object descriptor, a field marked required appears in the wire `required` array (as a **string**); a field marked optional does NOT. The handle then: rejects an object missing a required field; accepts an object missing an optional field; and (per item 011 `properties` semantics) validates an optional field's type *when present* (so `{name:"a", age:"x"}` rejects on `age`'s type even though `age` is optional). Pin all three.
- [ ] **Nested object descriptors are SUPPORTED (decided); non-flat Racket contracts are always rejected.** A field whose contract is *itself* an `object-schema/c` descriptor maps recursively to a nested `{type:"object", properties:…, required:…}` wire fragment (arbitrary depth — the mapper recurses), and the handle validates the nested object + locates a nested failure's path (e.g. a wrong-typed inner field yields a `validation-error` whose `path` names the outer then inner field). A `(listof <object-schema/c>)` field maps to `items` of an object sub-schema. A genuinely non-flat *Racket* contract (higher-order, e.g. `(-> string? string?)`, `(listof (-> any/c any/c))`, an `(->i …)`, a `struct/c`) is **always rejected** (`check-exn`) as "no JSON-Schema equivalent". The boundary is documented: a nested `object-schema/c` is a structured **input** this module recurses into; a higher-order **Racket contract** is always rejected.
- [ ] **Empty schema → `validation-ok`, NOT an empty-`validation-errors` crash (edge case, issue #7).** Form A `(hasheq)` (empty JSON Schema) normalizes to a wire schema with root `type:"object"` added; its handle **accepts every object** — pin `(validation-ok? (normalized-schema-validate ns (hasheq 'anything 1)))` → `#t` AND `(validation-ok? (normalized-schema-validate ns (hasheq)))` → `#t`. A Form-B empty object descriptor `(object-schema/c (hash) #:required '())` likewise normalizes to `{type:"object", properties:{}, required:[]}` (or `{type:"object"}` — pin which) and `(validation-ok? (normalized-schema-validate ns (hasheq)))` → `#t` (case 9). **Explicitly assert `validation-ok?` (not merely "no exn")**: item 010's `validation-errors` guard RAISES on an empty error list, so a "build errors then wrap" bug would surface here as a crash or a malformed result — asserting `validation-ok?` falsifies that bug.
- [ ] **Form-detection precedence + symbol-key requirement (issue #6).** An `immutable?` `hasheq` with symbol keys → Form A. The `object-schema/c` struct → Form B. A bare flat contract → Form B-bare. A **string-keyed / `equal?`-keyed / mutable hash** (e.g. `(hash "type" "object")`) is **out of contract → rejected** (`check-exn`, case 8), NOT silently routed into the symbol-keyed provider (which would mis-validate every `required`/`properties` lookup — the silent-total-failure bug). A non-hash, non-descriptor, non-contract input (`42`, `"x"`) → rejected.
- [ ] **Deferred keyword in a Form-A input passes through (issue #3).** `(normalize-schema (hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string" 'minLength 3))))` → (a) the **wire schema retains `'minLength 3`** verbatim (`(hash-ref (hash-ref (normalized-schema-wire ns) 'properties) 'name)` still has `'minLength`); (b) the handle **accepts** `{name:"x"}` (deferred, not enforced — item 011 policy); (c) the deferred keyword is recorded in the default provider's `provider-warnings-for` for that handle (proving the handle was compiled through the provider). Case 3.
- [ ] **`and/c` is rejected (decided — supersedes any drop-and-record).** A field contract using `(and/c …)` — e.g. `(and/c string? immutable?)` or `(and/c string? (string-len/c 10))` — causes `normalize-schema` to **raise a clear S1 error** (`check-exn`) naming the field, NOT to map-the-type-and-drop-the-constraint. Pinned by case 7.
- [ ] **`or/c` arm rules (decided).** An all-literal `or/c` → `enum` (single-arm and duplicate-member accepted, duplicates de-duplicated in the emitted `enum`); a **mixed** literal+predicate `(or/c "a" string?)` and an **all-predicate** `(or/c string? number?)` → **rejected** (`check-exn`). Pinned by case 5 (mixed) + the all-predicate row.
- [ ] **`exact-integer?` only for `integer` (decided, S5 self-consistency).** An `integer` field maps from `exact-integer?` (NOT `integer?`). The derived handle **rejects `5.0`** for such a field (pinning that the contract form and its own derived handle agree — `integer?` would have advertised `5.0` as valid while the handle, using item 011's `exact-integer?`, rejects it). `integer?` as a field contract is **rejected** as un-mappable. Pinned by case 6.
- [ ] **Provider injection + default.** `normalize-schema` accepts `#:provider`. With no `#:provider`, it defaults to `(make-racket-native-provider)` (item 011). When a custom provider is supplied, the handle is compiled through THAT provider (verified with a stub provider OR by observing the default's `provider-warnings-for` for a deferred keyword routed through the wire schema). The provider is the M3 port — the module never validates outside it.
- [ ] **Delegation parity — the handle == `(provider-compile P (wire-of X))`, on the POST-normalization wire (issue #2).** For an input `X`, the normalized handle agrees, value-for-value, with a provider compiled **directly on `(normalized-schema-wire (normalize-schema X))`** (the *normalized* wire, NOT the raw input). Pinned for **three** `X`: (a) the object-rooted Form-A `J`; (b) a **typeless Form-A** input `(hasheq 'properties (hasheq 'name (hasheq 'type "string")))` (no root `type`) — so the parity case actually exercises the normalize-THEN-compile path the object-rooted case can pass accidentally (case 2); (c) the Form-B contract `C` — **contract-form self-delegation**: `(handle-of C)` agrees with `(provider-compile (make-racket-native-provider) (wire-of C))` over the full sample set (case 2b). This pins that the util compiles the *derived* wire, not the raw contract, and never runs a parallel validator.
- [ ] **`normalized-schema-validate` sugar.** `(normalized-schema-validate ns v)` equals `(validate (normalized-schema-handle ns) v)` for representative `v` (a convenience that does not introduce a second validation path).
- [ ] **Prompt-arguments helper (ships here).** `normalized-schema-prompt-arguments` over a wire schema with `properties {name, age}` and `required ["name"]` returns entries naming each property with its required flag (`name`→required, `age`→optional), mirroring TS `promptArgumentsFromStandardSchema`.
- [ ] **Imports = S1 + M3 ONLY.** The module requires only `mcp/core/main.rkt`, `mcp/core/validators/provider.rkt`, `mcp/core/validators/from-json-schema.rkt`, and `racket/contract` (+ `json` if `(json-null)` is used directly). It requires NO transport/engine/role/subprocess/socket module and NOT `net/url`. **Verified by a restricted-namespace load test** rooted at `schema.rkt` itself: a fresh `(make-base-namespace)` requiring it and walking `module->imports` transitively shows EMPTY intersection with the banned set (`racket/system racket/tcp racket/udp net/url net/http-client net/sendurl racket/sandbox racket/port`).
- [ ] `raco test mcp/core/util/` passes (exit 0) — module + new test compile and run cleanly within the new collection.
- [ ] `raco make mcp/core/util/schema.rkt` exits 0 (compiles clean, no warnings about missing/non-portable modules).
- [ ] Parity-matrix discipline: the `util/schema` row advances to `partial` (the dual-form normalization now exists; full conformance lands with items 017/018 + S9). Update `docs/aide/progress.md` per the Completion Reminder — flip the `util/schema.rkt` deliverable line AND check the Stage-S2 **schema-normalization** acceptance box (this item owns it).

---

## Implementation Steps

1. **Re-read the framing sources for shape + role:** `typescript-sdk/packages/core/src/util/standardSchema.ts` (the `standardSchemaToJsonSchema` root-`type:"object"` rule + throw-on-non-object; `validateStandardSchema` result shape; `promptArgumentsFromStandardSchema` extraction) and `util/schema.ts` (the thin schema→result role). Re-read item 011's `from-json-schema.rkt` public surface (`make-racket-native-provider`, `provider-warnings-for`) and item 010's `provider.rkt` (`provider-compile`, `validate`, `compiled-validator?`, the result API) so you require, not redefine, M3.
2. **The Form-B object-descriptor surface + form-detection rule are PINNED** (do not re-decide): surface = `(object-schema/c field-hash #:required req-list)` (a module-defined `struct`, with `#:required` validated against `field-hash` keys at construction — raises on an absent field); form detection = `(and (hash? x) (immutable? x) (hash-eq? x))` → Form A, the `object-schema/c` struct → Form B, a bare flat contract → Form B-bare (mapped then root-rule applied → bare scalar/array/enum root rejects), anything else → raise.
3. **Write `mcp/core/util/schema.rkt`.** Use `#lang racket/base`. In order:
   - `(require racket/contract racket/list "../main.rkt" "../validators/provider.rkt" "../validators/from-json-schema.rkt")` plus `json` if `(json-null)` is needed.
   - A module-level **doc block** recording: the role-port framing (Standard-Schema analogue, input forms net-new per §8); the two input forms; the **contract→JSON-Schema mapping table + its documented limits** (flat-only; `and/c`/mixed-`or/c`/`integer?` rejected; no `format` from contracts; reject-on-un-mappable); the **form-dependent root rule**; the **single-delegation-path** directive; the **deferred-keyword pass-through** for Form A; the **form-detection guard** (`hash-eq?`/`immutable?`/symbol-keys); and the symbol/string field-name boundary (wire `properties` keys = symbols, wire `required` members = strings — matching item 011).
   - The **`normalized-schema` struct** (`wire`, `handle`) with curated accessors only.
   - The **Form-A path** `(json-schema->wire schema)`: ensure root `type:"object"` (add if absent; reject if explicit non-object); return the wire schema.
   - The **Form-B mapping** `(descriptor->wire descriptor)`: walk the object descriptor's fields, mapping each flat contract via a `(flat-contract->fragment c)` cond over the supported table — recursing into a nested `object-schema/c` field (→ nested `{type:"object", …}`) and into `(listof <flat-or-descriptor>)` (→ `items`); collect `properties` (symbol-keyed) + `required` (string list of required fields); **reject (via `make-protocol-error`/`make-mcp-error`) any un-mappable contract — `and/c`, mixed/all-predicate `or/c`, `integer?`, higher-order/dependent/struct contracts, bare opaque predicates** — naming the offending field. `or/c` arms are checked all-literal (else reject) and de-duplicated for `enum`. **Recognition is by identity / constructor-match against the fixed supported table** (e.g. `eq?`/predicate-identity for `string?`/`exact-integer?`/`boolean?`, `object-schema/c?` for descriptors, the `or/c`/`listof` constructor) — NOT by decomposing a compiled `or/c`'s arms or parsing contract-name strings (a compiled `or/c` exposes no structured arm-decomposition API, so the enum-literal/arm checks operate on the descriptor surface that built it, not on the opaque compiled contract).
   - **`normalize-schema`** `(input #:provider [provider (make-racket-native-provider)])`: detect the form, produce the wire schema (Form A or Form B), `(provider-compile provider wire)` for the handle, construct + return the `normalized-schema`.
   - `normalized-schema-validate` sugar; `normalized-schema-prompt-arguments` (ships here); the explicit `(provide …)` block (entry point + struct predicate/accessors + `object-schema/c` + its predicate; NOT internal mapping helpers; NOT a re-export of the M3 result API).
4. **Write the test** `mcp/core/util/test/schema-test.rkt` (see Testing Strategy). Cover both forms (A + B), the dual-form equivalence (same accepts/rejects + same wire), the **delegation-parity cases 2 + 2b** (compile direct on the *post-normalization* wire, incl. a typeless Form-A input + contract-form self-delegation), the root-`type:"object"` invariant (Form-A add / unchanged / reject-non-object with both `"string"` and `"array"`; Form-B bare scalar/array/enum-root reject — cases 1a/1b/1c), every supported scalar/array/enum mapping + the `or/c` arm rules, optional-vs-required, the un-mappable-contract rejects (`and/c` case 7, mixed `or/c` case 5, `integer?`/`5.0` case 6, higher-order), nested object descriptors + located paths, the **empty-schema `validation-ok?` assertion** (case 9), the **Form-A deferred-keyword pass-through** (case 3), the **string-keyed-hash reject** (case 8), the **`object-schema/c` absent-required reject** (case 4), provider injection + default, the `validate` sugar, the prompt-arguments helper, and the restricted-load portability sub-test (reuse the item-008/010/011 walk helper; entry point = `schema.rkt`; confirm no `(module+ test …)` in `schema.rkt`). All nine reviewer-mandated cases (Part 8 table) MUST be present.
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
- **Non-object root rejected — two reps (case 1c):** `(check-exn exn:fail? (lambda () (normalize-schema (hasheq 'type "string"))))` AND `(check-exn exn:fail? (lambda () (normalize-schema (hasheq 'type "array"))))` — the reject path is not string-specific (mirrors the TS throw).
- **Empty schema → `validation-ok` (case 9, issue #7):** `(define ns (normalize-schema (hasheq)))` — wire root `type` is `"object"`; `(check-true (validation-ok? (normalized-schema-validate ns (hasheq 'anything 1))))`; `(check-true (validation-ok? (normalized-schema-validate ns (hasheq))))` — assert **`validation-ok?`**, not merely no-exn (an empty `validation-errors` would crash item 010's guard).
- **Deferred keyword passes through (case 3, issue #3):** `(define ns (normalize-schema (hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string" 'minLength 3)))))` — `(check-true (hash-has-key? (hash-ref (hash-ref (wire ns) 'properties) 'name) 'minLength))` (wire retains `minLength`); `(check-true (ok? ns (hasheq 'name "x")))` (deferred, not enforced — `"x"` is < 3 chars yet accepts). If the default provider is captured, `(memq 'minLength (provider-warnings-for the-provider (normalized-schema-handle ns)))` → truthy (compiled through the provider).
- **String-keyed / mutable hash rejected (case 8, issue #6):** `(check-exn exn:fail? (lambda () (normalize-schema (hash "type" "object"))))` — a string-keyed `equal?`-hash is out of contract (NOT silently routed into the symbol-keyed provider). Also `(check-exn exn:fail? (lambda () (normalize-schema 42)))` and `(… "x")` (non-hash, non-descriptor, non-contract).

### Part 2 — Form B (flat-contract object descriptor)

- **Object descriptor → wire:** build the descriptor `{name: string? (required), age: exact-integer? (optional)}` in the chosen surface; assert `(wire ns)` equals (or is structurally equal to) `(hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string") 'age (hasheq 'type "integer")) 'required '("name"))`. **`required` members are STRINGS, `properties` keys are SYMBOLS** — assert both explicitly.
- **Scalar mappings:** for a one-field descriptor, assert the produced `properties` fragment for each of `string?`→`{type:"string"}`, `exact-integer?`→`{type:"integer"}`, `real?`/`number?`→`{type:"number"}`, `boolean?`→`{type:"boolean"}`.
- **Array mapping:** `(listof string?)` → `{type:"array", items:{type:"string"}}` (assert the `items` sub-fragment).
- **Enum mapping (all-literal only):** `(or/c "red" "green")` → `{enum:["red","green"]}`; a multi-type-literal `(or/c "x" 42 #t)` → `{enum:["x",42,#t]}` (literal members carried through; assert membership). A null-literal `(or/c "x" (json-null))` carries `(json-null)` as a member. Single-arm `(or/c "a")` → `{enum:["a"]}`; duplicate `(or/c "a" "a")` → `{enum:["a"]}` (de-dup). **Mixed `(or/c "a" string?)` and all-predicate `(or/c string? number?)` → rejected** (Part 4).
- **Optional vs required:** the handle rejects `{age:5}` (missing required `name`); accepts `{name:"a"}` (optional `age` absent); rejects `{name:"a", age:"x"}` (optional `age` present-but-wrong-type — item 011 `properties` validates present optionals).

### Part 3 — Dual-form equivalence (the headline)

- Build `ns-contract` from the Form-B descriptor `{name: string? (required), age: exact-integer? (optional)}` and `ns-json` from the equivalent Form-A `(hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string") 'age (hasheq 'type "integer")) 'required '("name"))`.
- **Same accepts:** `(hasheq 'name "a" 'age 5)`, `(hasheq 'name "a")` → BOTH `ok?`.
- **Same rejects:** `(hasheq 'age 5)` (no name), `(hasheq 'name 5)` (wrong-type name), `(hasheq 'name "a" 'age "x")` (wrong-type age) → BOTH `bad?`.
- **Same wire:** `(equal? (wire ns-contract) (wire ns-json))` → `#t` (or structural equality per the pinned comparison — assert field-by-field if hash-ordering makes `equal?` brittle; pin which).
- Run all three assertions via the `same-verdicts` helper + an explicit wire-equality check.

**Delegation parity (issue #2) — compile DIRECT on the POST-normalization wire:**
- **Case 2 — typeless Form-A input (exercises normalize-THEN-compile):** `(define P (hasheq 'properties (hasheq 'name (hasheq 'type "string"))))` (no root `type`); `(define nsP (normalize-schema P))`; `(define direct (provider-compile (make-racket-native-provider) (wire nsP)))` — compile DIRECT on `(wire nsP)` (the *normalized* wire, which has `type:"object"` added), NOT on raw `P`. Assert `(handle-of nsP)` and `direct` agree on `(hasheq 'name "x")` (both ok) and `(hasheq)` (both reject on missing — once `type:"object"` is present `properties` is evaluated; this is the case the object-rooted `J` passes accidentally).
- **Case 2b — contract-form self-delegation:** `(define direct-c (provider-compile (make-racket-native-provider) (wire ns-contract)))`; over the full Part-3 sample set (accepts + rejects), assert `(validation-ok? (validate (normalized-schema-handle ns-contract) v))` `=` `(validation-ok? (validate direct-c v))` for every `v`. Proves the contract handle is exactly the provider compiled on the *derived* wire (no parallel contract validator).

### Part 4 — Edge cases

- **No-JSON-Schema-equivalent contract → reject:** `(check-exn exn:fail? (lambda () (normalize-schema (object-schema/c (hash 'x (-> string? string?)) #:required '(x))))) `; same for an `(->i …)`, a `struct/c`, a bare opaque predicate `even?`, and `integer?` (the inexact-integer trap) as a field contract. Assert the error is an S1 error type (not a raw Racket contract error) and (optionally) that its message names the offending field/contract.
- **Nested object descriptors (supported):** a field whose contract is a nested `object-schema/c` produces a `{type:"object", properties:…, required:…}` wire fragment and the handle validates the nested object; a wrong-typed inner field yields a located path naming outer then inner (e.g. `'("outer" "inner")`). A `(listof <object-schema/c>)` field → `items` of an object sub-schema; a bad element's path includes the integer index + inner field (e.g. `'("items" 0 "id")`). A non-flat *Racket* contract (`(-> string? string?)`, `(listof (-> any/c any/c))`) is **always rejected** (`check-exn`).
- **`and/c` rejected (decided):** `(check-exn exn:fail? (lambda () (normalize-schema (object-schema/c (hash 'x (and/c string? immutable?)) #:required '(x)))))` (case 7) — `and/c` has no clean single-fragment equivalent, so it raises (NOT drop-and-record).
- **`or/c` arm rules:** all-literal `(or/c "red" "green")` → `{enum:["red","green"]}`; single-arm `(or/c "a")` → `{enum:["a"]}`; duplicate `(or/c "a" "a")` → `{enum:["a"]}` (de-dup); **mixed** `(or/c "a" string?)` → `(check-exn …)` (case 5, not a clean enum); **all-predicate** `(or/c string? number?)` → `(check-exn …)`.
- **`exact-integer?` self-consistency (case 6):** an `exact-integer?` field's handle **rejects `5.0`** — `(bad? ns-with-int-field (hasheq 'n 5.0))` → `#t` (and accepts `(hasheq 'n 5)`). Documents why `integer?` is rejected (it would accept `5.0` the handle rejects).
- **`object-schema/c` absent-required (case 4):** `(check-exn exn:fail? (lambda () (object-schema/c (hash 'name string?) #:required '(missing))))` — raises **at construction**, naming the absent field.
- **Empty Form-B descriptor (case 9):** `(object-schema/c (hash) #:required '())` → wire `{type:"object", properties:{}, required:[]}` (or `{type:"object"}` — pin); `(check-true (validation-ok? (normalized-schema-validate ns (hasheq))))` AND `(check-true (validation-ok? (normalized-schema-validate ns (hasheq 'anything 1))))` — assert **`validation-ok?`** explicitly (not merely no-exn), since an empty `validation-errors` would crash item 010's guard.

### Part 5 — Provider injection + default + sugar

- **Default provider:** with no `#:provider`, `(normalize-schema (hasheq 'type "object"))` compiles through `(make-racket-native-provider)` — `(compiled-validator? (normalized-schema-handle ns))` → `#t`.
- **Custom provider:** pass an explicit `(make-racket-native-provider)` (or a trivial stub provider satisfying `gen:json-schema-validator-provider`) via `#:provider`; assert the handle came from THAT provider. With the default provider, route a deferred keyword through a Form-A wire schema (`(hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string" 'minLength 3)))`) and assert `(provider-warnings-for the-provider (normalized-schema-handle ns))` records `'minLength` — proving the module compiled through the provider (not an ad-hoc checker).
- **`normalized-schema-validate` sugar:** `(equal? (normalized-schema-validate ns v) (validate (normalized-schema-handle ns) v))` for an ok value and a bad value (structural equality on the result — or assert both are `validation-ok?` / both `validation-errors?`).

### Part 6 — prompt-arguments helper (ships here)

- For a wire schema with `properties {name, age}` + `required ["name"]`, `(normalized-schema-prompt-arguments ns)` returns two entries; `name` is required, `age` is not; descriptions (if the wire `properties` carry `description`) are surfaced. Mirrors TS `promptArgumentsFromStandardSchema`.

### Part 7 — restricted-namespace portability (S1 + M3 only)

Reuse the transitive `module->imports` walk from item 008/010/011 — fresh `(make-base-namespace)`, `namespace-require` `schema.rkt`, walk imports threading `current-load-relative-directory` per module dir, assert the FULL banned set (`racket/system racket/tcp racket/udp net/url net/http-client net/sendurl racket/sandbox racket/port`) has empty intersection with the visited set. **Entry point is `schema.rkt` ITSELF.** This proves the schema util (and, transitively, the M3 modules it requires) is portability-clean. **Specifically guards** that the contract→JSON-Schema mapping did not reach for `net/url` (banned) for any format handling. **Non-vacuity (drift):** temporarily inject `(require racket/tcp)` into a scratch copy, confirm the walk FAILS naming `racket/tcp`, then revert. (Scope note inherited from item 008: `module->imports` does not see into `(module+ test …)` submodules — proves the module's own import graph, not a test submodule's.)

> **`schema.rkt` MUST NOT define a `(module+ test …)` submodule** — tests live in the separate `test/schema-test.rkt` file (consistent with items 010/011). This keeps the portability walk (which does not see into `module+ test`) a faithful proof of the module's own import graph, and keeps the test's heavier requires (`rackunit`, `racket/set`, `racket/path`) out of `schema.rkt`'s closure.

### Part 8 — reviewer-mandated regression cases (consolidated)

Each row is a single falsifiable assertion; they back-reference the issue they close. (Several are also folded into Parts 1–7 above; this table is the checklist.)

| # | Input | Expected |
|---|---|---|
| 1a | `(normalize-schema (listof string?))` | **raises** (array root is non-object) |
| 1b | `(normalize-schema (or/c "a" "b"))` (root enum contract) | **raises** (typeless contract-derived root is NOT auto-wrapped — decided) |
| 1c | `(normalize-schema (hasheq 'type "array"))` | **raises** (non-object JSON-Schema root; not string-specific) |
| 2 | `direct = (provider-compile (make-racket-native-provider) (wire-of P))` for `P = (hasheq 'properties (hasheq 'name (hasheq 'type "string")))` | `direct` and `(handle-of P)` agree on `{name:"x"}` and `{}` (normalize-THEN-compile path) |
| 2b | `(handle-of C)` vs `(provider-compile (make-racket-native-provider) (wire-of C))` for the Part-3 `C` | agree on the full sample set (contract-form self-delegation) |
| 3 | `J = (hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string" 'minLength 3)))` | `(hash-ref (hash-ref (wire-of J) 'properties) 'name)` still has `'minLength 3`; `(ok? J (hasheq 'name "x"))` → `#t` (deferred, not enforced) |
| 4 | `(object-schema/c (hash 'name string?) #:required '(missing))` | **raises at construction** (required names absent field) |
| 5 | `(normalize-schema (object-schema/c (hash 'x (or/c "a" string?)) #:required '(x)))` | **raises** (mixed literal/predicate `or/c` is not a clean enum) |
| 6 | an `exact-integer?` field handle on `5.0` | **rejects** (pins `exact-integer?`; `integer?` would have accepted `5.0` the handle rejects) |
| 7 | `(normalize-schema (object-schema/c (hash 'x (and/c string? immutable?)) #:required '(x)))` | **raises** (`and/c` not in supported table) |
| 8 | `(normalize-schema (hash "type" "object"))` (string-keyed, `equal?`-hash) | **raises** (out of contract — NOT silently mis-validated) |
| 9 | `(validation-ok? (validate (handle-of (object-schema/c (hash) #:required '())) (hasheq)))` | `#t` (empty schema → ok, NOT an empty-`validation-errors` crash) |

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

The **design decisions below are PINNED at spec time** (the reviewer required real choices, not options). The **post-build outcome** (require list as built, exact check count, drift result, REPL transcript) is *to be updated during implementation*.

**(a) Form-B object-descriptor surface = `(object-schema/c field-hash #:required req-list)`** — a module-defined `struct`, `field-hash` = `hasheq` of `field-symbol → flat-contract`, `req-list` = list of required field symbols. Chosen over an assoc-list because the field→contract map and the required-set are explicit and introspectable. **`#:required` is validated at construction**: naming a field absent from `field-hash` **raises** (case 4) — a required-but-undeclared field is a programmer error caught earliest.

**(b) Form detection = `(and (hash? x) (immutable? x) (hash-eq? x))` → Form A; `object-schema/c?` → Form B; `flat-contract?`/procedure → Form B-bare; else raise.** The stricter `hash-eq?`/`immutable?` guard (NOT bare `hash?`) is deliberate: a string-keyed / `equal?`-keyed / mutable hash routed into item 011's symbol-keyed provider mis-validates *every* `required`/`properties` lookup (the silent-total-failure bug item 011 warns of), so such input is **out of contract → rejected** (case 8). JSON-Schema input MUST be what `read-json`/`string->jsexpr` produce (an immutable symbol-keyed `hasheq`).

**(c) Root `type:"object"` rule is DELIBERATELY FORM-DEPENDENT.** Form-A typeless root → **add** `type:"object"` (TS `{type:"object", ...result}` parity for the Zod `{oneOf}` case). Form-A explicit non-object root → **reject** (TS throw parity; tested with both `"string"` and `"array"`, case 1c). Form-B bare scalar/array root → **reject** (cases 1a + bare scalar). Form-B root **enum** contract → **reject** (case 1b), NOT auto-wrapped: a contract author choosing `(or/c "a" "b")` as the whole schema explicitly asked for a non-object root, and auto-wrapping to `{type:"object", enum:[…]}` would advertise nonsense and make item 011 reject every object (it evaluates `enum` against the whole object). The form-dependence is acknowledged as intentional, not an inconsistency.

**(d) `exact-integer?` only for `integer`; `integer?` is rejected (S5 self-consistency).** Item 011's `json-integer?` is `exact-integer?` (`5.0` is a JSON *number*, not *integer*). Mapping `integer?` would advertise `5.0` as valid while the derived handle rejects it — a self-inconsistency. So only `exact-integer?` maps; `integer?` is un-mappable → reject. Pinned by the `5.0`-rejects test (case 6).

**(e) `and/c` is REJECTED; mixed/all-predicate `or/c` is REJECTED (supersedes any drop-and-record middle path).** `and/c`'s non-`type` conjuncts are exactly item-011 *deferred* constraint keywords; mapping the type and dropping the constraint would advertise a contract *narrower* than the author wrote. So `and/c` raises (case 7). An `or/c` with any non-literal arm (mixed `(or/c "a" string?)` case 5, or all-predicate `(or/c string? number?)`) has no clean `enum` → raise. Only all-literal `or/c` → `enum` (single-arm OK; duplicates de-duplicated). A length-bounded string is expressed via a Form-A JSON Schema instead (where the deferred keyword round-trips in the wire schema for a future provider).

**(f) Deferred keywords in Form-A input pass through untouched (issue #3).** The wire schema retains the keyword verbatim (advertised as-is); the handle's behaviour is exactly item 011's (ignore-with-warning, recorded in `provider-warnings-for`). No stripping/rewriting/rejecting. Pinned (case 3).

**(g) Nested `object-schema/c` descriptors are SUPPORTED (recursive, arbitrary depth); higher-order Racket contracts are always rejected.** A nested descriptor field → nested `{type:"object", …}` with located paths; `(listof <descriptor>)` → `items` of an object sub-schema. A `(-> …)`/`(->i …)`/`struct/c`/`(listof (-> …))` is always rejected.

**(h) `normalized-schema-prompt-arguments` ships here** (pure function of the wire schema, no extra dep, S6b needs it) — tested in Part 6.

**(i) No `(module+ test …)` in `schema.rkt`** — tests live in `test/schema-test.rkt` (keeps the portability walk faithful and the test-only requires out of the module's closure).

**(j) Fresh-provider-per-call default (perf note).** `normalize-schema` defaults `#:provider` to a fresh `(make-racket-native-provider)` per call. This is correct (the provider is cheap, holds only a weak handle→warnings map) but means S6b, if it normalizes once per tool registration, creates one provider per tool. **Recommendation for S6b:** pass a single shared `#:provider` across all `normalize-schema` calls in a registration batch if provider allocation ever shows up in a profile. Not a correctness issue (item 011's warnings map is per-compile-keyed and weak, so a shared provider stays correct across many schemas — N1/N2). Documented so S6b has the knob.

*(Post-build, also record: the wire-schema comparison used in the dual-form test (`equal?` vs field-by-field structural — pin which survived hash-ordering); the require list as built with each import's justification; and the restricted-load drift result.)*

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
- [ ] **Form A root invariant verified (both reps):** no-root-`type` → `type:"object"` added; object root → unchanged; non-object root rejected for BOTH `{type:"string"}` AND `{type:"array"}` (case 1c).
- [ ] **Form B root rule verified (form-dependent):** bare scalar root → reject; root `(listof string?)` → reject (case 1a); root `(or/c "a" "b")` → reject (case 1b, NOT auto-wrapped).
- [ ] **Form B object descriptor verified:** `(object-schema/c (hash 'name string? 'age exact-integer?) #:required '(name))` → wire equals the equivalent JSON Schema; `properties` keys are symbols, `required` members are strings.
- [ ] **Form B scalar/array/enum mappings verified:** string/integer/number/boolean; `(listof string?)`→array+items; all-literal `(or/c "red" "green")`→enum; single-arm + duplicate de-dup; **mixed `(or/c "a" string?)` rejected (case 5)**; all-predicate `(or/c string? number?)` rejected.
- [ ] **`exact-integer?` self-consistency verified (case 6):** an `exact-integer?` field handle rejects `5.0`, accepts `5`; `integer?` as a field contract is rejected.
- [ ] **Dual-form equivalence verified (headline):** contract input and equivalent JSON-Schema input accept the same value set + reject the same value set, AND emit the same wire schema.
- [ ] **Delegation parity verified (case 2 + 2b):** handle agrees with `(provider-compile P (wire-of X))` on a **typeless Form-A** input (normalize-THEN-compile) AND on the **contract form** (self-delegation over the full sample set).
- [ ] **Deferred keyword pass-through verified (case 3):** Form-A `{...minLength:3...}` → wire retains `minLength`; handle accepts a short string; `provider-warnings-for` records `'minLength`.
- [ ] **No-equivalent contract rejected:** `(-> string? string?)` / `(->i …)` / `struct/c` / bare `even?` / `integer?` as a field contract → `normalize-schema` raises an S1 error (not silent `{}`, not a raw contract crash).
- [ ] **`and/c` rejected: raises (case 7):** `(and/c string? immutable?)` field → raises.
- [ ] **Optional vs required verified:** required field in wire `required` (string); optional absent OK; optional-present-wrong-type rejects.
- [ ] **`object-schema/c` absent-required rejected (case 4):** `#:required '(missing)` naming an undeclared field → raises at construction.
- [ ] **Nested object descriptors verified:** nested `object-schema/c` field → nested `{type:"object",…}`, located path on inner failure; `(listof <descriptor>)` → object `items`; higher-order Racket contract always rejected.
- [ ] **Empty schema → `validation-ok?` verified (case 9):** Form-A `(hasheq)` AND Form-B empty descriptor each yield `validation-ok?` (asserted explicitly, not just no-exn) on `(hasheq)` and `(hasheq 'x 1)`.
- [ ] **String-keyed hash rejected (case 8):** `(hash "type" "object")` (string-keyed `equal?`-hash) → `normalize-schema` raises (out of contract, not silently mis-validated); `42`/`"x"` also raise.
- [ ] **Provider injection + default verified:** default `make-racket-native-provider`; custom/stub provider routed; deferred-keyword `provider-warnings-for` proves compile-through-provider.
- [ ] **`normalized-schema-validate` sugar verified:** equals `(validate (normalized-schema-handle ns) v)`.
- [ ] **Prompt-arguments helper verified (ships here):** entries per property with required flags; mirrors TS.
- [ ] **No `(module+ test …)` in `schema.rkt` confirmed:** tests live in `test/schema-test.rkt`.
- [ ] **Portability verified:** the restricted-load test passes (no subprocess/socket — incl. NO `net/url` — in the transitive import closure of `schema.rkt`).
- [ ] **Drift / non-vacuity check (portability):** temporarily add `(require racket/tcp)` to a scratch copy, confirm the load test FAILS naming `racket/tcp`, then revert.
- [ ] **Health checks pass:** N/A (no running service).

### Expected Outcomes

Concrete, verifiable:

- The module **exports** `normalize-schema` (entry point), the `normalized-schema` struct predicate + curated accessors (`normalized-schema-wire`, `normalized-schema-handle`, `normalized-schema-validate`), the `normalized-schema-prompt-arguments` helper, and the Form-B object-descriptor surface `object-schema/c` (+ predicate). It does NOT re-export the M3 result API and does NOT leak internal mapping helpers. `(normalized-schema? (normalize-schema (hasheq 'type "object")))` → `#t`.
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
- [ ] Form A root invariant (both reps): no-type→added; object→unchanged; non-object→rejected for {type:string} AND {type:array} (case 1c)
- [ ] Form B root rule (form-dependent): bare scalar→reject; (listof string?)→reject (1a); (or/c "a" "b")→reject (1b)
- [ ] Form B object descriptor verified: wire equals equivalent JSON Schema; properties symbol-keyed, required string members
- [ ] Form B scalar/array/enum mappings verified; mixed/all-predicate or/c rejected (case 5)
- [ ] exact-integer? self-consistency: int field rejects 5.0, accepts 5; integer? rejected (case 6)
- [ ] Dual-form equivalence verified (headline): same accepts + same rejects + same wire
- [ ] Delegation parity verified: handle == (provider-compile P (wire-of X)) on typeless Form-A (case 2) + contract self-delegation (case 2b)
- [ ] Deferred keyword pass-through (case 3): wire retains minLength; handle accepts short string; provider-warnings-for records 'minLength
- [ ] No-equivalent contract rejected: higher-order/dependent/opaque/integer? → S1 error (not silent {})
- [ ] and/c rejected: raises (case 7): (and/c string? immutable?) field → raises
- [ ] Optional vs required verified
- [ ] object-schema/c absent-required rejected at construction (case 4)
- [ ] Nested object descriptors verified: nested {type:object,…} + located path; (listof descriptor)→items; higher-order always rejected
- [ ] Empty schema → validation-ok? (case 9): Form-A {} + Form-B empty descriptor each validation-ok? on {} and {x:1} (asserted, not just no-exn)
- [ ] String-keyed hash rejected (case 8): (hash "type" "object") → raises; 42/"x" → raise
- [ ] Provider injection + default verified (provider-warnings-for proves compile-through-provider)
- [ ] normalized-schema-validate sugar verified
- [ ] prompt-arguments helper verified (ships here)
- [ ] No (module+ test …) in schema.rkt confirmed
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
