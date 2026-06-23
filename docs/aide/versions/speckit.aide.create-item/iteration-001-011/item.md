# Work Item 011: Default Racket-native provider — `from-json-schema` (M3)

> **Queue:** `docs/aide/queue/queue-002.md` — Item 011
> **Stage:** S2 (Foundation: validators, schema, shared utilities — L0 part 2)
> **Module:** M3 (Validators) — the **default provider** sub-unit (`mcp/core/validators/from-json-schema.rkt`); it implements the item-010 port (`mcp/core/validators/provider.rkt`). The schema util that consumes it is item 012.
> **Source vision:** `docs/aide/vision.md` §4.5 (pluggable JSON-Schema validator; **Ajv/cfWorker collapse to one Racket-native provider**), §8 (Zod/Standard-Schema-lib + cfWorker **exclusions**), §6 (Portability NFR — core loads without subprocess/socket; **Minimal-deps NFR** — default = hand-rolled subset unless a vetted lib is adopted).
> **Source roadmap:** `docs/aide/roadmap.md` Stage S2 → Deliverables line (`mcp/core/validators/from-json-schema.rkt` — Racket-native default; keywords `type`/`properties`/`required`/`enum`/`items`/`format`) + Testing/validation criteria (keyword coverage cross-checked vs TS Ajv baseline; unsupported keywords documented).
> **Source architecture:** `docs/aide/architecture.md` M3 (the default provider implements the port; port = dependency-inversion seam), §1.3 (public/internal boundary, curated `main.rkt`, explicit `provide`), §4.1 (Ports via `racket/generic`; Runtime-neutral core L0–L2 import no subprocess/socket).
> **Reference impl (authoritative):** MCP TypeScript SDK v2 at `typescript-sdk/` — `packages/core/src/validators/fromJsonSchema.ts` (the **~43-line, keyword-FREE wrapper** — schema-in → validate-fn-out; **mirror only the WRAPPER SHAPE**), `packages/core/src/validators/types.ts` (the port interface item 011 implements), and `packages/core/test/validators/validators.test.ts` (the **keyword-semantics baseline** this item cross-checks against, for the supported subset only). **Framing:** the real keyword logic in TS lives in the Ajv / cfWorker providers, which vision §8 **excludes** and §4.5 collapses into one Racket-native provider — so the keyword semantics here are **net-new Racket-native design**, not a port of any TS keyword code.
> **Status:** 📋 Not started.

---

## Description

Implement `mcp/core/validators/from-json-schema.rkt`, the **default Racket-native JSON-Schema validator provider** for `racket-mcp`. It is the first concrete provider implementing the **item-010 port** (`gen:json-schema-validator-provider`, `provider-compile`, `validate`, and the `validation-ok` / `validation-errors` / `validation-error` result shape). It is the provider the schema util (item 012) and the S2 demo (item 018) wire up by default, and the one the high-level server (S6b) will use for tool I/O until/unless a vetted-library provider is adopted.

### Framing — what is ported vs what is net-new (read carefully)

The TS source has **two distinct pieces**, and this item relates to them very differently:

1. **`fromJsonSchema.ts`** (`packages/core/src/validators/fromJsonSchema.ts`) is a **~43-line, keyword-FREE wrapper**. It takes a `(schema, validator-provider)` pair, calls `validator.getValidator(schema)` once to get a `check` closure, and wraps the result in a Standard-Schema envelope (`{ value }` on success, `{ issues: [{ message }] }` on failure). **It contains no keyword-validation logic at all** — it delegates entirely to the injected provider. This item mirrors **only the WRAPPER SHAPE**: schema-in → reusable validate-fn-out, success carries the value, failure carries a message (here enriched to path+message per the item-010 result shape).
2. The **actual keyword logic** in TS lives in `ajvProvider.ts` and `cfWorkerProvider.ts`, which `validators.test.ts` instantiates and tests. **Vision §8 EXCLUDES both** of these (no Ajv dependency, no cfWorker), and **§4.5 collapses them into ONE Racket-native provider** — this item. So the keyword semantics here are **net-new Racket-native design**, hand-rolled against the **observable behaviour** that `validators.test.ts` asserts (for the supported subset), **not** a transliteration of Ajv or cfWorker source.

The consequence: this module is the spot where the "Ajv/cfWorker collapse" actually happens. `fromJsonSchema.ts` is the shape template; `validators.test.ts` is the behavioural oracle (restricted to the supported keyword subset); the implementation is original Racket.

### The supported keyword subset (the build contract)

**Minimum supported keywords (MUST be fully evaluated):**

| Keyword | Semantics to implement |
|---|---|
| `type` | one of `"string"` / `"number"` / `"integer"` / `"boolean"` / `"object"` / `"array"` / `"null"` (per-value type check; see edge cases below for integer-vs-number and null) |
| `properties` | object: for each named property present in the value, validate it against its sub-schema; **absence is not a failure** (that is `required`'s job) |
| `required` | object: each listed key MUST be present in the value (presence only — the sub-schema check is `properties`' job) |
| `enum` | value MUST be `equal?` to one of the listed members (members may be heterogeneous — strings, numbers, booleans, `null`) |
| `items` | array: every element MUST validate against the single `items` sub-schema (tuple/`prefixItems` form is OUT of scope — single-schema `items` only, matching the TS fixtures) |
| `format` | string formats `"date-time"`, `"uri"`, `"email"` ONLY (see edge cases for the chosen recognizers; other format values fall under the deferred policy) |

**Deliberately deferred keywords (documented unsupported in this iteration — handled per ONE documented policy, never silently mis-validated):**

`pattern`, `minLength` / `maxLength`, `minimum` / `maximum`, `additionalProperties`, `uniqueItems`.

The single documented policy for these is **one of** (implementer chooses, documents in module docs, and the test asserts the chosen one consistently):
- **(Recommended) ignore-with-warning** — the keyword is *skipped* during evaluation (does not affect accept/reject), and its presence is surfaced once per compile via a `log-warning` / `eprintf` to stderr (or a collected warnings list on the compiled handle). This keeps a schema that *uses* a deferred keyword still usable (the rest of its keywords validate), which is what a default provider should do; OR
- **reject** — `provider-compile` raises (fail-fast) when the schema contains any deferred keyword, via an S1 error constructor (`make-mcp-error` / `make-protocol-error`).

The forbidden third option is **silently honoring the appearance of support** — e.g. accepting `{ type: "string", minLength: 3 }` for `"ab"` as if `minLength` were enforced. Whichever policy is chosen, a value that a deferred keyword *would have* rejected MUST NOT be reported as a per-keyword pass for that keyword; under ignore-with-warning the value is accepted *because the keyword is skipped* (documented), not because it was checked.

> **Minimal-deps decision (record in module docs).** The module docs MUST record the **hand-rolled-subset-vs-library** decision as a justified Minimal-deps choice: the default is a hand-rolled keyword subset (no external JSON-Schema library) because vision §6 (Minimal-deps NFR) and §8 (Ajv/cfWorker exclusions) call for it, and the port (item 010) exists precisely so a vetted library provider can be swapped in later **without changing callers**. State this explicitly in a module-level doc block alongside the supported/deferred keyword tables.

### Error path enrichment — the Racket-native job item 010 left open

Item 010 defined `(validation-error path message)` with `path` a list of JSON-Pointer-ish segments (string keys + integer array indices; `'()` = root) but, being port-only, **left `path` always-root** in its stub. **This item is the first to POPULATE `path` from real per-keyword evaluation.** Nested failures MUST carry their location:

- a failing `properties` sub-schema at key `"name"` → path segment `"name"` prepended;
- a failing `items` element at index `0` → integer segment `0` prepended;
- a nested `properties` → `items` → `properties` failure → the full path, e.g. `'("data" "items" 0 "name")` (string/integer segments interleaved), exactly the mixed-path shape item 010 pinned as a test.

`message` is a human-readable per-keyword failure string (e.g. `"expected string, got 123"`, `"missing required property: name"`, `"value not in enum"`). `validation-ok` carries the validated value unchanged (↔ TS `data`).

### Imports — S1 + the item-010 port ONLY

The module requires:
- `mcp/core/main.rkt` (the S1 barrel: types M1 + errors M2 — for the `jsexpr` notion / `json-null` and, if the deferred-keyword policy is **reject**, the error constructors `make-mcp-error` / `make-protocol-error`); and
- the item-010 port module `mcp/core/validators/provider.rkt` (for `gen:json-schema-validator-provider`, `provider-compile`, `validate`, `compiled-validator`, `validation-ok`, `validation-errors`, `validation-error`).

It MUST NOT require any transport, engine, role, subprocess, or socket module. Restricted-load portability MUST stay clean (no subprocess/socket pulled in) — the item-008 / item-010 walk mechanism is reused (this item's test runs a `from-json-schema.rkt`-rooted load check, and item 017 adds the collection-wide sweep).

### Scope guard (explicit — do NOT cross these lines)

- **Implements the item-010 port AS-IS.** Do NOT redefine the result structs or the generic — `require` them from `provider.rkt`. This item supplies a `struct` that implements `gen:json-schema-validator-provider` plus the keyword evaluator the handle's closure calls.
- **Supported subset ONLY** (the six keyword families above). Deferred keywords get the documented policy, NOT a real implementation. Combinators (`allOf` / `anyOf` / `oneOf` / `not`), `$ref` / `$id` / `$schema` resolution, tuple `items` / `prefixItems`, `minItems` / `maxItems`, and `const` (an enum-of-one is the substitute if needed) are **out of scope** — `$schema` / `$id` / `title` / `description` / `default` keys are simply *ignored harmlessly* (they are annotations, present in the TS fixtures, and MUST NOT cause failures).
- **NO schema normalization** (contract-or-JSON-Schema bridging) — that is item 012.
- **NO new port surface.** This item adds `from-json-schema.rkt`'s own provider struct + a constructor (e.g. `make-racket-native-provider`) to `provide`; it does NOT widen `provider.rkt`'s exports.

---

## Acceptance Criteria

- [ ] `mcp/core/validators/from-json-schema.rkt` exists as `#lang racket/base` (or `#lang racket`) with an explicit, curated `provide` (no `(provide (all-defined-out))`).
- [ ] The module defines a `struct` (e.g. `racket-native-provider`) that **implements `gen:json-schema-validator-provider`** from `provider.rkt` (`#:methods gen:json-schema-validator-provider [(define (provider-compile p schema) …)]`), and provides a constructor (e.g. `make-racket-native-provider` or the struct constructor) on the public surface. `(json-schema-validator-provider? (make-racket-native-provider))` → `#t`.
- [ ] `provider-compile` returns a `compiled-validator?` handle (item-010 type) whose `validate` closure evaluates the supported keyword subset; the same handle is reusable across many `validate` calls (no per-call mutable state — tested).
- [ ] **`type` keyword** — accept + reject for EACH of `string` / `number` / `integer` / `boolean` / `object` / `array` / `null`. Specifically: `"string"` accepts a string + rejects a number; `"number"` accepts `42` AND `3.14` + rejects `"42"`; `"integer"` accepts `42` + **rejects `3.14`** (integer-vs-number distinction); `"boolean"` accepts `#t`/`#f` + rejects `1` and `"true"`; `"object"` accepts a `hasheq` + rejects a list; `"array"` accepts a list + rejects a `hasheq`; `"null"` accepts `(json-null)` + rejects `0`/`#f`/`""`.
- [ ] **`object` / `properties` keyword** — accept a value whose present properties all validate; reject a value where a present property violates its sub-schema, with the failing property's key as a `path` segment. Absent (non-required) properties do NOT cause failure.
- [ ] **`required` keyword** — accept a value containing all required keys; reject a value missing a required key, with a `message` naming the missing key (path = the object's path, or the missing-key segment per the documented convention — pin whichever is chosen). **Empty `required` (`[]`)** accepts every object (edge case, tested).
- [ ] **`enum` keyword** — accept a value `equal?` to a listed member; reject a value not in the list. A **heterogeneous** enum (`'("option1" 42 #t (json-null))`) accepts each listed member of its respective type and rejects an unlisted value (mirrors the TS mixed-type enum fixture). `(json-null)` as an enum member matches a `(json-null)` value (not `#f`/`0`).
- [ ] **`items` keyword** — accept an array whose every element validates against the `items` sub-schema (incl. the **empty array**, which trivially accepts); reject an array with any non-conforming element, with the **integer index** of the first failing element as a `path` segment. **Nested `items` + `properties`** path construction is tested: an `array` of `object`s where one object's property fails carries a path like `'(0 "name")`.
- [ ] **`format` keyword** (string formats) — accept + reject for EACH of `date-time` (`"2025-10-17T12:00:00Z"` accepts, `"not-a-date"` rejects), `uri` (`"https://example.com"` accepts, `"not-a-uri"` rejects), `email` (`"user@example.com"` accepts, `"invalid-email"` rejects). The recognizer for each is documented (a pragmatic regex/parse, not full RFC) and its known limitations noted in module docs.
- [ ] **Deferred-keyword policy is enforced and uniform.** EACH of `pattern`, `minLength`/`maxLength`, `minimum`/`maximum`, `additionalProperties`, `uniqueItems` is handled by the **single documented policy** (ignore-with-warning OR reject), asserted by a test, and **listed in the module docs** as deliberately unsupported. Under ignore-with-warning: a schema using a deferred keyword still validates its supported keywords, the deferred keyword does NOT affect accept/reject, and a warning is emitted/recorded (asserted). Under reject: `provider-compile` raises on a schema containing any deferred keyword (asserted via `check-exn`). The forbidden behaviour — silently appearing to enforce a deferred keyword — is NOT present.
- [ ] **Errors carry real path + message.** On a nested failure the produced `validation-errors` contains a `validation-error` whose `path` reflects the failure location (string keys + integer indices, `'()` for a root/top-level type mismatch) and whose `message` is a non-empty human-readable string — populated from actual per-keyword evaluation, NOT a hard-coded root error. The **mixed-path** `'(… 0 …)` case (item-010's pinned shape) is produced by a real nested-`items` failure.
- [ ] **TS-baseline cross-check (supported subset).** For each of `type`, `object`/`properties`, `required`, `enum`, `string`-`format`, at least one accept + one reject case uses the **same schema + value** as a fixture in `typescript-sdk/packages/core/test/validators/validators.test.ts`, and the Racket provider produces the SAME accept/reject verdict the TS test asserts (`valid:true` ↔ `validation-ok?`, `valid:false` ↔ `validation-errors?`). Fixtures from deferred-keyword TS tests (`minLength`, `pattern`, `minimum`, `additionalProperties`, `uniqueItems`, `allOf`/`anyOf`/`oneOf`/`not`) are explicitly NOT used as accept/reject oracles — they exercise unsupported features. The cross-check methodology (which fixtures, how parity is asserted) is documented in the test file header.
- [ ] **Malformed-schema compile policy (fail-fast precedent inherited from item 010).** `provider-compile` on a structurally malformed schema (non-`hasheq` schema, a `properties` whose value is not an object-of-subschemas, a `type` whose value is not a recognized type string, an `enum` that is not a list) **fails fast** — raises via an S1 error constructor — rather than deferring to validate time or silently passing. Asserted via `check-exn`. (This matches item 010's documented compile-on-garbage precedent.)
- [ ] The module imports **only S1** (`mcp/core/main.rkt`) **and the item-010 port** (`provider.rkt`). It requires NO transport/engine/role/subprocess/socket module. **Verified by a restricted-namespace load test** whose entry point is **`from-json-schema.rkt` itself**: a fresh `(make-base-namespace)` requiring it and walking `module->imports` transitively shows EMPTY intersection with the banned set (`racket/system racket/tcp racket/udp net/url net/http-client net/sendurl racket/sandbox racket/port`). **Note:** if a `format`-`uri` recognizer is tempted to use `net/url`, it MUST NOT — `net/url` is in the banned set; use a string/regex recognizer instead (documented).
- [ ] `raco test mcp/core/validators/` passes (exit 0) — module + new test compile and run cleanly within the collection, alongside item 010's `provider-test.rkt`.
- [ ] `raco make mcp/core/validators/from-json-schema.rkt` exits 0 (compiles clean, no warnings about missing/non-portable modules).
- [ ] Parity-matrix discipline: per Stage S2 the `validators/*` row advances toward `partial` (the default provider's supported-keyword exercise now exists; full conformance lands with items 017/018 and S9). Update `docs/aide/progress.md` per the Completion Reminder — flip the `from-json-schema.rkt` deliverable line AND check the Stage-S2 **validator keyword-coverage** acceptance box (this item owns it).

---

## Implementation Steps

1. **Read the framing sources once more for shape + oracle:** `typescript-sdk/packages/core/src/validators/fromJsonSchema.ts` (wrapper shape — schema-in / validate-fn-out / value-on-success / message-on-failure) and `typescript-sdk/packages/core/test/validators/validators.test.ts` (the behavioural oracle; identify which fixtures fall in the **supported subset** vs the deferred/excluded set — see Testing Strategy for the exact fixture map). Re-read item 010's `provider.rkt` surface (`docs/aide/items/010-validator-provider-port.md` Description §1–§3) so you require, not redefine, the port + result types.
2. **Confirm the S1 surface you need:** `(json-null)` from `json` (re-exported through the S1 barrel or `require json` directly — record which), and, if the deferred policy is **reject**, `make-mcp-error` / `make-protocol-error` from `mcp/core/main.rkt`.
3. **Write `mcp/core/validators/from-json-schema.rkt`.** Use `#lang racket/base`. In order:
   - `(require racket/generic racket/list "../main.rkt" "provider.rkt")` plus `json` if `(json-null)` is needed directly; `racket/contract` only if attaching `contract-out`.
   - A module-level **doc block** recording: the Minimal-deps hand-rolled-subset decision; the supported-keyword table; the deferred-keyword table + the chosen single policy; the `format` recognizer choices + limitations.
   - A **compile-time schema validator** `(check-schema-shape schema)` that fail-fasts (via `make-mcp-error`/`make-protocol-error`) on malformed schemas (non-hash, bad `properties`, bad `type`, bad `enum`) and (under the reject policy) on deferred keywords.
   - A **recursive evaluator** `(evaluate schema value path)` → `(listof validation-error)` (empty = ok), threading `path` and prepending string keys / integer indices on descent into `properties` / `items`. Each keyword family contributes errors; combine.
   - The provider **struct** implementing `gen:json-schema-validator-provider`: `provider-compile` runs `check-schema-shape` once, then returns `(compiled-validator (lambda (v) (let ([errs (evaluate schema v '())]) (if (null? errs) (validation-ok v) (validation-errors errs)))))`.
   - A constructor (`make-racket-native-provider`) and the explicit `(provide …)` block (struct predicate/constructor + constructor proc; NOT the internal `evaluate`/`check-schema-shape` helpers; NOT a re-export of the port — callers `require` the port directly for the result API).
4. **Write the test** `mcp/core/validators/test/from-json-schema-test.rkt` (see Testing Strategy). Cover every supported keyword (accept+reject), the edge cases (integer-vs-number, null-vs-`json-null`, empty `required`, heterogeneous enum, empty array, nested path construction), the deferred-keyword policy (one assertion per deferred keyword), the malformed-schema fail-fast, the TS-baseline cross-check block, and the restricted-load portability sub-test (reuse the item-008/010 walk helper; entry point = `from-json-schema.rkt`).
5. **Run** `raco make mcp/core/validators/from-json-schema.rkt` then `raco test mcp/core/validators/`. Fix any failure. Confirm item 010's `provider-test.rkt` still passes alongside.
6. **Update progress + parity matrix** (see Completion Reminder).

---

## Testing Strategy

The test is a **behavioural keyword-coverage test** for the supported subset, with a **TS-baseline cross-check** (the supported fixtures from `validators.test.ts`), the **deferred-keyword policy** pinned per keyword, **edge cases** for every tricky semantic, the **fail-fast compile** precedent, **path-construction** assertions, and the **restricted-load portability** sub-test. Result-shape mechanics (the `validation-ok`/`validation-errors`/`validation-error` API, the non-empty guard, opacity) are already covered by item 010's `provider-test.rkt` and are NOT re-litigated here — this test asserts *verdicts and paths*, requiring the result API from the port.

**Test file:** `mcp/core/validators/test/from-json-schema-test.rkt` (`#lang racket/base`; `(require rackunit json "../from-json-schema.rkt" "../provider.rkt")` plus `racket/set`/`racket/path` for the portability walk). `json` is needed for `(json-null)`.

A small helper makes the verdict assertions terse and readable:
```racket
(define (accepts? provider schema value)
  (validation-ok? (validate (provider-compile provider schema) value)))
;; and the negation for rejects?
```

### Part 1 — `type` keyword, all seven types + the hard edge cases

For each of the seven `type` values, at least one accept and one reject, with the edge cases pinned explicitly:
- `"string"` — accepts `"hi"`; rejects `123` (TS: "validates basic string").
- `"number"` — accepts `42` AND `3.14`; rejects `"42"` (TS: "validates number type").
- `"integer"` — accepts `42`; **rejects `3.14`** (the integer-vs-number distinction — `42.0` handling documented: Racket `42` is an integer; if a value arrives as `42.0`/`exact->inexact`, document whether it counts as integer — recommended: accept only `exact-integer?`, matching Ajv's "is it a JSON integer"). (TS: "validates integer type".)
- `"boolean"` — accepts `#t` and `#f`; rejects `1` and `"true"` (TS: "validates boolean type").
- `"object"` — accepts `(hasheq 'a 1)`; rejects `'(1 2 3)` and a string.
- `"array"` — accepts `'(1 2 3)`; rejects `(hasheq 'a 1)`.
- `"null"` — accepts `(json-null)`; rejects `0`, `#f`, `""`. **Pin the `null`-vs-`(json-null)` semantic:** JSON `null` is represented as `(json-null)` (which is `'null` by default in Racket's `json`); the test asserts the provider matches `(json-null)` and NOT Racket `'()` or `#f`. Document the representation assumption.

### Part 2 — `object` / `properties` / `required`

- `properties` accept: `{type:object, properties:{name:{type:string}, age:{type:number}}, required:[name]}` accepts `{name:"John", age:30}` AND `{name:"John"}` (age absent is fine) (TS: "validates simple object").
- `properties` reject + path: the same schema rejects `{name:123}` (name present but wrong type); assert the produced `validation-error`'s `path` contains `"name"`.
- `required` reject + message: the same schema rejects `{age:30}` and `{}` (name missing); assert a `message` naming `name` (TS: same fixture asserts `valid:false`).
- **Empty `required`** edge: `{type:object, properties:{}, required:[]}` accepts `{}` and `{anything:1}` (empty required never fails).
- **Nested objects** (TS: "validates nested objects"): `{type:object, properties:{user:{type:object, properties:{name:{type:string}, email:{type:string, format:email}}, required:[name]}}, required:[user]}` accepts `{user:{name:"John", email:"john@example.com"}}` and `{user:{name:"John"}}`; rejects `{user:{email:"john@example.com"}}` (user.name missing) — assert path includes `"user"`.

### Part 3 — `enum`, incl. heterogeneous + `null` member

- Homogeneous string enum (TS: "validates enum values"): `{enum:["red","green","blue"]}` accepts each of `"red"`/`"green"`/`"blue"`; rejects `"yellow"`.
- **Heterogeneous enum** (TS: "validates enum with mixed types"): `{enum:["option1", 42, #t, (json-null)]}` accepts `"option1"`, `42`, `#t`, and `(json-null)`; rejects `"other"`. Assert `(json-null)` membership matches a `(json-null)` value and NOT `#f`/`0` — heterogeneous `equal?`-membership with the null representation pinned.

### Part 4 — `items`, incl. empty array + nested path

- Array of strings (TS: "validates array of strings"): `{type:array, items:{type:string}}` accepts `["a","b","c"]` AND `[]` (empty array trivially accepts); rejects `["a", 1, "c"]` — assert the failing element's **integer index** `1` appears in the `path`.
- **Nested `items` + `properties`** path construction: `{type:array, items:{type:object, properties:{name:{type:string}}, required:[name]}}` over `[{name:"ok"}, {name:123}]` rejects, and the produced path is `'(1 "name")` (integer index then string key) — the mixed-path shape item 010 pinned. Also test the deeply-nested TS "API response" fixture (`data.items[].name`) to produce a `'("data" "items" 0 "name")`-style path on a crafted failing value.

### Part 5 — `format` (string formats)

For each of `date-time`/`uri`/`email`, one accept + one reject, using the TS fixtures verbatim:
- `format:date-time` — accepts `"2025-10-17T12:00:00Z"`; rejects `"not-a-date"`.
- `format:uri` — accepts `"https://example.com"`; rejects `"not-a-uri"`.
- `format:email` — accepts `"user@example.com"`; rejects `"invalid-email"`.
Document each recognizer's strategy + limitations in the test header (e.g. the email recognizer is a pragmatic `local@domain` regex, not full RFC 5322; `uri` requires a scheme; `date-time` is an ISO-8601 subset). Note `format` applies only when the value is a string (a non-string under a `format` schema is governed by `type`, if present).

### Part 6 — deferred-keyword policy (one assertion per keyword)

For EACH of `pattern`, `minLength`/`maxLength`, `minimum`/`maximum`, `additionalProperties`, `uniqueItems`, assert the **single documented policy** consistently. Using the TS deferred fixtures as the schema source but NOT as accept/reject oracles:
- **Under ignore-with-warning (recommended):** e.g. `{type:string, minLength:3}` on `"ab"` is **accepted** (the deferred keyword is skipped — documented), proving the keyword is NOT silently enforced-as-pass-by-luck but explicitly ignored; and the supported `type:string` part still rejects `123`. Assert a warning is emitted/recorded for the deferred keyword (capture stderr via `with-output-to-string`/`parameterize current-error-port`, or read the handle's recorded-warnings field). Do this for each of the five deferred keyword families.
- **Under reject:** `(check-exn exn:fail? (lambda () (provider-compile p {schema-with-deferred-keyword})))` for each of the five families.
Also assert each deferred keyword **is named in the module docs** — e.g. read `from-json-schema.rkt` as text and `regexp-match?` the keyword names in the doc block (a lightweight "documented" check, mirroring the TS `should document that … is required` test pattern).

### Part 7 — TS-baseline cross-check (the parity methodology, made explicit)

A dedicated test block headed with the methodology comment: *"Each case below uses the exact schema+value from `validators.test.ts` and asserts the Racket verdict equals the TS-asserted `valid`. Only fixtures in the supported keyword subset are used; deferred/excluded-keyword fixtures (minLength, pattern, minimum, additionalProperties, uniqueItems, allOf/anyOf/oneOf/not, $schema/$id constraint behaviour) are intentionally omitted as they exercise unsupported features."* The supported fixtures to mirror: basic string; number type; integer type; boolean type; enum values; enum mixed types; simple object; nested objects; array of strings; email/uri/date-time format; and the **supported slices** of the two "complex real-world" fixtures (the user-registration and API-response objects, evaluated for only their supported keywords — i.e. construct values that pass/fail on `type`/`properties`/`required`/`enum`/`format` alone, since those fixtures also carry `minLength`/`pattern`/`minimum` which are deferred). State in the block that the complex fixtures are cross-checked on their **supported-keyword projection** only.

### Part 8 — malformed-schema fail-fast (item-010 precedent inherited)

`check-exn exn:fail?` (ideally an S1 error type) for each malformed schema at **compile** time:
- non-`hasheq` schema (`42`, `'()`);
- `properties` whose value is not an object-of-subschemas (e.g. `(hasheq 'properties 5)`);
- `type` whose value is not a recognized type string (`(hasheq 'type "stringg")`, `(hasheq 'type 5)`);
- `enum` that is not a list (`(hasheq 'enum 5)`).
Document that fail-fast at compile is the chosen policy (inherited from item 010 Decisions (e)), distinct from validate-time *value* rejection.

### Part 9 — restricted-namespace portability (S1 + port only)

Reuse the transitive `module->imports` walk from item 008/010 — fresh `(make-base-namespace)`, `namespace-require` `from-json-schema.rkt`, walk imports threading `current-load-relative-directory` per module dir, assert the FULL banned set (`racket/system racket/tcp racket/udp net/url net/http-client net/sendurl racket/sandbox racket/port`) has empty intersection with the visited set. **Entry point is `from-json-schema.rkt` ITSELF.** This proves the default provider (and, transitively, the port it requires) is portability-clean. **Specifically guards** that the `format`-`uri` recognizer did not reach for `net/url` (banned). **Non-vacuity (drift):** temporarily inject `(require racket/tcp)` into a scratch copy, confirm the walk FAILS naming `racket/tcp`, revert. (Scope note inherited from item 008: `module->imports` does not see into `(module+ test …)` submodules — proves the module's own import graph, not a test submodule's.)

---

## Dependencies

- **Upstream work items:**
  - **Item 010** (`mcp/core/validators/provider.rkt`, ✅ complete) — this item REQUIRES the port: `gen:json-schema-validator-provider`, `provider-compile`, `validate`, `compiled-validator`, and the result API `validation-ok` / `validation-errors` / `validation-error` (+ their predicates/accessors). It implements the generic and populates `validation-error` `path`/`message`.
  - **Stage S1 items 001–009** (✅ complete) — `mcp/core/main.rkt` (item 008 barrel: types M1 + errors M2). Provides the `jsexpr` notion, `(json-null)`, and (if the deferred policy is reject) `make-mcp-error` / `make-protocol-error`.
- **Downstream consumers (informational):**
  - **Item 012** (`util/schema.rkt`) — the schema-normalization util produces a validation handle that delegates to a provider; the **default provider it wires up is this one**.
  - **Item 017** — the S2 collection-wide restricted-load portability sweep includes `mcp/core/validators` (this module).
  - **Item 018** — the S2 demo registers a JSON Schema via THIS provider and validates a good + bad value, showing the structured (path+message) errors.
  - **S6b** high-level server consumes validation (via item 012, defaulting to this provider) for tool I/O.
- **Tooling/runtime:** Racket ≥ 8.x (`raco`, `rackunit`). The `typescript-sdk/` checkout MUST be present — unlike item 010, **this item DOES assert TS-baseline parity** (Part 7 cross-check uses `validators.test.ts` fixtures), so the checkout's `packages/core/test/validators/validators.test.ts` is read (by the implementer, to lift fixtures into the Racket test) — the Racket test itself hard-codes the lifted fixtures rather than parsing the `.ts` at runtime, so a missing checkout would not break the *running* test but WOULD make the fixtures un-reproducible; treat the checkout as required for authoring.

---

## Decisions & Trade-offs

To be updated during implementation.

---

## Project-Specific Adaptations (Racket / raco / rackunit)

This is a **Racket library, not a service** — same adaptation pattern as item 010. The generic "Testing Prerequisites" template (Required Services / database / API endpoint / ports / health checks) does **not** apply and is adapted as follows (documented explicitly per the create-item skill):

- **Required Services → None.** Pure Racket library; no external services, databases, message queues, HTTP servers, sockets, subprocesses, or network. The module is L0 and load-portable by construction (and proven so by the restricted-load test). **Note:** the supported `format`-`uri` recognizer MUST be a string/regex recognizer — it MUST NOT use `net/url` (banned by the portability NFR).
- **Database / API endpoint / ports sections → N/A.** Removed; replaced by the Racket toolchain row below.
- **Required toolchain:** Racket ≥ 8.x (`raco test`, `rackunit`). Verified present in this environment: **Racket v8.18 [cs]**.
- **TS checkout role:** present at `typescript-sdk/`; **required for authoring** (Part 7 lifts fixtures from `validators.test.ts`). Unlike item 010 (no parity), item 011 DOES assert TS-baseline parity on the supported keyword subset. The lifted fixtures are hard-coded into the Racket test, so the running test does not parse the `.ts` at runtime.
- **Manual Validation Checklist → specialized** to `raco make` / `raco test` + a REPL / provider smoke check (below). No "service started" / "health check" / "screenshots" rows — replaced with N/A or removed.
- **Language/naming:** `#lang racket/base`; kebab-case bindings; explicit `(provide …)` never `all-defined-out` (architecture §1.3); implements the port's `racket/generic` interface (architecture §4.1).

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None (pure Racket library; no external services).** No databases, message queues, HTTP servers, sockets, subprocesses, or network dependencies.

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime | compile + run module and tests (`raco`, `rackunit`) | system install (`racket --version` ≥ 8.0; this env: v8.18) | n/a |
| S1 barrel (`mcp/core/main.rkt`) | the module requires the S1 public surface (types + errors) | already present (items 001–008, ✅) | n/a |
| Item-010 port (`mcp/core/validators/provider.rkt`) | the module implements the generic + uses the result API | already present (item 010, ✅) | n/a |
| `typescript-sdk/` checkout | read while authoring to lift supported-subset fixtures from `validators.test.ts` (Part 7 parity) | already present at repo root | n/a |

### Environment Configuration

- **Environment variables / secrets / config files / free ports:** none required.
- **Racket version:** ≥ 8.x (verified: v8.18 [cs]).
- **Working directory:** run `raco test` from the **repo root** so the `mcp/...` collection path resolves.
- **How to run the tests:**
  - `raco make mcp/core/validators/from-json-schema.rkt` — compile the default provider clean.
  - `raco test mcp/core/validators/` — run all validator-collection tests (picks up `test/from-json-schema-test.rkt` AND item 010's `test/provider-test.rkt` recursively), exit 0.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0.
  - `raco make mcp/core/validators/provider.rkt` → exit 0 (the item-010 port this item requires loads clean).

### Manual Validation Checklist

*(Not yet built — leave UNCHECKED until implementation completes.)*

- [ ] **Build/compile succeeds:** `raco make mcp/core/validators/from-json-schema.rkt` compiles with no errors/warnings.
- [ ] **Module loads in isolation:** `racket -e '(require (file "mcp/core/validators/from-json-schema.rkt"))'` from repo root succeeds.
- [ ] **Tests pass:** `raco test mcp/core/validators/test/from-json-schema-test.rkt` → all checks pass, exit 0.
- [ ] **Collection tests pass (incl. item 010):** `raco test mcp/core/validators/` → exit 0.
- [ ] **Services started:** N/A (no services — pure library).
- [ ] **Application runs:** N/A (library; "running" = the require + REPL/provider smoke check below).
- [ ] **Feature verified (REPL / provider smoke check):** from repo root, build the provider, compile an object schema, validate a good + bad value — e.g.
      `racket -e '(require (file "mcp/core/validators/from-json-schema.rkt") (file "mcp/core/validators/provider.rkt")) (define p (make-racket-native-provider)) (define h (provider-compile p (hasheq (quote type) "object" (quote properties) (hasheq (quote name) (hasheq (quote type) "string")) (quote required) (list "name")))) (list (validation-ok? (validate h (hasheq (quote name) "John"))) (validation-errors? (validate h (hasheq))))'`
      prints `(#t #t)` (ok for `{name:"John"}`, errors for `{}` — missing required). (Adjust to the chosen constructor name; record exact transcript in Validation Results.)
- [ ] **`type` matrix verified:** accept+reject for each of string/number/integer/boolean/object/array/null; integer rejects `3.14`; null matches `(json-null)` not `#f`/`0`.
- [ ] **`properties`/`required` verified:** present-but-wrong-type rejects with key in path; missing-required rejects with key in message; empty `required` accepts any object; nested-object path includes the parent key.
- [ ] **`enum` verified:** homogeneous + heterogeneous (incl. `(json-null)` member) accept listed / reject unlisted.
- [ ] **`items` verified:** accepts (incl. empty array), rejects with failing element's integer index in path; nested `items`+`properties` produces a `'(0 "name")`-style mixed path.
- [ ] **`format` verified:** date-time/uri/email each accept the TS-valid example and reject the TS-invalid one.
- [ ] **Deferred-keyword policy verified:** each of `pattern`/`minLength`-`maxLength`/`minimum`-`maximum`/`additionalProperties`/`uniqueItems` handled per the single documented policy (ignore-with-warning OR reject) and listed in module docs.
- [ ] **Error path+message verified:** a nested failure yields a `validation-error` with a real path (incl. a `'(… 0 …)` mixed path) and a non-empty message — not a hard-coded root error.
- [ ] **TS-baseline cross-check verified:** the supported-subset fixtures from `validators.test.ts` produce the same accept/reject verdict in Racket (parity block green).
- [ ] **Malformed-schema fail-fast verified:** `provider-compile` raises on non-hash schema / bad `properties` / bad `type` / non-list `enum` (check-exn).
- [ ] **Portability verified:** the restricted-load test passes (no subprocess/socket — incl. NO `net/url` from the uri recognizer — in the transitive import closure of `from-json-schema.rkt`).
- [ ] **Drift / non-vacuity check (portability):** temporarily add `(require racket/tcp)` to a scratch copy, confirm the load test FAILS naming `racket/tcp`, then revert.
- [ ] **Health checks pass:** N/A (no running service).

### Expected Outcomes

Concrete, verifiable:

- The module **exports** a default-provider constructor (e.g. `make-racket-native-provider`) + its struct predicate; `(json-schema-validator-provider? (make-racket-native-provider))` → `#t`. **No internal evaluator/schema-checker helper leaks** (`evaluate` / `check-schema-shape` are NOT provided). It does NOT re-export the port's result API (callers `require` `provider.rkt`).
- A compiled handle from this provider returns a `validation-ok` (value recovered) for a value satisfying the supported keywords, and a `validation-errors` (non-empty list of `validation-error`, each with a **real path** + message) for a violating value — paths populated from actual nested evaluation (incl. mixed string/integer paths).
- For each of `type`/`object`-`properties`/`required`/`enum`/`string`-`format`, ≥1 accept + ≥1 reject case matches the TS `validators.test.ts` verdict for the same schema+value (supported subset).
- Each deferred keyword (`pattern`, `minLength`/`maxLength`, `minimum`/`maximum`, `additionalProperties`, `uniqueItems`) is handled per one documented policy and named in the module docs.
- The module **requires only S1 + the item-010 port** — a restricted-namespace load test confirms NO subprocess/socket module (`racket/system`, `racket/tcp`, `racket/udp`, `net/*`, `racket/sandbox`, `racket/port`) is pulled in (Portability NFR).
- `raco test mcp/core/validators/` reports all checks passing, 0 failures, 0 errors (item 011's new test + item 010's existing test).

### Validation Results

*(Template — populate during implementation; leave checkboxes UNCHECKED until built.)*

```markdown
## Validation Results
- [ ] Service started: N/A (pure Racket library, no services)
- [ ] Application started successfully: N/A (library; `require` + provider smoke check)
- [ ] Build verified: `raco make mcp/core/validators/from-json-schema.rkt` clean (exit 0, no warnings)
- [ ] Module load verified: `(require (file ".../from-json-schema.rkt"))` succeeds
- [ ] Tests verified: `raco test mcp/core/validators/` → all checks pass, 0 failures, 0 errors
- [ ] type matrix verified: string/number/integer/boolean/object/array/null accept+reject; integer rejects 3.14; null = (json-null) not #f/0
- [ ] properties/required verified: wrong-type prop rejects (key in path); missing required rejects (key in message); empty required accepts; nested path includes parent key
- [ ] enum verified: homogeneous + heterogeneous (incl. (json-null) member) accept/reject
- [ ] items verified: empty-array accepts; bad element rejects with integer index in path; nested items+properties → '(0 "name") mixed path
- [ ] format verified: date-time/uri/email accept TS-valid, reject TS-invalid
- [ ] deferred-keyword policy verified: pattern/minLength-maxLength/minimum-maximum/additionalProperties/uniqueItems per single documented policy; listed in module docs
- [ ] error path+message verified: nested failure yields real path (incl. mixed '(… 0 …)) + non-empty message
- [ ] TS-baseline cross-check verified: supported-subset validators.test.ts fixtures → same accept/reject verdict
- [ ] malformed-schema fail-fast verified: non-hash / bad properties / bad type / non-list enum → provider-compile raises (check-exn)
- [ ] Portability verified: restricted-load walk over from-json-schema.rkt — empty intersection with banned set (incl. no net/url from uri recognizer)
- [ ] Portability drift check: injected (require racket/tcp) → walk FAILED naming racket/tcp, then reverted
- [ ] S1 + port imports confirmed: require list = racket/generic + ../main.rkt + provider.rkt (+ json if used)
- [ ] Database tables verified: N/A
- [ ] Seed data verified: N/A
- [ ] API endpoints verified: N/A
- [ ] Screenshots captured: N/A (no UI)
```

---

## Completion Reminder

On completion, the implementer MUST update **`docs/aide/progress.md`** (Stage S2 section), advancing the icon **📋 → 🚧 → ✅**:

1. Flip the deliverable line **`📋 mcp/core/validators/from-json-schema.rkt — Racket-native default (keywords: type, properties, required, enum, items, format for date-time/uri/email)`** (progress.md line ~72) from 📋 → 🚧 (on start) → ✅ (on delivery + all acceptance criteria pass). Never revert an icon backward.
2. **Check the Stage-S2 validator keyword-coverage acceptance box** — **`[ ] Validator keyword coverage: ≥1 accept + 1 reject per type/object/required/enum/string-format, cross-checked vs TS Ajv baseline; unsupported keywords documented`** (progress.md line ~86). **This box belongs to THIS item** (item 010 delivered only the port; this item delivers the keyword evaluation + the TS-baseline cross-check + the documented-unsupported-keywords list). Check it on delivery.
3. Do **not** check the other broad Stage-S2 acceptance boxes that depend on sibling items (the `raco test over all S2 modules`, URI-template, tool-name, schema-normalization, and stdio-framing boxes belong to items 012–017/018).
4. **Parity matrix:** per Stage S2 discipline, advance the `validators/*` row toward `partial` (the default provider's supported-keyword exercise now exists; full conformance + the collection-wide sweep land with items 017/018 and S9). Record that the **default-provider/keyword** sub-row is now satisfied (item 010 satisfied the **port** sub-row).
5. Leave all other S2 deliverable lines (`util/schema.rkt`, the `shared/*` utils, tests-under-other-dirs) at their current status — this item delivers only `validators/from-json-schema.rkt` + its test.
