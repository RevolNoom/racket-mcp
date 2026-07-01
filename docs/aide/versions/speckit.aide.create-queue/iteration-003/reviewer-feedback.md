# Reviewer feedback — queue-004 (Stage S4 Protocol engine, iteration-003)

**Verdict: APPROVE (no revision required).** This is a strong, faithful S4 batch. Numbering, sizing, surface coverage, dependency gating, scope discipline, and format are all correct. The issues below are minor refinements, none of which are genuine gaps, errors, or mis-scoping.

---

## 1. Sequential numbering — PASS

Items run **024 → 029**, six items, contiguous, continuing cleanly after queue-003's reserved 019–023. No gaps, no duplicates, no overlap with prior queues. The header (line 8) states the rationale explicitly and correctly. queue-003 ends at 023; queue-004 starts at 024. Confirmed.

## 2. Item-count reconciliation — PASS

The header "Sizing: 6 items" (line 9), the "Why this batch" prose enumeration (line 17: scheduler/outbound → dispatch/context → negotiation → ported tests → portability sweep → demo+closeout = 6 units), and the six `### Item NNN` headings all agree. No count drift — the recurring speckit "Sizing-vs-prose-vs-headings" mismatch is **not** present here.

## 3. Independent testability — PASS (anti-pattern avoided)

The recurring "impl item whose only gate is 'module loads' with real tests pushed to a later item" defect is **absent**:

- **024** ships its own core suite inline (response correlation by id, timeout-rejects-and-reaps, cancellation via `cancel-evt`/custodian + reap, notification with no id/resolver) and is explicitly "extended by item 027" — the validated house pattern (own tests inline, extended later), mirroring queue-003 item 020.
- **025** extends `protocol-test.rkt` with handler-invocation, notification-handler, method-not-found-keeps-running, full handler-context surface, and a server-initiated `send-request` round-trip — all substantive, all in-item.
- **026** extends with out-of-capability rejection (outbound SDK error / inbound JSON-RPC error), supported-version-accepted-and-recorded, `UnsupportedProtocolVersion`, and one-shot negotiation — substantive, in-item.
- **027** is a deliberate consolidation/port pass; its genuinely net-new assertions (N-concurrent no-HOL-blocking, malformed-inbound→JSON-RPC-error-no-crash) are the two load-bearing S4 NFRs (Concurrency + Reliability), correctly given their own item per house style (parallels queue-003 item 021).

Every item's "Testable:" clause verifies that item's substantive deliverable, not merely that it loads.

## 4. Full S4 deliverable-surface coverage — PASS

Cross-checked against roadmap S4 deliverables (lines 170–178) and acceptance criteria (lines 184–191):

| S4 deliverable / criterion | Covered by | OK |
|---|---|---|
| Outbound `request` (id assign, response resolver, timeout, progress cb, cancellation) | 024 | ✓ |
| Outbound `notification` (fire-and-forget, no id/resolver) | 024 | ✓ |
| Internal id-keyed in-flight registry + thread/channel/`sync` scheduler + per-request custodian + `cancel-evt` | 024 | ✓ |
| Handler-registration (request + notification handlers keyed by method) | 025 | ✓ |
| Inbound response/error routing to in-flight resolver; `notifications/progress`→originating callback | 025 | ✓ |
| Handler-context mirroring `RequestHandlerExtra` (cancel signal, `send-notification`/`send-request`, request-id, session, HTTP info) | 025 | ✓ |
| S8 `AuthInfo` seam left extensible (F7); `send-request`/`related-request-id` inert-in-S4 seam | 025 (+ batch note line 21) | ✓ |
| `assert-capability-for-method` guards; out-of-capability rejection | 026 | ✓ |
| Version negotiation vs `SUPPORTED_PROTOCOL_VERSIONS`; `UnsupportedProtocolVersion`; one-shot at `initialize`; gates N1 | 026 | ✓ |
| Ported `protocol.test.ts` subset (correlation/timeout/cancel/progress/concurrency/server-initiated/malformed) | 027 | ✓ |
| No-HOL-blocking asserted directly (Concurrency NFR) | 027 | ✓ |
| Malformed→JSON-RPC error, engine survives (Reliability NFR) | 027 | ✓ |
| Composition invariant — engine standalone, no role subclassing | 028 (+ every test constructs engine directly) | ✓ |
| Portability sweep (no subprocess/socket/web-server) | 028 | ✓ |
| Parity-matrix touch `protocol.ts`→`partial` | 028, confirmed 029 | ✓ |
| Two-engine in-memory demo (request/reply, out-of-order concurrent, timeout, cancellation) | 029 | ✓ |

Nothing in the S4 surface is missing.

## 5. No spill into S5 — PASS

The batch is scoped tightly to M11. Critically, **item 026 explicitly defers the `initialize` *handler* to S5** ("the actual `initialize` handler is a role concern deferred to S5 — keep this item to the reusable guard/negotiation surface, no role code"), keeping only the reusable negotiation *machinery* in S4. This is exactly the M11/M12a boundary in the roadmap (S5 line 206 owns the `initialize` handler). Every item repeats "no role code" and the batch notes (line 27) bar pulling in `server`/`client`/subprocess/socket/`web-server`. No S5 leakage.

## 6. Dependency gating — PASS

The dependency gate is stated forcefully and accurately (lines 19, 27): S4 depends on S1 (types/errors), S2 (utils), and **S3 — binding the M6 port (item 019) and testing over the M10 in-memory pair (item 020)** — and "Do not begin S4 work until items 019–023 are ✅." This matches roadmap S4 dependencies (line 181). Note that per progress.md the M10 adapter (item 020) is still `📋`, so the gate is real and correctly asserted. The forward-seam flags (lines 21) for the `AuthInfo` hook, `send-request`/`related-request-id`, and N1-gating correctly prevent the Worker from stripping inert-but-load-bearing structure.

## 7. Format — PASS

Parseable `### Item NNN: Title` headings + single descriptive paragraph each, matching the queue-003 house style exactly. Header block (source vision/roadmap/progress/reference, stage focus, queue number, sizing) mirrors queue-003. Line references in the header (roadmap S4 = 164–195; progress S4 section) resolve correctly.

---

## Minor refinements (non-blocking)

These do **not** warrant revision but would tighten the batch:

1. **Item 028 parity-matrix wording may misdirect the Worker.** It instructs "update the roadmap §9 / `docs/aide/progress.md` parity-matrix row for `protocol.ts` (M11) to `partial`." Per the executed precedent recorded in **progress.md item 017** ("Roadmap §9 has **no materialized parity table** — the row names appear only in the `roadmap.md:131` S2 acceptance line + module bullets"), there is no parity *table* in roadmap §9 to edit. The actual parity state is tracked in the progress.md **"Parity matrix progression"** prose section (where items 010–017 each appended a sentence). The Worker should record `protocol.ts`→`partial` there, and may touch the roadmap S4 acceptance line (191) which already reads "Parity matrix row for `protocol.ts` marked `partial`." Recommend rewording 028 to point at the progress.md "Parity matrix progression" prose and note the absence of a materialized roadmap table, so the Worker does not hunt for a table that does not exist. (Mitigating: this is verbatim the wording approved in queue-003 item 022, so it is a house-style carry-over rather than a new defect.)

2. **Item 029 omits the S4 acceptance-box line numbers.** queue-003's closeout (item 023) cited the exact progress.md S3 box lines ("lines 106–111"). Item 029 says only "flip the Stage S4 acceptance boxes" without the reference. The S4 boxes live at progress.md **lines 123–132** and the Stage S4 status row in the overview table is **line 30**. Recommend citing these so the closeout edit is unambiguous. (Minor; arguably omitting line numbers is more drift-resistant.)

3. **Item 027 is partly a restatement of 024–026 tests.** Its only net-new scenarios are no-HOL-blocking and malformed-input; correlation/timeout/cancel/progress/server-initiated were already landed inline in 024–026. This is acceptable (it is the consolidation/port item per house style, paralleling queue-003 item 021, and the two net-new cases are the load-bearing NFRs), but the item could state more explicitly that its *new* value is the concurrency + reliability NFR assertions and that the rest is the consolidated ported suite, to avoid the impression of duplicated work.

---

## Summary

- **Queue health: 6/6 items Ready.** All four review criteria (clear input, clear output, verifiable `raco test` expectation, sub-multi-day granularity) are met on every item.
- **Numbering, count, surface, scope, gating, format: all correct.**
- **Three minor refinements** (parity-matrix wording, closeout line refs, 027 framing) — stylistic/clarity only, no genuine gap or mis-scope.
- **needs_revision: false.**
