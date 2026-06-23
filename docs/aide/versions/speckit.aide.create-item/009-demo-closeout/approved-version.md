# Work Item 009: Stage S1 demo script + parity-matrix/progress closeout

> **Queue:** `docs/aide/queue/queue-001.md` — Item 009 (`queue-001.md:47–48`). This is the
>   **LAST item in queue-001**; on delivery + execution it completes Stage S1 in full and
>   unblocks queue-002 / Stage S2 (`queue-001.md:15`, `queue-001.md:48`).
> **Stage:** S1 (Foundation: types, constants, guards, errors — L0 part 1). This item is the
>   **closeout** deliverable — the runnable demo plus the progress/parity-matrix bookkeeping that
>   marks S1 done. It adds NO new library types, structs, contracts, or errors; it exercises the
>   already-✅ items 001–008 from a downstream-consumer vantage and updates docs.
> **Module:** M1 (Types) + M2 (Errors) — the **demo + closeout**, NOT a new module. The demo is a
>   `racket`-runnable script (+ a companion `module+ test` so "runs end-to-end" is mechanically
>   verified by `raco test`, not eyeballed) that `require`s the item-008 barrel
>   `mcp/core/main.rkt` (`progress.md:52`) as an external consumer would.
> **Source vision:** `docs/aide/vision.md` Goal **G1** (wire-protocol parity, both revisions) —
>   the demo's round-trip is a hand-runnable G1 witness at the S1 level. Note the demo is a
>   *witness*, not a *proof*: full G1 is certified by the S9 conformance suite, so this item must
>   NOT over-claim G1 as fully satisfied (see §Project-specific adaptations and Completion
>   Reminder for the conservative progress edits).
> **Source roadmap:** `docs/aide/roadmap.md` Stage S1 **Demo** line (`roadmap.md:99` — "A REPL
>   transcript / script that parses a sample `initialize` request and a `tools/call` request from
>   JSON, prints the structs, re-emits JSON, and shows a malformed message converted to a correct
>   JSON-RPC error object") and the Stage-S1 **Testing/validation** parity-matrix criterion
>   (`roadmap.md:97` — "Parity matrix rows for `core/types/*`, `errors/*` marked `partial` (structs
>   exist; exercised by conformance later)"). Also the cross-stage **Parity discipline** note
>   (`roadmap.md:23` — "Each stage updates the §9 parity matrix rows it touches
>   (`done / partial / intentionally-excluded`)").
> **Source architecture:** `docs/aide/architecture.md` **§1.3** (public/internal boundary — the
>   demo consumes ONLY the curated `mcp/core/main.rkt` barrel, proving the barrel is a usable
>   single entry point); **§4.1** (the single exn↔JSON-RPC error-to-wire boundary — the demo's
>   malformed-message arm exercises the ENCODE direction item 006 built at that boundary). The
>   N1 normalized-superset façade (architecture N1, `types.rkt`) is the version-agnostic surface
>   the demo's commentary should reference, though the concrete request decoders the demo calls
>   live in the per-revision `spec-2025-11-25.rkt` module (see §Description for why).
> **Reference impl:** MCP TypeScript SDK v2 at `typescript-sdk/`. The fixtures the demo consumes
>   (`mcp/core/types/test/fixtures/initialize-request.json`, `tools-call-request.json`,
>   `error-response.json`) are TS-SDK-shaped fixtures already used by item 003's round-trip test
>   (`spec-2025-11-25-test.rkt:77–96`); the demo REUSES them rather than inventing JSON, so the
>   sample messages stay authoritative. There is no single TS file this demo ports line-for-line —
>   a demo/example script is a packaging artifact, not a runtime algorithm.
> **Delivered siblings (the FORMAT + rigor bar):**
>   `docs/aide/items/008-core-barrels-and-portability-test.md` (✅ delivered + approved 5/5 — the
>   immediately-preceding closeout-adjacent item; match its header-citation depth, build-contract
>   precision, acceptance-criterion concreteness, and Decisions discipline),
>   `docs/aide/items/007-error-decode-path.md` (✅, the DECODE half — source of the
>   `jsonrpc-error->exn`/typed-decoder surface), and
>   `docs/aide/items/006-error-hierarchy-and-encode-path.md` (✅, the ENCODE half — source of the
>   `exn->jsonrpc-error` / `exn->jsonrpc-error-jsexpr` the demo's malformed arm uses).
> **Status:** Specified (not yet implemented). On delivery + execution this is the **final S1
>   item** — it flips the Stage S1 header and stage-overview row to ✅, checks the remaining S1
>   acceptance boxes, records the parity-matrix `partial` state, and thereby completes Stage S1 /
>   unblocks queue-002.

---

## Description

Add the **Stage S1 demo script** the roadmap's S1 Demo line (`roadmap.md:99`) calls for, plus the
**progress.md / parity-matrix closeout edits** that mark Stage S1 complete. Two kinds of
deliverable:

1. **A runnable demo** (`mcp/core/demo/s1-demo.rkt`, see §Decision on location) that, requiring
   ONLY the item-008 curated barrel `mcp/core/main.rkt` as a downstream consumer would:
   - parses a sample **`initialize`** REQUEST and a **`tools/call`** REQUEST from JSON text into the
     appropriate structs (via the per-revision decoders re-exported through the barrel);
   - **prints** the resulting structs to stdout;
   - **re-emits** each parsed struct back to JSON and asserts the re-emission round-trips
     **identically** — where "identically" means **canonical-jsexpr equality (`jsexpr=?`,
     unordered object keys), NOT byte-identical string compare** (see §The "identically" trap
     below — this is the single most likely demo bug);
   - takes a **malformed** message and shows it converted to a **spec-correct JSON-RPC error
     object** via `errors.rkt`'s ENCODE path (item 006), at the architecture §4.1 error-to-wire
     boundary.
   The demo runs end-to-end via plain `racket mcp/core/demo/s1-demo.rkt`, printing a readable
   transcript, AND carries a `(module+ test …)` whose `rackunit` assertions make the round-trip and
   error-encode claims **non-vacuous and CI-checkable by `raco test`** (so "runs end-to-end" is
   mechanically enforced, not merely observed once).

2. **The closeout doc edits** to `docs/aide/progress.md`:
   - check the remaining Stage S1 **acceptance boxes** (`progress.md:56–62`) now satisfied by
     items 001–008 + this demo (exact box→evidence mapping in §The progress.md acceptance-box
     mapping);
   - flip the Stage S1 **header** (`progress.md:41`) and the **stage-overview S1 row**
     (`progress.md:27`) from 📋 → ✅, and the **shared test-deliverable line** (`progress.md:53`,
     currently 🚧 with item-008's shared-ownership note) → ✅ (this item is the deferred closeout
     item-008 explicitly handed forward — see item 008's Completion Reminder
     `008-…md:1164–1181`);
   - update the **"## Parity matrix progression"** section (`progress.md:334–336`) to record that
     `core/types/*` and `errors/*` are now `partial` (structs/errors exist; full conformance
     exercise deferred to S9), replacing its current "no rows yet (no source)" text — see §The
     parity-matrix update: what it concretely is, which RESOLVES the long-standing ambiguity about
     where "the parity matrix" lives.

This item writes NO `.rkt` library code beyond the demo file. It does not create `mcp/examples/`
(that is S9 / M15 — `progress.md:267–275`; do NOT collide with it). It does not re-open or
re-grade any already-✅ item-001–008 deliverable.

### Why the demo decodes via the per-revision module, not the N1 façade

The roadmap Demo line says "parse a sample `initialize` request … from JSON … into the resulting
structs." The concrete, JSON-text → request-struct decoders are `json->initialize-request` and
`json->call-tool-request`, which live in the per-revision module `spec-2025-11-25.rkt` (verified:
`spec-2025-11-25.rkt:130` `json->initialize-request`, `spec-2025-11-25.rkt:177`/`1139–1140`
`json->call-tool-request`, with their serializers `initialize-request->json` /
`call-tool-request->json` on the same `provide` lines). The N1 façade (`types.rkt`) exposes
**per-primitive** `normalize-facade-*` / `denormalize-facade-*` seams (verified:
`types.rkt:104–345`) — it does NOT expose a single top-level `json->initialize-request` request
decoder; the façade normalizes ALREADY-decoded per-revision structs into the version-agnostic
shape, it is not itself the JSON entry point for a whole request envelope. **Therefore the demo
calls the per-revision decoders** — which, through the item-008 barrel, are reachable under the
`r25:` prefix (verified: item 008 `prefix-in r25: "spec-2025-11-25.rkt"`, `008-…md:218`,
`progress.md:52`), i.e. **`r25:json->initialize-request`**, **`r25:json->call-tool-request`**,
**`r25:json->jsonrpc-error-response`**, and the matching `r25:…->json` serializers. The demo's
narration MAY mention that a real protocol layer (S4+) would further normalize these into the N1
façade, but the demo's own scope is the JSON↔struct round-trip + error-encode the roadmap line
specifies, which is fully exercised at the per-revision level. (The fixtures are `2025-11-25`-shaped
— `initialize-request.json`'s `protocolVersion` is `"2025-11-25"` — so the `r25:` decoders are the
correct match; do NOT use `r26:` for these fixtures.)

### The "identically" trap — the single most likely demo bug (read before implementing)

"Re-emit JSON identically" must be implemented as **`jsexpr=?` canonical equality (object keys
compared as unordered sets), NOT `(string=? (jsexpr->string a) (jsexpr->string b))` and NOT a
byte-for-byte file compare.** Two independent reasons, both verified against the real files:

- **JSON object key order is not guaranteed** across a `read-json` → struct → `write-json`
  round-trip. Racket's `write-json` emits a `hasheq`'s keys in an unspecified order; a struct
  serializer assembles its `hasheq` field-by-field. A byte/string compare would spuriously FAIL on
  a mere key-reordering that is semantically identical JSON. Item 003's own round-trip test already
  solved this with a `jsexpr=?` helper that "compares JSON objects as unordered key sets"
  (`spec-2025-11-25-test.rkt:12`, `:45–60`) — the demo MUST reuse that exact semantics (define an
  equivalent local `jsexpr=?`, or read the comparator's shape from that test). **Lists stay
  order-sensitive** (`spec-2025-11-25-test.rkt:51–52,59` — `(check-false (jsexpr=? (list 1 2)
  (list 2 1)))`), which is correct (array order is significant in JSON).
- **`initialize-request.json` carries an `extraUnknownKey` that is intentionally DROPPED on
  decode** (verified: `initialize-request.json` has `"extraUnknownKey": "should-be-dropped-on-
  params"`, and item 003's test at `spec-2025-11-25-test.rkt:77–81` handles this by removing
  `extraUnknownKey` from the expected re-serialized params before comparing — the struct decoder
  keeps only known fields + `_meta`, so the re-emitted JSON legitimately omits `extraUnknownKey`).
  **A naive demo that compares re-emitted JSON against the ORIGINAL file bytes WILL FAIL on this
  fixture** because the round-trip correctly drops that key. The demo's round-trip assertion for
  `initialize-request.json` must compare against an **expected jsexpr with `extraUnknownKey`
  removed from `params`** (mirroring `spec-2025-11-25-test.rkt:77–81` exactly), NOT against the raw
  file. (`tools-call-request.json` and `error-response.json` have no such dropped key — verified —
  so they round-trip against their raw fixture jsexpr directly, per `spec-2025-11-25-test.rkt:83–84`
  and `:95–96`.) The demo's narration should explicitly call out that the unknown key is dropped,
  since that is a real, correct, spec-relevant behavior worth showing.

### The malformed-message → JSON-RPC error arm — the concrete mechanism

`errors.rkt`'s ENCODE entry points take an **`exn`**, not a raw bad jsexpr (verified:
`errors.rkt:98` `[exn->jsonrpc-error (-> exn? jsonrpc-error?)]`, `errors.rkt:100`
`[exn->jsonrpc-error-jsexpr (-> exn? hash?)]`). So the rejection must produce an `exn` to encode.

> **CRITICAL — the decoder does NOT self-reject; the rejection MUST go through the contract.
> Verified by running code against the live barrel (Racket 8.18):**
>
> `r25:json->call-tool-request` and `r25:json->call-tool-request-params` are plain functions whose
> result is NOT `contract-out`'d, and the "required" field reader `h-req`
> (`spec-2025-11-25.rkt:76`, `(define (h-req h key) (hash-ref h key absent))`) returns the `absent`
> sentinel on a missing key instead of raising. So BOTH "obviously malformed" inputs an earlier
> draft of this spec proposed are silently ACCEPTED, not rejected:
> ```
> (r25:json->call-tool-request-params (hasheq 'name 42 'arguments (hasheq)))
>   => #(struct:call-tool-request-params 42 #hasheq() absent absent)   ; name=42 ACCEPTED, no raise
> (r25:json->call-tool-request-params (hasheq))
>   => #(struct:call-tool-request-params absent absent absent absent)  ; missing name ACCEPTED, no raise
> ```
> A `with-handlers`-around-the-decoder design therefore **never catches a decoder exception** — the
> decoder returns normally, control falls to whatever follows, and if that "whatever" is a guard
> like `(error "decoder unexpectedly accepted …")` then the encoded error object carries the
> GUARD's message, not a real rejection. A `module+ test` asserting only `code == -32603` +
> non-empty message would pass on that fabricated error — a **vacuously-green test that proves
> nothing.** This is the exact failure mode this item must avoid.

**The rejection mechanism the demo MUST use — drive the contract explicitly, mirroring the
existing test at `spec-2025-11-25-test.rkt:219–224`** (which is how the repo itself rejects a
numeric `name`):

```racket
;; decode garbage (succeeds — decoder doesn't validate), THEN apply the contract,
;; which DOES raise on the type violation:
(contract r25:call-tool-request-params/c
          (r25:json->call-tool-request-params (hasheq 'name 42 'arguments (hasheq)))
          'demo 'demo)
;; => raises: contract violation; expected: string?; given: 42
;;    in the call-tool-request-params-name field
```

- **`r25:call-tool-request-params/c` IS reachable through the barrel** (verified live:
  `(contract? r25:call-tool-request-params/c)` → `#t`), and `r25:json->call-tool-request-params`
  too (`(procedure? r25:json->call-tool-request-params)` → `#t`). **These two names are NOT in the
  original `only-in` list (§The build contract) and MUST be ADDED to it** — see the updated
  `require` form below.
- The raised exn is a plain `exn:fail` (a contract violation, not an `exn:fail:mcp`), so
  `exn->jsonrpc-error` (`errors.rkt:171–176`) maps it to code **`-32603` INTERNAL-ERROR** (the
  non-mcp-error branch, `errors.rkt:176`) with a real message beginning `"contract violation\n
  expected: string?"` — **verified live**: the full pipeline
  `(with-handlers ([exn:fail? exn->jsonrpc-error-jsexpr]) (contract …/c (json->…params (hasheq
  'name 42 …)) 'demo 'demo))` produced `code: -32603`, `message:` starting `"contract violation …
  expected: string? …"`. This is a GENUINE spec-contract rejection encoded to the wire, not a
  guard crash. (`INTERNAL-ERROR = -32603` reached through the barrel from item 001 — verified
  `008-…md:644`.)

**The `module+ test` MUST assert the rejection was REAL, not fabricated** (this is mandatory, not
optional — it is what makes the test non-vacuous): in addition to `(hash? err-obj)`,
`(= (hash-ref err-obj 'code) -32603)`, and non-empty `message`, it MUST assert the message is the
CONTRACT-violation message and NOT a guard string — e.g.
`(check-true (regexp-match? #rx"contract violation" (hash-ref err-obj 'message)))` and/or
`(check-false (regexp-match? #rx"unexpectedly accepted" (hash-ref err-obj 'message)))`. Structuring
the arm so `err-obj` can ONLY be produced by the `(contract …/c …)` raise (no fallback `(error …)`
guard inside the same `with-handlers`) is the cleanest way to guarantee this — see §Testing
strategy for the exact structure. A future regression that makes the contract stop raising must
make this arm FAIL, not silently pass.

**Optional richer code (shape B), layered on TOP of the real rejection, NOT instead of it.** If a
more spec-meaningful code than the catch-all `-32603` is desired (e.g. `-32602` `INVALID-PARAMS`
for a bad-params rejection), the demo MAY, inside the `with-handlers`, re-wrap the caught contract
exn as `(make-protocol-error INVALID-PARAMS (exn-message caught))` (`errors.rkt:88–94`) before
`exn->jsonrpc-error-jsexpr`, yielding `code: -32602`. This is allowed ONLY as a transformation of
the genuinely-caught contract exn — never as a hand-constructed error from a valid input. If used,
the `module+ test` asserts the chosen code (`-32602`) instead of `-32603`, AND still asserts the
message carries the underlying contract-violation text (so the rejection's provenance stays
provable). Record the choice (plain `-32603`, or re-wrapped `-32602`) and the constant used in
Decisions.

The demo MUST end the malformed arm by printing a valid JSON-RPC error **object** (a
jsexpr/`hasheq`, suitable for `write-json`) and the `module+ test` MUST assert its shape (an
integer `code`, a non-empty string `message`) PLUS the not-fabricated check above — proving the
"converted to a correct JSON-RPC error object" claim is real, not narration and not a guard crash.

---

## The build contract — the demo's exact arms (enumerate ALL)

The demo file's body is organized as four labelled, printing arms plus a `module+ test`. The
representative function/identifier names below are **verified present** in the sources as of
spec-writing; the implementer must re-confirm each against the current files (items 001–008 are
✅ and stable, but re-verify rather than trust this list blindly — the AC are outcome-based so a
renamed identifier is caught by a failing `raco test`, not a silent pass).

| Arm | Input fixture | Barrel-reachable functions called | Prints | `module+ test` asserts |
|---|---|---|---|---|
| **1 — `initialize` round-trip** | `mcp/core/types/test/fixtures/initialize-request.json` (`initialize-request.json`) | `r25:json->initialize-request` (decode), `r25:initialize-request->json` (re-emit) | the parsed `initialize-request` struct; the re-emitted JSON | `(jsexpr=? expect rt)` where `expect` = original jsexpr with `extraUnknownKey` removed from `params` (per `spec-2025-11-25-test.rkt:77–81`); a second idempotent pass `(jsexpr=? rt (->json (->struct rt)))` |
| **2 — `tools/call` round-trip** | `tools-call-request.json` | `r25:json->call-tool-request` (decode), `r25:call-tool-request->json` (re-emit) | the parsed `call-tool-request` struct; the re-emitted JSON | `(jsexpr=? orig rt)` against the RAW fixture jsexpr (no dropped key — `spec-2025-11-25-test.rkt:83–84`); idempotent second pass |
| **3 — malformed → JSON-RPC error** | `tools/call`-params with a type-violating `name` (`(hasheq 'name 42 'arguments (hasheq))`) — chosen because the decoder ACCEPTS it but the contract REJECTS it (see §The malformed-message arm); NOT a "missing name" / "wrong type passed to the bare decoder" input, both of which are silently accepted | `r25:json->call-tool-request-params` (decode — succeeds), then `(contract r25:call-tool-request-params/c … 'demo 'demo)` inside `with-handlers` (THIS raises), then `exn->jsonrpc-error-jsexpr` (encode); optionally re-wrap via `make-protocol-error` (shape B) | the malformed input; the raised contract violation; the resulting JSON-RPC error **object** | `(hash? err-obj)`; `(= code -32603)` (or the re-wrapped shape-B code); non-empty string `message`; **AND the message matches `#rx"contract violation"` and does NOT match a guard string** (the not-fabricated assertion — the test's whole point) |
| **4 (optional, recommended) — round-trip the `error-response.json` envelope** | `error-response.json` | `r25:json->jsonrpc-error-response` (decode), `r25:jsonrpc-error-response->json` (re-emit) | the parsed `jsonrpc-error-response` struct; the re-emitted JSON | `(jsexpr=? orig rt)` against the raw fixture (`spec-2025-11-25-test.rkt:95–96`) | 

Arm 4 is recommended (it shows a *full JSON-RPC error envelope* round-tripping, complementing
arm 3's *constructed* error object) but not strictly required by the roadmap Demo line; include it
if it keeps the transcript coherent, and note its inclusion/exclusion in Decisions.

**`require` form (the demo as a downstream consumer):**

```racket
#lang racket/base
(require racket/pretty json
         (only-in (file "../main.rkt")        ; the item-008 top barrel — mcp/core/main.rkt
                  ;; per-revision decoders/serializers (r25:-prefixed via item 008's prefix-in)
                  r25:json->initialize-request   r25:initialize-request->json
                  r25:json->call-tool-request    r25:call-tool-request->json
                  r25:json->jsonrpc-error-response r25:jsonrpc-error-response->json
                  ;; Arm 3 rejection: the -params decoder + its contract (the decoder does NOT
                  ;; self-reject; (contract …/c …) is what raises — VERIFIED reachable through
                  ;; the barrel: (procedure? r25:json->call-tool-request-params)=#t,
                  ;; (contract? r25:call-tool-request-params/c)=#t)
                  r25:json->call-tool-request-params  r25:call-tool-request-params/c
                  ;; error ENCODE path (items 006/007)
                  exn->jsonrpc-error-jsexpr make-protocol-error
                  ;; a constant, to show the barrel reaches item 001 too
                  INTERNAL-ERROR))
```

> The exact relative path in `(file "../main.rkt")` depends on the demo's chosen location (see
> §Decision: demo file location). If the demo lives at `mcp/core/demo/s1-demo.rkt`, the barrel is
> `(file "../main.rkt")` (one directory up from `demo/` is `mcp/core/`). Use the codebase's
> existing runtime-path idiom for locating sibling/fixture files at runtime
> (`define-runtime-path`, as `spec-2025-11-25-test.rkt:40` does) rather than CWD-relative literals,
> so `racket mcp/core/demo/s1-demo.rkt` works from any working directory. The demo loads fixtures
> from `mcp/core/types/test/fixtures/` — compute that path via `define-runtime-path` relative to
> the demo file, e.g. `(define-runtime-path fixtures "../types/test/fixtures")`.

> **Decision — re-confirm the `r25:` decoder/serializer names compile through the barrel before
> writing the test.** Item 008 re-exports `spec-2025-11-25.rkt`'s surface under the `r25:` prefix
> (`008-…md:218,238`). A quick `racket -e '(require (file "mcp/core/main.rkt")) (displayln
> (procedure? r25:json->initialize-request))'` → `#t` (run from repo root) confirms the prefixed
> name is reachable before the full demo is written; if it prints an unbound-identifier error,
> re-read item 008's actual delivered `provide` form (it may have used a different prefix or
> re-exported these unprefixed via `types.rkt`'s façade — verify, don't assume).

### Decision: demo file location

**Use `mcp/core/demo/s1-demo.rkt`** (a NEW `mcp/core/demo/` directory). Justification:

- **It must NOT collide with the future `mcp/examples/` tree (S9 / M15, `progress.md:267–275`,
  `roadmap.md` S9 deliverables).** The S9 curated-examples set (`stdio server`, `basic client`,
  etc.) is a separate, application-surface deliverable; a Stage-S1 internal demonstration script is
  not one of those seven curated examples and should not pre-seed that directory (verified: neither
  `mcp/examples/` nor `mcp/demos/` nor `mcp/core/demo/` exists yet). Placing the demo under
  `mcp/core/demo/` keeps it adjacent to the S1 code it exercises and clearly out of `mcp/examples/`'s
  way.
- **`mcp/core/demo/s1-demo.rkt`** (singular `demo/`, S1-prefixed filename) leaves room for later
  per-stage demos (`s2-demo.rkt`, …) under the same directory without renaming, and signals this is
  a per-stage internal demonstration, distinct from the user-facing S9 `examples/`.
- The companion `module+ test` lives in the SAME file (so `raco test mcp/core/demo/s1-demo.rkt`
  and a directory-level `raco test mcp/core/demo/` both pick it up — verify `raco test`'s
  directory recursion covers `mcp/core/demo/`; if the project's canonical green command is
  `raco test mcp/core/types/ mcp/core/test/` it must be EXTENDED to also cover the demo's location,
  OR the demo test placed where the existing command already reaches — record the final invocation
  in Decisions and update the AC's literal `raco test` command accordingly).

(If the implementer has a strong reason to prefer `mcp/core/demo/s1-demo.rkt` vs an alternative
like `mcp/demos/s1-demo.rkt`, either is acceptable so long as it (a) does not shadow the future
`mcp/examples/` and (b) is reachable by the project's `raco test` invocation — record the final
choice and the test command in Decisions.)

---

## Acceptance criteria

- [ ] **The demo file `mcp/core/demo/s1-demo.rkt` exists** as `#lang racket/base`, and `require`s
      the item-008 barrel `mcp/core/main.rkt` (NOT the underlying per-revision modules directly) —
      proving the barrel is a usable single entry point (architecture §1.3). `raco make
      mcp/core/demo/s1-demo.rkt` exits 0.
- [ ] **The demo runs end-to-end via plain `racket`:** `racket mcp/core/demo/s1-demo.rkt` (run
      from repo root) exits 0 and prints a readable transcript containing, in order: the parsed
      `initialize` struct, its re-emitted JSON, an `initialize round-trip: OK`-style line; the
      parsed `tools/call` struct, its re-emitted JSON, a `tools/call round-trip: OK`-style line;
      and the malformed-message arm's input plus the resulting JSON-RPC error **object** with its
      code. (Specify the exact "OK" wording in implementation; the AC requires the transcript make
      each of the four roadmap-mandated steps visibly observable — parse, print, re-emit, malformed→error.)
- [ ] **Arm 1 — `initialize` round-trips identically (canonical jsexpr):** the demo decodes
      `initialize-request.json` with `r25:json->initialize-request`, re-emits with
      `r25:initialize-request->json`, and asserts `(jsexpr=? expect rt)` where `expect` is the
      original jsexpr with `extraUnknownKey` removed from `params` (mirroring
      `spec-2025-11-25-test.rkt:77–81`). The assertion is in the `module+ test` and passes under
      `raco test`. **A byte/string compare here is WRONG and must not be used** — see §The
      "identically" trap.
- [ ] **Arm 2 — `tools/call` round-trips identically (canonical jsexpr):** the demo decodes
      `tools-call-request.json` with `r25:json->call-tool-request`, re-emits with
      `r25:call-tool-request->json`, and asserts `(jsexpr=? orig rt)` against the RAW fixture
      jsexpr (no dropped-key handling needed — verified). Passes under `raco test`.
- [ ] **Both round-trip arms are also idempotent:** a second `read→struct→write` pass yields a
      `jsexpr=?`-equal result (mirroring `spec-2025-11-25-test.rkt:68–69`'s idempotence check) —
      guards against an asymmetric decoder/serializer that "round-trips once" by luck.
- [ ] **Arm 3 — a malformed message is converted to a spec-correct JSON-RPC error object via a
      GENUINE contract rejection:** the demo decodes `(hasheq 'name 42 'arguments (hasheq))` with
      `r25:json->call-tool-request-params` (which SUCCEEDS — the decoder does not validate), then
      applies `(contract r25:call-tool-request-params/c <decoded> 'demo 'demo)` inside
      `with-handlers`, which RAISES a `string?` contract violation (mirroring
      `spec-2025-11-25-test.rkt:219–224`); the caught exn is encoded with `exn->jsonrpc-error-jsexpr`
      to a JSON-RPC error **object** (`hash?`, integer `code`, non-empty string `message`). The
      `module+ test` asserts `(hash? err-obj)`, `(exact-integer? (hash-ref err-obj 'code))`,
      `(= (hash-ref err-obj 'code) -32603)` (the non-mcp contract-violation mapping —
      `errors.rkt:176`; or the re-wrapped shape-B code if used), and a non-empty `message`. **Both
      `r25:json->call-tool-request-params` and `r25:call-tool-request-params/c` MUST be in the
      demo's `only-in` list** (verified reachable through the barrel:
      `(contract? r25:call-tool-request-params/c)` → `#t`).
- [ ] **THE NON-VACUOUS ASSERTION (the iteration-001 blocker) — the error is a REAL contract
      rejection, not a fabricated guard crash:** the `module+ test` MUST additionally assert
      `(regexp-match? #rx"contract violation" (hash-ref err-obj 'message))` AND
      `(check-false (regexp-match? #rx"unexpectedly accepted" (hash-ref err-obj 'message)))`. This
      is mandatory: the decoder ACCEPTS both "missing name" and "wrong-type name passed to the bare
      decoder" (verified live), so a `with-handlers`-around-the-bare-decoder design with a
      `(error "decoder unexpectedly accepted …")` fallthrough would encode the GUARD's crash and
      pass a code-only/message-non-empty test GREEN while proving nothing. The error object MUST be
      producible ONLY by the `(contract …/c …)` raise (no fabricating `(error …)` is the source of
      `err-obj`), and the message-content assertions above must FAIL if a future regression makes
      the contract stop raising. Item 003's flat contract IS the rejector here (`queue-001.md:30`),
      reached via `(contract …/c …)`, NOT via the non-validating decoder.
- [ ] **`raco test` is GREEN across all of `mcp/core/types/` and `mcp/core/errors.rkt`** (the
      queue's literal closeout test claim, `queue-001.md:48`). Concretely: the project's green
      baseline (`raco test mcp/core/types/ mcp/core/test/` → **908 tests passed**, exit 0, per
      item 008's Validation Results `008-…md:1041–1042,1092–1093`) is NOT regressed, and the new
      demo's `module+ test` checks pass when its location is included in the `raco test` invocation
      (state the exact command — e.g. `raco test mcp/core/types/ mcp/core/test/ mcp/core/demo/`).
- [ ] **The demo adds NO new library types/structs/contracts/errors** — it is a pure consumer.
      `grep -cE '\(struct |\(define-struct|define-contract|exn:fail:mcp' mcp/core/demo/s1-demo.rkt`
      → `0` for struct/contract/error definitions (the demo may use `define` for local helpers and
      the `jsexpr=?` comparator — that is fine; the prohibition is on declaring NEW protocol
      types/errors, which belong to items 001–007, not this closeout).
- [ ] **The demo does NOT create or write into `mcp/examples/`** (S9 / M15 territory —
      `progress.md:267–275`): `test ! -d mcp/examples` still holds after this item, and the demo
      lives under `mcp/core/demo/` (or the recorded alternative), not `mcp/examples/`.
- [ ] **Portability is not regressed:** the demo requires only `mcp/core/main.rkt` (+ `json`,
      `racket/pretty`, `racket/runtime-path`), none of which pulls in a subprocess/socket module;
      the item-008 portability test still passes (the demo is not in the barrel's import graph, so
      it cannot regress the barrel's transitive closure, but confirm `raco test` over the item-008
      portability suite still passes as part of the green baseline).
- [ ] **progress.md acceptance boxes checked per the exact mapping** in §The progress.md
      acceptance-box mapping: `progress.md:56` (raco test), `:58` (envelope round-trips), `:59`
      (decode `-32042`/`-32004`), `:60` (restricted-namespace load test), `:61` (parity rows
      `partial`), `:62` (the demo itself) all flip `[ ]` → `[x]`; `:57` is already `[x]` and stays.
      No box is unchecked or reverted (`progress.md:19`).
- [ ] **Stage S1 status flipped to ✅ in BOTH places** item 008 deferred to this item
      (`008-…md:1177–1181`): the Stage S1 header `## Stage S1 — … — 📋` (`progress.md:41`) → ✅,
      and the stage-overview table S1 row (`progress.md:27`) `| S1 | … | 📋 |` → `| S1 | … | ✅ |`.
      Also the shared test-deliverable line (`progress.md:53`, currently 🚧) → ✅, since this item
      lands the demo + final closeout that retires it.
- [ ] **The parity-matrix update is present and unambiguous** per §The parity-matrix update:
      the `progress.md:334–336` "## Parity matrix progression" section's "Current state: **no rows
      yet (no source).** 📋" is replaced with text recording `core/types/*` and `errors/*` as
      `partial` (structs/errors exist; full conformance exercise deferred to S9). **No new literal
      table is added to `roadmap.md` §9** (see §The parity-matrix update for the explicit decision
      and justification); the roadmap's existing prose criterion (`roadmap.md:97`) and the updated
      progress.md section TOGETHER constitute the parity matrix of record at S1.
- [ ] **Conservative goal-coverage edits only:** any touch to the "Vision goal coverage" G1 row
      (`progress.md:298`) or the NFR rows (`progress.md:324,330`) is conservative — S1 only
      PARTIALLY satisfies G1 (full wire-parity is S9-certified), so G1 must NOT be marked ✅ here;
      see §The progress.md acceptance-box mapping for exactly what 009 may touch vs must leave.

---

## The progress.md acceptance-box mapping (box → evidence)

Exact mapping of each Stage S1 acceptance box (`progress.md:56–62`) to the delivering item, so the
implementer checks each box ONLY against real evidence (mirrors item 007's evidence discipline):

| Box (line) | Text | Now satisfied by | Check? |
|---|---|---|---|
| `:56` | `raco test` over `mcp/core/types/` + `mcp/core/errors.rkt` passes | items 001–008 (908 tests green, `008-…md:1041`) + this demo's test | **[x]** |
| `:57` | Error codes + version constants match TS byte-for-byte | item 001 (already `[x]`) | already `[x]` — leave |
| `:58` | Each JSON-RPC envelope kind round-trips from TS fixture → struct → identical JSON (G1) | items 003/004 round-trip tests (`spec-2025-11-25-test.rkt`) + this demo's arms 1/2/4 | **[x]** |
| `:59` | Decode `-32042` → `UrlElicitationRequired`; `-32004` → unsupported-version | item 007 decode tests (`errors-test.rkt`) | **[x]** |
| `:60` | Restricted-namespace load test: no subprocess/socket pulled in (Portability NFR) | item 008 portability walk (`mcp/core/test/main-test.rkt`) | **[x]** |
| `:61` | Parity rows `core/types/*`, `errors/*` marked `partial` | **this item's parity-matrix edit** (§The parity-matrix update) | **[x]** |
| `:62` | Demo: parse `initialize`+`tools/call` from JSON, re-emit, malformed→JSON-RPC error | **this item's demo** | **[x]** |

Boxes `:56`, `:58`, `:59`, `:60` are satisfied by ALREADY-DELIVERED items (001–008); this item is
the closeout that records them as done now that the whole S1 batch has landed (it does not
re-implement them). Boxes `:61` and `:62` are this item's own new work. Do NOT check a box whose
evidence you have not personally re-confirmed green during implementation (e.g. re-run the item-008
portability test before checking `:60`).

---

## The parity-matrix update — what it concretely is (RESOLVING the long-standing ambiguity)

**Decision: there is NO materialized parity-matrix TABLE in `roadmap.md`, and this item does NOT
add one.** Verified: `roadmap.md` mentions "parity matrix rows … marked `partial`" only as PROSE
inside each stage's Testing/validation criteria (e.g. `roadmap.md:97` for S1) and in the
cross-stage discipline note (`roadmap.md:23` "Each stage updates the §9 parity matrix rows it
touches"); there is **no literal table with `done`/`partial`/`intentionally-excluded` rows anywhere
in `roadmap.md`**. The only place that tracks parity-row state as a materialized artifact is
`progress.md`'s **"## Parity matrix progression"** section (`progress.md:334–336`), which currently
reads "Current state: **no rows yet (no source).** 📋". The item-008 reviewer already flagged that
"update the roadmap §9 parity-matrix rows to `partial`" is ambiguous because the table it implies
does not exist. **This item resolves the ambiguity definitively:**

- **The parity matrix of record at S1 = the roadmap's per-stage prose criteria
  (`roadmap.md:97`, already authored) + the `progress.md` "Parity matrix progression" section
  (`progress.md:334–336`, which this item updates).** Inventing a new standalone table the rest of
  the roadmap does not use and does not reference would be scope creep that diverges from the
  established doc structure — rejected. The roadmap's S9 closeout (`roadmap.md` S9 deliverable
  "Final parity-matrix pass", `progress.md:280`) is where a full materialized matrix, if ever
  built, belongs; at S1 the prose + progress-section IS the matrix.

- **The concrete edit this item makes** is to `progress.md:336`. Replace:

  > Per-stage discipline: each stage flips the `core/types/*`, `errors/*`, `validators/*`,
  > transport, role, and auth rows from `partial`→`done` as it fully exercises them; S9 is the
  > certification pass. Tracked in roadmap §9 parity matrix. Current state: **no rows yet (no
  > source).** 📋

  with text recording the S1 rows as `partial`, for example:

  > Per-stage discipline: each stage flips the `core/types/*`, `errors/*`, `validators/*`,
  > transport, role, and auth rows from `partial`→`done` as it fully exercises them; S9 is the
  > certification pass. Tracked via each stage's roadmap Testing/validation criteria (no separate
  > materialized table until the S9 closeout pass). **Current state (after Stage S1):**
  > `core/types/*` and `errors/*` are **`partial`** — the per-revision structs/contracts (items
  > 003/004), the N1 façade (item 005), the guards (item 002), the constants (item 001), and the
  > bidirectional exn↔JSON-RPC error layer (items 006/007) all exist and round-trip TS-SDK
  > fixtures, but full cross-SDK conformance exercise is deferred to S9 (§9.1/§9.2). All other
  > rows remain `📋` (no source yet). 🚧

  (The implementer should read the section's exact current wording at edit time and preserve its
  voice; the above is the required *content*, not a mandated verbatim string — the load-bearing
  changes are: `core/types/*` and `errors/*` → `partial`; "no rows yet (no source)" removed;
  conformance-deferred-to-S9 noted; status icon advanced from 📋 to 🚧 since most rows are still
  planned.)

- **Justification for `partial`, not `done`:** the roadmap criterion (`roadmap.md:97`) literally
  says `partial` ("structs exist; exercised by conformance later"). The structs/errors EXIST and
  round-trip local TS-SDK fixtures, but cross-SDK byte-for-byte conformance (G1 full / §9.1 / §9.2)
  is an S9 deliverable — so `partial` is correct and `done` would over-claim. This matches the
  N-stage discipline (`progress.md:334`, `roadmap.md:23`).

---

## Implementation steps

1. **Confirm the green baseline.** From repo root: `raco make mcp/core/types/*.rkt
   mcp/core/errors.rkt mcp/core/types/main.rkt mcp/core/main.rkt` → exit 0; `raco test
   mcp/core/types/ mcp/core/test/` → **908 tests passed**, exit 0 (the baseline this item must not
   regress — `008-…md:1092–1093`). Confirm `racket --version` (this session: Racket 8.18; `raco`
   is NOT broken here — do not propagate any stale "raco is broken" note from very early items, per
   `008-…md:937–954`).
2. **Confirm the barrel reaches the decoders under the expected names.** `racket -e '(require
   (file "mcp/core/main.rkt")) (for-each (lambda (p) (displayln (procedure? p))) (list
   r25:json->initialize-request r25:json->call-tool-request r25:json->jsonrpc-error-response
   exn->jsonrpc-error-jsexpr make-protocol-error)) (displayln INTERNAL-ERROR)'` → six `#t` lines
   then `-32603`. If any name is unbound, re-read item 008's delivered `provide` form and adjust
   the `only-in` list (the prefix or façade-vs-per-revision routing may differ from this spec's
   assumption — verify, don't assume).
3. **Read the proven fixture round-trip pattern** at `spec-2025-11-25-test.rkt:40–96` (the
   `define-runtime-path fixtures`, `read-fx`, `jsexpr=?` comparator at `:45–60`, the `check-rt`
   helper at `:63–69`, and the `extraUnknownKey`-drop handling at `:77–81`). The demo's assertions
   reuse this exact pattern — define a local `jsexpr=?` with the same unordered-key/ordered-list
   semantics.
4. **Write `mcp/core/demo/s1-demo.rkt`** per §The build contract: the four printing arms +
   `module+ test`. Load fixtures via `define-runtime-path` relative to the demo file (so `racket
   <demo>` works from any CWD). Use `racket/pretty`'s `pretty-print` (or `displayln` + `~a`) for
   the struct printouts and `(jsexpr->string …)` or `write-json` for the JSON printouts — make the
   transcript readable.
5. **Run the demo standalone:** `racket mcp/core/demo/s1-demo.rkt` → exit 0, readable transcript
   showing all four roadmap steps (parse, print, re-emit, malformed→error). Eyeball that the
   re-emitted JSON looks right and the error object carries a sensible code.
6. **Run the demo's tests:** `raco test mcp/core/demo/s1-demo.rkt` → exit 0, all `module+ test`
   checks pass. Confirm the round-trip assertions are NON-VACUOUS (temporarily break a serializer
   call to confirm the `jsexpr=?` check fails, then revert — mirrors item 008's drift-check
   discipline).
7. **Run the full suite including the demo:** `raco test mcp/core/types/ mcp/core/test/
   mcp/core/demo/` → exit 0, 908 inherited + the demo's new checks, 0 regressions. Record the
   exact final command (the green baseline command must be EXTENDED to include the demo's location
   — note it in Decisions and in the AC's literal command).
8. **Edit `docs/aide/progress.md` — acceptance boxes.** Flip `:56`, `:58`, `:59`, `:60`, `:61`,
   `:62` `[ ]` → `[x]` per §The progress.md acceptance-box mapping (only after re-confirming each
   box's evidence is green — e.g. re-run the item-008 portability test before checking `:60`).
   Leave `:57` (already `[x]`) untouched.
9. **Edit `docs/aide/progress.md` — Stage S1 status.** Flip the header `progress.md:41`
   `## Stage S1 — … — 📋` → ✅; the stage-overview S1 row `progress.md:27` `| S1 | … | 📋 |` → ✅;
   and the shared test-deliverable line `progress.md:53` 🚧 → ✅. Never revert any icon
   (`progress.md:19`).
10. **Edit `docs/aide/progress.md` — parity-matrix progression.** Replace `progress.md:336`'s
    "no rows yet (no source). 📋" text per §The parity-matrix update (mark `core/types/*` and
    `errors/*` `partial`, note conformance deferred to S9, advance icon to 🚧). Do NOT add a new
    table to `roadmap.md`.
11. **Conservative goal/NFR edits.** Optionally annotate the G1 row (`progress.md:298`) and the
    Portability/MCP-spec-compat NFR rows (`progress.md:324,330`) to reflect S1 partial progress —
    but do NOT mark G1 ✅ (full wire-parity is S9). If unsure, leave the goal/NFR tables untouched
    and note in Decisions that they advance at S9; the load-bearing closeout edits are the S1
    acceptance boxes + header + parity-matrix section, NOT the cross-stage goal tables.
12. **Final green check** and Decisions write-up: re-run the full `raco test` command + the
    standalone `racket <demo>` run, record outputs in Validation Results, and fill in §Decisions &
    Trade-offs (malformed-arm shape chosen + code, arm-4 included or not, final `raco test`
    command, demo location).

---

## Testing strategy

**Demo file:** `mcp/core/demo/s1-demo.rkt`, `#lang racket/base`. Top-level arms print the
transcript (so `racket <demo>` shows it); a `(module+ test …)` holds the `rackunit` assertions (so
`raco test <demo>` mechanically verifies the round-trip + error-encode claims). This split mirrors
the project convention where runnable behavior and its checks co-locate; the `module+ test`
submodule is NOT loaded on a plain `racket <demo>` run, so the printed transcript stays clean while
the checks still run under `raco test`.

```racket
#lang racket/base
(require racket/pretty json racket/runtime-path
         (only-in (file "../main.rkt")
                  r25:json->initialize-request   r25:initialize-request->json
                  r25:json->call-tool-request    r25:call-tool-request->json
                  r25:json->jsonrpc-error-response r25:jsonrpc-error-response->json
                  ;; Arm 3 — the -params decoder + its contract (decoder does NOT self-reject;
                  ;; the contract is what raises). VERIFIED reachable through the barrel.
                  r25:json->call-tool-request-params r25:call-tool-request-params/c
                  exn->jsonrpc-error-jsexpr make-protocol-error INTERNAL-ERROR)
         racket/contract)   ; for `contract`

(define-runtime-path fixtures "../types/test/fixtures")
(define (read-fx name) (call-with-input-file (build-path fixtures name) read-json))

;; canonical jsexpr equality — unordered object keys, ordered lists, numeric `=`
;; (same semantics as spec-2025-11-25-test.rkt:45–60, incl. its line-54 number? clause)
(define (jsexpr=? a b)
  (cond
    [(and (hash? a) (hash? b))
     (and (= (hash-count a) (hash-count b))
          (for/and ([(k v) (in-hash a)])
            (and (hash-has-key? b k) (jsexpr=? v (hash-ref b k)))))]
    [(and (list? a) (list? b))
     (and (= (length a) (length b)) (andmap jsexpr=? a b))]
    [(and (number? a) (number? b)) (= a b)]    ; spec-2025-11-25-test.rkt:54
    [else (equal? a b)]))

;; ---- Arm 1: initialize round-trip (extraUnknownKey is dropped on decode) ----
(define init-orig   (read-fx "initialize-request.json"))
(define init-struct (r25:json->initialize-request init-orig))
(define init-rt     (r25:initialize-request->json init-struct))
(define init-expect ; original with the unknown key removed from params
  (hash-set init-orig 'params
            (hash-remove (hash-ref init-orig 'params) 'extraUnknownKey)))
(printf "initialize struct:\n") (pretty-print init-struct)
(printf "initialize re-emit:\n~a\n" (jsexpr->string init-rt))
(printf "initialize round-trip identical (canonical): ~a\n" (jsexpr=? init-expect init-rt))

;; ---- Arm 2: tools/call round-trip ----
(define call-orig   (read-fx "tools-call-request.json"))
(define call-struct (r25:json->call-tool-request call-orig))
(define call-rt     (r25:call-tool-request->json call-struct))
(printf "tools/call struct:\n") (pretty-print call-struct)
(printf "tools/call re-emit:\n~a\n" (jsexpr->string call-rt))
(printf "tools/call round-trip identical (canonical): ~a\n" (jsexpr=? call-orig call-rt))

;; ---- Arm 3: malformed -> JSON-RPC error object ----
;; The decoder does NOT validate (verified: name=42 is ACCEPTED, returns a struct).
;; Rejection comes from applying the CONTRACT, exactly as spec-2025-11-25-test.rkt:219-224 does.
;; There is NO fabricating (error …) guard in this with-handlers: err-obj can ONLY be produced
;; by the (contract …/c …) raise, so the not-fabricated assertion below cannot be fooled.
(define malformed-params (hasheq 'name 42 'arguments (hasheq))) ; name must be string?
(define err-obj
  (with-handlers ([exn:fail? exn->jsonrpc-error-jsexpr])
    (contract r25:call-tool-request-params/c
              (r25:json->call-tool-request-params malformed-params) ; decode succeeds…
              'demo 'demo)                                          ; …contract RAISES here
    ;; If we reach here the contract did NOT raise — fail LOUDLY (do not silently
    ;; encode a fabricated error). This is a real test failure, not an err-obj source.
    (error 's1-demo "contract unexpectedly accepted malformed name — Arm 3 is vacuous, FIX")))
(printf "malformed input: ~a\n" (jsexpr->string malformed-params))
(printf "JSON-RPC error object: ~a\n" (jsexpr->string err-obj))

;; ---- Arm 4 (optional): error-response envelope round-trip ----
(define er-orig   (read-fx "error-response.json"))
(define er-struct (r25:json->jsonrpc-error-response er-orig))
(define er-rt     (r25:jsonrpc-error-response->json er-struct))
(printf "error-response round-trip identical (canonical): ~a\n" (jsexpr=? er-orig er-rt))

(module+ test
  (require rackunit)
  ;; arm 1
  (check-true (jsexpr=? init-expect init-rt) "initialize round-trips (canonical)")
  (check-true (jsexpr=? init-rt (r25:initialize-request->json
                                 (r25:json->initialize-request init-rt)))
              "initialize idempotent")
  ;; arm 2
  (check-true (jsexpr=? call-orig call-rt) "tools/call round-trips (canonical)")
  (check-true (jsexpr=? call-rt (r25:call-tool-request->json
                                 (r25:json->call-tool-request call-rt)))
              "tools/call idempotent")
  ;; arm 3 — the malformed message produced a correct JSON-RPC error object via a REAL
  ;; contract rejection (not a fabricated guard crash).
  (check-true (hash? err-obj) "error object is a JSON object")
  (check-true (exact-integer? (hash-ref err-obj 'code)) "error object has integer code")
  (check-equal? (hash-ref err-obj 'code) INTERNAL-ERROR
                "contract-violation maps to -32603")
  (let ([msg (hash-ref err-obj 'message)])
    (check-true (and (string? msg) (> (string-length msg) 0)) "non-empty message")
    ;; THE non-vacuous assertions: the error came from the CONTRACT, not the guard.
    (check-true  (regexp-match? #rx"contract violation" msg)
                 "error is a genuine contract rejection")
    (check-false (regexp-match? #rx"unexpectedly accepted" msg)
                 "error is NOT the fabricating guard crash"))
  ;; arm 4
  (check-true (jsexpr=? er-orig er-rt) "error-response envelope round-trips (canonical)"))
```

> The code above is a **specification sketch** — but the Arm 3 mechanism in it (decode-then-
> `(contract …/c …)`, with the named identifiers and `name=42` input) was **verified to work
> against the live barrel during this revision**: `r25:json->call-tool-request-params` accepts
> `name=42` and returns a struct, `(contract r25:call-tool-request-params/c … 'demo 'demo)` then
> raises a `string?` contract violation, and `exn->jsonrpc-error-jsexpr` of the caught exn yields
> `code: -32603`, `message:` beginning `"contract violation … expected: string?"`. Do NOT
> substitute a "missing name" (`(hasheq …)`) or a bare-decoder "wrong type" input — **both are
> silently ACCEPTED by the decoder** (verified) and would make Arm 3 vacuous (the exact blocker
> the iteration-001 review caught). The implementer must still re-run to confirm the names resolve
> in the delivered barrel and adjust if item 008 routed them differently, but the rejection
> mechanism itself is confirmed, not a guess. The load-bearing contracts the implemented file MUST
> satisfy are the Acceptance criteria, not this sketch's exact bytes.

### Edge cases the demo + tests must handle (do not leave implicit)

- **Key order / `jsexpr=?` not string compare** — see §The "identically" trap. A string/byte
  compare WILL spuriously fail; canonical `jsexpr=?` is mandatory.
- **`extraUnknownKey` dropped on `initialize` decode** — the demo's arm-1 expected value removes it
  from `params` (`spec-2025-11-25-test.rkt:77–81`). Comparing arm-1's re-emit against the RAW
  fixture WILL fail; compare against the dropped-key `expect`.
- **The malformed arm's rejection comes from the CONTRACT, not the decoder, and not a fabricated
  guard.** The decoder (`r25:json->call-tool-request-params`) does NOT validate — it accepts
  `name=42` and missing-`name` alike (verified). Rejection MUST be driven by `(contract
  r25:call-tool-request-params/c (decode …) 'demo 'demo)`, which raises on the type violation
  (mirroring `spec-2025-11-25-test.rkt:219–224`). The `module+ test` MUST assert the resulting
  error message matches `#rx"contract violation"` and is NOT the fabricating-guard string — without
  that assertion a future regression that stops the contract raising would make the demo encode the
  guard's own crash and pass green (the iteration-001 blocker). Do NOT route the bare decoder
  inside `with-handlers` expecting it to raise — it won't.
- **Fixtures located relative to the demo file, not CWD** — `define-runtime-path` (as
  `spec-2025-11-25-test.rkt:40`) so `racket mcp/core/demo/s1-demo.rkt` works from repo root or any
  other CWD.
- **`module+ test` not loaded on plain `racket <demo>`** — the printed transcript stays free of
  rackunit output on a direct run, while `raco test` still executes the submodule's checks.
- **Demo is OUTSIDE the barrel's import graph** — the demo `require`s the barrel, not vice-versa,
  so it cannot regress the item-008 portability closure; but it DOES pull in `json` and
  `racket/runtime-path` for ITSELF, which is fine (the Portability NFR constrains the CORE's
  transitive closure, not a demo script's).

---

## Dependencies

- **Upstream work items (ALL ✅ — this item is a pure consumer + doc-closeout over them):**
  - **Item 001** (`constants.rkt`, ✅) — `INTERNAL-ERROR` (`-32603`) reached through the barrel for
    the malformed-arm code assertion.
  - **Items 003/004** (`spec-2025-11-25.rkt` / `spec-2026-07-28.rkt`, ✅) — the `r25:json->…` /
    `r25:…->json` request decoders/serializers the demo's round-trip arms call (the
    `2025-11-25`-shaped fixtures match the `r25:` decoders).
  - **Item 005** (`types.rkt`, ✅) — the N1 façade the demo's narration references (architecture
    N1); not directly called for whole-request decode (see §Why the demo decodes via the
    per-revision module).
  - **Items 006/007** (`errors.rkt`, ✅, both halves) — the ENCODE path (`exn->jsonrpc-error-jsexpr`,
    `make-protocol-error`) the malformed arm uses.
  - **Item 008** (`mcp/core/main.rkt` + `mcp/core/types/main.rkt` barrels + portability test, ✅) —
    the SINGLE `require` entry point the demo consumes (architecture §1.3); the portability test
    whose green state box `:60` depends on. Item 008 explicitly DEFERRED the Stage S1 header/
    overview flip and the shared test-deliverable line to THIS item (`008-…md:1164–1181`).
- **Fixtures (✅, reused not invented):** `mcp/core/types/test/fixtures/initialize-request.json`,
  `tools-call-request.json`, `error-response.json` (verified present; TS-SDK-shaped; already
  consumed by `spec-2025-11-25-test.rkt:77–96`).
- **Forward / downstream:** completing this item completes Stage S1 and unblocks **queue-002 /
  Stage S2** (validators/schema/shared utils, which import only S1 — `queue-001.md:15,48`,
  `roadmap.md:30`).
- **Operates on:** in-process JSON parse/serialize (`json` library) + struct field access + the
  error-encode path; reads three fixture files; writes one `.rkt` demo file + edits one doc
  (`progress.md`). No databases, services, network, or subprocess.
- **Tooling/runtime:** Racket ≥ 8.x (this session: 8.18; `raco make`/`raco test` BOTH work, not
  broken — `008-…md:937–954`); `rackunit`, `json`, `racket/runtime-path`, `racket/pretty`. The
  `typescript-sdk/` checkout is NOT needed at run time (the fixtures are already materialized in
  the repo).

---

## Project-specific adaptations (Racket demo script / `module+ test` / canonical JSON / docs)

This template's "Required Services / database / API endpoint" framing does not apply: **this is a
library-demo script + documentation closeout — no external services, no I/O beyond reading three
in-repo fixture files and writing stdout.** Adaptations:

- **`racket <file>` runnable demo + `module+ test` for CI-checkability.** The roadmap Demo line
  (`roadmap.md:99`) asks for "a REPL transcript / script"; the Racket idiom is a `#lang
  racket/base` file whose top-level forms print the transcript and whose `(module+ test …)`
  submodule holds the `rackunit` assertions. `racket <file>` runs the transcript; `raco test
  <file>` runs the checks — so "runs end-to-end" is BOTH demonstrable (printed) and mechanically
  verified (tested), without the demo's checks polluting the printed run. This is strictly better
  than a non-asserting "eyeball the output" script (which could silently rot).
- **Canonical JSON equality, not string compare — the Racket-specific gotcha** (no TS analogue
  worth porting). `write-json`/`jsexpr->string` emit object keys in unspecified order; "identical"
  must mean `jsexpr=?` (unordered keys, ordered arrays), reusing item 003's comparator semantics
  (`spec-2025-11-25-test.rkt:45–60`). See §The "identically" trap.
- **Consuming the curated barrel as a downstream module would** (`(require (file
  "../main.rkt"))`) — the demo is the FIRST real downstream consumer of the item-008 §1.3 barrel,
  validating that the barrel is a usable single entry point (and that the `r25:` prefix routing is
  workable for a consumer, not just for the barrel author).
- **Parity-matrix-as-prose, not a materialized table** — the single most important
  project-specific adaptation for THIS item: the roadmap tracks parity rows as per-stage PROSE
  criteria, not a literal table, so the "parity-matrix update" is concretely the `progress.md`
  "Parity matrix progression" section edit + the already-authored `roadmap.md:97` criterion, NOT a
  new table. See §The parity-matrix update for the full decision + justification.
- **No fixtures invented; no `mcp/examples/` collision.** The demo reuses the three existing
  TS-SDK-shaped fixtures and lives under a NEW `mcp/core/demo/` directory, deliberately distinct
  from the S9/M15 `mcp/examples/` curated-examples deliverable (`progress.md:267–275`).

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None.** No I/O beyond reading three in-repo fixture files and writing stdout; no service
contacted. External artifacts:

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime (this session: 8.18) | compile + run the demo + `module+ test` (`rackunit`, `json`, `racket/runtime-path`, `racket/pretty`) | system install (`racket --version` ≥ 8.0) | n/a |
| Items 001–008 (`mcp/core/types/*.rkt`, `mcp/core/errors.rkt`, `mcp/core/main.rkt`, ✅) | the barrel + modules the demo consumes | produced by items 001–008 | n/a |
| Fixtures `initialize-request.json`, `tools-call-request.json`, `error-response.json` (✅) | the sample messages the demo parses | already in `mcp/core/types/test/fixtures/` | n/a |

No databases, queues, HTTP servers, or network dependencies.

### Environment Configuration

- **Environment variables / secrets / config files:** none.
- **Ports:** none must be free.
- **Working directory:** the demo is CWD-independent (fixtures located via `define-runtime-path`),
  but run `raco`/`racket` commands from the **repo root** (`/home/tlam/racket-mcp`) so the
  `mcp/...` collection + relative requires resolve consistently with the rest of the suite.
- **`raco` status in THIS session — VERIFIED, not assumed (per item 008's correction):** Racket
  v8.18; `raco make` and `raco test` BOTH exit 0 and report pass counts directly (e.g. "908 tests
  passed" — `008-…md:1092–1093`). Do NOT propagate any stale "raco is broken / use `racket <file>`
  workaround" note from very early items (006/007 described a DIFFERENT prior session's
  environment, `008-…md:937–954`). If a future session DOES observe `raco` broken, fall back to
  `racket <file>` direct-run THEN, re-verifying first.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0 (this session: 8.18).
  - `raco test mcp/core/types/ mcp/core/test/` → exit 0, **908 tests passed** (the regression
    baseline this item must not break — `008-…md:1092–1093`).
  - `racket -e '(require (file "mcp/core/main.rkt")) (displayln (procedure?
    r25:json->initialize-request))'` → `#t` (confirms the barrel reaches the decoders under the
    expected `r25:` prefix before writing the demo).
  - `test -f mcp/core/types/test/fixtures/initialize-request.json` &&
    `test -f mcp/core/types/test/fixtures/tools-call-request.json` &&
    `test -f mcp/core/types/test/fixtures/error-response.json` → all present.
  - `test ! -d mcp/examples && test ! -d mcp/core/demo` → confirms the demo dir is genuinely NEW
    and the S9 examples dir does not yet exist (do not collide).

### Manual Validation Checklist

- [ ] **Build/compile:** `raco make mcp/core/demo/s1-demo.rkt` → exit 0.
- [ ] **Demo runs end-to-end (the roadmap's literal claim):** `racket mcp/core/demo/s1-demo.rkt`
      (from repo root) → exit 0; transcript shows, in order: parsed `initialize` struct + re-emit +
      identical-OK; parsed `tools/call` struct + re-emit + identical-OK; malformed input + the
      resulting JSON-RPC error object with its code; (optional) error-response envelope round-trip.
- [ ] **Demo from a DIFFERENT CWD:** `cd /tmp && racket /home/tlam/racket-mcp/mcp/core/demo/s1-demo.rkt`
      → exit 0 (proves `define-runtime-path` fixture loading is CWD-independent, not a CWD-relative
      path bug).
- [ ] **Demo's tests pass:** `raco test mcp/core/demo/s1-demo.rkt` → exit 0, all `module+ test`
      checks pass.
- [ ] **Round-trip assertions are NON-VACUOUS:** temporarily replace `r25:initialize-request->json`
      with a function returning a deliberately wrong jsexpr (e.g. `(lambda (s) (hasheq))`); re-run
      `raco test mcp/core/demo/s1-demo.rkt`; confirm the arm-1 `check-true` FAILS; revert; confirm
      green. (Mirrors item 008's drift-check discipline — prove the check can fail.)
- [ ] **Malformed arm genuinely rejects (the iteration-001 blocker):** confirm the `(contract
      r25:call-tool-request-params/c …)` call (NOT the bare decoder) is what raises — the decoder
      accepts `name=42` and returns a struct, so without the `(contract …/c …)` wrap nothing
      raises. Confirm `err-obj`'s `message` matches `#rx"contract violation"` and does NOT match
      `#rx"unexpectedly accepted"`. **Prove the non-vacuous assertion can FAIL:** temporarily
      replace the `(contract …/c …)` line with the bare decoded value (so nothing raises and the
      fabricating `(error …)` fires); re-run `raco test mcp/core/demo/s1-demo.rkt`; confirm the
      `#rx"contract violation"` / `#rx"unexpectedly accepted"` checks FAIL; revert; confirm green.
      Record the malformed input + resulting code in Validation Results.
- [ ] **Full-suite regression:** `raco test mcp/core/types/ mcp/core/test/ mcp/core/demo/` → exit
      0, `<inherited baseline — re-run to confirm; item 008 recorded 908>` + the demo's new checks,
      0 regressions.
- [ ] **No new library types in the demo:** `grep -cE '\(struct |define-struct|exn:fail:mcp'
      mcp/core/demo/s1-demo.rkt` → `0` (the demo declares no protocol structs/errors).
- [ ] **No `mcp/examples/` collision:** `test ! -d mcp/examples` still holds; the demo is under
      `mcp/core/demo/`.
- [ ] **progress.md acceptance boxes checked correctly:** boxes `:56`,`:58`,`:59`,`:60`,`:61`,`:62`
      flipped `[ ]`→`[x]`; `:57` unchanged; no icon reverted. Re-confirm each box's evidence green
      BEFORE checking (esp. re-run item-008 portability test before `:60`).
- [ ] **Stage S1 status flipped:** header `progress.md:41` 📋→✅; overview row `progress.md:27`
      📋→✅; shared test line `progress.md:53` 🚧→✅.
- [ ] **Parity-matrix section updated:** `progress.md:336` "no rows yet (no source)" replaced with
      `core/types/*`/`errors/*` `partial` + conformance-deferred-to-S9 text; NO new table added to
      `roadmap.md`.
- [ ] **G1 NOT over-claimed:** the "Vision goal coverage" G1 row (`progress.md:298`) is NOT marked
      ✅ (S1 is partial G1; full is S9). Any touch is a conservative annotation, not a ✅.
- [ ] **Health checks pass:** N/A.

### Expected Outcomes

- The demo file `mcp/core/demo/s1-demo.rkt` exists, compiles, runs end-to-end via `racket`, and
  its `module+ test` adds a small number of `rackunit` checks (≈ 7–9: two round-trip + two
  idempotence + three-to-four malformed-arm/error-envelope assertions).
- `raco test mcp/core/types/ mcp/core/test/ mcp/core/demo/` → `<inherited baseline, re-run to
  confirm — item 008 recorded 908>` + the demo's new checks, all passing, exit 0.
- `docs/aide/progress.md` shows Stage S1 fully closed out: header + overview-row + test-line ✅,
  all S1 acceptance boxes `[x]`, parity-matrix section recording `core/types/*` / `errors/*` as
  `partial`.
- No new library code, no `mcp/examples/`, no reverted icons, no over-claimed G1.

### Validation Results

```markdown
## Validation Results (completed during implementation — Racket 8.18, repo root /home/tlam/racket-mcp)
- [ ] Service started: N/A (demo script + doc closeout, no services)
- [ ] Build verified: `raco make mcp/core/demo/s1-demo.rkt` → exit 0
- [ ] Demo end-to-end: `racket mcp/core/demo/s1-demo.rkt` → exit 0; transcript pasted below
- [ ] Demo CWD-independent: run from /tmp → exit 0
- [ ] Demo tests: `raco test mcp/core/demo/s1-demo.rkt` → exit 0, <N> checks passed
- [ ] Non-vacuous round-trip: broke a serializer → arm-1 check FAILED as expected; reverted → green
- [ ] Malformed arm rejects via CONTRACT (not decoder, not guard): input = <the malformed jsexpr used, e.g. name=42>; `(contract …/c …)` raised contract violation; error code = <-32603 or re-wrapped>; message matched #rx"contract violation", did NOT match #rx"unexpectedly accepted"
- [ ] Full regression: `raco test mcp/core/types/ mcp/core/test/ mcp/core/demo/` → exit 0, <total to confirm> passed (<inherited, item 008 recorded 908> + <new>)
- [ ] No new types in demo: `grep -cE '\(struct |define-struct|exn:fail:mcp' …` → 0
- [ ] No mcp/examples collision: `test ! -d mcp/examples` → holds
- [ ] progress.md boxes: :56,:58,:59,:60,:61,:62 → [x]; :57 unchanged; no revert
- [ ] Stage S1 status: header/overview-row/test-line → ✅
- [ ] Parity-matrix section: updated to core/types/* + errors/* `partial`; no new roadmap table
- [ ] G1 not over-claimed: G1 row not ✅
- [ ] Database tables verified: N/A
- [ ] API endpoints verified: N/A
- [ ] Screenshots captured: N/A (no UI; transcript pasted instead)
```

### Test commands run and results

All from repo root `/home/tlam/racket-mcp`, Racket v8.18 [cs]. **The `→` lines below are a TEMPLATE
to fill at implementation — re-run each command and record the REAL output. The pass counts shown
as `<to confirm>` are placeholders; item 008 recorded 908 inherited, but re-run rather than copy.**

```
$ raco test mcp/core/types/ mcp/core/test/                 # baseline regression
  → <to confirm — item 008 recorded 908> tests passed, exit 0   (inherited from items 001–008)

$ racket -e '(require (file "mcp/core/main.rkt")) (displayln (procedure? r25:json->initialize-request))'
  → #t   (barrel reaches the r25:-prefixed decoder)

$ raco make mcp/core/demo/s1-demo.rkt                      # the new demo
  → exit 0

$ racket mcp/core/demo/s1-demo.rkt                         # the demo transcript
  → exit 0   (transcript: parse+print+re-emit initialize & tools/call; malformed→error object)

$ raco test mcp/core/demo/s1-demo.rkt                      # the demo's module+ test
  → <to confirm> tests passed, exit 0

$ raco test mcp/core/types/ mcp/core/test/ mcp/core/demo/  # whole tree incl. demo
  → <to confirm> tests passed, exit 0   (<inherited, item 008 recorded 908>, 0 regressed; +<new> from the demo)
```

---

## Decisions & Trade-offs

To be updated during implementation.

(At minimum, record on delivery: (1) the malformed-arm rejection mechanism — confirm it is the
`(contract r25:call-tool-request-params/c (r25:json->call-tool-request-params (hasheq 'name 42 …))
'demo 'demo)` route (NOT the bare decoder, which does not self-reject), the exact malformed input,
the resulting code (plain `-32603`, or a re-wrapped `make-protocol-error` code such as `-32602` if
shape B was layered on top), and that the not-fabricated assertions (`#rx"contract violation"`
present, `#rx"unexpectedly accepted"` absent) are in the `module+ test`; (2) whether arm 4
(error-response envelope round-trip) was included; (3) the final `raco test` command that covers
the demo's location AND the REAL inherited + new pass counts (do not copy the template's
placeholders); (4) the demo's final location if it differed from `mcp/core/demo/s1-demo.rkt`;
(5) confirmation that `r25:json->initialize-request`, `r25:json->call-tool-request`,
`r25:json->call-tool-request-params`, and `r25:call-tool-request-params/c` all resolved through the
item-008 barrel as expected (all four verified reachable during this spec's iteration-002
revision), or the actual names used if item 008 routed them differently; (6) the exact replacement
text used for the `progress.md` "Parity matrix progression" section; (7) confirmation that NO new
table was added to `roadmap.md` and that G1 was NOT over-claimed.)

---

## Completion Reminder

On completion, the implementer MUST:

1. **Land the demo + its `module+ test`** at `mcp/core/demo/s1-demo.rkt` (or the recorded
   alternative), verified to run end-to-end via `racket` AND pass under `raco test`, with the
   round-trip arms using canonical `jsexpr=?` (NOT string compare) and the malformed arm producing
   a real JSON-RPC error object via the `errors.rkt` ENCODE path.
2. **Update `docs/aide/progress.md` — acceptance boxes.** Flip boxes `:56`, `:58`, `:59`, `:60`,
   `:61`, `:62` `[ ]` → `[x]` per §The progress.md acceptance-box mapping, ONLY after re-confirming
   each box's evidence is green. Leave `:57` untouched. Never uncheck a checked box or revert an
   icon (`progress.md:19`).
3. **Flip Stage S1 to ✅ — the closeout item 008 deferred to THIS item** (`008-…md:1164–1181`):
   the Stage S1 header (`progress.md:41`), the stage-overview S1 row (`progress.md:27`), and the
   shared test-deliverable line (`progress.md:53`, 🚧 → ✅).
4. **Record the parity-matrix update** in `progress.md`'s "## Parity matrix progression" section
   (`progress.md:334–336`): replace "no rows yet (no source). 📋" with `core/types/*` and
   `errors/*` marked `partial` (structs/errors exist; full conformance deferred to S9), per §The
   parity-matrix update. **Do NOT add a new materialized table to `roadmap.md`** — the roadmap's
   per-stage prose criteria (`roadmap.md:97`) + this progress-section edit ARE the S1 parity matrix
   of record.
5. **Be conservative on cross-stage goal/NFR tables.** Do NOT mark G1 (`progress.md:298`) ✅ — S1
   only partially satisfies it (full wire-parity is S9-certified). Any touch to G1 / Portability /
   MCP-spec-compat NFR rows is a conservative partial-progress annotation at most.
6. **Do NOT create `mcp/examples/`** (S9 / M15 — `progress.md:267–275`); the demo lives under
   `mcp/core/demo/`. Do NOT re-open or re-grade any already-✅ item-001–008 deliverable — this item
   adds one demo file + doc edits only.
7. **Confirm Stage S1 is genuinely complete:** with items 001–009 all delivered, Stage S1's
   roadmap `### Deliverables` list (`roadmap.md:78–86`) — including the demo (`roadmap.md:99`) — is
   fully satisfied, and queue-002 / Stage S2 is unblocked (`queue-001.md:15,48`). This is the LAST
   item in queue-001.
