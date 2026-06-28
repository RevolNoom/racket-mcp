# Item 016 — Approved implementation (pointer)

- **Canonical item:** `docs/aide/items/016-stdio-framing.md` (Status ✅)
- **Deliverable:** `mcp/core/shared/stdio.rkt` (M5e, newline-delimited JSON framing; TS ReadBuffer port) + `mcp/core/shared/test/stdio-test.rkt`
- **Progress edits:** `docs/aide/progress.md` (deliverable :78 →✅, framing box :88 →[x])
- **Approved iteration:** `iteration-001`
- **Reviewer verdict:** 9.6, `needs_revision=false`. Pinned read-message! factoring clean (envelope raise outside the confined parse handler); CRITICAL invalid-envelope-raises + non-JSON-skips both pass.
- **Gates:** `raco make` exit 0; `raco test mcp/core/shared/` → 317 passed (+48 stdio); `raco test validators/ util/` → 402 passed.
- **Non-blocking notes:** progress.md:79 "except stdio-test.rkt" caveat now stale (item-017-owned row); try-parse-json-line trailing-bytes check caps at 1MB (unreachable by fixtures).
