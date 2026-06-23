# Reviewer feedback — Item 009 (Stage S1 demo + closeout), iteration-001

**Verdict: APPROVED (needs_revision = false), first pass.**

The item's acceptance criteria are outcome-based (a renamed identifier or broken serializer is
caught by a failing `raco test`, not a silent pass), so verification is mechanical. Every AC was
re-confirmed green by running the actual commands, not by reading the transcript.

## AC verification

| AC | Result |
|---|---|
| Demo exists, `#lang racket/base`, requires only the item-008 barrel `mcp/core/main.rkt` | ✅ `raco make mcp/core/demo/s1-demo.rkt` → exit 0 |
| Runs end-to-end via plain `racket` | ✅ `racket mcp/core/demo/s1-demo.rkt` → exit 0; readable transcript, four arms, OK lines, error object + code |
| Arm 1 initialize round-trips canonical jsexpr (extraUnknownKey pruned) | ✅ `jsexpr=?` against `init-expect` (pruned), not raw bytes |
| Arm 2 tools/call round-trips canonical jsexpr (raw fixture) | ✅ |
| Both round-trip arms idempotent (second pass) | ✅ |
| Arm 3 malformed → JSON-RPC error via GENUINE contract rejection | ✅ decoder accepts `name=42`, `(contract …/c …)` raises, `exn->jsonrpc-error-jsexpr` → code -32603 |
| THE non-vacuous assertion (`#rx"contract violation"` present, `#rx"unexpectedly accepted"` absent) | ✅ present in `module+ test`; **drift-confirmed**: valid `name="ok"` → guard fires → 2/11 fail |
| `raco test` green across types + errors, no regression | ✅ 919 passed (908 inherited, +11), exit 0 |
| Demo adds no new types/structs/contracts/errors | ✅ grep → 0 |
| Does not create/write `mcp/examples/` | ✅ `test ! -d mcp/examples` holds |
| Portability not regressed | ✅ item-008 portability suite green within the 908; demo outside barrel import graph |
| progress.md boxes :56,:58,:59,:60,:61,:62 → [x]; :57 unchanged | ✅ |
| Stage S1 → ✅ in header + overview row + test-deliverable line | ✅ |
| Parity-matrix section updated (`core/types/*`, `errors/*` = `partial`); no new roadmap table | ✅ |
| Conservative goal/NFR edits (G1 NOT ✅) | ✅ G1 row + NFR rows left untouched |

## Drift / non-vacuity checks performed (not trusted from transcript)

1. **Canonical compare is live + prune load-bearing:** replacing arm-1 `expect` with the un-pruned
   `init-orig` → 1/11 failure (extraUnknownKey present in expect, dropped in rt). Reverted → green.
2. **Arm 3 non-vacuity:** replacing the malformed `name=42` with a valid `name="ok"` → contract
   accepts → loud guard fires → 2/11 failures (the contract-violation and not-fabricated
   assertions). Reverted + rebuilt → green. Confirms a regression that stops the contract raising
   FAILS this arm rather than passing it — the exact iteration-001 (create-item) blocker is closed.

## Notes

- `make-protocol-error` is imported but unused (shape A / plain `-32603` chosen over shape-B
  re-wrap). Kept in `only-in` as documentation of the available path; harmless. Recorded in
  Decisions #1/#5.
- Demo transcript lives in `(module+ main …)` so `raco test` output stays clean and a `require` of
  the demo prints nothing — cleaner than top-level prints. Recorded in Decisions #6.

No actionable criticism remaining.
