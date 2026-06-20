# Roadmap Review — Iteration 001

**Reviewer:** roadmap-reviewer (aide-roadmap team)
**Date:** 2026-06-15
**Artifact:** `docs/aide/versions/speckit.aide.create-roadmap/iteration-001/roadmap.md`
**Reviewed against:** `docs/aide/vision.md`, `docs/aide/architecture.md` (M1–M17, L0–L4), MCP TS SDK v2 reference (`typescript-sdk/`).

---

## Vision Coverage Score: 88%

The roadmap is strong: it follows the architecture's layer build-up (L0→L4) faithfully, every stage ends in a demonstrable + testable artifact, the dependency graph respects the "lower layers never import higher" invariant, and per-stage parity-matrix discipline keeps G1/G3 continuously satisfied instead of dumping all conformance into S9. Every vision Goal (G1–G8) and every Success Criterion (§9.1–§9.8) is traceable to at least one stage's acceptance gate, and every architecture module M1–M17 is placed. The 12% gap is driven by a handful of concrete protocol-ownership omissions, two genuinely oversized stages, and several under-specified acceptance gates — all listed below. None are structural; all are fixable by editing stage text, not by re-deciding the architecture.

I verified the load-bearing wire claims against the TS checkout and they hold: `LATEST=2025-11-25`, `DEFAULT_NEGOTIATED_PROTOCOL_VERSION=2025-03-26`, full `SUPPORTED_PROTOCOL_VERSIONS` (`constants.ts:1-3`); no `JSONRPCBatch`/`isJSONRPCBatch` anywhere in `packages/` (J3 correct); error codes `-32002/-32003/-32004/-32042` all present (`enums.ts:25`, `spec.types.2026-07-28.ts:366,374`, `spec.types.2025-11-25.ts:189`); in-memory async-delivery model and ping/`logging/setLevel` server ownership confirmed (`server.ts:117,237,406`).

---

## Critical Gaps

1. **`initialize` handler ownership is never assigned to a stage.** S5 (line 197) says the low-level `Server` "owns protocol-utility handlers (`ping`, `logging/setLevel` ownership stub)" but never names `initialize`. In the TS reference the low-level server owns `initialize` and runs version/capability negotiation server-side (`server.ts:108`, `server.ts:363`). The engine (S4) provides the negotiation *machinery* (§4.1 façade gate), but the *handler that responds to an inbound `initialize`* is a server-role responsibility and must be an explicit S5 deliverable. As written, a reader could build S5's client `connect` (which sends `initialize` and reads the negotiated version, client.ts:425-446) with no server endpoint registered to answer it — the S5 demo would not run.

2. **`logging/setLevel` is owned in S5 but its behavioral effect is deferred to S7 with no bridge.** S5 line 197 calls it a "`logging/setLevel` ownership stub"; S7 line 267 implements the per-session logging-level filter. That is a reasonable split, but neither stage states the contract between them: what does the S5 stub *do* with the level (store it? ignore it?), and does S7 only add the filter or also the per-session storage? Spell out that S5 accepts + records the level (no-op filter) and S7 adds the at-or-above-level gating, so the handoff is testable on both sides.

3. **`core/types/errors.ts` (wire-error decode) is not mapped.** S1 line 76 maps `mcp/core/errors.rkt` to "`errors/sdkErrors.ts` + `auth/errors.ts`". But the TS checkout has a *third, distinct* error module — `packages/core/src/types/errors.ts` — that decodes a JSON-RPC error object back into the correct typed error (e.g. a `-32042` payload into `UrlElicitationRequiredError`, `errors.ts:23-26,46-48`). This is precisely the "exn↔JSON-RPC mapping, **both directions**" that S1's own testing criterion (line 78) and architecture §4.1 demand. The roadmap's S1 source-map omits it, so the decode-direction logic has no named home. Add `types/errors.ts` to the S1 M2 source list (or state it is folded into `errors.rkt`) and confirm the round-trip test covers the `-32042`/`-32004` *decode* path, not just encode.

4. **Elicitation URL-mode error surfacing has no producer.** S7 line 263/277 has the *client* "surface `UrlElicitationRequired`" — but `UrlElicitationRequiredError` is *raised by the server* when a tool needs URL elicitation (`mcp.ts:156`), then decoded by the client. The roadmap only describes the client-receive side. Either the server-raise side belongs in S6/S7 high-level-server work and is missing, or it is implicitly covered — but it is not stated. Clarify which stage implements the server emitting `-32042`.

---

## Milestone Critique

| Milestone | Issue | Reasoning | Suggested Fix |
|-----------|-------|-----------|---------------|
| **S6** | Too big | Explicitly two tracks (6A real transports: M7 stdio + M8 Streamable HTTP + M9 web-server adapter; 6B high-level server: M12b + M12c + completions + pagination + handle lifecycle). M8 alone (SSE, sessions, Host/Origin validation, **N2 resumption token mint/validate/replay**) is a full week; stdio is another sub-week; M12b with register-tool/resource/prompt + handle enable/disable/update/remove + J2 pagination is another. The roadmap admits parallelism but a single-agent week is not credible. | Split into **S6a (transports: M7+M8+M9)** and **S6b (high-level server: M12b+M12c)** as numbered stages, both depending on S5, both feeding S7. This matches the architecture's N3 note that M12a/M12b/M12c are "independently-shippable units" and makes each ~1-week and independently demonstrable. The dependency graph already draws them as separate nodes — make the numbering match. |
| **S7** | Too big | Bundles sampling, elicitation (form+URL), roots, resource subscriptions with per-session fan-out (J1), client-side pagination (J2), per-session logging filter (S3), AND progress+cancellation end-to-end across both roles. That is 6–7 distinct primitive flows, several with their own session-state machinery (subscription table, logging-level table). | Split along the server-state boundary: **S7a** = client-driven server-initiated flows (sampling, elicitation, roots) + client cursor-following; **S7b** = server-side session-scoped state (subscription table + resource-updated fan-out J1, per-session logging filter S3) + progress/cancel role wiring. Each is one demonstrable week. |
| **S5** | Under-detailed | "demonstrating the **first cross-SDK interop** … against a TS SDK endpoint over in-memory/stdio bridging **where feasible**" (line 190) and line 209 "over stdio if the real transport lands here, **else document the bridge used and defer**". The success of the project's first-interop milestone is gated on a bridge mechanism that is left undefined and may be deferred — so S5 can "pass" without actually achieving cross-SDK interop. | Make the S5 interop gate binary and concrete: either (a) pull a *minimal* stdio client adapter forward into S5 so the Racket client can spawn the TS example server over stdio (the TS examples are stdio-runnable), or (b) explicitly redefine S5's interop as Racket-client↔Racket-server only and move the *first* cross-SDK leg to S6a where stdio lands. Do not leave "where feasible." |
| **S2** | Under-detailed (one item) | The default JSON-Schema validator's supported-subset is the single largest correctness risk for tool I/O (F8) and the architecture (§5) leaves hand-rolled-vs-library open. S2 line 120 says "document any unsupported keywords explicitly" but sets no minimum bar. | Add an explicit acceptance criterion: enumerate the *required* JSON-Schema keyword subset (the keywords the TS example tool schemas actually use — object/properties/required/type/enum/string-format at minimum) and require those to validate identically to a TS baseline. Otherwise "supported subset" is unfalsifiable. |
| **S9** | Under-detailed (examples) | §9.8 / S9 line 323 claims "runnable mirrors of the TS examples" as "five categories," but the TS checkout has ~17 server + ~13 client example sources, including `inMemoryEventStore.ts` (the N2 resumption store), `customProtocolVersion.ts`, and `multipleClientsParallel.ts`. | Either keep five as an explicit, named *curated subset* (state that it is a subset, not a mirror) or expand. As written, "mirroring the TS examples set" overstates coverage and §9.8's gate is ambiguous. |

---

## Detail Requirements (sizing OK, specificity lacking)

- **S6 N2 resumption — backend vs interface.** S6 line 226 correctly fixes the mint/validate/replay *interface obligation* and says "token-storage backend = in-memory for this stage (pluggable store deferred)." Good — this matches architecture §5/N2. But the acceptance test (line 241) only checks replay; add an explicit note that the *pluggable-store seam* (not just the in-memory impl) is part of the M8 interface so S9's `inMemoryEventStore` example and any future store drop in without an M8 change.

- **S3/S4 boundary — `related-request-id` on `send`.** The transport port (S3, line 136) carries `related-request-id` + resumption-token on `send`, but nothing in S3–S5 exercises `related-request-id` (it matters for SSE stream routing of server-initiated requests). Note where it first becomes load-bearing (S6 HTTP / S7 server-initiated-over-HTTP) so S3's port shape is validated against a real consumer rather than only by the in-memory adapter that ignores it.

- **S8 independence from S7 is asserted but the handler-context dependency is unverified.** S8 line 302 says "Independent of S7." Server auth injects `AuthInfo` into the engine handler context (F7), which is built in S4 — so this is correct. State that dependency explicitly (S8 needs S4's handler-context + S6a's M8 bearer-extraction seam, not S7) so the parallelization claim is auditable.

- **Progress/cancellation: engine vs role split.** S4 builds engine-level progress/cancel; S7 line 268 "wire the role-level surfaces." Name the concrete role surface (client `call-tool` progress callback + cancellation token; server handler-context `signal` + progress emitter) in the S7 deliverables list, not just the testing criteria, so the deliverable is self-contained.

---

## Logical Progression / Dependency Check (passed, with notes)

- Layer ordering L0(S1,S2)→L1-port(S3)→L2(S4)→L3-mvp(S5)→L1-real+L3-high(S6)→primitives(S7)→auth(S8)→L4(S9) is correct and never inverts the architecture §3.1 arrows. Verified.
- S4 binding the M6 port and testing over the M10 in-memory pair (line 172) is the right call — engine is provable before any real transport. Good.
- The "composition, not inheritance" invariant (architecture S1) is correctly surfaced as an S4 acceptance gate (line 181). Excellent — this is the kind of architectural invariant that usually gets lost in roadmaps.
- One real ordering issue beyond the S5/S6 splits above: **S2 includes M5e stdio framing, but S3 line 142 explicitly says M5e is "not needed here"** and stdio framing is first used in S6. Building M5e in S2 is fine (it is L0 shared), but flag that it sits untested-by-a-consumer until S6 — or move it to S6a beside M7 where it is exercised. Currently it is a two-stage-orphaned deliverable.

---

## Direct Instructions for Roadmap Worker

1. **Add `initialize` handler ownership to S5** as an explicit M12a deliverable (low-level server answers `initialize` and runs server-side capability/version negotiation). Without it the S5 demo does not run.
2. **Split S6 into S6a (transports M7+M8+M9) and S6b (high-level server M12b+M12c)** — renumber downstream stages or use S6a/S6b. Both depend on S5; both must land before S7.
3. **Split S7 into S7a (client-driven: sampling, elicitation, roots, client cursor-following) and S7b (server session-state: subscription table+J1 fan-out, S3 logging filter, progress/cancel wiring).**
4. **Make S5 cross-SDK interop binary** — remove "where feasible"/"else defer." Either pull a minimal stdio client into S5 or redefine S5 interop as Racket-only and move the first cross-SDK leg to S6a.
5. **Map `core/types/errors.ts` (wire-error decode) into S1's M2 source list** and require the round-trip test to cover the *decode* direction (`-32042`→`UrlElicitationRequiredError`, `-32004`→unsupported-version error).
6. **Name the stage that implements the server *raising* `-32042` UrlElicitationRequired** (currently only the client-receive side is described, in S7).
7. **Specify the `logging/setLevel` S5-stub→S7-filter contract** (S5 records the level as a no-op; S7 adds at-or-above gating).
8. **Add a concrete JSON-Schema keyword subset to S2's acceptance criteria** (minimum: type/object/properties/required/enum/string-format) validated against a TS baseline.
9. **Clarify S9 examples scope** — declare five as a curated subset (not a full mirror) or expand toward the ~17 TS server examples; explicitly include the `inMemoryEventStore` resumption example to exercise N2's pluggable-store seam.
10. **Annotate M5e framing's first real consumer** (S6a/M7) so it is not an orphaned S2 deliverable, and note where `related-request-id` on the transport `send` first becomes load-bearing.
11. **State S8's true dependencies explicitly** (S4 handler-context + S6a M8 bearer seam; *not* S7) to make the "independent of S7" parallelization claim auditable.

---

**Overall:** A well-structured, vision-aligned roadmap that earns its 88% on layering discipline and continuous parity-checking. Needs revision before execution, primarily to (a) close the four protocol-ownership gaps and (b) split the two oversized stages (S6, S7) so the ~1-week-per-stage discipline the roadmap claims is actually true. The fixes are edits to stage text, not architectural rework.
