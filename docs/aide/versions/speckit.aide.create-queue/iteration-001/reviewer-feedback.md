# Reviewer Feedback — Queue 001 (Iteration 001)

**Snapshot reviewed:** `docs/aide/versions/speckit.aide.create-queue/iteration-001/queue-001.md`
**Reviewed against:** `docs/aide/vision.md`, `docs/aide/roadmap.md`, `docs/aide/progress.md`, and the `speckit.aide.create-queue` SKILL format requirements.
**Verdict:** Needs revision (substantive sizing + scope-boundary problems, not nitpicks).
**Overall rating:** 6/10.

---

## Summary

This is a genuinely strong first queue in most respects. It correctly identifies that progress is all-📋 and starts at the bottom of the dependency graph (S1, L0). The layer-dependency ordering is impeccable: every item depends only on items earlier in the queue (S1 has no deps; S2 depends only on S1). Numbering is correct (sequential 001–010, zero-padded, no gaps, no duplicates; correct for a first queue). The format is correct — every item is a `### Item NNN: Title` block followed by a description. Testability is stated for every item and is concrete (named test files, TS-fixture cross-checks). The detail-requirement fidelity to the roadmap is excellent: N1 façade (item 004), J3 no-batch-guard (item 002), the bidirectional encode/decode error mapping with the -32042/-32004 decode cases (item 005), the M5e "orphaned until S6a" note (item 010), the validator minimum keyword set (item 007), and the restricted-load portability test (item 006) are all faithfully carried through.

The problems that push this to "needs revision" are **sizing and batch-scope**, not correctness. In short: this queue tries to deliver **all of Stage S1 plus all of Stage S2** in ten items, and two of those items (003 and 007) are each multi-day efforts on their own. The result is a batch that is closer to two weeks than one, with two under-sized items masking two over-sized ones.

---

## What is correct (keep it)

1. **Stage selection and entry point.** Starting at S1 because progress is all-📋 is exactly right. The "Why this batch" section correctly reasons from the dependency graph.
2. **Layer-dependency ordering.** No item depends on an un-built layer. Within the queue, item 004 (types façade) sensibly follows 003 (per-revision specs); 005 (errors) can stand alone; 006 (barrels) correctly comes after 001–005; the S2 items (007–010) all sit on top of S1. Clean.
3. **Numbering / format / no duplicates.** Sequential 001–010, three-digit, `### Item NNN: Title` throughout. Matches the SKILL format block exactly. First queue correctly starts at 001.
4. **Detail-requirement fidelity.** Listed above — the roadmap's "flashpoint" requirements are all present and correctly attributed. This is the strongest part of the queue.
5. **Testability.** Every item names where tests live and what they assert, with TS-checkout cross-checks where the roadmap calls for them.

---

## Substantive issues (require revision)

### Issue A — The batch is ~two weeks, not ~one. (Sizing / week-sized-batch)
The queue explicitly scopes "Stage S1 in full, then early Stage S2 (M3, M4, M5a–M5e)." But that "early S2" is in fact **the entirety of S2's module list** — M3, M4, M5a, M5b, M5c, M5d, M5e are every module S2 defines. So this is not "S1 plus a head start on S2"; it is "S1 + S2 complete." The roadmap sizes **each** of S1 and S2 as roughly one week on its own (see roadmap "sized to be deployable locally in roughly one week" applied per stage, and the stage table treating S1 and S2 as separate stages). Folding both into one ten-item queue is the core problem and is what forces the under-sizing in Issue B.

**Recommendation:** Scope this queue to **Stage S1 only** (items 001–006), and add ~3–4 more genuinely S1-sized items by decomposing the two oversized items (below) so the batch is a full, well-sized week of L0-part-1 work. Defer M3/M4/M5 (S2) to queue 002. If the team prefers to keep some S2 in this batch, then S1's oversized items must be split and the S2 tail trimmed to one or two modules — but you cannot have both "all of S1+S2" and "one week."

### Issue B — Item 003 is too large (needs decomposition).
"Per-revision structs + flat contracts for **every** request, response, notification, and error type in **each** of two revisions" is the single biggest modeling task in the whole foundation. The TS `spec.types.*.ts` files are large; reproducing every message shape as a struct + contract, for two revisions, with `_meta` envelope handling, round-trip tests, and contract-rejection tests, is multiple days by itself. Bundling both revisions into one item also hides progress and makes the item hard to mark done incrementally.

**Proposed split:**
1. **Item: spec types — 2025-11-25 revision** — structs + flat contracts for every request/response/notification/error in `spec.types.2025-11-25.ts`; round-trip + contract-rejection tests.
2. **Item: spec types — 2026-07-28 revision** — same for the RC revision, including the `_meta` reserved-key envelope fields it introduces; round-trip + contract-rejection tests, plus a test asserting the RC-only fields are present.

This split also makes the dependency for item 004 (the N1 façade) cleaner: the façade unions two now-independently-verified revision modules.

### Issue C — Item 007 bundles two modules (M3 provider port + default provider) and is too large.
Item 007 implements both the `racket/generic` provider **port** (`provider.rkt`) and the **default Racket-native provider** (`from-json-schema.rkt`) — the latter being a hand-rolled JSON-Schema subset evaluator across `type`/`properties`/`required`/`enum`/`items`/`format`, each cross-checked against a TS Ajv baseline. The default provider alone is a substantial, edge-case-heavy implementation. (This only needs splitting if S2 work stays in this queue; if S2 is deferred per Issue A, fold the split into queue 002.)

**Proposed split (for whichever queue carries S2):**
1. **Item: validator-provider port** — `provider.rkt` only: the `gen:`-style interface (compile schema → validator; validate → ok/errors) plus a trivial conformance test against a stub provider.
2. **Item: Racket-native default provider** — `from-json-schema.rkt`: the documented keyword subset with the ≥1-accept/≥1-reject-per-keyword Ajv-cross-checked suite; unsupported-keyword documentation.

### Issue D — Item 010 bundles two unrelated M5 concerns **and** carries the S2 demo. (Cohesion / sizing)
Item 010 lumps `auth.rkt` (M5d — pure structs/helpers, tiny) with `stdio.rkt` (M5e — byte-stream framing with partial-frame buffering, non-trivial and I/O-touching), and then also tacks on "the S2 demo script." These are three different things; M5d is trivially small while M5e + the demo are not. The demo as written ("register a JSON Schema → validate … expand/match a URI template … encode/decode a stdio frame") depends on items 007, 009, and 010 all being done — so it is really a stage-closeout artifact, not part of one module item. (Again, contingent on S2 staying in scope.)

**Recommendation:** Separate M5d (can join the other tiny M5a–c shared-utils item) from M5e (its own item, given the framing/buffering logic and that it is the lone I/O module). Make the S2 demo its own small closeout item (mirroring how item 006 is the S1 closeout/demo), depending on the S2 module items.

---

## Minor observations (non-blocking)

- **Item 006 double-duties as barrels + portability test + S1 demo.** This is acceptable as an S1 closeout item (it parallels how the roadmap groups the S1 demo with the load test), and none of the three sub-parts is large, so I am **not** requiring a split — but flag it: if the restricted-namespace load test proves fiddly, consider promoting it to its own item.
- **Output path note (informational, not the queue's fault).** The SKILL says the live queue lives at `docs/aide/queue/queue-NNN.md` and is snapshotted into the iteration dir. I reviewed the snapshot as instructed; just confirming the canonical copy should also exist at `docs/aide/queue/queue-001.md`.
- **Cross-checking against the TS checkout.** Several items assert byte-for-byte / Ajv-baseline parity against `typescript-sdk/`. Good. Worth ensuring the Worker actually has that checkout available; if it does not, those acceptance criteria become unverifiable. (Not a queue defect — an execution prerequisite.)

---

## Recommendation to team-lead

Revise. The fix is primarily **re-scoping** (drop S2 to queue 002 so this is a clean, full S1 week) **plus two decompositions** (item 003 → per-revision split; and, wherever S2 lands, item 007 → port/default split and item 010 → M5d/M5e/demo split). The technical content and detail-fidelity are already very good, so this should be a fast revision: no item needs to be rewritten for correctness, only resized and rehomed.
