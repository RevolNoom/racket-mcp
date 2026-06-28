---
name: speckit.aide.feedback-loop
description: Create a technical architecture based on the project vision. Use this skill whenever the user needs to define modules, interfaces, or the tech stack before starting a roadmap.
---

# Feedback Loop

Analyze what went wrong and identify improvements needed.

## Purpose

This is Step 8 of the AI-Driven Engineering workflow. Use this whenever work didn't go smoothly — when you needed help, found unclear requirements, or the process broke down. This step is available at any point in the workflow.

## Instructions

Analyze the current state of the project documents and recent work to identify improvements.

### 1. Document Gaps

- What should have been in `docs/aide/vision.md` but wasn't?
- What should have been in `docs/aide/roadmap.md` (dependencies, prerequisites)?
- What should have been in `docs/aide/progress.md` for tracking?
- Was the work item specification missing critical information?

### 2. Process Issues

- Did the human need to intervene? Why?
- Were requirements unclear or ambiguous?
- Were dependencies not identified upfront?
- Did scope expand unexpectedly?

### 3. Command Adaptations Needed

The AIDE commands may need project-specific adjustments. Because Spec Kit installs extension commands into agent-specific directories, the installed copies must be located and updated:

**Finding installed commands:**
- Look for AIDE command files in agent-specific directories such as:
  - `.claude/commands/` (Claude Code)
  - `.github/prompts/` (GitHub Copilot commands)
  - `.github/agents/` (GitHub Copilot agents)
  - `.gemini/commands/` (Gemini CLI)
  - `.cursor/commands/` (Cursor)
  - Or any other agent directory present in the project
- Also check for installed skills (e.g., in `.github/skills/` or similar)
- Search for files containing `speckit.aide` to locate all installed copies

**What to adapt:**
- Should the create-item command be adapted for this project's needs?
  - Example: Add "API Contract" section for API-heavy projects
  - Example: Add "Database Migration" section for data-intensive projects
  - Example: Add "Security Review" section for sensitive systems
- Should we create project-specific commands? (e.g., testing strategy, deployment checklist)
- What worked well that we should keep?

**When modifying commands**, update the installed copies in the agent-specific directories — these are the files that actually get executed.

### 4. Recommendations

Provide specific, actionable suggestions:
- Updates to vision/roadmap/progress
- Changes to command templates
- New commands to create
- Process improvements

### Important Notes

- **Routine decisions** during smooth implementation belong in the work item's "Decisions" section, not here.
- This feedback loop is for **systemic issues** that need process, document, or command improvements.
- **Be minimal** — suggest the smallest set of changes that will prevent the problem from recurring.

### Worker/Reviewer Team Loop

This command participates in the worker/reviewer loop. Instead of spawning a fresh one-shot subagent for each pass, create a **persistent team** of a Worker and a Reviewer so that both retain context across iterations.

1. **Team Setup (once per invocation)**: Call `TeamCreate` with `team_name: "aide-feedback"`. Spawn a persistent **Worker** via the `Agent` tool (`team_name: "aide-feedback"`, `name: "worker"`, `subagent_type: "general-purpose"`) whose standing role is to analyze the project state, produce the recommended document/command improvements per these instructions, and apply the minimal set of changes — then `SendMessage` `team-lead` when done. Spawn a persistent **Reviewer** via the `Agent` tool (`team_name: "aide-feedback"`, `name: "reviewer"`, `subagent_type: "general-purpose"`) whose standing role is to verify the recommendations are minimal, actionable, and address the systemic issue, then report back.
2. Create or update `docs/aide/versions/<command-name>/iteration-NNN/` before work begins.
3. **Worker Pass**: `SendMessage` to `worker` with the task (and prior reviewer feedback if NNN > 001). Wait for completion, then save a snapshot of changed files.
4. **Reviewer Pass**: `SendMessage` to `reviewer`; have it save feedback to `docs/aide/versions/<command-name>/iteration-NNN/reviewer-feedback.md` and store the reviewer result in `reviewer-feedback.json` when JSON is produced.
5. If the reviewer has actionable criticism, increment the iteration number and return to the Worker Pass — reusing the **same** teammates so they keep their context.
6. If the reviewer has nothing left to criticize, mark this iteration as approved in `docs/aide/versions/<command-name>/approved-version.md`, shut down both teammates via `SendMessage` `{type: "shutdown_request"}`, and call `TeamDelete`.
7. Preserve the original output path for this command as the latest approved artifact, while keeping every rejected/intermediate version in the version directory.

## Next Step

After applying the recommended changes, resume the workflow from where you left off. Start a **new chat session** for the next step.
