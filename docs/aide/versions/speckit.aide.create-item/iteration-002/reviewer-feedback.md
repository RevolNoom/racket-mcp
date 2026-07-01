# Reviewer feedback — Item 022 iteration-002 (re-review)

**Overall: 9/10 — both CRITICAL issues resolved; both SUGGESTED addressed. `needs_revision: false`.** Two minor internal inconsistencies remain (the Implementation Steps drifted out of sync with the now-correct Acceptance Criteria) — fix them before a Worker executes, but they do not warrant another full review cycle.

---

## CRITICAL 1 (web-server teeth) — RESOLVED
The web-server assertion is no longer vacuously-passing. A **mandatory second teeth injection** now appears in all three required places:
- **Acceptance Criteria** line 77-80: teeth check split into (a) `racket/tcp` and **(b) `(require web-server/http)` → confirm the `#rx"/web-server/"` `check-false` fires RED → revert → green**, with an explicit rationale ("it would never fire naturally since no swept module imports web-server, so without this mutation the regex could be silently wrong forever"). Exactly the point I raised.
- **Implementation Steps** line 102-105: Step 4 mirrors (a)/(b), noting "(b) is the only way to prove the web-server assertion has working teeth."
- **Decisions** requirement: line 80 and 105 both require recording "both RED→revert→green transitions in Decisions." (The Decisions section itself is still the "To be updated during implementation" placeholder — correct; the Worker fills it.)

This genuinely proves the assertion bites: injecting `web-server/http` makes the walk visit `.../web-server/http.rkt`, which matches `#rx"/web-server/"`, firing the `check-false`. Good.

One residual caveat (non-blocking): if `web-server` is not installed in the Worker's Racket, `(require web-server/http)` fails at compile and the observed RED is a *load error*, not the `check-false` firing — which would not prove the assertion. web-server ships with the standard Racket distribution, so this normally resolves; the spec already directs the Worker to confirm the *specific* `#rx"/web-server/"` check-false fires (not merely "not green"), which is the right guard. Adequate as written.

## CRITICAL 2 (M10 branch non-vacuity) — RESOLVED (with a Step-2 sync gap, see below)
The M10 reachability guard is now **mandatory**, not optional:
- **Description** line 54-58: "MANDATORY second guard — M10 reachability," with both `check-true`s shown together (`#rx"core/main\.rkt"` for M6/S1 + `#rx"in-memory\.rkt"` for M10), and the correct rationale ("a truncated walk that stops at `transport.rkt` would pass the `core/main.rkt` guard but silently miss M10").
- **Acceptance Criteria** line 76: "Teeth-proving non-vacuity guards (TWO, both mandatory)" listing both regexes.

Both branches of the barrel are now permanently proven reached. Correct fix.

## SUGGESTED 3 (box-text anchoring) — ADDRESSED
- AC line 82-83 now anchor each parity box **by its literal box text**, with the line number demoted to a "hint," plus the explicit note "sibling items 020/021/023 may shift them; always locate by box text."
- Completion Reminder line 145 also anchors by text.

## SUGGESTED 4 (racket/port escalate-not-suppress) — ADDRESSED
Description line 38: "**Important:** `racket/port` IS in the ban list. If `racket/async-channel` transitively pulls `racket/port` … the sweep will go RED — this is a **real portability finding** and MUST be surfaced/escalated, NOT suppressed by removing the entry from `banned-module-paths` or adding an exemption." Exactly the guidance requested.

---

## Minor internal inconsistencies (fix before execution — not a new review round)

These are places where the Implementation Steps were not updated to match the corrected Acceptance Criteria. The AC is the binding contract and is correct, but a Worker who follows the Steps list literally could regress the very fix.

1. **Step 2 (line 99) omits the M10 guard.** Its concrete assert list reads: "`check-portable!` + web-server collection `check-false` + teeth-proving `check-true` for `#rx"core/main\.rkt"`." It does **not** mention the mandatory `#rx"in-memory\.rkt"` guard that AC line 76 and Description line 54-58 now require. Since Step 2 is the "here is what to assert" walkthrough a Worker copies from, add the `in-memory.rkt` `check-true` to this list so the M10 guard is not silently dropped. This is the same gap I flagged as CRITICAL 2 — resolved in AC/Description but re-openable via Step 2.

2. **Step 5 (line 107) still uses bare line numbers** (`progress.md:109 → [x]; progress.md:110 → [x]`), inconsistent with the text-anchoring adopted in AC line 82-83 and Completion Reminder line 145. Sync Step 5 to "locate by box text (hint: :109/:110)" so the whole spec is consistent.

Neither changes behavior if the Worker cross-references the AC, but both should be a 30-second edit.

---

## New gaps introduced by the edits
None beyond the two Step/AC sync nits above. The web-server regex is unchanged and still correct; the ban list is untouched (8 entries, no web-server — correctly a separate assertion); scope of progress.md edits still targets only the two S3 parity boxes; no roadmap edit. No over-reach introduced.

## Verdict
`needs_revision: false`. Both criticals and both suggestions are substantively resolved in the authoritative sections. Recommend patching Step 2 (add the `in-memory.rkt` guard) and Step 5 (text-anchor) as a trivial pre-execution cleanup.
