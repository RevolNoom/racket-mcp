Item 009 (Stage S1 demo + parity-matrix/progress closeout) APPROVED by review (5/5, needs_revision=false) on iteration 001 — approved on first pass. This is the FINAL item of queue-001 and completes Stage S1.

Delivered:
- `mcp/core/demo/s1-demo.rkt` — `#lang racket/base` demo, pure consumer of the item-008 barrel `mcp/core/main.rkt` (0 new types/structs/contracts/errors; grep → 0). Four labelled arms + a `module+ test` (11 checks):
  - Arm 1 — `initialize` request JSON → struct → JSON, canonical `jsexpr=?` round-trip with `extraUnknownKey` pruned from `params` (mirrors spec-2025-11-25-test.rkt:77–81) + idempotence.
  - Arm 2 — `tools/call` request round-trip against raw fixture + idempotence.
  - Arm 3 — malformed `(hasheq 'name 42 'arguments (hasheq))`: decoder ACCEPTS it (does not self-reject), `(contract r25:call-tool-request-params/c … 'demo 'demo)` RAISES the `string?` violation, `exn->jsonrpc-error-jsexpr` → JSON-RPC error object code `-32603`. Non-vacuous assertions (`#rx"contract violation"` present, `#rx"unexpectedly accepted"` absent); `err-obj` producible ONLY by the contract raise (loud guard otherwise fails the test).
  - Arm 4 — `error-response.json` full envelope round-trip.
  - Transcript in `(module+ main …)` so `racket <demo>` shows it while `raco test` stays clean.
- `docs/aide/progress.md` closeout: Stage S1 → ✅ in the stage-overview row, the `## Stage S1` header, and the shared test-deliverable line (🚧→✅); acceptance boxes :56,:58,:59,:60,:61,:62 → [x] (:57 already [x], untouched); "Parity matrix progression" section rewritten — `core/types/*` and `errors/*` now `partial` (conformance deferred to S9), "no rows yet" removed, icon 📋→🚧. G1 row + NFR rows left untouched (S1 only partially satisfies G1; full wire-parity is S9-certified).

Verification (re-run live, not trusted from transcript):
- `raco make mcp/core/demo/s1-demo.rkt` → exit 0.
- `racket mcp/core/demo/s1-demo.rkt` → exit 0 (and exit 0 from /tmp — CWD-independent via `define-runtime-path`).
- `raco test mcp/core/demo/s1-demo.rkt` → 11 passed.
- `raco test mcp/core/types/ mcp/core/test/ mcp/core/demo/` → 919 passed, exit 0 (908 inherited from items 001–008, 0 regressed, +11 new). This extended command is the canonical S1 green command going forward.
- Drift injection #1: un-pruned arm-1 `expect` → 1/11 fail (canonical compare + prune load-bearing) → reverted green.
- Drift injection #2: valid `name="ok"` → contract accepts → guard fires → 2/11 fail (Arm-3 non-vacuity proven; the create-item iteration-001 vacuous-test blocker is closed) → reverted + rebuilt green.
- `test ! -d mcp/examples` holds (no S9/M15 collision); demo lives under new `mcp/core/demo/`.

Decisions of record: shape A (plain `-32603`, no shape-B `-32602` re-wrap); arm 4 included; final command extended to cover `mcp/core/demo/`; all four load-bearing `r25:` names + the error-encode path resolved through the barrel as specified; no new `roadmap.md` table; G1 not over-claimed.

Stage S1 is COMPLETE. queue-001 exhausted → queue-002 / Stage S2 unblocked.
