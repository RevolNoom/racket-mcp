# Reviewer Feedback — Queue 003 (Stage S3: Transport port + in-memory adapter, L1 part 1)

**Artifact:** `docs/aide/versions/speckit.aide.create-queue/iteration-001/queue-003.md`
**Overall rating:** 8.5 / 10
**Needs revision:** Yes — two surgical fixes (one factual inconsistency, one independent-testability gap). Both quick; the queue is otherwise implementation-ready.

---

## Queue Summary

5 items (019–023). 3 Ready, 2 Needs Refinement, 0 Too Large.

- 019 Transport port (M6) — Ready
- 020 In-memory adapter (M10) — Needs Refinement (behavioral tests deferred → not independently verifiable)
- 021 Barrel + test suite — Needs Refinement (absorbs 020's real verification; conflicts with stated item count)
- 022 Portability sweep + parity touch — Ready
- 023 Demo + closeout — Ready

---

## What the queue gets right (verified, not assumed)

- **Scope boundary is correct.** Items cover exactly the roadmap S3 deliverables (`transport.rkt` M6, `in-memory.rkt` M10, `main.rkt` barrel, `in-memory-test.rkt`, portability load test, parity rows, demo). No S4 leakage — protocol engine M11 and real transports M7/M8/M9 are explicitly deferred to queue-004 (header line 7). No missing S3 deliverable.
- **Numbering is clean.** 019–023 continues sequentially from queue-002's item 018. No gaps, no dupes.
- **Both architectural invariants are captured explicitly, as acceptance criteria — not buried as implementation detail:**
  - *Async cross-thread delivery* — batch note (line 21) + items 020/021 require `send` to return **before** the peer `on-message` runs, separate thread, FIFO-per-direction, N concurrent with no loss / no HOL blocking. Item 021 even specifies the test mechanism (flag/box set after `send` but before handler completes, or a sync that would deadlock under inline delivery). Strong.
  - *`related-request-id` defined-but-inert-until-S6a* — batch note (line 19) + item 019 + item 020 all flag it as a routing hint that in-memory/stdio ignore, first load-bearing in S6a/M8, "do NOT strip as dead weight." Exactly right.
- **Closeout references are accurate (checked against progress.md).** Item 023's "flip Stage S3 acceptance boxes (lines 106–111)" matches the actual checkbox block (106–111) and the Stage S3 status marker (📋, line 95). Item 022's parity rows `transport.ts` / `inMemory.ts` map to the real progress row at line 110. These are not hand-waved line numbers — they resolve correctly.
- **Dependency hygiene matches roadmap.** S3 imports L0 only (S1 types/errors + S2 `auth.rkt` for `AuthInfo` in `message-extra-info`); no subprocess/socket/web-server. Item 022 enforces this with a restricted-load test. Consistent with roadmap S3 deps (lines 150–151).
- **Granularity is appropriate.** 5 items for a small stage is correct; padding to ~10 would be artificial. No item is too large.

---

## Detailed Feedback

### Issue 1 — Item count is internally inconsistent (must fix; factual)
- **Where:** header line 9 ("**Sizing:** 6 items") and "Why this batch" line 17 ("the **barrel**, **test suite**, portability sweep, and demo + closeout each earn separate items").
- **Problem:** Only 5 items exist (019–023). Item 021 bundles the barrel **and** the test suite into one item, contradicting both the "6 items" count and the line-17 prose that says they "each earn separate items."
- **Recommendation:** Pick one and make the document consistent:
  - (a) Change line 9 to "5 items" and reword line 17 so barrel + test suite are described as one item; **or**
  - (b) Split 021 into two items (barrel = 021, test suite = 022, renumber portability→023, demo→024) to match the "6 items" claim.
  - Option (b) also resolves Issue 2 more cleanly if combined with moving the core tests into 020 (see below). Recommend resolving Issue 2 first, then setting the count to whatever falls out.

### Issue 2 — Item 020 is not independently testable; deviates from the house test-pairing pattern (should fix)
- **Where:** item 020 ("Testable: deferred to the dedicated suite in item 021 ... a smoke check that the module loads and a pair constructs cleanly ... is sufficient here") and item 021 (owns all behavioral tests).
- **Problem:** Item 020 delivers what the queue itself calls "the substantive engineering" (async cross-thread relay, FIFO, concurrency, close/error propagation) but its only acceptance gate is "module loads + pair constructs." Its real correctness is verified only by a *later* item. That violates the independently-testable criterion: 020 can be marked done while the async/ordering/close semantics are silently broken, caught only in 021.
- **House-style deviation:** Every implementation item in queue-002 ships with its own test in the same item (011 provider + suite, 012 schema + dual-form test, 013 uri-template + round-trip, 014 tool-name + accept/reject table, 016 stdio + standalone harness). Item 020 breaks that validated pattern by externalizing its tests.
- **Recommendation:** Move the **core behavioral tests into item 020** so the adapter and its proof ship together: each-direction round-trip, asynchronous-delivery observation (`send` returns before peer handler), close fires `on-close` on both endpoints, induced relay failure fires `on-error`. Leave item 021 as the **barrel** + the **extended/stress coverage** (N-concurrent no-loss / FIFO / no-HOL-blocking, `message-extra-info` delivery, ported `util/inMemory.test.ts` expectations). This makes 020 independently verifiable, restores parity with the S2 house style, and naturally yields a 6-item batch that matches the line-9 count.

---

## Minor / optional

- Item 021's "Port the relevant `util/inMemory.test.ts` expectations **if present**" — the reference-impl footer (line 6) already hedges "if present." Fine to leave, but if the Worker should hard-require parity with a known fixture file, confirm the file exists in `typescript-sdk/` and drop the hedge; otherwise keep as-is.
- Item 022 sets parity rows to `partial` with "full conformance exercise deferred to S9" — consistent with the S2 precedent (item 017) and the progress parity-matrix progression note (line 336). No change needed; noted for confirmation only.

---

## Verdict

Tightly scoped, invariant-aware, accurate line references, correct dependency posture. The two issues are surgical: a one-line count/prose fix and relocating ~4 behavioral tests from 021 into 020. Resolve both and this is a green-light.
