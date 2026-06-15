---
name: speckit.aide.create-queue
description: Create a technical architecture based on the project vision. Use this skill whenever the user needs to define modules, interfaces, or the tech stack before starting a roadmap.
---

# Create Queue

Generate the next batch of prioritized work items.

## Purpose

This is Step 5 of the AI-Driven Engineering workflow. The queue contains the next ~10 actionable work items prioritized from the roadmap and progress documents. This step is repeated whenever the current queue is exhausted.

## Prerequisites

- `docs/aide/vision.md` must exist
- `docs/aide/roadmap.md` must exist
- `docs/aide/progress.md` must exist

## Instructions

Read `docs/aide/vision.md`, `docs/aide/roadmap.md`, and `docs/aide/progress.md`, then create a prioritized queue of work items.

### Requirements

1. **Next logical items** — select the next ~10 items based on roadmap priority and current progress
2. **No duplicates** — check existing queues in `docs/aide/queue/queue-*.md` to avoid re-queuing completed or already-queued items
3. **Sequential numbering** — work item numbers must be sequential across all queues. Check existing queues to find the highest item number used, then start from the next number. For example, if `queue-001.md` ends at item 10, `queue-002.md` starts at item 11.
4. **Testable items** — each item must be testable locally
5. **Week-sized batch** — the total work in the queue should be deliverable in about a week
6. **Consistent format** — each item must follow this format so other commands can parse it:
   ```
   ### Item NNN: Short Title
   Brief description of the scope and deliverables for this item.
   ```
   Where NNN is the sequential item number (e.g., 001, 012, 023).

### Queue Naming

Name the queue file sequentially: `queue-001.md`, `queue-002.md`, etc.

### Output

Save the queue to `docs/aide/queue/queue-NNN.md` (where NNN is the next sequential number).

### MANDATORY Worker/Reviewer Team Loop

You MUST execute this loop for every invocation. Instead of spawning a fresh one-shot subagent for each pass, create a **persistent team** of a Worker and a Reviewer so that both retain context across iterations. Do not stop until the Reviewer approves.

1. **Team Setup (once per invocation)**:
   - Call `TeamCreate` with `team_name: "aide-queue"` and a short description.
   - Spawn the **Worker** as a persistent teammate using the `Agent` tool: `team_name: "aide-queue"`, `name: "worker"`, `subagent_type: "general-purpose"`. Standing-role prompt: "You are the Worker. Each time you are messaged, generate the next batch of prioritized work items based on `docs/aide/vision.md`, `docs/aide/roadmap.md`, and `docs/aide/progress.md`, following the create-queue requirements and format, and save it with the `Write` tool to `docs/aide/queue/queue-NNN.md`. Incorporate any reviewer feedback included in the message. When finished, `SendMessage` to `team-lead` reporting completion."
   - Spawn the **Reviewer** as a persistent teammate using the `Agent` tool: `team_name: "aide-queue"`, `name: "reviewer"`, `subagent_type: "queue-quality-reviewer"`. Standing-role prompt: "You are the Reviewer. Each time you are messaged, critique the queue at the path provided against the vision and roadmap. When finished, `SendMessage` to `team-lead` reporting completion."
2. **Initialization**: Identify the current iteration number (starting at 001). Create the directory `docs/aide/versions/speckit.aide.create-queue/iteration-NNN/`.
3. **Worker Pass**: `SendMessage` to `worker` with the task for this iteration. If NNN > 001, include the previous iteration's reviewer feedback verbatim. Wait for the Worker to report completion.
4. **Snapshot**: Immediately copy the output from `docs/aide/queue/queue-NNN.md` to `docs/aide/versions/speckit.aide.create-queue/iteration-NNN/queue-NNN.md`.
5. **Reviewer Pass**: `SendMessage` to `reviewer` pointing it at `docs/aide/versions/speckit.aide.create-queue/iteration-NNN/queue-NNN.md`. Instruct it to be meticulous, identify gaps/errors/improvements, save detailed feedback to `docs/aide/versions/speckit.aide.create-queue/iteration-NNN/reviewer-feedback.md`, and a JSON summary to `docs/aide/versions/speckit.aide.create-queue/iteration-NNN/reviewer-feedback.json` (fields: `overall_rating` (number), `needs_revision` (boolean), and `key_issues` (array of strings)). Wait for the Reviewer to report completion.
6. **Decision**:
   - Read the JSON summary from `docs/aide/versions/speckit.aide.create-queue/iteration-NNN/reviewer-feedback.json`.
   - **If `needs_revision` is `true`**: Increment the iteration number (NNN+1) and return to Step 3 — reuse the **same** Worker and Reviewer teammates (they keep their context), passing the latest feedback into the next Worker Pass.
   - **If `needs_revision` is `false`**: Mark the iteration as approved by saving a copy of the artifact to `docs/aide/versions/speckit.aide.create-queue/approved-version.md`. Proceed to teardown.
7. **Teardown**: Gracefully shut down both teammates via `SendMessage` with `message: {type: "shutdown_request"}`, then call `TeamDelete` to clean up the team.

## Next Step

Select an item from the queue and start a **new chat session**. Run `/speckit.aide.create-item` with the item description to create a detailed work item specification.
