# Reviewer Feedback — Item 017 (S2 portability sweep + parity touch)

**Verdict: APPROVED. needs_revision = false. Rating 9/10.**

Every Acceptance Criterion objectively met. No correctness bug. No module source touched. All three mandatory gates re-run green by reviewer.

## Gates re-run (reviewer, exit 0 confirmed)
- `raco test mcp/core/validators/ mcp/core/util/ mcp/core/shared/` → **671 passed**, EXIT=0.
- `raco test mcp/core/test/s2-portability-test.rkt` → **63 passed**, EXIT=0.
- `raco test mcp/core/test/` (dir-wide superset incl. main-test.rkt/errors-test.rkt) → **221 passed**, EXIT=0.

Worker's claimed counts (671 / 63 / 221) reproduce exactly.

## Focus-point findings

1. **Per-root base-dir + teeth guard — CORRECT, no `> 1` regression.** `check-root` (s2-portability-test.rkt:153-160) derives `base-dir = (path-only root-path)` from its own `path` argument per root — not a shared `here`-derived dir. It asserts (i) the banned-module `check-false` loop AND (ii) the supplied teeth-check on the same `visited` set. Teeth are path-presence, not count: `s1-edge-teeth` (:134-137) asserts `#rx"core/main\.rkt"` or `#rx"spec-2026"` for the six S1-importers; `base-collection-teeth` (:143-146) asserts `#rx"/(string|list)\.rkt$"` or `>= 50` for tool-name-validation. No bare `(> (set-count visited) 1)` anywhere.

2. **banned-module-paths matches main-test.rkt:49-51 exactly** — `'(racket/system racket/port racket/tcp racket/udp net/url net/http-client net/sendurl racket/sandbox)` (s2-portability-test.rkt:55-57). The six walk helpers (resolve-mpi/dir-of/direct-imports/transitive-imports/banned-hit?/check-portable!) are copied verbatim. Seven literal roots (:168-174); stdio absent; no directory-list/glob over shared/.

3. **Three mandatory raco commands re-run — all exit 0**, counts as above. Did NOT re-run the teeth mutation (worker already proved RED→revert→green; git confirms no module left modified, so no need to risk a non-byte-identical revert).

4. **progress.md edits correct (line numbers shifted +1 from spec because the new Deliverables line was inserted at :80):**
   - Raco catch-all box (now :83) flipped `[x]` WITH the "except stdio.rkt/M5e — orphaned-until-S6a per roadmap.md:118; stdio coverage + the framing box land with item 016" caveat — not a bare check.
   - Per-module-tests Deliverable (:79) flipped ✅ WITH "except shared/test/stdio-test.rkt — lands with item 016/M5e" caveat.
   - Parity-rows box (now :89) flipped `[x]`.
   - stdio-framing box (:88) and demo box (:90) correctly left `[ ]` (items 016/018).
   - New sweep Deliverable line added (:80).
   - Item-017 narrative sentence appended (:337): names the six rows + `partial`, describes the per-root base-dir walk, the teeth guards with observed visited counts (220–233 / 82), stdio carve-out, the racket/tcp RED→revert mutation, all three gate counts, and the "no materialized roadmap §9 table; acceptance line roadmap.md:131 stands" note. No other item's rows touched.

5. **git — no module source modified.** `git diff -- mcp/core/validators mcp/core/util mcp/core/shared` is empty. New module dirs (shared/, util/) and the test file are untracked; the new test file `mcp/core/test/s2-portability-test.rkt` is untracked. Nothing under validators/util/shared shows as modified.

6. **No leftover `(require racket/tcp)` / stray mutation.** grep for racket/tcp/system/sandbox across the swept modules returns only comment text and banned-list literals inside test files — no live banned require in any swept module. Mutation cleanly reverted.

## Minor (non-blocking)
- The verbatim `check-portable!` (:110-115) is retained but unused by the sweep (check-root supersedes it). Spec acceptance line 61 explicitly mandates copying it verbatim, so this is intentional dead code, not a defect. NOTE only.

No revision required.
