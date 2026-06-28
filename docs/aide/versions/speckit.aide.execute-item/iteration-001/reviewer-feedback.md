# Reviewer Feedback — Item 015 (`_meta` metadata utils M5c + shared `AuthInfo` M5d)

**Iteration:** 001
**Verdict:** ✅ Approved — no actionable criticism. Rating 10/10.

## Scope reviewed
- `mcp/core/shared/metadata-utils.rkt` (M5c)
- `mcp/core/shared/auth.rkt` (M5d)
- `mcp/core/shared/test/metadata-utils-test.rkt`
- `mcp/core/shared/test/auth-test.rkt`

## Acceptance-criteria check

### M5c — metadata-utils
- ✅ `#lang racket/base`, explicit curated `provide`, in `mcp/core/shared/`.
- ✅ Exports exactly: `get-display-name`; the 8 reserved-key string constants (5 re-exported from S1 + `TRACEPARENT/TRACESTATE/BAGGAGE` defined here); `reserved-meta-key-strings`; `reserved-meta-keys`; `reserved-meta-key?`; `meta-ref`; `meta-set`. `normalize-key` not leaked.
- ✅ `get-display-name` precedence — all 7 happy-path cases pass.
- ✅ C1 — `(hash? annotations)` guard present; `null`/non-hash annotations → `"n"`, no crash.
- ✅ S5 — non-string title falls through (`string?` guard, documented divergence).
- ✅ S6 — missing `name` raises (asserted via `check-exn`).
- ✅ 5-vs-8 reconciliation — trace constants present, `(length reserved-meta-keys)` = 8, predicate accepts string+symbol.
- ✅ S1 two-notions boundary — `(reserved-meta-key? 'progressToken)` → `#f`, asserted + documented.
- ✅ Accessor round-trip, non-reserved untouched, functional `meta-set`, S2 prefixed-key string/symbol equivalence, S3 missing-key→`#f`.
- ✅ C5/S7 — trace keys survive the S1 `request-meta` envelope round-trip with the pinned valid-sub-object fixture (`r26:`-prefixed calls; `clientCapabilities` = `(hasheq)` accepted).
- ✅ Module doc block covers precedence, empty-string fallthrough, S5/C1 divergences, 5-vs-8 + SEP-414 unprefixed exception, two-notions boundary, SDK-does-not-interpret.

### M5d — auth
- ✅ `#lang racket/base`, explicit `provide`, in `mcp/core/shared/`.
- ✅ Exports exactly: `struct-out auth-info` + `make-auth-info` + `auth-info-expired?` + `auth-info-has-scope?` + `auth-info->json` + `json->auth-info`. `req`/`opt`/`put-unless-false`/`missing` not leaked.
- ✅ Field surface EXACT — 6 fields in order (`struct->vector` length 7 asserted).
- ✅ Construct + required/optional defaults (`scopes`='(), optionals `#f`).
- ✅ C3 — `make-auth-info` uses `define/contract` so the contract is checked on the INTERNAL call from `json->auth-info` too (not just at the module boundary as `contract-out` would). 5 bad-field `check-exn exn:fail:contract?`.
- ✅ `auth-info-expired?` — expired/not-yet/boundary(`<=`)/no-expiry, plus S4 epoch-0.
- ✅ `auth-info-has-scope?` — member/non-member/empty.
- ✅ JSON encode omit-on-`#f`; S4 — `0` and empty-but-present `extra` emitted; symmetric round-trip.
- ✅ C4 — literal-wire camelCase decode test (de-vacuumed).
- ✅ C2 — `json->auth-info` raises on missing token / missing clientId / non-string token / non-list scopes.
- ✅ `resource` is a string; no `net/url`.
- ✅ Module doc block covers field surface, resource-as-string portability, decode-reject discipline, NO-OAuth.

### Cross-cutting
- ✅ Imports = S1 only: M5c `(require "../main.rkt")`; M5d `(require racket/contract "../main.rkt")`. No `net/*`, no subprocess/socket (grep clean — matches are doc-comments only).
- ✅ No `(module+ test …)`; tests under `test/`.
- ✅ `raco make` both modules → exit 0, clean.
- ✅ `raco test mcp/core/shared/` → 269 passed (192 baseline + 38 metadata-utils + 39 auth). Siblings unchanged: validators 300, util 102.

## Notable design corrections caught during build
1. **`define/contract` over `contract-out`** — `contract-out` only checks at the module boundary; the internal `json->auth-info → make-auth-info` path would bypass it, so the C2 non-string-token rejection test would fail. `define/contract` checks every call, keeping the decoder's type-rejection real.
2. **Require path** — spec text wrote `mcp/core/main.rkt` (not a registered collection); corrected to the codebase convention `"../main.rkt"`.
3. **`r26:` prefix** — `json->request-meta`/`request-meta->json` are re-exported prefixed via `types/main.rkt`; the round-trip test uses `r26:`.

No outstanding issues. Approved.
