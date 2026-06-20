# Work Item 002: JSON-RPC type guards / predicates (no batch guard)

> **Queue:** `docs/aide/queue/queue-001.md` — Item 002
> **Stage:** S1 (Foundation: types, constants, guards, errors — L0 part 1)
> **Module:** M1 (Types) — `guards` sub-unit
> **Source vision:** `docs/aide/vision.md` §4.1 (line 67: "Type guards / predicates … → `mcp/core/types/guards.rkt`")
> **Source roadmap:** `docs/aide/roadmap.md` Stage S1 → Deliverables → `mcp/core/types/guards.rkt` (line 83: "**No batch guard** (architecture J3)")
> **Source architecture:** `docs/aide/architecture.md` M1 line 71 (Guards interface), **J3** line 73 (no batching), §1.3 (public/internal boundary)
> **Reference impl (authoritative):** MCP TypeScript SDK v2 at `typescript-sdk/`
> **Status:** 📋 Planned (see Completion Reminder)

---

## Description

Implement `mcp/core/types/guards.rkt`, a **pure-predicate** Racket module mirroring the
TypeScript SDK's `typescript-sdk/packages/core/src/types/guards.ts`. It provides the
JSON-RPC message-shape predicates that every dispatch/routing layer (the future protocol
engine, transports, and the error decode path) uses to classify a parsed-but-untrusted
inbound message into request / notification / result-response / error-response before
acting on it.

The predicates operate on **parsed JSON values** — i.e. the `jsexpr` produced by
`read-json` from `json`, where a JSON object is an immutable `hasheq` with **symbol**
keys (`'jsonrpc`, `'id`, `'method`, `'params`, `'result`, `'error`). They take any value
(including non-hash values such as numbers, strings, `'null`, lists) and return a boolean
— they must never raise on hostile input. This is the Racket analogue of the TS guards,
which take `unknown` and return a type-narrowing boolean via `Schema.safeParse(value).success`.

### Authoritative TS reference (verified against the checkout — DO NOT guess)

All shapes below were read from the checkout on the queue date and are reproduced here as
the implementation contract, not as a substitute for the parity test.

**Predicate definitions — `typescript-sdk/packages/core/src/types/guards.ts`:**

| TS export (line) | Delegates to schema | Racket name (this item) |
|---|---|---|
| `isJSONRPCRequest` (line 43) | `JSONRPCRequestSchema.safeParse(value).success` | `is-jsonrpc-request?` |
| `isJSONRPCNotification` (line 45) | `JSONRPCNotificationSchema.safeParse(value).success` | `is-jsonrpc-notification?` |
| `isJSONRPCResultResponse` (lines 53–54) | `JSONRPCResultResponseSchema.safeParse(value).success` | `is-jsonrpc-result-response?` (supporting check) |
| `isJSONRPCErrorResponse` (lines 62–63) | `JSONRPCErrorResponseSchema.safeParse(value).success` | `is-jsonrpc-error?` |
| `isJSONRPCResponse` (line 71) | `JSONRPCResponseSchema.safeParse(value).success` (= union of result OR error) | `is-jsonrpc-response?` |

> **Naming reconciliation (load-bearing).** The queue/roadmap/vision/architecture all
> canonically name **four** public predicates: `is-jsonrpc-request?`,
> `is-jsonrpc-notification?`, `is-jsonrpc-response?`, `is-jsonrpc-error?`. TS splits the
> response side into three functions (`isJSONRPCResultResponse`, `isJSONRPCErrorResponse`,
> and the union `isJSONRPCResponse`). The mapping this item adopts:
> - `is-jsonrpc-error?` ↔ TS `isJSONRPCErrorResponse` (an **error response** object).
> - `is-jsonrpc-response?` ↔ TS `isJSONRPCResponse` — the **union** (result OR error
>   response), matching `JSONRPCResponseSchema = z.union([Result, Error])` (guards.ts:71,
>   schemas.ts:201). This is the one most likely to be misread as "result-only"; it is
>   NOT — it is true for both result and error responses, exactly like TS.
> - `is-jsonrpc-result-response?` ↔ TS `isJSONRPCResultResponse` — exported as the
>   "supporting message-shape check" the queue text requires, so callers that need the
>   result-vs-error distinction have it, and the truth-table test can assert
>   `is-jsonrpc-response?` ≡ `(or result-response error-response)` exactly as TS test
>   guards.test.ts:63–76 does.
>
> Five predicates are provided in total. `is-call-tool-result?`,
> `is-task-augmented-request-params?`, `is-initialize-request?`,
> `is-initialized-notification?`, and the `assertCompleteRequest*` helpers in guards.ts
> (lines 79–110) are **out of scope** — they depend on MCP primitive/spec types (items
> 003–005) not yet built. This item is the JSON-RPC **envelope** guards only.

**The schema shapes the predicates enforce — `typescript-sdk/packages/core/src/types/schemas.ts`:**

`RequestIdSchema` (schemas.ts:136): `z.union([z.string(), z.number().int()])` — an id is a
**string or an integer number**. Crucially, **`null` is NOT a valid id**, and a
**non-integer number** (e.g. `1.5`) is NOT a valid id.

| Schema (line) | Mode | Required keys | Optional keys | Forbidden |
|---|---|---|---|---|
| `JSONRPCRequestSchema` (141–147) | `.strict()` | `jsonrpc`="2.0", `id` (string\|int), `method` (string) | `params` | any extra key; `result`; `error` |
| `JSONRPCNotificationSchema` (152–157) | `.strict()` | `jsonrpc`="2.0", `method` (string) | `params` | any extra key; **`id`** (its presence makes it a request, not a notification); `result`; `error` |
| `JSONRPCResultResponseSchema` (162–168) | `.strict()` | `jsonrpc`="2.0", `id` (string\|int), `result` (object) | — | any extra key; `method`; `error` |
| `JSONRPCErrorResponseSchema` (173–192) | `.strict()` | `jsonrpc`="2.0", `error` `{code:int, message:string, data?}` | **`id` (string\|int, optional)** | any extra key; `result`; `method` |

> **Three discriminator subtleties that the test must pin (all confirmed from source):**
> 1. **`.strict()` everywhere** (schemas.ts:147,157,168,192) → **extra/unknown top-level
>    keys cause rejection**. A message with both `result` and `error` matches neither
>    result-response (has extra `error`) nor error-response (has extra `result`) →
>    `is-jsonrpc-response?` is **false** for it. Likewise `{jsonrpc,id,method,result}`
>    matches neither request (extra `result`) nor result-response (extra `method`).
> 2. **Notification vs request is discriminated purely by `id` presence.** Notification
>    schema is strict and has no `id` field → any `id` key (even a valid one) makes it
>    fail the notification schema; it then matches request only if `method` is present.
> 3. **Error-response `id` is OPTIONAL** (schemas.ts:176 `RequestIdSchema.optional()`)
>    whereas request/result-response `id` is **required**. An error object with no `id`
>    is still a valid error response (a parse error before an id is known). But an `id`
>    of `null` is invalid even for an error response, because `RequestIdSchema` does not
>    admit `null` and `.optional()` means absent, not null.

**The `result` field is a loose object** (`ResultSchema = z.looseObject(...)`, schemas.ts:118)
— it may be an empty object `{}` and may carry arbitrary extra keys (`_meta`, `resultType`,
tool-specific content). So a result-response only requires that `result` be present and an
object; its contents are not constrained at the envelope level.

### J3 — no batch guard (verified)

Per architecture **J3** (architecture.md:73): both target revisions (`2025-11-25`,
`2026-07-28`) removed JSON-RPC batching. A `grep -rni batch` over
`typescript-sdk/packages/core/src/types/` returns **zero matches** (verified on the queue
date): there is **no** `JSONRPCBatchSchema`, no `isJSONRPCBatch` guard, and
`JSONRPCMessageSchema` (schemas.ts:194–199) is a 4-way union of single envelopes with no
array/batch arm. Therefore this module **must not** define or `provide` any batch
predicate (`is-jsonrpc-batch?` or similar), and a test asserts its absence by module
introspection (see Testing Strategy).

---

## Acceptance criteria

- [ ] `mcp/core/types/guards.rkt` exists as `#lang racket/base` with an explicit, curated
      `(provide …)` (no `(provide (all-defined-out))`).
- [ ] Exactly **five** predicates are provided, all ending in `?`:
      `is-jsonrpc-request?`, `is-jsonrpc-notification?`, `is-jsonrpc-result-response?`,
      `is-jsonrpc-error?`, `is-jsonrpc-response?`.
- [ ] Each predicate accepts **any** Racket value and returns a boolean; it never raises,
      including on non-hash inputs (`42`, `"x"`, `'null`, `'()`, `#f`, a list, a vector,
      a mutable `hash`, a string-keyed hash) and on objects missing `jsonrpc`.
- [ ] Predicates operate on the `read-json` representation: a JSON object is an **immutable
      `hasheq` with symbol keys**; `jsonrpc` must equal the string `"2.0"`
      (`JSONRPC-VERSION` from item 001's `constants.rkt`).
- [ ] **Request:** true iff value is a hasheq with `jsonrpc`="2.0", an `id` that is a
      string or **exact integer**, a `method` that is a string, optional `params`, and
      **no** other top-level keys, **no** `result`, **no** `error` (mirrors strict schema).
- [ ] **Notification:** true iff hasheq with `jsonrpc`="2.0", a `method` string, optional
      `params`, and **no `id`**, no `result`, no `error`, no extra keys.
- [ ] **Result response:** true iff hasheq with `jsonrpc`="2.0", a valid `id`
      (string\|int), a `result` that is an object (hasheq), and no `method`/`error`/extra.
- [ ] **Error response (`is-jsonrpc-error?`):** true iff hasheq with `jsonrpc`="2.0", an
      `error` object having an **integer** `code` and a **string** `message` (and optional
      `data`), an **optional** `id` (string\|int when present), and no `result`/`method`/extra.
- [ ] **Response (`is-jsonrpc-response?`):** true iff `is-jsonrpc-result-response?` OR
      `is-jsonrpc-error?` — the union, matching TS. Assert this identity holds for the full
      truth-table value set.
- [ ] **`id` validity:** an `id` of `'null` (JSON `null`), a fractional number (`1.5`), a
      boolean, or an object is **rejected** wherever an id is checked. A string id and an
      exact-integer id are both accepted.
- [ ] **Mutual exclusivity holds on the truth-table set:** no single valid envelope value
      satisfies more than one of {request, notification, result-response, error-response}
      (request/notification/result/error are disjoint), and `is-jsonrpc-response?` is the
      only intentional overlap (= result OR error).
- [ ] **No batch predicate is exported.** A test asserts, by introspecting the module's
      exports (`module->exports` / `dynamic-require`), that no provided binding name
      matches `#rx"batch"` (case-insensitive), and specifically that
      `is-jsonrpc-batch?` is not bound.
- [ ] A rackunit truth-table test at `mcp/core/types/test/guards-test.rkt` exercises every
      predicate against the valid-accept and invalid-reject cases (including the
      ambiguous/overlapping shapes) enumerated in Testing Strategy, and passes.
- [ ] `raco test mcp/core/types/` passes (exit 0) from the repo root — confirms the module
      and its test compile and load cleanly within the collection, alongside item 001.
- [ ] **Portability (NFR):** `guards.rkt` requires nothing beyond `racket/base` and item
      001's `constants.rkt` (for `JSONRPC-VERSION`). No subprocess/socket module is pulled
      in. (The dedicated restricted-load test is item 008's job; this module must not
      introduce such a dependency — confirm by reading its `require` list.)
- [ ] Parity-matrix discipline: the roadmap §9 / progress.md `guards.ts` sub-row under
      `core/types/*` is advanced toward `partial` per Stage S1 discipline on completion
      (see Completion Reminder); sibling rows are left untouched.

---

## Implementation steps

1. **Ensure the collection dirs exist** (created by item 001): `mcp/core/types/` and
   `mcp/core/types/test/`.
2. **Write `mcp/core/types/guards.rkt`** with `#lang racket/base`. Require
   `(only-in "constants.rkt" JSONRPC-VERSION)` and nothing else at runtime beyond
   `racket/base`. Group with section comments matching the TS layout
   (`; --- request ---`, `; --- notification ---`, `; --- responses ---`).
3. **Write small internal helpers** (not provided):
   - `(json-object? v)` → `(and (hash? v) (immutable? v) (hash-eq? v))` — the `read-json`
     object shape. (Be tolerant: also accept any `hash?` keyed by symbols if you prefer,
     but match `read-json`'s `hasheq` default; the test feeds `hasheq` objects to mirror
     real wire input.) Reject mutable/string-keyed hashes that don't match `read-json`.
   - `(valid-jsonrpc? h)` → `(and (json-object? h) (equal? (hash-ref h 'jsonrpc #f) JSONRPC-VERSION))`.
   - `(valid-id? x)` → `(or (string? x) (exact-integer? x))` — string OR exact integer;
     **rejects** `'null`, inexact/fractional numbers, booleans, objects.
   - `(only-keys? h allowed)` → true iff every key of `h` is in the `allowed` set — this
     enforces the `.strict()` "no extra keys" behavior. Implement by checking
     `(for/and ([k (in-hash-keys h)]) (memq k allowed))`. Use this in every predicate so
     extra keys (and the result/error cross-contamination cases) are rejected.
4. **Implement the five predicates** using the helpers, each returning a boolean
   (wrap with `(and … #t)` or `(if … #t #f)` so the result is a true boolean, not a
   truthy value):
   - `is-jsonrpc-request?`: `valid-jsonrpc?` ∧ id present & `valid-id?` ∧ `method` is string
     ∧ no `result`/`error` ∧ `only-keys?` ⊆ `{jsonrpc id method params}`.
   - `is-jsonrpc-notification?`: `valid-jsonrpc?` ∧ **no `id` key** ∧ `method` is string
     ∧ no `result`/`error` ∧ `only-keys?` ⊆ `{jsonrpc method params}`.
   - `is-jsonrpc-result-response?`: `valid-jsonrpc?` ∧ id present & `valid-id?` ∧ `result`
     present & is a `json-object?` ∧ no `method`/`error` ∧ `only-keys?` ⊆ `{jsonrpc id result}`.
   - `is-jsonrpc-error?`: `valid-jsonrpc?` ∧ (id absent OR `valid-id?`) ∧ `error` present
     & is a `json-object?` with `code` = `exact-integer?` and `message` = `string?`
     (and any `data` allowed) ∧ no `result`/`method` ∧ `only-keys?` ⊆ `{jsonrpc id error}`
     ∧ error sub-object keys ⊆ `{code message data}`.
   - `is-jsonrpc-response?`: `(or (is-jsonrpc-result-response? v) (is-jsonrpc-error? v))`.
5. **Add the explicit `provide`** listing the five predicate names. **Do not** define or
   provide any batch predicate.
6. **Write the test** `mcp/core/types/test/guards-test.rkt` (see Testing Strategy) — the
   full truth table plus the no-batch introspection assertion.
7. **Run** `raco test mcp/core/types/` from the repo root and fix any failure. Most-likely
   pitfalls: forgetting the `.strict()` extra-key rejection; treating `'null` id as valid;
   accepting an inexact number as an id; mixing up `is-jsonrpc-response?` (union) with
   result-only.
8. **Optional TS parity cross-check** (recommended): in the test, locate
   `typescript-sdk/packages/core/test/types/guards.test.ts` via `define-runtime-path` and,
   for the small inline value set in its `isJSONRPCResponse` describe block (guards.test.ts:6–77),
   assert the Racket predicates produce the same booleans. This is a true upstream-behavior
   cross-check rather than a re-statement of expectations. (If the fixture file is absent,
   `fail` loudly naming the path — do not skip.)
9. **Update progress + parity matrix** (see Completion Reminder).

---

## Testing strategy

The required test is a **truth table**: every predicate is asserted against a curated set
of valid-accept and invalid-reject message values, with explicit attention to the
ambiguous/overlapping shapes. All object values are built with `hasheq` (symbol keys) to
mirror `read-json`'s output. The Reviewer is an edge-case specialist — the table below is
exhaustive and each row is a named `check-true`/`check-false` so a failure pinpoints the case.

**Test file:** `mcp/core/types/test/guards-test.rkt` (`#lang racket/base`, `require
rackunit`, `racket/runtime-path` for the optional TS cross-check; require the module under
test via `(require "../guards.rkt")` and `JSONRPC-VERSION` via `(require "../constants.rkt")`).

**Reusable value fixtures** (define once; `V` = `JSONRPC-VERSION`):

```
req            = (hasheq 'jsonrpc V 'id 1 'method "ping")
req/str-id     = (hasheq 'jsonrpc V 'id "abc" 'method "ping")
req/params     = (hasheq 'jsonrpc V 'id 1 'method "ping" 'params (hasheq 'x 1))
notif          = (hasheq 'jsonrpc V 'method "notifications/initialized")
notif/params   = (hasheq 'jsonrpc V 'method "x" 'params (hasheq))
result         = (hasheq 'jsonrpc V 'id 1 'result (hasheq))
result/full    = (hasheq 'jsonrpc V 'id "id-2" 'result (hasheq 'data 1 'resultType "complete"))
err            = (hasheq 'jsonrpc V 'id 1 'error (hasheq 'code -32600 'message "Invalid Request"))
err/no-id      = (hasheq 'jsonrpc V 'error (hasheq 'code -32700 'message "Parse error"))
err/data       = (hasheq 'jsonrpc V 'id 1 'error (hasheq 'code -1 'message "e" 'data (hasheq 'k 1)))
```

### Truth table — `is-jsonrpc-request?`

| Case | Expect |
|---|---|
| `req`, `req/str-id`, `req/params` | **true** |
| `notif` (no id) | false |
| `result`, `err` | false |
| id is `'null` `(hasheq 'jsonrpc V 'id 'null 'method "m")` | false |
| id is fractional `(… 'id 1.5 …)` | false |
| id is boolean `(… 'id #t …)` | false |
| `method` missing | false |
| `method` non-string `(… 'method 5 …)` | false |
| extra key `(hasheq 'jsonrpc V 'id 1 'method "m" 'foo 1)` | false (strict) |
| `jsonrpc` missing / `"1.0"` / `1` | false |
| `id`+`method`+`result` together | false (extra `result`) |

### Truth table — `is-jsonrpc-notification?`

| Case | Expect |
|---|---|
| `notif`, `notif/params` | **true** |
| `req` (has id) | false — id presence makes it a request, not a notification |
| `result`, `err` | false |
| `method` missing | false |
| `method` non-string | false |
| extra key besides jsonrpc/method/params | false (strict) |
| `jsonrpc` missing / wrong | false |

### Truth table — `is-jsonrpc-result-response?`

| Case | Expect |
|---|---|
| `result`, `result/full` | **true** |
| `result` with string id | true |
| `req`, `notif` | false |
| `err` | false (has `error`, not `result`) |
| missing `id` `(hasheq 'jsonrpc V 'result (hasheq))` | false (id required for result) |
| `result` not an object `(… 'result 5)` / `(… 'result 'null)` | false |
| both `result` and `error` `(hasheq 'jsonrpc V 'id 1 'result (hasheq) 'error (hasheq 'code 1 'message "m"))` | false (strict: extra `error`) |
| `id`+`method`+`result` | false (extra `method`) |
| extra key | false |

### Truth table — `is-jsonrpc-error?`

| Case | Expect |
|---|---|
| `err`, `err/data` | **true** |
| `err/no-id` (id absent) | **true** — id is optional for error responses |
| error with string id | true |
| `result`, `req`, `notif` | false |
| `id` present but `'null` | false (null is not a valid id even when optional) |
| `error.code` non-integer `(… 'error (hasheq 'code 1.5 'message "m"))` | false |
| `error.code` missing | false |
| `error.message` missing / non-string | false |
| `error` not an object `(… 'error "boom")` | false |
| both `result` and `error` | false (strict) |
| extra top-level key | false |
| unknown key inside `error` `(… 'error (hasheq 'code 1 'message "m" 'foo 1))` | false (error sub-object strict to {code,message,data}) |

### Truth table — `is-jsonrpc-response?` (union)

| Case | Expect |
|---|---|
| `result`, `result/full` | **true** (result side) |
| `err`, `err/no-id`, `err/data` | **true** (error side) |
| `req`, `notif` | false |
| both `result` and `error` | false (matches neither strict schema) |
| `{foo: "bar"}` / `42` / `'null` / `#f` / `"s"` / `'()` | false |
| **Identity assertion:** for every value in the full fixture set, `(is-jsonrpc-response? v)` ≡ `(or (is-jsonrpc-result-response? v) (is-jsonrpc-error? v))` | must hold (mirrors guards.test.ts:63–76) |

### Cross-cutting "never raises" cases (run all five predicates over each)

Every predicate must return `#f` (never raise) for each of: `42`, `1.5`, `"string"`,
`'null`, `#f`, `#t`, `'()`, `'(1 2 3)`, `(vector 1 2)`, `(box 1)`, `(make-hash)` (mutable),
`(hash "jsonrpc" "2.0")` (string keys, not symbol keys → not the `read-json` shape),
`(hasheq)` (empty), and `(hasheq 'foo 1)`. Wrap with `check-not-exn` plus `check-false`.

### Ambiguous / overlapping shapes (the Reviewer's focus — assert ALL explicitly)

1. **`result` AND `error` together** → false for result-response, false for error-response,
   false for response (strict rejects the extra arm). Named check.
2. **`id` + `method` + `result`** → false for request (extra `result`), false for
   result-response (extra `method`), false for response.
3. **`method` + `id` (no result/error)** → true for request, false for notification
   (the id-presence discriminator).
4. **`method` only (no id)** → true for notification, false for request.
5. **`error` present but `id` absent** → true for error and for response; false for request
   (no method), false for result.
6. **id as string vs exact integer** → both accepted everywhere an id is valid.
7. **id `'null`** → rejected everywhere (request, result, error-with-id).
8. **Missing `jsonrpc`** → false for all five.
9. **`jsonrpc` present but `"1.0"` / `2.0`-as-number / `2` ** → false for all five
   (must `equal?` the string `"2.0"`).
10. **Extra/unknown top-level keys** on an otherwise-valid envelope → false (strict) for
    the matching predicate.
11. **Empty result object `result: {}`** → true for result-response (loose object allows
    empty).

### No-batch-export assertion (required)

Introspect the module's exported bindings and assert no batch predicate is exposed:

```
(require racket/runtime-path)
(define-runtime-path guards-path "../guards.rkt")
;; phase-0 provided names:
(define provided
  (let-values ([(vars _stx) (module->exports `(file ,(path->string (path->complete-path guards-path))))])
    (for*/list ([phase (in-list vars)] [b (in-list (cdr phase))]) (car b))))
(check-false (memq 'is-jsonrpc-batch? provided) "no is-jsonrpc-batch? export")
(check-false (for/or ([n (in-list provided)]) (regexp-match? #rx"(?i:batch)" (symbol->string n)))
             "no provided name contains 'batch'")
;; and it must not be dynamically requirable:
(check-exn exn:fail? (λ () (dynamic-require `(file ,(path->string (path->complete-path guards-path))) 'is-jsonrpc-batch?)))
;; positive control: the five real predicates ARE exported
(for ([n '(is-jsonrpc-request? is-jsonrpc-notification? is-jsonrpc-result-response? is-jsonrpc-error? is-jsonrpc-response?)])
  (check-true (and (memq n provided) #t) (format "~a is exported" n)))
```

> **Edge case in the introspection itself:** if `module->exports` cannot load the module,
> the test must fail loudly (not silently pass). The positive-control loop guarantees the
> introspection is live — if it ever returns an empty/garbage list, the five positive
> checks fail rather than the negative checks vacuously passing.

### Edge cases the test must cover (do not leave implicit)

- Inexact vs exact id (`1` vs `1.0` vs `1.5`): only exact integers and strings are valid ids.
- `result` being `'null` (JSON `null`) vs an object: `'null` is not an object → result
  predicate false.
- Symbol-keyed `hasheq` (correct, from `read-json`) vs string-keyed `hash` (wrong shape) →
  string-keyed rejected.
- Mutable hash rejected (read-json yields immutable `hasheq`).
- The union identity (`is-jsonrpc-response?` ≡ result OR error) over the entire fixture set.
- `error.data` present (allowed) vs an unknown 4th key inside `error` (rejected).

---

## Dependencies

- **Upstream work items:** **item 001** (`mcp/core/types/constants.rkt`) — guards require
  `JSONRPC-VERSION` from it. Item 001 must be complete (its test green) before this item
  is executed. No other upstream dependency.
- **Operates on:** parsed JSON values — the `jsexpr` from `read-json` (a JSON object is an
  immutable `hasheq` with symbol keys). The guards do **not** call `read-json` themselves;
  callers pass already-parsed values. This keeps `guards.rkt` pure and I/O-free.
- **Downstream consumers (informational):** the protocol engine / dispatch layer (later
  stages) for message routing; the error **decode** path (item 007) to recognize an error
  response; item 008 (barrels) re-exports this module's `provide`.
- **Tooling/runtime:** Racket ≥ 8.x (`raco`, `rackunit`); the `typescript-sdk/` checkout at
  the repo root (only the optional TS-parity cross-check reads from it; see Testing
  Prerequisites).

---

## Project-specific adaptations (Racket / raco / rackunit)

This template's "Required Services / database / API endpoint" framing does not apply:
**this is a pure-predicate module with no external services, no I/O, no network, no
database.** The adaptations are:

- **Language:** `#lang racket/base`. `racket/contract` is **not** used — these are plain
  boolean predicates, not contracted procedures; adding contracts here would be a JS-ism
  (the predicates are themselves the validators). Keep `require`s minimal (Portability NFR):
  only `racket/base` + `(only-in "constants.rkt" JSONRPC-VERSION)`.
- **Naming:** Racket predicates end in `?` and use kebab-case: `is-jsonrpc-request?` (vs TS
  `isJSONRPCRequest`). The `is-` prefix is retained to match the canonical names in
  vision/roadmap/architecture, even though bare `jsonrpc-request?` would also be idiomatic;
  the spec's named surface wins.
- **Parsed-JSON representation:** predicates operate on the `read-json` `jsexpr` shape — a
  JSON object is an immutable `hasheq` with **symbol** keys; JSON `null` is the symbol
  `'null`. The guards check `hash-eq?`/symbol-key shape rather than TS's `typeof object`.
- **TS Zod → Racket structural checks:** TS guards delegate to `Schema.safeParse(...).success`
  (Zod). Racket has no Zod; the predicates re-implement the **same structural rules**
  (required/optional keys, types, `.strict()` no-extra-keys) by hand. The truth-table test
  and the optional TS-fixture cross-check are what keep the two in parity.
- **`.strict()` parity:** the Zod `.strict()` no-extra-keys behavior is replicated by the
  `only-keys?` helper. This is the single most parity-sensitive detail and is what makes
  the ambiguous-shape cases (both result+error; id+method+result) reject correctly.
- **Public surface:** explicit `(provide …)` — never `all-defined-out` — mirroring the TS
  curated `core/public` boundary (architecture §1.3). Internal helpers (`json-object?`,
  `valid-id?`, `only-keys?`, etc.) are **not** provided.
- **Test framework:** `rackunit`; the test lives under `mcp/core/types/test/` and is
  discovered by `raco test`.
- **No batch guard:** per J3, no batch predicate is defined or provided; the test asserts
  its absence by export introspection.

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None.** This module performs no I/O and contacts no service. The only externally required
artifacts are:

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime (v9.1 installed) | compile + run module and tests (`raco`, `rackunit`); `raco` at `/snap/bin/raco` | system install (`racket --version` ≥ 8.0) | n/a |
| Item 001 `constants.rkt` | guards require `JSONRPC-VERSION` | produced by item 001 in the same collection | n/a |
| `typescript-sdk/` checkout | **only** the optional TS-parity cross-check reads `guards.test.ts` from it | already present at repo root: `typescript-sdk/packages/core/test/types/guards.test.ts` | n/a |

There are explicitly **no** databases, message queues, HTTP servers, or network
dependencies for this item. (A harmless `/home/rev/.bash_env: Permission denied` line may
print on stderr when running shell commands — ignore it.)

### Environment Configuration

- **Environment variables:** none required.
- **Secrets:** none.
- **Config files:** none.
- **Ports:** none must be free.
- **Working directory:** run `raco test` from the **repo root**
  (`/home/rev/Linux/Projects/racket_mcp`) so the `mcp/...` collection path resolves. The
  optional TS cross-check anchors its path to the test source via `define-runtime-path`, so
  it does not depend on cwd; but `raco test mcp/...` collection resolution does.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0.
  - `test -f mcp/core/types/constants.rkt` → item 001 present.
  - (optional cross-check) `test -f typescript-sdk/packages/core/test/types/guards.test.ts`.

### Manual Validation Checklist

- [ ] **Build/compile succeeds:** `raco make mcp/core/types/guards.rkt` compiles with no
      errors.
- [ ] **Module loads in isolation:** from repo root,
      `racket -e '(require (file "mcp/core/types/guards.rkt"))'` succeeds.
- [ ] **Tests pass:** `raco test mcp/core/types/test/guards-test.rkt` → all checks pass,
      exit 0.
- [ ] **Collection tests pass:** `raco test mcp/core/types/` → exit 0 (item 001 + 002).
- [ ] **Services started:** N/A (no services).
- [ ] **Application runs:** N/A (library module; "running" = require + REPL inspect below).
- [ ] **Feature verified (REPL):** from repo root,
      `racket -e '(require (file "mcp/core/types/guards.rkt") (file "mcp/core/types/constants.rkt")) (list (is-jsonrpc-request? (hasheq (quote jsonrpc) JSONRPC-VERSION (quote id) 1 (quote method) "ping")) (is-jsonrpc-notification? (hasheq (quote jsonrpc) JSONRPC-VERSION (quote method) "x")) (is-jsonrpc-response? (hasheq (quote jsonrpc) JSONRPC-VERSION (quote id) 1 (quote result) (hasheq))) (is-jsonrpc-error? (hasheq (quote jsonrpc) JSONRPC-VERSION (quote error) (hasheq (quote code) -32600 (quote message) "x"))))'`
      prints `(#t #t #t #t)`.
- [ ] **No-batch verified (REPL):** the same require followed by
      `(dynamic-require (file "mcp/core/types/guards.rkt") 'is-jsonrpc-batch? (lambda () 'absent))`
      returns `'absent` (binding not present).
- [ ] **Ambiguity verified (REPL):** a both-`result`-and-`error` object returns `#f` from
      `is-jsonrpc-response?`, `is-jsonrpc-result-response?`, and `is-jsonrpc-error?`.
- [ ] **Never-raises verified:** each predicate over `42`, `'null`, `"s"`, `'()` returns
      `#f` without raising.
- [ ] **Drift detection:** temporarily flip one expected boolean in the test (e.g. assert a
      notification IS a request) and confirm the test FAILS, then revert — proving the
      truth-table assertions are live.
- [ ] **Health checks pass:** N/A (no running service).

### Expected Outcomes

Concrete, verifiable results — the module MUST export exactly these five predicates, each a
boolean-returning, never-raising procedure:

- `is-jsonrpc-request?`
- `is-jsonrpc-notification?`
- `is-jsonrpc-result-response?`
- `is-jsonrpc-error?`
- `is-jsonrpc-response?` (= result OR error response)

**Behavioral invariants:**
- Request/notification/result-response/error-response are mutually disjoint over valid
  envelopes; `is-jsonrpc-response?` ≡ `(or is-jsonrpc-result-response? is-jsonrpc-error?)`.
- An `id` is valid iff string or exact integer; `'null`, fractional, and boolean ids are
  rejected. Error-response `id` is optional; request/result-response `id` is required.
- Extra/unknown top-level keys reject (strict). A both-`result`-and-`error` object matches
  no envelope. Notification vs request is decided by `id` presence.
- **No** batch predicate is exported (`#rx"(?i:batch)"` matches no provided name;
  `is-jsonrpc-batch?` is unbound).

**Test outcome:** `raco test mcp/core/types/` reports all checks passing, 0 failures, 0
errors; the truth-table test's check count is high (≳ 50 individual `check-*` across the
five tables, the cross-cutting never-raises set, the ambiguous-shapes set, and the
no-batch introspection block).

**Total public bindings provided:** 5 (the five predicates; zero batch predicates).

### Validation Results

```markdown
## Validation Results
- [ ] Service started: N/A (pure-predicate module, no services)
- [ ] Application started successfully: N/A (library; `require` + REPL inspect succeeded)
- [ ] Build verified: `raco make mcp/core/types/guards.rkt` clean
- [ ] Module load verified: `(require (file ".../guards.rkt"))` succeeds
- [ ] Tests verified: `raco test mcp/core/types/` → 0 failures, 0 errors
- [ ] Truth table verified: all five predicates accept/reject per the tables (request, notification, result, error, response)
- [ ] Ambiguous shapes verified: result+error → all false; id+method+result → all false; id-presence discriminates notif vs request
- [ ] id validity verified: string + exact-int accepted; 'null / fractional / boolean rejected; error id optional, request/result id required
- [ ] Union identity verified: is-jsonrpc-response? ≡ (or result error) over the full fixture set
- [ ] No-batch verified: no provided name matches /batch/i; is-jsonrpc-batch? unbound; positive control confirms 5 predicates exported
- [ ] Never-raises verified: predicates return #f (not raise) on 42, 'null, "s", '(), mutable/string-keyed hashes
- [ ] Drift detection: deliberately wrong assertion FAILED as expected, then reverted
- [ ] (optional) TS cross-check verified against guards.test.ts inline value set
- [ ] Database tables verified: N/A
- [ ] API endpoints verified: N/A
- [ ] Screenshots captured: N/A (no UI)
```

---

## Decisions & Trade-offs

To be updated during implementation.

---

## Completion Reminder

On completion, the implementer MUST:

1. **Update `docs/aide/progress.md`** — advance the `mcp/core/types/guards.rkt` deliverable
   line under Stage S1 from 📋 → 🚧 (when starting) → ✅ (when delivered and acceptance
   criteria pass). Do **not** check Stage-S1 acceptance boxes owned by other items
   (round-trip fixtures, façade normalization, error encode/decode); only the
   guards-related S1 acceptance box (the type-guard truth-table / `guards.rkt` deliverable)
   may be checked once this item's test passes. Never revert an icon backward.
2. **Touch the parity-matrix rows** per Stage S1 discipline (roadmap "Parity discipline
   applies to every stage"): advance the roadmap §9 / progress row for `guards.ts` (under
   `core/types/*`) toward `partial` (the predicates exist and are truth-table-tested; full
   conformance exercise lands later). Per item 009 the broader `core/types/*` row flip to
   `partial` is the S1 closeout's job, so here record only that the `guards.ts` sub-row is
   satisfied — do not prematurely flip sibling rows.
3. Leave the sibling `core/types/*` deliverables (constants — already delivered by item 001;
   spec types, façade, errors) at their current status — this item delivers only
   `guards.rkt`.
