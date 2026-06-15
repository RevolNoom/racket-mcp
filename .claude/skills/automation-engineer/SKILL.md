---
name: automation-engineer
description: >-
  Transform a user’s repeated manual or AI‑Agent procedure into an executable script that can be run by AI Agent commands, reducing token consumption, improving accuracy, and enabling reliable replication. Trigger on phrases such as “automate this”, “create a script for”, “turn this into a command”, “generate a reusable workflow”, “write a bash/python/... script”, “repeatable procedure”, “reduce token usage”, “optimize for agents”, “script this task”, “automation request”, “agent‑friendly script”, “convert to AI‑command”, “create an automation‑engineer script”, and any request that asks for a repeatable, agent‑driven automation.
compatibility: "None – pure Claude reasoning; no external tools required"
---

## Overview
The **automation‑engineer** skill helps you turn a description of a repetitive, multi‑step procedure—whether it is a human‑typed series of commands **or** an AI‑Agent’s own repeated workflow—into a concise, self‑contained script. The script can then be executed by an AI Agent with a single `Bash` (or appropriate) call, saving you from re‑prompting the model each time and cutting token usage dramatically.

## Recognizing AI‑Agent Repeated Procedures
AI Agents often emit the same sequence of commands across many runs (e.g., scaffolding a project, linting, deploying). When the user supplies a transcript of such a run, the skill will:
1. **Detect repetition** – look for identical or near‑identical command blocks.
2. **Abstract parameters** – replace literals (paths, names, versions) with variables.
3. **Generate a reusable script** – include placeholders and a short usage guide.
4. **Provide an execution hint** – how to invoke the script via an Agent command.

## Expected JSON Output
The skill always returns a JSON object with this exact schema:
```json
{
  "summary": "One‑sentence overview of the generated script.",
  "script_language": "bash | python | powershell | node | ...",
  "script_name": "suggested filename (e.g., automate_task.sh)",
  "script_content": "<full script text, escaped for JSON>",
  "execution_hint": "How to run the script with an AI Agent, e.g., `! bash automate_task.sh`",
  "token_savings_estimate": "Approximate tokens saved per execution (optional)",
  "notes": "Caveats, required env vars, parameterization details"
}
```
All fields are required; arrays are not needed for this skill.

## How to Use
1. **Provide the procedure** – paste the full manual steps, a concise description, or a transcript of an AI Agent run.
   ```text
   /automation-engineer Automate this repeated git‑workflow:
   git checkout feature-x
   git pull origin main
   npm install
   npm run test
   git add .
   git commit -m "auto test"
   git push origin feature-x
   ```
2. **Invoke the skill** – type `/automation-engineer` followed by the request (any of the trigger phrases above).
3. **Read the JSON** – copy `script_content` to a file named `script_name`, make it executable if needed, and run it using the provided `execution_hint`.

## Example Prompt & Output
**Prompt**
```
/automation-engineer Turn this AI‑Agent transcript into a reusable Bash script that builds, tags, pushes, and runs a Docker container.
---
Agent output:
docker build -t myapp:latest .
docker tag myapp:latest registry.example.com/myapp:latest
docker push registry.example.com/myapp:latest
docker run -d -p 8080:80 registry.example.com/myapp:latest
```
**Output**
```json
{
  "summary": "Build, tag, push, and run a Docker container for the myapp service.",
  "script_language": "bash",
  "script_name": "deploy_myapp.sh",
  "script_content": "#!/usr/bin/env bash\nset -euo pipefail\n\n# Build image\ndocker build -t myapp:latest .\n# Tag for registry\ndocker tag myapp:latest registry.example.com/myapp:latest\n# Push to registry\ndocker push registry.example.com/myapp:latest\n# Run container\ndocker run -d -p 8080:80 registry.example.com/myapp:latest\n",
  "execution_hint": "Save the content to deploy_myapp.sh, make it executable (`chmod +x deploy_myapp.sh`), then run `! ./deploy_myapp.sh` in the Claude session.",
  "token_savings_estimate": "≈ 350 tokens per execution (vs re‑prompting the full 4‑step list each time)",
  "notes": "Docker must be installed and you must be logged into the registry before running the script."
}
```

## Edge‑Case Guidance
- **Parameterization** – If the user mentions “different environments” or “varying version numbers”, the skill will replace those literals with positional arguments (`$1`, `$2`, …) and document them in `notes`.
- **Interactive steps** – When a step requires user input (e.g., `read` or `sudo`), the script will include a comment `# TODO: user interaction required` and the `notes` will flag it.
- **Large transcripts** – For very long Agent logs, the skill will group related commands into functions and expose a simple top‑level entry point.
- **Language selection** – Default to `bash` for Unix‑style command sequences, `python` for data‑processing pipelines, `powershell` for Windows‑only steps, and `node` for JavaScript‑centric workflows. Explicit language requests are respected.

## Frequently Asked Questions
**Q:** *Can the skill handle mixed‑language procedures?*\
**A:** Yes. The skill will split the transcript into language‑specific blocks and generate separate scripts, then return a JSON object with a `scripts` array (each entry follows the same schema). For simplicity, the basic version returns a single script; you can request “multiple scripts” for mixed cases.

**Q:** *What if the original procedure includes secret values?*\
**A:** The skill will redact any strings that look like passwords or tokens (patterns of 20+ alphanumeric characters) and add a note: “Insert secret values via environment variables or a secure vault.”

**Q:** *How accurate is the token‑saving estimate?*\
**A:** It is a rough calculation based on the token count of the original step list versus the JSON payload plus a single‑command invocation. It gives a useful ballpark but is not a guarantee.

---

*Created with the Skill‑Creator workflow. Feel free to iterate on the description, trigger phrases, or JSON schema as your automation needs evolve.*