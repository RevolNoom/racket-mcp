# Reviewer feedback — Item 017 iteration-002 (re-review)

Reviewed: `docs/aide/items/017-s2-portability-and-parity-touch.md` (147 lines, read in full).
Scope: verify the five iteration-001 required changes were applied correctly and completely,
and check for NEW gaps introduced by the edits.

**Verdict: all five fixes correctly and completely applied; no substantive new gap.
needs_revision = FALSE.** Two cosmetic stale-reference nits remain (polish only, listed
at the end — not grounds for another cycle).

I re-ran the portability walk empirically to confirm the central new mechanism (the
S1-edge teeth guard) actually distinguishes a correct walk from a truncated one,
including under process-level module-cache contamination. It does.

---

## Point 1 (CRITICAL — weak guard) — FIXED, and empirically VERIFIED sufficient.

The revision replaces the blind `(> (set-count visited) 1)` with (a) a mandated per-root
base-dir `(path-only <root>)` (line 63, §"Per-root base-dir is load-bearing" line 30-32,
step 2 line 87) and (b) a teeth-proving path-presence guard (line 65, §"Non-vacuity" line
34-40, helper sketch line 40): the six S1-importing roots assert `visited` contains
`#rx"core/main\\.rkt"` or `#rx"spec-2026"`; `tool-name-validation` asserts
`#rx"/(string|list)\\.rkt$"` or `>= 50`.

**Is the S1-edge assertion actually sufficient to catch the truncation I proved in
iteration-001?** Yes — verified directly. I almost mis-cleared this: a naive probe that
walked a root CORRECT-then-WRONG in the same process showed `core/main.rkt` present even
on the "wrong" walk, which would have meant the guard was useless. The cause is that
`module-path-index-resolve` caches its result on the MPI object process-globally, so the
prior correct resolution contaminated the wrong one. That contamination is an artifact of
the probe, not of the real test: the real `s2-portability-test.rkt` walks **each root
once** in a fresh `make-base-namespace`. The decisive isolated test:

```
provider CORRECT first: visited=228  core/main=#t
metadata-utils WRONG (after provider already loaded core/main): visited=79  core/main=#f
```

Even after a *different* root loaded `core/main.rkt` into the process, a wrong-base-dir
walk on `metadata-utils` still truncates to 79 with `core/main` **absent** — because each
module's `../main.rkt` is a distinct MPI resolved fresh against its own (wrong) base-dir →
bogus path → `module->imports` raises → `with-handlers` swallows → truncates before the S1
subtree. So in the real one-walk-per-root test, a wrong per-root base-dir makes the S1-edge
assertion fire RED. The guard has teeth against exactly the hazard iteration-001 proved.

**Is the `tool-name-validation` floor/regex right?** Yes. Measured `visited=82`; `>= 50`
holds, and the regex matches — `racket/string`/`racket/list` resolve to real paths
(`/usr/share/racket/collects/racket/string.rkt`, `…/list.rkt`), so `#rx"/(string|list)\\.rkt$"`
is satisfied. Note `tool-name-validation` has **no relative requires** (only `racket/string`,
`racket/list`, `racket/base` — all collection-anchored), so it cannot truncate via base-dir
at all; `>= 50` is a safe non-vacuity floor here and the "or" gives the implementer a correct
fallback if they distrust the regex. Both options are valid. Correct partition: 6 S1-importers
+ 1 base-collections-only = 7. All six S1-importers do directly require `../main.rkt`
(confirmed), so `core/main.rkt` is the right edge marker for all of them.

## Point 2 (CRITICAL — progress over-claim) — FIXED.

Lines 73 and 76 now mandate explicit scope caveats on both flips:
- `:82` → `[x] raco test over all S2 modules passes (except stdio.rkt/M5e — orphaned-until-S6a
  per roadmap.md:118; stdio coverage + the framing box land with item 016)`, with "Do NOT
  flip it to a bare `[x]`."
- `:79` → `✅ Tests under …/test/ (except shared/test/stdio-test.rkt — lands with item 016/M5e)`.

The Completion Reminder (line 139) and step 5 (line 92-94) echo the caveat. This removes the
contradiction: `:82`/`:79` now explicitly scope **out** stdio, so they no longer assert
anything about the still-📋 `:78` deliverable or the `[ ]` `:87` framing box. The line
targets (82/79/78/87/88/89/336) are unchanged from iteration-001 and remain correct.

## Point 3 (MEDIUM — factor regression) — FIXED, no "Optionally" remains.

Line 70 makes `raco test mcp/core/test/` a MANDATORY acceptance box (runs the new sweep AND
`main-test.rkt`/`errors-test.rkt`). Line 71 adds the factored-walk check-count box. Testing
Strategy line 104 heads the command block "all MANDATORY, all must exit 0"; line 111 states
it is "mandatory (not optional)" and demotes the file-only run to a "fast inner loop," not
the gate. Grep for "optional" returns only line 111's "mandatory (not optional)" — the
iteration-001 "Optionally" on the main-test-covering run is gone.

## Point 4 (SUGGESTED — teeth check) — ADDED.

Acceptance box line 66, Implementation step 4 (line 90, with concrete root `util/schema.rkt`,
RED → revert → green), and Decisions line 130 all require the `(require racket/tcp)` mutation
proof. Complete.

## Point 5 (SUGGESTED — stdio wording) — FIXED.

Line 67 reworded to "excluded **as a root**" with the clarification that if any swept module
ever transitively imports `stdio.rkt`, the sweep walks in and correctly surfaces stdio's
banned imports against the *importing* module (stdio is not exempt from portability). The
in-file-comment instruction (step 2, line 88) echoes the same. Done.

---

## New gaps introduced by the edits

None substantive. The per-root-base-dir + S1-edge-presence pair is internally consistent
across the Description (30-40), Acceptance Criteria (63/65), and Implementation step 2 (87),
and is empirically sound (verified above). The teeth-check momentarily edits a real module
then reverts — a slight tension with the "no module source edits" scope guard (line 52), but
the spec frames it explicitly as temporary-then-reverted, so it is not a real violation.

## Cosmetic nits (polish only — NOT grounds for revision)

1. Stale label: step 1 (line 82) and Dependencies (line 119) still call
   `uri-template-test.rkt:336-341` "the non-vacuity guard," even though the spec now
   explicitly rejects that file's bare `> 1` guard. They mean it as the
   parameterize/namespace *shape* template, but an implementer skimming could copy the `> 1`.
   The emphatic instructions at lines 28/34-40/65/87 prevent this, so it is low-risk. If
   touched, reword to "the parameterize/fresh-namespace shape (NOT its `> 1` guard, which is
   insufficient — see §Non-vacuity)."
2. Testing-Strategy one-liner (line 102) still says "each guarded against a vacuous (empty)
   walk" — accurate but understates the strengthened truncation guard; not contradictory.
3. Optional gold-plating (not required): the mutation check (Point 4) proves the *banned*
   assertion bites but not the *non-vacuity* assertion. A second mutation (temporarily pass a
   wrong base-dir, confirm the S1-edge assertion fires RED) would prove the new guard's teeth
   too. The guard's correctness is already established here, so this is purely optional.

## Bottom line

Rating 9/10. The two iteration-001 CRITICALs are correctly resolved and the central new
mechanism is empirically verified to catch the hazard it targets. The three remaining items
are cosmetic. Ship it.
