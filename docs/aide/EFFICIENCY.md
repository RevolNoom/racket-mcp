# AIDE Efficiency Contract

Standing rules for every AIDE skill, worker, and reviewer. Goal: keep token
cost low across the unattended `--auto` chain where `/clear` is never used, so
the main thread context grows for the whole roadmap.

These rules exist because a usage audit found the chain was dominated by
re-reading large documents: item specs of 25–96 KB read 13–28× each, and
`progress.md`/`roadmap.md` re-read on every chain hop and every subagent
cold-start. The fixes below remove those multipliers.

## R1 — Read ranges, never whole large files

- Do **not** read a file over ~400 lines in full to extract one section.
  Use `Grep` to find the line, then `Read` with `offset`/`limit`, or read the
  specific section only.
- To decide the next item, read only the **status-table rows** of
  `progress.md` (grep the status markers 📋/🚧/✅) plus the current queue file.
  Do not read `roadmap.md` in full on every hop — read it once per batch, by
  section.

## R2 — Item-spec size budget

- Target **≤ 400 lines / ~40 KB** per `docs/aide/items/NNN-*.md`.
- Reference existing code by `path:line` instead of pasting large code blocks
  into the spec.
- Heavy boilerplate (Manual Validation Checklist, Validation Documentation
  Template, Expected Outcomes) is **opt-in**: include a section only when the
  item actually needs it. Omit "N/A" scaffolding.
- A spec is implementation-ready when a worker can build from it — not when it
  restates the whole codebase.

## R3 — No full-document snapshots in versions/

- `versions/<skill>/iteration-NNN/` stores **only**: `reviewer-feedback.md`,
  `reviewer-feedback.json`, and a `pointer.txt` naming the canonical artifact
  path. Optionally a unified `diff` against the previous iteration.
- Do **not** copy the full item/queue/roadmap artifact into each iteration.
  The canonical file in `docs/aide/items/` (or wherever) is the single source.
- Reviewer reads the **canonical file** (by section/range), not a full copy.

## R4 — Thin handoffs to subagents

- A spawn / `SendMessage` prompt to a worker or reviewer MUST carry: the exact
  artifact **path**, the specific **excerpt(s)** it needs, and prior reviewer
  feedback verbatim. It MUST NOT say "go read progress.md and roadmap.md."
- The subagent reads only what is missing from its prompt. Every fact the
  lead already has should be passed down, not re-derived.

## R5 — Keep progress.md compact

- `progress.md` is a **status table**, not a narrative. Per-item prose belongs
  in the item file's "Decisions & Trade-offs" section.
- The lead updates only the status cell(s) for its own item number.

## How skills reference this

Each AIDE skill links here instead of restating the rules. Workers/reviewers
are told their size/handoff budget in the spawn prompt. The feedback-loop step
audits adherence to R1–R5 and may tighten these rules over time (it edits this
file and logs the change in `docs/aide/feedback/changelog.md`).
