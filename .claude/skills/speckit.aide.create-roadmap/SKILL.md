---
name: speckit.aide.create-roadmap
description: Create a technical architecture based on the project vision. Use this skill whenever the user needs to define modules, interfaces, or the tech stack before starting a roadmap.
---

# Create Roadmap

Generate a staged development roadmap based on the project vision.

## Purpose

This is Step 3 of the AI-Driven Engineering workflow. The roadmap breaks the vision into deliverable stages, each producing a demonstrable version of the project.

## Prerequisites

- `docs/aide/vision.md` must exist (created by `/speckit.aide.create-vision`)

## Instructions

Read `docs/aide/vision.md`. If `docs/aide/roadmap.md` already exists, **update it incrementally** — do not regenerate from scratch. If it does not exist, create it.

### Updating an Existing Roadmap

When updating an existing roadmap:

1. **Read `docs/aide/progress.md` first** to determine which stages are completed or in progress.
2. **Completed and in-progress stages are immutable** — never modify their goals, deliverables, dependencies, or acceptance criteria.
3. **Add new stages** at the end of the roadmap to cover new or changed vision features.
4. **Only planned/not-started stages may be edited** — adjust goals, deliverables, or acceptance criteria as needed.

### Requirements

1. **Staged delivery** — break the vision into incremental stages that build on each other
2. **Each stage is demonstrable** — every stage must deliver a version that can be shown and tested
3. **Each stage is testable** — include clear acceptance criteria per stage
4. **Logical progression** — features should flow naturally from foundational to advanced
5. **Prescriptive detail** — assume most work will be done by AI, so be as specific as possible
6. **Realistic scope** — each stage should be deployable locally and deliverable in about a week

### Output Format

Generate the document with:
- Description of each stage and its goals
- Bulleted list of specific deliverables per stage
- Dependencies between stages (if any)
- Testing/validation criteria per stage

### Output

Save the completed roadmap to `docs/aide/roadmap.md`.

### MANDATORY Worker/Reviewer Team Loop

You MUST execute this loop for every invocation. Instead of spawning a fresh one-shot subagent for each pass, create a **persistent team** of a Worker and a Reviewer so that both retain context across iterations. Do not stop until the Reviewer approves.

1. **Team Setup (once per invocation)**:
   - Call `TeamCreate` with `team_name: "aide-roadmap"` and a short description.
   - Spawn the **Worker** as a persistent teammate using the `Agent` tool: `team_name: "aide-roadmap"`, `name: "worker"`, `subagent_type: "general-purpose"`. Standing-role prompt: "You are the Worker. Each time you are messaged, generate (or incrementally update) a staged development roadmap based on the project vision in `docs/aide/vision.md`, following the create-roadmap requirements and structure, and save it with the `Write` tool to `docs/aide/roadmap.md`. Incorporate any reviewer feedback included in the message. When finished, `SendMessage` to `team-lead` reporting completion."
   - Spawn the **Reviewer** as a persistent teammate using the `Agent` tool: `team_name: "aide-roadmap"`, `name: "reviewer"`, `subagent_type: "roadmap-reviewer"`. Standing-role prompt: "You are the Reviewer. Each time you are messaged, critique the roadmap at the path provided against the vision document and MCP specification. When finished, `SendMessage` to `team-lead` reporting completion."
2. **Initialization**: Identify the current iteration number (starting at 001). Create the directory `docs/aide/versions/speckit.aide.create-roadmap/iteration-NNN/`.
3. **Worker Pass**: `SendMessage` to `worker` with the task for this iteration. If NNN > 001, include the previous iteration's reviewer feedback verbatim. Wait for the Worker to report completion.
4. **Snapshot**: Immediately copy the output from `docs/aide/roadmap.md` to `docs/aide/versions/speckit.aide.create-roadmap/iteration-NNN/roadmap.md`.
5. **Reviewer Pass**: `SendMessage` to `reviewer` pointing it at `docs/aide/versions/speckit.aide.create-roadmap/iteration-NNN/roadmap.md`. Instruct it to be meticulous, identify gaps/errors/improvements, save detailed feedback to `docs/aide/versions/speckit.aide.create-roadmap/iteration-NNN/reviewer-feedback.md`, and a JSON summary to `docs/aide/versions/speckit.aide.create-roadmap/iteration-NNN/reviewer-feedback.json` (fields: `overall_rating` (number), `needs_revision` (boolean), and `key_issues` (array of strings)). Wait for the Reviewer to report completion.
6. **Decision**:
   - Read the JSON summary from `docs/aide/versions/speckit.aide.create-roadmap/iteration-NNN/reviewer-feedback.json`.
   - **If `needs_revision` is `true`**: Increment the iteration number (NNN+1) and return to Step 3 — reuse the **same** Worker and Reviewer teammates (they keep their context), passing the latest feedback into the next Worker Pass.
   - **If `needs_revision` is `false`**: Mark the iteration as approved by saving a copy of the artifact to `docs/aide/versions/speckit.aide.create-roadmap/approved-version.md`. Proceed to teardown.
7. **Teardown**: Gracefully shut down both teammates via `SendMessage` with `message: {type: "shutdown_request"}`, then call `TeamDelete` to clean up the team.
## Next Step

After reviewing the roadmap, start a **new chat session** and run `/speckit.aide.create-progress` to create the progress tracking file.
