# Work Item 011: Default Racket-native provider — `from-json-schema` (M3)

> **Queue:** `docs/aide/queue/queue-002.md` — Item 011
> **Stage:** S2 (Foundation: validators, schema, shared utilities — L0 part 2)
> **Module:** M3 (Validators) — the **default provider** sub-unit (`mcp/core/validators/from-json-schema.rkt`); it implements the item-010 port (`mcp/core/validators/provider.rkt`). The schema util that consumes it is item 012.
> **Source vision:** `docs/aide/vision.md` §4.5 (pluggable JSON-Schema validator; **Ajv/cfWorker collapse to one Racket-native provider**), §8 (Zod/Standard-Schema-lib + cfWorker **exclusions**), §6 (Portability NFR — core loads without subprocess/socket; **Minimal-deps NFR** — default = hand-rolled subset unless a vetted lib is adopted).
> **Source roadmap:** `docs/aide/roadmap.md` Stage S2 → Deliverables line (`mcp/core/validators/from-json-schema.rkt` — Racket-native default; keywords `type`/`properties`/`required`/`enum`/`items`/`format`) + Testing/validation criteria (keyword coverage cross-checked vs TS Ajv baseline; unsupported keywords documented).
> **Source architecture:** `docs/aide/architecture.md` M3 (the default provider implements the port; port = dependency-inversion seam), §1.3 (public/internal boundary, curated `main.rkt`, explicit `provide`), §4.1 (Ports via `racket/generic`; Runtime-neutral core L0–L2 import no subprocess/socket).
> **Reference impl (authoritative):** MCP TypeScript SDK v2 at `typescript-sdk/` — `packages/core/src/validators/fromJsonSchema.ts` (the **~43-line, keyword-FREE wrapper** — schema-in → validate-fn-out; **mirror only the WRAPPER SHAPE**), `packages/core/src/validators/types.ts` (the port interface item 011 implements), and `packages/core/test/validators/validators.test.ts` (the **keyword-semantics baseline** this item cross-checks against, for the supported subset only). **Framing:** the real keyword logic in TS lives in the Ajv / cfWorker providers, which vision §8 **excludes** and §4.5 collapses into one Racket-native provider — so the keyword semantics here are **net-new Racket-native design**, not a port of any TS keyword code.
> **Status:** ✅ Complete — `from-json-schema.rkt` + test shipped, `raco test mcp/core/validators/` = 300 checks pass / 0 fail, portability + drift verified (see Validation Results)

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
| `enum` | value MUST be `equal?` to one of the listed members (members may be heterogeneous — strings, numbers, booleans, `null`, and compound objects/arrays — `equal?` is a deep structural compare, NOT `eq?`/`eqv?`) |
| `items` | array: every element MUST validate against the single `items` sub-schema (tuple/`prefixItems` form is OUT of scope — single-schema `items` only, matching the TS fixtures) |
| `format` | string formats `"date-time"`, `"uri"`, `"email"` ONLY, **and only when the value is a string** (see "format on non-strings + unknown formats" below + the recognizer-rigor directive) |

> **Type-guard semantics for the structural keywords (`properties`/`required`/`items`/`enum`/`format`) — MUST NOT crash on a wrong-typed value (C2/C3/C5).** Each of these keywords presupposes a value of a particular Racket kind (`hash?` for `properties`/`required`, `list?` for `items`, `string?` for `format`). The evaluator MUST **guard each keyword on the value's actual type and return a clean `validation-error` (NOT raise a Racket contract error) when the value is the wrong kind.** Concretely: `properties`/`required` on a non-`hash?` value, `items` on a non-`list?` value, and `format` on a non-`string?` value MUST NOT call `hash-ref`/`hash-has-key?`/`map`/a regexp on the wrong-typed value. Two sub-rules, both pinned by tests:
> - **When `type` is ALSO present and excludes the value's kind** (e.g. `{type:"object", properties:…}` on `42`), the `type` keyword produces the type-mismatch error and the structural keyword is **skipped** (no point descending into a value already known to be the wrong kind).
> - **When `type` is ABSENT but a structural keyword is present** (e.g. `{properties:{name:…}, required:["name"]}` on `42`, or `{items:…}` on `(hasheq 'a 1)`, or `{format:"email"}` on `42`) — a **legal schema with no `type` guard to catch the mismatch first** — the structural keyword itself MUST short-circuit cleanly: `properties`/`required` on a non-hash and `items` on a non-list each **produce a clean type-expectation `validation-error`** (recommended message e.g. `"expected object, got 42"` / `"expected array, got …"`), NOT a raise; `format` on a non-string is **skipped (accepts as far as `format` is concerned)** — JSON-Schema `format` is a no-op on non-strings (documented). These behaviours are pinned by the C2/C3/C5 fixtures and MUST be implemented as explicit type guards.

**Error-collection policy — COLLECT-ALL (committed design directive, C1).** When a value violates **multiple** keywords (or multiple array elements / multiple properties fail), the evaluator **collects ALL independent failures into the `validation-errors` list** — it does NOT short-circuit at the first error. Rationale: item 010 deliberately built a *non-empty list* result + a mixed-path test precisely to carry **multiple located errors**; a first-error/short-circuit evaluator would make that machinery vestigial. Concretely (pinned by the C1 fixture): `{type:object, properties:{name:{type:string}, age:{type:number}}, required:["name"]}` on `{age:"x"}` violates BOTH `required` (name missing) AND `properties` (age is a string, not a number) and MUST yield a `validation-errors` of **exactly 2** `validation-error`s. Within an array, EACH failing element contributes its own error (so `[{name:123},{name:456}]` under an object-`items` schema yields BOTH `'(0 "name")` and `'(1 "name")` errors — NOT just the first). The phrase "first failing element's index" from the original `items` AC is **removed** — every failing element is reported. (A per-element/per-property evaluation MAY still stop at the first failing keyword *within a single scalar leaf* — e.g. one string value is reported once — but sibling keywords, sibling properties, and sibling array elements are ALL collected.)

**format on non-strings + unknown formats (C5).**
- **`format` on a non-string value is a NO-OP** (skipped) — e.g. `{format:"email"}` (no `type`) on `42` **accepts** (as far as `format` is concerned; there is no `type` to reject it), matching JSON-Schema semantics where `format` only constrains strings. The recognizer MUST NOT run (no regexp on a number → no crash). When `type:"string"` co-occurs (`{type:"string", format:"email"}` on `42`), the `type` keyword rejects and the recognizer still does not run.
- **Unknown `format` values** (any `format` string other than the three supported `date-time`/`uri`/`email` — e.g. `"ipv4"`, `"hostname"`, `"uuid"`) are routed through the **same deferred-keyword policy** as the deferred keywords below (ignore-with-warning): the unknown format is **skipped (does not constrain) and recorded once at compile** (as a symbol/marker per S-g) — NEVER silently treated as a constraint that passes, and NEVER silently treated as one of the three known formats. Pinned by the C5c fixture (`{type:"string", format:"ipv4"}` on `"1.2.3.4"` → accepts on the supported keywords, warns on the unknown format).

**Unknown (non-deferred, non-supported) keywords (S3).** A keyword that is neither in the supported set, nor in the deferred set, nor a harmless annotation (e.g. `multipleOf`, `propertyNames`, `$ref`, `contains`) is treated by the **same documented deferred policy** (ignore-with-warning): it is skipped, a warning is emitted once at compile naming the unknown keyword, and it does NOT affect accept/reject. This is the catch-all so no keyword is ever *silently* honored-as-support. (Pure annotations — `$schema`, `$id`, `title`, `description`, `default`, `examples` — are ignored **without** a warning, since they carry no validation semantics; see Scope guard.)

**Deliberately deferred keywords (committed: ignore-with-warning, warned ONCE at compile — C4):**

`pattern`, `minLength` / `maxLength`, `minimum` / `maximum`, `additionalProperties`, `uniqueItems`.

The single committed policy (recorded in module docs **before** the test is authored, applied **uniformly to all five** deferred keywords, all unknown formats, and all unknown keywords):

- **ignore-with-warning** — the keyword is *skipped* during evaluation (does **not** affect accept/reject), and its presence is surfaced **exactly once, at `provider-compile` time** (NOT per `validate` call). The list of ignored keywords for a compile is the **load-bearing, test-readable record**; a stderr line is an optional human-facing side effect. A schema using a deferred keyword stays usable — its supported keywords still validate — which is what a default provider should do.

> **Warnings mechanism — PINNED, port-compatible, per-compile-keyed (N1/N2/N3).** Item 010's shipped `compiled-validator` is a **frozen single-field struct** `(struct compiled-validator (validate-proc) #:transparent)`, and this item's Scope guard forbids redefining it or widening the port surface — so a `compiled-validator-warnings` accessor is **impossible** and is NOT used. The committed mechanism:
> - **Warnings are keyed PER COMPILE, NOT stored in a single provider-level slot.** A single mutable provider slot would be overwritten by a second `provider-compile` and directly contradict the S7 two-handles-from-one-provider test (and break item 012, which compiles many schemas through one provider). **The committed mechanism (single, not a menu):** a provider-held **weak** map `(make-weak-hasheq)` from produced **handle → ignored-keyword list**, populated by `provider-compile`, read via a provided accessor **`(provider-warnings-for provider handle)`**. Weak so the provider does NOT retain every handle it ever compiled (a leak when item 012 compiles many schemas through one long-lived provider). **Two encodings are explicitly REJECTED — do NOT use them:** (i) `provider-compile` returning `(values handle warnings)` — this changes the item-010 generic's arity (the forbidden "new port surface"), breaks the spec's own `(validate (provider-compile P schema) value)` helpers with a values-in-single-value-context arity error, and makes `(warnings-of h)` unimplementable; (ii) a single provider-level mutable slot (overwritten by the next compile). `provider-compile` MUST keep returning a single `compiled-validator?` exactly as the port requires. With the weak-map encoding, **two handles compiled from the same provider carry distinct, non-overwritten warning lists** (pinned by the N1 fixture in Part 6).
> - **Warnings element type is SYMBOLS, not strings (S-g).** Schema keys arrive as **symbols** (Racket's `json` reader: `{"minLength":3}` → `'minLength`), so the natural result of collecting unrecognized hash-keys is a `(listof symbol?)`. The committed element type is therefore **symbols** — `(provider-warnings-for provider handle)` returns e.g. `'(minLength)` / `'(ipv4)` / `'(multipleOf)`. Every warnings fixture asserts membership with a **symbol** (`(memq 'minLength (provider-warnings-for P h))`), NOT a string — the same symbol/string boundary S8 pinned for `required`. (For the unknown-`format` case the recorded element MAY be the format symbol `'ipv4` or a `'(format . ipv4)`-style marker; pin the chosen form and keep all fixtures consistent with it.)
> - **Cardinality is pinned on the RECORDED LIST (the load-bearing channel), as a conjunction, NOT an either/or (N2).** The recorded ignored-keyword list for a handle MUST have **identical length after 3 `validate` calls as after 0** — i.e. `validate` NEVER appends to it. This is the primary warn-once assertion. If a stderr line is also emitted, it too fires once at compile, but stderr cardinality is a *documented side effect*, not the load-bearing test.
> - **Emission/capture method must MATCH (N3).** If a stderr line is emitted it MUST use **`eprintf` / `(fprintf (current-error-port) …)`** (so a `(parameterize ([current-error-port (open-output-string)]) …)` capture is valid). `log-warning` writes to the logging system, NOT `current-error-port`, so a `current-error-port` capture of a `log-warning` impl captures NOTHING and a "exactly one warning" stderr assertion passes **vacuously** — forbidden. Recommended (cleanest): make the **recorded list** the warn-once oracle and treat stderr as documented-but-not-cardinality-tested; if the impl uses `log-warning`, the test MUST attach a `make-log-receiver` and count events there rather than capturing `current-error-port`.

> **Why ignore-with-warning, not reject:** a default provider must not hard-fail a schema merely because it carries a `minLength` it can't yet enforce; the supported keywords still provide real validation, and the recorded ignored-list + the documented unsupported-list make the gap visible. (Reject was the considered alternative — rejected because it makes the default provider brittle against perfectly ordinary schemas.) **Warning cardinality is committed to once-at-compile, asserted on the recorded list** (the original line-45-vs-Part-6 contradiction is resolved in favor of compile-time): compiling a schema with a deferred keyword records it once; the resulting handle, `validate`d N times, leaves the recorded list **unchanged in length**.

> **Recording is a COMPILE-time property, independent of the validate verdict (S-b).** The ignored-keyword list is populated by `provider-compile` from the *schema*, before any value is seen. So `{type:"string", format:"ipv4"}` records `ipv4` even when a later `validate` rejects the value on `type` — the record reflects what the schema asked for, not whether validation passed. Pinned in Part 6.

The forbidden behaviour is **silently honoring the appearance of support** — e.g. accepting `{ type: "string", minLength: 3 }` for `"ab"` as if `minLength` were enforced WITHOUT recording that `minLength` was ignored. Under ignore-with-warning the value is accepted *because the keyword is skipped* (warned + recorded), not because it was checked.

> **Minimal-deps decision (record in module docs).** The module docs MUST record the **hand-rolled-subset-vs-library** decision as a justified Minimal-deps choice: the default is a hand-rolled keyword subset (no external JSON-Schema library) because vision §6 (Minimal-deps NFR) and §8 (Ajv/cfWorker exclusions) call for it, and the port (item 010) exists precisely so a vetted library provider can be swapped in later **without changing callers**. State this explicitly in a module-level doc block alongside the supported/deferred keyword tables.

### Error path enrichment — the Racket-native job item 010 left open

Item 010 defined `(validation-error path message)` with `path` a list of JSON-Pointer-ish segments (string keys + integer array indices; `'()` = root) but, being port-only, **left `path` always-root** in its stub. **This item is the first to POPULATE `path` from real per-keyword evaluation.** Nested failures MUST carry their location:

- a failing `properties` sub-schema at key `"name"` → path segment `"name"` prepended;
- a failing `items` element at index `0` → integer segment `0` prepended;
- a nested `properties` → `items` → `properties` failure → the full path, e.g. `'("data" "items" 0 "name")` (string/integer segments interleaved), exactly the mixed-path shape item 010 pinned as a test.

`message` is a human-readable per-keyword failure string (e.g. `"expected string, got 123"`, `"missing required property: name"`, `"value not in enum"`). `validation-ok` carries the validated value unchanged (↔ TS `data`).

### Object-key representation — the symbol-vs-string boundary (S8, MUST get right)

Racket's `json` reader parses JSON object keys as **symbols** (e.g. `{"name":…}` → `(hasheq 'name …)`), but a JSON Schema's `required` array members and `properties` keys arrive as **strings** (`required` is a JSON array of strings; `properties` is a JSON object whose *own* keys are symbols when the schema itself is a parsed jsexpr). The evaluator MUST bridge this:
- **`required`** — each required entry is a **string** `req`; the presence check MUST be `(hash-has-key? value (string->symbol req))`, NOT `(hash-has-key? value req)`. A naïve string lookup against a symbol-keyed hash reports **every** key missing → **every object fails `required`** (a silent, total-failure bug). Pin with a present-required-key **accept** test.
- **`properties`** — the schema's `properties` is itself a parsed jsexpr `hasheq` whose keys are **symbols**; the value's keys are also symbols. Matching a property's sub-schema to a value field is a **symbol-to-symbol** lookup. Document the assumption that both schema and value are parsed jsexprs (symbol keys); a caller passing a string-keyed hash is out of contract.

State this symbol/string boundary explicitly in the module docs and pin it with the accept test (the failure mode is invisible without it — a wrong implementation rejects *every* object yet still "passes" any test that only checks rejects).

### Format-recognizer rigor — recognizers MUST reject adversarial inputs (C6)

A recognizer that merely `(regexp-match? #rx"@" s)` for email passes the easy TS reject (`"invalid-email"`) yet wrongly **accepts** `"@"`, `"a@@b"`, `"example.com"` — making the format check security-theatre. Each recognizer MUST therefore:
- reject **≥1 adversarial input beyond the TS pair** (see the C6 fixtures in Testing Strategy), AND
- have **one concrete documented limitation** stated in the module docs, so the "limitations noted in module docs" ask is falsifiable rather than vacuous.

Recommended recognizer shapes + their documented boundary:
- **email** — a pragmatic `local@domain` check requiring exactly one `@`, a non-empty local part, and a domain containing a `.`; **documented limitation:** not full RFC 5322 (e.g. quoted local parts, comments, IP-literal domains are not handled). MUST reject `"a@"`, `"@b.com"`, `"a b@c.com"` (and `"a@b"` either rejected, or its acceptance documented as the no-dot limitation — pick and pin one).
- **uri** — requires a scheme (`scheme:` prefix per a pragmatic regex); **documented limitation:** scheme-presence + shape only, not full RFC 3986 (no host/path component validation). MUST reject `"example.com"` (scheme-less) and `"://example.com"` (empty scheme); accept-or-document `"mailto:x@y.com"`, `"urn:isbn:123"`. **MUST NOT use `net/url`** (banned by portability — see Imports).
- **date-time** — an ISO-8601 *shape* check (`YYYY-MM-DDThh:mm:ss` + optional fractional seconds + `Z`/offset) via regex; **documented limitation:** shape-only — it does NOT range-check fields, so `"2025-13-01T00:00:00Z"` (month 13) is **accepted** (documented), while `"not-a-date"` is rejected. State this boundary explicitly so the test asserts the documented behaviour, not an assumed range check.

### Imports — S1 + the item-010 port ONLY

The module requires:
- `mcp/core/main.rkt` (the S1 barrel: types M1 + errors M2 — for the `jsexpr` notion / `json-null` and, if the deferred-keyword policy is **reject**, the error constructors `make-mcp-error` / `make-protocol-error`); and
- the item-010 port module `mcp/core/validators/provider.rkt` (for `gen:json-schema-validator-provider`, `provider-compile`, `validate`, `compiled-validator`, `validation-ok`, `validation-errors`, `validation-error`).

It MUST NOT require any transport, engine, role, subprocess, or socket module. Restricted-load portability MUST stay clean (no subprocess/socket pulled in) — the item-008 / item-010 walk mechanism is reused (this item's test runs a `from-json-schema.rkt`-rooted load check, and item 017 adds the collection-wide sweep).

### Scope guard (explicit — do NOT cross these lines)

- **Implements the item-010 port AS-IS.** Do NOT redefine the result structs or the generic — `require` them from `provider.rkt`. This item supplies a `struct` that implements `gen:json-schema-validator-provider` plus the keyword evaluator the handle's closure calls.
- **Supported subset ONLY** (the six keyword families above). Deferred keywords + unknown formats + unknown keywords get the documented ignore-with-warning policy, NOT a real implementation. Combinators (`allOf` / `anyOf` / `oneOf` / `not`), `$ref` / `$id` resolution, tuple `items` / `prefixItems`, `minItems` / `maxItems`, and `const` (an enum-of-one is the substitute if needed) are **out of scope** (combinators + `$ref` fall under the unknown-keyword ignore-with-warning catch-all, S3). **Pure annotation keys** — `$schema`, `$id`, `title`, `description`, `default`, `examples` — are *ignored harmlessly and WITHOUT a warning* (they carry no validation semantics, are present in the TS fixtures, and MUST NOT cause failures NOR suppress a real failure — pinned by S2: `{type:"string", title:"X", default:"z"}` on `42` still rejects on `type`).
- **NO schema normalization** (contract-or-JSON-Schema bridging) — that is item 012.
- **NO new port surface.** This item adds `from-json-schema.rkt`'s own provider struct + a constructor (e.g. `make-racket-native-provider`) to `provide`; it does NOT widen `provider.rkt`'s exports.

---

## Acceptance Criteria

- [x] `mcp/core/validators/from-json-schema.rkt` exists as `#lang racket/base` (or `#lang racket`) with an explicit, curated `provide` (no `(provide (all-defined-out))`).
- [x] The module defines a `struct` (e.g. `racket-native-provider`) that **implements `gen:json-schema-validator-provider`** from `provider.rkt` (`#:methods gen:json-schema-validator-provider [(define (provider-compile p schema) …)]`), and provides a constructor (e.g. `make-racket-native-provider` or the struct constructor) on the public surface. `(json-schema-validator-provider? (make-racket-native-provider))` → `#t`.
- [x] `provider-compile` returns a `compiled-validator?` handle (item-010 type) whose `validate` closure evaluates the supported keyword subset; the same handle is reusable across many `validate` calls (no per-call mutable state — tested).
- [x] **Error-collection policy = COLLECT-ALL (C1).** When a value violates multiple sibling keywords / multiple properties / multiple array elements, the `validation-errors` list contains **one `validation-error` per independent failure** — the evaluator does NOT short-circuit at the first error. Pinned: `{type:object, properties:{name:{type:string}, age:{type:number}}, required:["name"]}` on `{age:"x"}` → `validation-errors` of **exactly 2** (missing `required` name + `properties` age-type). `{type:string, enum:["a","b"]}` on `42` → exactly 2 (type + enum). (Within a single scalar leaf, one error is fine; siblings are all collected.)
- [x] **`type` keyword** — accept + reject for EACH of `string` / `number` / `integer` / `boolean` / `object` / `array` / `null`. Specifically: `"string"` accepts a string + rejects a number; `"number"` accepts `42` AND `3.14` + rejects `"42"`; `"integer"` accepts `42` + **rejects `3.14`** (integer-vs-number distinction); `"boolean"` accepts `#t`/`#f` + rejects `1` and `"true"`; `"object"` accepts a `hasheq` + rejects a list; `"array"` accepts a list + rejects a `hasheq`; `"null"` accepts `(json-null)` + rejects `0`/`#f`/`""`.
- [x] **Numeric `type` edge cases (S5).** Under `{type:"integer"}`: `42` accepts, `3.14` **rejects**, `42.0` (inexact) **rejects** (a JSON integer is exact — recognizer is `exact-integer?`, NOT `integer?` which is true of `42.0`), `(/ 84 2)` = exact `42` accepts, `(expt 10 100)` (bignum) accepts. Under `{type:"number"}`: `42`, `3.14`, and the bignum accept; **pin + document** the verdict for `+nan.0` / `+inf.0` (recommended: `rational?`/`real?`-without-special — document which, since `(number? +nan.0)` is `#t` but a JSON number cannot be NaN/Inf). The `42.0`-rejects-under-integer (inexact-integer trap) MUST be an explicit test.
- [x] **`object` / `properties` keyword** — accept a value whose present properties all validate; reject a value where a present property violates its sub-schema, with the failing property's key as a `path` segment (symbol→string in the path is documented; pin the produced segment form). Absent (non-required) properties do NOT cause failure.
- [x] **`properties`/`required` on a NON-object value MUST return `validation-errors`, NOT raise (C2).** `{type:object, properties:{name:{type:string}}, required:["name"]}` on each of `42` / `"str"` / `'(1 2 3)` / `(json-null)` returns a clean type-mismatch `validation-errors` (no Racket contract error). The **no-`type` variant** `{properties:{name:{type:string}}, required:["name"]}` (legal schema, no `type` guard) on `42` ALSO returns `validation-errors` (a clean "expected object" error) and does NOT raise — the structural keywords self-guard on `hash?`.
- [x] **`required` keyword** — accept a value containing all required keys; reject a value missing a required key, with a `message` naming the missing key (path = the object's path, or the missing-key segment per the documented convention — pin whichever is chosen). **Empty `required` (`[]`)** accepts every object. The **symbol/string key bridge (S8)** is correct: `required` members are strings, the value's keys are symbols, presence is checked via `(hash-has-key? value (string->symbol req))` — a present-required-key **accept** test pins this (a naïve string lookup would make every object fail `required`).
- [x] **`enum` keyword** — accept a value `equal?` (deep structural compare) to a listed member; reject a value not in the list. A **heterogeneous** enum (`'("option1" 42 #t (json-null))`) accepts each listed member of its respective type and rejects an unlisted value (mirrors the TS mixed-type enum fixture). `(json-null)` as an enum member matches a `(json-null)` value (not `#f`/`0`).
- [x] **`enum` edge cases (S4).** **Empty `enum` (`[]`)** rejects EVERY value (no member can match). **Duplicate members** (`["a","a"]`) accept `"a"` without crash. **Compound member** (`(hasheq 'a 1)` as an enum member) accepts a structurally-equal `(hasheq 'a 1)` value via `equal?` deep compare — catches an `eq?`/`eqv?`-based membership that would reject a fresh-but-equal hash.
- [x] **`items` keyword** — accept an array whose every element validates against the `items` sub-schema (incl. the **empty array**, which trivially accepts); reject an array with any non-conforming element. Under **collect-all (C1/S6)**, EVERY failing element contributes its own error with that element's **integer index** as a `path` segment. **Nested `items` + `properties`** path construction is tested: an `array` of `object`s where elements fail carries paths like `'(0 "name")` AND `'(1 "name")` for `[{name:123},{name:456}]` (both present — proves the index is not hard-coded to the first failing element).
- [x] **`items` on a NON-array value MUST return `validation-errors`, NOT raise (C3).** `{type:array, items:{type:string}}` on `(hasheq 'a 1)` and on `42` returns a clean type-mismatch `validation-errors` (no `map`/iteration crash). The **no-`type` variant** `{items:{type:string}}` on a non-list ALSO self-guards and returns `validation-errors` (does not attempt to iterate). When `type` AND `enum` co-occur (`{type:string, enum:["a","b"]}`): `42` fails both (count per C1 = 2), `"c"` fails enum but passes type (count = 1).
- [x] **`format` keyword** (string formats) — accept + reject for EACH of `date-time` (`"2025-10-17T12:00:00Z"` accepts, `"not-a-date"` rejects), `uri` (`"https://example.com"` accepts, `"not-a-uri"` rejects), `email` (`"user@example.com"` accepts, `"invalid-email"` rejects).
- [x] **Recognizer rigor — adversarial rejects + documented limitation per format (C6).** Each recognizer rejects **≥1 adversarial input beyond the TS pair** AND has **one concrete documented limitation** in the module docs: email rejects `"a@"`, `"@b.com"`, `"a b@c.com"` (and `"a@b"` rejected-or-documented); uri rejects `"example.com"` (scheme-less) and `"://example.com"` (empty scheme); date-time is a documented ISO-8601 *shape* check that ACCEPTS `"2025-13-01T00:00:00Z"` (no range check — the documented limitation) and rejects `"not-a-date"`. A bare `(regexp-match? #rx"@" s)`-style recognizer that passes the TS pair but accepts `"@"`/`"a@@b"` MUST fail these criteria.
- [x] **`format` on a non-string + unknown formats (C5).** `{format:"email"}` (no `type`) on `42` **accepts** — `format` is a no-op on non-strings, recognizer does NOT run (no crash). `{type:"string", format:"email"}` on `42` **rejects on `type`** and the recognizer still does not run. An **unknown format** `{type:"string", format:"ipv4"}` on `"1.2.3.4"` **accepts on the supported keywords** and routes the unknown format through the ignore-with-warning policy (skipped + warned once at compile + recorded) — NOT silently treated as a passing constraint, NOT treated as a known format.
- [x] **Deferred-keyword policy = ignore-with-warning, UNIFORM across all five, recorded ONCE at compile (C4).** EACH of `pattern`, `minLength`/`maxLength`, `minimum`/`maximum`, `additionalProperties`, `uniqueItems` is **skipped** (does NOT affect accept/reject) and its **symbol** is **recorded in the per-compile ignored-keyword list** read via `(provider-warnings-for P h)` (a `(listof symbol?)`, S-g; NOT a `compiled-validator` field). **Uniformity is asserted:** all five exhibit the SAME policy (none rejects while another warns) — for each, `{type:string, <deferred>:…}` on a value the deferred keyword *would* reject is **accepted** (the supported `type` part still rejects a non-string), and the keyword symbol appears in the recorded list (`(memq 'minLength (provider-warnings-for P h))` etc.). `(check-not-exn (lambda () (provider-compile P <each-deferred-schema>)))` for all five (none is on the reject path). **Warn-once cardinality is asserted on the RECORDED LIST (N2):** a handle compiled from a deferred-keyword schema, `validate`d 3×, has a recorded ignored-keyword list of **identical length after 3 validates as after 0** (validate NEVER appends). If a stderr line is also emitted it uses `eprintf`/`current-error-port` (NOT `log-warning`) so a string-capture is valid (N3) — but the recorded-list length is the load-bearing oracle. Each deferred keyword is **listed by name in the module docs**.
- [x] **Per-compile-keyed warnings — two handles from one provider stay distinct (N1).** From ONE provider instance, `h1` compiled from `{type:"string", minLength:3}` and `h2` from `{type:"string", pattern:"x"}`: `(provider-warnings-for P h1)` names `'minLength` (and NOT `'pattern`), `(provider-warnings-for P h2)` names `'pattern` (and NOT `'minLength`) — proving warnings are keyed per handle in the provider's weak map, NOT stored in a single provider-level slot a second compile would overwrite. (A single-mutable-slot impl would pass every other warnings assertion — each reads right after its own compile — while being broken for item 012, which compiles many schemas through one provider; this fixture is what catches it.)
- [x] **Unknown non-deferred keyword policy (S3).** A genuinely-unknown keyword outside both the supported and deferred lists (`multipleOf`, `propertyNames`, `$ref`, a combinator like `allOf`) is handled by the SAME ignore-with-warning catch-all (skipped + warned-once-at-compile + recorded), so no keyword is ever *silently* honored. Pure annotation keys (`$schema`/`$id`/`title`/`description`/`default`/`examples`) are ignored WITHOUT a warning (S2).
- [x] **Annotation keys must not suppress a real failure (S2).** `{type:"string", title:"X", description:"Y", default:"z"}` on `42` still produces a `validation-errors` (the annotations did not suppress the `type` failure, nor did they trigger a spurious warning).
- [x] **Empty / degenerate schemas (S1).** `{}` (empty schema) **accepts every value** (`42`, `(json-null)`, `(hasheq)`). `{type:"object"}` with no `properties`/`required` accepts `(hasheq 'whatever 1)` and `(hasheq)`. `{required:["name"]}` with no `properties` still **enforces presence** (rejects an object lacking `name`, accepts one with it) — pin whether a no-`type` `required`-only schema applies to non-objects per the C2 self-guard rule.
- [x] **Provider statelessness across schemas (S7).** From ONE provider instance, `h1` compiled from `{type:"string"}` and `h2` from `{type:"number"}`: `"hi"` is `validation-ok?` for `h1` and `validation-errors?` for `h2` (catches module-level mutable / memoized last-schema state).
- [x] **Errors carry real path + message.** On a nested failure the produced `validation-errors` contains a `validation-error` whose `path` reflects the failure location (string keys + integer indices, `'()` for a root/top-level type mismatch) and whose `message` is a non-empty human-readable string — populated from actual per-keyword evaluation, NOT a hard-coded root error. The **mixed-path** `'(… 0 …)` case (item-010's pinned shape) is produced by a real nested-`items` failure, and (per S6/collect-all) a two-failing-element array yields BOTH `'(0 "name")` and `'(1 "name")`.
- [x] **TS-baseline cross-check (supported subset).** For each of `type`, `object`/`properties`, `required`, `enum`, `string`-`format`, at least one accept + one reject case uses the **same schema + value** as a fixture in `typescript-sdk/packages/core/test/validators/validators.test.ts`, and the Racket provider produces the SAME accept/reject verdict the TS test asserts (`valid:true` ↔ `validation-ok?`, `valid:false` ↔ `validation-errors?`). Fixtures from deferred-keyword TS tests (`minLength`, `pattern`, `minimum`, `additionalProperties`, `uniqueItems`, `allOf`/`anyOf`/`oneOf`/`not`) are explicitly NOT used as accept/reject oracles — they exercise unsupported features. The cross-check methodology (which fixtures, how parity is asserted) is documented in the test file header.
- [x] **C1×C4 interaction — ignored keywords contribute ZERO errors (S-a).** A deferred keyword does NOT add a phantom error to the collect-all list. `{type:"number", minimum:0}` on `"x"` → **exactly 1** error (the `type` failure; `minimum` is ignored and contributes 0 errors — NOT a `"minimum: skipped"` pseudo-error that would push the count to 2). Pins that "skipped" means truly skipped, not "reported as a skip-error".
- [x] **Recording is compile-time, independent of validate verdict (S-b).** `{type:"string", format:"ipv4"}` on `42` → **exactly 1** error (`type`), AND the handle's recorded ignored-keyword list STILL names `ipv4` even though the value failed `type` — proving the record reflects the schema (a compile-time property), not whether validation passed.
- [x] **Malformed deferred-keyword VALUE — chosen branch is tested (S-c).** A deferred keyword whose value is itself malformed, e.g. `{type:"string", minLength:"three"}` (non-integer `minLength`): the implementer picks raise-at-compile OR ignore-with-warning, **and the chosen branch has a test** — `check-exn` if raise, accept+record if ignore. The path is NOT left uncovered. (Record the choice in Decisions.)
- [x] **Malformed NESTED sub-schema — recursion policy pinned (S-d).** `{type:"object", properties:{name:{type:"stringg"}}}` (a bad `type` in a *sub*-schema): pin whether `check-schema-shape` **recurses into sub-schemas** (recommended: recurse → fail-fast at compile → `check-exn` that it raises at compile) vs defers the malformed sub-schema until a value descends into `name`. Recommended = recurse + compile-time raise; whichever is chosen is documented + tested.
- [x] **`enum` nested in structure carries a located path (S-e).** `{type:"object", properties:{color:{enum:["red","green"]}}}` on `{color:"blue"}` → `validation-errors` with a `validation-error` whose `path` is `'("color")` (enum errors are LOCATED like type errors via the `properties` descent, NOT hard-coded to root `'()`).
- [x] **Empty `properties` hash vs absent `properties` key (S-f).** `{type:"object", properties:{}}` (present-but-empty `properties`) on `(hasheq 'anything 1)` → **accepts**, no crash (distinguishes an absent `properties` key from an empty `properties` hash; a `hash-ref schema 'properties` WITHOUT a default would crash on the absent-key case — both branches MUST be guarded with a default).
- [x] **Malformed-schema compile policy (fail-fast precedent inherited from item 010).** `provider-compile` on a structurally malformed schema (non-`hasheq` schema, a `properties` whose value is not an object-of-subschemas, a `type` whose value is not a recognized type string, an `enum` that is not a list) **fails fast** — raises via an S1 error constructor — rather than deferring to validate time or silently passing. Asserted via `check-exn`. (This matches item 010's documented compile-on-garbage precedent.)
- [x] The module imports **only S1** (`mcp/core/main.rkt`) **and the item-010 port** (`provider.rkt`). It requires NO transport/engine/role/subprocess/socket module. **Verified by a restricted-namespace load test** whose entry point is **`from-json-schema.rkt` itself**: a fresh `(make-base-namespace)` requiring it and walking `module->imports` transitively shows EMPTY intersection with the banned set (`racket/system racket/tcp racket/udp net/url net/http-client net/sendurl racket/sandbox racket/port`). **Note:** if a `format`-`uri` recognizer is tempted to use `net/url`, it MUST NOT — `net/url` is in the banned set; use a string/regex recognizer instead (documented).
- [x] `raco test mcp/core/validators/` passes (exit 0) — module + new test compile and run cleanly within the collection, alongside item 010's `provider-test.rkt`.
- [x] `raco make mcp/core/validators/from-json-schema.rkt` exits 0 (compiles clean, no warnings about missing/non-portable modules).
- [x] Parity-matrix discipline: per Stage S2 the `validators/*` row advances toward `partial` (the default provider's supported-keyword exercise now exists; full conformance lands with items 017/018 and S9). Update `docs/aide/progress.md` per the Completion Reminder — flip the `from-json-schema.rkt` deliverable line AND check the Stage-S2 **validator keyword-coverage** acceptance box (this item owns it).

---

## Implementation Steps

1. **Read the framing sources once more for shape + oracle:** `typescript-sdk/packages/core/src/validators/fromJsonSchema.ts` (wrapper shape — schema-in / validate-fn-out / value-on-success / message-on-failure) and `typescript-sdk/packages/core/test/validators/validators.test.ts` (the behavioural oracle; identify which fixtures fall in the **supported subset** vs the deferred/excluded set — see Testing Strategy for the exact fixture map). Re-read item 010's `provider.rkt` surface (`docs/aide/items/010-validator-provider-port.md` Description §1–§3) so you require, not redefine, the port + result types.
2. **Confirm the S1 surface you need:** `(json-null)` from `json` (re-exported through the S1 barrel or `require json` directly — record which), and, if the deferred policy is **reject**, `make-mcp-error` / `make-protocol-error` from `mcp/core/main.rkt`.
3. **Write `mcp/core/validators/from-json-schema.rkt`.** Use `#lang racket/base`. In order:
   - `(require racket/generic racket/list "../main.rkt" "provider.rkt")` plus `json` if `(json-null)` is needed directly; `racket/contract` only if attaching `contract-out`.
   - A module-level **doc block** recording: the Minimal-deps hand-rolled-subset decision; the supported-keyword table; the deferred-keyword table + **the committed ignore-with-warning policy (warned once at compile)**; the unknown-format + unknown-keyword catch-all routing through the same policy; the symbol/string object-key boundary; and the **`format` recognizer choices + one concrete documented limitation each**.
   - A **compile-time schema validator** `(check-schema-shape schema)` that (a) **fail-fasts** (via `make-mcp-error`/`make-protocol-error`) on *structurally malformed* schemas (non-hash, `properties` not an object-of-subschemas, `type` not a recognized type string, `enum` not a list) and (recommended, S-d) **recurses into sub-schemas** (`properties` values, `items`) applying the same shape check so a bad nested `type` raises at compile; and (b) **collects the ignore-with-warning keyword set** (deferred + unknown-format + unknown keywords present) for *this* schema, returning that list so the compile can record it per-handle. Malformed-shape = raise; deferred/unknown = record (the two policies are distinct and both pinned). Pin the S-c choice (malformed deferred-keyword *value*) here: either add it to the raise set or to the recorded-ignore set.
   - A **recursive collect-all evaluator** `(evaluate schema value path)` → `(listof validation-error)` (empty = ok), threading `path` and prepending string keys / integer indices on descent into `properties` / `items` (so a nested `enum`/`type` failure is LOCATED, S-e). **Each keyword family contributes its errors and ALL are appended (collect-all, C1) — do NOT short-circuit across siblings; an ignored keyword contributes ZERO errors (S-a).** **Each structural keyword type-guards the value first (C2/C3/C5):** `properties`/`required` check `hash?` (else emit one clean "expected object" error and skip descent), `items` checks `list?` (else "expected array" + skip), `format` checks `string?` (else skip silently). Read `properties`/`required`/`enum`/`items` with a **default** (`(hash-ref schema 'properties #f)` etc.) so an absent key is distinct from an empty value (S-f). The `required` presence check uses `(hash-has-key? value (string->symbol req))` (S8).
   - The provider **struct** implementing `gen:json-schema-validator-provider`, carrying a **`(make-weak-hasheq)`** mapping produced handle → ignored-keyword list (a `(listof symbol?)`, S-g). Because item 010's `compiled-validator` is a frozen single-field struct that may NOT be widened, the ignore-list lives on item 011's own `racket-native-provider` keyed by the handle — **NOT** a `(values handle warnings)` return (changes the port's generic arity — rejected) and **NOT** a single provider-level mutable slot (overwritten by the next compile — rejected). `provider-compile` runs `check-schema-shape` once (raising on malformed, computing the ignore-list for this schema), produces a single `compiled-validator?` exactly as the port requires, stores `handle → ignore-list` in the weak map, and returns the handle. The closure runs `(evaluate schema v '())` and maps empty→`(validation-ok v)` / non-empty→`(validation-errors errs)`; it NEVER touches the ignore-list (warn-once = compile-time; validate does not append — N2). If a stderr line is emitted it uses `eprintf` (NOT `log-warning`, so a `current-error-port` capture is valid — N3).
   - A constructor (`make-racket-native-provider`) + the read accessor `(provider-warnings-for provider handle)` (returns the handle's `(listof symbol?)`), and the explicit `(provide …)` block (struct predicate/constructor + constructor proc + `provider-warnings-for`; NOT the internal `evaluate`/`check-schema-shape` helpers; NOT a re-export of the port — callers `require` the port directly for the result API).
4. **Write the test** `mcp/core/validators/test/from-json-schema-test.rkt` (see Testing Strategy). Cover every supported keyword (accept+reject), the collect-all error count (C1), the non-object/non-array clean-rejection (C2/C3), the numeric edges (S5), the symbol/string `required` accept (S8), the enum edges (S4), the format non-string + unknown-format routing (C5) + adversarial rejects + documented limitations (C6), the empty/degenerate schemas (S1), annotations-don't-suppress (S2), unknown-keyword policy (S3), provider statelessness (S7), the deferred-keyword uniform ignore-with-warning + warn-once (C4), the path construction incl. both-elements (S6), the malformed-schema fail-fast, the TS-baseline cross-check block, and the restricted-load portability sub-test (reuse the item-008/010 walk helper; entry point = `from-json-schema.rkt`).
5. **Run** `raco make mcp/core/validators/from-json-schema.rkt` then `raco test mcp/core/validators/`. Fix any failure. Confirm item 010's `provider-test.rkt` still passes alongside.
6. **Update progress + parity matrix** (see Completion Reminder).

---

## Testing Strategy

The test is a **behavioural keyword-coverage test** for the supported subset, with a **TS-baseline cross-check** (the supported fixtures from `validators.test.ts`), the **deferred-keyword policy** pinned per keyword, **edge cases** for every tricky semantic, the **fail-fast compile** precedent, **path-construction** assertions, and the **restricted-load portability** sub-test. Result-shape mechanics (the `validation-ok`/`validation-errors`/`validation-error` API, the non-empty guard, opacity) are already covered by item 010's `provider-test.rkt` and are NOT re-litigated here — this test asserts *verdicts and paths*, requiring the result API from the port.

**Test file:** `mcp/core/validators/test/from-json-schema-test.rkt` (`#lang racket/base`; `(require rackunit json "../from-json-schema.rkt" "../provider.rkt")` plus `racket/set`/`racket/path` for the portability walk). `json` is needed for `(json-null)`.

A few small helpers make the verdict assertions terse and readable:
```racket
(define P (make-racket-native-provider))
(define (accepts? schema value)
  (validation-ok? (validate (provider-compile P schema) value)))
(define (rejects? schema value)
  (validation-errors? (validate (provider-compile P schema) value)))
;; (errs schema value) -> (validation-errors-errors (validate (provider-compile P schema) value))
;;   for count/path assertions (one compile, one validate).
;; (errs-from h value) -> same but over an ALREADY-compiled handle h (for S-b: assert the verdict
;;   on a handle whose warnings you separately inspect via provider-warnings-for).
;; (provider-warnings-for P h) -> the handle's recorded ignored-keyword list, a (listof symbol?) (S-g);
;;   membership is checked with SYMBOLS: (memq 'minLength (provider-warnings-for P h)).
;; NOTE: provider-compile MUST NOT raise for the C2/C3/C5 cases — those are clean validate-time rejects,
;;   not compile errors (a raise = test failure). It DOES raise for the malformed-shape + S-d cases.
```

### Part 1 — `type` keyword, all seven types + the hard edge cases

For each of the seven `type` values, at least one accept and one reject, with the edge cases pinned explicitly:
- `"string"` — accepts `"hi"`; rejects `123` (TS: "validates basic string").
- `"number"` — accepts `42` AND `3.14`; rejects `"42"` (TS: "validates number type").
- `"integer"` — accepts `42`; **rejects `3.14`** (the integer-vs-number distinction). (TS: "validates integer type".)
- `"boolean"` — accepts `#t` and `#f`; rejects `1` and `"true"` (TS: "validates boolean type").
- `"object"` — accepts `(hasheq 'a 1)`; rejects `'(1 2 3)` and a string.
- `"array"` — accepts `'(1 2 3)`; rejects `(hasheq 'a 1)`.
- `"null"` — accepts `(json-null)`; rejects `0`, `#f`, `""`. **Pin the `null`-vs-`(json-null)` semantic:** JSON `null` is represented as `(json-null)` (which is `'null` by default in Racket's `json`); the test asserts the provider matches `(json-null)` and NOT Racket `'()` or `#f`. Document the representation assumption.

**Numeric edges (S5) — explicit fixtures, `{type:"integer"}` and `{type:"number"}`:**
- `(accepts? (hasheq 'type "integer") 42)` → `#t`; `(rejects? (hasheq 'type "integer") 3.14)` → `#t`; **`(rejects? (hasheq 'type "integer") 42.0)` → `#t`** (inexact-integer trap — `42.0` is NOT a JSON integer; recognizer is `exact-integer?`, not `integer?`); `(accepts? (hasheq 'type "integer") (/ 84 2))` → `#t` (exact `42`); `(accepts? (hasheq 'type "integer") (expt 10 100))` → `#t` (bignum).
- `{type:"number"}` accepts `42`, `3.14`, and the bignum. **Pin + document** `+nan.0` / `+inf.0`: assert the chosen verdict (recommended: rejected — a JSON number is finite/rational) and note the documented choice in the test header.

### Part 2 — `object` / `properties` / `required` (incl. C1 collect-all, C2 non-object, S8 symbol/string)

- `properties` accept: `{type:object, properties:{name:{type:string}, age:{type:number}}, required:["name"]}` accepts `{name:"John", age:30}` AND `{name:"John"}` (age absent is fine) (TS: "validates simple object").
- `properties` reject + path: the same schema rejects `{name:123}` (name present but wrong type); assert the produced `validation-error`'s `path` contains the `name` key segment.
- `required` reject + message: the same schema rejects `{age:30}` and `{}` (name missing); assert a `message` naming `name`.
- **S8 symbol/string `required` ACCEPT (the silent-total-failure guard):** `(accepts? (hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string")) 'required '("name")) (hasheq 'name "John"))` → `#t`. This pins that the string `"name"` in `required` is bridged to the symbol key `'name` in the value (a naïve `(hash-has-key? value "name")` would make this FAIL — every object would miss every required key).
- **C1 collect-all error COUNT:** `(errs (hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string") 'age (hasheq 'type "number")) 'required '("name")) (hasheq 'age "x"))` → a list of **exactly 2** `validation-error`s (missing-required `name` + wrong-type `age`). Assert `(= 2 (length …))` AND both are `validation-error?` — the headline C1 assertion that distinguishes collect-all from short-circuit.
- **C2 non-object value MUST return errors, not raise** — for each of `42`, `"str"`, `'(1 2 3)`, `(json-null)`:
  `(check-not-exn (lambda () (validate (provider-compile P (hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string")) 'required '("name"))) <v>)))` AND `(rejects? <that-schema> <v>)` → `#t`. Then the **no-`type` variant** `(hasheq 'properties (hasheq 'name (hasheq 'type "string")) 'required '("name"))` on `42`: `(check-not-exn …)` AND `(rejects? … 42)` → `#t` (the structural keywords self-guard on `hash?` — a clean "expected object" error, no contract crash).
- **Empty `required`** edge: `{type:object, properties:{}, required:[]}` accepts `{}` and `{anything:1}`.
- **Nested objects** (TS: "validates nested objects"): `{type:object, properties:{user:{type:object, properties:{name:{type:string}, email:{type:string, format:email}}, required:["name"]}}, required:["user"]}` accepts `{user:{name:"John", email:"john@example.com"}}` and `{user:{name:"John"}}`; rejects `{user:{email:"john@example.com"}}` (user.name missing) — assert path includes the `user` segment.
- **S-e nested `enum` carries a located path:** `(errs (hasheq 'type "object" 'properties (hasheq 'color (hasheq 'enum '("red" "green")))) (hasheq 'color "blue"))` → contains a `validation-error` whose `path` is `'("color")` (the enum failure is LOCATED via the `properties` descent, NOT hard-coded to root `'()`) — proves enum errors are path-enriched like type errors.

### Part 3 — `enum`, incl. heterogeneous + `null` member + edges (S4)

- Homogeneous string enum (TS: "validates enum values"): `{enum:["red","green","blue"]}` accepts each of `"red"`/`"green"`/`"blue"`; rejects `"yellow"`.
- **Heterogeneous enum** (TS: "validates enum with mixed types"): `{enum:["option1", 42, #t, (json-null)]}` accepts `"option1"`, `42`, `#t`, and `(json-null)`; rejects `"other"`. Assert `(json-null)` membership matches a `(json-null)` value and NOT `#f`/`0`.
- **S4 empty enum:** `(rejects? (hasheq 'enum '()) "x")` → `#t` (empty enum rejects EVERY value — no member can match).
- **S4 duplicate members:** `(accepts? (hasheq 'enum '("a" "a")) "a")` → `#t` (no crash, accepts).
- **S4 compound member (deep `equal?`):** `(accepts? (hasheq 'enum (list (hasheq 'a 1))) (hasheq 'a 1))` → `#t` — a fresh-but-structurally-equal hash matches via `equal?` (catches an `eq?`/`eqv?` membership that would wrongly reject).
- **C3 type+enum co-occurrence COUNT:** `(errs (hasheq 'type "string" 'enum '("a" "b")) 42)` → exactly 2 (fails type AND enum); `(errs (hasheq 'type "string" 'enum '("a" "b")) "c")` → exactly 1 (passes type, fails enum).

### Part 4 — `items`, incl. empty array, non-array (C3), nested + both-element paths (S6)

- Array of strings (TS: "validates array of strings"): `{type:array, items:{type:string}}` accepts `["a","b","c"]` AND `[]` (empty array trivially accepts); rejects `["a", 1, "c"]` — assert the failing element's **integer index** `1` appears in a produced error's `path`.
- **C3 non-array value MUST return errors, not raise:** for `(hasheq 'a 1)` and `42` under `{type:array, items:{type:string}}`: `(check-not-exn (lambda () (validate (provider-compile P …) <v>)))` AND `(rejects? … <v>)` → `#t` (no `map`/iteration crash). The **no-`type` variant** `{items:{type:string}}` on `(hasheq 'a 1)`: `(check-not-exn …)` AND `(rejects? … (hasheq 'a 1))` → `#t` (self-guards on `list?`, does not iterate).
- **S6 collect-all over array elements (both indices present):** `(errs (hasheq 'type "array" 'items (hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "string")) 'required '("name"))) (list (hasheq 'name 123) (hasheq 'name 456)))` → contains a `validation-error` whose path is `'(0 "name")` AND one whose path is `'(1 "name")` (assert BOTH present — proves the index is per-element, not hard-coded to the first failing element).
- **Nested `items` + `properties` mixed path:** `{type:array, items:{type:object, properties:{name:{type:string}}, required:["name"]}}` over `[{name:"ok"}, {name:123}]` rejects, producing a path `'(1 "name")` (integer index then string key). Also test the deeply-nested TS "API response" fixture (`data.items[].name`) to produce a `'("data" "items" 0 "name")`-style path on a crafted failing value.

### Part 5 — `format` (recognizer rigor C6, non-string + unknown-format C5)

**Accept/reject the TS pairs** for each of `date-time`/`uri`/`email`:
- `format:date-time` — accepts `"2025-10-17T12:00:00Z"`; rejects `"not-a-date"`.
- `format:uri` — accepts `"https://example.com"`; rejects `"not-a-uri"`.
- `format:email` — accepts `"user@example.com"`; rejects `"invalid-email"`.

**C6 adversarial rejects (beyond the TS pair) + documented limitation per recognizer:**
- email `{type:"string", format:"email"}` REJECTS `"a@"`, `"@b.com"`, `"a b@c.com"`; pin `"a@b"` (no dot) as rejected-or-documented (choose one, assert it). Documented limitation in test header + module docs: not full RFC 5322.
- uri `{type:"string", format:"uri"}` REJECTS `"example.com"` (scheme-less) and `"://example.com"` (empty scheme); accept-or-document `"mailto:x@y.com"`/`"urn:isbn:123"`. Limitation: scheme-shape only, not full RFC 3986.
- date-time `{type:"string", format:"date-time"}` is a documented ISO-8601 *shape* check: **ACCEPTS `"2025-13-01T00:00:00Z"`** (month 13 — no range check, the documented limitation) and rejects `"not-a-date"`. Assert the documented accept, so the limitation is falsifiable.

**C5 format on non-string + unknown format:**
- `(accepts? (hasheq 'format "email") 42)` → `#t` AND `(check-not-exn …)` — `format` with no `type` is a no-op on a non-string; recognizer does NOT run (no regexp-on-number crash).
- `(rejects? (hasheq 'type "string" 'format "email") 42)` → `#t` (rejects on `type`); assert no raise (recognizer still skipped on the non-string).
- **Unknown format** `(accepts? (hasheq 'type "string" 'format "ipv4") "1.2.3.4")` → `#t` (accepts on supported keywords; the unknown format `ipv4` is routed through ignore-with-warning — skipped, recorded once at compile). Assert `(provider-warnings-for P h)` (see Part 6) contains the symbol `'ipv4` (or the chosen unknown-format marker per S-g) — a SYMBOL, not a string.

### Part 6 — ignore-with-warning policy: uniform across five + warn-once on recorded list (C4/N2) + per-compile-keyed (N1) + emission/capture match (N3) + unknown keyword (S3) + annotations (S2)

The committed policy is **ignore-with-warning, recorded per-compile in the provider's weak handle→warnings map, recorded list is the load-bearing warn-once oracle**. The test reads warnings via the committed accessor `(provider-warnings-for P h)`, which returns the handle's recorded ignored-keyword list as a `(listof symbol?)` (S-g) — membership is checked with SYMBOLS. It does NOT read a `compiled-validator` field (item 010's struct is frozen). A `current-error-port` string-capture is a permitted **supplementary** assertion ONLY if the impl emits via `eprintf` (N3) — if the impl uses `log-warning`, the supplementary capture MUST use `make-log-receiver`, not `current-error-port` (which would capture nothing and pass vacuously).

- **Uniform across all five deferred keywords.** For EACH of `{type:"string", pattern:"^[A-Z]{3}$"}` on `"ab"`, `{type:"string", minLength:3}` on `"ab"`, `{type:"string", maxLength:1}` on `"abc"`, `{type:"number", minimum:0}` on `-1`, `{type:"number", maximum:100}` on `101`, `{type:"object", properties:{name:{type:"string"}}, additionalProperties:false}` on `{name:"x", extra:"y"}`, `{type:"array", items:{type:"number"}, uniqueItems:true}` on `[1,1]`:
  - the value a deferred keyword *would* reject is **ACCEPTED** (the deferred keyword is skipped) — `(accepts? <schema> <value>)` → `#t`;
  - BUT the supported part still works — e.g. `{type:"string", minLength:3}` on `123` (a number) `(rejects? …)` → `#t` (the `type` keyword still fires);
  - the compile **records** the ignored keyword — assert `(provider-warnings-for P h)` for that handle contains the deferred keyword **symbol** (e.g. `(memq 'minLength (provider-warnings-for P h))`).
- **Uniformity cross-check:** assert that NO deferred keyword causes `provider-compile` to RAISE (none is on the reject path) — `(check-not-exn (lambda () (provider-compile P <each-deferred-schema>)))` for all five. (This pins "the same policy applies to all five — none rejects while another warns".)
- **N1 per-compile-keyed, two handles from ONE provider stay distinct.** `(define h1 (provider-compile P (hasheq 'type "string" 'minLength 3)))` then `(define h2 (provider-compile P (hasheq 'type "string" 'pattern "x")))` from the SAME `P`. Assert `(memq 'minLength (provider-warnings-for P h1))` AND NOT `(memq 'pattern (provider-warnings-for P h1))`; `(memq 'pattern (provider-warnings-for P h2))` AND NOT `(memq 'minLength (provider-warnings-for P h2))`. This is the fixture a single-mutable-slot impl FAILS (the second compile would have overwritten the first) while passing every read-right-after-own-compile assertion.
- **N2 warn-once on the RECORDED LIST (conjunction, not either/or).** Compile `(define h (provider-compile P (hasheq 'type "string" 'minLength 3)))`. Capture `(define n0 (length (provider-warnings-for P h)))`. `validate` h 3× (`(validate h "ab")` etc.). Assert `(= (length (provider-warnings-for P h)) n0)` — the recorded list is **identical length after 3 validates as after 0** (validate NEVER appends). This is the primary, load-bearing warn-once check. ADDITIONALLY (supplementary), if a stderr line is emitted via `eprintf`, capture compile-time stderr in an `(open-output-string)` and assert exactly one line, and capture the three validates' stderr and assert it is empty — but the recorded-list length is the oracle.
- **S-a C1×C4 interaction — ignored keyword contributes ZERO errors.** `(errs (hasheq 'type "number" 'minimum 0) "x")` → a list of **exactly 1** (the `type` failure; `minimum` ignored, no phantom "minimum: skipped" pseudo-error). Assert `(= 1 (length …))`.
- **S-b recording is compile-time, independent of verdict.** `(define h (provider-compile P (hasheq 'type "string" 'format "ipv4")))`; `(errs-from h 42)` → exactly 1 (`type`), AND `(memq 'ipv4 (provider-warnings-for P h))` is true (or the chosen unknown-format marker per S-g) — the unknown format is recorded even though the value failed `type`.
- **S3 unknown (non-deferred) keyword:** `{type:"string", multipleOf:2}` (or `$ref`, `propertyNames`, an `allOf` combinator) on `"hi"` → ACCEPTS on the supported `type`, routes `multipleOf` through the SAME ignore-with-warning catch-all (skipped + recorded). Assert `(memq 'multipleOf (provider-warnings-for P h))`. `(check-not-exn (lambda () (provider-compile P <unknown-kw-schema>)))`.
- **S2 annotations must NOT warn or suppress:** `(define h (provider-compile P (hasheq 'type "string" 'title "X" 'description "Y" 'default "z")))`; `(validation-errors? (validate h 42))` → `#t` (annotations did NOT suppress the `type` failure), AND `(null? (provider-warnings-for P h))` → `#t` (pure annotations are ignored WITHOUT a warning — distinguishes them from deferred/unknown keywords).
- **Module-docs listing:** read `from-json-schema.rkt` as text and `regexp-match?` each deferred keyword name (`pattern`, `minLength`, `maxLength`, `minimum`, `maximum`, `additionalProperties`, `uniqueItems`) in the doc block (mirrors the TS `should document that … is required` pattern) — pins the "listed in module docs" criterion.

### Part 6b — empty/degenerate schemas (S1) + provider statelessness (S7)

- **S1 empty schema accepts everything:** `(accepts? (hasheq) 42)` / `(accepts? (hasheq) (json-null))` / `(accepts? (hasheq) (hasheq))` all → `#t`.
- **S1 `{type:"object"}` with no properties/required:** accepts `(hasheq 'whatever 1)` and `(hasheq)`.
- **S1 `{required:["name"]}` with no `properties`:** still enforces presence — accepts `(hasheq 'name 1)`, rejects `(hasheq)`. (And, per C2, a non-object value flows through the structural self-guard cleanly.)
- **S-f empty `properties` hash vs absent `properties` key:** `(accepts? (hasheq 'type "object" 'properties (hasheq)) (hasheq 'anything 1))` → `#t` and `(check-not-exn …)`. The present-but-empty `properties` hash MUST NOT crash (a `hash-ref schema 'properties` without a default would crash on the *absent*-key case `{type:"object"}` above — both the absent-key and empty-hash branches are guarded with a default, and BOTH accept).
- **S7 provider statelessness across schemas:** `(define h1 (provider-compile P (hasheq 'type "string")))` / `(define h2 (provider-compile P (hasheq 'type "number")))` — `(validation-ok? (validate h1 "hi"))` → `#t`, `(validation-errors? (validate h2 "hi"))` → `#t`, and the converse for `42`. Catches module-level mutable / memoized last-schema state in the provider.

### Part 7 — TS-baseline cross-check (the parity methodology, made explicit)

A dedicated test block headed with the methodology comment: *"Each case below uses the exact schema+value from `validators.test.ts` and asserts the Racket verdict equals the TS-asserted `valid`. Only fixtures in the supported keyword subset are used; deferred/excluded-keyword fixtures (minLength, pattern, minimum, additionalProperties, uniqueItems, allOf/anyOf/oneOf/not, $schema/$id constraint behaviour) are intentionally omitted as they exercise unsupported features."* The supported fixtures to mirror: basic string; number type; integer type; boolean type; enum values; enum mixed types; simple object; nested objects; array of strings; email/uri/date-time format; and the **supported slices** of the two "complex real-world" fixtures (the user-registration and API-response objects, evaluated for only their supported keywords — i.e. construct values that pass/fail on `type`/`properties`/`required`/`enum`/`format` alone, since those fixtures also carry `minLength`/`pattern`/`minimum` which are deferred). State in the block that the complex fixtures are cross-checked on their **supported-keyword projection** only.

### Part 8 — malformed-schema fail-fast (item-010 precedent inherited)

`check-exn exn:fail?` (ideally an S1 error type) for each **structurally malformed** schema at **compile** time:
- non-`hasheq` schema (`42`, `'()`);
- `properties` whose value is not an object-of-subschemas (e.g. `(hasheq 'properties 5)`);
- `type` whose value is not a recognized type string (`(hasheq 'type "stringg")`, `(hasheq 'type 5)`);
- `enum` that is not a list (`(hasheq 'enum 5)`).
- **S-d malformed NESTED sub-schema:** `(hasheq 'type "object" 'properties (hasheq 'name (hasheq 'type "stringg")))` — a bad `type` in a *sub*-schema. Recommended: `check-schema-shape` RECURSES, so this **raises at compile** (`check-exn`). Test the chosen branch: if recurse-and-raise (recommended), `check-exn` at compile; if defer-to-descent, assert it does NOT raise at compile and instead surfaces when a value reaches `name` — pin whichever is implemented (document in Decisions).

Document that fail-fast at compile is the chosen policy for **malformed shape** (inherited from item 010 Decisions (e)), and that it is **distinct from** (a) validate-time *value* rejection (a well-formed schema + a non-conforming value → `validation-errors`, not a raise — see C2/C3/C5) and (b) the ignore-with-warning policy for deferred/unknown keywords (a well-formed schema carrying an unsupported-but-shaped keyword → warn-and-record, not a raise). All three paths are separately pinned: malformed → raise (Part 8), bad value → errors (Parts 2–5), unsupported keyword → warn (Part 6).

**S-c malformed deferred-keyword VALUE — the chosen branch IS tested (do not leave uncovered).** A deferred keyword whose value is itself malformed (e.g. `(hasheq 'type "string" 'minLength "three")` — `minLength` a string, not an integer): the implementer picks ONE branch and the test pins it — either treat-as-malformed → `(check-exn exn:fail? (lambda () (provider-compile P …)))`, or treat-as-ignore → `(check-not-exn …)` + accept + `(memq 'minLength (provider-warnings-for P h))`. Record the choice in Decisions; the path MUST have a test either way.

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

**Implementation outcome (recorded post-build).** Shipped `mcp/core/validators/from-json-schema.rkt` (`#lang racket/base`) + `mcp/core/validators/test/from-json-schema-test.rkt`. `raco make` clean (exit 0, no warnings); `raco test mcp/core/validators/` → **300 checks pass, 0 failures** (item 011's new test + item 010's existing `provider-test.rkt`). Portability drift check: injecting `(require racket/tcp)` makes the restricted-load test FAIL naming `racket/tcp` (1/234), then reverted → green. REPL smoke check prints `(#t #t)`.

Key decisions made:

**(a) Require list = `racket/generic racket/list racket/string json ../main.rkt provider.rkt`.** `../main.rkt` (S1 barrel) is used for `make-protocol-error` (fail-fast compile on malformed shape). `json` is required directly for `(json-null)` (the `null`-type recognizer + heterogeneous-enum member). `racket/string` for `string-join` in the stderr line. `racket/list` for `remove-duplicates`. All are portability-clean (restricted-load walk: empty intersection with the banned set, incl. **no `net/url`** — the uri recognizer is string/regex-based).

**(b) Encoding — closure-in-handle + provider-held weak warnings map.** `provider-compile` returns a single `compiled-validator?` (item-010's frozen struct, NOT widened, NOT a `(values …)`). The ignored-keyword list lives on item 011's own `racket-native-provider` struct as a `(make-weak-hasheq)` keyed `handle → (listof symbol?)`, read via `provider-warnings-for`. Weak so a long-lived provider does not retain every compiled handle (item 012 compiles many schemas through one provider). N1 (two handles from one provider stay distinct) and N2 (validate never appends to the list) both pinned.

**(c) Type recognizers — exact-integer + finite-rational.** `integer` = `exact-integer?` (so `42.0` REJECTS — the inexact-integer trap; `(/ 84 2)` and bignums accept). `number` = `(and (real? v) (rational? v))` — so `+nan.0` and `+inf.0` REJECT (a JSON number cannot be NaN/Inf, even though `(number? +nan.0)` is `#t`). `null` = `(eq? v (json-null))` where `(json-null)` is `'null`.

**(d) Error policy — COLLECT-ALL with located paths.** `evaluate` threads a `path`, prepending the string key on `properties` descent and the integer index on `items` descent, and APPENDS all sibling/element/property errors (no short-circuit across siblings). A scalar leaf may report one error. An ignored keyword contributes ZERO errors (S-a). Each structural keyword type-guards the value first: `properties`/`required` on a non-hash and `items` on a non-list emit ONE clean "expected object/array" error (only when `type` did not already report the mismatch — no double-report) and skip descent; `format` on a non-string is skipped silently. `hash-ref` reads use a `#f` default so an absent key is distinct from an empty value (S-f).

**(e) S-c malformed deferred-keyword VALUE → ignore-with-warning.** A deferred keyword whose value is itself malformed (e.g. `minLength:"three"`) is treated exactly like any deferral: the keyword is SKIPPED regardless of its value, so the value's shape is never inspected — `provider-compile` does NOT raise, the keyword is recorded, and a value the keyword would reject is accepted. (Rationale: the deferred keyword is never evaluated, so validating its value would be dead work and would make a deferred keyword a reject path, contradicting the uniform ignore-with-warning policy.)

**(f) S-d malformed NESTED sub-schema → recurse + compile-time raise.** `check-schema-shape` RECURSES into `properties` values and `items` sub-schemas, applying the same shape check, so a bad nested `type` (e.g. `properties:{name:{type:"stringg"}}`) RAISES at `provider-compile` (fail-fast), `check-exn`-pinned. Malformed-SHAPE → raise is distinct from bad-VALUE → `validation-errors` (C2/C3/C5) and from unsupported-but-shaped-keyword → warn-and-record; all three paths are separately tested.

**(g) Unknown-format recorded form (S-g).** An unknown `format` (e.g. `"ipv4"`) is recorded as the format SYMBOL `'ipv4` (via `string->symbol`), uniform with the symbol-typed deferred/unknown keyword records. Membership is checked with `(memq 'ipv4 (provider-warnings-for P h))`.

**(h) Format-recognizer choices + documented limitations.** email: one `@`, non-empty local part, dotted domain, no whitespace — `"a@b"` (no dot) REJECTS; not full RFC 5322. uri: `^[A-Za-z][A-Za-z0-9+.-]*:` scheme-presence shape — `"mailto:…"`/`"urn:…"` accept, scheme-less/empty-scheme reject; not full RFC 3986; string/regex only (NOT `net/url`). date-time: ISO-8601 SHAPE regex (`#px` for `{n}` quantifiers) — `"2025-13-01T00:00:00Z"` (month 13) ACCEPTS (no range check). All three documented in the module doc block.

**(i) Warnings emission via `eprintf` (N3).** A single human-facing stderr line is emitted at compile when any keyword is ignored, via `eprintf` (so a `current-error-port` string-capture is valid — NOT `log-warning`). The RECORDED LIST is the load-bearing warn-once oracle; the supplementary stderr assertion (one line at compile, none across three validates) is also pinned.

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

- [x] **Build/compile succeeds:** `raco make mcp/core/validators/from-json-schema.rkt` compiles with no errors/warnings.
- [x] **Module loads in isolation:** `racket -e '(require (file "mcp/core/validators/from-json-schema.rkt"))'` from repo root succeeds.
- [x] **Tests pass:** `raco test mcp/core/validators/test/from-json-schema-test.rkt` → all checks pass, exit 0.
- [x] **Collection tests pass (incl. item 010):** `raco test mcp/core/validators/` → exit 0.
- [x] **Services started:** N/A (no services — pure library).
- [x] **Application runs:** N/A (library; "running" = the require + REPL/provider smoke check below).
- [x] **Feature verified (REPL / provider smoke check):** from repo root, build the provider, compile an object schema, validate a good + bad value — e.g.
      `racket -e '(require (file "mcp/core/validators/from-json-schema.rkt") (file "mcp/core/validators/provider.rkt")) (define p (make-racket-native-provider)) (define h (provider-compile p (hasheq (quote type) "object" (quote properties) (hasheq (quote name) (hasheq (quote type) "string")) (quote required) (list "name")))) (list (validation-ok? (validate h (hasheq (quote name) "John"))) (validation-errors? (validate h (hasheq))))'`
      prints `(#t #t)` (ok for `{name:"John"}`, errors for `{}` — missing required). (Adjust to the chosen constructor name; record exact transcript in Validation Results.)
- [x] **`type` matrix verified:** accept+reject for each of string/number/integer/boolean/object/array/null; integer rejects `3.14`; null matches `(json-null)` not `#f`/`0`.
- [x] **Numeric edges verified (S5):** integer rejects `42.0` (inexact), accepts `(/ 84 2)` + bignum; number `+nan.0`/`+inf.0` verdict per documented choice.
- [x] **Collect-all verified (C1):** `{props name:string,age:number, required:[name]}` on `{age:"x"}` → exactly 2 errors; `{type:string,enum:[a,b]}` on `42` → exactly 2.
- [x] **`properties`/`required` verified:** present-but-wrong-type rejects with key in path; missing-required rejects with key in message; empty `required` accepts any object; nested-object path includes the parent key.
- [x] **Symbol/string `required` accept verified (S8):** required `["name"]` + value `(hasheq 'name …)` accepts (string→symbol bridge).
- [x] **Non-object value verified (C2):** `{type:object,…}` on `42`/`"str"`/list/`(json-null)` returns errors, NOT raise; no-`type` `{properties,required}` on `42` also returns errors.
- [x] **`enum` verified:** homogeneous + heterogeneous (incl. `(json-null)` member) accept listed / reject unlisted.
- [x] **`enum` edges verified (S4):** empty enum rejects every value; duplicates accept; compound member matches via deep `equal?`.
- [x] **`items` verified:** accepts (incl. empty array); rejects with failing element's integer index in path; nested `items`+`properties` produces `'(1 "name")` mixed path.
- [x] **Non-array value verified (C3):** `{type:array,items:…}` on `(hasheq 'a 1)`/`42` returns errors, NOT raise; no-`type` `{items}` on a non-list also returns errors; type+enum co-occurrence counts (42→2, "c"→1).
- [x] **Both-element paths verified (S6):** `[{name:123},{name:456}]` under object-`items` yields BOTH `'(0 "name")` and `'(1 "name")`.
- [x] **`format` verified:** date-time/uri/email each accept the TS-valid example and reject the TS-invalid one.
- [x] **Recognizer rigor verified (C6):** email rejects `a@`/`@b.com`/`a b@c.com`; uri rejects `example.com`/`://example.com`; date-time accepts `2025-13-01T00:00:00Z` (documented shape-only limitation); one documented limitation per recognizer present in module docs.
- [x] **Format non-string + unknown-format verified (C5):** `{format:email}` on `42` accepts (no-op, no crash); `{type:string,format:email}` on `42` rejects on type (recognizer not run); `{type:string,format:ipv4}` on `"1.2.3.4"` accepts + warns/records unknown format.
- [x] **Deferred-keyword policy verified (C4):** all five (`pattern`/`minLength`/`maxLength`/`minimum`/`maximum`/`additionalProperties`/`uniqueItems`) ignore-with-warning UNIFORMLY (none raises), each recorded as a SYMBOL in `(provider-warnings-for P h)`; warn-ONCE on the RECORDED LIST (N2: list length identical after 3 validates as after 0); each listed in module docs.
- [x] **Per-compile-keyed warnings verified (N1):** h1={type:string,minLength:3} and h2={type:string,pattern:"x"} from one provider — `(provider-warnings-for P h1)` has `'minLength` not `'pattern`, h2 the reverse; distinct, not overwritten (weak handle→warnings map).
- [x] **Warnings emission/capture method verified (N3):** stderr (if any) via `eprintf`/`current-error-port` (capturable) — NOT `log-warning` with a vacuous `current-error-port` capture; recorded-list is the load-bearing oracle.
- [x] **S-a ignored keyword contributes 0 errors:** `{type:number,minimum:0}` on `"x"` → exactly 1 error (no phantom minimum-skipped error).
- [x] **S-b recording is compile-time:** `{type:string,format:ipv4}` on `42` → exactly 1 error (type) AND `'ipv4` still in `(provider-warnings-for P h)`.
- [x] **Warnings element type = SYMBOLS (S-g):** every `provider-warnings-for` membership check uses symbols (`(memq 'minLength …)`), consistent with schema keys; accessor is `(provider-warnings-for provider handle)` over a weak handle→warnings map.
- [x] **Unknown-keyword + annotations verified (S3/S2):** `multipleOf`/`$ref` routed through ignore-with-warning (recorded as symbol); annotations (`title`/`description`/`default`) ignored WITHOUT warning (`(provider-warnings-for P h)` empty) and do NOT suppress a `type` failure.
- [x] **S-c malformed deferred-keyword value:** `{type:string,minLength:"three"}` — chosen branch (raise OR ignore+record) is tested.
- [x] **S-d malformed nested sub-schema:** `{type:object,properties:{name:{type:"stringg"}}}` — recursion policy pinned (recommended: raises at compile).
- [x] **S-e nested enum located path:** `{type:object,properties:{color:{enum:[red,green]}}}` on `{color:"blue"}` → error path `'("color")`.
- [x] **S-f empty vs absent properties:** `{type:object,properties:{}}` on `(hasheq 'anything 1)` accepts, no crash (default-guarded `hash-ref`).
- [x] **Empty/degenerate + statelessness verified (S1/S7):** `{}` accepts all; `{type:object}` accepts any object; `{required:[name]}` enforces presence; one provider's h1=string/h2=number disagree on the same value.
- [x] **Error path+message verified:** a nested failure yields a `validation-error` with a real path (incl. a `'(… 0 …)` mixed path) and a non-empty message — not a hard-coded root error.
- [x] **TS-baseline cross-check verified:** the supported-subset fixtures from `validators.test.ts` produce the same accept/reject verdict in Racket (parity block green).
- [x] **Malformed-schema fail-fast verified:** `provider-compile` raises on non-hash schema / bad `properties` / bad `type` / non-list `enum` (check-exn).
- [x] **Portability verified:** the restricted-load test passes (no subprocess/socket — incl. NO `net/url` from the uri recognizer — in the transitive import closure of `from-json-schema.rkt`).
- [x] **Drift / non-vacuity check (portability):** temporarily add `(require racket/tcp)` to a scratch copy, confirm the load test FAILS naming `racket/tcp`, then revert.
- [x] **Health checks pass:** N/A (no running service).

### Expected Outcomes

Concrete, verifiable:

- The module **exports** a default-provider constructor (e.g. `make-racket-native-provider`) + its struct predicate + the read-only accessor **`(provider-warnings-for provider handle)`** returning the handle's recorded ignored-keyword list as a `(listof symbol?)` (for the C4/C5/N1/S3/S-g assertions — keyed to the produced handle in the provider's weak map, NOT a `compiled-validator` field, which item 010 froze and this item may not widen); `(json-schema-validator-provider? (make-racket-native-provider))` → `#t`. **No internal evaluator/schema-checker helper leaks** (`evaluate` / `check-schema-shape` are NOT provided), and the validate-closure stays opaque (item-010 contract). It does NOT re-export the port's result API (callers `require` `provider.rkt`).
- A compiled handle from this provider returns a `validation-ok` (value recovered) for a value satisfying the supported keywords, and a `validation-errors` (non-empty list of `validation-error`, each with a **real path** + message) for a violating value — paths populated from actual nested evaluation (incl. mixed string/integer paths).
- For each of `type`/`object`-`properties`/`required`/`enum`/`string`-`format`, ≥1 accept + ≥1 reject case matches the TS `validators.test.ts` verdict for the same schema+value (supported subset).
- Each deferred keyword (`pattern`, `minLength`/`maxLength`, `minimum`/`maximum`, `additionalProperties`, `uniqueItems`) is handled per one documented policy and named in the module docs.
- The module **requires only S1 + the item-010 port** — a restricted-namespace load test confirms NO subprocess/socket module (`racket/system`, `racket/tcp`, `racket/udp`, `net/*`, `racket/sandbox`, `racket/port`) is pulled in (Portability NFR).
- `raco test mcp/core/validators/` reports all checks passing, 0 failures, 0 errors (item 011's new test + item 010's existing test).

### Validation Results

*(Populated post-build.)*

```markdown
## Validation Results
- [x] Service started: N/A (pure Racket library, no services)
- [x] Application started successfully: N/A (library; `require` + provider smoke check → `(#t #t)`)
- [x] Build verified: `raco make mcp/core/validators/from-json-schema.rkt` clean (exit 0, no warnings)
- [x] Module load verified: `(require (file ".../from-json-schema.rkt"))` succeeds
- [x] Tests verified: `raco test mcp/core/validators/` → 300 checks pass, 0 failures, 0 errors
- [x] type matrix verified: string/number/integer/boolean/object/array/null accept+reject; integer rejects 3.14; null = (json-null) not #f/0
- [x] numeric edges verified (S5): integer rejects 42.0, accepts (/ 84 2)+bignum; number nan/inf per documented choice
- [x] collect-all verified (C1): {name:string,age:number,required:[name]} on {age:"x"} → 2 errors; {type:string,enum:[a,b]} on 42 → 2
- [x] properties/required verified: wrong-type prop rejects (key in path); missing required rejects (key in message); empty required accepts; nested path includes parent key
- [x] symbol/string required accept verified (S8): required ["name"] + (hasheq 'name …) accepts
- [x] non-object value verified (C2): {type:object} on 42/"str"/list/(json-null) → errors not raise; no-type {properties,required} on 42 → errors
- [x] enum verified: homogeneous + heterogeneous (incl. (json-null) member) accept/reject
- [x] enum edges verified (S4): empty enum rejects all; duplicates accept; compound member matches via equal?
- [x] items verified: empty-array accepts; bad element rejects with integer index in path; nested items+properties → '(1 "name") mixed path
- [x] non-array value verified (C3): {type:array,items} on (hasheq 'a 1)/42 → errors not raise; no-type {items} on non-list → errors; type+enum counts 42→2, "c"→1
- [x] both-element paths verified (S6): [{name:123},{name:456}] → both '(0 "name") and '(1 "name")
- [x] format verified: date-time/uri/email accept TS-valid, reject TS-invalid
- [x] recognizer rigor verified (C6): email rejects a@/@b.com/a b@c.com; uri rejects example.com/://example.com; date-time accepts month-13 (documented); one documented limitation each
- [x] format non-string + unknown-format verified (C5): {format:email} on 42 accepts (no crash); {type:string,format:email} on 42 rejects on type; {type:string,format:ipv4} on "1.2.3.4" accepts + records unknown format
- [x] deferred-keyword policy verified (C4): all five ignore-with-warning uniformly (none raises), recorded as symbols in (provider-warnings-for P h); warn-once on recorded list (3 validates → list length unchanged); listed in module docs
- [x] per-compile-keyed warnings verified (N1): weak handle→warnings map; h1=minLength / h2=pattern from one provider stay distinct (not overwritten)
- [x] warnings element type = symbols (S-g): provider-warnings-for returns (listof symbol?); membership via (memq 'minLength …)
- [x] warnings emission/capture verified (N3): eprintf/current-error-port (not vacuous log-warning capture); recorded-list is the oracle
- [x] S-a ignored kw 0 errors: {type:number,minimum:0} on "x" → exactly 1 error
- [x] S-b compile-time recording: {type:string,format:ipv4} on 42 → 1 error (type) AND ipv4 still recorded
- [x] S-c malformed deferred value: {type:string,minLength:"three"} → chosen branch tested (raise or ignore+record)
- [x] S-d malformed nested sub-schema: {type:object,properties:{name:{type:"stringg"}}} → recursion policy pinned (recommended raises at compile)
- [x] S-e nested enum located path: {type:object,properties:{color:{enum:[red,green]}}} on {color:"blue"} → path '("color")
- [x] S-f empty vs absent properties: {type:object,properties:{}} on (hasheq 'anything 1) accepts, no crash
- [x] unknown-keyword + annotations verified (S3/S2): multipleOf/$ref ignore-with-warning recorded as symbol; annotations ignored no-warning ((provider-warnings-for P h) empty) + don't suppress type failure
- [x] empty/degenerate + statelessness verified (S1/S7): {} accepts all; {type:object} accepts objects; {required:[name]} enforces presence; h1=string/h2=number disagree
- [x] error path+message verified: nested failure yields real path (incl. mixed '(… 0 …)) + non-empty message
- [x] TS-baseline cross-check verified: supported-subset validators.test.ts fixtures → same accept/reject verdict
- [x] malformed-schema fail-fast verified: non-hash / bad properties / bad type / non-list enum → provider-compile raises (check-exn)
- [x] Portability verified: restricted-load walk over from-json-schema.rkt — empty intersection with banned set (incl. no net/url from uri recognizer)
- [x] Portability drift check: injected (require racket/tcp) → walk FAILED naming racket/tcp, then reverted
- [x] S1 + port imports confirmed: require list = racket/generic + ../main.rkt + provider.rkt (+ json if used)
- [x] Database tables verified: N/A
- [x] Seed data verified: N/A
- [x] API endpoints verified: N/A
- [x] Screenshots captured: N/A (no UI)
```

---

## Completion Reminder

On completion, the implementer MUST update **`docs/aide/progress.md`** (Stage S2 section), advancing the icon **📋 → 🚧 → ✅**:

1. Flip the deliverable line **`📋 mcp/core/validators/from-json-schema.rkt — Racket-native default (keywords: type, properties, required, enum, items, format for date-time/uri/email)`** (progress.md line ~72) from 📋 → 🚧 (on start) → ✅ (on delivery + all acceptance criteria pass). Never revert an icon backward.
2. **Check the Stage-S2 validator keyword-coverage acceptance box** — **`[ ] Validator keyword coverage: ≥1 accept + 1 reject per type/object/required/enum/string-format, cross-checked vs TS Ajv baseline; unsupported keywords documented`** (progress.md line ~86). **This box belongs to THIS item** (item 010 delivered only the port; this item delivers the keyword evaluation + the TS-baseline cross-check + the documented-unsupported-keywords list). Check it on delivery.
3. Do **not** check the other broad Stage-S2 acceptance boxes that depend on sibling items (the `raco test over all S2 modules`, URI-template, tool-name, schema-normalization, and stdio-framing boxes belong to items 012–017/018).
4. **Parity matrix:** per Stage S2 discipline, advance the `validators/*` row toward `partial` (the default provider's supported-keyword exercise now exists; full conformance + the collection-wide sweep land with items 017/018 and S9). Record that the **default-provider/keyword** sub-row is now satisfied (item 010 satisfied the **port** sub-row).
5. Leave all other S2 deliverable lines (`util/schema.rkt`, the `shared/*` utils, tests-under-other-dirs) at their current status — this item delivers only `validators/from-json-schema.rkt` + its test.
