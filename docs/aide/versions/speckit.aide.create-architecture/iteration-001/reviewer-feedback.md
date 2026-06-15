# Architecture Review Report — `racket-mcp` Iteration 001

**Reviewed:** `docs/aide/versions/speckit.aide.create-architecture/iteration-001/architecture.md`
**Against vision:** `docs/aide/vision.md`
**Date:** 2026-06-14

## Executive Summary

This is a strong, disciplined architecture document. It is well-structured, stays at the correct altitude (modules/interfaces/communication without prematurely binding implementation), and traces nearly every vision feature to a module via an explicit coverage matrix (§3.3/§3.4). The tech stack is internally consistent and faithful to the vision's tech-stack table. The main gaps are a handful of MCP protocol primitives that the vision implies but the module decomposition does not explicitly own — most notably resource-subscription *update* notifications, list pagination (cursors), and batch message assembly. None are structural redesigns; they are additions to existing module interface lists. Recommended next step: a targeted revision closing the primitive-coverage gaps below, after which this is ready for the roadmap step.

## Strengths

- **Explicit, bidirectional coverage trace.** §3.3 and §3.4 map every vision §4 feature and Appendix-A capability to modules *and* assert every module traces back to vision scope, including a deliberate "no module created" statement for the six §8 exclusions. This is exactly the verification a reviewer needs and it is rare to see done well.
- **Correct architectural altitude.** The doc states up front (line 9) that it stops short of implementation detail and that naming is illustrative of interface *shape*. It holds to this consistently — interfaces are described by responsibility, not signature.
- **The hexagonal port choice is well-justified and load-bearing.** The `gen:transport` port (M6) and the validator/verifier provider ports are tied directly to the portability NFR and to test doubles (M10), not adopted decoratively. The callback-inversion seam (M6 communication) is correctly identified as the core eventing mechanism.
- **Concurrency model is concrete and consistent.** Green threads + id-keyed in-flight registry + channels/`sync` + per-request custodian/`cancel-evt` is described identically in §1.2, M11, and the tech stack — and it directly answers the "no head-of-line blocking" and cancellation NFRs.
- **Data-flow paths (§3.2) validate the decomposition.** F1–F8 trace realistic runtime flows through the modules; F3 (server-initiated requests reusing the same engine) is a good demonstration that the composition-over-inheritance model actually works for sampling/elicitation.
- **Tech stack consistency with the vision is excellent.** Every row in architecture §4 matches the vision §5.1 table; no technology is introduced that the vision did not sanction, and the Zod→contract / Ajv→single-provider collapses are carried through faithfully.

## Critical Issues 🔴

None. There is no structural flaw, vision contradiction, or missing layer that blocks proceeding to a roadmap. The issues below are coverage gaps in interface lists, not architectural defects.

## Major Issues 🟡

### J1. Resource-subscription *update* notifications are not owned by any module
- **Location:** M12 (§2, lines 157–166), §3.4 coverage row "4.3 High-level server API".
- **Problem:** The client (M13) exposes `subscribe-resource`/`unsubscribe-resource` (vision §4.4, line 87). The companion server obligation — emitting `notifications/resources/updated` when a subscribed resource changes — is absent. M12 lists only list-changed (tool/resource/prompt) + logging notifications (line 160, 164). Subscription is half-wired: a client can subscribe but no module is responsible for the server-side update emission or the subscription bookkeeping.
- **Why it matters:** "All MCP primitives implemented … resources (static + templated) … each with passing tests" is Success Criterion §9.4 of the vision. A subscribe with no corresponding update notification fails conformance for the resources primitive.
- **Recommendation:** Add a resource-update notification + subscription-tracking responsibility to M12's external Notification interface (e.g. "resource-updated emitter; tracks active subscriptions per session"). Add a coverage line for it in §3.4.

### J2. List pagination (cursors) is unaddressed
- **Location:** M12/M13 list interfaces; §3.2 F1/F2.
- **Problem:** MCP `*/list` operations (`tools/list`, `resources/list`, `prompts/list`, `resource-templates/list`) are cursor-paginated in the spec. No module interface mentions cursor handling on either the server (producing `nextCursor`) or client (following it) side. The vision lists the verbs (§4.3/§4.4) without naming pagination, so this is easy to miss, but the wire types include cursors.
- **Why it matters:** Wire-protocol parity (G1) and interop with reference clients (G2) require correct cursor semantics; a TS client paging through a `racket-mcp` server's tool list will break if cursors are unhandled.
- **Recommendation:** Note pagination as a responsibility in the M12 registration/list path and the M13 client list verbs (e.g. "list verbs surface/consume opaque pagination cursors"). It may live inside the role modules rather than as a new module — but it should appear in an interface description so the roadmap accounts for it.

### J3. JSON-RPC batch assembly/disassembly has no owner
- **Location:** M1 (line 67, mentions "batch" envelopes), M11 engine.
- **Problem:** M1 declares batch envelopes among the wire shapes, but no module is responsible for splitting an inbound batch into individual dispatches or assembling outbound batched responses. The engine (M11) describes single request/response correlation only.
- **Why it matters:** If batch is in the type layer but unhandled in the engine, it is a latent parity gap. (Note: confirm against the target spec revisions — `2025-11-25`/`2026-07-28` may have removed JSON-RPC batching, in which case M1 should *drop* the batch envelope rather than the engine adding handling. Either way the doc is currently internally inconsistent: batch is a type with no processor.)
- **Recommendation:** Resolve the inconsistency in one direction — either give M11 an explicit batch fan-out/fan-in responsibility, or remove batch from M1 if the targeted spec revisions dropped it. Cite the spec revision in the decision.

## Minor Issues 🔵

### N1. "Normalization seam / façade" for versioned specs is asserted but its boundary is thin
- **Location:** M1 internal interface (line 72), §4.1 cross-cutting decision (line 319).
- **Problem:** The version-agnostic façade is the mechanism that lets M11/M12/M13 "negotiate version once and operate version-agnostically." But where two spec revisions *differ in shape* (e.g. the `2026-07-28` `_meta` envelope, `UrlElicitationRequired`/URL-mode elicitation), a façade implies a normalized superset or a lossy projection. The doc does not say which, and that choice has real downstream consequences.
- **Why it matters:** Not blocking, but the roadmap will need to know whether handlers see a normalized model or branch on version.
- **Recommendation:** One sentence stating the façade strategy (normalized superset vs. version-tagged variants). Could fold into the §5 open-questions list if intentionally deferred.

### N2. Where SSE resumption tokens are *issued/correlated* is underspecified at the interface level
- **Location:** M8 (line 120, 123), §5 open question 3 (line 329).
- **Problem:** Storage strategy is correctly deferred (line 329). But the *interface* responsibility — who mints a resumption token, who validates it on reconnect, how it ties to the on-message `related-request-id` — is part of M6's `send` options and M8's internal handling, and is only gestured at. The vision's Reliability NFR (line 213) makes resumable streams a hard requirement.
- **Recommendation:** Confirm M8's internal HTTP/SSE interface explicitly lists "mint + validate resumption token" as a responsibility (the storage *backend* stays deferred). Distinguish the interface obligation from the deferred storage decision.

### N3. M12 bundles three TS modules under one "M" number
- **Location:** M12 (lines 157–166) covers `server.rkt`, `mcp.rkt`, and `completable.rkt`.
- **Problem:** Cosmetic, but M12 conflates low-level Server, high-level McpServer, and Completable into one module entry while elsewhere (M5a–e) the doc splits cohesive helpers into sub-numbers. The asymmetry makes the completions responsibility easy to overlook in the coverage trace.
- **Recommendation:** Either give completable its own sub-letter (M12c) for symmetry with M5, or leave as-is but ensure the roadmap treats low-level vs high-level server as separable deliverables.

## Suggestions 💡

### S1. State the engine↔role contract as an explicit "no inheritance" invariant
The doc says composition over inheritance (line 41, 150, 318) — strong and correct. Consider stating the *invariant* that roles never reach into engine internals (in-flight registry, scheduler are M11-internal per line 147), only through the three external engine interfaces. This protects the composition boundary during implementation.

### S2. Ping/keepalive and connection-health are implied but unnamed
`ping` appears in M13 (line 170). Consider noting whether the engine/transport has any keepalive responsibility, or whether ping is purely an application-level verb. Minor, and arguably an implementation detail.

### S3. Consider a one-line note on logging-level filtering location
`set-logging-level` (M13) and `send-logging-message` (M12) exist, but which side enforces the level filter (server drops below-threshold messages) is unstated. Low priority — could be an M12 internal detail.

## Vague Language Audit

The document is notably concrete; the vision's "all objectives measurable" discipline carried through. Few issues:

| Phrase | Location | Note / suggested tightening |
|--------|----------|------------------------------|
| "near-pure" helpers | M5 communication (line 102) | Acceptable, but clarify which M5 helper has a side effect (likely none — if so, say "pure"). |
| "ergonomic" register-* | M12 (line 160) | Fine as intent; the G4 contract/keyword/struct criteria already make "ergonomic" measurable elsewhere. No change required. |
| "mimics the async event timing of real transports" | M10 (line 134) | Slightly vague; "introduces a thread/channel hop so message delivery is asynchronous like real transports" would be crisper. Non-blocking. |
| "thin specializations" | §1.1 (line 41) | Defined immediately after via composition + generics, so acceptable. |

No instances of unqualified "scalable / robust / flexible / simple" used as a substitute for a real requirement. Good.

## Verification Against the Four Mandated Criteria

1. **All vision requirements covered by modules — MOSTLY.** §3.4 traces every §4 feature and Appendix-A row. Gaps are at the *primitive* sub-feature level, not the feature level: resource-update notifications (J1), pagination (J2), and the batch inconsistency (J3). Spec-version negotiation, both transports, both roles, OAuth (client+server), sampling, elicitation (form+URL), roots, completion, logging, progress, cancellation are all owned.
2. **Interfaces at sufficient granularity (internal + external) — YES.** Every module separates Internal vs External interfaces with responsibilities, and §3.3 summarizes internal-vs-external comms per module. The port/callback inversion (M6), engine handler-context (M11), and provider ports (M3/M14) are all defined at the right granularity for a structural doc. J1/J2 are missing *responsibilities on otherwise-defined interfaces*, not missing interface definitions.
3. **No implementation details enforced — YES.** The doc explicitly disclaims implementation detail (line 9) and holds to it. Naming is illustrative; field types, control flow, and concrete signatures are absent. Deferred decisions are parked in §5. This criterion is well satisfied — arguably the document's strongest dimension.
4. **Tech stack consistent — YES.** Architecture §4 matches vision §5.1 row-for-row; the green-threads/contracts/std-lib-only stance is uniform across §1.2, M11, §4, and §4.1. No contradictory or unsanctioned technology introduced. SSE-over-`web-server` streaming (line 308) is the one place the doc commits slightly beyond the vision, but consistently and justifiably.

## Vision Alignment Score

**9 / 10.** The architecture is a faithful structural realization of the vision: the 1:1 TS-mirror collection layout, the public/internal boundary, the ports-and-adapters core, the contract-vs-JSON-Schema validation split, and the six exclusions are all carried through exactly as the vision specifies, with explicit traceability. The single point held back is the primitive-level coverage gaps (J1–J3) that touch Success Criteria §9.2/§9.4 (full conformance, all primitives) — small in size but directly on the vision's central objective of wire-protocol parity and interop.

## Recommended Next Steps

1. **Close J1 (resource-update notifications)** — add the server-side `resources/updated` emitter + subscription tracking to M12's interface and a §3.4 coverage row. (Highest priority: it is a half-wired primitive touching §9.4.)
2. **Address J2 (pagination)** — add cursor handling as a responsibility on the M12/M13 list interfaces. (Required for G1/G2 parity.)
3. **Resolve J3 (batch)** — decide per the target spec revision whether the engine handles batch or M1 drops the batch envelope; record the decision with a spec citation.
4. **Add one sentence each for N1 (façade strategy) and N2 (resumption-token interface obligation)**, or move them explicitly into §5 open questions if deferral is intentional.
5. After 1–3, this document is ready to drive the roadmap step; the minor items and suggestions can be folded in opportunistically.
