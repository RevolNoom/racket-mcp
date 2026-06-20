# Reviewer Feedback — Item 006 (Error hierarchy + ENCODE path), iteration 001

**Files reviewed**
- `mcp/core/errors.rkt` (186 lines)
- `mcp/core/test/errors-test.rkt` (200 lines)
- additive change: `jsexpr-value?` added to the `provide` of `mcp/core/types/spec-2025-11-25.rkt`

**Verdict:** Accept. `overall_rating = 9/10`, `needs_revision = false`.

The implementation is a faithful, idiomatic, and complete realization of the ENCODE half of
the M2 error seam. Every acceptance criterion is met; every subtle correctness property the
spec called out (falsy-data carriage, reference identity, absent-vs-null, contract rejection,
the -32603 fallback) was verified at runtime, not just asserted in tests. The single
out-of-scope edit (`jsexpr-value?` export) is the correct DRY choice and is purely additive.
This is high-quality work; the issues below are NOTE/MINOR only.

---

## 1. Acceptance-criteria conformance

I walked every acceptance bullet and the Part A/B/C build-contract tables. All pass.

### Hierarchy (Part A) — PASS
- `(struct exn:fail:mcp exn:fail (code data) #:transparent)` + the two empty `#:transparent`
  sub-structs are exactly as specified (`errors.rkt:109-111`). Field layout is the
  load-bearing `(message marks code data)` order; the friendly `make-*` constructors hide it
  (`errors.rkt:133-143`).
- Constructors carry `code`/`message` and default `marks` to `(current-continuation-marks)`
  (`errors.rkt:134,138,142`). Verified: `exn-message` round-trips, the value is `raise`-able
  and catchable by an `mcp-error?` handler (`errors-test.rkt:34,93`), and the
  continuation-marks field is a populated `continuation-mark-set?` (`errors-test.rkt:45`).
- Each subtype constructs with its stable code, asserted by `=` against the imported
  `constants.rkt` binding — never a literal (`errors-test.rkt:28-32,42`).

### Predicate discrimination matrix — PASS
The full 5×4 matrix (`errors-test.rkt:60-90`) covers base / protocol / auth / synthetic
generic / caught-`(car '())` against `exn:fail?`/`mcp-error?`/`protocol-error?`/`auth-error?`.
Boundary cases all correct:
- `(protocol-error? b)` and `(auth-error? b)` are `#f` (base is not a subtype) — 69-70.
- `(auth-error? p)` `#f` and `(protocol-error? a)` `#f` (siblings don't cross-identify) — 75,79.
- A generic `exn:fail` (synthetic and a real caught `(car '())`) satisfies none of the mcp
  predicates — 83-90. This is the critical "plain `exn:fail` is NOT `mcp-error?`" boundary.

### Encode mapping (Part B) — PASS
The encoder is the prescribed single `cond` (`errors.rkt:161-166`): `(mcp-error? e)` → copy
own code/message/data; else → `(jsonrpc-error INTERNAL-ERROR (exn-message e) absent)`.
- mcp subtype → its own code/message, absent data stays absent (`errors-test.rkt:99-103`).
- data preserved through encode (`errors-test.rkt:106-107`).
- **The -32603 fallback is exercised twice** — synthetic `make-exn:fail` AND a real thrown
  `(vector-ref (vector) 0)` (`errors-test.rkt:110-117`). This is the hard requirement and it
  is unambiguously covered.
- Both non-base subtypes (protocol + auth) are encoded with structured data through the single
  `(mcp-error? e)` branch (`errors-test.rkt:125-133`) — directly proving the one branch
  handles all three subtypes.

### Wire shape + absent-vs-null — PASS
`(jsonrpc-error->json (exn->jsonrpc-error …))` yields a symbol-keyed `hasheq` with `'code`
(exact-integer) and `'message` (string); `'data` present iff the exn had data
(`errors-test.rkt:142-159`). Absent data is omitted (`check-false (hash-has-key? w 'data)`,
line 147) — NOT `'data: 'null`. The encoded object composes into a full envelope that
satisfies `is-jsonrpc-error?` (`errors-test.rkt:164`), proving encode↔guard parity. I
confirmed `is-jsonrpc-error?` calls `only-keys? v '(jsonrpc id error)` (`guards.rkt:133`), so
the `(hasheq 'jsonrpc "2.0" 'id 1 'error w)` test envelope is a genuine, non-vacuous check.

### Codes imported, not re-literaled — PASS
`grep -nE '\-32[0-9]{3}|\-3200[0-9]' mcp/core/errors.rkt | grep -v ';;'` returns nothing —
every numeric code in code flows from `constants.rkt`. I cross-checked all nine codes against
`constants.rkt:45-55` and they match the authoritative `enums.ts` numbers
(INTERNAL -32603, PARSE -32700, INVALID-REQUEST -32600, METHOD-NOT-FOUND -32601,
INVALID-PARAMS -32602, RESOURCE-NOT-FOUND -32002, MISSING-REQUIRED-CLIENT-CAPABILITY -32003,
UNSUPPORTED-PROTOCOL-VERSION -32004, URL-ELICITATION-REQUIRED -32042).

### Portability NFR — PASS
Require list is exactly `racket/contract` + `types/constants.rkt` + `types/spec-2025-11-25.rkt`
(`errors.rkt:39-62`). No subprocess/socket module, no load-time I/O. Module loads in isolation;
spec module and the `types.rkt` façade still load after the additive export.

---

## 2. Correctness & subtle properties (runtime-verified)

I did not take the tests on faith — I re-derived the load-bearing properties in a fresh REPL:

- **Falsy-data carriage (no truthiness-presence bug):** `#f`, `'null`, `0`, `""` each appear on
  the wire with the exact value. This is correct *because* the spec serializer's `put` helper
  (`spec-2025-11-25.rkt:78-82`) omits via `present?` = `(not (eq? v absent))`, NOT via
  truthiness. The encoder never does its own truthiness test — it uses `(mcp-error? e)` and
  passes `(mcp-error-data e)` straight through. So the only value that is ever omitted is the
  `eq?`-identical `absent` sentinel. Correct and robust.
- **Data copied by reference, not flattened:** `(eq? wire-data original-nested-hash)` is `#t`.
  The encoder threads the value unchanged; `jsonrpc-error->json`'s `put` applies the identity
  conv. No deep copy, no inspection. (`errors-test.rkt:188` asserts this with `check-eq?`.)
- **`absent` is the same `eq?` binding everywhere:** `errors.rkt` imports `absent`/`absent?`
  from the spec module (`errors.rkt:61`) rather than redefining the uninterned symbol — so the
  serializer's `(absent? v)` test recognizes the encoder's absent. This was the one place a
  silent "data: null leaks" bug could hide, and it is avoided correctly by sharing the binding.
- **`exn-message` totality on the fallback path:** `exn-message` is total over `exn?`, and the
  contract is `(-> exn? …)`, so the fallback message is always a string. No guard needed; the
  implementer documented this (`errors.rkt:156-159`). Correct.
- **Contracts reject bad input:** `(make-mcp-error "x" "m")` and `(make-protocol-error c 5)`
  both raise `exn:fail:contract?`. The `->* (exact-integer? string?) …` contracts
  (`errors.rkt:84-92`) are real, not decorative. Tested at `errors-test.rkt:51-53`.
- **Empty message is preserved** (`""`, not omitted/coerced) — `errors-test.rkt:135-137`.
- **Negative/exact code preserved verbatim** — `errors-test.rkt:42`.

---

## 3. 007 decode seam — READY

- The "DECODE (item 007)" anchor is present and detailed (`errors.rkt:173-186`), with the
  exact decode signatures and the -32042/-32004 mapping spelled out for 007 to follow.
- The `provide` is split into two blocks (`errors.rkt:68-79` struct-out/predicates/accessors,
  and `81-96` contract-out for constructors+encoders). 007 can append a third `provide` block
  for decode bindings without editing 006's exports. Append-only is genuinely satisfied.
- The hierarchy is sufficient for 007 with NO new struct: Part 5 of the test
  (`errors-test.rkt:194-198`) constructs a typed `-32042` URL-elicitation error via
  `make-protocol-error URL-ELICITATION-REQUIRED … (hasheq 'elicitations '())` and confirms
  `protocol-error?` + the code. The same path covers -32004. This is a real anti-vacuous check
  of the 007 seam.
- The `require` list already pulls in everything 007 needs (the codes + the `jsonrpc-error`
  shape + `absent`), so 007 adds nothing new to the requires.

---

## 4. The additive export deviation — ACCEPTABLE (correct call)

Adding `jsexpr-value?` to `spec-2025-11-25.rkt`'s `provide` (line 110, with an explanatory
comment) is the right decision, not a concern:
- It is **purely additive** — the predicate was already defined (`spec-2025-11-25.rkt:67`), only
  not exported. No behavior of the spec module changed; its test passes and the module + façade
  still load (verified).
- It is the **DRY choice**: `errors.rkt`'s `mcp-data/c` (`errors.rkt:123`) now reuses the EXACT
  predicate behind `jsonrpc-error/c` (`spec-2025-11-25.rkt:326-327`). A locally redefined value
  predicate would be a parity hazard — exactly the kind of duplication item 003 warns against.
  Reusing the single source of truth means the constructor's `data` contract can never drift
  from what the serializer/contract accept.
- It keeps `errors.rkt` from importing or re-implementing a jsexpr validator, preserving the
  minimal-require posture.

This is a documented, reasonable deviation that strengthens parity. No revision warranted.

---

## 5. Idiomatic Racket + portability — PASS

- Curated `(provide …)` with `(struct-out …)` — no `all-defined-out` (`errors.rkt:68-96`).
- Friendly predicates/accessors are clean re-bindings of the auto-generated struct bindings
  (`errors.rkt:114-118`) — idiomatic, zero overhead.
- `contract-out` on the constructors and encoders; raw `struct-out` on the structs — matches
  item 003's established convention (raw structs + contracted functions).
- No JS-isms; native `struct`-on-`exn:fail` super-typing, native `raise`/`with-handlers`,
  kebab-case naming, the `exn:fail:…` colon convention used only where Racket itself uses it.
- Comment density and Decisions-discipline match the sibling 003/005 bar.

---

## Test execution (re-run by reviewer)

- `racket mcp/core/test/errors-test.rkt` → exit 0, no FAILURE lines, prints
  "errors-test.rkt: all checks executed".
- `racket -e '(require (file "mcp/core/errors.rkt"))'` → loads clean (only the documented
  harmless `.bash_env: Permission denied` stderr).
- Regression: spec-2025-11-25.rkt and types.rkt façade load clean after the additive export.
- Independent REPL re-derivation of falsy-carriage, reference-identity, absent-omission, and
  contract-rejection — all confirmed (see §2).

---

## Minor / NOTE-level observations (non-blocking)

- **[NOTE]** `exn->jsonrpc-error-jsexpr` is typed `(-> exn? hash?)` (`errors.rkt:96`). The
  serializer always returns a symbol-keyed `hasheq`; `hash?` is a slightly looser return
  contract than the value actually produced (a `hash-eq?`/`immutable?` post-condition would be
  tighter). Harmless — the test independently asserts `hash-eq?` on the result
  (`errors-test.rkt:143`) — but if you want the contract to fully document the shape, narrowing
  to `(and/c hash? hash-eq? immutable?)` or an `is-jsonrpc-error?`-style predicate would do it.
  Not required for acceptance.
- **[NOTE]** The encoder intentionally maps any non-mcp `exn?` (including, if ever handed one,
  `exn:break`) to -32603. The implementer documented that S3 is expected to let breaks
  propagate so they should never reach the encoder (`errors.rkt:156-159`). This is the right
  call and is well-documented; flagging only so 007/S3 reviewers keep the invariant in mind
  (the encoder is not the place that decides break-propagation policy).
- **[NOTE]** `make-mcp-error` exposes `#:marks` on the public surface while the two subtype
  constructors also accept it. This is consistent and harmless (keeps errors stack-bearing);
  worth a one-line provide-comment noting `#:marks` is part of all three signatures if a future
  caller relies on it, but the contract already documents it.

None of these affect correctness, acceptance, or the 007 seam.
