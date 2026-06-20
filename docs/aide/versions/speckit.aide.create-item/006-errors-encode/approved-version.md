# Work Item 006: Error hierarchy + ENCODE path (exn → JSON-RPC)

> **Queue:** `docs/aide/queue/queue-001.md` — Item 006
> **Stage:** S1 (Foundation: types, constants, guards, errors — L0 part 1)
> **Module:** M2 (Errors) — `mcp/core/errors.rkt` sub-unit (the exn↔JSON-RPC seam) —
>   **this item builds the ENCODE half only.**
> **Source vision:** `docs/aide/vision.md` §4.8 line 110 (Errors — mirrors
>   `core/errors/sdkErrors`, `core/auth/errors`): "`SdkError` hierarchy with stable error
>   codes, plus `ProtocolError` for wire-level errors → `mcp/core/errors.rkt` using Racket
>   `exn` subtypes (`exn:fail:mcp`, `exn:fail:mcp:protocol`, `exn:fail:mcp:auth`)"; G1
>   line 34 (wire-protocol parity — "every … error type in both spec revisions has a
>   corresponding Racket struct + contract").
> **Source roadmap:** `docs/aide/roadmap.md` Stage S1 → Deliverables line 84
>   (`mcp/core/errors.rkt` — `exn:fail:mcp`, `:protocol`, `:auth` subtypes with stable
>   codes; constructors + predicates; the single exn↔JSON-RPC-error conversion point
>   "Covers **both directions**: (a) *encode* … (b) *decode* …") and the test line 86
>   (`mcp/core/test/errors-test.rkt` — "exn↔JSON-RPC mapping in **both** directions").
>   **This item delivers direction (a) ENCODE; item 007 delivers (b) DECODE into the same
>   file.**
> **Source architecture:** `docs/aide/architecture.md` §4.1 line 328 (the **error-to-wire
>   boundary** — "M2 owns the single conversion point exn↔JSON-RPC error so malformed input
>   never crashes the engine"), **M2** line 76–79 (Errors module — "Racket `exn` subtypes
>   (`exn:fail:mcp`, `:protocol`, `:auth`) with stable codes; predicates + constructors"),
>   §1.3 line 50 (public/internal boundary — `exn` subtypes are part of the external
>   error-type interface).
> **Reference impl (authoritative):** MCP TypeScript SDK v2 at `typescript-sdk/` —
>   `packages/core/src/types/errors.ts` (86 lines; `ProtocolError` + `UrlElicitationRequiredError`
>   + `UnsupportedProtocolVersionError`) and `packages/core/src/types/enums.ts` lines 5–25
>   (`ProtocolErrorCode` enum — the authoritative code numbers). **This item is the ENCODE
>   half of the conversion `errors.ts` performs; item 007 will add the DECODE half
>   (`ProtocolError.fromError`, lines 21–39) into the SAME `errors.rkt`.**
> **Delivered siblings (the FORMAT + rigor bar):** `docs/aide/items/003-spec-types-2025-11-25.md`
>   (✅ delivered) and `docs/aide/items/005-public-types-and-normalized-superset-facade.md`
>   (📨 specified). Their structure, depth, and Decisions discipline are the bar this spec
>   meets.
> **Status:** 📨 Specified (not yet implemented) — ENCODE half. DECODE half is item 007;
>   the file is NOT complete until 007 lands.

---

## Description

Implement `mcp/core/errors.rkt`, the **M2 Errors module** — specifically the **error
hierarchy** and the **ENCODE** direction of the single exn↔JSON-RPC-error conversion point
(architecture §4.1 error-to-wire boundary, line 328). Two deliverables, one file:

1. **The Racket exception hierarchy.** Three `exn`-derived struct subtypes that mirror the TS
   SDK's `ProtocolError` family (`typescript-sdk/packages/core/src/types/errors.ts`):
   - `exn:fail:mcp` — the **base** MCP error: a struct subtype of Racket's built-in
     `exn:fail` carrying a stable numeric `code` and an optional structured `data` payload.
     This is the Racket analogue of `ProtocolError` (errors.ts:8 — `class ProtocolError
     extends Error` with `public readonly code`, `message`, `public readonly data?`).
   - `exn:fail:mcp:protocol` — a subtype of `exn:fail:mcp` for **wire/protocol-level**
     errors (the JSON-RPC error codes — parse / invalid-request / method-not-found /
     invalid-params / internal, plus the MCP protocol codes). Mirrors `ProtocolError`'s
     wire-error role.
   - `exn:fail:mcp:auth` — a subtype of `exn:fail:mcp` for **authentication/authorization**
     errors (vision §4.8 — `core/auth/errors.ts`). It carries the same `code`/`data` and adds
     no new required field in S1 (the auth-specific fields — `error_uri`, OAuth `error`
     string — are an S6/S7 concern; this struct reserves the subtype so auth code can raise a
     discriminable error now without restructuring later).

   Each subtype ships a **constructor** (`make-…`) and a **predicate** (`…?`), and the base
   ships a `code`/`data` accessor pair. Stable codes come from `constants.rkt` (item 001) —
   never re-literaled.

2. **The ENCODE function** `exn->jsonrpc-error` — the one-way map `exn → JSON-RPC error
   object`. It takes any Racket exception and returns a **`{code, message, data?}`** JSON-RPC
   error object in the EXACT representation the spec modules already model (the `jsonrpc-error`
   struct / its `jsonrpc-error->json` jsexpr — see §Representation conventions):
   - An `exn:fail:mcp` (or any subtype) → `{code = (exn:fail:mcp-code e), message =
     (exn-message e), data?}` (the optional `data` field emitted only when present).
   - A **generic** `exn:fail` (or any non-mcp exception) → the **InternalError** fallback:
     `{code = INTERNAL-ERROR (-32603), message = (exn-message e)}`. This is the "malformed
     input never crashes the engine" guarantee (architecture §4.1): whatever an inner handler
     throws, the boundary turns it into a well-formed `-32603` error object rather than
     propagating.

This is **HALF** of the single conversion point. Item 007 adds the **DECODE** direction
(a received JSON-RPC error object → the matching typed `exn:fail:mcp:*`, mirroring
`ProtocolError.fromError`, errors.ts:21–39: `-32042` → a URL-elicitation-required error,
`-32004` → an unsupported-protocol-version error, otherwise a generic protocol error) into
the SAME `errors.rkt`. **This item MUST design the file layout, the struct fields, and the
`provide` block so 007 extends them additively** — see §Decisions "designing for 007's
decode extension". Until 007 lands, `errors.rkt` is the encode half only; the roadmap S1
`errors.rkt` deliverable is not fully ✅ until both halves are in.

This module sits in M2, one layer beside M1 (`core/types/*`). It depends on `constants.rkt`
(item 001) for the codes and — for the encode target shape — must be **consistent with** the
`jsonrpc-error` struct that the spec modules (003/004) already model (`{code, message,
data?}`, a symbol-keyed `hasheq`). See §Representation conventions for the precise coupling
and the decision on whether to emit a raw jsexpr `hasheq` or a `jsonrpc-error` struct.

### Representation conventions (the encode target shape — non-negotiable for parity)

The ENCODE function produces a **JSON-RPC error object**. Items 003/004 already model this
shape twice (the struct + its serializer); 006 MUST be consistent with both:

- **The struct shape.** `spec-2025-11-25.rkt:323` defines
  `(struct jsonrpc-error (code message data) #:transparent)` with
  `jsonrpc-error/c = (struct/c jsonrpc-error exact-integer? string? (opt/c jsexpr-value?))`
  (line 324–325). The `data` field is the shared `absent` sentinel when absent
  (`spec-2025-11-25.rkt:55`, `(define absent (string->uninterned-symbol "absent"))`).
- **The wire jsexpr shape.** `jsonrpc-error->json` (line 328–330) serializes that struct to
  a symbol-keyed `hasheq`: `(hasheq 'code … 'message …)` with `'data` emitted **only when
  present** (the `put` helper omits an `absent` value — line 80). So the wire object is
  `{"code": <int>, "message": <string>}` plus `"data": <jsexpr>` iff data is present. There is
  NEVER a `"data": null` for absent data (the absent-vs-null rule, item 003 Representation
  conventions).
- **DECISION (encode return type — see §Decisions, settle in implementation):** `errors.rkt`'s
  `exn->jsonrpc-error` returns a **`jsonrpc-error` struct** (re-using the 003/004 struct), NOT
  a raw jsexpr `hasheq`. Rationale: (a) the struct is the typed in-engine representation and
  the protocol layer (S3) wants the struct, not a loose hash; (b) the struct already has a
  serializer (`jsonrpc-error->json`) and a contract (`jsonrpc-error/c`), so the wire bytes are
  produced by ONE serializer, not duplicated here; (c) item 007's DECODE consumes a
  `jsonrpc-error` struct symmetrically. A thin convenience wrapper `exn->jsonrpc-error-jsexpr`
  MAY also be provided (= `(jsonrpc-error->json (exn->jsonrpc-error e))`) for callers that want
  the wire hash directly, but the canonical encode result is the struct. **The test asserts
  both** the struct's `code`/`message`/`data` AND the serialized jsexpr's `'code`/`'message`.
- **`data` carriage.** The exn's `data` field uses the SAME `absent` sentinel as 003/004 (so
  an `exn:fail:mcp` with no data encodes to a `jsonrpc-error` whose `data` is `absent`, which
  the serializer omits). Import the sentinel from one place — see §Decisions "data carriage".
- **No I/O, no `'null` confusion.** The module touches no ports; JSON null (if it ever appears
  inside a `data` payload) is the symbol `'null` per the read-json convention, but encode does
  not synthesize `'null` — absent data is `absent`, not `'null`.

---

## The build contract — exn hierarchy + encode mapping (enumerate ALL)

### Part A — the exception hierarchy (struct subtypes of `exn:fail`)

Racket models exceptions as transparent structs; a custom error type is a `struct` whose
super-type is an existing `exn` struct, so `(raise (make-…))` is catchable by
`with-handlers`/`exn:fail?` and discriminable by the new predicate. The base extends
`exn:fail` (which itself carries `message` + `continuation-marks` — do NOT redeclare those;
the subtype adds ONLY the new fields).

| Racket type | Super-type | Added fields | Constructor | Predicate | Mirrors (errors.ts) |
|---|---|---|---|---|---|
| `exn:fail:mcp` | `exn:fail` | `code` (exact-integer), `data` (jsexpr-value \| `absent`) | `make-mcp-error` | `mcp-error?` | `ProtocolError` (line 8) — `code`/`message`/`data?` |
| `exn:fail:mcp:protocol` | `exn:fail:mcp` | — (inherits `code`/`data`) | `make-protocol-error` | `protocol-error?` | `ProtocolError` wire-error role |
| `exn:fail:mcp:auth` | `exn:fail:mcp` | — (inherits `code`/`data`) | `make-auth-error` | `auth-error?` | `core/auth/errors.ts` (vision §4.8) |

> **Field layout (the load-bearing decision).** Racket's `exn:fail` already supplies
> `message` (string) and `continuation-marks`. Define the base as
> `(struct exn:fail:mcp exn:fail (code data) #:transparent)` — i.e. the FULL field order a
> constructor sees is `(message continuation-marks code data)` (super fields first, then the
> two new ones). The ergonomic constructors below hide that ordering:
> - `(make-mcp-error code message [data absent] [#:marks marks])` →
>   `(exn:fail:mcp message (or marks (current-continuation-marks)) code data)`.
> - `(make-protocol-error code message [data absent])` → the `exn:fail:mcp:protocol` variant.
> - `(make-auth-error code message [data absent])` → the `exn:fail:mcp:auth` variant.
> The subtypes add NO new fields in S1, so their constructors take the same `(code message
> [data])` shape; the auth struct merely reserves the discriminable subtype (vision §4.8) for
> S6/S7 OAuth fields without a later restructure.

> **Predicate discrimination (the testable property).** Because `exn:fail:mcp:protocol` and
> `exn:fail:mcp:auth` are sub-structs of `exn:fail:mcp`, Racket's auto-generated predicates
> nest correctly: `(mcp-error? (make-protocol-error …))` is `#t`, `(protocol-error?
> (make-protocol-error …))` is `#t`, but `(auth-error? (make-protocol-error …))` is `#f` and
> `(protocol-error? (make-mcp-error …))` is `#f`. `(exn:fail? (make-mcp-error …))` is `#t`
> (catchable by generic handlers). `(mcp-error? (make-exn:fail …))` / `(mcp-error?
> (/ 1 0))`-style generic exn is `#f`. The test enumerates this matrix.

> **Code accessors.** Provide `mcp-error-code` and `mcp-error-data` (the `struct`'s
> auto-generated `exn:fail:mcp-code` / `exn:fail:mcp-data`, re-provided under the friendly
> names). All three subtypes answer to `mcp-error-code`/`mcp-error-data` since they inherit
> the fields.

### Part B — the encode mapping (`exn → JSON-RPC error object`)

`exn->jsonrpc-error : exn? → jsonrpc-error?` (the canonical encoder). The mapping table —
each input class → the output `{code, message, data?}`:

| Input exn | `code` | `message` | `data` | Notes |
|---|---|---|---|---|
| `exn:fail:mcp` (base) | `(mcp-error-code e)` | `(exn-message e)` | `(mcp-error-data e)` (absent ⇒ omitted) | carries its own stable code |
| `exn:fail:mcp:protocol` | `(mcp-error-code e)` | `(exn-message e)` | `(mcp-error-data e)` | e.g. constructed with `INVALID-PARAMS` |
| `exn:fail:mcp:auth` | `(mcp-error-code e)` | `(exn-message e)` | `(mcp-error-data e)` | auth code (S6/S7 chooses the number) |
| **generic `exn:fail`** (non-mcp) | **`INTERNAL-ERROR` (-32603)** | `(exn-message e)` | `absent` (omitted) | the FALLBACK — architecture §4.1 |
| any other `exn` (e.g. `exn:break`) | `INTERNAL-ERROR` | `(exn-message e)` | `absent` | see Decisions "what counts as fallback" |

> The encoder is a single `cond` on the input: `(mcp-error? e)` → copy code/message/data;
> else → `(jsonrpc-error INTERNAL-ERROR (exn-message e) absent)`. The result is a
> `jsonrpc-error` struct; `(jsonrpc-error->json result)` produces the wire jsexpr (a
> symbol-keyed `hasheq` with `'code`/`'message` and `'data` iff present).

> **Stable-code reuse (HARD requirement).** The codes are imported from `constants.rkt`
> (item 001) — `INTERNAL-ERROR` (-32603), and for the protocol-error constructors used in
> tests `PARSE-ERROR` (-32700), `INVALID-REQUEST` (-32600), `METHOD-NOT-FOUND` (-32601),
> `INVALID-PARAMS` (-32602), plus the MCP codes `RESOURCE-NOT-FOUND` (-32002),
> `MISSING-REQUIRED-CLIENT-CAPABILITY` (-32003), `UNSUPPORTED-PROTOCOL-VERSION` (-32004),
> `URL-ELICITATION-REQUIRED` (-32042). The module re-literals NONE of these numbers; the test
> asserts the encoded `code` `=` the named constant, NOT a magic number. (`constants.rkt`
> ProtocolErrorCode parity is verified against `enums.ts:5–25`.)

### Part C — `provide` surface (designed for 007 to extend)

`errors.rkt` provides (curated, no `all-defined-out`):

- `(struct-out exn:fail:mcp)` — constructor/predicate/accessors for the base.
- `(struct-out exn:fail:mcp:protocol)`, `(struct-out exn:fail:mcp:auth)`.
- the friendly constructors `make-mcp-error`, `make-protocol-error`, `make-auth-error`.
- the friendly predicates `mcp-error?`, `protocol-error?`, `auth-error?`.
- the friendly accessors `mcp-error-code`, `mcp-error-data`.
- the encoder `exn->jsonrpc-error` (and optionally `exn->jsonrpc-error-jsexpr`).
- re-export the `jsonrpc-error` struct shape it produces, OR document that callers get it from
  the spec module — see §Decisions "where the jsonrpc-error struct comes from".

> **007-extension contract (state explicitly in a file comment).** Item 007 will add
> `jsonrpc-error->exn` (DECODE) and the typed-error helpers (`-32042` →
> URL-elicitation-required exn; `-32004` → unsupported-protocol-version exn) into THIS file.
> 006 MUST: (a) define the hierarchy so 007's decode can `make-protocol-error`/`make-auth-error`
> with no new struct; (b) leave a clearly-commented "DECODE (item 007)" section anchor in the
> file; (c) make the `provide` additive (007 appends decode bindings, does not edit 006's
> exports); (d) keep the file's `require` minimal (007 adds nothing beyond what 006 + 003's
> `jsonrpc-error` shape already pull in).

---

## Acceptance criteria

- [ ] `mcp/core/errors.rkt` exists as `#lang racket/base` with `(require racket/contract)` and
      `(require (only-in "types/constants.rkt" INTERNAL-ERROR PARSE-ERROR INVALID-REQUEST
      METHOD-NOT-FOUND INVALID-PARAMS RESOURCE-NOT-FOUND MISSING-REQUIRED-CLIENT-CAPABILITY
      UNSUPPORTED-PROTOCOL-VERSION URL-ELICITATION-REQUIRED))` and an explicit curated
      `(provide …)` (no `all-defined-out`). **Note the path:** `errors.rkt` is at
      `mcp/core/`, so constants is at `"types/constants.rkt"` (one dir down), NOT
      `"constants.rkt"`.
- [ ] **The three exn subtypes exist** as struct subtypes of `exn:fail`:
      `(struct exn:fail:mcp exn:fail (code data) #:transparent)`,
      `(struct exn:fail:mcp:protocol exn:fail:mcp () #:transparent)`,
      `(struct exn:fail:mcp:auth exn:fail:mcp () #:transparent)`.
- [ ] **Each subtype constructs with its stable code.** `(make-protocol-error INVALID-PARAMS
      "bad params")` yields a value `v` with `(mcp-error-code v)` `=` `INVALID-PARAMS`
      (`-32602`); `(make-mcp-error INTERNAL-ERROR "x")` `=` `-32603`; an auth error constructs
      with whatever code is passed. The codes are the `constants.rkt` bindings, asserted by
      `=` to the named constant.
- [ ] **Predicates discriminate correctly** (the full matrix): `mcp-error?` is `#t` on all
      three subtypes; `protocol-error?` is `#t` only on `exn:fail:mcp:protocol` (and `#f` on
      base / auth); `auth-error?` only on `exn:fail:mcp:auth`; all three satisfy `exn:fail?`;
      a generic `exn:fail` (e.g. from `(error "boom")` or `(car '())`) satisfies NONE of
      `mcp-error?`/`protocol-error?`/`auth-error?`.
- [ ] **Constructors carry message + continuation-marks correctly.** `(exn-message
      (make-mcp-error INTERNAL-ERROR "msg"))` is `"msg"`; the value is `raise`-able and
      catchable by `(with-handlers ([mcp-error? …]) (raise (make-protocol-error …)))`; the
      continuation-marks field is populated (the constructor defaults it to
      `(current-continuation-marks)`).
- [ ] **THE QUEUE'S CORE TESTABLE CLAIM — ENCODE produces a spec-correct error object:**
      - `(exn->jsonrpc-error (make-protocol-error INVALID-PARAMS "bad"))` → a `jsonrpc-error?`
        struct with `code` `=` `INVALID-PARAMS`, `message` `=` `"bad"`, `data` `absent`.
      - `(exn->jsonrpc-error (make-mcp-error RESOURCE-NOT-FOUND "nope" (hasheq 'uri "x")))` →
        `code` `=` `RESOURCE-NOT-FOUND`, `data` `=` `(hasheq 'uri "x")` (preserved).
      - **The InternalError fallback:** `(exn->jsonrpc-error (make-exn:fail "boom"
        (current-continuation-marks)))` — or any non-mcp exn, e.g. caught from `(car '())` —
        → `code` `=` `INTERNAL-ERROR` (`-32603`), `message` `=` the exn's message, `data`
        `absent`. **This -32603 fallback is a HARD requirement, not optional.**
- [ ] **Serialized wire shape is spec-correct.** `(jsonrpc-error->json (exn->jsonrpc-error
      e))` is a symbol-keyed `hasheq` with `'code` (exact-integer) and `'message` (string);
      `'data` present **iff** the exn had data; NEVER `'data: 'null` for absent data
      (absent-vs-null rule). The result satisfies `is-jsonrpc-error?`'s inner
      `valid-error-object?` shape (code+message present, well-typed).
- [ ] **Codes are imported, not re-literaled.** A `grep` for the integer literals `-32603`,
      `-32602`, etc. in `errors.rkt` finds NONE (except possibly in comments); all codes flow
      from `constants.rkt`. The test asserts `(= (jsonrpc-error-code …) INVALID-PARAMS)` using
      the imported binding.
- [ ] **`raco test` passes** (exit 0) over `mcp/core/test/errors-test.rkt` and the broader
      `mcp/core/` tree (per the `raco`-broken workaround below, run via
      `racket mcp/core/test/errors-test.rkt` directly). Module + test compile and load cleanly
      alongside items 001–005.
- [ ] **Portability (NFR — roadmap line 96):** `errors.rkt` requires ONLY `racket/base`,
      `racket/contract`, and `types/constants.rkt` (which itself needs only `racket/base`). NO
      subprocess/socket module, NO I/O at module load. (It does NOT require the full spec
      module just for the `jsonrpc-error` struct — see §Decisions "where the jsonrpc-error
      struct comes from".)
- [ ] **007-readiness:** the file has a commented "DECODE (item 007)" anchor, the `provide` is
      structured to be appended to, and the hierarchy supports `make-protocol-error`/`make-auth-error`
      construction from a decoded code/message/data with no new struct. A comment documents
      that `errors.rkt` is the encode half and 007 completes it.
- [ ] **Parity-matrix discipline:** progress.md Stage S1 `errors.rkt` deliverable line is
      advanced 📋 → 🚧 (this item is the ENCODE half — do NOT flip ✅ until item 007's decode
      lands); the §9 / parity row for `errors.rkt` is touched per Stage-S1 discipline.
      Sibling rows (`constants`, `guards`, `spec-*`, `types.rkt`) untouched.

---

## Implementation steps

1. **Confirm inputs are green.** `mcp/core/types/constants.rkt` (item 001) loads and exports
   the codes; `mcp/core/types/spec-2025-11-25.rkt` (item 003) loads (for cross-checking the
   `jsonrpc-error` struct shape the encoder targets). Run them directly per the workaround.
   Confirm `mcp/core/test/` does NOT yet exist — create it (the test dir is `mcp/core/test/`,
   NOT `mcp/core/types/test/`).
2. **Re-read the reference** `typescript-sdk/packages/core/src/types/errors.ts` (the
   `ProtocolError` constructor: `code`, `message`, `data?`) and `enums.ts:5–25`
   (`ProtocolErrorCode`) to confirm the code numbers match `constants.rkt`. Note that
   `errors.ts` is a FLAT class hierarchy (`ProtocolError` + two subclasses); the Racket
   `protocol`/`auth` split is the architecture's `exn:fail:mcp:*` decomposition (vision §4.8),
   richer than TS's single `ProtocolError` — document the mapping in Decisions.
3. **Write the hierarchy.** `#lang racket/base`, `(require racket/contract)`,
   `(require (only-in "types/constants.rkt" …codes…))`. Define the `absent` sentinel access
   (see Decisions — import from the spec module OR redefine + document). Define the three
   structs `(struct exn:fail:mcp exn:fail (code data) #:transparent)` and the two empty
   subtypes. Define `make-mcp-error`/`make-protocol-error`/`make-auth-error` with the
   `(code message [data absent] [#:marks])` signature. Define the friendly
   predicates/accessors.
4. **Write the encoder** `exn->jsonrpc-error`: a `cond` — `(mcp-error? e)` →
   `(jsonrpc-error (mcp-error-code e) (exn-message e) (mcp-error-data e))`; else →
   `(jsonrpc-error INTERNAL-ERROR (exn-message e) absent)`. Decide where `jsonrpc-error`
   comes from (see Decisions); optionally add `exn->jsonrpc-error-jsexpr`.
5. **Add contracts.** `make-mcp-error` etc. via `contract-out` OR raw + a `…/c` (match 003's
   choice: raw structs + the encoder takes/returns contracted values; recommend
   `(-> exn? jsonrpc-error?)` on `exn->jsonrpc-error`). Keep the constructor signatures
   contract-checked (`exact-integer?` code, `string?` message, `jsexpr-value?`-or-`absent`
   data).
6. **Add the curated `provide`** (Part C) and the commented "DECODE (item 007)" anchor.
7. **Write the test** `mcp/core/test/errors-test.rkt` (see Testing strategy).
8. **Run** `racket mcp/core/test/errors-test.rkt` from repo root (workaround); fix failures.
   Likely failures: wrong super-field order in the struct (message/marks vs code/data);
   forgetting to default `continuation-marks`; `data: 'null` instead of omitted; re-literaled
   code; importing constants from the wrong relative path (`"constants.rkt"` vs
   `"types/constants.rkt"`).
9. **Update progress.md + parity matrix** (Completion Reminder) — advance `errors.rkt` to 🚧
   (NOT ✅; 007 owns the ✅ flip).

---

## Testing strategy

**Test file:** `mcp/core/test/errors-test.rkt` (`#lang racket/base`, `(require rackunit
(file …/errors.rkt) (only-in …/types/constants.rkt …) (only-in …/types/spec-2025-11-25.rkt
jsonrpc-error? jsonrpc-error-code jsonrpc-error-message jsonrpc-error-data
jsonrpc-error->json))`). Rackunit checks run at module top level (so `racket <file>` exercises
them — see Testing Prerequisites). Five parts.

### Part 1 — construction with stable codes

- `(check = (mcp-error-code (make-mcp-error INTERNAL-ERROR "x")) INTERNAL-ERROR)`.
- `(check = (mcp-error-code (make-protocol-error INVALID-PARAMS "x")) INVALID-PARAMS)`.
- `(check = (mcp-error-code (make-protocol-error METHOD-NOT-FOUND "x")) METHOD-NOT-FOUND)`.
- `(check = (mcp-error-code (make-auth-error MISSING-REQUIRED-CLIENT-CAPABILITY "x"))
  MISSING-REQUIRED-CLIENT-CAPABILITY)`.
- `(check-equal? (exn-message (make-mcp-error INTERNAL-ERROR "boom")) "boom")`.
- `(check-true (present? …))` / data carriage: `(make-mcp-error RESOURCE-NOT-FOUND "x"
  (hasheq 'uri "y"))` has `(mcp-error-data …)` `=` `(hasheq 'uri "y")`; with no data arg, data
  is `absent`.
- **Codes-are-constants (anti-magic):** assert each `code` `=` the imported `constants.rkt`
  binding, NOT a literal — so a future code-number drift in constants.rkt is caught here.

### Part 2 — predicate discrimination matrix

Build one of each: `b = (make-mcp-error INTERNAL-ERROR "b")`,
`p = (make-protocol-error INVALID-PARAMS "p")`, `a = (make-auth-error -1 "a")`,
`g = (make-exn:fail "g" (current-continuation-marks))` (a generic exn), and a thrown-then-caught
generic exn `(with-handlers ([exn:fail? values]) (car '()))`. Assert the full matrix:

| value | `exn:fail?` | `mcp-error?` | `protocol-error?` | `auth-error?` |
|---|---|---|---|---|
| `b` | #t | #t | #f | #f |
| `p` | #t | #t | #t | #f |
| `a` | #t | #t | #f | #t |
| `g` | #t | #f | #f | #f |
| caught `(car '())` | #t | #f | #f | #f |

Also: `(check-true (with-handlers ([mcp-error? (λ (_) #t)]) (raise p)))` — a raised mcp error
is catchable by the predicate handler.

### Part 3 — ENCODE produces a spec-correct error object (the queue's core requirement)

- **mcp subtype → its own code:** `(define j (exn->jsonrpc-error (make-protocol-error
  INVALID-PARAMS "bad")))`; `(check-true (jsonrpc-error? j))`;
  `(check = (jsonrpc-error-code j) INVALID-PARAMS)`;
  `(check-equal? (jsonrpc-error-message j) "bad")`;
  `(check-true (absent? (jsonrpc-error-data j)))`.
- **data preserved:** `(exn->jsonrpc-error (make-mcp-error RESOURCE-NOT-FOUND "nf"
  (hasheq 'uri "u")))` → `data` `=` `(hasheq 'uri "u")`.
- **THE -32603 FALLBACK (HARD):** `(define j2 (exn->jsonrpc-error (make-exn:fail "kaboom"
  (current-continuation-marks))))`; `(check = (jsonrpc-error-code j2) INTERNAL-ERROR)`;
  `(check-equal? (jsonrpc-error-message j2) "kaboom")`; `(check-true (absent?
  (jsonrpc-error-data j2)))`. Also exercise a REAL thrown generic exn:
  `(define j3 (exn->jsonrpc-error (with-handlers ([exn:fail? values]) (vector-ref (vector) 0))))`;
  assert `(= (jsonrpc-error-code j3) INTERNAL-ERROR)`.
- **auth subtype encodes with its code:** `(exn->jsonrpc-error (make-auth-error
  MISSING-REQUIRED-CLIENT-CAPABILITY "no cap"))` → `code` `=`
  `MISSING-REQUIRED-CLIENT-CAPABILITY`.

### Part 4 — serialized wire jsexpr is spec-correct (absent-vs-null)

- `(define w (jsonrpc-error->json (exn->jsonrpc-error (make-protocol-error INVALID-REQUEST
  "x"))))`; `(check-true (hash-eq? w))`; `(check = (hash-ref w 'code) INVALID-REQUEST)`;
  `(check-equal? (hash-ref w 'message) "x")`;
  **absent data omitted:** `(check-false (hash-has-key? w 'data))` — NOT `'data: 'null`.
- **present data emitted:** with `(make-mcp-error PARSE-ERROR "p" (hasheq 'detail "d"))`, the
  serialized hash HAS `'data` `=` `(hasheq 'detail "d")`.
- **valid-error-object shape:** the serialized hash satisfies the guards' inner shape — `'code`
  is an exact-integer and `'message` is a string (mirror `valid-error-object?` from
  `guards.rkt:118` to keep encode↔guard parity; the test MAY import `is-jsonrpc-error?` and
  wrap the error in a full envelope `(hasheq 'jsonrpc "2.0" 'id 1 'error w)` and assert
  `(is-jsonrpc-error? …)` is `#t` — proving the encoded object composes into a wire-valid
  error response).

### Part 5 — 007-readiness / file-shape (anti-vacuous, lightweight)

- Assert the constructors accept a decoded-style call (the shape 007's decode will use):
  `(make-protocol-error URL-ELICITATION-REQUIRED "url required" (hasheq 'elicitations '()))`
  constructs and `(protocol-error? …)` is `#t` and `(mcp-error-code …)` `=`
  `URL-ELICITATION-REQUIRED` — proving 007 can build a typed `-32042` error with no new struct.
- (Documentation check, not a code assertion:) the file contains the "DECODE (item 007)"
  anchor comment. The test header notes that the decode-direction tests (`-32042` →
  URL-elicitation exn; `-32004` → unsupported-version exn) are item 007's; this file's tests
  are encode-only.

### Edge cases the test must cover (do not leave implicit)

- **A non-`exn:fail` exception** (if reachable, e.g. a raised non-exn value caught and
  re-wrapped) — the encoder's `else` branch must still produce `-32603` and not crash. Test by
  passing the encoder a value that is `exn?` but not `mcp-error?` (use `make-exn:fail`).
  (Per Decisions "what counts as fallback", the encoder's contract is `(-> exn? …)`; a
  raised non-`exn?` value is the caller's responsibility to wrap before encoding.)
- **Empty / unusual messages:** `(make-mcp-error INTERNAL-ERROR "")` encodes with `message`
  `=` `""` (empty string is valid; not omitted).
- **`data` = a falsy-looking jsexpr** (`#f`, `'null`, `0`, `""`): all are PRESENT (not
  `absent`) and must be emitted — confirm `(make-mcp-error INTERNAL-ERROR "x" 'null)` encodes
  with `'data` `=` `'null` in the wire hash (a deliberately-present null, distinct from absent).
- **Code is preserved exactly** (no coercion): a negative code round-trips as the same exact
  integer.

---

## Dependencies

- **Upstream work items:**
  - **Item 001** (`mcp/core/types/constants.rkt`, ✅) — the stable codes `INTERNAL-ERROR`,
    `PARSE-ERROR`, `INVALID-REQUEST`, `METHOD-NOT-FOUND`, `INVALID-PARAMS`,
    `RESOURCE-NOT-FOUND`, `MISSING-REQUIRED-CLIENT-CAPABILITY`, `UNSUPPORTED-PROTOCOL-VERSION`,
    `URL-ELICITATION-REQUIRED`. Imported via `(only-in "types/constants.rkt" …)`. MUST be green.
  - **Item 003** (`mcp/core/types/spec-2025-11-25.rkt`, ✅) — the `jsonrpc-error` struct
    (`{code message data}`, line 323), its `jsonrpc-error/c` contract (324), serializer
    `jsonrpc-error->json` (328), and the `absent` sentinel (55). The encode target shape MUST
    be consistent with these. **See §Decisions** on whether `errors.rkt` imports the struct
    from 003 or defines its own — this is a Portability-vs-DRY trade-off the implementer
    settles.
  - **Item 002** (`guards.rkt`, ✅) — the inner `valid-error-object?` shape (line 118) and
    `is-jsonrpc-error?` (126); the test optionally composes the encoded object into a full
    envelope and asserts `is-jsonrpc-error?` for encode↔guard parity. (Not a module
    dependency of `errors.rkt` itself — test-only.)
- **Forward dependency — item 007 (DECODE):** item 007 adds `jsonrpc-error->exn` and the typed
  decoders (`-32042` → URL-elicitation-required exn, `-32004` → unsupported-protocol-version
  exn; mirrors `ProtocolError.fromError`, errors.ts:21–39) into THIS SAME `errors.rkt`. 006
  must leave the hierarchy + `provide` + a commented anchor ready for that. The roadmap S1
  `errors.rkt` deliverable (line 84) and the both-directions test (line 86) are not fully
  satisfied until 007 lands.
- **Downstream consumers (informational):** the protocol engine (S3) calls
  `exn->jsonrpc-error` at the request-handler boundary so a thrown handler error becomes a
  `-32603` (or typed) wire error instead of crashing the engine (architecture §4.1); the
  high-level server (S7b) RAISES `make-protocol-error URL-ELICITATION-REQUIRED …` which this
  encode path serializes (roadmap line 330).
- **Operates on:** in-memory `exn` values → a `jsonrpc-error` struct / jsexpr. No file/network
  I/O.
- **Tooling/runtime:** Racket ≥ 8.x (v9.1 installed; `raco` at `/snap/bin/raco` but BROKEN —
  see Testing Prerequisites); `rackunit`; the `typescript-sdk/` checkout (read for parity, not
  imported).

---

## Project-specific adaptations (Racket / exn structs / contracts / rackunit)

This template's "Required Services / database / API endpoint" framing does not apply: **this
is a pure-data module — exn struct subtypes + flat contracts + a pure encode function — with
no external services, no I/O at module load, no network, no database.** Adaptations:

- **Language:** `#lang racket/base` + `racket/contract`. The exn subtypes use Racket's native
  `struct` super-typing on `exn:fail` (NO class transliteration — G4). `raise`/`with-handlers`
  is the native error channel; the TS `throw new ProtocolError(...)` maps to
  `(raise (make-protocol-error …))`.
- **Structs not classes (G4):** transparent `struct`s subtyping `exn:fail`. TS's
  `class ProtocolError extends Error` with getters (`get elicitations`, errors.ts:53) becomes
  a flat-field struct + the optional `data` payload; the TS getters are item 007's concern
  (they read `data.elicitations` / `data.supported` on decode) and are NOT modeled as struct
  fields here.
- **TS-flat vs Racket-richer hierarchy:** `errors.ts` has ONE wire-error class
  (`ProtocolError`) plus two data-specialized subclasses. The architecture (vision §4.8,
  M2 line 79) specifies a `protocol`/`auth` SPLIT under `exn:fail:mcp`. So the Racket
  hierarchy is intentionally richer than the TS one — `exn:fail:mcp:protocol` carries TS's
  `ProtocolError` role; `exn:fail:mcp:auth` is the Racket analogue of `core/auth/errors.ts`
  (which TS keeps in a separate module). Document this 1-to-richer mapping in Decisions.
- **Flat contracts:** `(-> exn? jsonrpc-error?)` on the encoder; `exact-integer?` / `string?`
  / `(or/c absent? jsexpr-value?)` on the constructors. Match item 003's choice of raw structs
  + contracted functions (NOT `contract-out` on the structs themselves) unless the implementer
  prefers `contract-out` consistently — record the choice.
- **Naming:** kebab-case functions (`make-mcp-error`, `exn->jsonrpc-error`); predicates end in
  `?`; the exn struct names follow Racket's `exn:fail:…` convention (colon-separated, the ONE
  place colons appear, mirroring `exn:fail:read` etc.).
- **No services / no I/O:** the only file access is the test reading nothing (no fixtures
  needed — the test constructs exns and asserts in-memory; this differs from 003/005 which
  needed JSON fixtures). NO `fixtures/` dir for this item.

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None.** No I/O at module load, no service contacted. External artifacts:

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime (v9.1 installed) | compile + run module/tests (`rackunit`) | system install (`racket --version` ≥ 8.0) | n/a |
| Item 001 `types/constants.rkt` | imports the stable error codes | produced by item 001 | n/a |
| Item 003 `types/spec-2025-11-25.rkt` | the `jsonrpc-error` struct shape the encoder targets + `absent` (per Decisions, may import) | produced by item 003 | n/a |
| `typescript-sdk/` checkout | implementer reads `errors.ts` + `enums.ts` for parity | already present at repo root | n/a |

No databases, queues, HTTP servers, or network dependencies. No JSON fixtures (the test is
in-memory). (Harmless `/home/rev/.bash_env: Permission denied` on stderr — ignore.)

### Environment Configuration

- **Environment variables / secrets / config files:** none.
- **Ports:** none must be free.
- **Working directory:** run tests from the **repo root**
  (`/home/rev/Linux/Projects/racket_mcp`) so the `mcp/...` collection + relative requires
  (`"types/constants.rkt"`, `"types/spec-2025-11-25.rkt"`) resolve.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0.
  - `test -f mcp/core/types/constants.rkt` → item 001 present.
  - `test -f mcp/core/types/spec-2025-11-25.rkt` → item 003 present.
  - `mkdir -p mcp/core/test` if absent (the test dir is `mcp/core/test/`, NOT
    `mcp/core/types/test/`).

### Manual Validation Checklist

- [ ] **Build/compile:** `raco make mcp/core/errors.rkt` compiles clean — **BUT see the
      `raco`-broken note below; if `raco make` silently exits 1, use `racket -e '(require
      (file "mcp/core/errors.rkt"))'` to confirm the module compiles+loads.**
- [ ] **ENVIRONMENT QUIRK — `raco` IS BROKEN in this sandbox.** The `raco` snap wrapper
      (`/snap/bin/raco`) silently exits 1 here: `raco test …` and `raco make …` do NOT
      report results. **Run tests with sandboxed `racket <test-file.rkt>` DIRECTLY** —
      rackunit `check-*` forms run at module top level, so loading the file executes the
      suite; **silence + exit 0 = all checks passed**; a failed check prints a FAILURE block
      and the file still exits 0, so SCAN the output for `FAILURE` / `check-` lines, do not
      rely on the exit code alone. **Do NOT disable the `racket` sandbox** — that breaks
      `racket` itself in this environment. The canonical run is:
      `racket mcp/core/test/errors-test.rkt` from the repo root.
- [ ] **Module loads in isolation:** from repo root,
      `racket -e '(require (file "mcp/core/errors.rkt"))'` succeeds (no error printed).
- [ ] **Tests pass:** `racket mcp/core/test/errors-test.rkt` → exit 0, NO `FAILURE` lines in
      output.
- [ ] **Construction verified (REPL):** `(require (file "mcp/core/errors.rkt"))` then
      `(mcp-error-code (make-protocol-error -32602 "x"))` → `-32602`.
- [ ] **Predicate matrix verified (REPL):** `(protocol-error? (make-mcp-error -32603 "x"))` →
      `#f`; `(mcp-error? (make-protocol-error -32602 "x"))` → `#t`.
- [ ] **Encode verified (REPL):** `(jsonrpc-error-code (exn->jsonrpc-error (make-exn:fail
      "boom" (current-continuation-marks))))` → `-32603` (the fallback).
- [ ] **Absent-vs-null verified (REPL):** `(hash-has-key? (jsonrpc-error->json
      (exn->jsonrpc-error (make-protocol-error -32602 "x"))) 'data)` → `#f`.
- [ ] **Codes-imported verified:** `grep -nE '\-326[0-9][0-9]|\-3200[0-9]|\-32042'
      mcp/core/errors.rkt` finds matches ONLY in comments (not in code) — codes flow from
      `constants.rkt`.
- [ ] **Portability verified:** `errors.rkt`'s `require` list is exactly `racket/contract` +
      `types/constants.rkt` (+ optionally `types/spec-2025-11-25.rkt` per Decisions) — no
      subprocess/socket module.
- [ ] **007-anchor present:** the file contains a "DECODE (item 007)" comment anchor.
- [ ] **Drift detection:** flip one expected `check` (e.g. assert the fallback is `-32602`)
      and confirm the run prints a `FAILURE`; revert.
- [ ] **Health checks pass:** N/A.

### Expected Outcomes

The module MUST export the three exn subtypes (struct-out × 3), the three constructors, the
three predicates, the two accessors, and `exn->jsonrpc-error` (+ optional
`exn->jsonrpc-error-jsexpr`).

- **exn subtypes:** 3 (`exn:fail:mcp`, `exn:fail:mcp:protocol`, `exn:fail:mcp:auth`).
- **constructors:** 3 (`make-mcp-error`, `make-protocol-error`, `make-auth-error`).
- **predicates:** 3 (`mcp-error?`, `protocol-error?`, `auth-error?`) + the auto-generated
  struct predicates.
- **accessors:** `mcp-error-code`, `mcp-error-data`.
- **encode functions:** `exn->jsonrpc-error` (canonical) + optional
  `exn->jsonrpc-error-jsexpr`.
- **codes referenced (all from `constants.rkt`):** at minimum `INTERNAL-ERROR` (the fallback);
  the test exercises `PARSE-ERROR`, `INVALID-REQUEST`, `METHOD-NOT-FOUND`, `INVALID-PARAMS`,
  `RESOURCE-NOT-FOUND`, `MISSING-REQUIRED-CLIENT-CAPABILITY`, `UNSUPPORTED-PROTOCOL-VERSION`,
  `URL-ELICITATION-REQUIRED`.

**Test outcome:** `racket mcp/core/test/errors-test.rkt` → no `FAILURE`/error lines, exit 0.
Construction checks ≥ 4; predicate-matrix checks ≥ 10 (5 values × the predicate columns);
encode checks ≥ 5 (incl. the -32603 fallback); wire-shape checks ≥ 4 (incl. absent-data
omission). **Total ≥ ~25 rackunit checks.**

**Total public bindings provided:** 3 struct-outs + 3 constructors + 3 predicates +
2 accessors + 1–2 encode functions (~12–13 public bindings). (Exact count recorded during
implementation.)

### Validation Results

```markdown
## Validation Results (completed YYYY-MM-DD)
- [ ] Service started: N/A (pure-data module, no services)
- [ ] Application started successfully: N/A (library; `require` succeeds)
- [ ] Build verified: `racket -e '(require (file "mcp/core/errors.rkt"))'` succeeds
      (`raco make` skipped — raco broken in sandbox; documented in Testing Prerequisites)
- [ ] Module load verified: `(require (file ".../errors.rkt"))` succeeds
- [ ] Tests verified: `racket mcp/core/test/errors-test.rkt` → exit 0, 0 FAILURE lines,
      N checks passed
- [ ] Hierarchy verified: 3 exn subtypes (mcp / mcp:protocol / mcp:auth) subtype exn:fail
- [ ] Construction-with-code verified: each subtype constructs with its stable constants.rkt code
- [ ] Predicate-matrix verified: mcp?/protocol?/auth? discriminate correctly; generic exn ⇒ all #f
- [ ] Encode verified: mcp subtype → own code; non-mcp exn → INTERNAL-ERROR (-32603) fallback
- [ ] Wire-shape verified: serialized hash has 'code/'message; absent data OMITTED (not 'null)
- [ ] Codes-imported verified: no integer code literals in errors.rkt code (grep clean)
- [ ] Portability verified: requires only racket/contract + types/constants.rkt (+ spec per Decisions)
- [ ] 007-readiness verified: DECODE anchor present; provide additive; -32042 constructs typed error
- [ ] Drift detection: flipped fallback assertion → FAILURE printed; reverted → clean
- [ ] Database tables verified: N/A
- [ ] API endpoints verified: N/A
- [ ] Screenshots captured: N/A (no UI)
```

---

## Decisions & Trade-offs

**Seeded decisions the implementer confirms/records on delivery:**

- **Struct field layout (SETTLED — load-bearing).** Base is
  `(struct exn:fail:mcp exn:fail (code data) #:transparent)`. `exn:fail` already supplies
  `message` + `continuation-marks`; the subtype adds ONLY `code` + `data`, so the raw
  constructor order is `(exn:fail:mcp message marks code data)`. The friendly `make-mcp-error`
  hides this with signature `(code message [data absent] #:marks)` and defaults marks to
  `(current-continuation-marks)`. **Rationale:** subtyping the native `exn:fail` makes the
  errors catchable by ordinary `exn:fail?` handlers and by `error-display-handler`, and keeps
  `exn-message` working — re-implementing a parallel struct would break interop with Racket's
  exception machinery.
- **`protocol`/`auth` carry NO new fields in S1 (SETTLED).** `exn:fail:mcp:protocol` and
  `exn:fail:mcp:auth` are empty sub-structs `(… () #:transparent)`. Both inherit `code`/`data`.
  The auth subtype's OAuth-specific fields (`error_uri`, OAuth `error` string, errors.ts auth
  module) are deferred to S6/S7 and can be added additively (a further subtype or extra
  fields) without touching encode. **Rationale:** the architecture (vision §4.8) requires a
  *discriminable* auth error NOW; the *shape* of auth error data is not needed until the auth
  stage. Reserving the subtype avoids a later breaking restructure.
- **Where `exn->jsonrpc-error` lives (SETTLED).** It lives in `errors.rkt` (M2), NOT in the
  spec modules (M1). The architecture §4.1 names M2 as the owner of the single conversion
  point; M1 owns the wire *shapes*, M2 owns the exn↔wire *conversion*. The encoder returns the
  M1 `jsonrpc-error` struct — M2 depends on M1's shape, not vice-versa (the dependency
  direction matches the layer order: errors ride beside/above types).
- **Where the `jsonrpc-error` struct comes from (OPEN — implementer settles; recommendation
  below).** Two options for the encode target type:
  - **(a) Import from item 003** — `(require (only-in "types/spec-2025-11-25.rkt" jsonrpc-error
    jsonrpc-error? jsonrpc-error->json absent))` and have the encoder construct that struct.
    PRO: ONE `jsonrpc-error` type across the codebase; ONE serializer; no duplication; item 007
    symmetrically consumes the same struct. CON: `errors.rkt` then transitively requires the
    full spec module (≈2000 lines) — but the spec module is itself portable (only
    `racket/base` + `racket/contract` + `constants.rkt` + `json` conventions, NO
    subprocess/socket per item 003's NFR), so the Portability NFR (roadmap line 96, "no
    subprocess/socket") is STILL satisfied. **RECOMMENDATION: option (a)** — DRY wins and the
    Portability NFR is about subprocess/socket, not module size. Record the load-time cost as
    acceptable.
  - **(b) Define a local minimal `jsonrpc-error` in `errors.rkt`** and keep M1's separate.
    PRO: `errors.rkt` requires only `constants.rkt`. CON: TWO `jsonrpc-error` types that must
    be kept in sync — a parity hazard exactly like the one item 003 warns about; the protocol
    layer would have to convert between them. **Rejected unless** the spec-module import proves
    to pull in something non-portable (it does not). If chosen, the local struct MUST be
    `(struct jsonrpc-error (code message data) #:transparent)` IDENTICAL to 003's, and a test
    must assert field-compatibility.
  The acceptance criterion's Portability bullet is written to ALLOW option (a) (it lists
  `types/spec-2025-11-25.rkt` as an optional require). **Implementer records the final choice
  and confirms the require list contains no subprocess/socket module either way.**
- **How `data` is carried (SETTLED).** `data` uses the SAME `absent` sentinel as 003/004
  (`(string->uninterned-symbol "absent")`). It MUST be the SAME `eq?` binding so the serializer
  (`put`, which tests `absent?`) omits it correctly — therefore import `absent`/`absent?` from
  the spec module (option (a) above gives this for free; option (b) must import the sentinel
  alone or it will fail to omit). A present `data` (including a deliberately-present `'null`,
  `#f`, `0`, `""`) is carried verbatim and serialized; only `absent` is omitted.
- **The generic-exn → -32603 fallback (SETTLED — the core reliability guarantee).** Any
  `exn?` that is not `mcp-error?` encodes to `INTERNAL-ERROR` with the exn's message and no
  data. This is the architecture §4.1 "malformed input never crashes the engine" contract: the
  protocol boundary wraps handler errors so an arbitrary internal failure surfaces as a
  well-formed `-32603`, never as an unhandled crash. The exn's MESSAGE is preserved (it is safe
  to surface a generic message; if a future security review wants to redact internal messages,
  that is an additive change at the boundary, not here). **`data` is dropped for non-mcp exns**
  — a generic exn has no structured wire data.
- **What counts as the fallback input (SETTLED).** The encoder's contract is `(-> exn?
  jsonrpc-error?)`. Callers must pass an `exn` (the protocol boundary already catches via
  `(with-handlers ([(λ (_) #t) …]) …)` and, for a raised non-`exn?` value, wraps it in an
  `exn:fail` first). `errors.rkt` does not try to encode arbitrary raised values — that
  wrapping is the boundary's job (S3). Documented so 007/S3 know the contract.
- **TS-flat → Racket-richer hierarchy mapping (SETTLED — record for the parity matrix).**
  `errors.ts` has `ProtocolError` (+ two data-specialized subclasses). The Racket hierarchy
  splits the single TS wire-error class into `exn:fail:mcp:protocol` (the wire/JSON-RPC role)
  and `exn:fail:mcp:auth` (the `core/auth/errors.ts` role, a separate TS module), both under
  `exn:fail:mcp`. The two TS data-subclasses (`UrlElicitationRequiredError` `-32042`,
  `UnsupportedProtocolVersionError` `-32004`) are NOT separate Racket structs — they are
  `exn:fail:mcp:protocol` instances carrying the right `code` + `data`, CONSTRUCTED by item
  007's decode helpers (the `data.elicitations` / `data.supported` getters become decode-side
  accessors). Record this 1-to-richer mapping in the §9 parity row for `errors.rkt` so the
  matrix maps cleanly.
- **Designing for 007's DECODE extension (SETTLED — the seam).** 007 adds `jsonrpc-error->exn`
  + typed decoders into THIS file. 006 guarantees: (a) the hierarchy + constructors are
  sufficient for 007 to build any decoded error (`-32042`/`-32004`/generic) via
  `make-protocol-error` with the right code/message/data — NO new struct needed; (b) a
  commented "DECODE (item 007)" section anchor marks where 007's code goes; (c) the `provide`
  block is appended-to, not edited; (d) the `require` list already pulls in everything 007
  needs (the codes + the `jsonrpc-error` shape). The roadmap's both-directions test (line 86)
  is split: 006's test is encode-only; 007's test adds the decode-direction assertions
  (`-32042` → URL-elicitation exn; `-32004` → unsupported-version exn).
- **`contract-out` vs raw + `…/c` (FOLLOW 003).** Item 003 chose raw transparent structs +
  separately-provided contracts (no `contract-out` on structs). 006 follows: provide
  `(struct-out exn:fail:mcp …)` raw; put the function contract `(-> exn? jsonrpc-error?)` on
  `exn->jsonrpc-error` (via `contract-out` on the function OR a documented raw provide).
  Constructor argument validation (`exact-integer?` code, `string?` message) is enforced via
  `contract-out` on `make-*` OR an internal guard — record the choice; recommend `contract-out`
  on the three `make-*` so a bad code/message is caught at construction.

---

## Completion Reminder

On completion, the implementer MUST:

1. **Update `docs/aide/progress.md` — Stage S1 `errors.rkt` deliverable line.** Advance
   `mcp/core/errors.rkt` 📋 → 🚧 (when starting) and **leave it at 🚧** on delivery — **do NOT
   flip ✅.** This item is the ENCODE half only; the roadmap S1 `errors.rkt` deliverable
   (line 84) explicitly covers **both** directions, and the test deliverable (line 86) demands
   the decode direction too. **Item 007 (DECODE) is the one that flips `errors.rkt` ✅** once
   `jsonrpc-error->exn` + the `-32042`/`-32004` typed decoders + their tests land. If the
   progress row is a single combined errors line, advance it only to 🚧 with a note "encode
   half delivered (item 006); decode half pending (item 007)". Never revert an icon backward.
2. **Touch the parity-matrix row** for `errors.rkt` (under `core/errors/*` / `core/auth/*`)
   per Stage-S1 discipline (roadmap "Parity discipline applies to every stage"): record that
   the exn hierarchy + ENCODE path exist and are tested, and that DECODE (the TS
   `ProtocolError.fromError` half) is pending in item 007 — so the row reflects "encode
   partial" not "full". Record the TS-flat → Racket-richer hierarchy mapping (Decisions) in
   the row's notes so the matrix maps `errors.ts` ↔ `errors.rkt` cleanly.
3. Leave the sibling `core/types/*` deliverables (`constants`, `guards`, `spec-2025-11-25`,
   `spec-2026-07-28`, `types.rkt` façade) at their current status — this item delivers only the
   ENCODE half of `errors.rkt`.
