# Reviewer Feedback — `racket-mcp` Vision (iteration-001)

**Reviewer:** vision-spec-reviewer (team "aide-vision")
**Date:** 2026-06-14
**Document reviewed:** `docs/aide/versions/speckit.aide.create-vision/iteration-001/vision.md`
**Reference:** MCP TypeScript SDK v2.0.0-alpha (`typescript-sdk/`)

---

## Verdict

**Status: APPROVED (with minor polish notes).**
**Rating: 9 / 10. needs_revision: false.**

This is an exhaustive, specific, and — most importantly — *factually accurate* vision. I verified its concrete claims directly against the TS SDK checkout rather than taking them at face value, and they hold up. This document clears the high bar for a vision artifact: it defines the *what* and *why* with measurable objectives, it names the *how* concretely enough to be actionable, and it faithfully reflects the TS SDK v2 architecture in Racket idioms. Every issue raised in the previous round (the stale rating-6 `reviewer-feedback.json` at repo root) has been resolved. The remaining notes below are refinements, not blockers; none of them should hold up progression to the architecture phase.

---

## What I verified against the TS SDK (and that checked out)

I treated the vision's specific claims as testable assertions and checked each against `typescript-sdk/`:

- **Package set.** `core`, `client`, `server`, `middleware`, `server-legacy`, `codemod` — all present, all at `2.0.0-alpha`. Correct.
- **`core/types` file mapping.** `constants.ts`, `enums.ts`, `guards.ts`, `types.ts`, `spec.types.2025-11-25.ts`, `spec.types.2026-07-28.ts` all exist exactly as the vision claims in §4.1 and §5.2.
- **`core/shared` mapping.** `protocol.ts`, `transport.ts`, `stdio.ts`, `uriTemplate.ts`, `toolNameValidation.ts`, `metadataUtils.ts`, `auth.ts` + `authUtils.ts` — all present; the vision's `auth.rkt ↔ auth.ts + authUtils.ts` collapse is justified.
- **Error codes (§4.1).** Every code is correct against `enums.ts`: `ParseError -32700`, `InvalidParams -32602`, `ResourceNotFound -32002`, `MissingRequiredClientCapability -32003`, `UnsupportedProtocolVersion -32004`, `UrlElicitationRequired -32042`. No fabricated codes.
- **Protocol version constants (§4.1).** Exactly right per `constants.ts`: `LATEST_PROTOCOL_VERSION = '2025-11-25'`, `DEFAULT_NEGOTIATED_PROTOCOL_VERSION = '2025-03-26'`, and `SUPPORTED_PROTOCOL_VERSIONS` containing the older revisions. The `_meta` per-request envelope is correctly attributed to revision `2026-07-28`.
- **Module homes.** `server/mcp.ts`, `server/server.ts`, `server/completable.ts`, `client/client.ts`, `client/middleware.ts`, `{client,server}/streamableHttp.ts`, `{client,server}/stdio.ts`, `core/util/inMemory.ts`, `core/validators/{types,fromJsonSchema}.ts`, `core/errors/sdkErrors.ts`, `core/auth/errors.ts` — all located where the vision says.
- **Exclusion reasoning.** `codemod` (no v1 to migrate from), `server-legacy` SSE, per-framework middleware (Express/Hono/Fastify confirmed under `middleware/`), Zod/Standard-Schema lib compat, and the browser/workerd/Deno shims (`shimsBrowser.ts`, `shimsWorkerd.ts`, `cfWorkerProvider.ts` all confirmed present in TS) are each excluded with a sound, runtime-specific rationale.

This level of correspondence is exactly what "strictly mirrors the TS SDK" should mean, and it is rare to see a vision get the constants and error codes right.

## Strongest parts

1. **Measurable objectives (§2).** G1–G8 each pair an objective with a concrete measure (conformance suite, Inspector flow, parity matrix, `raco pkg install` success). This is the antidote to weasel-word visions.
2. **The parity matrix as the governing artifact (§9.1, Appendix A).** Making a `done / partial / intentionally-excluded` matrix the definition of "complete" gives the whole project a single, auditable source of truth and operationalizes the "mirror the TS SDK" goal.
3. **Idiom translation is principled, not literal (§4 intro, §5.1, G4).** Kebab-case, `?`-predicates, `!`-mutators, `racket/contract` over Zod, `racket/generic` `gen:transport` over a TS interface, threads/channels over Promises. The vision explicitly rejects JS transliteration (G4, Constraint) and backs it with a concrete tech-stack table.
4. **Public/internal boundary (§5.2).** Correctly identifies the TS `core/public` vs internal-barrel split and mirrors it via `main.rkt` curated `provide` + runtime-neutral root rule. This is a subtle architectural property most visions miss.
5. **Concurrency model is named (§5.3, §6).** The previous round flagged "no concurrency model"; this version specifies per-request id hash, channel/`sync` resolution, and `cancel-evt`/custodian cancellation — addressing it head-on.

---

## Minor polish notes (non-blocking — for the architecture phase, not a revision gate)

1. **Client-side legacy SSE (`client/sse.ts`) is unaddressed.** The vision excludes legacy SSE by pointing only at the `server-legacy` package (§8). But the *current* `client` package still ships `client/sse.ts` (a v1 SSE client transport with its own `SseError`). A client that wants to talk to legacy-only servers needs it. Recommend one sentence in §8 clarifying that the client-side SSE transport is *also* out of scope (and the consequence: `racket-mcp` clients cannot connect to pre-Streamable-HTTP servers), or scoping it in. Right now a reader could infer the exclusion is server-only.

2. **The Zod schema layer (`types/schemas.ts`, `types/specTypeSchema.ts`) has no explicit Racket analogue.** §4.5/§5.2 map `types.ts` to contracts, but in TS the *runtime* validation of protocol messages lives in a separate `schemas.ts` (Zod schemas) distinct from the static `types.ts`. The vision's "contracts replace Zod" is the right call, but it would be stronger to state explicitly that `mcp/core/types/types.rkt` (or a sibling) absorbs *both* the TS `types.ts` static types *and* the `schemas.ts` runtime validators into contracts, so the parity matrix has a home for `schemas.ts` rather than it silently disappearing.

3. **Transport relocation is a real divergence — call it out as one.** The vision puts the `Transport` interface at `mcp/transport/transport.rkt`, whereas TS keeps it at `core/shared/transport.ts`, and groups all transports under a top-level `transport/` collection rather than inside client/server packages. This is a defensible Racket grouping, but it is a *deviation* from the strict 1:1 mirror the document promises elsewhere. Add a half-sentence in §5.2 acknowledging this as an intentional regrouping (with the rationale: transports are cross-cutting), so the parity matrix doesn't read as a mismatch.

4. **`server/validators/{ajv,cfWorker}.ts` and `core/util/zodCompat.ts`.** These exist in TS and are implicitly covered by the "single Racket-native provider" decision (§4.5) and the Zod-compat exclusion, but they aren't named. A one-line note that these specific files map to "intentionally-excluded / collapsed" rows keeps the parity matrix exhaustive.

5. **Performance NFR (§6) still leans slightly soft.** "Dominated by JSON parsing, not SDK bookkeeping" plus "establish a baseline benchmark" is good and much improved, but it has no number. Consider naming the *form* of the target (e.g., "SDK overhead per stdio round-trip recorded and gated against regression in CI; absolute target set once the baseline exists"). This is the one remaining place the language is qualitative — acceptable for a vision, worth tightening at architecture time.

---

## On the prior round

The stale `reviewer-feedback.json` at repo root (rating 6) listed: vague success metrics, missing JSON-RPC error-handling strategy, no TS→Racket paradigm mapping, no enumerated MCP methods, no concurrency model. All five are now resolved — measures are quantified (§2), error codes and malformed-message handling are specified (§4.1, §6 Reliability), the paradigm mapping is explicit (§4 intro, §5.1), every MCP primitive is enumerated (§9.4, §4.4), and the concurrency model is described (§5.3). Per the team-lead's instruction, that root file is stale and untouched.

---

## Bottom line

Approve and proceed to architecture. The five notes above are refinements to fold in during `create-architecture`, not reasons to send the vision back. This document is genuinely exhaustive, specific, and faithful to the TS SDK v2 architecture.
