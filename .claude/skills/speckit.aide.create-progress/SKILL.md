---
name: speckit.aide.create-progress
description: Create a technical architecture based on the project vision. Use this skill whenever the user needs to define modules, interfaces, or the tech stack before starting a roadmap.
---

# Create Progress File

Create a progress tracking file to monitor project completion.

## Purpose

This is Step 4 of the AI-Driven Engineering workflow. The progress file provides visibility into which features and capabilities have been completed, are in progress, or are still planned.

## Prerequisites

- `docs/aide/vision.md` must exist (created by `/speckit.aide.create-vision`)
- `docs/aide/roadmap.md` must exist (created by `/speckit.aide.create-roadmap`)

## Instructions

Read both `docs/aide/vision.md` and `docs/aide/roadmap.md`. If `docs/aide/progress.md` already exists, **update it incrementally** — do not regenerate from scratch. If it does not exist, create it.

### Updating an Existing Progress File

When updating an existing progress file:

1. **Preserve all existing statuses** — never change a ✅, 🚧, ⏸️, or ❌ status back to 📋.
2. **Add new items** for any stages, deliverables, or features that appear in the roadmap but are not yet tracked in the progress file.
3. **Do not remove items** — even if they no longer appear in the roadmap, keep them and mark as ⏸️ Deferred (with a note) rather than deleting.
4. **Preserve acceptance criteria checkboxes** — do not uncheck any already-checked criteria.

### Requirements

1. **Comprehensive coverage** — every feature, capability, and deliverable from the vision and roadmap should be tracked
2. **Status tracking** — use status icons to indicate state:
   - 📋 Planned
   - 🚧 In Progress
   - ✅ Complete
   - ⏸️ Deferred
   - ❌ Excluded
3. **Organized by stage** — group items according to the roadmap stages
4. **Actionable** — each item should be specific enough to verify completion

### Output

Save the completed progress file to `docs/aide/progress.md`.

### Worker/Reviewer Team Loop

This command participates in the worker/reviewer loop. Instead of spawning a fresh one-shot subagent for each pass, create a **persistent team** of a Worker and a Reviewer so that both retain context across iterations.

1. **Team Setup (once per invocation)**: Call `TeamCreate` with `team_name: "aide-progress"`. Spawn a persistent **Worker** via the `Agent` tool (`team_name: "aide-progress"`, `name: "worker"`, `subagent_type: "general-purpose"`) whose standing role is to create or incrementally update `docs/aide/progress.md` per these instructions, then `SendMessage` `team-lead` when done. Spawn a persistent **Reviewer** via the `Agent` tool (`team_name: "aide-progress"`, `name: "reviewer"`, `subagent_type: "general-purpose"`) whose standing role is to verify the progress file covers every vision/roadmap deliverable and preserves prior statuses, then report back.
2. Create or update `docs/aide/versions/<command-name>/iteration-NNN/` before work begins.
3. **Worker Pass**: `SendMessage` to `worker` with the task (and prior reviewer feedback if NNN > 001). Wait for completion, then save a snapshot of changed files.
4. **Reviewer Pass**: `SendMessage` to `reviewer`; have it save feedback to `docs/aide/versions/<command-name>/iteration-NNN/reviewer-feedback.md` and store the reviewer result in `reviewer-feedback.json` when JSON is produced.
5. If the reviewer has actionable criticism, increment the iteration number and return to the Worker Pass — reusing the **same** teammates so they keep their context.
6. If the reviewer has nothing left to criticize, mark this iteration as approved in `docs/aide/versions/<command-name>/approved-version.md`, shut down both teammates via `SendMessage` `{type: "shutdown_request"}`, and call `TeamDelete`.
7. Preserve the original output path for this command as the latest approved artifact, while keeping every rejected/intermediate version in the version directory.

## Next Step

After reviewing the progress file, start a **new chat session** and run `/speckit.aide.create-queue` to generate the first batch of prioritized work items.
