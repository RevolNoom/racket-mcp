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

- **≤ ~40 KB is the binding budget** per `docs/aide/items/NNN-*.md` — KB tracks
  the actual reading cost. **≤ 400 lines** is a secondary guide, not a target to
  hit on its own: a spec that meets the line count by packing prose into long,
  dense lines has not been trimmed, it has been reflowed. (A queue-001→002
  retrospective found exactly this — lines fell ~970→450 while KB held ~74 KB
  because bytes-per-line doubled.) If a spec runs **> ~120 bytes/line**
  (`wc -c` ÷ `wc -l`), that is the tell: prose is dense, not lean — cut content,
  don't reflow.
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

## R6 — Reuse harvested scripts; don't re-derive recurring commands

- Before running a build/test/validate command, check `docs/aide/scripts/` for
  a script that already does it. Prefer the script — it ran the same way on
  prior items, so reusing it keeps behavior consistent and saves the worker
  from re-deriving flags/paths from scratch each time.
- The worker logs each non-trivial command it runs to the command ledger via
  `.claude/skills/speckit.aide.self-improve/scripts/log-command.sh <item> <cmd>`.
  This is one cheap appended line; it's what lets the self-improve step see which
  commands recur across items.
- The self-improve step owns harvesting: when a command recurs across ≥2 items
  (detected by `tally-commands.sh`) it writes a reusable script into
  `docs/aide/scripts/` (`harvest-script.sh`) and wires the relevant skills to
  call it. Workers do not invent these scripts themselves.

## How skills reference this

Each AIDE skill links here instead of restating the rules. Workers/reviewers
are told their size/handoff budget in the spawn prompt. The self-improve step
audits adherence to R1–R6 and may tighten these rules over time (it edits this
file and logs the change in `docs/aide/feedback/changelog.md`).
