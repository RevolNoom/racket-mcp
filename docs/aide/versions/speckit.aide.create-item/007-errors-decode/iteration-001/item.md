# Work Item 007: Error DECODE path (JSON-RPC → typed error)

> **Queue:** `docs/aide/queue/queue-001.md` — Item 007
> **Stage:** S1 (Foundation: types, constants, guards, errors — L0 part 1)
> **Module:** M2 (Errors) — `mcp/core/errors.rkt` sub-unit (the exn↔JSON-RPC seam) —
>   **this item builds the DECODE half; it COMPLETES the file (both directions).**
> **Source vision:** `docs/aide/vision.md` §4.8 line 110 (Errors — mirrors
>   `core/errors/sdkErrors`, `core/auth/errors`): "`SdkError` hierarchy with stable error
>   codes, plus `ProtocolError` for wire-level errors → `mcp/core/errors.rkt` using Racket
>   `exn` subtypes (`exn:fail:mcp`, `exn:fail:mcp:protocol`, `exn:fail:mcp:auth`)"; G1
>   line 34 (wire-protocol parity).
> **Source roadmap:** `docs/aide/roadmap.md` Stage S1 → Deliverables line 84
>   (`mcp/core/errors.rkt` — the single exn↔JSON-RPC-error conversion point, "Covers **both
>   directions**: (a) *encode* … (b) *decode* a received JSON-RPC error object → the matching
>   typed error") and the test line 86 (`mcp/core/test/errors-test.rkt` — "exn↔JSON-RPC
>   mapping in **both** directions"). **Item 006 delivered direction (a) ENCODE; THIS item
>   delivers direction (b) DECODE into the same file, satisfying both roadmap lines fully.**
> **Source architecture:** `docs/aide/architecture.md` §4.1 line 328 (the **error-to-wire
>   boundary** — "M2 owns the single conversion point exn↔JSON-RPC error so malformed input
>   never crashes the engine"). DECODE is the inbound leg of that single point.
> **Reference impl (authoritative):** MCP TypeScript SDK v2 at `typescript-sdk/` —
>   `packages/core/src/types/errors.ts` lines 21–39 (`ProtocolError.fromError` — the
>   code→typed-error factory), lines 46–56 (`UrlElicitationRequiredError`, `-32042`), lines
>   67–85 (`UnsupportedProtocolVersionError`, `-32004`), and `packages/core/src/types/enums.ts`
>   lines 5–25 (`ProtocolErrorCode`). **This item is the DECODE half mirroring
>   `ProtocolError.fromError`.**
> **Delivered siblings (the FORMAT + rigor bar):** `docs/aide/items/006-error-hierarchy-and-encode-path.md`
>   (✅ delivered, the ENCODE counterpart — match its format, honor its seam decisions) and
>   `docs/aide/items/003-spec-types-2025-11-25.md` (✅).
> **Status:** Specified (not yet implemented) — DECODE half. With this item, `errors.rkt`
>   covers BOTH directions and the roadmap S1 `errors.rkt` deliverable flips 🚧 → ✅.

---

## Description

Extend `mcp/core/errors.rkt` (delivered by item 006 — the ENCODE half) with the **DECODE**
direction of the single exn↔JSON-RPC-error conversion point: given a received JSON-RPC error
object, produce the **matching typed Racket error** so a *generic* failure is never produced
where a *specific* one is defined (architecture §4.1 inbound leg). This mirrors the TypeScript
SDK's `ProtocolError.fromError` factory (`typescript-sdk/packages/core/src/types/errors.ts`
lines 21–39).

One deliverable, appended into the existing file at the **"DECODE (item 007)" anchor**
(`errors.rkt:173–186`):

1. **The DECODE function** `jsonrpc-error->exn` — the one-way map `JSON-RPC error object →
   typed `exn:fail:mcp:protocol``. It dispatches on the received `(jsonrpc-error-code e)`:
   - **`-32042` (`URL-ELICITATION-REQUIRED`)** with well-shaped data → a
     URL-elicitation-required-typed error: `(make-protocol-error URL-ELICITATION-REQUIRED
     message data)` carrying `data.elicitations`. Mirrors `errors.ts:23–28`
     (`new UrlElicitationRequiredError(...)`).
   - **`-32004` (`UNSUPPORTED-PROTOCOL-VERSION`)** with well-shaped data → an
     unsupported-protocol-version-typed error: `(make-protocol-error UNSUPPORTED-PROTOCOL-VERSION
     message data)` carrying `data.supported` + `data.requested`. Mirrors `errors.ts:30–35`
     (`new UnsupportedProtocolVersionError(...)`).
   - **any other code** (and the two specials when their data is absent/malformed) → a
     **generic** typed error `(make-protocol-error code message data)` carrying the received
     code/message/data verbatim. Mirrors `errors.ts:38` (the `return new ProtocolError(code,
     message, data)` default). This is the "generic failure is not produced where a specific
     one is defined, BUT a specific failure is not faked where the data does not support it"
     contract — see §The build contract.

   No new `struct` is added: item 006 designed the hierarchy + constructors so 007 builds every
   decoded error with `make-protocol-error` and the right code/message/data (errors.rkt:177–185
   spells this out). The new bindings are **APPENDED** to the second `provide` block
   (`errors.rkt:81–96`); 006's exports are not edited (the additive-provide rule, item 006
   Decisions "Designing for 007's DECODE extension").

This **COMPLETES** the single conversion point: ENCODE (`exn->jsonrpc-error`, item 006) +
DECODE (`jsonrpc-error->exn`, this item) are now symmetric, both consuming/producing the ONE
`jsonrpc-error` struct from item 003 (`spec-2025-11-25.rkt:325`). The strong round-trip
invariant `(jsonrpc-error->exn (exn->jsonrpc-error e))` preserves code (and message/data where
defined) becomes assertable — see Acceptance criteria.

### Representation conventions (the decode input/output shapes — non-negotiable for parity)

- **Input shape.** The canonical input is a **`jsonrpc-error` struct**
  (`spec-2025-11-25.rkt:325`, `(struct jsonrpc-error (code message data) #:transparent)`), the
  exact value `exn->jsonrpc-error` returns and the value
  `json->jsonrpc-error` (`spec-2025-11-25.rkt:328`) parses a wire hasheq into. The decode
  function's contract is `(-> jsonrpc-error? exn:fail:mcp:protocol?)`. **Rationale (matches the
  engine call site):** the protocol layer (S3) parses an inbound wire error response with
  `json->jsonrpc-error-response` (`spec-2025-11-25.rkt:338`) — which already yields a
  `jsonrpc-error` struct via `json->jsonrpc-error` — then hands THAT struct to the decoder. So
  the decoder consumes the struct symmetrically with how ENCODE produces it; it does NOT
  re-parse a raw wire hasheq (that is `json->jsonrpc-error`'s job, in M1). See §Decisions
  "decode input type".
- **`data` carriage.** `data` is the SAME `absent` sentinel / jsexpr value as item 003/006
  (`mcp-data/c = (or/c absent? jsexpr-value?)`, errors.rkt:123). A decoded error carries the
  received `data` field VERBATIM into the typed error's `data` (so a round-trip preserves it);
  `absent` stays `absent`. A present falsy payload (`#f`, `'null`, `0`, `""`, empty hasheq)
  survives. The data-shape *check* that gates specialization (does `-32042` data look like an
  elicitations payload?) NEVER mutates or coerces the carried `data`.
- **Output shape.** The output is an `exn:fail:mcp:protocol` (a raisable Racket exception),
  NOT a façade `jsonrpc-error-response` wire message and NOT a raw hasheq. The two TS
  data-subclasses (`UrlElicitationRequiredError`, `UnsupportedProtocolVersionError`) are NOT
  separate Racket structs — they are `exn:fail:mcp:protocol` instances carrying the right
  code + data (item 006 Decisions "TS-flat → Racket-richer hierarchy mapping"; errors.rkt:178–183).
- **Message carriage.** The decoded error's message is the received `(jsonrpc-error-message e)`
  verbatim. (TS's specialized subclasses default a synthesized message when none is given —
  errors.ts:47, 68 — but `fromError` always passes the received `message` through, so the
  decode never synthesizes a message; it uses what arrived.)

---

## The build contract — the code→typed-error decode mapping (enumerate ALL)

`jsonrpc-error->exn : jsonrpc-error? → exn:fail:mcp:protocol?`. A single `cond` on
`(jsonrpc-error-code e)` (binding `code`, `message`, `data` once at the top), mirroring
`ProtocolError.fromError` (errors.ts:21–39).

### Part A — the decode mapping table

| Received `code` | Data gate (mirrors errors.ts) | Result | `data` carried | Mirrors |
|---|---|---|---|---|
| `URL-ELICITATION-REQUIRED` (`-32042`) | `data` present AND looks like an elicitations payload (a `json-object?` with an `'elicitations` key) | `(make-protocol-error URL-ELICITATION-REQUIRED message data)` — the **URL-elicitation-required**-typed error | received `data` verbatim | errors.ts:23–28 |
| `UNSUPPORTED-PROTOCOL-VERSION` (`-32004`) | `data` present AND a `json-object?` with `'supported` a list AND `'requested` a string | `(make-protocol-error UNSUPPORTED-PROTOCOL-VERSION message data)` — the **unsupported-protocol-version**-typed error | received `data` verbatim | errors.ts:30–35 |
| `-32042` / `-32004` **with absent or malformed data** | gate FAILS | **generic** `(make-protocol-error code message data)` (still the right code, just not the "specialized" branch) | received `data` verbatim | errors.ts:38 default |
| **any other code** (`-32603`, `-32602`, `-32002`, `-32003`, any unknown integer) | n/a | **generic** `(make-protocol-error code message data)` carrying the received code | received `data` verbatim | errors.ts:38 default |

> **The data-gate (mirrors errors.ts EXACTLY — load-bearing).** `ProtocolError.fromError` does
> NOT specialize on code alone — it ALSO checks the data shape (`if (code === … && data)` then a
> nested shape check, errors.ts:23–35). So `-32042` with **no** data, or with data lacking
> `elicitations`, falls through to the generic `ProtocolError` (errors.ts:38). The Racket decode
> mirrors this: a code-only match is NOT sufficient for the specialized branch; the data must be
> present and well-shaped. This avoids constructing a "specialized" error whose accessors
> (`data.elicitations` / `data.supported`) would be undefined. **Consequence for the typed
> error:** because all three TS classes are the SAME Racket struct (`exn:fail:mcp:protocol`)
> distinguished only by `code` + `data` shape, the Racket specialized-vs-generic distinction is
> observable only via `(mcp-error-code e)` and `(mcp-error-data e)`, not via a distinct
> predicate. The decode therefore carries the right code in EVERY branch (`-32042` always
> decodes to a `-32042` typed error, specialized or generic); the gate only governs whether the
> SDK considered the data "well-shaped enough to specialize". The test asserts: `-32042` →
> `(protocol-error? r)` ∧ `(= (mcp-error-code r) URL-ELICITATION-REQUIRED)` ∧ data preserved;
> and that `-32042` with no/garbage data still decodes to a `-32042` protocol error (the generic
> fall-through for a special code), never throwing.

> **Stable-code reuse (HARD requirement — anti-magic).** The codes the decoder switches on are
> imported from `constants.rkt` — `URL-ELICITATION-REQUIRED` (-32042) and
> `UNSUPPORTED-PROTOCOL-VERSION` (-32004) are already in errors.rkt's require list
> (errors.rkt:49–50); item 007 adds NO new constant import (item 006 left the require complete
> — Decisions "Designing for 007"). The decode `cond` matches with `(= code URL-ELICITATION-REQUIRED)`
> / `(= code UNSUPPORTED-PROTOCOL-VERSION)`, NEVER a literal `-32042`/`-32004`. The test asserts
> the decoded code `=` the named constant, not a literal.

### Part B — the generic fall-through rule (the queue's "not generic where specific is defined" + its dual)

The queue clause: "so a generic failure is not produced where a specific one is defined." The
decoder satisfies this AND its necessary dual:

1. **A specific code yields its typed error** — `-32042`/`-32004` (with valid data) produce the
   URL-elicitation / unsupported-version typed errors, NOT a bare generic `exn:fail:mcp`.
2. **An UNKNOWN code yields a generic *typed* error, NOT a wrong specific type** — any code not
   in the special set (e.g. `-32602`, a future `-39999`) decodes to `(make-protocol-error code
   message data)` carrying *that* code. It is "generic" only in that no specialized data-shape
   handling applies; it is still a *typed* `exn:fail:mcp:protocol`, never an
   `exn:fail:mcp:auth` and never a raw `exn:fail`. (Mirrors `errors.ts:38` returning a plain
   `ProtocolError`.)
3. **A special code with bad data does NOT fake a specialization** — `-32042` without an
   `elicitations` payload decodes to a `-32042` protocol error via the generic constructor
   path, not a "specialized" one with missing accessors (mirrors the `&& data` guard).

### Part C — `provide` surface extension (additive)

Append to the second `provide` block (`errors.rkt:81–96`, the `contract-out` block):

- `[jsonrpc-error->exn (-> jsonrpc-error? exn:fail:mcp:protocol?)]` — the canonical decoder.
- (Optional convenience, decide in implementation) `[jsonrpc-error-jsexpr->exn (-> hash?
  exn:fail:mcp:protocol?)]` — a wire-hasheq → exn wrapper `(= (jsonrpc-error->exn
  (json->jsonrpc-error h)))` for callers holding a raw wire error object. If added, it requires
  importing `json->jsonrpc-error` from `spec-2025-11-25.rkt` (an additive `only-in` entry). See
  §Decisions "decode input type" — RECOMMEND the struct-only canonical form + this thin wrapper
  ONLY if a concrete caller needs it; otherwise omit (YAGNI) and let S3 call
  `json->jsonrpc-error` itself.

> **Additive-provide discipline (item 006 seam).** Do NOT touch item 006's first `provide`
> block (`errors.rkt:68–79`, the struct-outs/predicates/accessors) or the existing entries in
> the second block. ADD the decode entry/entries to the second `contract-out` block. The
> `require` list is unchanged unless the optional wire wrapper is added (then one `only-in`
> entry for `json->jsonrpc-error`).

---

## Acceptance criteria

- [ ] **The DECODE function exists** in `mcp/core/errors.rkt`, defined at the "DECODE (item
      007)" anchor (`errors.rkt:173`+), provided via the second `contract-out` block with
      contract `(-> jsonrpc-error? exn:fail:mcp:protocol?)`. Item 006's exports and `require`
      list are otherwise untouched (additive-only).
- [ ] **THE QUEUE'S CORE TESTABLE CLAIM #1 — `-32042` → `UrlElicitationRequired`:**
      `(jsonrpc-error->exn (jsonrpc-error URL-ELICITATION-REQUIRED "url required" (hasheq
      'elicitations '())))` → a value `r` with `(protocol-error? r)` `#t`, `(mcp-error-code r)`
      `=` `URL-ELICITATION-REQUIRED` (`-32042`), and `(mcp-error-data r)` `=` the received
      elicitations payload (preserved verbatim). Mirrors `errors.ts:23–28`.
- [ ] **THE QUEUE'S CORE TESTABLE CLAIM #2 — `-32004` → unsupported-version:**
      `(jsonrpc-error->exn (jsonrpc-error UNSUPPORTED-PROTOCOL-VERSION "bad ver" (hasheq
      'supported '("2025-11-25" "2025-06-18") 'requested "1999-01-01")))` → `r` with
      `(protocol-error? r)` `#t`, `(mcp-error-code r)` `=` `UNSUPPORTED-PROTOCOL-VERSION`
      (`-32004`), and `(mcp-error-data r)` carrying the `supported`/`requested` payload. Mirrors
      `errors.ts:30–35`.
- [ ] **THE QUEUE'S CORE TESTABLE CLAIM #3 — unknown code → generic typed error:**
      `(jsonrpc-error->exn (jsonrpc-error INVALID-PARAMS "bad" absent))` → `r` with
      `(protocol-error? r)` `#t`, `(mcp-error-code r)` `=` `INVALID-PARAMS` (the received code,
      NOT a defaulted/wrong code), `(auth-error? r)` `#f`. A code with NO specific handler
      decodes to a generic `exn:fail:mcp:protocol` carrying that exact code. Mirrors
      `errors.ts:38`.
- [ ] **The data-gate fall-through is correct:** `(jsonrpc-error->exn (jsonrpc-error
      URL-ELICITATION-REQUIRED "x" absent))` (a `-32042` with NO data) decodes WITHOUT throwing
      to a `-32042` protocol error (`(= (mcp-error-code r) URL-ELICITATION-REQUIRED)`); likewise
      `-32004` with malformed data (e.g. `'supported` not a list) decodes to a `-32004`
      protocol error. A special code never faking a specialization on bad data, and never
      crashing.
- [ ] **ROUND-TRIP INVARIANT (the symmetry test):** for representative errors `e`
      (`make-protocol-error` with `INVALID-PARAMS`, with `URL-ELICITATION-REQUIRED`+elicitations
      data, with `UNSUPPORTED-PROTOCOL-VERSION`+supported/requested data, and a `make-mcp-error`
      base with `RESOURCE-NOT-FOUND`+data), `(jsonrpc-error->exn (exn->jsonrpc-error e))` yields
      `r` with `(= (mcp-error-code r) (mcp-error-code e))`, `(equal? (exn-message r) (exn-message
      e))`, and `(equal? (mcp-error-data r) (mcp-error-data e))`. (Note the type does not
      round-trip for a base/auth `e` — ENCODE erases the subtype to a `jsonrpc-error`, so DECODE
      always yields a `protocol`-typed error; CODE/message/data are the preserved invariants.
      See §Decisions "what round-trips".)
- [ ] **Decode preserves data verbatim (no coercion):** a present falsy/odd `data` (`#f`,
      `'null`, `0`, `""`, empty `hasheq`, a nested object/array) is carried into the typed error
      unchanged (`equal?`, and the nested case `eq?` — copied by reference). `absent` data
      stays `absent` (`(absent? (mcp-error-data r))`).
- [ ] **Codes are imported, not re-literaled.** A `grep` for `-32042`/`-32004` (and any other
      code literal) in errors.rkt's DECODE section finds NONE in code (only comments); the
      decode `cond` uses `URL-ELICITATION-REQUIRED` / `UNSUPPORTED-PROTOCOL-VERSION`. The test
      asserts decoded codes `=` the named constants.
- [ ] **The decoded error is a raisable, catchable exn:** `(with-handlers ([protocol-error?
      (λ (_) #t)]) (raise (jsonrpc-error->exn (jsonrpc-error URL-ELICITATION-REQUIRED "x"
      (hasheq 'elicitations '())))))` → `#t`; the decoded value satisfies `exn:fail?` and
      `mcp-error?`.
- [ ] **`raco test` passes** (exit 0) over `mcp/core/test/errors-test.rkt` — per the
      `raco`-broken workaround, run via `racket mcp/core/test/errors-test.rkt` and SCAN for
      `FAILURE`/`ERROR` lines. The existing item-006 encode checks still pass (the decode
      section is ADDED, the encode section is NOT rewritten).
- [ ] **Portability (NFR — roadmap line 96) unchanged:** errors.rkt still requires ONLY
      `racket/contract` + `types/constants.rkt` + `types/spec-2025-11-25.rkt` (plus, IF the
      optional wire wrapper is added, the `json->jsonrpc-error` binding from the SAME spec
      module — no new module). No subprocess/socket, no I/O at module load.
- [ ] **Parity-matrix discipline:** progress.md Stage S1 `errors.rkt` deliverable flips
      🚧 → ✅ (BOTH directions now delivered); the §9 / parity row for `errors.rkt` records that
      ENCODE + DECODE both exist and are tested, mirroring `ProtocolError.fromError`. Sibling
      rows (`constants`, `guards`, `spec-*`, `types.rkt`) untouched.

---

## Implementation steps

1. **Confirm inputs are green.** `racket mcp/core/errors.rkt` (item 006 — must load); `racket
   mcp/core/test/errors-test.rkt` (item 006 encode tests must pass) — establish the baseline
   BEFORE editing so a later failure is attributable to the decode change. Confirm
   `mcp/core/types/constants.rkt` and `mcp/core/types/spec-2025-11-25.rkt` load.
2. **Re-read the reference** `typescript-sdk/packages/core/src/types/errors.ts` lines 21–39
   (`ProtocolError.fromError`): note (a) the dispatch is on `code` AND a data-shape guard, (b)
   the default returns a plain `ProtocolError(code, message, data)`, (c) the specialized
   classes pass the received `message` through. This is the exact shape to mirror.
3. **Decide the decode-input type** (§Decisions): canonical input is the `jsonrpc-error` struct
   (`(-> jsonrpc-error? exn:fail:mcp:protocol?)`). Decide whether to add the optional
   `jsonrpc-error-jsexpr->exn` wire wrapper (recommend: omit unless a caller needs it — YAGNI).
4. **Write the decoder** at the "DECODE (item 007)" anchor (errors.rkt:173+). A single `cond`:
   - bind `(define code (jsonrpc-error-code e))`, `(define message (jsonrpc-error-message e))`,
     `(define data (jsonrpc-error-data e))` once.
   - `[(and (= code URL-ELICITATION-REQUIRED) (url-elicitation-data? data))
     (make-protocol-error URL-ELICITATION-REQUIRED message data)]`
   - `[(and (= code UNSUPPORTED-PROTOCOL-VERSION) (unsupported-version-data? data))
     (make-protocol-error UNSUPPORTED-PROTOCOL-VERSION message data)]`
   - `[else (make-protocol-error code message data)]`
   where the two small data-gate helpers mirror errors.ts:24–25 / 32 (`url-elicitation-data?`:
   a `json-object?` with an `'elicitations` key; `unsupported-version-data?`: a `json-object?`
   with `'supported` a `list?` and `'requested` a `string?`). Reuse `json-object?` — import it
   `only-in` from `spec-2025-11-25.rkt` IF not already imported (check the require list; if
   absent, add it as an additive `only-in` entry, OR use a local `hash?`/`hash-eq?` check — see
   §Decisions "json-object? import"). Since the specialized and generic branches BOTH call
   `make-protocol-error` with the same code, the gate's only observable effect today is that a
   malformed `-32042`/`-32004` still produces the right code — keep the gate anyway for
   errors.ts parity and forward-compat (so a future specialized-accessor layer can rely on it).
5. **Append the `provide`** entry/entries to the second `contract-out` block (errors.rkt:81–96).
   Do not edit existing entries.
6. **Extend the test** `mcp/core/test/errors-test.rkt` (do NOT rewrite — ADD a "Part 6 —
   DECODE" section after the existing Part 5, before the final `displayln`). See Testing
   strategy. Add the needed imports (`jsonrpc-error` constructor — already imported as a
   selector set; ADD the `jsonrpc-error` constructor + `jsonrpc-error-message` if not present)
   to the test's `only-in` lists.
7. **Run** `racket mcp/core/test/errors-test.rkt` from repo root (workaround); scan for
   `FAILURE`/`ERROR`. Likely failures: matching code with `eq?`/`equal?` vs `=` (use `=` for
   numbers); the data-gate too strict (rejecting a valid present payload) or too loose
   (specializing on `absent`); forgetting the generic else returns the *received* code not a
   default; a contract violation if a non-`jsonrpc-error?` is passed.
8. **Update progress.md + parity matrix** (Completion Reminder) — flip `errors.rkt` 🚧 → ✅
   (both directions now delivered).

---

## Testing strategy

**Test file:** `mcp/core/test/errors-test.rkt` (EXTEND — add a Part 6, keep Parts 1–5). The
file's conventions (item 006): `#lang racket/base`; rackunit `check-*` at module top level so
`racket <file>` runs the suite; a final `(displayln "errors-test.rkt: all checks executed")`;
imports via `(file "../errors.rkt")` and `(only-in (file "../types/...") ...)`. **Add to the
imports:** the `jsonrpc-error` STRUCT CONSTRUCTOR + `jsonrpc-error-message` from
`spec-2025-11-25.rkt` (the existing `only-in` already pulls `jsonrpc-error?`,
`jsonrpc-error-code`, `jsonrpc-error-data`, `jsonrpc-error->json`, `absent`, `absent?` —
errors-test.rkt:18–20; add `jsonrpc-error` and `jsonrpc-error-message`). The decode functions
themselves come from `(file "../errors.rkt")` (already required, errors-test.rkt:12).

### Part 6 — DECODE (the new section)

**6a — the special-code → typed-error decodes (the queue's core claims):**
- `-32042` → URL-elicitation: `(define du (jsonrpc-error->exn (jsonrpc-error
  URL-ELICITATION-REQUIRED "url required" (hasheq 'elicitations '()))))`; assert
  `(protocol-error? du)`, `(= (mcp-error-code du) URL-ELICITATION-REQUIRED)`,
  `(equal? (mcp-error-data du) (hasheq 'elicitations '()))`, `(equal? (exn-message du) "url
  required")`.
- `-32004` → unsupported-version: `(define dv (jsonrpc-error->exn (jsonrpc-error
  UNSUPPORTED-PROTOCOL-VERSION "bad ver" (hasheq 'supported '("2025-11-25" "2025-06-18")
  'requested "1999-01-01"))))`; assert `(protocol-error? dv)`, `(= (mcp-error-code dv)
  UNSUPPORTED-PROTOCOL-VERSION)`, data carries `supported`+`requested`.

**6b — unknown / generic code → generic typed error:**
- `(define dg (jsonrpc-error->exn (jsonrpc-error INVALID-PARAMS "bad params" absent)))`; assert
  `(protocol-error? dg)`, `(= (mcp-error-code dg) INVALID-PARAMS)`, `(absent? (mcp-error-data
  dg))`, `(false? (auth-error? dg))`.
- a genuinely-unknown code (not in constants): `(define dx (jsonrpc-error->exn (jsonrpc-error
  -39999 "weird" absent)))`; assert `(= (mcp-error-code dx) -39999)` (the received code is
  preserved, NOT defaulted) and `(protocol-error? dx)`.

**6c — special code with absent/malformed data falls through to its generic typed error
(no throw, right code):**
- `-32042` with NO data: `(define dun (jsonrpc-error->exn (jsonrpc-error
  URL-ELICITATION-REQUIRED "x" absent)))`; assert `(= (mcp-error-code dun)
  URL-ELICITATION-REQUIRED)` and `(protocol-error? dun)` (it did not throw, it carries the right
  code).
- `-32004` with malformed data (`'supported` not a list): `(jsonrpc-error->exn (jsonrpc-error
  UNSUPPORTED-PROTOCOL-VERSION "x" (hasheq 'supported "nope" 'requested "v")))` → still a
  `-32004` protocol error (`(= (mcp-error-code …) UNSUPPORTED-PROTOCOL-VERSION)`), no throw.

**6d — the ROUND-TRIP invariant (encode∘decode symmetry):**
- For each `e` in a small list — `(make-protocol-error INVALID-PARAMS "bad")`,
  `(make-protocol-error URL-ELICITATION-REQUIRED "u" (hasheq 'elicitations '()))`,
  `(make-protocol-error UNSUPPORTED-PROTOCOL-VERSION "v" (hasheq 'supported '("a") 'requested
  "b"))`, `(make-mcp-error RESOURCE-NOT-FOUND "nf" (hasheq 'uri "u"))` — compute `(define r
  (jsonrpc-error->exn (exn->jsonrpc-error e)))` and assert `(= (mcp-error-code r) (mcp-error-code
  e))`, `(equal? (exn-message r) (exn-message e))`, `(equal? (mcp-error-data r) (mcp-error-data
  e))`. (Document in a test comment: the SUBTYPE does not round-trip — DECODE always yields a
  `protocol`-typed error because ENCODE erases the subtype to a code-bearing `jsonrpc-error`;
  code/message/data are the invariants. This is the correct, intended asymmetry.)
- The reverse direction `(exn->jsonrpc-error (jsonrpc-error->exn j))` `equal?`-reproduces the
  input `jsonrpc-error` `j` for a `j` built with each special + a generic code (a `jsonrpc-error
  → exn → jsonrpc-error` round-trip preserving code/message/data exactly).

**6e — decoded error is a raisable, catchable exn (interop):**
- `(check-true (with-handlers ([protocol-error? (λ (_) #t)]) (raise (jsonrpc-error->exn
  (jsonrpc-error URL-ELICITATION-REQUIRED "x" (hasheq 'elicitations '()))))))`.
- `(check-true (exn:fail? du))` and `(check-true (mcp-error? du))` (the decoded value is a real
  exn, catchable generically).

**6f — data-carriage / no-coercion matrix (decode side):**
- falsy/odd data survives: for `data` in `(list #f 'null 0 "" (hasheq))`, decode a generic-code
  error carrying it and assert `(equal? (mcp-error-data r) data)`.
- nested data copied by reference: `(define nested (hasheq 'a (list 1 2)))`;
  `(check-eq? (mcp-error-data (jsonrpc-error->exn (jsonrpc-error INTERNAL-ERROR "x" nested)))
  nested)`.

### Edge cases the test must cover (do not leave implicit)

- **`-32042`/`-32004` with WELL-shaped data → specialized branch; with absent/malformed →
  generic branch — BOTH carry the correct code** (6a + 6c). This is the data-gate's whole point.
- **Unknown code preserves the received code exactly** (no defaulting to `-32603` or `-32602`) —
  6b's `-39999` case.
- **Contract rejects a non-`jsonrpc-error?` input:** `(check-exn exn:fail:contract? (λ ()
  (jsonrpc-error->exn (hasheq 'code -32602 'message "x"))))` — a raw hasheq is NOT a
  `jsonrpc-error?` and the `(-> jsonrpc-error? …)` contract rejects it (proving the canonical
  input is the struct, not the wire hash; the wire hash path, if provided, is the separate
  optional wrapper).
- **Empty/odd message:** a `jsonrpc-error` with `message = ""` decodes to an exn with
  `(exn-message …)` `=` `""`.
- **Code preserved exactly (no coercion):** a negative non-special code round-trips identically.

### The `racket <file>` gate

Run `racket mcp/core/test/errors-test.rkt` from the repo root. Silence + the final
`"errors-test.rkt: all checks executed"` line ≈ pass; SCAN stdout/stderr for `FAILURE` /
`ERROR` / `check-` failure blocks (the file exits 0 even on a failed check, so the exit code
alone is NOT trustworthy — especially on the first recompile run).

---

## Dependencies

- **Upstream work items:**
  - **Item 006** (`mcp/core/errors.rkt`, ✅ — the ENCODE half) — THIS item extends it: reuses
    `make-protocol-error` (errors.rkt:137), the predicates `protocol-error?`/`mcp-error?`
    (errors.rkt:114–116), the accessors `mcp-error-code`/`mcp-error-data` (errors.rkt:117–118),
    `exn->jsonrpc-error` (for the round-trip test), the `mcp-data/c` shape, and the second
    `provide` block (errors.rkt:81–96, appended to). MUST be green before starting.
  - **Item 001** (`mcp/core/types/constants.rkt`, ✅) — `URL-ELICITATION-REQUIRED` (-32042),
    `UNSUPPORTED-PROTOCOL-VERSION` (-32004), plus the codes the tests use (`INVALID-PARAMS`,
    `RESOURCE-NOT-FOUND`, `INTERNAL-ERROR`). Already in errors.rkt's require list
    (errors.rkt:42–50) — item 007 adds NO new constant import.
  - **Item 003** (`mcp/core/types/spec-2025-11-25.rkt`, ✅) — the `jsonrpc-error` struct
    (`{code message data}`, line 325), its accessors `jsonrpc-error-code/-message/-data`, the
    `absent` sentinel (55), and `json-object?` (51) for the data-gate. errors.rkt already
    imports `jsonrpc-error`/`jsonrpc-error?`/`absent`/`absent?` (errors.rkt:57–62); item 007
    MAY add `only-in` entries for `jsonrpc-error-code/-message/-data` and `json-object?` IF the
    decoder/gate needs them and they are not already pulled (check the require list during
    implementation — see §Decisions).
  - **Item 005** (`mcp/core/types/types.rkt` façade, the public superset) — RELATED but **NOT a
    dependency**, and the source of the key reconciliation decision (see §Decisions
    "reconciliation with the façade typed errors"). The façade re-exports
    `make-facade-url-elicitation-required-error` / `facade-url-elicitation-required-error?`
    (types.rkt:1176–1178) and `make-facade-unsupported-protocol-version-error` /
    `facade-unsupported-protocol-version-error?` (types.rkt:1244–1246), which delegate to
    `spec-2025-11-25.rkt:1851` / `spec-2026-07-28.rkt:1806`. Those constructors build
    **`jsonrpc-error-response` WIRE MESSAGES** (id + error), NOT raisable exns — a DIFFERENT
    role. errors.rkt's decode produces `exn:fail:mcp:protocol` (exns). The two do not collide;
    see §Decisions.
- **Forward / downstream consumers (informational):** the protocol engine (S3) decodes an
  inbound JSON-RPC error response — `json->jsonrpc-error-response` → its `jsonrpc-error` field →
  `jsonrpc-error->exn` → a typed exn it can `raise` to the awaiting request caller, so a remote
  `-32042`/`-32004` surfaces as the specific typed error rather than a generic one
  (architecture §4.1 inbound leg). The client (S5+) catches `protocol-error?` and inspects
  `(mcp-error-code …)` / `(mcp-error-data …)`.
- **Operates on:** in-memory `jsonrpc-error` struct → an `exn:fail:mcp:protocol`. No file/network
  I/O.
- **Tooling/runtime:** Racket ≥ 8.x (v9.1 installed; `raco` BROKEN — see Testing
  Prerequisites); `rackunit`; the `typescript-sdk/` checkout (read for parity, not imported).

---

## Project-specific adaptations (Racket / exn structs / contracts / rackunit)

This template's "Required Services / database / API endpoint" framing does not apply: **this is
a pure-data extension — one dispatch function + two tiny data-shape predicates, no external
services, no I/O at module load.** Adaptations:

- **Language:** `#lang racket/base` + `racket/contract` (the file is already this). The decode
  is a pure function; the TS `static fromError(...)` factory maps to a top-level
  `(define (jsonrpc-error->exn e) (cond …))`. The TS `throw` is the consumer's
  `(raise (jsonrpc-error->exn …))`, not the decode's job (decode RETURNS the exn; S3 raises it).
- **Structs not classes (G4):** the three TS classes (`ProtocolError`,
  `UrlElicitationRequiredError`, `UnsupportedProtocolVersionError`) collapse to ONE Racket
  struct (`exn:fail:mcp:protocol`) distinguished by `code` + `data`. TS's class-specific getters
  (`get elicitations`, errors.ts:53; `get supported`/`get requested`, errors.ts:75/83) are NOT
  Racket struct fields — a consumer reads `(hash-ref (mcp-error-data r) 'elicitations)` /
  `'supported` / `'requested` directly. (A future helper layer COULD add named accessors; not
  this item — YAGNI, and item 006 deferred it.)
- **The data-gate mirrors errors.ts's `&& data` + shape checks** via two small predicates over
  `json-object?` — flat, no Zod, no schema engine. This is the Racket idiom for the TS
  `Array.isArray(...)` / `typeof ... === 'string'` runtime checks (errors.ts:32).
- **Flat contracts:** `(-> jsonrpc-error? exn:fail:mcp:protocol?)` on the decoder (matching item
  006's `(-> exn? jsonrpc-error?)` on the encoder — the symmetric inverse). Match item 006's
  `contract-out` placement (the function in the second block).
- **Naming:** `jsonrpc-error->exn` (mirrors item 006's `exn->jsonrpc-error`, reversed — the
  `->` direction names the conversion). Data-gate helpers are private (`url-elicitation-data?` /
  `unsupported-version-data?`, NOT provided).
- **No services / no I/O / no fixtures:** the test constructs `jsonrpc-error` structs in memory
  and asserts; NO `fixtures/` dir (same as item 006).

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None.** No I/O at module load, no service contacted. External artifacts:

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime (v9.1 installed) | compile + run module/tests (`rackunit`) | system install (`racket --version` ≥ 8.0) | n/a |
| Item 006 `mcp/core/errors.rkt` (ENCODE half) | the file being EXTENDED; reuses its constructors/predicates | produced by item 006 | n/a |
| Item 001 `types/constants.rkt` | the `-32042`/`-32004` (+ others) codes | produced by item 001 | n/a |
| Item 003 `types/spec-2025-11-25.rkt` | the `jsonrpc-error` struct + `json-object?` + `absent` | produced by item 003 | n/a |
| `typescript-sdk/` checkout | implementer reads `errors.ts:21–39` for parity | already present at repo root | n/a |

No databases, queues, HTTP servers, or network dependencies. No JSON fixtures (the test is
in-memory). (Harmless `/home/rev/.bash_env: Permission denied` on stderr — ignore.)

### Environment Configuration

- **Environment variables / secrets / config files:** none.
- **Ports:** none must be free.
- **Working directory:** run tests from the **repo root**
  (`/home/rev/Linux/Projects/racket_mcp`) so the `mcp/...` collection + relative requires
  resolve.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0.
  - `racket mcp/core/errors.rkt` → loads (item 006 green).
  - `racket mcp/core/test/errors-test.rkt` → exit 0, no FAILURE (item 006 baseline green BEFORE
    the edit).
  - `test -f mcp/core/types/spec-2025-11-25.rkt` → item 003 present.

### Manual Validation Checklist

- [ ] **Build/compile:** `racket -e '(require (file "mcp/core/errors.rkt"))'` succeeds (no
      error). (`raco make` is BROKEN — see below.)
- [ ] **ENVIRONMENT QUIRK — `raco` IS BROKEN in this sandbox.** The `raco` snap wrapper
      (`/snap/bin/raco`) silently exits 1 here: `raco test …` / `raco make …` do NOT report
      results. **Run the suite with sandboxed `racket <test-file.rkt>` DIRECTLY** — rackunit
      `check-*` forms run at module top level, so loading the file executes the suite. **Silence
      + the final `"errors-test.rkt: all checks executed"` line ≈ pass; a failed check prints a
      `FAILURE` block and the file STILL exits 0, so SCAN the output for `FAILURE`/`ERROR`/`check-`
      lines — do NOT rely on the exit code, ESPECIALLY on the first recompile run.** **Do NOT
      disable the `racket` sandbox** — that breaks `racket` itself in this environment. Canonical
      run: `racket mcp/core/test/errors-test.rkt` from the repo root.
- [ ] **Module loads in isolation:** `racket -e '(require (file "mcp/core/errors.rkt"))'`
      succeeds.
- [ ] **Tests pass:** `racket mcp/core/test/errors-test.rkt` → no `FAILURE`/`ERROR` lines,
      prints "errors-test.rkt: all checks executed". (Both the item-006 encode section AND the
      new decode Part 6 run.)
- [ ] **Decode `-32042` verified (REPL):** `(require (file "mcp/core/errors.rkt") (only-in
      (file "mcp/core/types/spec-2025-11-25.rkt") jsonrpc-error))` then
      `(mcp-error-code (jsonrpc-error->exn (jsonrpc-error -32042 "x" (hasheq 'elicitations
      '()))))` → `-32042`, and `(protocol-error? (jsonrpc-error->exn …))` → `#t`.
- [ ] **Decode unknown code verified (REPL):** `(mcp-error-code (jsonrpc-error->exn
      (jsonrpc-error -39999 "x" (string->uninterned-symbol "absent"))))` → `-39999` (generic
      fall-through, received code preserved). (Use the actual imported `absent` in the test;
      in a quick REPL any present jsexpr or `absent` works.)
- [ ] **Round-trip verified (REPL):** `(mcp-error-code (jsonrpc-error->exn (exn->jsonrpc-error
      (make-protocol-error -32602 "bad"))))` → `-32602`.
- [ ] **Contract rejects raw hash (REPL):** `(jsonrpc-error->exn (hasheq 'code -32602 'message
      "x"))` raises an `exn:fail:contract?` (the canonical input is the struct).
- [ ] **Codes-imported verified:** `grep -nE '\-32042|\-32004' mcp/core/errors.rkt | grep -v
      ';;'` finds the codes ONLY via the constant names in code (no bare numeric literals in the
      decode logic).
- [ ] **Additive-only verified:** `git diff mcp/core/errors.rkt` shows changes ONLY in the
      DECODE-anchor region + the second `provide` block (and possibly one `only-in` require
      line); item 006's first `provide` block and the encode logic are untouched.
- [ ] **Portability verified:** errors.rkt's `require` list is still `racket/contract` +
      `types/constants.rkt` + `types/spec-2025-11-25.rkt` (no new MODULE) — no subprocess/socket.
- [ ] **Drift detection:** flip one expected decode `check` (e.g. assert `-32042` decodes to
      `UNSUPPORTED-PROTOCOL-VERSION`) and confirm the run prints a `FAILURE`; revert.
- [ ] **Regression:** `racket mcp/core/types/test/constants-test.rkt`,
      `.../guards-test.rkt`, and a load of `mcp/core/types/types.rkt` → no FAILURE/error (the
      façade still loads; decode did not perturb M1).
- [ ] **Health checks pass:** N/A.

### Expected Outcomes

The module MUST additionally export `jsonrpc-error->exn` (canonical decoder; +
`jsonrpc-error-jsexpr->exn` IF the optional wire wrapper is chosen). All item-006 exports remain.

- **decode functions:** `jsonrpc-error->exn` (canonical) [+ optional `jsonrpc-error-jsexpr->exn`].
- **codes switched on (all from `constants.rkt`):** `URL-ELICITATION-REQUIRED` (-32042),
  `UNSUPPORTED-PROTOCOL-VERSION` (-32004); the test also exercises `INVALID-PARAMS`,
  `RESOURCE-NOT-FOUND`, `INTERNAL-ERROR`, and an unknown `-39999`.
- **private helpers:** `url-elicitation-data?`, `unsupported-version-data?` (NOT provided).

**Test outcome:** `racket mcp/core/test/errors-test.rkt` → no `FAILURE`/error lines, prints the
final line. The NEW Part 6 adds: special-code decode checks ≥ 4 (incl. data preserved);
generic/unknown-code checks ≥ 3 (incl. received-code-preserved + `-39999`); data-gate
fall-through checks ≥ 2; round-trip checks ≥ 4 values × 3 fields; raisable/catchable checks ≥ 2;
data-carriage matrix ≥ 5; contract-rejection ≥ 1. **New decode checks total ≥ ~25** (atop item
006's ~60).

**Total public bindings provided by errors.rkt after 007:** item 006's ~12–13 + 1 (or 2) decode
function(s).

### Validation Results

```markdown
## Validation Results (completed YYYY-MM-DD)
- [ ] Service started: N/A (pure-data module, no services)
- [ ] Application started successfully: N/A (library; `require` succeeds)
- [ ] Build verified: `racket -e '(require (file "mcp/core/errors.rkt"))'` succeeds
      (`raco make` skipped — raco broken in sandbox; documented in Testing Prerequisites)
- [ ] Module load verified: `(require (file ".../errors.rkt"))` succeeds in isolation
- [ ] Tests verified: `racket mcp/core/test/errors-test.rkt` → exit 0, 0 FAILURE lines,
      prints "errors-test.rkt: all checks executed" (item-006 encode + new decode Part 6)
- [ ] Decode -32042 verified: → protocol-error? #t, code = URL-ELICITATION-REQUIRED, data preserved
- [ ] Decode -32004 verified: → protocol-error? #t, code = UNSUPPORTED-PROTOCOL-VERSION, data preserved
- [ ] Decode unknown-code verified: -39999 (and INVALID-PARAMS) → generic protocol-error?
      carrying the RECEIVED code (not defaulted), auth-error? #f
- [ ] Data-gate fall-through verified: -32042/-32004 with absent/malformed data → still the
      right code, no throw
- [ ] Round-trip verified: (jsonrpc-error->exn (exn->jsonrpc-error e)) preserves code/message/data
- [ ] Raisable/catchable verified: decoded exn catchable by protocol-error? handler; exn:fail?/mcp-error? #t
- [ ] Data-carriage verified: falsy/odd/nested data carried verbatim; absent stays absent
- [ ] Contract verified: raw hasheq input → exn:fail:contract? (canonical input is the struct)
- [ ] Codes-imported verified: no bare -32042/-32004 literals in decode code (constants only)
- [ ] Additive-only verified: git diff confined to DECODE anchor + second provide block (+ maybe one require line)
- [ ] Portability verified: require list = racket/contract + types/constants.rkt + types/spec-2025-11-25.rkt
- [ ] Drift detection: flipped a decode assertion → FAILURE printed; reverted → clean
- [ ] Regression: constants-test / guards-test / types.rkt load → 0 FAILURE/error lines
- [ ] Database tables verified: N/A
- [ ] API endpoints verified: N/A
- [ ] Screenshots captured: N/A (no UI)
```

### Test commands run and results (fill on delivery)

- `racket mcp/core/test/errors-test.rkt` → exit 0, no FAILURE, prints final line.
- `racket -e '(require (file "mcp/core/errors.rkt")) ...'` → smoke decode checks return -32042 /
  -39999 / -32602.
- `grep -nE '\-32042|\-32004' mcp/core/errors.rkt | grep -v ';;'` → no bare literals in decode code.
- `git diff mcp/core/errors.rkt` → additive (DECODE anchor + provide).
- Drift: flipped a decode assertion → FAILURE; reverted → clean.

---

## Decisions & Trade-offs

**Seeded decisions (the implementer confirms/records on delivery):**

- **Decode function name + signature (SETTLED — recommended).** `jsonrpc-error->exn :
  (-> jsonrpc-error? exn:fail:mcp:protocol?)`. The name is the exact inverse of item 006's
  `exn->jsonrpc-error` (the `->` reads the conversion direction). The CANONICAL input is the
  `jsonrpc-error` STRUCT (item 003), not a raw wire hasheq. **Rationale:** the engine (S3)
  parses an inbound error response with `json->jsonrpc-error-response`
  (`spec-2025-11-25.rkt:338`), which already produces a `jsonrpc-error` struct via
  `json->jsonrpc-error` — so handing the struct to the decoder is the natural call shape, and it
  is symmetric with ENCODE (which RETURNS a `jsonrpc-error` struct). Parsing raw JSON is M1's
  job (`json->jsonrpc-error`), not M2's — keeping M2 a pure exn↔struct converter preserves the
  layer boundary (item 006 Decisions "where exn->jsonrpc-error lives").
- **Decode input type — struct only, with an OPTIONAL thin wire wrapper (SETTLED —
  recommend struct-only unless a caller appears).** If a concrete caller holds a raw wire
  hasheq, add `jsonrpc-error-jsexpr->exn : (-> hash? exn:fail:mcp:protocol?)` `=
  (jsonrpc-error->exn (json->jsonrpc-error h))` (requires an additive `only-in
  json->jsonrpc-error` from the spec module). **Recommendation: OMIT it (YAGNI)** — S3 can call
  `json->jsonrpc-error` itself; adding the wrapper now bloats the surface for a hypothetical
  caller. The contract-rejection test (`a raw hasheq → exn:fail:contract?`) documents that the
  canonical form takes the struct.
- **Output type — `exn:fail:mcp:protocol`, NOT base/auth (SETTLED).** All decoded errors are
  PROTOCOL errors: a received JSON-RPC error object IS a wire/protocol error by definition (it
  crossed the wire as an error response). Mirrors TS where `fromError` always returns a
  `ProtocolError` (or a `ProtocolError` subclass). Auth errors (`exn:fail:mcp:auth`) are RAISED
  locally by the auth layer (S6/S7), never DECODED from a generic wire error in this path —
  there is no auth-specific JSON-RPC code to dispatch on here. So decode's contract co-domain is
  `exn:fail:mcp:protocol?`, narrower than `exn:fail:mcp?`. (If S6/S7 later needs auth-code
  decoding, that is an additive extension to this `cond`, not a contract change today.)
- **RECONCILIATION with item 005's façade typed errors (SETTLED — THE KEY 007 DECISION).**
  Item 005's `mcp/core/types/types.rkt` re-exports `make-facade-url-elicitation-required-error`
  / `facade-url-elicitation-required-error?` (types.rkt:1176–1178, delegating to
  `spec-2025-11-25.rkt:1851`) and `make-facade-unsupported-protocol-version-error` /
  `facade-unsupported-protocol-version-error?` (types.rkt:1244–1246, delegating to
  `spec-2026-07-28.rkt:1806`). **These are a DIFFERENT KIND of object from errors.rkt's typed
  errors, serving a different role — there is no collision, and errors.rkt's decode produces
  `exn:fail:mcp:protocol`, NOT the façade objects.** Concretely:
  - The FAÇADE constructors build **`jsonrpc-error-response` WIRE MESSAGES** — `(jsonrpc-error-response
    id (jsonrpc-error -32042 message (hasheq 'elicitations …)))` (spec-2025-11-25.rkt:1851–1855)
    — i.e. a complete, id-bearing JSON-RPC *response message* a server SENDS. Their predicates
    test "is this a wire error-response with code -32042?". They are M1 *message builders*.
  - errors.rkt's typed errors are **`exn:fail:mcp:protocol` RAISABLE EXCEPTIONS** — Racket `exn`
    values you `raise`/`with-handlers`-catch, carrying `code`/`message`/`data` but NO `id` and
    NO envelope. They are M2 *control-flow values*.
  - **These map cleanly onto the TS split:** TS's `ProtocolError` family (errors.ts) ARE
    exceptions (`extends Error`) — the analogue is errors.rkt's `exn:fail:mcp:*`. TS's
    *response-message* construction lives elsewhere (the protocol/transport layer building a
    `JSONRPCError` response object) — the analogue is M1's façade `jsonrpc-error-response`
    builders. So errors.rkt decode → exns (mirrors `ProtocolError.fromError`); the façade →
    wire response messages (mirrors building a `JSONRPCError`). **DECISION: errors.rkt's decode
    produces `exn:fail:mcp:protocol` instances and does NOT call, depend on, or return the
    façade typed-error builders.** The two coexist: a server BUILDS an outbound error with the
    façade message builder; a client DECODES an inbound error with `jsonrpc-error->exn` into an
    exn it raises locally. **errors.rkt does NOT require types.rkt** (no dependency added),
    keeping the layering clean (M2 errors do not depend on the M1 public façade).
  - *Open question surfaced to the lead (see summary):* should the façade ALSO re-export
    errors.rkt's `jsonrpc-error->exn` (so the public surface has both "build an outbound error
    message" and "decode an inbound error to an exn")? That is a façade-surface question for
    item 005's owner, NOT a blocker for 007 — 007 just provides `jsonrpc-error->exn` from
    errors.rkt; whether item 005 later re-exports it is its call.
- **Unknown-code fallback shape (SETTLED).** An unknown code → `(make-protocol-error code
  message data)` carrying the RECEIVED code verbatim (NOT defaulted to `-32603`). It is a
  *generic* PROTOCOL error (no specialized data handling), but a *typed* one with the right code
  — satisfying the queue's "generic failure is not produced where a specific one is defined"
  AND its dual "a specific type is not faked for an unknown code". Mirrors `errors.ts:38`
  (`return new ProtocolError(code, message, data)`). The decode NEVER produces a bare
  `exn:fail` or an `exn:fail:mcp` base — always `:protocol`.
- **The data-gate (SETTLED — mirrors errors.ts `&& data` + shape check).** `-32042`/`-32004`
  take the specialized branch ONLY when `data` is present AND well-shaped
  (`url-elicitation-data?`: a `json-object?` with `'elicitations`; `unsupported-version-data?`:
  a `json-object?` with `'supported` a `list?` + `'requested` a `string?`). On a gate miss the
  code STILL routes to a `(make-protocol-error <special-code> message data)` (the else/generic
  constructor) — so the code is always correct; the gate only governs the "the SDK deemed the
  payload specialization-worthy" semantics. **Observability caveat (recorded honestly):** since
  all three branches build the SAME `exn:fail:mcp:protocol` struct, the specialized-vs-generic
  distinction is NOT observable via a distinct Racket predicate today (unlike TS's distinct
  subclasses). The gate is kept for (a) exact errors.ts parity, (b) forward-compat if a future
  item adds named accessors / a `url-elicitation-error?` refinement predicate that relies on the
  data being well-shaped. The test asserts behavior through `code` + `data`, which is the
  honest observable surface.
- **What round-trips (SETTLED — the invariant's precise scope).** `(jsonrpc-error->exn
  (exn->jsonrpc-error e))` preserves **code, message, and data** — these are the strong testable
  invariants. It does NOT preserve the exn SUBTYPE: ENCODE erases `exn:fail:mcp` / `:auth` /
  `:protocol` to a flat `jsonrpc-error` (code/message/data only), so DECODE always reconstructs
  a `:protocol` exn. This is correct and intended (the wire has no notion of the Racket
  subtype; only the code crosses). The test documents this asymmetry explicitly so it is not
  mistaken for a bug. The reverse round-trip `(exn->jsonrpc-error (jsonrpc-error->exn j))`
  `equal?`-reproduces `j` (code/message/data), which IS a clean fixpoint.
- **Where message/data carry through (SETTLED).** The decoded exn's message = the received
  `(jsonrpc-error-message e)` verbatim (decode never synthesizes a default message — TS's
  subclass default messages, errors.ts:47/68, are bypassed because `fromError` always threads
  the received `message`). The decoded exn's data = the received `(jsonrpc-error-data e)`
  verbatim (`absent` stays `absent`; any present payload — including falsy/nested — carried by
  reference, never coerced). The `#:marks` default (`current-continuation-marks`) supplies a
  usable stack for the decoded exn (item 006's constructors handle this).
- **`json-object?` import (OPEN — implementer settles).** The data-gate needs an object check.
  Options: (a) import `json-object?` from `spec-2025-11-25.rkt` (one additive `only-in` entry —
  the predicate already exists at spec-2025-11-25.rkt:51; **RECOMMENDED** for reusing the exact
  M1 object notion); (b) use a local `(and (hash? d) (hash-eq? d) (immutable? d))`-style check
  (no new import, but re-defines the object notion — a mild parity hazard). **Recommend (a)** —
  one `only-in` line, no subprocess/socket, Portability NFR holds; reuses the same object
  predicate `jsonrpc-error/c`'s `data` field is validated against, so the gate agrees with the
  struct's own contract.
- **`contract-out` placement (FOLLOW item 006).** The decode function's contract `(->
  jsonrpc-error? exn:fail:mcp:protocol?)` goes in the SECOND `provide`/`contract-out` block
  (errors.rkt:81–96), appended after `exn->jsonrpc-error-jsexpr`. The data-gate helpers are
  unprovided private defines. No `contract-out` on them.

---

## Completion Reminder

On completion, the implementer MUST:

1. **Update `docs/aide/progress.md` — Stage S1 `errors.rkt` deliverable line.** Flip
   `mcp/core/errors.rkt` 🚧 → **✅** — item 007 delivers the DECODE half, so BOTH directions of
   the single conversion point (roadmap line 84 "covers both directions") and the
   both-directions test (roadmap line 86) are now satisfied. **This item OWNS the ✅ flip** that
   item 006 deliberately deferred (item 006 left it at 🚧, encode-only). Likewise flip the
   `errors-test.rkt` test deliverable to ✅ (both encode + decode tested). Never revert an icon
   backward.
2. **Touch the parity-matrix row** for `errors.rkt` (under `core/errors/*` / `core/auth/*`):
   record that ENCODE + DECODE BOTH exist and are tested, mirroring `errors.ts`
   `ProtocolError` + `ProtocolError.fromError` (errors.ts:21–39). Update the row's notes: the
   TS-flat 3-class family (`ProtocolError` + `UrlElicitationRequiredError` +
   `UnsupportedProtocolVersionError`) maps to ONE Racket `exn:fail:mcp:protocol` struct
   distinguished by code+data, and the decode dispatches on `-32042`/`-32004` with a data-gate +
   generic fall-through. Note the façade-vs-exn role split (Decisions) so the matrix maps
   `errors.ts` ↔ `errors.rkt` cleanly.
3. Leave the sibling `core/types/*` deliverables (`constants`, `guards`, `spec-2025-11-25`,
   `spec-2026-07-28`, `types.rkt` façade) at their current status — this item delivers only the
   DECODE half of `errors.rkt` and does NOT modify M1.
