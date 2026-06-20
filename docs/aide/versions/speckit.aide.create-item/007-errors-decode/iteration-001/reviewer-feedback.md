# Reviewer feedback — Item 007: Error DECODE path (JSON-RPC → typed error)

**Role:** Reviewer (testing strategy, prerequisites, edge cases).
**Spec:** `docs/aide/versions/speckit.aide.create-item/007-errors-decode/iteration-001/item.md`
**Verdict:** 8/10 — strong, near-buildable. ONE substantive blocker (a recommended import that
does not exist as an export), plus a handful of test-coverage gaps worth closing. `needs_revision: true`
solely because the spec STEERS the implementer toward a require that will fail to compile.

---

## Verification of the spec's factual claims (all checked against source)

| Claim in spec | Source | Verdict |
|---|---|---|
| `URL-ELICITATION-REQUIRED` = -32042, `UNSUPPORTED-PROTOCOL-VERSION` = -32004 | `constants.rkt:54-55` | ✅ correct |
| TS dispatch is `code === X && data` THEN nested shape check; default `new ProtocolError(code,message,data)`; subclasses thread received `message` | `errors.ts:21-39, 47, 68` | ✅ correct — the mapping table + data-gate mirror it exactly |
| `jsonrpc-error` struct = `(code message data) #:transparent` | `spec-2025-11-25.rkt:325` | ✅ correct |
| `(struct-out jsonrpc-error)` provided (gives the test the `jsonrpc-error` CONSTRUCTOR + `jsonrpc-error-message`) | `spec-2025-11-25.rkt:119` | ✅ correct — test imports are satisfiable |
| `json->jsonrpc-error-response` yields a `jsonrpc-error` struct (S3 call-site rationale) | `spec-2025-11-25.rkt:338-342` | ✅ correct |
| DECODE anchor present at errors.rkt bottom; `make-protocol-error`/predicates/accessors exist | `errors.rkt:137, 114-118, 173-186` | ✅ correct |
| Façade builders make `jsonrpc-error-response` WIRE MESSAGES, not exns — different role, no collision | `spec-2025-11-25.rkt:1859` (and the façade re-exports) | ✅ reasoning holds; no M2→M1-façade dependency needed |
| Round-trip erases subtype (encode → flat `jsonrpc-error`, decode → always `:protocol`) | `errors.rkt:161-166` | ✅ correct; the documented asymmetry is real and intended |

The parity reasoning, the façade reconciliation, and the round-trip-scope decisions are all sound.

---

## Missing Coverage (CRITICAL)

### C1. The RECOMMENDED `json-object?` import does NOT exist as an export — will not compile.
The spec's Decisions "`json-object?` import (OPEN)" **recommends option (a): import `json-object?`
from `spec-2025-11-25.rkt` via one `only-in` entry.** I verified the module:
`json-object?` is defined at `spec-2025-11-25.rkt:51` UNDER the comment at line 47
("Internal wire helpers (NOT provided, except `absent`)") and **it is absent from the `provide`
block (lines 106-320 checked).** An `(only-in "types/spec-2025-11-25.rkt" json-object?)` will raise
a compile-time "not exported" error.

This is the one claim in the spec that would actively MISLEAD the implementer into a broken build.
Three fixes, in order of preference:
1. **Re-export `json-object?` from spec-2025-11-25.rkt** (add it to the provide block) and keep
   option (a). This is the cleanest — reuses the exact M1 object notion the struct's own
   `jsonrpc-error/c` validates against. But it edits M1, which the item explicitly says it must NOT
   ("Leave the sibling `core/types/*` deliverables ... at their current status"). So this needs the
   lead's blessing or it belongs to item 003/005's owner.
2. **Switch the recommendation to option (b)** — a local `(and (hash? d) (hash-eq? d) (immutable? d))`
   check (this exactly reproduces the body of `json-object?` at `spec-2025-11-25.rkt:51-52`, so it is
   not a "parity hazard" at all — it is byte-identical logic). **This is the right default given the
   no-M1-edit constraint.** The spec should DEMOTE option (a) and PROMOTE (b), inverting its current
   recommendation.
3. Import a DIFFERENT already-exported predicate that implies object-ness — none fits cleanly, skip.

**Action:** the spec must stop recommending (a) as written. Either authorize the M1 re-export
explicitly, or make (b) the recommendation. As written, an implementer who follows the
RECOMMENDED path hits a compile error.

### C2. No test that the data-gate REJECTS a well-typed-but-wrong-shape `-32042` payload.
6c covers `-32042` with absent data and `-32004` with `'supported` = a string. But it never tests
`-32042` with PRESENT data that is a `json-object?` LACKING `'elicitations` (e.g.
`(hasheq 'somethingelse 1)`) — the exact TS `if (errorData.elicitations)` miss at `errors.ts:25`.
Today both branches build the same struct so the observable code is identical, BUT this is the
load-bearing gate the spec spends two paragraphs justifying for forward-compat; an implementer
could write `(= code URL-ELICITATION-REQUIRED)` alone (dropping the `'elicitations` check) and ALL
listed 6c tests would still pass. Add: `-32042` with `(hasheq 'foo 1)` (object, no `elicitations`)
→ still a `-32042` protocol error, no throw. This is the assertion that actually pins the gate's
`elicitations`-key check rather than letting code-only matching pass vacuously.

### C3. `-32004` "well-shaped" positive-path gate test is asymmetric with `-32042`.
6a asserts `-32042` with good data and 6a asserts `-32004` with good data, but the gate for
`-32004` requires `'supported` a `list?` AND `'requested` a `string?` (two conjuncts). The only
malformed `-32004` test (6c) breaks `'supported`. There is no test that breaks `'requested`
(e.g. `'requested` missing, or a non-string). Add a `-32004` with `'supported` a list but
`'requested` absent/numeric → generic fall-through. Otherwise an implementer who checks only
`'supported` (dropping the `'requested` string check) passes every listed test.

---

## Missing Coverage (SUGGESTED)

### S1. The reverse-fixpoint (6d second bullet) needs a SPECIAL-code-with-good-data case spelled out.
6d says "for a `j` built with each special + a generic code." Make it explicit that
`j = (jsonrpc-error URL-ELICITATION-REQUIRED "u" (hasheq 'elicitations '()))` →
`(exn->jsonrpc-error (jsonrpc-error->exn j))` is `equal?` to `j`. This is the only test that
proves the specialized branch carries data verbatim THROUGH a full round-trip (the forward 6d uses
`make-protocol-error` directly, not the decode of a wire `j`). Worth pinning since data-verbatim is
a named acceptance criterion.

### S2. Round-trip list omits an AUTH `e`, but the asymmetry note references one.
Acceptance criterion "ROUND-TRIP INVARIANT" parenthetically says "for a base/auth `e` ... DECODE
always yields a `protocol`-typed error," but the 6d concrete list (item.md:341-344) contains NO
`make-auth-error`. Either add `(make-auth-error MISSING-REQUIRED-CLIENT-CAPABILITY "x" (hasheq 'capability "roots"))`
to the 6d list (so the "auth subtype erased to protocol on round-trip" claim is actually exercised
— code/message/data preserved, `(protocol-error? r)` #t, `(auth-error? r)` #f), or drop "auth" from
the prose. Currently the prose over-claims relative to the test. Adding the case is better — it is
the cleanest demonstration of the intended subtype-erasure asymmetry.

### S3. `make-mcp-error` (the BASE, not protocol) round-trip: assert the OUTPUT is `:protocol`.
6d includes `(make-mcp-error RESOURCE-NOT-FOUND ...)` (a base mcp error). Good — but the assertions
only check code/message/data. Add `(check-true (protocol-error? r))` and `(check-false (auth-error? r))`
for this case too: it proves the base→protocol erasure, the same way S2 proves auth→protocol. Right
now the base case's TYPE transformation is untested.

### S4. Contract-rejection test (edge-cases section) is good — keep it, and add the dual.
`(check-exn exn:fail:contract? (λ () (jsonrpc-error->exn (hasheq ...))))` is correct and valuable
(it pins "canonical input is the struct"). Also add a POSITIVE: `(check-true (protocol-error?
(jsonrpc-error->exn (jsonrpc-error INVALID-PARAMS "x" absent))))` already exists in 6b — fine.
No change needed beyond keeping the contract test; just noting it is one of the strongest
anti-vacuous assertions in the suite.

### S5. Message edge: `""` is covered (good). Also assert a SPECIAL code with `""` message threads
through (TS subclasses default a synthesized message — `errors.ts:47/68` — but `fromError` threads
the received message; the Racket decode must NOT synthesize). Add:
`(jsonrpc-error->exn (jsonrpc-error URL-ELICITATION-REQUIRED "" (hasheq 'elicitations '())))` →
`(equal? (exn-message r) "")` (NOT a synthesized "URL elicitation required"). This pins the
"decode never synthesizes a message even on the specialized branch" decision, which is currently
asserted only implicitly via the non-empty 6a message.

---

## Anti-vacuous-pass audit

The suite is mostly non-vacuous (asserts real codes via constants, real data shapes, `protocol-error?`
+ `auth-error?` discrimination). The two places where a WRONG implementation could still pass every
listed test are exactly C2 and C3 (a code-only match that drops the data-shape conjuncts). Closing
C2/C3 makes the data-gate genuinely tested rather than decorative. The drift-detection step
(flip an assertion → expect FAILURE) is present and correct.

## Prerequisites / tooling

- Test path stays `mcp/core/test/errors-test.rkt`, EXTEND with "Part 6," keep Parts 1-5 — correct.
- `raco`-broken workaround (run `racket <file>`, SCAN for FAILURE/ERROR, do NOT trust exit code,
  do NOT disable sandbox) — correctly documented and matches the file's top-level-`check-*` design.
- Test imports: `(struct-out jsonrpc-error)` at `spec-2025-11-25.rkt:119` DOES export the
  constructor + `jsonrpc-error-message`, so the spec's "add `jsonrpc-error` and
  `jsonrpc-error-message` to the test's `only-in`" is satisfiable. ✅
- Portability NFR (only `racket/contract` + constants + spec-2025-11-25) holds IFF C1 is resolved
  via option (b) (no new import) or an authorized re-export (still same module, no new MODULE). ✅

## Implementability / seam discipline

- Additive build at the DECODE anchor, append-only second `provide` block, no edit to 006's first
  block — all correctly specified and consistent with `errors.rkt:64-96, 173-186`.
- The YAGNI call on the optional `jsonrpc-error-jsexpr->exn` wrapper is reasonable; recommending
  OMIT keeps the surface minimal. The contract-rejection test documents the struct-only canonical
  form. Sound.
- Façade reconciliation (no M2→types.rkt dependency) is correct and well-argued; the open question
  (should the façade re-export `jsonrpc-error->exn`) is correctly punted to item 005's owner and is
  not a 007 blocker.

## Bottom line

Build-ready except for C1, which mis-recommends a non-existent export and must be corrected before
an implementer follows it into a compile error. C2/C3 close the only vacuous-pass holes (the
data-gate). S1-S5 are robustness polish. Fix C1 (flip to option (b) or authorize the M1 re-export)
and add C2/C3 and this is a clean 9.
