# Work Item 019: Transport port — `gen:transport` interface (M6)

> **Queue:** `docs/aide/queue/queue-002.md` — Item 019
> **Stage:** S2 (Foundation: validators, schema, shared utilities — L0 part 2)
> **Module:** **M6** — `mcp/transport/transport.rkt`. The hexagonal transport port every adapter (stdio M7, HTTP M8, …) implements. Mirrors TS `shared/transport.ts` → `Transport` interface + `TransportSendOptions` + `MessageExtraInfo`. First module in the new `mcp/transport/` collection; no existing sibling files.
> **Source vision:** `docs/aide/vision.md` §6 (Portability NFR — core L0–L2 loads without subprocess/socket), G1 (behaviour parity with TS SDK).
> **Source roadmap:** `docs/aide/roadmap.md` Stage S2 → Deliverables (`mcp/transport/transport.rkt` (M6) — transport port interface).
> **Source architecture:** `docs/aide/architecture.md` M6 (transport port; depends on S1 + S2 auth; L1 boundary), §1.3 (explicit `provide`), §4.1 (portability).
> **Reference impl:** `typescript-sdk/packages/core/src/shared/transport.ts:74` — the `Transport` interface (start/send/close, onmessage/onclose/onerror, sessionId); `typescript-sdk/packages/core/src/shared/transport.ts:51` — `TransportSendOptions` (relatedRequestId, resumptionToken); `typescript-sdk/packages/core/src/types/types.ts:561` — `MessageExtraInfo` (request, authInfo).
> **Auth shape:** `mcp/core/shared/auth.rkt:67–75` — `auth-info` struct + `make-auth-info` (the S2 AuthInfo this port references for the `auth` field of `message-extra-info`).
> **Status:** ✅ Done

---

## Description

Implement `mcp/transport/transport.rkt` — the **hexagonal port** that every MCP transport adapter (stdio, Streamable HTTP, SSE, …) must satisfy. Uses `racket/generic` (`gen:transport`) to define a dispatch surface with three methods (`transport-start`, `transport-send`, `transport-close`) and three settable callback sinks (`on-message`, `on-close`, `on-error`). Also defines the `message-extra-info` struct (session + auth + http-req-info) consumed by the `on-message` sink, and the `transport-send-options` keyword contract surface (related-request-id — inert until S6a/M8 — and resumption-token).

This is the **port only** — no concrete adapter code; no subprocess, socket, or I/O. It belongs at L1 (imports S1 types/errors + S2 auth.rkt; nothing deeper). Adapters (M7 stdio, M8 Streamable HTTP) implement `gen:transport` in their own modules.

### Method + callback surface (TS → Racket mapping)

| TS `Transport` | Racket `gen:transport` | Notes |
|---|---|---|
| `start(): Promise<void>` | `(transport-start t)` | Begin processing; call after sinks set |
| `send(msg, opts?)` | `(transport-send t msg [opts])` | `msg` = `json-object?`; `opts` = `transport-send-options?` or `#f` |
| `close(): Promise<void>` | `(transport-close t)` | Close connection |
| `onmessage?` | `transport-on-message` (settable sink) | `(fn msg extra)` where `extra` = `message-extra-info?` or `#f` |
| `onclose?` | `transport-on-close` (settable sink) | `(fn)` or `#f` |
| `onerror?` | `transport-on-error` (settable sink) | `(fn err)` or `#f` |
| `sessionId?` | `transport-session-id` (optional accessor) | `(or/c #f string?)` |

Settable sinks are struct fields with `#:mutable` (adapters set them before calling `start`). Because Racket generics dispatch on struct type, the `gen:transport` methods delegate to the struct's concrete implementations.

### `message-extra-info` struct

Defined in this module; consumed by every `on-message` handler. Mirrors TS `MessageExtraInfo` (`typescript-sdk/packages/core/src/types/types.ts:561`), scoped to the three fields relevant at this layer:

```
(struct message-extra-info (session auth http-req-info) #:transparent)
```

| Field | Contract | TS counterpart | Notes |
|---|---|---|---|
| `session` | `(or/c #f string?)` | **(none — Racket-specific)** | Per-connection session ID; TS surfaces session via `sessionId` on `Transport`, not `MessageExtraInfo`. Sanctioned by queue; disambiguated from `transport-session-id` in Decisions. |
| `auth` | `(or/c #f auth-info?)` | `authInfo?` | From S2 `auth.rkt`; `#f` when unauthenticated |
| `http-req-info` | `(or/c #f json-object?)` | `request?` (HTTP request) | Wire-safe jsexpr map of HTTP metadata; `#f` for stdio |

`make-message-extra-info` is the smart constructor (keyword args, all default `#f`); it MUST use `define/contract` (house precedent: `mcp/core/shared/auth.rkt:81`) so bad field values raise `exn:fail:contract?`. Zero-arg `(make-message-extra-info)` → all three fields `#f`.

`closeSSEStream` / `closeStandaloneSSEStream` (TS `MessageExtraInfo`) are SSE-specific and belong to the HTTP adapter layer — not included here.

### `transport-send-options`

```
(struct transport-send-options (related-request-id resumption-token) #:transparent)
```

| Field | Contract | TS counterpart | Status |
|---|---|---|---|
| `related-request-id` | `(or/c #f (or/c string? exact-integer?))` | `relatedRequestId?` (`RequestId`) | **INERT until S6a/M8** — defined here as a routing hint; stdio + in-memory ignore it |
| `resumption-token` | `(or/c #f string?)` | `resumptionToken?` | For reconnect continuity; adapter decides whether to use |

`onresumptiontoken` (TS callback in `TransportSendOptions`) is adapter-internal plumbing — not part of the port surface; HTTP adapter may add it internally.

`make-transport-send-options` is the smart constructor (keyword args, both default `#f`); MUST use `define/contract` so bad field values raise `exn:fail:contract?`.

### `related-request-id` — defined but INERT

`related-request-id` is a **routing hint**: it tells a multiplexed transport which incoming request an outgoing message is associated with. In-memory and stdio transports handle one message stream and safely ignore it. It becomes live in S6a/M8 (Streamable HTTP). Defining it here — not in M8 — keeps the port surface stable. **Adapters MUST NOT strip or error on a non-`#f` `related-request-id`; they must accept and ignore it until M8 activates it.**

---

## Acceptance Criteria

- [ ] `mcp/transport/` directory created (new; no prior files). `mcp/transport/transport.rkt` exists as `#lang racket/base` with explicit, curated `provide`.
- [ ] `mcp/transport/test/` directory created. `mcp/transport/test/transport-test.rkt` exists as the unit test.
- [ ] **`gen:transport` generic interface** declared via `racket/generic` with three methods: `transport-start`, `transport-send`, `transport-close`. Each has a default impl that raises (so a stub must implement all three explicitly).
- [ ] **`message-extra-info` struct** defined and provided with fields `session`, `auth`, `http-req-info` (`#:transparent`); `make-message-extra-info` smart constructor using `define/contract` (field contracts enforced, raises `exn:fail:contract?` on bad values); field accessors provided.
- [ ] **`transport-send-options` struct** defined and provided with fields `related-request-id`, `resumption-token` (`#:transparent`); `make-transport-send-options` smart constructor using `define/contract` (field contracts enforced); field accessors provided.
- [ ] **Settable sinks** (`on-message`, `on-close`, `on-error`) are part of the transport protocol surface (generic methods `transport-on-message`, `transport-on-close`, `transport-on-error` to get; `set-transport-on-message!`, `set-transport-on-close!`, `set-transport-on-error!` to set) — OR defined as mutable fields on a `transport-base` convenience struct that `gen:transport` concrete types may embed; document the chosen approach.
- [ ] **`transport-session-id`** generic method returning `(or/c #f string?)`; optional accessor (concrete types may return `#f` if they don't track session IDs).
- [ ] **`related-request-id` is documented as INERT until S6a/M8** in the module's doc comment.
- [ ] **Imports L0/L1 only.** Requires: `racket/generic`, `racket/contract`, `mcp/core/main.rkt` (S1 barrel — `json-object?` for `msg` contract), `mcp/core/shared/auth.rkt` (S2 — `auth-info?`). NO `racket/system`, NO sockets, NO `net/url`, NO subprocess, NO web-server.
- [ ] **Explicit `provide`** — never `(all-defined-out)`. Public surface: `gen:transport`, `transport-start`, `transport-send`, `transport-close`, `transport-on-message`, `transport-on-close`, `transport-on-error`, `set-transport-on-message!`, `set-transport-on-close!`, `set-transport-on-error!`, `transport-session-id`, `message-extra-info`, `message-extra-info?`, `make-message-extra-info`, `message-extra-info-session`, `message-extra-info-auth`, `message-extra-info-http-req-info`, `transport-send-options`, `transport-send-options?`, `make-transport-send-options`, `transport-send-options-related-request-id`, `transport-send-options-resumption-token`.
- [ ] **Unit test — full stub satisfies `gen:transport`.** `transport-test.rkt` defines a `test-transport` struct that implements ALL `gen:transport` methods; `(check-pred transport? ...)` passes; `transport-start`, `transport-send`, `transport-close` each callable without error.
- [ ] **Unit test — partial stub triggers default raise (C2).** A second struct (`partial-transport`) that omits `transport-send` from its `#:methods gen:transport` block; `(check-exn exn:fail? (λ () (transport-send pt (hasheq 'jsonrpc "2.0" 'method "x"))))` — proves the default-raise fires on an unimplemented method.
- [ ] **Unit test — `transport-send` arity (C4).** Full stub tested with BOTH 2-arg `(transport-send s msg)` and 3-arg `(transport-send s msg opts)` where `opts` is a `transport-send-options` with a non-`#f` `related-request-id` — both `check-not-exn`. Test with `related-request-id` as a string AND as an exact-integer (both legal per contract); stub accepts and ignores (pins arity and inert accept-and-ignore at port level).
- [ ] **Unit test — sinks set + invoked, extra-info asserted (C3).** `on-message`: set handler capturing BOTH args `(λ (msg extra) ...)`. Invoke with a real `(make-message-extra-info #:session "s1" #:auth ai #:http-req-info #f)` as the second arg; assert `got-msg` is the message AND `(check-pred message-extra-info? got-extra)` AND field accessors on `got-extra` match. Also invoke with `extra = #f` (unauthenticated path) and assert `got-extra` is `#f`. `on-close`: set + invoke, assert fired. `on-error`: set + invoke with a dummy `exn:fail?`, assert captured.
- [ ] **Unit test — `message-extra-info` field surface + zero-arg.** `(make-message-extra-info #:session "s1" #:auth ai #:http-req-info #f)` — all three field accessors correct. `(make-message-extra-info)` → all fields `#f` (zero-arg all-defaults).
- [ ] **Unit test — `message-extra-info` contract rejection (C1).** `(check-exn exn:fail:contract? (λ () (make-message-extra-info #:session 42)))` (non-string session); `(check-exn exn:fail:contract? (λ () (make-message-extra-info #:auth "not-auth-info")))` (non-auth-info auth).
- [ ] **Unit test — `transport-send-options` contract rejection (C1).** `(check-exn exn:fail:contract? (λ () (make-transport-send-options #:related-request-id 'sym)))` (symbol is not `(or/c #f string? exact-integer?)`); `(check-exn exn:fail:contract? (λ () (make-transport-send-options #:resumption-token 42)))` (non-string token).
- [ ] **Unit test — `transport-session-id` accessor.** Stub returns a fixed session string; `(transport-session-id s)` → that string.
- [ ] **Unit test — `transport-send-options` field surface.** `(make-transport-send-options #:related-request-id "req-1" #:resumption-token "tok")` → accessors return correct values; `(make-transport-send-options)` → both fields `#f`.
- [ ] `raco test mcp/transport/test/` passes (exit 0). `raco make mcp/transport/transport.rkt` exits 0.
- [ ] **Progress** (`docs/aide/progress.md`): flip M6 deliverable line 📋→🚧→✅.

---

## Implementation Steps

1. **Re-read references** (targeted):
   - `typescript-sdk/packages/core/src/shared/transport.ts:51–134` — `TransportSendOptions` + `Transport` interface.
   - `typescript-sdk/packages/core/src/types/types.ts:561–583` — `MessageExtraInfo` fields.
   - `mcp/core/shared/auth.rkt:67–75` — `auth-info` struct fields + `(provide …)` surface (confirm `auth-info?` + `make-auth-info` are exported).
   - Skim `mcp/core/shared/stdio.rkt` (or `mcp/core/main.rkt`) for how `racket/generic` usage looks in this codebase if needed for precedent.

2. **Create `mcp/transport/` directory** and `mcp/transport/test/` directory.

3. **Write `mcp/transport/transport.rkt`** (`#lang racket/base`):
   - `(require racket/generic racket/contract "../core/main.rkt" "../core/shared/auth.rkt")` (relative paths from `mcp/transport/` to `mcp/`; adjust if using collection-style requires consistent with `mcp/core/shared/auth.rkt`'s own import pattern at `auth.rkt:65`).
   - Module-level doc comment: port of TS `Transport` interface; `related-request-id` inert until S6a/M8; `message-extra-info` defined here as port surface; L0/L1 imports only.
   - `(struct message-extra-info (session auth http-req-info) #:transparent)` + `make-message-extra-info` via `define/contract` (house precedent: `auth.rkt:81`; keyword args `#:session (or/c #f string?)`, `#:auth (or/c #f auth-info?)`, `#:http-req-info (or/c #f json-object?)`, all default `#f`; bad values raise `exn:fail:contract?`).
   - `(struct transport-send-options (related-request-id resumption-token) #:transparent)` + `make-transport-send-options` via `define/contract` (keyword args `#:related-request-id (or/c #f string? exact-integer?)`, `#:resumption-token (or/c #f string?)`, both default `#f`).
   - `(define-generics transport ...)` declaring `transport-start`, `transport-send`, `transport-close`, `transport-on-message`, `transport-on-close`, `transport-on-error`, `set-transport-on-message!`, `set-transport-on-close!`, `set-transport-on-error!`, `transport-session-id`. Each method has a default raise so missing impls are caught early.
   - Explicit `(provide …)` listing all public names.

4. **Write `mcp/transport/test/transport-test.rkt`** (see Testing Strategy).

5. **Run** `raco make mcp/transport/transport.rkt` then `raco test mcp/transport/test/`. Fix any failures. Confirm `raco test mcp/core/` still passes (this item adds a new collection; it must not break S1/S2 suites).

6. **Update progress** (see Completion Reminder).

---

## Testing Strategy

Pure logic, no external services. Strategy: one-line `raco test mcp/transport/test/`.

**Test file:** `mcp/transport/test/transport-test.rkt` (`#lang racket/base`; `(require rackunit (file "../transport.rkt") (file "../../core/shared/auth.rkt"))`).

Define a minimal stub:

```racket
;; Trivial concrete transport for testing the port surface.
(struct test-transport
  ([on-message #:mutable]
   [on-close   #:mutable]
   [on-error   #:mutable]
   [session-id])
  #:methods gen:transport
  [(define (transport-start t) (void))
   (define (transport-send t msg [opts #f]) (void))
   (define (transport-close t) (void))
   (define (transport-on-message t) (test-transport-on-message t))
   (define (transport-on-close t)   (test-transport-on-close t))
   (define (transport-on-error t)   (test-transport-on-error t))
   (define (set-transport-on-message! t h) (set-test-transport-on-message! t h))
   (define (set-transport-on-close! t h)   (set-test-transport-on-close! t h))
   (define (set-transport-on-error! t h)   (set-test-transport-on-error! t h))
   (define (transport-session-id t) (test-transport-session-id t))])
```

**Helpers:**

```racket
(define s (test-transport #f #f #f "sess-1"))  ; full stub
(define ai (make-auth-info #:token "t" #:client-id "c"))
(define msg (hasheq 'jsonrpc "2.0" 'method "ping"))
```

**Part 1 — stub satisfies gen:transport:**
- `(check-pred transport? s)`.
- `(check-not-exn (λ () (transport-start s)))`.
- `(check-not-exn (λ () (transport-send s msg)))` — 2-arg (no opts).

**Part 2 — `transport-send` arity + related-request-id inert (C4):**
- `(check-not-exn (λ () (transport-send s msg (make-transport-send-options))))` — 3-arg, all-`#f` opts.
- `(define opts-str (make-transport-send-options #:related-request-id "rid-1"))` → `(check-not-exn (λ () (transport-send s msg opts-str)))` — string related-request-id accepted and ignored.
- `(define opts-int (make-transport-send-options #:related-request-id 42))` → `(check-not-exn (λ () (transport-send s msg opts-int)))` — exact-integer related-request-id also accepted and ignored.

**Part 3 — partial stub triggers default raise (C2):**
```racket
(struct partial-transport ()
  #:methods gen:transport
  [(define (transport-start t) (void))
   ;; transport-send deliberately omitted
   (define (transport-close t) (void))
   ...])
(define pt (partial-transport))
(check-exn exn:fail? (λ () (transport-send pt msg)))
```

**Part 4 — sinks set + invoked with extra-info asserted (C3):**
- `on-message` with real extra-info:
  ```racket
  (define got-msg #f) (define got-extra 'unset)
  (set-transport-on-message! s (λ (m e) (set! got-msg m) (set! got-extra e)))
  (define ei (make-message-extra-info #:session "s1" #:auth ai))
  ((transport-on-message s) msg ei)
  (check-equal? got-msg msg)
  (check-pred message-extra-info? got-extra)
  (check-equal? (message-extra-info-session got-extra) "s1")
  (check-equal? (message-extra-info-auth got-extra) ai)
  (check-false  (message-extra-info-http-req-info got-extra))
  ```
- `on-message` with `#f` extra (unauthenticated path):
  ```racket
  (set! got-extra 'unset)
  ((transport-on-message s) msg #f)
  (check-false got-extra)
  ```
- `on-close`: `(set-transport-on-close! s (λ () (set! closed? #t)))` → `((transport-on-close s))` → `(check-true closed?)`.
- `on-error`: set handler → invoke with `(make-exn:fail "boom" (current-continuation-marks))` → assert captured error.

**Part 5 — `message-extra-info` field surface + zero-arg:**
- `(define ei (make-message-extra-info #:session "s1" #:auth ai #:http-req-info #f))` → field accessors check.
- `(define ei0 (make-message-extra-info))` → all three fields `#f`.

**Part 6 — contract rejection (C1):**
- `(check-exn exn:fail:contract? (λ () (make-message-extra-info #:session 42)))`.
- `(check-exn exn:fail:contract? (λ () (make-message-extra-info #:auth "not-auth-info")))`.
- `(check-exn exn:fail:contract? (λ () (make-transport-send-options #:related-request-id 'sym)))` (symbol not in `(or/c #f string? exact-integer?)`).
- `(check-exn exn:fail:contract? (λ () (make-transport-send-options #:resumption-token 99)))`.

**Part 7 — `transport-session-id` accessor:**
- `(check-equal? (transport-session-id s) "sess-1")`.

**Part 8 — `transport-send-options` field surface:**
- `(define opts (make-transport-send-options #:related-request-id "req-1" #:resumption-token "tok"))` → accessors correct.
- `(define opts0 (make-transport-send-options))` → both `#f`.

---

## Dependencies

- **S1** (`mcp/core/main.rkt`): `json-object?` (for the `msg` contract in `transport-send`); error types.
- **S2 auth** (`mcp/core/shared/auth.rkt`): `auth-info?`, `make-auth-info` — used in `message-extra-info`'s `auth` field and in the test.
- **`racket/generic`**, **`racket/contract`**: stdlib; no external packages.
- First L1 module (first `mcp/transport/` file). No existing transport collection to conflict with.

---

## Decisions & Trade-offs

- **`define-generics` first-arg constraint** — Racket's `define-generics` requires
  the generic name (here: `transport`) to appear as the first by-position argument
  identifier in every method signature (e.g., `(transport-start transport)` not
  `(transport-start t)`). This was discovered at compile time and fixed before first
  test run. All method signatures in both the generic declaration and `#:methods`
  blocks use `transport` as the dispatch parameter name.

- **`transport-send` arity / `define-generics` optional-arg limitation** — `define-generics`
  does not cleanly support optional positional arguments in method signatures. The
  chosen solution: declare an internal 3-arg generic `%transport-send` (opts always
  required at dispatch level); expose a public `transport-send` wrapper function with
  `[opts #f]` default. Concrete types implement `%transport-send`. This gives callers
  2-arg AND 3-arg call sites (C4 test) without fighting the macro. `%transport-send`
  is NOT in the `provide` list; only `transport-send` (the wrapper) is public.

- **Sink representation** — generic getter/setter methods (`transport-on-message` +
  `set-transport-on-message!` etc.) declared in `define-generics`. No `transport-base`
  convenience struct provided at the port layer; adapters own their field layout and
  wire these generics to their own mutable fields. Keeps the port minimal and avoids
  forced inheritance.

- **Default-raise for unimplemented methods** — `define-generics` raises `exn:fail`
  by default for missing method impls. This is the chosen behavior; no explicit
  `#:defaults` overrides were added. Incomplete stubs are caught at first call (C2
  test validates this).

- **`related-request-id` INERT documentation** — the "inert until S6a/M8" note lives
  in (a) the module-level doc comment at the top of `transport.rkt`, (b) inline on
  `%transport-send` in the generic declaration, and (c) inline on the
  `transport-send-options-related-request-id` field struct comment.

- **`http-req-info` as `(or/c #f json-object?)`** — TS `MessageExtraInfo.request`
  is `globalThis.Request` (a live HTTP object). Racket holds a wire-safe jsexpr map
  per the portability NFR (`net/url` not used at this layer). Unchanged from spec.

- **`message-extra-info.session` — Racket-specific addition** — TS `MessageExtraInfo`
  does not have a `session` field; TS exposes session via `sessionId` on the Transport
  object. The Racket `session` field co-locates session context alongside auth for the
  `on-message` handler (sanctioned by queue-003.md). It is distinct from
  `transport-session-id` (per-transport accessor). This divergence is intentional.

---

## Completion Reminder

After `raco test mcp/transport/test/` passes:

1. Open `docs/aide/progress.md`.
2. Find the M6 deliverable row (`mcp/transport/transport.rkt`) — flip 📋 → 🚧 → ✅.
3. Check the Stage-S2 acceptance box for the transport port item.
4. Do NOT flip parity-matrix, catch-all `raco test`, or demo boxes (those belong to items 017/018/022).
