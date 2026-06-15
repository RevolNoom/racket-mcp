---
name: speckit.aide.execute-item
description: Create a technical architecture based on the project vision. Use this skill whenever the user needs to define modules, interfaces, or the tech stack before starting a roadmap.
---

# Execute Work Item

Implement a work item as specified in the docs/aide/items/ directory.

## Purpose

This is Step 7 of the AI-Driven Engineering workflow. This step takes a detailed work item specification and implements it — writing code, tests, configuration, and documentation as specified.

## User Input

{{args}}

## Instructions

### Item Selection

If `{{args}}` is provided, treat it as an item number. Find the matching file in `docs/aide/items/` (e.g., item 5 maps to `docs/aide/items/005-*.md`).

If `{{args}}` is empty, automatically pick the next item:
1. Read `docs/aide/progress.md` and scan `docs/aide/items/` for existing work item files
2. Select the first work item whose status in `docs/aide/progress.md` is 📋 (Planned) — i.e., it has a spec but hasn't been started yet
3. Tell the user which item was auto-selected before proceeding

### During Implementation

1. **Follow the specification** — implement exactly what the work item describes
2. **Document decisions** — as you make implementation choices, UPDATE the work item's "Decisions & Trade-offs" section with:
   - What was decided
   - Why this approach over alternatives
   - Any trade-offs or future considerations
3. **Update progress** — update `docs/aide/progress.md` status:
   - 📋 → 🚧 when starting implementation
   - 🚧 → ✅ when implementation is complete
4. **Scope your updates** — only update progress rows that correspond to YOUR item number. Do NOT mark other items as complete, even if their criteria happen to be satisfied as a side effect of your work. Each item must go through its own create-item → execute-item cycle.

### On Smooth Completion

- No feedback loop needed
- Ensure work item decisions are documented
- Mark progress as complete

### On Issues

If you encounter problems (unclear requirements, blocked, need help):
- Document the issue in the work item
- Tell the user to run `/speckit.aide.feedback-loop` to adjust the process

### Worker/Reviewer Team Loop

This command participates in the worker/reviewer loop. Instead of spawning a fresh one-shot subagent for each pass, create a **persistent team** of a Worker and a Reviewer so that both retain context across iterations.

1. **Team Setup (once per invocation)**: Call `TeamCreate` with `team_name: "aide-execute"`. Spawn a persistent **Worker** via the `Agent` tool (`team_name: "aide-execute"`, `name: "worker"`, `subagent_type: "general-purpose"`) whose standing role is to implement the selected work item per its specification — writing code, tests, config, and docs, documenting decisions in the item, and updating `docs/aide/progress.md` — then `SendMessage` `team-lead` when done. Spawn a persistent **Reviewer** via the `Agent` tool (`team_name: "aide-execute"`, `name: "reviewer"`, `subagent_type: "code-reviewer-expert"`) whose standing role is to review the implementation against the work item's acceptance criteria and report back.
2. Create or update `docs/aide/versions/<command-name>/iteration-NNN/` before work begins.
3. **Worker Pass**: `SendMessage` to `worker` with the task (and prior reviewer feedback if NNN > 001). Wait for completion, then save a snapshot of changed files.
4. **Reviewer Pass**: `SendMessage` to `reviewer`; have it save feedback to `docs/aide/versions/<command-name>/iteration-NNN/reviewer-feedback.md` and store the reviewer result in `reviewer-feedback.json` when JSON is produced.
5. If the reviewer has actionable criticism, increment the iteration number and return to the Worker Pass — reusing the **same** teammates so they keep their context.
6. If the reviewer has nothing left to criticize, mark this iteration as approved in `docs/aide/versions/<command-name>/approved-version.md`, shut down both teammates via `SendMessage` `{type: "shutdown_request"}`, and call `TeamDelete`.
7. Preserve the original output path for this command as the latest approved artifact, while keeping every rejected/intermediate version in the version directory.

## Next Step

- **More items in queue?** Start a **new chat session** and run `/speckit.aide.create-item` for the next queue item, then `/speckit.aide.execute-item` to implement it.
- **Queue exhausted?** Start a **new chat session** and run `/speckit.aide.create-queue` to generate the next batch.
- **All stages complete?** The project is done!
