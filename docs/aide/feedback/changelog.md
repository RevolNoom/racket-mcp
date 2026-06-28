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

## 2026-06-26T00:00:00Z — bootstrap
- **Trigger:** Usage audit — subagents 68% of tokens; item specs 25–96 KB read 13–28× each; progress.md (29 KB) read 28×.
- **Change:** Created `docs/aide/EFFICIENCY.md` (R1–R5); wired feedback-loop into `--auto` chain as per-item triage; trimmed create-item spec template; switched create-item/execute-item version snapshots to feedback+pointer (R3); added thin-handoff rule (R4).
- **Backup:** versions/skills/ (pre-edit SKILL.md copies, this commit)
- **Est. impact:** Removes the 13–28× whole-doc re-read multiplier; per-item feedback runs lean so cadence stays cheap.
