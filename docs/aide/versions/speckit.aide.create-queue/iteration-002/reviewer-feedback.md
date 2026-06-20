# Reviewer Feedback — Queue 001 (Iteration 002, revision of Iteration 001)

**Snapshot reviewed:** `docs/aide/versions/speckit.aide.create-queue/iteration-002/queue-001.md`
**Reviewed against:** `docs/aide/vision.md`, `docs/aide/roadmap.md`, `docs/aide/progress.md`, the `speckit.aide.create-queue` SKILL format requirements, and my iteration-001 feedback.
**Verdict:** Ready — no revision required.
**Overall rating:** 9/10.

---

## Summary

This revision resolves every substantive issue I raised in iteration 001, cleanly and without introducing new problems. The queue is now correctly scoped to a single roadmap stage (S1), the two oversized items are split sensibly, the demo is its own closeout item, and the queue went a step beyond what I asked by also splitting the error layer into encode and decode paths — which improves both sizing balance and incremental testability. The result is a well-sized, correctly ordered, fully testable one-week S1 batch. I am marking it ready.

---

## Iteration-001 issues — resolution check

- **Issue A (batch was ~two weeks; spanned all of S1 + all of S2).** RESOLVED. The queue is now explicitly "Stage S1 only — M1 + M2," with S2's M3/M4/M5a–e deferred to queue-002. Both the header and the "Why this batch" section state the reasoning (S2's modules constitute the entirety of S2 and would push to ~two weeks). This is exactly the re-scope I recommended.
- **Issue B (item 003 — every message type across BOTH revisions — too large).** RESOLVED. Split into item 003 (revision `2025-11-25`) and item 004 (revision `2026-07-28`, including the `_meta` reserved-key envelope and an explicit RC-only-fields-present test). This is the per-revision split I proposed, and item 004 correctly carries the `_meta`/RC-only assertion.
- **Issue C (item 007 bundled M3 provider port + default provider).** RESOLVED by deferral — that was an S2 item and S2 is now out of this queue. Carry the split recommendation forward to queue-002 (noted below).
- **Issue D (item 010 lumped M5d + M5e + the S2 demo).** RESOLVED by deferral, same as C. Carry forward to queue-002.
- **Bonus improvement beyond the ask:** the error layer is now split into item 006 (hierarchy + ENCODE: exn → JSON-RPC) and item 007 (DECODE: JSON-RPC → typed error, incl. the -32042/-32004 cases and an unknown-code fall-through). I only required the spec-types split; splitting errors too is a good independent call that balances sizing and lets the decode direction be tested on its own.

All four blocking issues are resolved.

---

## Fresh pass on the revised queue (no prior context assumed)

- **Stage / dependency entry point.** Correct — progress is all-📋, so starting at S1 (L0, no dependencies) is right.
- **Layer-dependency ordering.** Clean and internally consistent. 005 (N1 façade) correctly follows 003+004 (the per-revision modules it unions). 007 (decode) correctly extends 006 (which creates `errors.rkt`). 008 (barrels) re-exports 001–007. 009 is the closeout. No item depends on an un-built layer or on a later item.
- **Numbering / format / duplicates.** Items 001–009, sequential, three-digit zero-padded, every one a `### Item NNN: Title` block followed by a description — matches the SKILL format block exactly. First queue correctly starts at 001. No duplicates.
- **Sizing / week-sized batch.** 9 items, each a genuine sub-multi-day S1 unit. The heaviest remain 003 and 004 (structs + contracts for every message kind in a revision), but those are now one revision each, which is appropriate. The error split keeps 006/007 from being trivially small on their own while still being individually testable. The whole batch reads as a realistic one week of L0-part-1 work.
- **Testability.** Every item names its test location and concrete assertions, with TS-checkout cross-checks where the roadmap calls for them (byte-for-byte constants in 001; TS-fixture round-trips in 003/004; TS `core/types/errors.ts` behaviour in 007). The Worker prerequisite (the `typescript-sdk/` checkout must be present) is now stated explicitly in the header — good, that closes the execution-prerequisite gap I flagged last time.
- **Roadmap detail-requirement fidelity.** All S1 flashpoints present and correctly attributed: J3 no-batch-guard (002), N1 façade (005), `_meta`/RC-only fields (004), bidirectional encode/decode with -32042/-32004 (006/007), restricted-namespace portability load test (008), and a public/internal boundary test that asserts an internal-only binding is not re-exported (008 — a nice addition).

---

## Minor / non-blocking observations (do NOT require revision)

1. **006 and 007 both own `mcp/core/errors.rkt`.** 006 creates the file (hierarchy + encode); 007 extends it (decode). They are correctly ordered so this is fine, but note the two items cannot be parallelized and 007 edits a file 006 produced. If the team ever wants more parallelism this is the one coupling point in the queue — acceptable as-is.
2. **Parity-matrix location precision (item 009).** Item 009 says "update the roadmap §9 parity-matrix rows." The roadmap refers to "§9 parity matrix," but the actual capability/parity table lives in vision.md Appendix A (with the roadmap describing per-stage `partial`/`done` progression). When executing 009, make sure the edit lands wherever the project actually maintains those rows so the update is not silently lost. Purely an execution-precision note, not a queue defect.
3. **Carry-forward for queue-002 (S2).** When S2 is queued, apply the iteration-001 decompositions that were deferred here: split the M3 validator-provider port from the default `from-json-schema` provider, and separate M5d (auth structs) from M5e (stdio framing) with the S2 demo as its own closeout item. Flagging so the next queue does not reintroduce those bundles.

None of these blocks the queue.

---

## Recommendation to team-lead

Approve / proceed. `needs_revision = false`. The revision is responsive and clean; the only follow-ups are non-blocking execution notes (parity-matrix edit location) and a carry-forward reminder for the S2 queue (apply the deferred M3/M5 splits there).
