# Reviewer feedback — Item 005 (Public types + N1 normalized-superset façade)

**Artifacts reviewed**
- `mcp/core/types/types.rkt` (1476 lines)
- `mcp/core/types/test/types-test.rkt` (349 lines)
- new fixtures under `mcp/core/types/test/fixtures/`
- against spec `docs/aide/items/005-public-types-and-normalized-superset-facade.md`
- cross-checked against `spec-2025-11-25.rkt` and `spec-2026-07-28.rkt` struct definitions.

**Verdict: 8.5 / 10 — APPROVE, no revision required.**

This is a high-quality implementation. The analytical core (the §4 field-by-field
shared / 2025-only / 2026-only classification) is correct in every place I spot-checked
against the actual delivered structs, the N1 wire-parity refusal rule is implemented
consistently, and the test suite genuinely exercises the queue's core testable claim with
non-vacuous, hand-authored fixtures. The four documented deviations are all legitimate
representation choices, not gaps. Findings below are advisory.

---

## 1. Acceptance-criteria conformance

I walked the acceptance checklist (spec lines ~445–513) and the §4 Group 0–8 inventory.
Genuinely met:

- **Module shape / imports.** `#lang racket/base`, `racket/contract`, `prefix-in r25:/r26:`,
  `(only-in "spec-2025-11-25.rkt" absent absent? present?)`, explicit curated `(provide …)`
  with no `all-defined-out`. ✔
- **Shared `absent` from one place, re-exported.** Imported from 003 only and re-exported;
  the test asserts `(eq? absent r25:absent)` AND `(eq? absent r26:absent)` (lines 312–313). ✔
- **`absent` for other-revision-only fields.** Verified in every normalizer: e.g.
  `normalize-facade-tool-from-2026` passes `absent-field` for `exec` (line 558);
  `normalize-facade-list-tools-result-from-2025` sets `ttl-ms`/`cache-scope`/`result-type`
  to `absent-field` (line 591). ✔
- **Denormalize RAISES on a present field absent from the target revision (N1 parity).**
  `refuse-if-present` is applied consistently in the to-2025 result denormalizers (ttl-ms,
  cache-scope, result-type), the to-2026 tool denormalizer (execution), the elicit params
  (task AND meta), call-tool params (task / input-responses / request-state), and
  list-roots (meta + non-empty rest). ✔
- **Revision-parameterized dispatch.** `dispatch-table` is keyed on `(cons method revision)`,
  and `(dispatch-for method revision)` resolves the matching `(parser . normalizer)` pair —
  a bare `hash[method]` would be wrong, and this is not that. Both-revisions methods
  (`tools/call`, `resources/read`, `prompts/get`, `completion/complete`,
  `sampling/createMessage`, `roots/list`) have TWO distinct entries; single-revision methods
  resolve only for their home revision and return `#f` otherwise. The test asserts the two
  `tools/call` pairs are not `eq?` in both car and cdr (lines 276–277) and that each yields
  the correct revision-shaped façade (lines 279–284). ✔
- **Per-primitive `meta` type (C1/C2).** This is the headline divergence and it is handled
  correctly:
  - `facade-request-meta` envelope is the `meta`-field type for CLIENT request params ONLY
    (call-tool / read-resource / get-prompt / complete). ✔
  - `create-message` carries a PLAIN shared `meta` + 2025-only `task`; the test asserts
    its 2026 meta is `json-object?` and NOT `facade-request-meta?` (lines 157–159). ✔
  - Both `elicit-*` carry NEITHER `task` NOR `meta` in 2026 (both 2025-only); the test
    asserts both absent on the 2026 façade and that the 2025 meta is not the envelope
    (lines 144–147). ✔
- **Round-trip lossless on home revision, incl. `rest` (C4).** Part 2 round-trips both
  revisions of list-tools and call-tool params back to `jsexpr=?` with the fixture, and
  asserts the unknown top-level key AND `_meta` survive on both revisions (lines 194–199).
  The cross-revision `rest` pass-through is isolated correctly (named 2026-only fields
  cleared via `struct-copy`, rest kept) and asserted not to raise (lines 204–210).
  Empty-rest-is-`{}`-not-`absent` and no-phantom-`_meta` are asserted (lines 213–220). ✔
- **Cross-revision refusal + symmetric pass.** Part 3 covers task, ttl/result-type,
  execution, elicit task/meta, list-roots meta, a 2025-only standalone (initialize ↛ 2026),
  a 2026-only standalone (discover ↛ 2025), and the all-absent-denormalizes-to-both pass.
  The bare-shape emissions are asserted exactly: elicit → `{mode,message,requestedSchema}`
  (line 235), list-roots → `{roots}` (line 240). ✔
- **Presence-vs-revision-capability (Part 5).** A 2026 list-tools result that legitimately
  omits `resultType` normalizes to `absent` (same sentinel as 2025), does not crash, and
  re-denormalizes to 2026 (lines 299–305). The optional-absent == revision-absent identity
  is also asserted on `tool.title` (lines 316–317). ✔

**`facade-read-resource-result` next-cursor (deviation #6) — confirmed correct against code.**
`spec-2026-07-28.rkt:915` is `(struct read-resource-result (contents next-cursor ttl-ms
cache-scope meta result-type rest))`; `spec-2025-11-25.rkt:716` is `(contents meta rest)`.
So `next-cursor` IS genuinely 2026-only on this primitive, and the implementer correctly
modeled it as such and refuses it on `denormalize-...-to-2025` (line 713). The spec's §4
Group-2 table omitting it is the table's error, not the code's; the code is right.

---

## 2. Ruling on the four documented deviations

**(a) 58 façade structs vs the spec's ~75–85 estimate — ACCEPTABLE.**
The implementer modeled the diverging *substance* (params and result shapes) as concrete
façade structs and represented the thin request/notification ENVELOPE wrappers (Group-5
`facade-tools-call-request` etc. = method literal + payload) via the params façades plus the
superset union contracts. The spec's ~75–85 number explicitly counted those envelope wrappers
as separate structs. Nothing *testable* is missing: every primitive whose shape actually
diverges across revisions has a full 4-function seam; the envelopes that would have been
mechanical method-string + payload wrappers add no normalization logic and no present/absent
matrix. The dispatch table already routes by method string, which is what an envelope wrapper
would have provided. This is a sound S1 representation choice. (Note the §4 estimate was always
hedged as an estimate; the spec even says "record the exact count".)

**(b) `subscriptions/listen` omitted from the dispatch table — ACCEPTABLE (S1 cut).**
Its 2026 params wrap a `subscription-filter` + envelope, which the façade does not yet model as
a single params façade. The implementer DID provide `facade-subscription-filter` for the
superset, and correctly chose not to register a mismatched parser/normalizer pair in the
dispatch table (registering one that doesn't actually produce a unified params façade would be
worse than omitting it). Reasonable; S3's protocol engine can add it when the params façade is
modeled. Not a wire-parity violation.

**(c) `facade-read-resource-result` next-cursor as 2026-only — CORRECT (see §1 above).**
Verified against `spec-2026-07-28.rkt:915` / `spec-2025-11-25.rkt:716`. The deviation from the
spec table is the spec table being incomplete; the code matches the actual structs.

**(d) `facade-tool-exec` / `facade-tool-annots` field renames — REASONABLE.**
`facade-tool-execution` and `facade-tool-annotations` are already the constructor names of the
sibling façade structs; a same-named accessor (`facade-tool-execution`) would collide at module
level. Shortening the field names to `exec` / `annots` mirrors 003's own `tool-exec` /
`tool-annots` and is the idiomatic fix. The public `/c` and `(struct-out facade-tool)` expose
the accessors consistently. Fine.

---

## 3. Correctness & edge cases — does the suite genuinely test the claims?

The suite is not vacuous. The fixtures are real and exercise the divergence:
- `tools-call-request-task.json` carries `task` AND a flat `_meta` with `progressToken: "p-7"`
  and an `io.modelcontextprotocol/related-task` key, so the 2025-only `task` absence on the
  2026 façade and the flat-`_meta`-into-envelope split are both non-vacuous. The test asserts
  the specific value `"p-7"` lands in `facade-request-meta-progress-token` (line 94) and that
  `related-task` survives into the envelope (line 96) — strong, value-level assertions, not
  just presence.
- `2026-tools-call-request.json` carries `inputResponses` / `requestState` / a reserved-key
  `_meta`, so the 2026-only present assertions and the envelope-population assertions
  (protocol-version / client-info / client-capabilities present, lines 85–87) are real.
- The Group-0 aliasing-trap guard (lines 112–116) confirms a 2026-built `facade-text-content`
  satisfies the SAME predicate as a 2025-built one — the load-bearing "same façade" claim.
- The C4 cross-revision `rest` test correctly isolates the behavior: it clears the named
  2026-only fields so that ONLY `rest` is exercised, proving rest is not refused while the
  named fields would be (contrast with Part 3). This is exactly the discrimination the spec
  demanded.

I found no silently-dropped fields in the normalize/denormalize pairs I traced
(content blocks, tool, list-tools-result, call-tool params, request-meta envelope,
list-roots, elicit params, create-message params). The `rest` field is threaded through
every result struct, which was the explicit 003 failure mode to guard against.

### Advisory findings (none blocking)

- **[MINOR] Part 6 count assertion is `>= 55`, but the inventory is exactly 58.** A `>=`
  threshold three below the actual count weakens the anti-drift purpose of Part 6: a future
  change that silently drops one or two primitives from the `provide`/predicate list could
  still pass. Recommend pinning it to `(check-equal? facade-struct-count 58 …)` (or at least
  `>= 58`) so a dropped primitive fails the count. The hand-enumerated predicate list mitigates
  this somewhat (a dropped struct would also fail to compile if the predicate were referenced),
  but the assertion itself should be tight.

- **[MINOR] `facade-request-meta` reserved-field contracts are very loose.** `client-info`
  and `client-capabilities` are typed `(opt/c any/c)` and `protocol-version` is `(opt/c
  string?)`. `any/c` accepts anything including a malformed value; since the façade composes
  003/004 parsers that already validate, this is defensible at S1, but a follow-up could tighten
  `client-info` to `facade-implementation/c`-or-absent once normalization of that nested value
  is decided. Note today the envelope stores `client-info` as the raw 2026 value passed through
  (`facade-request-meta-from-2026`), not a normalized `facade-implementation` — acceptable for
  S1 but worth a comment so a later layer doesn't assume it's a façade struct.

- **[NOTE] `facade-request-meta-from-2025-flat` reserved-key split.** The 2025 flat-`_meta`
  splitter only special-cases `progressToken` and the `related-task` key; every other key
  (including any future reserved key) lands in `rest`. That matches the spec (2025 carries only
  those two as shared), and the round-trip reconstructs them, so it is correct. Just flagging
  that the reserved-key list is duplicated knowledge (the symbols are re-declared locally at
  lines 835–837 rather than imported from constants.rkt); if constants.rkt grows the reserved
  key set, these will need manual sync. Low risk at S1.

- **[NOTE] `denormalize-facade-list-roots-result-to-2025` supplies `(hasheq)` for an absent
  `rest`** (line 810). Correct — the 2025 struct requires a hash — but worth noting this is the
  one place a façade-side default is synthesized rather than passed through; it is consistent
  with the empty-rest-is-`{}` convention.

---

## 4. Idiomatic Racket / public-surface discipline

- Explicit curated `(provide …)` grouped by §4 group, no `all-defined-out`. ✔
- Helper kit (`copy-opt`, `absent-field`, `refuse-if-present`, `refuse-primitive`) is internal,
  not provided. ✔
- Fresh `facade-` structs everywhere (no 003/004 internal struct leaked as the public surface);
  the Group-0 "convert both revisions" decision (S5) is honored — no aliasing. ✔
- `#:transparent` structs, flat `struct/c` / `or/c` contracts, predicates `?`, contracts `/c`,
  consistent kebab-case matching 003/004. No JS-isms. ✔
- The `prefix-in` mechanic is used exactly as the spec's key build constraint requires.

The only readability nit: the file is mechanical and very long (1476 lines), but that is
inherent to realizing a structural union as concrete code, and the section banners keep it
navigable. Naming is consistent throughout.

---

## Summary

The implementation meets every acceptance criterion I could verify, the four documented
deviations are all justified representation choices (one of them — read-resource next-cursor —
is the code being *more* correct than the spec table), and the test suite is non-vacuous with
value-level assertions on the hard cases. The advisory findings (tighten the Part-6 count
assertion; loose envelope contracts; reserved-key duplication) are quality follow-ups, not
correctness or wire-parity gaps. No revision required.
