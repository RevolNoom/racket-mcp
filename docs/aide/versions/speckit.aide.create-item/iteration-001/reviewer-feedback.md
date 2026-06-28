# Reviewer Feedback — Item 015 (`_meta` metadata utils M5c + shared `AuthInfo` M5d)

**Reviewer focus:** testing strategy, testing prerequisites, edge cases, TS-parity gaps.
**Verdict:** Strong, well-pinned spec — but the test plan is **too optimistic about well-formed input** and several pinned invariants are **unfalsifiable as currently tested**. Revision recommended before execute-item. Findings below are ordered Critical → Suggested, each with a concrete test proposal.

I verified every claim against source rather than trusting the spec:
- `typescript-sdk/.../shared/metadataUtils.ts` (rung-2 is `metadata.annotations?.title` — optional-chaining, null-tolerant)
- `typescript-sdk/.../types/constants.ts` (8 reserved keys confirmed)
- `typescript-sdk/.../types/types.ts:435` (AuthInfo shape confirmed)
- `mcp/core/types/spec-2026-07-28.rkt:436-487` (`json->request-meta` decode requirements + `request-meta-reserved-keys`)
- `mcp/core/types/constants.rkt:60-64` (the 5 S1 constants)

---

## Current Coverage Summary (what is already good)

- `get-display-name` happy-path + the empty-string-title fallthrough matrix is genuinely thorough — 7 cases incl. title-over-annotations and empty-annotations.title→name. This is the load-bearing precedence and it is well covered.
- Reserved-key constant values + `(length reserved-meta-keys)` = 8 + string/symbol acceptance on `reserved-meta-key?` are covered.
- `auth-info-expired?` boundary (`<=` at-expiry, before, `#f`-expiry) is correctly pinned and tested with an injected `now` (no wall-clock dependence) — exactly right.
- `auth-info-has-scope?` member/non-member/empty is covered.
- JSON-encode asymmetry is partially broken on the encode side (`(hash-has-key? json 'clientId)` + omitted-optional check) — good instinct.
- `struct->vector` length=7 guards against field-count drift.

---

## Missing Coverage (CRITICAL — can crash or ship a silent bug)

### C1. `get-display-name` crashes on `annotations: null` (and any non-hash annotations) — real TS-parity divergence
The pinned Racket code is `(hash-ref (hash-ref md 'annotations (hasheq)) 'title #f)`. The `(hasheq)` default only fires when `annotations` is **absent**. When `annotations` is **present but JSON `null`**, `read-json` yields the symbol `'null` (Racket's `json-null` default), and `(hash-ref 'null 'title #f)` raises a contract error — **crash**. TS's `metadata.annotations?.title` returns `undefined` via optional chaining and falls through to `name`. Same crash for `annotations` present as a string/number/array.
- This is wire-realistic: the input form is PINNED as "the symbol-keyed hash `read-json` produces," and `read-json` will happily produce `'annotations → 'null` or a non-hash.
- **The spec's own claim of "port TS verbatim" is false here** — TS tolerates null annotations; the Racket port aborts.
- **Test proposal:** `(check-equal? (get-display-name (hasheq 'name "n" 'annotations (json-null))) "n")` and `(check-equal? (get-display-name (hasheq 'name "n" 'annotations "garbage")) "n")`. Both must return `"n"`, not raise. Fix requires guarding rung 2 with `(hash? (hash-ref md 'annotations (hasheq)))` before the inner `hash-ref`.

### C2. AuthInfo **decode path** (`json->auth-info`) has ZERO adversarial/irregular coverage
Every `json->auth-info` test feeds it the output of `auth-info->json` (round-trip only). Malformed wire input is completely untested:
- Missing required `token` / `clientId` — does it raise (per the codebase's `h-req` decoder discipline) or silently build `#f`-fielded structs? Not pinned, not tested.
- `scopes` absent, or present as a non-array (`"read"` instead of `["read"]`).
- `token`/`clientId` present as non-strings (number, null).
- `expiresAt` as a string `"100"` or a negative/float number.

Per the project's recurring `json->struct` self-reject trap (decoders that silently accept malformed input), this is exactly where a bug hides. The spec must pin the rejection contract AND test it.
- **Test proposal (rejection):** `(check-exn exn:fail? (λ () (json->auth-info (hasheq 'clientId "c" 'scopes '()))))` (missing token); same for missing clientId; `(check-exn exn:fail? (λ () (json->auth-info (hasheq 'token 5 'clientId "c" 'scopes '()))))` (non-string token), assuming the decision is "reject." If the decision is instead "tolerate," that must be stated and asserted positively — but silent tolerance of a missing token in an auth struct is a security-relevant footgun and should be reject.

### C3. `make-auth-info` / `auth-info/c` contract is unfalsifiable — no construction-side rejection test
The spec claims field contracts (`string?`, `(listof string?)`, `(opt/c exact-nonnegative-integer?)`, `(opt/c string?)`, `(opt/c json-object?)`) but **every test constructs only valid values**. A `#:transparent` struct with a never-exercised contract is identical to one with no contract at all — the test suite would stay green if the contracts were missing or wrong. This is the project's documented "no-guard / vacuous-acceptance" trap.
- **Test proposal (rejection):** `(check-exn exn:fail:contract? (λ () (make-auth-info #:token 5 #:client-id "c")))` (non-string token); `(... #:token "t" #:client-id "c" #:expires-at -1)` (negative → must violate `exact-nonnegative-integer?`); `(... #:scopes "read")` (string not list); `(... #:resource 5)` (non-string resource); `(... #:extra "x")` (non-json-object extra). At least 2–3 of these must be in the suite or the contract claim is unproven.

### C4. JSON round-trip is partially **vacuous** on the decode side (camelCase parity)
`(check-equal? (json->auth-info (auth-info->json ai)) ai)` passes even if BOTH encode and decode use the wrong key consistently (e.g., both use `'client-id`). The encode side is guarded (`hash-has-key? 'clientId`), but the **decode side has no literal-wire test** — nothing proves `json->auth-info` reads the camelCase `clientId`/`expiresAt` keys rather than kebab-case.
- **Test proposal:** decode a hand-written literal wire hash: `(check-equal? (json->auth-info (hasheq 'token "t" 'clientId "c" 'scopes (list "read") 'expiresAt 100 'resource "https://x/mcp")) (make-auth-info #:token "t" #:client-id "c" #:scopes (list "read") #:expires-at 100 #:resource "https://x/mcp"))`. This breaks the round-trip symmetry and proves the decoder honors camelCase.

### C5. Part 4 (S1 envelope round-trip) prerequisite "minimal valid values" is underspecified — will fail or pass for the wrong reason
I read `json->request-meta` (`spec-2026-07-28.rkt:455`). It does NOT accept arbitrary values for the three required reserved keys:
- `clientInfo` is fed to `json->implementation` → must be a valid Implementation JSON object (`name` + `version`).
- `clientCapabilities` is fed to `json->client-capabilities` → must be a valid capabilities object.
- `protocolVersion` must be a non-absent value.

If the test author supplies `clientInfo → "x"` (a bare string, the literal reading of "minimal valid values"), `json->implementation` crashes and Part 4 fails on an unrelated decode error — masking whether `traceparent` actually round-trips. The spec MUST pin the exact minimal-valid fixture, e.g.:
```racket
(hasheq PROTOCOL-VERSION-KEY "2026-07-28"
        CLIENT-INFO-KEY (hasheq 'name "c" 'version "1")
        CLIENT-CAPABILITIES-KEY (hasheq)
        'traceparent "00-abc-01")
```
(Use the S1 `…-META-KEY` string constants `string->symbol`'d as keys, matching the decoder.) Confirm `(hasheq)` is an accepted minimal capabilities object against `json->client-capabilities` before pinning — if it rejects empty, supply the minimal accepted shape. **Without a pinned fixture this test is a coin flip.**

---

## Missing Coverage (SUGGESTED — robustness / boundary)

### S1. The 8-key set vs S1's `request-meta-reserved-keys` are DIFFERENT sets — the boundary deserves an explicit negative test
M5c `reserved-meta-keys` = {5 prefixed} ∪ {traceparent, tracestate, baggage} (8). S1 `request-meta-reserved-keys` = {`progressToken`} ∪ {5 prefixed} (6). Intersection is the 5 prefixed only. So:
- `progressToken` is reserved in S1 but **not** in M5c's set → `(reserved-meta-key? 'progressToken)` returns `#f`.
- The 3 trace keys are in M5c's set but ride S1's unreserved `rest`.

This is exactly the kind of "two notions of reserved" that confuses a future caller. The 8-key definition makes `progressToken → #f` correct, but it's a surprising boundary that must be pinned with a test.
- **Test proposal:** `(check-false (reserved-meta-key? 'progressToken))` with a comment noting it IS reserved at the S1 RequestParams level but is not one of the 8 namespaced `_meta` keys.

### S2. `meta-ref`/`meta-set` string-vs-symbol key normalization is asserted only for `reserved-meta-key?`, not for the accessors
The PIN says accessors normalize a string key (the `…-META-KEY` constant) to its symbol form, so `(meta-ref meta TRACEPARENT-META-KEY)` ≡ `(meta-ref meta 'traceparent)`. Part 3 exercises only symbol keys. The prefixed keys are the risky ones: `(string->symbol "io.modelcontextprotocol/logLevel")` = `|io.modelcontextprotocol/logLevel|`.
- **Test proposal:** `(define m (meta-set (hasheq) LOG-LEVEL-META-KEY "debug"))` then `(check-equal? (meta-ref m LOG-LEVEL-META-KEY) "debug")` AND `(check-equal? (meta-ref m (string->symbol LOG-LEVEL-META-KEY)) "debug")` — prove a string-keyed set is readable by the equivalent symbol and vice-versa.

### S3. `meta-ref` with no default on a missing key — behavior unpinned
Signature is `(meta-ref meta key [default])`. The no-default-on-missing path (`(meta-ref m 'absent)`) — raise like `hash-ref`, or return `#f`? Not stated. Pick one and test it; an accessor that raises on a normal "is this key present?" probe is a footgun if callers expect `#f`.

### S4. `expiresAt = 0` and empty-but-present optionals — falsy-omit regression
- `expires-at = 0` is a valid `exact-nonnegative-integer?` (epoch 0). In Racket `0` is truthy so `auth-info-expired?` and the `put`-skips-`#f` omit logic both handle it — but this is precisely the value that breaks naive falsy-omit ports. Add `(check-true (auth-info-expired? (make-auth-info #:token "t" #:client-id "c" #:expires-at 0) 1))` and `(check-true (hash-has-key? (auth-info->json (make-auth-info #:token "t" #:client-id "c" #:expires-at 0)) 'expiresAt))` to lock it.
- `extra = (hasheq)` (present but empty): is it emitted (present, `#f`≠empty) or omitted? The PIN says omit-on-`#f` only, so empty-hash extra should round-trip as present `{}`. Add one assertion so this boundary is pinned rather than incidental.

### S5. `get-display-name` non-string `title` (incl. `null`) — divergence from "verbatim TS"
TS rung 1 is `title !== undefined && title !== ''`; for `title: null` TS returns `null`, and for `title: 42` TS returns `42`. The Racket `(and (string? title) …)` guard is stricter — it falls through. This is arguably *better*, but the spec claims a verbatim port. Either (a) document the intentional divergence in the module doc block, or (b) note it. Add `(check-equal? (get-display-name (hasheq 'name "n" 'title (json-null))) "n")` so the chosen behavior is pinned, not accidental.

### S6. Missing-`name` "caller bug raises" is pinned but never asserted
The spec pins that `(hash-ref md 'name)` raises when `name` is absent and forbids a fallback — but no test proves it raises. Per the project's self-reject trap, an unfalsifiable "it raises" invariant tends to rot.
- **Test proposal:** `(check-exn exn:fail? (λ () (get-display-name (hasheq 'title ""))))` (no name, empty title → must reach rung 3 and raise).

### S7. Trace round-trip covers only `traceparent`, singular
Part 4 asserts only `traceparent` survives S1. Cheap to also assert `tracestate` and `baggage` survive simultaneously (they share the same `rest` passthrough, but a future S1 change could reserve one). Add them to the same fixture's assertions.

---

## Concrete Test-Case Proposals (consolidated input → expected)

metadata-utils-test.rkt:
- `(get-display-name (hasheq 'name "n" 'annotations (json-null)))` → `"n"` (C1, no crash)
- `(get-display-name (hasheq 'name "n" 'annotations "x"))` → `"n"` (C1, no crash)
- `(get-display-name (hasheq 'name "n" 'title (json-null)))` → `"n"` (S5)
- `(check-exn exn:fail? (λ () (get-display-name (hasheq 'title ""))))` (S6, missing name)
- `(reserved-meta-key? 'progressToken)` → `#f` (S1)
- string-keyed `meta-set`/`meta-ref` equivalence on `LOG-LEVEL-META-KEY` (S2)
- Part-4 fixture pinned with valid `clientInfo (hasheq 'name "c" 'version "1")` + verified-minimal `clientCapabilities`; assert `traceparent`/`tracestate`/`baggage` all survive (C5, S7)

auth-test.rkt:
- `(check-exn exn:fail? (λ () (json->auth-info (hasheq 'clientId "c" 'scopes '()))))` (C2, missing token)
- `(check-exn exn:fail? (λ () (json->auth-info (hasheq 'token "t" 'scopes '()))))` (C2, missing clientId)
- `(check-exn exn:fail:contract? (λ () (make-auth-info #:token 5 #:client-id "c")))` (C3)
- `(check-exn exn:fail:contract? (λ () (make-auth-info #:token "t" #:client-id "c" #:expires-at -1)))` (C3)
- literal-wire decode: `(json->auth-info (hasheq 'token "t" 'clientId "c" 'scopes (list "read") 'expiresAt 100))` → expected `make-auth-info` (C4)
- `expiresAt = 0` expired + emitted (S4)

---

## Bottom line
The happy-path and the headline empty-string-title precedence are well done. The gaps are concentrated where this agent always looks: **non-well-formed input (annotations-null crash C1, decode-path C2), unfalsifiable invariants (contract C3, round-trip vacuity C4, missing-name S6), and an underspecified cross-module test fixture (C5)**. C1 is a latent crash; C2/C3 leave an auth struct's validation entirely unproven. Address C1–C5 (and ideally S1–S6) and this is ready.
