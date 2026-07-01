# Reviewer feedback — Item 022 (S3 transport portability sweep + parity touch)

**Overall: 7/10 — needs a small revision.** The spec is close to item-017 rigor and gets the hard parts right (separate web-server collection assertion, per-root base-dir, path-presence non-vacuity for the M6 branch, mandatory teeth check, literal single-root walk, correct scope of progress.md edits). Two genuine gaps let a green-but-vacuous test through, both fixable with one sentence each. All quoted line numbers, box texts, imports, and template ranges were verified against the working tree and are currently accurate.

---

## What is correct (verified)

- **web-server separate assertion is justified and the regex is right.** Confirmed `banned-hit?` (`main-test.rkt:95-98`) anchors `/<sym>(\.rkt)?$`, so a bare `web-server` symbol only matches a path ending `/web-server.rkt` and would MISS `web-server/http` (resolves to `.../web-server/http.rkt`, ends in `http.rkt`). The mandated `#rx"/web-server/"` correctly matches the collection directory. No false-positive risk in this repo (no directory literally named `web-server`; grep confirms web-server appears only in the two inline `NO ... web-server` comments).
- **Non-vacuity edge for M6 is robust.** `transport.rkt:19-22` imports `"../core/main.rkt"`; asserting `#rx"core/main\.rkt"` presence proves the relative edge resolved and the S1 subtree was reached. Substring match cannot accidentally hit `transport/main.rkt`. Good.
- **base-dir.** Single root; `(path-only root)` = `mcp/transport/` is the barrel's own dir, and `dir-of` recomputes per path-named child, so `transport.rkt`'s `../core/main.rkt` resolves correctly. Correct.
- **Scope of progress.md edits is exactly right.** Verified: `progress.md:109` = "Load test: still no subprocess/socket module pulled in", `:110` = "Parity rows transport.ts, inMemory.ts marked partial". The spec flips ONLY these two and correctly leaves `:106/:107/:108` (owned by item 020), `:111` demo (021/023), and the Stage S3 header `:95` status `📋` (owned by 023). No over-reach.
- **roadmap reconciliation.** Verified `roadmap.md:158` is a plain acceptance line, no materialized §9 table. Spec correctly mandates no roadmap edit — matches item 017's finding.
- **async-channel not banned.** Correct — `banned-module-paths` (8 entries) does not list it; spec calls it out (line 36). No false flag.
- **Deliverables section exists** under Stage S3 (`progress.md:98-102`); "add an S3 Deliverables line" is valid and matches item-017 style.

---

## Missing coverage (Critical)

### 1. The web-server assertion is vacuously-passing — nothing proves it can go RED.
No swept module imports web-server (grep confirms), so the `check-false` over `#rx"/web-server/"` passes **unconditionally** in this codebase. The mandated teeth/mutation check (Step 4, AC line 71) injects `(require racket/tcp)` — that fires the **banned-module** loop, NOT the web-server assertion. Consequence: a Worker who fat-fingers the regex (`#rx"/web-sever/"`, or drops the leading `/`) ships a permanently-green, unfalsifiable assertion. This is exactly the "green-but-vacuous" failure the item is supposed to guard against.

**Fix:** make the teeth check prove BOTH assertions bite. Add a second, separate mutation: temporarily add `(require web-server/http)` to one swept module (e.g. `in-memory.rkt`), run the sweep, confirm the **web-server** `check-false` fires RED, then revert. Record RED→revert→green for the web-server check as its own line in Decisions. (web-server ships with the standard Racket distribution, so the require resolves.) If a live web-server dependency is undesirable, at minimum the spec must acknowledge the assertion is non-falsifiable in-repo and rely on a hand-review of the regex — but the second injection is the honest proof and costs one line.

### 2. The M10 (in-memory.rkt) branch is not permanently proven reached — only M6 is.
The item's stated purpose is "one barrel covers both M6 and M10." But the **only mandatory** non-vacuity guard is `#rx"core/main\.rkt"`, which lives under the `transport.rkt` (M6) subtree. `in-memory.rkt` is reached via `barrel → "in-memory.rkt"`, a **different** branch. If the barrel's `in-memory.rkt` require ever fails to resolve, or the walk truncates that branch, the sweep passes green having exercised M6 only — and M10 portability is asserted over an empty set. The spec relegates the M10 proof to an **optional** async-channel assertion (line 52) and a transient mutation. After the teeth revert, no permanent assertion guarantees `in-memory.rkt` stays in `visited`.

**Fix:** promote the M10-reachability guard from "optionally also assert" to **mandatory**. Assert `(check-true (visited-has? visited #rx"in-memory\.rkt") "walk did not reach M10/in-memory.rkt")` (most direct) or the `racket/async-channel` presence proof (only `in-memory.rkt` imports it). This makes both M6 and M10 subtrees permanently non-vacuous, matching the item's own coverage claim.

---

## Missing coverage (Suggested)

### 3. Line-number fragility in progress.md edits.
AC lines 73-76 and Step 5 pin literal line numbers (`:109`, `:110`, `:338`). Accurate **now**, but sibling S3 items (020/021/023) also edit this same file/section; if any lands between spec-write and execution the numbers drift and a Worker keying on the literal line could edit the wrong box. The spec does quote the box **text**, which is the safe anchor. Recommend the AC say "match by the quoted box text (line ~109)" rather than a bare line number — cheap robustness.

### 4. `racket/port` is in the banned list — confirm the sweep is actually expected green, don't assume.
`banned-module-paths` bans `racket/port` (an in-process port utility). The two new transitive imports vs the already-swept S1/S2 tree are `racket/generic` (already in core) and `racket/async-channel`. If `racket/async-channel` transitively pulls `racket/port`, the sweep goes RED and — correctly per Step 3 — the Worker must surface it, not edit the module. Not a spec defect, but the spec should explicitly tell the Worker: "the sweep must be RUN and observed green; if `racket/port` (or any ban) fires via `async-channel`, that is a real portability finding to escalate, not a test bug to suppress by weakening the ban list."

---

## Concrete teeth-check the revised spec should mandate

| Mutation / guard | Location | Expected result | Proves |
|---|---|---|---|
| `(require racket/tcp)` | inject `in-memory.rkt` | banned-module loop RED | ban assertions bite + M10 walked |
| `(require web-server/http)` | inject `in-memory.rkt` | web-server `check-false` RED | `/web-server/` assertion bites (gap #1) |
| `visited-has? #rx"in-memory\.rkt"` | permanent assert | green | M10 branch permanently non-vacuous (gap #2) |
| `visited-has? #rx"core/main\.rkt"` | permanent assert | green | M6 branch non-vacuous (already in spec) |

Both mutations reverted; `git diff mcp/transport/` empty; sweep green again — recorded in Decisions.

---

## Verdict
Solid, low-risk item that correctly reuses a proven template. Ship after: (a) adding the web-server teeth injection, and (b) promoting the M10/in-memory.rkt (or async-channel) presence guard to mandatory. Items 3-4 are polish. `needs_revision: true`.
