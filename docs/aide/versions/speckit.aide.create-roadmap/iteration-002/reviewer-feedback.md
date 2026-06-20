# Roadmap Review — Iteration 002

**Reviewer:** roadmap-reviewer (aide-roadmap team)
**Date:** 2026-06-15
**Artifact:** `docs/aide/versions/speckit.aide.create-roadmap/iteration-002/roadmap.md`
**Reviewed against:** `docs/aide/vision.md`, `docs/aide/architecture.md` (M1–M17, L0–L4), MCP TS SDK v2 reference (`typescript-sdk/`).
**Prior iteration:** 001 (rated 88, needs_revision=true, 11 direct instructions + detail requirements).

---

## Vision Coverage Score: 97%

All eleven iteration-001 direct instructions and every detail requirement are resolved, and resolved *correctly* — not just acknowledged. The two oversized stages are split into genuinely disjoint, parallel, ~1-week halves; the four protocol-ownership gaps now have explicit owners with TS line-references; and the previously-vague gates (S5 interop, S2 validator subset, S9 examples) are now binary and falsifiable. I re-verified the worker's *new* technical claims against the TS checkout and they hold (details below). The remaining 3% is a short list of minor tightenings, none of which block execution.

---

## Resolution of the 11 iteration-001 instructions

| # | Instruction | Status | Evidence in roadmap |
|---|-------------|--------|---------------------|
| 1 | `initialize` handler in S5 | **Resolved** | S5 line 206: M12a "answers the inbound `initialize` request" + runs server-side negotiation, returns `InitializeResult`, refs TS `server.ts:108,363`. Acceptance gate line 221. |
| 2 | Split S6 | **Resolved** | S6a (M7+M8+M9, line 232) and S6b (M12b+M12c, line 262) are separate numbered stages, drawn as parallel disjoint nodes (graph line 43-49), both gated to land before S7. |
| 3 | Split S7 | **Resolved** | S7a (client-driven, M13, line 288) and S7b (server session-state, M12b, line 319), parallel, disjoint role surfaces. |
| 4 | S5 binary interop | **Resolved** | S5 is now explicitly Racket-only (line 199, 225); the first cross-SDK leg is a hard S6a acceptance criterion (line 253) gated on stdio existing. "Where feasible / else defer" removed. |
| 5 | `core/types/errors.ts` decode in S1 | **Resolved** | S1 line 76 names all three TS error modules incl. `core/types/errors.ts`; line 84 specifies the decode direction; line 95 makes the `-32042`/`-32004` decode an explicit test gate. |
| 6 | Server-raise `-32042` stage | **Resolved** | S7b line 330 owns the *raise* side (refs `mcp.ts:156`); S7a line 297 owns the *receive/decode* side; the split is stated on both ends. |
| 7 | `logging/setLevel` contract | **Resolved** | Explicit stub→filter contract: S5 line 208 records the level (no-op filter); S7b line 329 reads it and adds at-or-above gating; the contract is spelled out in a dedicated block (line 214) with tests on both sides. |
| 8 | S2 JSON-Schema subset | **Resolved** | S2 line 112 enumerates the minimum keyword set (`type`, `properties`, `required`, `enum`, `items`, `format` for date-time/uri/email); line 129 requires accept+reject cases per keyword cross-checked against a TS Ajv baseline. |
| 9 | S9 examples scope + inMemoryEventStore | **Resolved** | S9 line 383 declares a *curated subset* (not a full mirror), 7 named examples incl. #7 the `inMemoryEventStore` resumable-HTTP example wired into the M8 event-store seam (line 390). |
| 10 | M5e annotation + related-request-id | **Resolved** | M5e orphaned-until-S6a note (S2 line 118, S6a line 240 "first real consumer"); `related-request-id` first-load-bearing-in-M8 note (S3 line 145, S6a line 241). |
| 11 | S8 deps | **Resolved** | S8 line 362 states the two concrete deps (S4 handler-context + S6a/M8 bearer seam), explicitly "neither S6b nor S7," making the parallel-with-S7 claim auditable. |

**Detail requirements** (N2 store seam, related-request-id load-point, S8 dep audit, progress/cancel role split) are all addressed: the resumption store is now a *port* delivered in S6a (line 243) with a drop-in seam-substitution test (line 255); progress/cancel is split into a concrete client surface (S7a line 300) and server surface (S7b line 331).

---

## Verification of the worker's new technical claims (against `typescript-sdk/`)

The revision introduced two assertions not present in iteration-001. Both check out:

1. **Resumption store as a port with `append-event`/`replay-after`** (S6a line 243). Confirmed: TS `streamableHttp.ts:27` declares `export interface EventStore` with `storeEvent(...)` (line 34) and `replayEventsAfter(...)` (line 46); it is injectable via `eventStore?: EventStore` (line 114); the example `InMemoryEventStore implements EventStore`. The roadmap's `append-event`/`replay-after` naming is a faithful Racket analogue, and "drops in without an M8 code change" matches the TS injection model exactly.

2. **`related-request-id` routes server-initiated messages onto the correct SSE stream** (S3 line 145, S6a line 241). Confirmed: TS `streamableHttp.ts:960` — `send(message, options?: { relatedRequestId?: RequestId })` uses `relatedRequestId` to select the request/stream (lines 961-968). The roadmap's account ("server-initiated requests/responses are routed onto the correct SSE stream by `related-request-id`") is accurate.

Iteration-001's verified constants/codes/J3/ping-ownership facts remain unchanged and correct.

---

## Milestone granularity, dependencies, feasibility (re-check)

- **Granularity.** The S6/S7 splits bring every stage back to a credible ~1-week single-agent unit. S6a (3 transports incl. M8/N2) is still the heaviest stage but is now a defensible week given M5e framing and the M6 port are pre-built and stdio/in-memory ignore `related-request-id`. Acceptable.
- **Dependencies.** Graph is correct and never inverts §3.1. The new parallel edges are sound: S6a∥S6b (disjoint L1 vs L3 modules), S7a∥S7b (disjoint client vs server role surfaces), S8∥S7 (S8 deps stop at S4+S6a). I checked S7a's stated dependency on *both* S6a (real transport for server-initiated sampling over HTTP) and S6b (a producing server to paginate against) — correct, and a subtlety iteration-001 did not force.
- **Feasibility.** No stage now claims an artifact it cannot demonstrate. S5's demo is honest about filtering being deferred (line 228); S6a's demo includes the resumed-stream reconnect; S7b's demo exercises the two-session fan-out.

---

## Remaining minor items (do not block execution; rated 3%)

These are tightenings, not gaps. The worker may address them in-place or defer to queue-generation.

1. **S7a↔S6a circularity smell (cosmetic).** S7a depends on S6a (real transport for server-initiated sampling). But sampling/elicitation are *server-initiated*, so the counterpart server hooks that *send* `sampling/createMessage` are exercised in S7a's tests too — yet S7a's module is M13 (client only). Clarify that S7a's sampling test uses a *test-harness server stub* (or the S6b server with an inline handler) to originate the request, so the reader doesn't expect S7b to exist first. One sentence in S7a dependencies.

2. **S6a "→done" parity claim may be premature for `streamableHttp.ts`.** S6a line 256 marks `streamableHttp.ts` "`partial`→`done` where fully exercised," but server-initiated requests over HTTP (the load-bearing use of `related-request-id`) are not exercised until S7a/S7b. Recommend `streamableHttp.ts` stays `partial` until S7 wires server-initiated flows over it; only the request/response + resumption paths are `done` at S6a. Minor parity-matrix accuracy point.

3. **`cross-app access` (M14 `crossAppAccess.ts`) has no test gate.** S8 lists cross-app access as a deliverable (line 357) and a parity row (line 369) but no acceptance criterion exercises it (the gates cover authorization-code/PKCE/refresh/verification only). Add a one-line gate or note it as advertised-but-not-separately-tested.

4. **Stateless-vs-stateful HTTP server distinction (S9 examples #2/#3) is not traced to an M8 capability.** The curated set assumes M8 supports a sessionless mode; S6a's M8 deliverable mentions session IDs but not an explicit stateless mode. Confirm M8 (S6a) delivers both session-bearing and sessionless operation, or the S9 stateless example has no substrate. The TS SDK supports both (`simpleStatelessStreamableHttp.ts`), so this is likely fine — just make the S6a deliverable say so.

---

## Direct Instructions for Roadmap Worker (optional, non-blocking)

1. Add one sentence to S7a clarifying the sampling/elicitation tests originate the server request via a test stub or S6b server, so S7a reads as genuinely client-only.
2. Keep `streamableHttp.ts` parity at `partial` after S6a; flip to `done` at S7 once server-initiated flows over HTTP are exercised.
3. Add a cross-app-access acceptance gate to S8 (or annotate it as covered-by-parity-only).
4. Make S6a's M8 deliverable explicitly state both session-bearing and sessionless (stateless) operation, to substrate the S9 stateless-HTTP example.

---

**Overall:** This iteration cleanly closes every issue from the first review and adds correct, reference-verified detail in the process. The roadmap is now executable: ten stages, each a demonstrable ~1-week unit, with an auditable parallel structure and falsifiable acceptance gates. The four remaining items are cosmetic/accuracy polish and do not block starting S1. **needs_revision = false** — the listed items can be folded in during queue generation without another full review cycle.
