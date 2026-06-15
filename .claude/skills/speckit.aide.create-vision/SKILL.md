---
name: speckit.aide.create-vision
description: Create a technical architecture based on the project vision. Use this skill whenever the user needs to define modules, interfaces, or the tech stack before starting a roadmap.
---

# Create Vision

Create a comprehensive vision document for the project described below.

## Purpose

This is Step 1 of the AI-Driven Engineering workflow. The vision document is the foundation for all subsequent steps — roadmap, progress tracking, work items, and implementation all flow from this document.

## User Input

{{args}}

## Instructions

### Existing Vision Check

Before creating, check if `docs/aide/vision.md` already exists.
- If it exists, **warn the user** and show a brief summary of the existing vision.
- Ask for confirmation before overwriting.
- If the user wants to update rather than replace, incorporate their input as amendments to the existing document.

### Creating the Vision

Create (or update) the vision document and store it in `docs/aide/vision.md`.

### Requirements

1. **Be exhaustive** — cover all aspects of the project scope
2. **Explain reasoning** — justify what is included and why
3. **Document exclusions** — explicitly state what is out of scope and why
4. **Be specific** — include technology choices, constraints, and assumptions
5. **Structure clearly** — use headings, lists, and sections for readability

### Suggested Structure

The vision document should cover (adapt to the specific project):

- **Project Overview** — what is being built and why
- **Goals & Objectives** — measurable outcomes
- **Target Users** — who will use this and how
- **Core Features** — detailed feature descriptions
- **Technical Architecture** — technology stack, infrastructure, deployment
- **Non-Functional Requirements** — performance, security, scalability, accessibility
- **Constraints & Assumptions** — technical, business, and timeline constraints
- **Out of Scope** — what is explicitly excluded from this project
- **Success Criteria** — how to measure project success

### Output

Save the completed vision document to `docs/aide/vision.md`.

### MANDATORY Worker/Reviewer Team Loop

You MUST execute this loop for every invocation. Instead of spawning a fresh one-shot subagent for each pass, create a **persistent team** of a Worker and a Reviewer so that both retain context across iterations. Do not stop until the Reviewer approves.

1. **Team Setup (once per invocation)**:
   - Call `TeamCreate` with `team_name: "aide-vision"` and a short description (e.g., "Worker/Reviewer loop for the project vision").
   - Spawn the **Worker** as a persistent teammate using the `Agent` tool: `team_name: "aide-vision"`, `name: "worker"`, `subagent_type: "general-purpose"`. Standing-role prompt: "You are the Worker. Each time you are messaged, (re)create a comprehensive vision document for: {{args}}, following the create-vision structure and requirements, and save it with the `Write` tool to `docs/aide/vision.md`. Incorporate any reviewer feedback included in the message. When finished, `SendMessage` to `team-lead` reporting completion."
   - Spawn the **Reviewer** as a persistent teammate using the `Agent` tool: `team_name: "aide-vision"`, `name: "reviewer"`, `subagent_type: "vision-spec-reviewer"`. Standing-role prompt: "You are the Reviewer. Each time you are messaged, critique the vision document at the path provided against the project goals and MCP specification. When finished, `SendMessage` to `team-lead` reporting completion."
2. **Initialization**: Identify the current iteration number (starting at 001). Create the directory `docs/aide/versions/speckit.aide.create-vision/iteration-NNN/`.
3. **Worker Pass**: `SendMessage` to `worker` with the task for this iteration. If NNN > 001, include the previous iteration's reviewer feedback verbatim so the Worker can address it. Wait for the Worker to report completion.
4. **Snapshot**: Immediately copy the output from `docs/aide/vision.md` to `docs/aide/versions/speckit.aide.create-vision/iteration-NNN/vision.md`.
5. **Reviewer Pass**: `SendMessage` to `reviewer` pointing it at `docs/aide/versions/speckit.aide.create-vision/iteration-NNN/vision.md`. Instruct it to be meticulous, identify gaps/errors/improvements, save detailed feedback to `docs/aide/versions/speckit.aide.create-vision/iteration-NNN/reviewer-feedback.md`, and a JSON summary to `docs/aide/versions/speckit.aide.create-vision/iteration-NNN/reviewer-feedback.json` (fields: `overall_rating` (number), `needs_revision` (boolean), and `key_issues` (array of strings)). Wait for the Reviewer to report completion.
6. **Decision**:
   - Read the JSON summary from `docs/aide/versions/speckit.aide.create-vision/iteration-NNN/reviewer-feedback.json`.
   - **If `needs_revision` is `true`**: Increment the iteration number (NNN+1) and return to Step 3 — reuse the **same** Worker and Reviewer teammates (they keep their context), passing the latest feedback into the next Worker Pass.
   - **If `needs_revision` is `false`**: Mark the iteration as approved by saving a copy of the artifact to `docs/aide/versions/speckit.aide.create-vision/approved-version.md`. Proceed to teardown.
7. **Teardown**: Gracefully shut down both teammates via `SendMessage` with `message: {type: "shutdown_request"}`, then call `TeamDelete` to clean up the team.
## Next Step

After reviewing the vision document, start a **new chat session** and run `/speckit.aide.create-architecture` to define the technical architecture.
