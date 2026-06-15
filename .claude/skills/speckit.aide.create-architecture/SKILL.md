---
name: speckit.aide.create-architecture
description: Create a technical architecture based on the project vision. Use this skill whenever the user needs to define modules, interfaces, or the tech stack before starting a roadmap.
---

# Create Architecture

Create a detailed technical architecture based on the project vision.

## Purpose

This is Step 2 of the AI-Driven Engineering workflow. Architecture bridges the gap between a high-level vision and a staged roadmap by defining the structural components, their boundaries, and how they communicate.

## Prerequisites

- `docs/aide/vision.md` must exist (created by `/speckit.aide.create-vision`)

## Instructions

Read `docs/aide/vision.md`. If `docs/aide/architecture.md` already exists, **update it incrementally** to accommodate new vision changes. If it does not exist, create it.

### Architectural Requirements

1. **Module Breakdown**: Decompose the vision into a set of logical modules. The sum of all modules must fully cover the entire scope defined in the vision.
2. **Interface Granularity**: For every module, define its interfaces.
   - **Internal Communication**: Detail how interfaces communicate with each other *inside* a module.
   - **External Communication**: Detail how modules communicate with *each other*.
3. **Technology Specification**: You may specify the technology stack, including specific languages, frameworks, libraries, or infrastructure components.
4. **No Implementation Enforcement**: The architecture defines *what* and *how* (at a structural level), not the exact code. Do not specify implementation details (e.g., specific function names or variable types) that are the responsibility of developers in later steps.

### Output Format

The architecture document should include:
- **System Overview**: High-level architectural pattern (e.g., Microservices, Layered, Event-Driven).
- **Module Definitions**: For each module:
    - Purpose and scope.
    - List of interfaces and their responsibilities.
    - Communication protocols/patterns used.
- **Interface Map**: A description or table showing the data flow and dependencies between modules.
- **Tech Stack**: Detailed list of chosen technologies and the reasoning behind them.

### Output

Save the completed architecture document to `docs/aide/architecture.md`.

### MANDATORY Worker/Reviewer Team Loop

You MUST execute this loop for every invocation. Instead of spawning a fresh one-shot subagent for each pass, create a **persistent team** of a Worker and a Reviewer so that both retain context across iterations. Do not stop until the Reviewer approves.

1. **Team Setup (once per invocation)**:
   - Call `TeamCreate` with `team_name: "aide-architecture"` and a short description.
   - Spawn the **Worker** as a persistent teammate using the `Agent` tool: `team_name: "aide-architecture"`, `name: "worker"`, `subagent_type: "general-purpose"`. Standing-role prompt: "You are the Worker. Each time you are messaged, (re)create a detailed technical architecture based on the project vision in `docs/aide/vision.md`, following the create-architecture requirements and structure, and save it with the `Write` tool to `docs/aide/architecture.md`. Incorporate any reviewer feedback included in the message. When finished, `SendMessage` to `team-lead` reporting completion."
   - Spawn the **Reviewer** as a persistent teammate using the `Agent` tool: `team_name: "aide-architecture"`, `name: "reviewer"`, `subagent_type: "architecture-reviewer"`. Standing-role prompt: "You are the Reviewer. Each time you are messaged, critique the architecture at the path provided against the vision document. When finished, `SendMessage` to `team-lead` reporting completion."
2. **Initialization**: Identify the current iteration number (starting at 001). Create the directory `docs/aide/versions/speckit.aide.create-architecture/iteration-NNN/`.
3. **Worker Pass**: `SendMessage` to `worker` with the task for this iteration. If NNN > 001, include the previous iteration's reviewer feedback verbatim. Wait for the Worker to report completion.
4. **Snapshot**: Immediately copy the output from `docs/aide/architecture.md` to `docs/aide/versions/speckit.aide.create-architecture/iteration-NNN/architecture.md`.
5. **Reviewer Pass**: `SendMessage` to `reviewer` pointing it at `docs/aide/versions/speckit.aide.create-architecture/iteration-NNN/architecture.md`. Instruct it to verify that: 1) All vision requirements are covered by the modules. 2) Interfaces are defined at sufficient granularity. 3) No implementation details are enforced. 4) The tech stack is consistent. Have it save detailed feedback to `docs/aide/versions/speckit.aide.create-architecture/iteration-NNN/reviewer-feedback.md` and a JSON summary to `docs/aide/versions/speckit.aide.create-architecture/iteration-NNN/reviewer-feedback.json` (fields: `overall_rating` (number), `needs_revision` (boolean), and `key_issues` (array of strings)). Wait for the Reviewer to report completion.
6. **Decision**:
   - Read the JSON summary from `docs/aide/versions/speckit.aide.create-architecture/iteration-NNN/reviewer-feedback.json`.
   - **If `needs_revision` is `true`**: Increment the iteration number (NNN+1) and return to Step 3 — reuse the **same** Worker and Reviewer teammates (they keep their context), passing the latest feedback into the next Worker Pass.
   - **If `needs_revision` is `false`**: Mark the iteration as approved by saving a copy of the artifact to `docs/aide/versions/speckit.aide.create-architecture/approved-version.md`. Proceed to teardown.
7. **Teardown**: Gracefully shut down both teammates via `SendMessage` with `message: {type: "shutdown_request"}`, then call `TeamDelete` to clean up the team.

## Next Step

After reviewing the architecture document, start a **new chat session** and run `/speckit.aide.create-roadmap` to generate a staged development roadmap.
