Item 008 (core barrels + restricted-load portability test) APPROVED by code review (5/5, needs_revision=false) on iteration 001 — approved on first pass.

Delivered:
- `mcp/core/types/main.rkt` — M1 barrel: re-exports constants.rkt, guards.rkt, (prefix-in r25:) spec-2025-11-25.rkt, (prefix-in r26:) spec-2026-07-28.rkt, types.rkt via five per-module `all-from-out`; 0 new defines. `prefix-in` resolves the 834-identifier mutual collision between the two per-revision spec modules with no except-out/rename-out needed.
- `mcp/core/main.rkt` — top M1+M2 barrel: `(all-from-out "types/main.rkt")` + `(all-from-out "errors.rkt")`; 0 new defines.
- `mcp/core/test/main-test.rkt` — 29 new checks: 8 barrel re-export presence (1 per underlying module), 16 transitive portability walk (2 barrels × 8 banned module paths, in a fresh make-base-namespace, with the base-dir-threaded relative-path-resolution fix and the module->imports single-value handling), 5 curation negatives (split-loose/h-opt/put! via types/main.rkt; url-elicitation-data?/unsupported-version-data? via main.rkt → all 'not-found).

Verification (reviewer re-ran live, did not trust transcript):
- `raco make mcp/core/types/main.rkt mcp/core/main.rkt` → exit 0.
- `raco test mcp/core/types/ mcp/core/test/` → 908 tests passed (879 inherited, 0 regressed + 29 new), exit 0.
- 2-hop drift injection independently reproduced: `(require racket/tcp)` into spec-2025-11-25.rkt (main.rkt→types.rkt→spec-2025-11-25.rkt) → 2/29 fail naming racket/tcp; reverted byte-identical (diff-confirmed) → 29/29 pass.
- One-directional DAG confirmed (no cycle); grep -c '^(define' → 0/0 on both barrels.

Progress: progress.md line 52 (barrels) flipped 🚧→✅; line 53 (test dir) set 🚧 with shared-ownership note (demo + final closeout left to item 009); Stage S1 header intentionally left 📋 (item 009's call). Items 001–007 untouched.

Deviations (both minor, spec-sanctioned): (1) item-005 façade representative binding uses `facade-text-content?` (the spec's suggested `facade-implementation?` does not exist in types.rkt); (2) banned-path comparison uses path-tail regexp since every racket/* module resolves to a collects/ path in this Racket 8.18 environment (no symbol-shaped resolved names occurred).
