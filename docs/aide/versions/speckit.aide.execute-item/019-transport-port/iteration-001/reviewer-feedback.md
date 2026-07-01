# Reviewer Feedback — Item 019: Transport port (`gen:transport`, M6)

**Iteration:** 001
**Verdict:** GREEN-LIGHT (approved, no revision required)
**Overall rating:** 9.5 / 10

Files reviewed:
- `mcp/transport/transport.rkt` (152 lines)
- `mcp/transport/test/transport-test.rkt` (155 lines)
- Spec: `docs/aide/items/019-transport-port.md`

Build/test (re-confirmed against source): imports clean, contracts present, exports complete. Team-lead verified `raco test` → 31 passed, `raco make` → exit 0.

---

## Review focus — findings

### 1. `gen:transport` + optional-opts hazard (the reviewer-flagged risk) — RESOLVED CORRECTLY
The optional positional-arg limitation of `define-generics` is handled by the **right** mechanism, not papered over:
- Internal 3-arg generic `%transport-send transport msg opts` (opts always required at dispatch level) — `transport.rkt:100`.
- Public wrapper `(define (transport-send transport msg [opts #f]) (%transport-send transport msg opts))` — `transport.rkt:117-118`.
- `%transport-send` is correctly **excluded** from `provide`; only the wrapper `transport-send` is public (`transport.rkt:128`).

This guarantees BOTH 2-arg and 3-arg call sites dispatch to the concrete impl. Concrete types implement `%transport-send` (3-arg), confirmed in the stub at `transport-test.rkt:24`. Mechanism is sound, not test-coincidental.

All ten generic methods present and dispatch on `transport` as first positional id (the `define-generics` first-arg constraint, correctly observed in both the declaration and `#:methods` blocks).

### 2. Callback sinks — CONFORMS
Getters (`transport-on-message/-close/-error`) + setters (`set-transport-on-message!` etc.) declared as generics (`transport.rkt:104-109`); concrete stub wires them to its own `#:mutable` fields (`transport-test.rkt:27-33`). `on-message` carries the 2nd `extra` arg — invoked at `transport-test.rkt:87` `((transport-on-message s) msg ei)` and asserted on both args.

### 3. `define/contract` enforcement (C1) — ENFORCED, not decorative
Both smart constructors use `define/contract` with `->*` keyword contracts:
- `make-message-extra-info` — `(or/c #f string?)` / `(or/c #f auth-info?)` / `(or/c #f json-object?)` (`transport.rkt:43-52`).
- `make-transport-send-options` — `(or/c #f string? exact-integer?)` / `(or/c #f string?)` (`transport.rkt:68-75`).
Rejection tests (`transport-test.rkt:131-138`) feed `#:session 42`, `#:auth "not-auth-info"`, `#:related-request-id 'sym`, `#:resumption-token 99` and assert `exn:fail:contract?`. These would FAIL if a plain `define` or a wrong contract were used — non-vacuous.

### 4. `related-request-id` inert-but-defined — CORRECT
Defined, not stripped. Documented as INERT until S6a/M8 in three places per the Decisions section: module doc comment (`transport.rkt:8-11`), inline on the generic (`transport.rkt:80-84`), and inline on the field struct (`transport.rkt:58-60`). Stub accepts-and-ignores; tests pin both string and integer values (`transport-test.rkt:64-68`).

### 5. Imports + provide surface — CONFORMS
`require` is `racket/generic racket/contract ../core/main.rkt ../core/shared/auth.rkt` only (`transport.rkt:19-22`). Grep confirms NO `net/url`, `racket/system`, `subprocess`, sockets/`racket/tcp`, or `web-server` (the only hits are doc-comment mentions in the NO-list). `json-object?` resolves via `core/main.rkt` → `types/main.rkt` re-export; `auth-info?`/`make-auth-info` via `(struct-out auth-info)` + `make-auth-info` in `auth.rkt:67-68`. `provide` is explicit (no `all-defined-out`) and lists every name required by the acceptance criteria (`transport.rkt:123-152`).

### 6. Falsifiability of key tests — NON-VACUOUS
- **C2 (partial-stub default-raise):** `partial-transport` omits `%transport-send` (`transport-test.rkt:38-41`); `(transport-send pt msg)` routes through the wrapper to the unimplemented generic, which raises the `define-generics` default `exn:fail`. Would NOT raise if the wrapper swallowed errors or a non-raising `#:defaults` existed — genuinely exercises the default-raise path.
- **C3 (extra-info shape + #f-extra):** asserts `got-msg`, `message-extra-info?` predicate, each field accessor (`transport-test.rkt:89-93`), AND the `extra = #f` unauthenticated path resetting `got-extra` to `#f` (`:96-98`). The `'unset` sentinel makes the `#f` assertion meaningful (distinguishes "handler not called" from "called with #f").
- **C4 (2/3-arg + string/integer rid):** 2-arg, 3-arg-all-#f, 3-arg-string, 3-arg-integer all covered (`transport-test.rkt:56-68`). Drops the wrapper default → 2-arg fails; drops a contract branch → integer/string fails.

### 7. Decisions & Trade-offs — REAL
Seven substantive decisions documented (first-arg constraint, `%transport-send` wrapper, sink representation, default-raise, INERT doc placement, `http-req-info` as jsexpr map, `session` as Racket-specific addition). These reflect actual design choices made during implementation, not boilerplate.

---

## Minor observations (NOTE-level, non-blocking)

- **[NOTE]** `transport?` predicate is provided (`transport.rkt:126`) and used by the C-pred test (`transport-test.rkt:54`) but is not listed in the spec's explicit `provide` enumeration (criterion at spec L85). It is auto-generated by `define-generics` and its inclusion is correct/necessary — this is the impl being more complete than the literal list, not a deviation. No action.
- **[NOTE]** `transport-test.rkt` requires `auth.rkt` via `(file "../../core/shared/auth.rkt")` directly rather than through the `core/main.rkt` barrel. Fine for a test needing `make-auth-info`, and matches the spec's Testing Strategy (L130). No action.

---

## Conclusion
Meets every acceptance criterion. The flagged `define-generics` optional-arg hazard is resolved at the mechanism level (internal generic + public wrapper), and the C1–C4 tests are falsifiable. Approve as-is.
