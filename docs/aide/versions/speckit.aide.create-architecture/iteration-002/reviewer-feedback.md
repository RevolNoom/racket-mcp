# Architecture Review Report — `racket-mcp` Iteration 002

**Reviewed:** `docs/aide/versions/speckit.aide.create-architecture/iteration-002/architecture.md`
**Against vision:** `docs/aide/vision.md`
**Prior review:** iteration-001 (9/10, needs_revision; issues J1–J3, N1–N3, S1–S3)
**Date:** 2026-06-14

## Executive Summary

Iteration 002 resolves every issue raised in iteration-001 — all three major coverage gaps (J1–J3), all three minor items (N1–N3), and all three suggestions (S1–S3) — and does so with precision rather than hand-waving. The resolutions are evidence-backed (J3 cites a verifiable grep over the TS checkout, which I independently confirmed), consistent with the rest of the document, and traced into the coverage matrix and data-flow paths. No new issues were introduced and the four mandated criteria are all satisfied. This document is ready to drive the roadmap step.

## Verification of Prior Issues

| Prior issue | Status | Where resolved |
|-------------|--------|----------------|
| **J1** Resource-update notifications unowned | ✅ Resolved | M12b Notification interface item (c): `notifications/resources/updated` emitter + per-session subscription table (created on subscribe, removed on unsubscribe/session-close, session-scoped fan-out). New flow F9. New §3.4 coverage row. Closes Success Criterion §9.4. |
| **J2** List pagination (cursors) unaddressed | ✅ Resolved | M12b registration interface: list ops cursor-paginated, server surfaces opaque `nextCursor` across `tools/list`, `resources/list`, `prompts/list`, `resources/templates/list`. M13 client verbs consume/follow cursors. New flow F10. New §3.4 row. Method name `resources/templates/list` verified correct against TS checkout. |
| **J3** Batch type with no processor (inconsistency) | ✅ Resolved (by removal) | New M1 "J3 — No JSON-RPC batching" note: both target spec revisions removed batch; TS v2 checkout has no `JSONRPCBatch`/`isJSONRPCBatch`/batch handling. M1 envelope list updated to "request/response/notification/error". **I independently confirmed** via grep — no `batch`/`JSONRPCBatch`/`isJSONRPCBatch` in `typescript-sdk/packages/core/src/`. Correct resolution direction. |
| **N1** Façade strategy unspecified | ✅ Resolved | §4.1: normalized-superset façade — handlers see the union of both revisions, revision-only fields present-or-absent and gated by negotiated version; façade refuses to emit a field absent from the negotiated revision (preserves wire parity). Version-tagged variants not exposed to handlers. |
| **N2** Resumption-token interface obligation underspecified | ✅ Resolved | M8 internal interface now mandates mint-token-per-SSE-event + validate/replay-on-reconnect as a fixed interface obligation; client presents last token to resume. §5 clarified: only the storage *backend* is deferred, not the obligation. |
| **N3** M12 bundled three TS modules | ✅ Resolved | M12 split into M12a (low-level Server), M12b (McpServer), M12c (Completable) with explicit separability + roadmap-sequencing note in §5 (M12a prereq for M12b; M12c layers on M12b). |
| **S1** Composition invariant | ✅ Addressed | §4.1 states it as a hard invariant: roles hold an engine instance, never subclass it, never reach into engine internals; sole coupling is M11's three public interfaces. |
| **S2** Ping/keepalive ownership | ✅ Addressed | M12a answers inbound `ping` and owns protocol-utility handlers; M13 issues `ping`; both roles may answer inbound ping. |
| **S3** Logging-level filtering location | ✅ Addressed | M12b applies the per-session logging-level filter set via `logging/setLevel` (owned by M12a), emitting only at/above the client's level. |

## Strengths (carried forward + new)

- **Resolutions are traced, not just asserted.** Each fix lands in the module interface *and* the data-flow table (F9, F10) *and* the §3.4 coverage matrix — the same triangulation discipline that made iteration-001 reviewable is maintained for the new responsibilities.
- **J3 handled by evidence, not assumption.** Resolving the batch inconsistency by *removing* the type — with a cited grep over the authoritative reference checkout — is exactly right. It avoids inventing engine machinery for a feature the target spec no longer has. This is the strongest single improvement.
- **The N1 façade decision is genuinely load-bearing.** "Normalized superset, version-gated, refuse-to-emit-absent-fields" is a real architectural commitment that the roadmap can build against, and it correctly preserves wire parity (a TS client on `2025-11-25` will never receive a `2026-07-28`-only field).
- **M12 sub-lettering now matches M5**, removing the asymmetry and making the low-level/high-level/completable split independently schedulable — useful for the upcoming roadmap.

## Critical Issues 🔴
None.

## Major Issues 🟡
None. All iteration-001 majors resolved; no new majors introduced.

## Minor Issues 🔵

### N4 (new, cosmetic). F4 still lists "list-changed, logging, progress, cancel" without resource-updated
- **Location:** §3.2 flow F4 (notification), line 248.
- **Problem:** Resource-updated notifications now have a dedicated flow (F9), which is correct. But F4's parenthetical enumeration of notification types ("list-changed, logging, progress, cancel") could be read as the exhaustive set and omits `notifications/resources/updated`. Purely a labeling nit — F9 covers the mechanism fully.
- **Recommendation:** Optionally add "resources/updated (see F9)" to F4's parenthetical, or leave as-is since F9 is explicit. Non-blocking.

## Suggestions 💡

### S4. Consider noting cursor *opacity/stability* expectation
M12b/M13 correctly treat cursors as opaque. A one-line note that a cursor is only guaranteed valid against the same server/session (not portable across restarts) would pre-empt an implementation question, but this is arguably an implementation detail and fine to leave for the roadmap.

## Vague Language Audit
No new vague language. The added text (F9/F10, M8 resumption obligation, §4.1 façade) is concrete and measurable. The iteration-001 "near-pure" wording was tightened in M5 communication (line 103) to explicitly separate pure functions (M5a–c), immutable structs (M5d), and the single I/O module (M5e) — a clean improvement.

## Verification Against the Four Mandated Criteria

1. **All vision requirements covered by modules — YES.** The primitive-level gaps from iteration-001 are closed: resource subscribe/update is now fully wired both sides (J1/F9), list pagination is owned on producer and consumer sides (J2/F10), and the batch inconsistency is removed with spec evidence (J3). §3.4 carries explicit rows for each. Feature- and primitive-level coverage is now complete.
2. **Interfaces at sufficient granularity (internal + external) — YES.** New responsibilities are expressed as interface obligations with internal/external split (M8 resumption mint/validate, M12b subscription table + cursor slicing, M12a ping/setLevel ownership). §3.3 updated to reflect M12's per-session subscription table and logging-level filter as internal comms.
3. **No implementation details enforced — YES.** The doc holds its altitude. The new obligations (mint-token-per-event, per-session subscription table, normalized-superset façade) describe *what* the interface must guarantee, not *how* (storage backend, table representation, and provider choice all remain deferred in §5). The line-9 disclaimer still holds.
4. **Tech stack consistent — YES.** §4 unchanged and still matches vision §5.1 row-for-row; no new technology introduced by the revisions.

## Vision Alignment Score

**10 / 10.** With the primitive-coverage gaps closed and every resolution traced and (where claimed) evidence-verified, the architecture is now a complete and faithful structural realization of the vision: full MCP-primitive coverage including subscriptions and pagination, the 1:1 TS mirror, the ports-and-adapters core, the contract-vs-JSON-Schema split, the version-negotiation façade, and the §8 exclusions — all consistent and traceable.

## Recommended Next Steps

1. **Proceed to the roadmap step.** This document is structurally sound and complete; no revision is required to move forward.
2. (Optional, non-blocking) Fold N4 into F4 and S4 into the roadmap when convenient.
3. Keep §5's deferred items (auth sub-module granularity, JSON-Schema provider choice, resumption-token storage backend, M12 sub-module sequencing) on the roadmap's input list — they are correctly parked, not lost.
