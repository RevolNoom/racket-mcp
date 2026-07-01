# Reviewer Feedback — Item 019: Transport port (`gen:transport`, M6)

Canonical spec: `docs/aide/items/019-transport-port.md` (202 lines — within R2 ≤400/40KB budget).
Reviewed against: TS `shared/transport.ts:51-134`, `types/types.ts:561-583`, `mcp/core/shared/auth.rkt:67-93`, queue-003.md:27-28.

**Verdict: NEEDS REVISION (minor).** Structure, scope, prerequisites, and imports are sound. The gaps are all in *test falsifiability* — several acceptance criteria are written so a worker can pass them with a vacuous or incomplete implementation. Fix the four Critical items (each is an added AC/test, not a rewrite) and this is implementation-ready.

---

## Prerequisites — VERIFIED

- `make-auth-info` signature confirmed at `auth.rkt:81-93`: mandatory `#:token string?` + `#:client-id string?`. The spec's test calls `(make-auth-info #:token "t" #:client-id "c")` (AC line 86, Strategy line 157) — **correct**, matches the real arity. Good catch including both required keywords; a common error is omitting `#:client-id`.
- `json-object?` re-exported by `mcp/core/main.rkt`: confirmed (auth.rkt:64-65 requires `../main.rkt` and uses `json-object?`). The `http-req-info` `(or/c #f json-object?)` contract and the `transport-send` msg contract have a real source. **Prerequisite holds.**
- L0/L1 import boundary (no `net/url`/subprocess/socket) is consistent with auth.rkt's own scope guard (auth.rkt:55-62). Good.

---

## Missing Coverage (Critical)

### C1 — Field contracts are decorative; no enforcement requirement, no rejection test (vacuous-contract trap)
`message-extra-info` and `transport-send-options` are plain `#:transparent` structs (spec lines 40, 54). The field contracts in the tables (`(or/c #f string?)`, `(or/c #f auth-info?)`, `(or/c #f (or/c string? exact-integer?))`) are **documented but nowhere required to be enforced**, and no test falsifies them. A worker can write a bare keyword constructor with zero contracts, pass every listed test, and ship `(make-message-extra-info #:session 42)` succeeding silently.

The house-style precedent sits one file over: `auth.rkt:81` uses `define/contract` on `make-auth-info` precisely so bad fields raise `exn:fail:contract?`. The spec should either (a) require `make-message-extra-info` / `make-transport-send-options` to be `define/contract` mirroring auth.rkt, then add **rejection tests**; or (b) explicitly state the port keeps constructors contract-free and delete the contract columns so they aren't misleading. Option (a) matches existing house style. As written the contracts are unfalsifiable.

Add ACs/tests:
- `(check-exn exn:fail:contract? (λ () (make-message-extra-info #:session 42)))`
- `(check-exn exn:fail:contract? (λ () (make-message-extra-info #:auth "not-auth-info")))`
- `(check-exn exn:fail:contract? (λ () (make-transport-send-options #:related-request-id 'sym)))`

### C2 — Default-raise behavior is claimed but untested (partial-stub unfalsifiable)
AC line 76 and Decisions line 188 state each generic method "has a default impl that raises (so a stub must implement all three explicitly)." **No test exercises a stub that omits a method.** If the worker writes `#:fallbacks` returning `(void)` instead of raising — or omits fallbacks so the error is the generic's default "not implemented" rather than the spec's intended raise — nothing catches it. The single full stub tests the happy path only.

Add a test: define a second stub that implements `gen:transport` but omits `transport-send`, assert `(check-exn exn:fail? (λ () (transport-send partial-stub (hash))))`. This is the only thing that proves "missing impls are caught early."

### C3 — `on-message` extra-info argument shape never asserted (lead's explicit question)
The team-lead asked: "Does it assert sinks fire with the extra-info argument shape?" As written, **no.** Strategy line 153 sets `(λ (msg extra) (set! got-msg msg))` and asserts only `got-msg`; `extra` is captured and discarded. The whole reason `message-extra-info` lives in this module is that it rides the `on-message` second argument — that linkage is untested.

Add: invoke the on-message sink with a real extra-info —
`((transport-on-message s) (hash "x" 1) (make-message-extra-info #:session "s1" #:auth ai))` — then assert `(check-pred message-extra-info? got-extra)` and `(check-equal? (message-extra-info-session got-extra) "s1")`. Also assert the 2-arg-with-`#f`-extra path works (`extra` defaulting/`#f`), since the TS sink is `(message, extra?)`.

### C4 — `transport-send` never tested with non-#f options; 3-arg arity + related-request-id accept-and-ignore unproven
Strategy line 151 only shows `transport-send` callable in the 2-arg form. Two problems:
1. **Arity/dispatch crash risk.** The stub defines `(transport-send t msg [opts #f])` (optional positional), but the spec never pins the *generic's declared arity*. If `define-generics` declares `transport-send` as 3 required args while the concrete uses an optional, or vice-versa, dispatch can fail at the boundary. Pin the generic to accept both 2- and 3-arg calls and **test both**: `(transport-send s (hash))` AND `(transport-send s (hash) opts)`.
2. **Accept-and-ignore of `related-request-id` (lead's question) is testable at the port level and currently isn't tested.** The strongest port-level proof of "adapters MUST NOT strip or error on a non-`#f` related-request-id" (spec line 68) is: `(check-not-exn (λ () (transport-send s (hash) (make-transport-send-options #:related-request-id "r1"))))`. The full strip/ignore *behavior* belongs to item 020, but "send accepts an options value carrying a live related-request-id without erroring" is exactly this item's contract — add it.

---

## Missing Coverage (Suggested)

- **S1 — integer `related-request-id` branch untested.** Contract is `(or/c #f (or/c string? exact-integer?))` but tests only use `"req-1"`. The `exact-integer?` union arm is the more fragile one. Add `(make-transport-send-options #:related-request-id 42)` → accessor returns `42`. (And under C1, a non-integer/non-string like `'sym` rejects.)
- **S2 — zero-arg `make-message-extra-info` untested.** Spec tests the fully-populated case + http-req-info `#f`, and mirrors a zero-arg case for `transport-send-options` (opts0, line 167) but not for extra-info. Add `(make-message-extra-info)` → all three fields `#f`, for symmetry and to prove every keyword defaults.
- **S3 — generic-method arity for the sinks.** Declaring getters and `set-...!` setters as generic methods is fine, but the spec leaves open whether they're 1-arg/2-arg on the generic. Pin them so a concrete struct using plain `#:mutable` field accessors (as the stub does) dispatches cleanly. Minor, but worth one line in Implementation Steps.
- **S4 — test require-path style.** Source uses relative `"../core/main.rkt"`; test uses `(file "../transport.rkt")`. Confirm `(file ...)` is the established test-file idiom in this repo (check an existing `mcp/core/test/*.rkt`) and keep it consistent, or the worker may guess wrong and hit a load error.

---

## Parity / House-style notes

- **`session` field is a TS divergence.** TS `MessageExtraInfo` (types.ts:561-583) has only `request`, `authInfo`, `closeSSEStream`, `closeStandaloneSSEStream` — **no `session` field**. The spec adds `session` (line 40, 45). It is *sanctioned by the queue* (queue-003.md:28 lists "session, auth, and HTTP-request info"), so this is acceptable, but the spec's TS-counterpart column ("(session-id carrier)") papers over the fact that there is no TS counterpart. One sentence in Decisions noting "session is a Racket addition not present in TS MessageExtraInfo; it carries the connection session into handlers, distinct from `transport-session-id`" would prevent a future parity-audit flag. Also clarify the relationship between `message-extra-info-session` and `transport-session-id` (two session concepts in one module).
- Dropping `closeSSEStream`/`closeStandaloneSSEStream`/`setProtocolVersion`/`setSupportedProtocolVersions` to the HTTP layer (spec line 49, 62) is correctly scoped — good.
- Size: 202 lines, well within R2. No oversized code blocks. R3 versions/ layout respected.

---

## Summary

Solid, scoped, prerequisite-accurate spec. The single theme across all four Critical items: **the test plan proves the happy path but not the rejections, the defaults, or the argument linkages** that are the actual contract of a port interface. Add the rejection tests (C1), the partial-stub raise test (C2), the extra-info assertion on on-message (C3), and the with-options/dual-arity send test (C4), plus the suggested integer/zero-arg cases. Then green-light.
