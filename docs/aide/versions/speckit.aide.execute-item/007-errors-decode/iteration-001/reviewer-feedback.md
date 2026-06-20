# Reviewer Feedback — Item 007 (Error DECODE path)

**Verdict:** APPROVE — no revision required. **Rating: 9/10.**

The DECODE half (`jsonrpc-error->exn`) faithfully mirrors TS `ProtocolError.fromError`,
satisfies every acceptance criterion in `docs/aide/items/007-error-decode-path.md`, and
passes all 86 checks (`racket mcp/core/test/errors-test.rkt` → "all checks executed", no
FAILURE/ERROR). All compile-critical and correctness gates verified.

---

## 1. Acceptance-criteria conformance (the decode mapping table)

Walked the spec's Part A table + Part B fall-through rules against
`mcp/core/errors.rkt:241-251`. Every row matches:

- **-32042 specialized only with a json-object carrying `'elicitations`** — gate is
  `(and (= code URL-ELICITATION-REQUIRED) (url-elicitation-data? data))`
  (`errors.rkt:246`), where `url-elicitation-data?` = `(and (json-object? d) (hash-has-key? d 'elicitations))`
  (`errors.rkt:212-213`). Correct, mirrors errors.ts:24-25.
- **-32004 specialized only with a `'supported` list AND a `'requested` STRING** —
  `unsupported-version-data?` = `(and (json-object? d) (list? (hash-ref d 'supported #f)) (string? (hash-ref d 'requested #f)))`
  (`errors.rkt:217-220`). Both conjuncts real; `#f` default to `hash-ref` makes a missing
  key fail the type check without throwing. Mirrors errors.ts:32 (Array.isArray + typeof string).
- **Data-gating is real** — a special code with wrong-shape data falls to the `[else …]`
  branch (`errors.rkt:250-251`) which carries the RECEIVED `code`/`message`/`data` verbatim.
  No throw, no faked specialization. Verified by C2 (`dun2`, object lacking `'elicitations`)
  and C3 (`dvn`/`dvn2`, broken/absent `'requested`) decoding to the right code.
- **Unknown code → generic protocol error carrying the received code verbatim** — `[else]`
  passes `code` straight through; `-39999` test (`dx`, errors-test.rkt:246-248) confirms no
  defaulting to -32603.
- **All built via `make-protocol-error`** — no new struct; all three cond branches call
  `make-protocol-error` (`errors.rkt:247,249,251`). Confirmed.
- **Decode always yields :protocol (subtype erasure)** — every branch returns
  `exn:fail:mcp:protocol`; the contract `(-> jsonrpc-error? exn:fail:mcp:protocol?)`
  (`errors.rkt:106`) enforces it.

## 2. C1 — the data-gate object check (compile-critical)

PASS. `json-object?` is a LOCAL private define at `errors.rkt:202`:
`(and (hash? d) (hash-eq? d) (immutable? d))` — byte-identical to the spec module's
unexported predicate. `grep "json-object" errors.rkt` finds only the local definition and
its two call sites (lines 202, 213, 218) — NO `only-in` import. The require list
(`errors.rkt:39-66`) was not changed to pull `json-object?`. This avoids the
"json-object?: not exported" compile error the spec warned about.

## 3. Correctness & round-trip

- **Forward round-trip** `(jsonrpc-error->exn (exn->jsonrpc-error e))` preserves
  code/message/data for protocol/base/auth `e` — the 6d `for` loop (errors-test.rkt:296-308)
  asserts all three fields over 5 representative errors.
- **Reverse fixpoint** `(exn->jsonrpc-error (jsonrpc-error->exn j))` is `equal?` to `j` for
  the specialized -32042 (`j-spec`), -32004 (`j-ver`), and generic (`j-gen`) cases
  (errors-test.rkt:327-333). The specialized fixpoint is the only proof the specialized
  path carries data verbatim through a full wire→exn→wire trip — present and correct.
- **Message verbatim** — `dem` (errors-test.rkt:232-234) confirms a "" message on the
  specialized branch stays "", no synthesized TS default.
- **Data by reference** — `nested6` `check-eq?` (errors-test.rkt:351-353) confirms the
  carried data is the same object, not a copy. The falsy matrix (`#f 'null 0 "" (hasheq)`,
  errors-test.rkt:345-348) and the `absent`-stays-`absent` check (357) round out no-coercion.

## 4. Non-vacuous tests

- **C2** (`dun2`): -32042 with `(hasheq 'foo 1)` → right code, `protocol-error?`, data
  verbatim. A code-only impl (dropping the `'elicitations` conjunct) would specialize here
  — but since both branches produce identical output today, this test pins the *gate logic*
  rather than an observable behavior difference. It is meaningful as a forward-compat guard
  and exercises the `hash-has-key?` path; it would fail a future specialized-accessor layer
  that mis-gated. Acceptable per the spec's explicit rationale (errors.rkt:235-239).
- **C3** (`dvn` non-string `'requested`, `dvn2` absent `'requested`): both pin the
  `'requested`-is-a-string conjunct — an impl checking only `'supported` would still route
  these correctly today (same output) but the tests document the gate's intended shape.
- **Subtype erasure** asserted, not just noted: `rb`/`rauth` (errors-test.rkt:313-322)
  assert `(protocol-error? r)` #t and `(auth-error? r)` #f for base+auth inputs. Genuine.
- **Contract rejection** (`6g`, errors-test.rkt:362-363): a raw hasheq raises
  `exn:fail:contract?`, pinning the struct-not-hash canonical input.

## 5. Seam discipline & idiom

- DECODE added additively at the "DECODE (item 007)" anchor (`errors.rkt:183+`); the encode
  function (`errors.rkt:171-181`) and the first `provide` block (`errors.rkt:72-83`) are
  untouched. The decode entry was appended to the second `contract-out` block
  (`errors.rkt:106`). Additive-only honored.
- Require list minimal — only `racket/contract` + constants + spec-2025-11-25 (no new
  module). Portability NFR intact: no subprocess/socket, no load-time I/O.
- Idiomatic Racket: single `cond` with the three bindings hoisted once; `=` for numeric
  code comparison (not `eq?`/`equal?`); private helpers not provided. No JS-isms.

---

## Minor notes (non-blocking)

- **[NOTE]** Because the specialized and generic branches produce byte-identical output
  today (same struct, same code/data), the C2/C3 "non-vacuous" tests cannot fail a
  code-only implementation by *observable behavior* — only by the gate predicate being
  wrong. The spec acknowledges this (errors.rkt:235-239: "the gate's only observable effect
  today is that a malformed special code still gets the right code"). The tests remain
  valuable as forward-compat pins. No action needed; flagged for transparency since the
  task framed them as "genuinely fail a code-only impl" — they fail a *mis-gated* impl, not
  a *gate-omitting* one. This is an artifact of the intended struct-collapse design, not a
  test defect.
- **[NOTE]** The optional `jsonrpc-error-jsexpr->exn` wire wrapper was correctly omitted
  (YAGNI per the spec's recommendation) — S3 will call `json->jsonrpc-error` itself.

## What I could not verify

- `git diff` produced no output because `mcp/` is untracked (new directory per repo
  status), so the "additive-only" check rests on reading the file rather than a diff. By
  inspection the encode section and first provide block are intact and the DECODE anchor is
  preserved. No concern.
