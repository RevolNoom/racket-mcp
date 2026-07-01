# Work Item 022: S3 transport portability sweep + parity-matrix touch

> **Queue:** `docs/aide/queue/queue-003.md` — Item 022
> **Stage:** S3 (Transport port + in-memory adapter — L1 part 1)
> **Modules touched (TEST + DOCS only, no permanent module source changes):** `mcp/transport/transport.rkt` (M6, item 019), `mcp/transport/in-memory.rkt` (M10, item 020) — walked via the single barrel `mcp/transport/main.rkt`.
> **Source vision:** `docs/aide/vision.md` §6 (Portability NFR — runtime-neutral core L0–L2 loads with no subprocess/socket/web-server module), G3 (parity-matrix discipline).
> **Source roadmap:** `docs/aide/roadmap.md` Stage S3 — acceptance lines `roadmap.md:157-158` (no subprocess/socket; parity rows `transport.ts`, `inMemory.ts` marked `partial`).
> **S2 analogue (MATCH THIS STYLE):** `docs/aide/items/017-s2-portability-and-parity-touch.md` — S3 is the same pattern, one barrel instead of seven roots.
> **S1 walk template (REUSE verbatim):** `mcp/core/test/main-test.rkt:43-114`.
> **Status:** ✅

---

## Description

Closes Stage S3's two outstanding cross-cutting obligations. Writes **no permanent module source** — one new test file plus `progress.md` edits.

**1. The S3 restricted-load portability proof.** `mcp/transport/transport.rkt` (M6) and `mcp/transport/in-memory.rkt` (M10) each carry inline comments stating "NO net/url, subprocess, socket, web-server" (`transport.rkt:17`, `in-memory.rkt:11`). What is still missing — and what item 022 closes — is the **formal restricted-load portability sweep**: walk the barrel `mcp/transport/main.rkt` transitively in a fresh base namespace and assert no banned module is ever reachable.

The sweep mirrors `mcp/core/test/main-test.rkt:43-114` (the S1 template) and `mcp/core/test/s2-portability-test.rkt` (the S2 extension). Copy the walk helpers verbatim.

**S3-specific addition — web-server ban.** The S1 `banned-module-paths` list (`main-test.rkt:49-51`) does NOT include `web-server`. The transport layer must be free of web-server imports too (Portability NFR). Because `banned-hit?` (`main-test.rkt:101-104`) matches `#rx"/<sym>(\.rkt)?$"`, a bare `web-server` symbol catches only a path ending in `/web-server.rkt` — it would miss nested paths like `web-server/http`. Add a **separate assertion** over the visited set: `(check-false (for/or ([m (in-set visited)]) (and (path? m) (regexp-match? #rx"/web-server/" (path->string m)))) "transport barrel transitively imports web-server collection")`.

**2. The parity-matrix touch.** Flip the two S3 parity acceptance boxes (`progress.md:109-110`) and append a parity narrative sentence (`progress.md:338`). Add an S3 Deliverables line for the new test file. `roadmap.md:157-158` acceptance lines already state the requirement — no §9 materialized table exists (same finding as item 017); record that fact in the narrative and make no roadmap edit.

### The mechanism (reuse the S1 walk verbatim)

`main-test.rkt:60-105` defines everything needed; **copy** into the new test:
- `banned-module-paths` (`main-test.rkt:49-51`) = `'(racket/system racket/port racket/tcp racket/udp net/url net/http-client net/sendurl racket/sandbox)`.
- Helpers `resolve-mpi`/`dir-of`/`direct-imports`/`transitive-imports`/`banned-hit?`/`check-portable!` (`main-test.rkt:60-105`).
- Same requires (`main-test.rkt:13-16`): `rackunit racket/set racket/path racket/runtime-path`.
- `(define-runtime-path here ".")` then `(simplify-path (build-path here ".." "main.rkt"))` for the barrel path. (`here` = `mcp/transport/test/`; `..` = `mcp/transport/`; `main.rkt` = the barrel.)

The sweep walks **one root** — the barrel `mcp/transport/main.rkt` — which transitively covers both M6 and M10:
- `transport.rkt:19-22` imports `racket/generic racket/contract "../core/main.rkt" "../core/shared/auth.rkt"`.
- `in-memory.rkt:13-15` imports `racket/generic racket/async-channel "transport.rkt"`. (`racket/async-channel` is in-process and NOT in `banned-module-paths`.)

**Important:** `racket/port` IS in the ban list. If `racket/async-channel` transitively pulls `racket/port` (or any other banned module), the sweep will go RED — this is a **real portability finding** and MUST be surfaced/escalated, NOT suppressed by removing the entry from `banned-module-paths` or adding an exemption.

`base-dir = (path-only root-path)` (the barrel lives in `mcp/transport/`; threading the correct dir ensures relative requires like `../core/main.rkt` resolve without truncation).

#### Non-vacuity / teeth-proving guard (PINNED)

A truncated walk reports ~79 visited (racket/base's own closure) and passes `(> (set-count visited) 1)` green. Prove non-vacuity by **path presence**: assert `visited` contains a resolved path matching `#rx"core/main\\.rkt"` — proving `transport.rkt`'s `../core/main.rkt` import actually resolved and the walk reached the S1 subtree.

A positive-match helper mirroring `banned-hit?`:
```racket
(define (visited-has? visited rx)
  (for/or ([m (in-set visited)])
    (and (path? m) (regexp-match? rx (path->string m)))))
```
Then: `(check-true (visited-has? visited #rx"core/main\\.rkt") "walk truncated — S1 edge not reached")`.

**MANDATORY second guard — M10 reachability.** Also assert `visited` contains a path matching `#rx"in-memory\\.rkt"` (or `#rx"async-channel"` as proxy). This proves the barrel's second branch (`in-memory.rkt`) was reached — a truncated walk that stops at `transport.rkt` would pass the `core/main.rkt` guard but silently miss M10. Both guards together prove both branches are non-vacuously covered:
```racket
(check-true (visited-has? visited #rx"core/main\\.rkt")  "walk truncated — S1 edge not reached")
(check-true (visited-has? visited #rx"in-memory\\.rkt")  "walk truncated — M10 branch not reached")
```

#### Scope guards

- No permanent module source edits. The **only** time a module file is touched is the mandatory teeth mutation (see Step 4) — and it is always reverted.
- Walk ONE root (the barrel) — do NOT enumerate `transport.rkt`/`in-memory.rkt` separately or glob.
- Existing tests (`transport-test.rkt`, `in-memory-test.rkt`) stay unchanged.

---

## Acceptance Criteria

- [ ] `mcp/transport/test/portability-test.rkt` exists as `#lang racket/base` with `(require rackunit racket/set racket/path racket/runtime-path)` (mirrors `main-test.rkt:13-16`).
- [ ] Defines (copied verbatim from `main-test.rkt:49-105`) `banned-module-paths` + `resolve-mpi`/`dir-of`/`direct-imports`/`transitive-imports`/`banned-hit?`/`check-portable!`. `banned-module-paths` matches `main-test.rkt:49-51` exactly (8 entries; no `web-server` in the list — the web-server check is a separate assertion).
- [ ] Walks **exactly ONE root** — `mcp/transport/main.rkt` — built via `(define-runtime-path here ".")` + `(simplify-path (build-path here ".." "main.rkt"))`.
- [ ] `base-dir = (path-only root-path)` passed to the walk (so `transport.rkt`'s `../core/main.rkt` relative import resolves correctly).
- [ ] `check-portable!` asserts no `banned-module-paths` entry is transitively reachable.
- [ ] **web-server collection assertion (S3-specific).** A `check-false` over `(for/or ([m (in-set visited)]) (and (path? m) (regexp-match? #rx"/web-server/" (path->string m))))` with a descriptive failure string. This catches nested web-server paths (e.g. `web-server/http`) that `banned-hit?`'s single-name regex would miss.
- [ ] **Teeth-proving non-vacuity guards (TWO, both mandatory).** `(check-true (visited-has? visited #rx"core/main\\.rkt") …)` — proves M6 branch / S1 edge resolved. `(check-true (visited-has? visited #rx"in-memory\\.rkt") …)` — proves M10 branch reached. Bare `(> (set-count visited) 1)` is NOT sufficient.
- [ ] **Teeth / mutation check performed (TWO injections, both mandatory):**
  - **(a)** Temporarily add `(require racket/tcp)` to one swept module; confirm sweep goes RED (banned-module loop fires); revert; confirm green. Proves the `banned-module-paths` assertions bite.
  - **(b)** Temporarily add `(require web-server/http)` to one swept module; confirm sweep goes RED (the `#rx"/web-server/"` `check-false` fires); revert; confirm green. Proves the web-server assertion bites (it would never fire naturally since no swept module imports web-server, so without this mutation the regex could be silently wrong forever).
  Both injections and RED confirmations recorded in Decisions.
- [ ] `raco test mcp/transport/` is green (exit 0) — runs the new portability sweep AND all existing transport tests (`transport-test.rkt`, `in-memory-test.rkt`). This is the acceptance gate.
- [ ] **Parity box** (anchor by text `- [ ] Load test: still no subprocess/socket module pulled in`; hint: `progress.md:109`): flip to `[x]`.
- [ ] **Parity box** (anchor by text `- [ ] Parity rows \`transport.ts\`, \`inMemory.ts\` marked \`partial\``; hint: `progress.md:110`): flip to `[x]`. Line numbers are hints — sibling items 020/021/023 may shift them; always locate by box text.
- [ ] **S3 Deliverables line** added to `progress.md` Stage S3 section for the new test file (e.g. `✅ mcp/transport/test/portability-test.rkt — S3 restricted-load portability sweep (item 022)`).
- [ ] **Parity narrative** (`progress.md:338`): an item-022 sentence appended following the `**Item 0NN (Stage SN):** …` pattern; names `transport.ts`/`inMemory.ts`, states `partial`, cites `raco test mcp/transport/` green + the web-server extra assertion; notes full conformance deferred to S9.
- [ ] **Roadmap §9:** no materialized parity table exists — acceptance lines `roadmap.md:157-158` stand unedited. Fact recorded in progress narrative.

---

## Implementation Steps

1. **Read the template once:** `mcp/core/test/main-test.rkt:43-114` (walk + application). No need to re-read the module sources.
2. **Create `mcp/transport/test/portability-test.rkt`** (`#lang racket/base`):
   - Same `require`s as `main-test.rkt:13-16`.
   - Copy `banned-module-paths` + the six walk helpers from `main-test.rkt:49-105` verbatim.
   - `(define-runtime-path here ".")`.
   - `(define root (simplify-path (build-path here ".." "main.rkt")))`.
   - In `(parameterize ([current-namespace (make-base-namespace)]) …)`, call `transitive-imports` with `root` and `(path-only root)` to get `visited`.
   - Assert: `check-portable!` (banned-module loop) + web-server collection `check-false` + TWO mandatory `check-true` guards: `#rx"core/main\\.rkt"` (M6→S1 branch) AND `#rx"in-memory\\.rkt"` (M10 branch).
   - Leading comment block: states this is the S3 Portability-NFR sweep over the transport barrel; notes web-server extra assertion; notes one root (the barrel covers M6 + M10 transitively).
3. **Run** `raco test mcp/transport/test/portability-test.rkt` (fast inner loop) and `raco test mcp/transport/` (acceptance gate). Fix any failure by inspecting the import — but a failure means a module regressed portability; surface it rather than silently editing the module.
4. **Teeth / mutation check (TWO injections, both mandatory):**
   - **(a)** Add `(require racket/tcp)` to `in-memory.rkt`; run sweep; confirm RED (banned-module loop); revert; confirm green.
   - **(b)** Add `(require web-server/http)` to `in-memory.rkt`; run sweep; confirm RED (`#rx"/web-server/"` check-false fires); revert; confirm green.
   Both required — (b) is the only way to prove the web-server assertion has working teeth. Record both RED→revert→green transitions in Decisions.
5. **Parity edits:**
   - Flip boxes to `[x]` (locate by TEXT, line# is hint): `- [ ] Load test: still no subprocess/socket module pulled in` (hint: `:109`) and `- [ ] Parity rows \`transport.ts\`, \`inMemory.ts\` marked \`partial\`` (hint: `:110`).
   - Add S3 Deliverables line for `mcp/transport/test/portability-test.rkt`.
   - Append item-022 sentence to the parity-matrix-progression narrative (locate by `## Parity matrix progression` heading; hint: near `:338`; follow `**Item 017 (Stage S2):** …` pattern).
   - `grep roadmap.md` for `transport.ts`/`inMemory.ts` — if no materialized table, record "acceptance lines `roadmap.md:157-158` stand; no §9 parity table yet" in narrative; make no roadmap edit.
6. Update item-022 status 📋 → 🚧 → ✅.

---

## Testing Strategy

Harvested script `docs/aide/scripts/test-transport.sh` runs `raco test mcp/transport/` — use it as the acceptance gate (green / exit 0).

Fast inner loop: `raco test mcp/transport/test/portability-test.rkt`.

Acceptance gate (mandatory): `raco test mcp/transport/` — runs the new sweep AND all existing transport tests in one shot.

No external services. No TS checkout needed.

---

## Dependencies

- **Items 019–020** — `mcp/transport/transport.rkt` (M6) and `mcp/transport/in-memory.rkt` (M10) must exist (they do; `progress.md:100-101` are ✅).
- **Item 021** — `mcp/transport/main.rkt` barrel (exists; `progress.md:102` ✅).
- **S1 walk template** — `mcp/core/test/main-test.rkt:43-114`.
- **TS checkout** (`typescript-sdk/`) — NOT needed (pure portability + docs, no wire fixture parity).

---

## Decisions & Trade-offs

- **Copy-not-factor for the walk machinery.** `banned-module-paths` + the six helpers copied verbatim from `main-test.rkt:49-105` (matching the S2 sweep's choice, `s2-portability-test.rkt:52-115`). Duplication is the cheaper trade vs. a shared helper module that would couple three portability suites and risk regressing S1/S2.
- **One root = the barrel.** Walked exactly `mcp/transport/main.rkt`; it re-exports M6 + M10, so a single walk transitively covers both. No separate enumeration of `transport.rkt`/`in-memory.rkt`, no glob.
- **Inlined the walk-and-assert** in a `parameterize` block rather than adding an S2-style `check-root` wrapper — only one root here, so the wrapper earns nothing. `check-portable!` retained verbatim (copy mandate) though unused by the single sweep.
- **web-server ban as a separate assertion.** `banned-hit?`'s `#rx"/<sym>(\.rkt)?$"` only catches `/web-server.rkt`; nested collection paths (`web-server/http`) need `#rx"/web-server/"`. Kept out of `banned-module-paths` (which stays the 8-entry S1 list) and expressed as its own `check-false` over `visited`.
- **Two non-vacuity guards.** `#rx"core/main\.rkt"` proves the M6→S1 edge resolved (truncated walks stop at racket/base's ~79-module closure and pass a bare `> 1`); `#rx"in-memory\.rkt"` proves the barrel's second branch (M10) was reached — a walk truncated at `transport.rkt` would pass the first guard but silently miss M10.
- **Teeth / mutation checks (both mandatory, both performed).**
  - (a) `(require racket/tcp)` added to `in-memory.rkt` → sweep RED (`check-false` at `:126`, "…imports banned module racket/tcp") → reverted → green (11 tests).
  - (b) `(require web-server/http)` added to `in-memory.rkt` → sweep RED (web-server `check-false` at `:131`, "…imports web-server collection"; also tripped the tcp/port banned entries since web-server pulls them transitively — 3 failures) → reverted → green.
  Both mutations reverted; module source unchanged from HEAD (verified via require-block diff).
- **No source/roadmap edits.** Only new file: `mcp/transport/test/portability-test.rkt`. `grep roadmap.md` confirms `transport.ts`/`inMemory.ts` appear only in the S3 acceptance line (`roadmap.md:158`) + module bullet (`:141`) — no materialized §9 parity table, so `roadmap.md:157-158` stand unedited (same finding as item 017).
- **Acceptance gate.** `raco test mcp/transport/` (via harvested `docs/aide/scripts/test-transport.sh`) → 57 tests passed, exit 0 (new sweep + existing `transport-test.rkt`/`in-memory-test.rkt`).

---

## Completion Reminder

On delivery, in `docs/aide/progress.md`:
- Flip boxes to `[x]` (locate by text, not line number): `- [ ] Load test: still no subprocess/socket module pulled in` and `- [ ] Parity rows \`transport.ts\`, \`inMemory.ts\` marked \`partial\``.
- Add S3 Deliverables line for `mcp/transport/test/portability-test.rkt`.
- Append the item-022 parity-matrix-progression sentence at `progress.md:338`.
- Confirm `roadmap.md:157-158` acceptance lines stand (no §9 table materialized); record in narrative.
- Flip item-022 status 📋 → ✅.
