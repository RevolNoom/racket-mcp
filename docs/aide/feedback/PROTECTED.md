# Protected Invariants — read-only for self-improve

The self-improve step has full authority to rewrite any AIDE skill, EXCEPT the
invariants below. These exist to keep the unattended `--auto` chain from going
runaway or losing its single engine. Feedback must never edit, weaken, or
remove them. If feedback believes one must change, it writes the proposal to
`docs/aide/feedback/proposals.md` and STOPS — a human decides.

## P1 — Termination guard (execute-item)

`speckit.aide.execute-item` Auto Mode MUST keep the rule:

> Roadmap fully complete → STOP. Do not chain.

This is the only thing preventing an infinite loop. Immutable.

## P2 — Single engine

Only `speckit.aide.execute-item` advances the pipeline (decides the next
create-item / create-queue / stop). `create-item`, `create-queue`, and
`self-improve` may chain *into* the next step exactly as their current specs
say, but self-improve in `--auto` MUST return control to its caller and MUST
NOT itself advance the pipeline. No second engine.

## P3 — Backup + log before any skill edit

Before editing any `*/SKILL.md`, feedback copies the current file to
`docs/aide/versions/skills/<skill-name>/<timestamp>-SKILL.md` and appends an
entry to `docs/aide/feedback/changelog.md`. No silent edits.

## P4 — Frontmatter integrity

Any edited SKILL.md keeps a valid `---` frontmatter block with `name:` and
`description:` intact. Never corrupt the skill header.

## P5 — Additive-by-default for control flow

Efficiency edits (read-range rules, size budgets, handoff wording, snapshot
format) may be applied directly. Edits that change a skill's control flow,
remove a required section, or alter what gets shipped to the user are written
to `proposals.md` for human review first — even under full-apply authority.
