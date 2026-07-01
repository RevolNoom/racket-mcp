# Feedback-Loop Changelog

Every skill/doc edit the `speckit.aide.feedback-loop` step applies is logged
here, newest first. One entry per change.

Format:
```
## <ISO-8601 timestamp> — <skill or file edited>
- **Trigger:** what signal/bottleneck prompted this (e.g. "item 011 read 28×", "create-item iteration count 5")
- **Change:** what was edited (additive rule / template trim / control-flow — note which)
- **Backup:** path under versions/skills/ holding the pre-edit copy
- **Est. impact:** rough token saving / problem prevented
```

---

## 2026-07-01T14:10:00Z — harvested docs/aide/scripts/test-transport.sh (queue-003 retrospective, spanned 2 items)
- **Trigger:** queue-003 retrospective. `tally-commands.sh` printed nothing at default/relaxed thresholds — but that *was* the signal: items 020 and 021 both verify the transport module using three different command shapes (`.../test/in-memory-test.rkt`, `.../test/`, `mcp/transport/`), so no two rows normalize identically and exact-match tally can't fire. Shape-drift is the R6 re-derivation cost, and pending items 022/023 will test transport too. Other detectors clean: specs trending down (22→17→11 KB, all <40 KB & <120 B/L), reviewer counts all ≤2, no open signals, progress.md long lines are house-format deliverable rows since S0 (not a batch regression).
- **Change (additive — new script, P5):** `harvest-script.sh test-transport 'raco test mcp/transport/'`. Whole-module command supersedes all three variant shapes and also covers the `main.rkt` barrel the file-specific commands missed. No SKILL.md edit: execute-item step 0 / EFFICIENCY R6 already direct workers to prefer a `docs/aide/scripts/*` script, so the pointer is generic (no P3 backup needed).
- **Backup:** n/a (no SKILL.md touched; new file only).
- **Est. impact:** 022/023 (and later transport items) run one stable command instead of re-guessing file-vs-dir-vs-module; barrel now always exercised. Verified: 46 tests pass.

## 2026-06-29T00:00:00Z — R2 made KB-binding + bytes/line tripwire (queue-001/002 retrospective)
- **Trigger:** queue-001→queue-002 Queue Retrospective dry-run. 16 of 18 specs bust R2's ~40 KB; the line rule (landed between the two queues) was gamed — avg lines fell ~970→450 (passing the line count) while avg KB held ~74 KB because bytes/line doubled (66→160). Specs were reflowed dense, not trimmed. Line count is gameable; KB is the honest cost.
- **Change (additive — size rule, P5):** EFFICIENCY **R2** rewritten so **≤ ~40 KB is the binding budget** and ≤ 400 lines is a secondary guide; added a **> ~120 bytes/line** tripwire (`wc -c` ÷ `wc -l`) that flags dense-reflow. Aligned `feedback-loop` triage spec-size check and Queue Retrospective spec-size-trend check to use KB + bytes/line.
- **Backup:** Authored via skill-creator; pre-edit state of `EFFICIENCY.md` in main repo git history, `feedback-loop/SKILL.md` in the `.claude` submodule history.
- **Est. impact:** Closes the line-count loophole so future specs actually shrink in reading cost (KB), not just line count; per-item triage now catches dense-reflow it previously passed.

## 2026-06-28T23:36:00Z — Queue Retrospective Mode (cross-item, queue-end optimization)
- **Trigger:** Feedback only ran per item (triage) — no vantage point ever saw a whole finished batch, so cross-item patterns (a command re-derived across N items, spec-size creep over a queue, multiple items needing >3 review rounds, sizing/sequencing that forced rework) went uncaught and the next queue inherited them. Authored via skill-creator at user request.
- **Change (control-flow + additive):** Added a third mode to `speckit.aide.feedback-loop`: **Queue Retrospective** (`--queue <NNN>`), run once when a queue ends, that scrutinizes ALL items in the finished batch and applies cross-item fixes (harvest recurring commands/sequences, trim template creep, feed sizing/sequencing fixes to create-queue) before the next batch is planned; returns control without advancing the pipeline (P2). Updated arg-parsing + Next Step + description. Wired `execute-item` Auto Mode step 3 (queue-exhausted transition) to call `feedback-loop --auto --queue <NNN>` before create-queue, and added the manual-mode hint. All edits preserve P1/P2; the new mode applies additive fixes directly and routes control-flow/structural changes to proposals.md (P5).
- **Backup:** Authored via skill-creator (not the feedback-loop runtime); pre-edit SKILL.md state recoverable from the `.claude` submodule git history.
- **Est. impact:** Cross-item friction fixed once at queue-end instead of recurring every batch; per-item triage stays lean (retro adds one queue read + one tally call, only when a queue ends).

## 2026-06-28T17:00:00Z — Pattern Harvest (repeated-command → reusable script)
- **Trigger:** Workers re-derive the same build/test/validate commands on every item (e.g. `raco test <module>`, `racket <demo>.rkt`) with no cross-item reuse — re-derivation cost + drift risk.
- **Change (additive):** Added EFFICIENCY **R6** (reuse harvested scripts; log recurring commands). Added bundled tooling to `speckit.aide.feedback-loop/scripts/`: `log-command.sh`, `tally-commands.sh`, `harvest-script.sh`. New artifacts: `docs/aide/feedback/command-log.tsv` (append-only ledger) and `docs/aide/scripts/` (harvested scripts). Wired execute-item worker to log commands + prefer harvested scripts; wired create-item testing-strategy to point at scripts; added **Pattern Harvest** procedure to feedback-loop (triage signal + harvest action, Deep Mode for multi-step sequences).
- **Backup:** versions/skills/{speckit.aide.feedback-loop,execute-item,create-item}/2026-06-28T16-59-46Z-SKILL.md
- **Est. impact:** Each recurring command harvested once → every later item calls one script instead of re-deriving flags/paths; consistent verification across the roadmap.

## 2026-06-26T00:00:00Z — bootstrap
- **Trigger:** Usage audit — subagents 68% of tokens; item specs 25–96 KB read 13–28× each; progress.md (29 KB) read 28×.
- **Change:** Created `docs/aide/EFFICIENCY.md` (R1–R5); wired feedback-loop into `--auto` chain as per-item triage; trimmed create-item spec template; switched create-item/execute-item version snapshots to feedback+pointer (R3); added thin-handoff rule (R4).
- **Backup:** versions/skills/ (pre-edit SKILL.md copies, this commit)
- **Est. impact:** Removes the 13–28× whole-doc re-read multiplier; per-item feedback runs lean so cadence stays cheap.
