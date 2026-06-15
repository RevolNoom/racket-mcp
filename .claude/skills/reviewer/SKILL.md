---
name: reviewer
description: "Review any user-provided task, seeking edge cases, verifying logic, identifying downsides, and proposing concrete alternative solutions with clear advantage proofs. Trigger on phrases like 'review', 'evaluate', 'audit', 'check', 'inspect', 'analyze', 'assess', 'validate', 'critique', 'examine', 'look over', 'give feedback on', 'run a review of', and any request that asks for a thorough assessment."
compatibility: "None – operates purely with Claude reasoning"
---

## Overview
The **reviewer** skill is a general‑purpose reviewer that can be invoked for code, designs, algorithms, proposals, or any other artefact where a critical eye is needed.

## Expected JSON Output
The skill must always return a JSON object with the following shape:
```json
{
  "summary": "Brief one‑sentence overview of the review",
  "edge_cases": [
    {"description": "What could go wrong", "impact": "Low|Medium|High"}
  ],
  "logic_verification": [
    {"statement": "Claim or step", "status": "correct|incorrect|uncertain", "explanation": "Why"}
  ],
  "downsides": [
    {"aspect": "Area of concern", "risk": "Low|Medium|High", "details": "Explanation"}
  ],
  "alternatives": [
    {"proposal": "Alternative approach", "advantage": "Concrete benefit (e.g., speed, safety, simplicity)", "tradeoff": "Any drawback"}
  ]
}
```
All fields are required; arrays may be empty if nothing applies.

## How to Use
1. **Provide the artefact** – either paste the code/design text directly in the prompt or give a brief description and a link to the source.
2. **Invoke the skill** – type `/reviewer` followed by your request, e.g.:
   ```
   /reviewer Review my sorting algorithm for edge‑case failures and suggest a faster alternative.
   ```
3. **Read the JSON** – the output can be fed to downstream tools or inspected manually.

## Example Prompt & Output
**Prompt**:
```
/reviewer Review this Python function that merges two sorted lists. Find edge cases and suggest a more efficient approach.
```
**Output** (formatted JSON):
```json
{
  "summary": "Merges two sorted lists correctly but fails on empty inputs and large lists due to O(n²) complexity.",
  "edge_cases": [
    {"description": "Both input lists empty", "impact": "High"},
    {"description": "One list much larger than the other", "impact": "Medium"}
  ],
  "logic_verification": [
    {"statement": "Loop iterates over both lists simultaneously", "status": "correct", "explanation": "Indices are advanced properly"}
  ],
  "downsides": [
    {"aspect": "Time complexity", "risk": "High", "details": "Current implementation is O(n²) because it repeatedly inserts at the front of a list"}
  ],
  "alternatives": [
    {"proposal": "Use a heap‑based merge (heapq.merge)", "advantage": "O(n log k) where k is number of lists, reduces memory moves", "tradeoff": "Requires import of heapq"},
    {"proposal": "Pre‑allocate result list and fill by index", "advantage": "O(n) time, no repeated inserts", "tradeoff": "Slightly more code"}
  ]
}
```

## Edge‑Case Guidance
- Always consider empty inputs, `null` values, and extremely large data sets.
- When reviewing security‑related artefacts, add a `"security": true` flag inside each relevant object (optional for downstream tooling).

## Frequently Asked Questions
**Q:** *Can the skill handle non‑text artefacts (e.g., images)?*\
**A:** Only if the user provides a textual description of the artefact. The skill itself does not process binary files.

**Q:** *What if I only want a subset of the sections?*\
**A:** The skill always returns the full JSON, but you may ignore sections you don’t need.

---

*This skill was created using the Skill‑Creator workflow. Feel free to iterate on the description or JSON schema as your use‑cases evolve.*