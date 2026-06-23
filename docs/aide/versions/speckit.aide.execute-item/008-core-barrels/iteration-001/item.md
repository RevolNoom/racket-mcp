# Work Item 008: Core barrels + restricted-load portability test

> **Queue:** `docs/aide/queue/queue-001.md` — Item 008
> **Stage:** S1 (Foundation: types, constants, guards, errors — L0 part 1)
> **Module:** M1 (Types) + M2 (Errors) — **public-surface barrels** (`mcp/core/types/main.rkt`,
>   `mcp/core/main.rkt`), NOT a new module's internals. No new types, no new errors — this item
>   curates and re-exports what items 001–007 already built, and adds the Portability NFR's
>   load-time proof.
> **Source vision:** `docs/aide/vision.md` line 214 (Portability NFR — "Core types/protocol must
>   load without pulling in subprocess/socket modules, so they remain usable in restricted
>   contexts (mirrors TS runtime-neutral root rule)").
> **Source roadmap:** `docs/aide/roadmap.md` Stage S1 → Deliverables line 85
>   (`mcp/core/types/main.rkt` and `mcp/core/main.rkt` barrels — explicit `provide` curated
>   public surface (architecture §1.3 public/internal boundary)) and the Testing/validation
>   criteria line 96 ("Loading `mcp/core/types` and `mcp/core/errors.rkt` pulls in **no**
>   subprocess/socket module (Portability NFR — verify with a load test in a restricted
>   namespace)"). Also Stage-summary table line 418 (S1 row: "Wire structs round-trip TS
>   fixtures; **restricted-load test**").
> **Source architecture:** `docs/aide/architecture.md` **§1.3 line 52** (Public/internal
>   boundary — "Each sub-collection exposes a curated public API via its `main.rkt` (explicit
>   `provide`). Internal modules `provide` only to siblings inside the collection. Non-portable
>   facilities (subprocess, sockets) live in `transport/` adapters and named submodules so
>   L0–L2 stay runtime-neutral. Mirrors TS `core/public` vs internal barrel."); **§4.1 line 327**
>   ("Runtime-neutral core. L0–L2 import no subprocess/socket modules; all non-portable I/O
>   confined to L1 adapters (Portability NFR)."); **§4.1 line 328** (the error-to-wire boundary,
>   already cited by item 007 — this item's barrel re-exports that boundary's public surface);
>   §3.3 line 320 (Module-system row: "`mcp` collection + sub-collections; `main.rkt` public
>   barrels … Mirrors TS public/internal boundary + ports-and-adapters").
> **Reference impl:** MCP TypeScript SDK v2 at `typescript-sdk/` — the TS package's
>   `core/public`-vs-internal barrel split (architecture §1.3's "Mirrors TS `core/public` vs
>   internal barrel"); there is no single TS file this item ports line-for-line (a barrel
>   `index.ts`-style re-export is a packaging convention, not a runtime algorithm) — the
>   authoritative target is the **architecture's own §1.3 contract**, satisfied by curating the
>   already-curated `provide` surfaces of items 001–007 into two new files.
> **Delivered siblings (the FORMAT + rigor bar):**
>   `docs/aide/items/007-error-decode-path.md` (✅ delivered, the DECODE half — match its format,
>   header depth, build-contract table style, and Decisions discipline) and
>   `docs/aide/items/006-error-hierarchy-and-encode-path.md` (✅ delivered, the ENCODE half).
>   Both are barrel CONSUMERS this item re-exports; their structural rigor (exact line-anchored
>   citations, enumerated build-contract tables, concretely-testable acceptance criteria) is the
>   bar this spec meets.
> **Status:** Specified (not yet implemented). This is the LAST item before Item 009's closeout
>   demo; on delivery it completes Stage S1's M1+M2 deliverable list except the demo script.

---

## Description

Implement the two **curated public-surface barrels** the architecture's public/internal
boundary (§1.3 line 52) requires for the `mcp/core/types/` and `mcp/core/` sub-collections, and
add the **restricted-namespace portability load test** the roadmap's Portability NFR (line 96)
demands but which no prior item has yet exercised (items 001–007 each asserted their OWN
`require` list was subprocess/socket-free; this item is the first to assert it **transitively**,
end-to-end, from the public entry point a downstream consumer would actually `require`).

Three deliverables:

1. **`mcp/core/types/main.rkt`** — a barrel re-exporting the ENTIRE already-curated public
   surface of items 001–005: `constants.rkt` (item 001), `guards.rkt` (item 002),
   `spec-2025-11-25.rkt` (item 003), `spec-2026-07-28.rkt` (item 004), and `types.rkt` (item 005,
   the N1 normalized-superset façade). This is M1's `core/public`-equivalent barrel
   (architecture §1.3).
2. **`mcp/core/main.rkt`** — the top M1+M2 barrel: re-exports `mcp/core/types/main.rkt` (deliverable
   1) PLUS `mcp/core/errors.rkt` (items 006 ENCODE + 007 DECODE). This is the single `require`
   target a downstream module (S2's validators, S3's protocol engine, or any external consumer)
   uses to pull in "all of Stage S1's public surface" without knowing the internal module
   layout — the architecture's "curated public API via its `main.rkt`" contract (§1.3) applied
   one level up.
3. **The restricted-namespace portability load test** — a new test asserting that requiring
   `mcp/core/types/main.rkt` and `mcp/core/main.rkt` (the barrels just built) in a fresh,
   restricted Racket namespace pulls in, **transitively**, NO module from a banned
   subprocess/socket set (`racket/system`, `racket/port`'s subprocess-spawning bindings,
   `racket/tcp`, `racket/udp`, and the `net/...` family). This is the first item to walk the
   FULL transitive import graph from the public entry point, closing the Portability NFR gap
   left open by every prior M1/M2 item (each of which only inspected its OWN direct `require`
   list by hand — see item 006 AC "Portability… requires ONLY racket/base, racket/contract, and
   types/constants.rkt" and item 007 AC "Portability… unchanged: errors.rkt still requires
   ONLY…" — neither mechanically verified the TRANSITIVE closure).

A fourth, smaller deliverable folded into the test suite: **a negative test proving the barrels
are curated, not blanket** — asserting a real internal-only binding from the underlying modules
is NOT re-exported by the barrel that wraps it. This is the operational meaning of "curated
public-surface barrel" (architecture §1.3's "Internal modules `provide` only to siblings inside
the collection") — a barrel that accidentally leaks an internal helper has failed its one job.

### The barrel re-export mechanism — concrete decision (read before implementing)

The queue text floats two options: "(NOT `(provide (all-from-out ...))` blanket re-export …
OR it should be a hand-picked list)". **DECISION for this item: use
`(provide (all-from-out "module.rkt") ...)` per underlying module — NOT a hand-picked
binding-by-binding list.** Justification, grounded in what the source files actually do (verified
by reading each module's own `provide` clause during spec-writing):

- **Every one of items 001–007's modules already enforces curation at its OWN boundary.**
  `constants.rkt` (item 001), `guards.rkt` (item 002), `spec-2025-11-25.rkt` (item 003),
  `spec-2026-07-28.rkt` (item 004), `types.rkt` (item 005), and `errors.rkt` (items 006+007) each
  ship an explicit, hand-curated `(provide …)` / `(provide (contract-out …))` block — NONE of
  them uses `(provide (all-defined-out))` (verified: `spec-2025-11-25.rkt:106–256` is a single
  hand-enumerated list ending in a closing paren before the scalar-contract definitions begin;
  `errors.rkt:72–83` and `errors.rkt:85–106` are two explicit lists; `types.rkt:72–73`, `85–86`,
  and `1319`+ are explicit lists; `guards.rkt:30–35` and `constants.rkt:8–31` are explicit
  lists). So `(all-from-out "spec-2025-11-25.rkt")` re-exports EXACTLY that module's own curated
  list — it does NOT additionally expose `json-object?`, `h-opt`, `h-req`, `put`, `put!`,
  `opt-map`, `opt-list`, `req-list`, or `split-loose` (the genuinely internal helpers documented
  at `spec-2025-11-25.rkt:47` "Internal wire helpers (NOT provided, except `absent`)" and never
  listed in the `provide` block at lines 106–256). The curation work is ALREADY DONE at the leaf
  level; a per-module `all-from-out` does not undo it.
- **A hand-picked list at the barrel level would be pure duplication with a parity hazard.**
  Re-typing every one of `spec-2025-11-25.rkt`'s ~150 provided identifiers (the file's `provide`
  block alone spans `spec-2025-11-25.rkt:106–256`, ~150 lines) into `types/main.rkt` would (a)
  duplicate ~150 names that must be kept in lock-step with every future addition to that module
  (a drift hazard exactly like the one item 003's own Decisions section warns against for
  duplicate type definitions), and (b) provide ZERO additional curation benefit, since the leaf
  module already decided what is public. The risk of a hand-picked barrel list silently going
  stale (a future item 0XX adds a struct to `spec-2026-07-28.rkt`'s `provide` and the barrel
  list is never updated) is strictly worse than the risk `all-from-out` carries (none — it always
  tracks the leaf's current curated surface).
- **Per-module granularity, not a single blanket `all-from-out` across the whole directory.**
  The decision is `(provide (all-from-out "constants.rkt") (all-from-out "guards.rkt")
  (all-from-out "spec-2025-11-25.rkt") (all-from-out "spec-2026-07-28.rkt")
  (all-from-out "types.rkt"))` — five explicit per-file `all-from-out` clauses, not a single
  wildcard. This keeps the barrel's `require`/`provide` pairing legible (each `require` line has
  a corresponding `all-from-out` for THAT module) and means a future module added to
  `mcp/core/types/` does NOT automatically appear in the barrel — a new module must be
  deliberately added to both the `require` and the `provide` clause, which is itself a
  curation gate at the barrel-authoring level (a human decides "yes, M1 grows a 6th public
  module" rather than it happening by directory-globbing).
- **`mcp/core/main.rkt` follows the identical pattern one level up:**
  `(provide (all-from-out "types/main.rkt") (all-from-out "errors.rkt"))` — two clauses, M1's
  already-curated barrel plus M2's already-curated errors module.
- **Architecture §1.3 grounding.** "Each sub-collection exposes a curated public API via its
  `main.rkt` (explicit `provide`)" is satisfied: the barrel's `provide` clause IS explicit (it
  names exactly which sibling modules' surfaces compose the barrel), even though each clause is
  an `all-from-out` rather than a binding list. "Internal modules `provide` only to siblings
  inside the collection" is satisfied because the *leaf* modules already gate internal helpers
  out of their own `provide` — the barrel inherits that gate for free and adds no new leak
  surface (proven by the negative test in deliverable 4).

> **Naming collision analysis — ALL THREE pairwise combinations actually required together in
> this barrel (verified by running real introspection code against the real files during spec
> research, not by grep/eyeball).** Five modules go into `mcp/core/types/main.rkt`, but only
> three of them carry overlapping identifiers; every pairwise combination was checked with
> `module->exports` (note: returns TWO values — `(define-values (vars stxs) (module->exports m))`
> — a different arity pitfall than `module->imports`' one-value return documented elsewhere in
> this item; both were hit and fixed during spec research):
>
> | Pair | Names compared | Collisions found |
> |---|---|---|
> | `spec-2025-11-25.rkt` × `spec-2026-07-28.rkt` | 1118 × 977 | **834** — e.g. `prompt-title`, `tool/c`, `json->prompt`, `struct:prompt`, every shared struct/accessor/json-codec/contract name the two per-revision modules happen to name identically |
> | `spec-2025-11-25.rkt` × `types.rkt` | 1118 × 709 | 9 — `progress-token/c`, `request-id/c`, `role/c`, `cursor/c`, `logging-level/c`, `task-status/c`, + 3 more façade-level scalar-contract aliases |
> | `spec-2026-07-28.rkt` × `types.rkt` | 977 × 709 | 10 — the RC-revision equivalents of the same façade-aliased scalar contracts |
> | `constants.rkt` / `guards.rkt` × anything | — | 0 — these two modules' surfaces (protocol-version/error-code constants; boolean predicates) do not share a name with any other module in this barrel |
>
> **The 834-collision pair is the real, dominant blocker** — three orders of magnitude larger
> than the 9–10 façade-alias collisions an earlier draft of this spec analyzed in isolation. A
> plain `(require "spec-2025-11-25.rkt" "spec-2026-07-28.rkt" …)` with no prefix fails at
> **require time**, before `provide`/`all-from-out` is even reached, with:
> ```
> module: identifier already required
>   at: prompt-title
>   in: "spec-2026-07-28.rkt"
>   also provided by: "spec-2025-11-25.rkt"
> ```
> (verified by running exactly this require form against the real files) — NOT the
> `all-from-out: name clashes` error a `provide`-level collision produces. `except-out` operates
> on a `provide` clause and cannot fix a `require`-level collision; the two per-revision modules
> must never be `require`d unprefixed into the same module body together.
>
> **DECISION — `prefix-in` on both per-revision spec modules, mirroring the pattern `types.rkt`
> itself already uses internally** (`types.rkt:31–32`: `(prefix-in r25: "spec-2025-11-25.rkt")`,
> `(prefix-in r26: "spec-2026-07-28.rkt")`). `mcp/core/types/main.rkt` requires
> `spec-2025-11-25.rkt` and `spec-2026-07-28.rkt` the SAME way `types.rkt` does — `(prefix-in r25:
> "spec-2025-11-25.rkt")` / `(prefix-in r26: "spec-2026-07-28.rkt")` — then `provide`s
> `(all-from-out "spec-2025-11-25.rkt")` / `(all-from-out "spec-2026-07-28.rkt")` **unprefixed in
> the `provide` clause** (verified live: `all-from-out` re-exports a module under the LOCAL
> prefixed names the `require` clause bound them to — e.g. `r25:prompt-title` — NOT under a
> doubled `r25:r25:prompt-title`; confirmed by testing both forms against the real files, only
> the bare-`all-from-out`-after-`prefix-in`-require form produces single-prefixed names). This
> resolves the 834-collision blocker completely (`r25:prompt-title` and `r26:prompt-title` are
> distinct identifiers — zero collision) and ALSO resolves the smaller 9/10-collision
> façade-vs-per-revision overlaps for free, since `types.rkt`'s own façade-level names
> (`progress-token/c`, etc., unprefixed) and the now-`r25:`/`r26:`-prefixed per-revision names no
> longer share a name either.
>
> **Why this design, not `except-out`/`rename-out` on a per-name basis, and not dropping the
> per-revision modules from the barrel entirely.** Downstream consumers (S2's validators, S3's
> protocol engine, and beyond) doing CROSS-REVISION work are expected to go through `types.rkt`'s
> already-curated N1 façade (architecture's normalized-superset intent) — they want
> `progress-token/c` to mean "the façade's version-agnostic contract," not "whichever per-revision
> module's require happened to load last." Hand-picking `except-out` names for the 9/10
> façade-collisions only (leaving spec25/spec26 unprefixed against EACH OTHER) would still fail to
> compile on the 834-collision pair — `except-out` cannot remove a require-level collision, only a
> provide-level one. Dropping the per-revision modules from the barrel instead (re-exporting only
> `types.rkt`'s façade) was considered and rejected: a future S2+ consumer that legitimately needs
> the RAW per-revision shape (e.g. a wire-format conformance test pinned to one specific protocol
> revision, or revision-specific validation code item 003/004's own test suites already exercise)
> would have no way to reach it through this barrel at all. `prefix-in` + bare `all-from-out`
> keeps BOTH reachable — `r25:jsonrpc-request?` / `r26:related-task-metadata-task-id` for raw
> per-revision access, `jsonrpc-request?`-style façade names (where `types.rkt` defines them) for
> the common case — at the cost of per-revision consumers needing the `r25:`/`r26:` prefix, which
> is a small, explicit, self-documenting cost (the prefix tells the reader which revision they're
> looking at) rather than a silent landmine.
>
> **The implementer must `raco make` the draft barrel and confirm exit 0 with no error** (this
> mechanism was verified to compile clean against the real files during spec research — see
> Decisions for the exact commands run) before this item is done.

---

## The build contract — what each new file must export (enumerate ALL)

### Part A — `mcp/core/types/main.rkt`

| Requires | Provides | Source module's own curation |
|---|---|---|
| `"constants.rkt"` | `(all-from-out "constants.rkt")` | `constants.rkt:8–31` — protocol versions, JSONRPC-VERSION, 9 error codes, 5 `_meta` keys |
| `"guards.rkt"` | `(all-from-out "guards.rkt")` | `guards.rkt:30–35` — 5 predicates, no batch guard (J3) |
| `(prefix-in r25: "spec-2025-11-25.rkt")` | `(all-from-out "spec-2025-11-25.rkt")` — re-exported under the `r25:`-prefixed names the `require` clause bound (e.g. `r25:prompt-title`, `r25:jsonrpc-request?`), NOT unprefixed — see §Decision above for why | `spec-2025-11-25.rkt:106–256` — ~150 bindings: sentinel/helpers, scalar contracts, every struct+contract+json-codec pair for the 2025-11-25 revision, the specialized `make-url-elicitation-required-error`/`url-elicitation-required-error?`, the aggregate union contracts |
| `(prefix-in r26: "spec-2026-07-28.rkt")` | `(all-from-out "spec-2026-07-28.rkt")` — re-exported under `r26:`-prefixed names (e.g. `r26:related-task-metadata-task-id`) | `spec-2026-07-28.rkt:111`+ — the RC revision's equivalent surface incl. `_meta` envelope types |
| `"types.rkt"` | `(all-from-out "types.rkt")` — unprefixed; this is the façade's version-agnostic surface and the common-case entry point | `types.rkt:72–73`, `85–86`, `1319`+ — `absent`/`absent?`/`present?`/`json-object?`/`revision/c`, shared scalar contracts (façade-level), every `facade-*` struct + contract + normalize/denormalize pair, the dispatch table accessor `dispatch-for` (if provided — verify during implementation), the specialized façade error constructors (`make-facade-url-elicitation-required-error` etc., cited by item 007 Dependencies at `types.rkt:1176–1178`/`1244–1246`) |

With the `prefix-in` design, there are zero remaining name collisions among any pair of the five
`require`s (verified — see §Naming collision analysis above) — no `except-out`/`rename-out` is
needed anywhere in this barrel.

**Exact expected `provide` form** (the new file's entire body — verified to `raco make` clean,
exit 0, against the real files during spec research):

```racket
#lang racket/base
(require "constants.rkt"
         "guards.rkt"
         (prefix-in r25: "spec-2025-11-25.rkt")
         (prefix-in r26: "spec-2026-07-28.rkt")
         "types.rkt")
(provide (all-from-out "constants.rkt")
         (all-from-out "guards.rkt")
         (all-from-out "spec-2025-11-25.rkt")   ; re-exported under r25:-prefixed names
         (all-from-out "spec-2026-07-28.rkt")   ; re-exported under r26:-prefixed names
         (all-from-out "types.rkt"))
```

No new `define`s, no new structs, no new contracts — this file is a pure re-export barrel (a
"named module" whose entire body is `require` + `provide`). No `except-out`/`rename-out` is
needed (the `prefix-in` design eliminates all collisions at the `require` level before `provide`
is ever reached — see §Naming collision analysis and §Decision above).

### Part B — `mcp/core/main.rkt`

| Requires | Provides |
|---|---|
| `"types/main.rkt"` (Part A's barrel) | `(all-from-out "types/main.rkt")` |
| `"errors.rkt"` (items 006+007) | `(all-from-out "errors.rkt")` |

**Exact expected `provide` form:**

```racket
#lang racket/base
(require "types/main.rkt" "errors.rkt")
(provide (all-from-out "types/main.rkt")
         (all-from-out "errors.rkt"))
```

`errors.rkt`'s own curated surface (already enumerated by item 006/007: 3 `struct-out`s, 3
predicates, 2 accessors via the first `provide` block at `errors.rkt:72–83`; 3 constructors, the
encode function, the encode-jsexpr convenience, and `jsonrpc-error->exn` via the second
`contract-out` block at `errors.rkt:85–106`) passes through unchanged. No naming collision is
expected between `errors.rkt`'s surface and `types/main.rkt`'s surface (verify during
implementation — `errors.rkt` does not redefine any `types.rkt`/spec-module identifier; it only
imports codes and the `jsonrpc-error` struct, none of which it re-provides under a NEW name that
would collide).

### Part C — the restricted-namespace portability load test (the mechanism, specified precisely)

**Banned module-path set** (transitively forbidden — none of these may appear anywhere in the
transitive import closure of `mcp/core/types/main.rkt` or `mcp/core/main.rkt`):

```racket
(define banned-module-paths
  (list 'racket/system     ; subprocess spawning (process, process*, system, system*, etc.)
        'racket/port        ; carries subprocess-adjacent port-copying utilities (conservative ban — verify it's actually unreachable, don't assume)
        'racket/tcp          ; raw TCP sockets
        'racket/udp          ; raw UDP sockets
        'net/url             ; HTTP client (pulls in tcp transitively)
        'net/http-client      ; HTTP client
        'net/sendurl
        'racket/sandbox))    ; the sandbox library itself must not be a RUNTIME dep of the core
```

> **Pick a concrete, implementable mechanism (per the assignment's instruction) — DECISION:**
> walk `module->imports` transitively from the barrel's module path, resolving each
> `module-path-index` to its `resolved-module-path-name`, and assert the banned set has empty
> intersection with the visited set. **A one-hop-deep version of this mechanism (direct imports
> of a single module, not yet transitive) was confirmed runnable in THIS environment during early
> spec research** (a `racket -e` one-liner against `mcp/core/errors.rkt`'s OWN direct `require`
> list correctly enumerated `racket/base`, `racket/contract` (+ its private submodules), and the
> two M1 deps, with none of the banned paths present) — establishing that `module->imports` +
> `module-path-index-resolve` are real, callable primitives in this sandbox, not a hypothetical
> design. **That one-hop check is NOT sufficient on its own**, however: it does not exercise
> relative-path resolution for a CHILD module's OWN sub-requires, which is exactly where a
> path-resolution bug was found and fixed during a later, deeper round of spec research — see the
> step-2 callout below for the concrete bug, the fix, and the live 2-hop-deep verification of the
> FIXED algorithm. The precise steps below describe the CORRECTED, transitively-verified
> algorithm, suitable for direct transcription into the test file:
>
> 1. `(namespace-require top-module-path)` — loads (and registers, for `module->imports`'
>    purposes) the target module (e.g. `(file ".../mcp/core/main.rkt")`) into the current
>    namespace. **Do this inside a FRESH namespace** (`(parameterize ([current-namespace
>    (make-base-namespace)]) …)`) so the test does not depend on / pollute whatever the test
>    runner's own namespace has already loaded (a load that "succeeds" only because some OTHER
>    test already required `racket/tcp` earlier in the same process would be a false pass — the
>    fresh namespace closes that hole).
> 2. **BFS/DFS over `module->imports`, tracking each module's OWN directory as the base for
>    resolving ITS relative sub-requires (the relative-path-resolution fix, verified — see below):**
>    maintain a worklist of `(module-name . base-dir)` pairs (start: `(list (cons top-module-path
>    top-dir))`, where `top-dir` is `top-module-path`'s own containing directory) and a `seen` set
>    keyed on module name alone. Pop a pair `(m . base-dir)`; if `m` already seen, skip; else mark
>    seen, call `(module->imports m)` (which returns a list of `(phase . (listof
>    module-path-index))` pairs — **note: a single value, NOT two values via
>    `define-values`** — this was a real implementation pitfall hit during spec research: the
>    naive `(define-values (imps _) (module->imports m))` raises `arity mismatch; expected: 2,
>    received: 1`, because `module->imports` returns ONE list of phase-groups, not two values),
>    extract every `module-path-index` across all phase-groups via `(apply append (map cdr
>    phase-groups))`, and resolve EACH one with **`(parameterize ([current-load-relative-directory
>    base-dir]) (resolved-module-path-name (module-path-index-resolve mpi)))`** — **NOT** a bare
>    `(resolved-module-path-name (module-path-index-resolve mpi))` with no `base-dir` context.
>    >
>    > **Why the `base-dir` parameterization is required — the bug a naive implementation hits.**
>    > A relative sub-require inside a required module (e.g. `errors.rkt`'s `(require
>    > "types/constants.rkt" ...)`, or `spec-2025-11-25.rkt`'s `(require "constants.rkt" ...)`)
>    > resolves relative to the AMBIENT `current-load-relative-directory`/process CWD if that
>    > parameter is not explicitly set to the REQUIRING module's own directory — **verified live**:
>    > running the naive (no-`base-dir`) version of this walk against the real
>    > `mcp/core/types/types.rkt` from repo root resolved `errors.rkt`'s/`spec-2025-11-25.rkt`'s
>    > `"constants.rkt"` sub-require to the nonexistent path
>    > `/home/tlam/racket-mcp/types/constants.rkt` (missing the `mcp/core/` prefix — CWD-relative,
>    > not requiring-module-relative) instead of the real
>    > `/home/tlam/racket-mcp/mcp/core/types/constants.rkt`. The subsequent `module->imports` call
>    > on that bogus path then raises `module->imports: unknown module in the current namespace`,
>    > which the `with-handlers` guard below (correctly, for ITS intended purpose) catches and
>    > treats as "no further imports" — **silently truncating the walk one level early for every
>    > relatively-required module**, which is most of this codebase. **The fix — parameterizing
>    > `current-load-relative-directory` to each module's own directory before resolving ITS
>    > children's `module-path-index`es — was implemented and live-tested against the real files**:
>    > re-running the SAME walk against `mcp/core/types/types.rkt` with the fix resolved
>    > `constants.rkt` to its correct absolute path at BOTH the hop-2 paths it's reachable by
>    > (`types.rkt → spec-2025-11-25.rkt → constants.rkt` and `types.rkt → spec-2026-07-28.rkt →
>    > constants.rkt`), with zero bogus top-level-relative paths anywhere in the 215-module visited
>    > set. A drift-injection test (`(require racket/tcp)` added inside `spec-2025-11-25.rkt`,
>    > i.e. at exactly the 2-hop depth the bug lived at) was ALSO re-run with the fixed algorithm
>    > and correctly surfaced `racket/tcp.rkt` in the visited set (216→217 modules) — confirming
>    > the fix doesn't just resolve paths correctly but the walk's PRACTICAL drift-detection
>    > purpose actually works past the point the bug used to truncate it.
>    >
>    > A module's "own directory," for propagating to ITS children, is `(path-only m)` when `m`
>    > is a `path?` (use `racket/path`'s `path-only`); collection-relative resolved names (`m` is a
>    > `symbol?`, e.g. `racket/base`) have no meaningful directory to propagate this way — their
>    > own relative sub-requires (if any) are resolved by Racket's collection-path system, not by
>    > `current-load-relative-directory`, so simply keep propagating the PARENT's `base-dir`
>    > unchanged in that case (it is never consulted for a symbol-named module's own resolution,
>    > so the exact value is immaterial, but the worklist entry still needs SOME `base-dir` slot
>    > filled to keep the pair-shape uniform).
>    >
>    > Push every newly-resolved `(child-name . child-base-dir)` pair onto the worklist. Guard the
>    > recursive `module->imports` call with `(with-handlers ([exn:fail? (lambda (e) '())]) …)` for
>    > any leaf/primitive module that STILL errors on introspection even with correct path
>    > resolution (e.g. `#%kernel`, `#%builtin`, `#%paramz`, and certain syntax-phase submodule
>    > references like `(litconv lazy-require-aux-1-0)` — **verified**: 21 such genuinely
>    > unintrospectable primitive/submodule dead-ends were hit and correctly caught when running
>    > the FIXED walk against the real `types.rkt`, none of which were mis-resolved relative paths
>    > — they are legitimate dead ends, not the bug) — treat those as having no further imports
>    > rather than failing the walk. **This guard is still necessary even after the path-resolution
>    > fix** — it now catches only genuine introspection dead-ends, not the formerly-disguised
>    > path bug.
> 3. **The assertion:** for every banned path `b` in `banned-module-paths`, assert NO visited
>    resolved-module-path-name's `module-path?`-normalized form equals (or is a symbol/path
>    matching) `b`. Concretely: collect all visited names that are `symbol?` (collection-relative
>    requires like `racket/base` resolve to symbols) or whose `path?` basename indicates the
>    banned collection (a `(file …)`-style resolution for a `racket/<x>` collection module — in
>    practice, on this Racket install, `module-path-index-resolve` + `resolved-module-path-name`
>    on a collection-required module like `racket/contract` yields a `path?` pointing into the
>    installed `collects/` tree, e.g. `.../collects/racket/contract.rkt` per the verified
>    transcript — so the check must inspect the PATH's collection-relative tail, not assume a
>    bare symbol). **Concrete check:** `(define (path-mentions-banned? p banned-sym)
>    (regexp-match? (regexp (format "/~a(\\.rkt)?$" banned-sym)) (path->string p)))`
>    OR, more robustly, compare against `(collection-file-path (symbol->string banned-sym)
>    "racket")`-style resolution for each banned symbol UP FRONT and then compare resolved paths
>    by `equal?`/`(same-directory? …)`. **Implementer's job:** pick whichever comparison is
>    robust against both symbol-shaped and path-shaped resolved names (the verified transcript
>    showed PATH-shaped results for `racket/*` collection modules in this environment) and
>    document the exact comparison chosen in the Decisions section on delivery.
> 4. Run the walk against BOTH `mcp/core/types/main.rkt` and `mcp/core/main.rkt` (the second
>    transitively includes the first plus `errors.rkt`, so it is technically redundant coverage,
>    but the acceptance criterion below requires both be asserted directly, matching the queue's
>    "require `mcp/core/types` and `mcp/core/errors.rkt`" framing literally).

> **Why `racket/sandbox`'s `make-evaluator` is NOT the chosen mechanism (documented so a future
> reader does not "fix" this into a worse design).** `racket/sandbox` IS available in this
> environment (verified: `(require racket/sandbox)` loads cleanly) and could run the barrel
> inside a `make-evaluator` with restricted permissions (e.g. `sandbox-network-guard` /
> `sandbox-make-inspector` / restricted `eval` limits) and then assert that EXERCISING the
> loaded module never attempts a banned operation at runtime. That is a strictly WEAKER test
> than the chosen `module->imports` walk: a sandboxed evaluator only catches a banned operation
> if the test happens to CALL the code path that performs it; `module->imports` proves the
> banned module is not even REACHABLE/LOADED, which is the actual Portability NFR claim ("pulls
> in no subprocess/socket module" — a load-time/import-graph property, not a runtime-behavior
> property). The chosen mechanism is therefore strictly stronger and directly tests the literal
> claim; `racket/sandbox` is not used for this assertion (it MAY still be reasonable defense in
> depth in a future item, but is out of scope here — YAGNI).

---

## Acceptance criteria

- [x] **`mcp/core/types/main.rkt` exists** as `#lang racket/base`, `require`s exactly the five
      sibling modules (`constants.rkt`, `guards.rkt`, `(prefix-in r25: "spec-2025-11-25.rkt")`,
      `(prefix-in r26: "spec-2026-07-28.rkt")`, `types.rkt` — see §The barrel re-export mechanism
      Decision for why the two spec modules are `prefix-in`'d), and `provide`s `(all-from-out …)`
      for each. `raco make mcp/core/types/main.rkt` exits 0 (outcome-based check — the failure
      mode of an unresolved collision is `module: identifier already required` at the `require`
      line, NOT an `all-from-out: name clashes` error at the `provide` line; asserting "exit 0"
      rather than the absence of one specific error substring covers both failure modes).
- [x] **`mcp/core/main.rkt` exists** as `#lang racket/base`, `require`s `"types/main.rkt"` and
      `"errors.rkt"`, and `provide`s `(all-from-out …)` for each. `raco make mcp/core/main.rkt`
      exits 0.
- [x] **The barrel re-exports a representative binding from EACH of the six underlying
      modules**, concretely testable via a single `require` + presence checks:
      `(require (file "mcp/core/main.rkt"))` then: `INTERNAL-ERROR` is bound and `=` `-32603`
      (item 001, via the types barrel); `is-jsonrpc-request?` is bound and is a procedure (item
      002); `r25:jsonrpc-request?` is bound (item 003 — NOTE the `r25:` prefix: per §The barrel
      re-export mechanism Decision, `spec-2025-11-25.rkt`/`spec-2026-07-28.rkt` are `prefix-in`'d
      `r25:`/`r26:` to resolve their 834-identifier mutual collision, so their re-exported names
      carry that prefix); a `2026-07-28`-only RC binding is bound under its `r26:`-prefixed name,
      e.g. `r26:related-task-metadata-task-id` (confirmed present in `spec-2026-07-28.rkt`'s own
      `provide` at the time of spec research — re-verify the exact identifier during
      implementation since this spec does not re-enumerate all ~176 of its bindings) (item 004);
      a `facade-*` struct predicate, e.g. `facade-implementation?`, unprefixed (item 005);
      `mcp-error?` and `protocol-error?` (item 006); `jsonrpc-error->exn` (item 007). **Each of
      these seven checks is a single `(check-true (procedure? jsonrpc-error->exn))`-style
      assertion** — non-vacuous because each name is drawn from a DIFFERENT underlying module, so
      a barrel that only re-exports (say) `errors.rkt` and silently drops one of the five `types/`
      modules would fail at least one check.
- [x] **THE QUEUE'S CORE TESTABLE CLAIM — the restricted-namespace portability load test
      passes:** a test (see §Testing strategy for the exact code) that, in a FRESH
      `(make-base-namespace)`, requires `mcp/core/types/main.rkt` and separately
      `mcp/core/main.rkt`, transitively walks `module->imports` from each, and asserts the
      visited resolved-module-path set has EMPTY intersection with the banned set
      (`racket/system`, `racket/tcp`, `racket/udp`, `net/url`, `net/http-client`, `net/sendurl`,
      `racket/sandbox`; `racket/port` included conservatively — see Decisions for whether it
      survives the actual walk). The test FAILS loudly (a `check-true`/`check-false` with a
      descriptive message naming which banned path was found) if a future item accidentally
      introduces a non-portable transitive dependency into M1/M2.
- [x] **The portability load test is NON-VACUOUS (drift-detectable) AT 2+ RELATIVE-REQUIRE HOPS
      DEEP, not just at the barrel's own direct `require` list.** Temporarily add `(require
      racket/tcp)` to a scratch copy of a module that is itself only reachable via a RELATIVE
      sub-require from another relatively-required module — e.g. inject it into
      `spec-2025-11-25.rkt` (reachable as `main.rkt → types.rkt → spec-2025-11-25.rkt`, 2 hops
      from the barrel, itself a relative require of a relative require) — re-run the portability
      test, confirm it FAILS with a message identifying `racket/tcp`, then revert. **Testing only
      at 1 hop (injecting into the barrel file itself, or into a module the barrel directly
      `require`s) is INSUFFICIENT and must not be the only drift check performed**, because that
      is exactly the depth at which the original (buggy) version of this algorithm still worked
      correctly — the path-resolution bug this item's algorithm fixes (see §The build contract
      Part C step 2) only manifests when resolving a CHILD module's OWN relative sub-requires,
      i.e. 2+ hops from the walk's starting point. This was verified during spec research: the
      live 2-hop injection test (`racket/tcp` inside `spec-2025-11-25.rkt`) correctly surfaced
      `racket/tcp.rkt` in the visited set using the FIXED algorithm, after first confirming the
      naive/unfixed algorithm's `with-handlers` guard would have silently swallowed the
      resulting bogus-path exception at that same depth instead. Document this drift run in
      Testing Prerequisites' Manual Validation Checklist (mirrors item 007's "Drift detection"
      discipline) and explicitly record the hop depth used.
- [x] **THE QUEUE'S SECOND CORE CLAIM — an internal-only binding is NOT re-exported (the
      curation proof):** `mcp/core/types/main.rkt` does NOT provide `json-object?` **as defined
      in `spec-2025-11-25.rkt`** — concretely, `(dynamic-require (quote (file
      ".../mcp/core/types/main.rkt")) 'json-object? (lambda () 'not-found))` → `'not-found`
      **IS THE WRONG TEST** if `types.rkt` ALSO defines and re-provides ITS OWN `json-object?`
      (verified during spec research: `types.rkt:73` DOES `(provide … json-object? …)` — it is
      `types.rkt`'s OWN binding, not a re-export of `spec-2025-11-25.rkt`'s unprovided one,
      since `spec-2025-11-25.rkt:51`'s `json-object?` is explicitly listed under "Internal wire
      helpers (NOT provided, except `absent`)" at line 47 and is absent from that file's own
      `provide` block at lines 106–256 — confirmed by reading both the comment and the full
      provide list). **The corrected, valid example:** assert that NONE of
      `spec-2025-11-25.rkt`'s internal helpers — `h-opt`, `h-req`, `put`, `put!`, `opt-map`,
      `opt-list`, `req-list`, or `split-loose` (all defined at `spec-2025-11-25.rkt:73–101`,
      none listed in that file's `provide` block) — are reachable through the barrel:
      `(dynamic-require (quote (file ".../mcp/core/types/main.rkt")) 'split-loose (lambda ()
      'not-found))` → `'not-found`. Repeat for `h-opt` and `put!` (pick at least two of the
      eight, per the "do not leave implicit" discipline). **Also assert the errors.rkt private
      data-gate helpers are not leaked through `mcp/core/main.rkt`:**
      `(dynamic-require (quote (file ".../mcp/core/main.rkt")) 'url-elicitation-data? (lambda ()
      'not-found))` → `'not-found` (this helper is defined at `errors.rkt:212`, used only
      internally by `jsonrpc-error->exn`, and is NOT in either of `errors.rkt`'s two `provide`
      blocks at lines 72–83 / 85–106 — confirmed by reading both blocks in full).
- [x] **`raco test` passes (exit 0) over `mcp/core/types/` and `mcp/core/errors.rkt`** — this
      criterion is **inherited, not new**: items 001–007 already deliver passing tests over
      these paths (verified during spec research: `raco test mcp/core/types/` → "750 tests
      passed", exit 0; `raco test mcp/core/test/errors-test.rkt` → "129 tests passed", exit 0,
      both via plain `raco test`, no workaround needed in this environment — see §Testing
      Prerequisites for the corrected environment note). This item's job is to ALSO make `raco
      test` pass over the two NEW barrel files plus the new portability/curation tests, without
      regressing the inherited 750+129.
- [x] **The barrel `require`/`provide` is exactly as specified in §The build contract Parts A/B**
      — no additional `define`s in either barrel file (the `prefix-in` design needs no
      `except-out`/`rename-out`, and introduces no new `define`s either); `grep -c '^(define'
      mcp/core/types/main.rkt mcp/core/main.rkt` → `0` for both (pure re-export files, no new
      logic).
- [x] **Portability (NFR) — both barrels load with zero new transitive non-portable deps beyond
      what items 001–007 already pull in.** The portability test (above) is the mechanized
      proof; additionally, `(require (file "mcp/core/main.rkt"))` from a plain `racket -e`
      one-liner succeeds with no error and no stderr warning about a missing/non-portable
      module.
- [x] **Scope boundary, stated explicitly (not left implicit):**
      (a) **Test submodules are out of scope for the portability walk.** `module->imports` walks
      the ordinary (phase-0/phase-1) import graph of a module; it does NOT see into a `(module+
      test ...)` or `(module test ...)` submodule's OWN `require` list, since a test submodule is
      not imported by its enclosing module unless something explicitly requires it. A banned
      module `require`d ONLY inside a test submodule of one of the six underlying modules (none
      currently exist, but a future item could add one) would NOT be caught by this item's
      portability test — this is a known, accepted scope limit of the chosen mechanism, not a
      bug; if test-submodule portability ever needs checking, that is a separate, future
      mechanism (e.g. walking `module-compiled-submodules` too), explicitly out of scope here.
      (b) **The two barrels form a one-directional DAG, confirmed, not assumed:** `mcp/core/main.rkt`
      `require`s `mcp/core/types/main.rkt` and `mcp/core/errors.rkt`; neither
      `mcp/core/types/main.rkt` nor any of the five modules it wraps `require`s anything from
      `mcp/core/main.rkt` or `errors.rkt` (verified by reading every one of the six underlying
      modules' own `require` clauses during spec research — `errors.rkt` requires only
      `racket/contract` + `types/constants.rkt`; none of the five `types/` modules requires
      `errors.rkt`). No circular `require` exists or is introduced by this item.
- [x] **Parity-matrix / progress discipline:** `docs/aide/progress.md` Stage S1 lines for
      `mcp/core/types/main.rkt` + `mcp/core/main.rkt` (currently 📋 at progress.md lines ~52–53)
      flip 📋 → ✅. Sibling deliverable lines (constants/spec-2025-11-25/spec-2026-07-28/
      types.rkt/guards.rkt/errors.rkt, progress.md lines 46–51, all already ✅) are untouched.
      Per queue-001, this item — together with the already-✅ items 001–007 — completes Stage
      S1's M1+M2 deliverable list EXCEPT item 009's closeout demo script and the
      `mcp/core/types/test/` + `mcp/core/test/errors-test.rkt` deliverable line (progress.md
      line 53), which item 009 also touches (the demo + final test-deliverable checkbox). This
      item does NOT claim the line-53 test-directory deliverable as fully done on its own — it
      only ADDS the barrel + portability + curation tests; the line is shared with items
      003–007's existing test files and is fully retired by item 009's closeout pass.

---

## Implementation steps

1. **Confirm inputs are green.** Run `raco make mcp/core/types/*.rkt mcp/core/errors.rkt &&
   raco test mcp/core/types/ mcp/core/test/errors-test.rkt` from repo root. Confirm 750+129
   tests pass (the baseline this item must not regress). Confirm `racket --version` (this
   session: Racket 8.18, not the 9.1 some prior item notes mention — version drift across
   sessions is expected; what matters is that `raco` itself is NOT broken here — verify this
   yourself before trusting any stale "raco is broken" note in an earlier item).
2. **Read every one of the six modules' `provide` clauses in full** (not just grep for the
   `(provide` line — read to the closing paren) to build the exact `all-from-out` list and spot
   naming collisions BEFORE writing the barrel: `constants.rkt:8–31`, `guards.rkt:30–35`,
   `spec-2025-11-25.rkt:106–256`, `spec-2026-07-28.rkt:111`+ (read to its closing paren —
   ~176 pinned checks in its test suggest a comparably large provide list to 003's), `types.rkt`
   (THREE provide forms: `72–73`, `85–86`, `1319`+ — read all three to their closing parens).
3. **Draft `mcp/core/types/main.rkt`** per §The build contract Part A — `require` the two spec
   modules via `(prefix-in r25: "spec-2025-11-25.rkt")` / `(prefix-in r26: "spec-2026-07-28.rkt")`
   per the Decision in §The barrel re-export mechanism (this resolves the 834-identifier mutual
   collision between the two spec modules AND the smaller façade-alias collisions, all at once,
   with no `except-out`/`rename-out` needed). `raco make` it; confirm exit 0. If it does NOT
   exit 0, re-read §Naming collision analysis — a non-zero exit at this step means either the
   `prefix-in` was applied to the wrong require, or a NEW collision was introduced by an item
   001–007 change since spec-writing time; re-run the `module->exports` pairwise check from
   §Naming collision analysis against the current file contents before assuming the spec's
   collision count is still accurate.
4. **Draft `mcp/core/main.rkt`** per §The build contract Part B. `raco make` it.
5. **Smoke-test the seven representative-binding checks** (1 per underlying module) at a REPL
   before writing the formal test file, to catch a wrong identifier name early.
6. **Write the portability-walk helper + test.** Transcribe the helper exactly as given in
   §Testing strategy Part 2 (the `resolve-mpi`/`dir-of`/`direct-imports`/`transitive-imports`
   functions) — this version already has BOTH fixes applied: the `module->imports`
   single-return-value pitfall (do not `define-values` two values from it) AND the
   relative-path-resolution fix (`base-dir` threaded through the walk via
   `current-load-relative-directory`, NOT a bare CWD-relative resolution — see §The build
   contract Part C step 2 for why the bare version silently truncates the walk). Run it against
   `mcp/core/types/main.rkt` and `mcp/core/main.rkt`. Confirm the visited set is what you expect
   (print it once during development — the verified research transcript against the real
   `types.rkt` showed 215 visited modules with both spec-module files correctly resolved to their
   `mcp/core/types/` paths; the full barrel's visited set will be larger but still finite and
   inspectable).
7. **Run the drift check AT 2+ HOPS DEEP, not just at the barrel's direct `require` list** (inject
   `(require racket/tcp)` into a module reachable only via a relative sub-require of another
   relatively-required module — e.g. into `spec-2025-11-25.rkt`, reachable as `main.rkt →
   types.rkt → spec-2025-11-25.rkt` — confirm the test fails with a message naming `racket/tcp`,
   revert) — do this BEFORE finalizing, not as an afterthought, so the test's actual sensitivity
   at the depth that matters is proven while the surrounding code is still fresh in mind. A
   1-hop-only drift check (injecting into the barrel file itself) is NOT sufficient — see the
   corresponding Acceptance criterion for why.
8. **Write the curation/negative test** (the internal-binding-not-leaked checks) using
   `dynamic-require` with a failure thunk, per the corrected example in Acceptance criteria
   (NOT the originally-floated `json-object?` example, which is invalid because `types.rkt`
   re-provides its OWN same-named binding — use `split-loose`/`h-opt`/`put!` from
   `spec-2025-11-25.rkt` and `url-elicitation-data?` from `errors.rkt` instead).
9. **Decide the test file location(s).** Recommend: `mcp/core/types/test/main-test.rkt` (barrel
   re-export + curation checks for the types barrel) and a new section appended to
   `mcp/core/test/errors-test.rkt` OR a new `mcp/core/test/main-test.rkt` for the top barrel +
   the portability walk (the portability test most naturally covers BOTH barrels at once, so a
   single file under `mcp/core/test/` that requires both seems cleanest — record the final
   choice in Decisions; either layout satisfies "raco test passes over mcp/core/types/ and
   mcp/core/errors.rkt" since `raco test mcp/core/types/` picks up everything under that
   directory recursively and `mcp/core/test/` is a sibling directory already covered by the
   item's own AC wording "over mcp/core/types/ and mcp/core/errors.rkt" — verify `raco test`'s
   directory-recursion behavior covers wherever you place the new file, and adjust the AC's
   literal test invocation if you place it somewhere `raco test mcp/core/types/
   mcp/core/errors.rkt` would miss, e.g. by also invoking `raco test mcp/core/test/`).
10. **Run the full suite** (`raco make` then `raco test`) over the whole `mcp/core/` tree;
    confirm the inherited 750+129 still pass AND the new barrel/portability/curation checks
    pass; scan for any new compiler warning.
11. **Update `docs/aide/progress.md`** — flip the two 📋 lines (progress.md lines 52–53's
    barrel portion only — see Acceptance criteria's note on NOT claiming the full line-53 test
    deliverable alone) to ✅ per the Completion Reminder.

---

## Testing strategy

**New test file(s):** recommend `mcp/core/test/main-test.rkt` (covers BOTH barrels: re-export
presence checks, the portability walk, and the curation/negative checks) — a single file keeps
the portability walk's helper function defined once and reused for both barrel entry points,
rather than duplicating it across two files split by directory. (If the implementer instead
splits types-barrel checks into `mcp/core/types/test/main-test.rkt`, the portability-walk helper
should still be defined once, e.g. in whichever file runs first, or factored as a tiny shared
`(require (only-in …))`-able module — record the final layout in Decisions.)

`#lang racket/base`; `(require rackunit racket/set (file "../main.rkt") (only-in (file
"../types/main.rkt") …representative bindings…))`. Rackunit `check-*` at module top level (so
`racket <file>` exercises them, matching the existing test files' convention — item 006/007's
`errors-test.rkt` convention, confirmed still followed by `raco test` cleanly in this
environment).

### Part 1 — barrel re-export presence (the seven representative-binding checks)

```racket
(require (only-in (file "../main.rkt")
                   INTERNAL-ERROR              ; item 001 via types barrel
                   is-jsonrpc-request?         ; item 002
                   jsonrpc-request?            ; item 003
                   ;; an RC-2026-07-28-only identifier — confirm exact name by reading
                   ;; spec-2026-07-28.rkt's own provide block during implementation
                   facade-implementation?      ; item 005 façade
                   mcp-error? protocol-error?  ; item 006
                   jsonrpc-error->exn))        ; item 007
(check-equal? INTERNAL-ERROR -32603)
(check-true (procedure? is-jsonrpc-request?))
(check-true (procedure? jsonrpc-request?))
(check-true (procedure? facade-implementation?))
(check-true (procedure? mcp-error?))
(check-true (procedure? protocol-error?))
(check-true (procedure? jsonrpc-error->exn))
```

(Add one more `only-in` entry for the chosen 2026-07-28-only identifier once confirmed by
reading that file's provide block; substitute it for `facade-implementation?`'s slot or add an
eighth check — either satisfies "a representative binding from each of the six modules", since
`types.rkt` and `spec-2026-07-28.rkt` are both M1 sources.)

### Part 2 — the restricted-namespace portability walk (the queue's core claim)

**This exact code was live-tested against the real files** (run against `mcp/core/types/types.rkt`
— the deepest real entry point available at spec-writing time, since `types/main.rkt` does not
exist yet — confirming correct resolution 2 hops deep: `types.rkt → spec-2025-11-25.rkt →
constants.rkt` and `types.rkt → spec-2026-07-28.rkt → constants.rkt`, both resolving to the
correct absolute `mcp/core/types/constants.rkt`, zero bogus CWD-relative paths in a 215-module
visited set; and confirming drift-detection at the same 2-hop depth via injecting `(require
racket/tcp)` inside `spec-2025-11-25.rkt`, which correctly surfaced `racket/tcp.rkt` in the
visited set):

```racket
(require racket/set racket/path)

(define banned-module-paths
  '(racket/system racket/port racket/tcp racket/udp
    net/url net/http-client net/sendurl racket/sandbox))

;; Resolve a module-path-index to its resolved-module-path-name, using the
;; REQUIRING module's own directory (base-dir) as the base for relative
;; resolution. THIS IS THE FIX for the bug below — do not drop base-dir.
;;
;; THE BUG a naive version hits: (resolved-module-path-name
;; (module-path-index-resolve mpi)) with NO base-dir context resolves a
;; relative sub-require (e.g. errors.rkt's (require "types/constants.rkt" ...))
;; against the ambient current-load-relative-directory / process CWD, NOT the
;; requiring module's own directory — producing a nonexistent path (verified:
;; this resolved to /home/tlam/racket-mcp/types/constants.rkt instead of
;; .../mcp/core/types/constants.rkt when run from repo root). module->imports
;; then raises on that bogus path, and the with-handlers guard below (correct
;; for its OWN purpose) swallows it as "no further imports" — silently
;; truncating the transitive walk one level early for every relatively-required
;; module, which is most of this codebase.
(define (resolve-mpi mpi base-dir)
  (define resolved
    (parameterize ([current-load-relative-directory base-dir])
      (module-path-index-resolve mpi)))
  (resolved-module-path-name resolved))

;; The directory to use as the base for resolving a module's OWN children.
;; path? names (file-based modules) propagate their containing directory;
;; symbol? names (collection requires, e.g. racket/base) have no meaningful
;; directory here — Racket's collection-path system resolves their own
;; sub-requires, not current-load-relative-directory — so just keep the
;; parent's base-dir (it is never consulted for a symbol-named module).
(define (dir-of name parent-base-dir)
  (if (path? name) (path-only name) parent-base-dir))

(define (direct-imports m base-dir)
  (with-handlers ([exn:fail? (lambda (e) '())])  ; genuine introspection dead-ends only, post-fix
    (define phase-groups (module->imports m))
    (apply append
           (map (lambda (pg) (map (lambda (mpi) (resolve-mpi mpi base-dir)) (cdr pg)))
                phase-groups))))

(define (transitive-imports top top-dir)
  (namespace-require top)
  (let loop ([queue (list (cons top top-dir))] [seen (set)])
    (cond
      [(null? queue) seen]
      [else
       (define m (car (car queue)))
       (define base-dir (cdr (car queue)))
       (cond
         [(or (not m) (set-member? seen m)) (loop (cdr queue) seen)]
         [else
          (define children (direct-imports m base-dir))
          (define child-pairs (map (lambda (c) (cons c (dir-of c base-dir))) children))
          (loop (append (cdr queue) child-pairs) (set-add seen m))])])))

(define (banned-hit? visited banned-sym)
  (for/or ([m (in-set visited)])
    (and (path? m) (regexp-match? (regexp (format "/~a(\\.rkt)?$" banned-sym))
                                   (path->string m)))))

(define (check-portable! top-path top-dir label)
  (parameterize ([current-namespace (make-base-namespace)])
    (define visited (transitive-imports top-path top-dir))
    (for ([b banned-module-paths])
      (check-false (banned-hit? visited b)
                   (format "~a transitively imports banned module ~a" label b)))))

(define types-main-path (path->complete-path "../types/main.rkt" (current-load-relative-directory)))
(check-portable! (list 'file (path->string types-main-path)) (path-only types-main-path) "types/main.rkt")

(define core-main-path (path->complete-path "../main.rkt" (current-load-relative-directory)))
(check-portable! (list 'file (path->string core-main-path)) (path-only core-main-path) "core/main.rkt")
```

(Resolve `types-main-path`/`core-main-path` using whatever absolute-path idiom this codebase's
existing tests use for locating sibling files at runtime — e.g. `(this-expression-source-directory)`
or `runtime-path` — rather than the literal placeholder shown; the key contract this code block
must preserve is that `top-dir` passed into `check-portable!` is the BARREL FILE's own directory,
matching what `transitive-imports` needs for the fix above to apply starting from hop 1.)

**Non-vacuous drift check, AT 2+ HOPS DEEP (manual, documented, not left in the final suite as a
standing test since it requires editing a sibling file):** temporarily add `(require racket/tcp)`
to a SCRATCH copy of `mcp/core/types/spec-2025-11-25.rkt` (reachable as `main.rkt → types.rkt →
spec-2025-11-25.rkt`, i.e. 2 relative-require hops from the barrel — NOT directly into the barrel
file itself or into a module the barrel directly `require`s, which would only exercise 1 hop and
would have passed even with the UNFIXED, buggy version of this algorithm), re-run
`check-portable!`, confirm a `check-false` failure naming `racket/tcp`, then revert. **This exact
2-hop injection was run during spec research and correctly failed naming `racket/tcp`** (216→217
visited modules, `racket/tcp.rkt` present) — confirming both that the walk reaches the injected
dependency at the depth that matters and that the path-resolution fix in `resolve-mpi`/`dir-of`
doesn't itself mask anything. Document the run (output snippet) in Testing Prerequisites'
Validation Results, mirroring item 007's drift-detection discipline, and record the hop depth
used.

### Part 3 — curation / negative checks (internal bindings not leaked)

```racket
(check-equal? (dynamic-require '(file "/ABS/PATH/TO/mcp/core/types/main.rkt")
                                'split-loose (lambda () 'not-found))
              'not-found)
(check-equal? (dynamic-require '(file "/ABS/PATH/TO/mcp/core/types/main.rkt")
                                'h-opt (lambda () 'not-found))
              'not-found)
(check-equal? (dynamic-require '(file "/ABS/PATH/TO/mcp/core/types/main.rkt")
                                'put! (lambda () 'not-found))
              'not-found)
(check-equal? (dynamic-require '(file "/ABS/PATH/TO/mcp/core/main.rkt")
                                'url-elicitation-data? (lambda () 'not-found))
              'not-found)
(check-equal? (dynamic-require '(file "/ABS/PATH/TO/mcp/core/main.rkt")
                                'unsupported-version-data? (lambda () 'not-found))
              'not-found)
```

### Edge cases the test must cover (do not leave implicit)

- **The portability walk is run in a FRESH namespace**, not the test runner's ambient one — a
  test that happens to pass only because no other loaded module pulled in `racket/tcp` yet would
  be a false negative on a future regression introduced by an UNRELATED earlier-loaded module in
  the same process; `(make-base-namespace)` per check closes this.
- **The `prefix-in` collision resolution is actually exercised**, i.e. compiling the barrel does
  not silently shadow one binding with another of the same name without the implementer
  noticing — `raco make` exiting non-zero on a `require`-level collision is the enforcement
  mechanism; the test file additionally asserts (Part 1) that the SPECIFIC `r25:`/`r26:`-prefixed
  names it cares about resolve to the expected per-revision values, catching a typo'd prefix or a
  wrong require form.
- **`module->imports`'s single-return-value shape** — pin this with the helper function as
  written above (NOT `define-values`), since the research transcript showed the naive
  `define-values` form raises an arity-mismatch error in this exact Racket version (8.18).
  (`module->exports`, used only during spec-research collision analysis and not in the shipped
  test file, has the OPPOSITE shape — it returns TWO values; do not confuse the two when reading
  the Decisions section's collision-analysis transcript.)
- **Relative sub-requires resolve against the REQUIRING module's own directory, not the process
  CWD** — pin this with the `base-dir`-threading in `resolve-mpi`/`dir-of`/`transitive-imports`
  as written above. A version that drops `base-dir` and calls
  `(resolved-module-path-name (module-path-index-resolve mpi))` with no `current-load-relative-
  directory` parameterization will silently truncate the walk one level early for every
  relatively-required module — verified to reproduce against this exact codebase (see §The build
  contract Part C step 2). This is the single most important edge case in this entire test file;
  do not regress it.
- **A leaf module that raises on `module->imports` introspection even with correct path
  resolution** (e.g. `#%kernel`, `#%builtin`, `#%paramz`, and certain syntax-phase submodule
  references — 21 such genuine dead-ends were observed walking the real `types.rkt`) does not
  crash the walk — the `with-handlers` guard in `direct-imports` treats it as a dead end, not a
  fatal error. This guard must NOT be the thing catching the relative-path bug above (verify by
  removing the `base-dir` fix temporarily during development and confirming the SAME guard now
  catches a DIFFERENT, larger set of "dead ends" that includes real project modules — if it does,
  the fix is not actually wired in correctly).

### The `raco test` / `raco make` gate (corrected environment note — see Testing Prerequisites)

Run `raco make mcp/core/types/*.rkt mcp/core/errors.rkt mcp/core/types/main.rkt
mcp/core/main.rkt && raco test mcp/core/types/ mcp/core/test/` from the repo root. **In THIS
session `raco` is NOT broken** (Racket 8.18; both commands exit 0 and report pass counts
directly, e.g. "750 tests passed" / "129 tests passed" — verified during spec research). Prior
items' notes claiming `raco`/the snap wrapper is broken describe a DIFFERENT, earlier
environment's quirk and should not be propagated as a standing workaround into this item — if a
future session DOES hit a broken `raco`, fall back to the documented `racket <file>` direct-run
+ output-scan technique items 006/007 used, but do not pre-emptively avoid `raco` here.

---

## Dependencies

- **Upstream work items (ALL ✅ — this item is a pure aggregator over their already-curated
  surfaces, adding no new logic of its own beyond the two re-export files + the portability/
  curation tests):**
  - **Item 001** (`mcp/core/types/constants.rkt`, ✅) — re-exported via
    `(all-from-out "constants.rkt")`.
  - **Item 002** (`mcp/core/types/guards.rkt`, ✅) — re-exported via `(all-from-out
    "guards.rkt")`.
  - **Item 003** (`mcp/core/types/spec-2025-11-25.rkt`, ✅) — required via `(prefix-in r25:
    "spec-2025-11-25.rkt")`, re-exported via `(all-from-out "spec-2025-11-25.rkt")` under its
    `r25:`-prefixed names (the `prefix-in` resolves both the 834-identifier collision against
    item 004 and the smaller façade-alias collision against item 005 — see §Naming collision
    analysis / §Decisions).
  - **Item 004** (`mcp/core/types/spec-2026-07-28.rkt`, ✅) — required via `(prefix-in r26:
    "spec-2026-07-28.rkt")`, re-exported via `(all-from-out "spec-2026-07-28.rkt")` under its
    `r26:`-prefixed names, same rationale as item 003.
  - **Item 005** (`mcp/core/types/types.rkt`, ✅) — re-exported via `(all-from-out "types.rkt")`,
    unprefixed; ALSO the source of the façade-alias names that collide with 003/004's UNPREFIXED
    surface (resolved by prefixing 003/004 rather than touching 005 — see §Decisions).
  - **Item 006** (`mcp/core/errors.rkt` ENCODE half, ✅) + **Item 007** (DECODE half, ✅,
    completing the file) — together re-exported via `(all-from-out "errors.rkt")` in
    `mcp/core/main.rkt`.
- **Forward / downstream consumers (informational):** Stage S2 (validators/schema/shared utils,
  queue-002) and every later stage's modules are expected to `require (file
  "mcp/core/main.rkt")` (or the types-only `mcp/core/types/main.rkt` where errors are not
  needed) as their SINGLE entry point into Stage S1's public surface, per architecture §1.3 — so
  this item's barrel shape is the API contract every later item inherits. Getting the
  curation/collision decisions right here avoids a breaking barrel-surface change later.
- **Operates on:** pure module-graph composition (`require`/`provide`) + introspection
  (`module->imports`) at test time. No file/network I/O at the barrels' own module load time;
  the test file performs in-process namespace/module introspection only (no subprocess, no
  socket — consistent with what it is proving about its subjects).
- **Tooling/runtime:** Racket ≥ 8.x (this session: 8.18; `raco make`/`raco test` BOTH confirmed
  working, not broken); `rackunit`; `racket/set` (for the visited-module-set); the
  `typescript-sdk/` checkout is NOT needed for this item (no TS line-for-line port — see
  Reference impl note above).

---

## Project-specific adaptations (Racket module system / barrels / restricted namespaces)

This template's "Required Services / database / API endpoint" framing does not apply: **this is
a pure module-composition item (two re-export files) plus a module-graph introspection test —
no external services, no I/O at barrel load time.** Adaptations:

- **`main.rkt` as the Racket idiom for a curated package barrel.** Racket collections
  conventionally expose a `main.rkt` (or `collection-name.rkt`) as the "import this for
  everything" entry point — directly mirroring what architecture §1.3 calls out as "Mirrors TS
  `core/public` vs internal barrel" (a TS package's `index.ts` re-export surface). No class/
  namespace-object transliteration needed (G4) — Racket's `require`/`provide`/`all-from-out` IS
  the idiomatic mechanism, simpler than TS's barrel-file re-export syntax.
- **`all-from-out` vs hand-picked re-export — the per-module decision is documented above** (not
  repeated here); the Racket-specific subtlety this surfaces is that `require`ing two modules
  that export the same identifier unprefixed fails at `require` time (`module: identifier already
  required`), and even a successful `require` followed by an `all-from-out` `provide` of two
  colliding names fails separately at `provide` time (`all-from-out: name clashes`) — TWO distinct
  Racket-specific failure modes with no direct TS analogue (TS's `export *` resolves collisions by
  last-write-wins shadowing silently, which Racket deliberately refuses to do at either level).
  This item hits the `require`-time form (834 colliding identifiers between the two per-revision
  spec modules) and resolves it with `prefix-in`, which sidesteps both failure modes at once. This
  item's collision-resolution step is therefore genuinely Racket-idiomatic work, not a mechanical
  port.
- **`module->imports` + `module-path-index-resolve` as the restricted-namespace mechanism.**
  Racket has no single "give me the transitive import closure" built-in; the walk is hand-rolled
  over the primitive `module->imports` (returns per-phase direct-import lists as
  `module-path-index` values needing resolution) — analogous to (but with no TS equivalent,
  since TS/JS has no comparable reflective module-graph introspection API at this level) a
  manual `require.resolve` + dependency-graph walk one might hand-roll in Node, except Racket's
  version operates on already-COMPILED module metadata, not source-text scanning, making it more
  reliable (it cannot be fooled by a `require` hidden behind a string-concatenation or dynamic
  `require` call the way a naive static source scan could be — though a TRUE `dynamic-require`
  at runtime, executed conditionally, could still evade this static-import-graph check; that
  residual gap is acceptable for L0 foundation modules which have no business doing conditional
  dynamic requires in the first place, and is noted, not solved, here).
- **No services / no I/O / no fixtures.** The test file requires its subjects and introspects
  in-memory module metadata; no `fixtures/` directory needed (same posture as items 006/007).

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None.** No I/O at barrel module load, no service contacted; the portability test's whole point
is that NONE is reachable. External artifacts:

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime (this session: 8.18) | compile + run modules/tests (`rackunit`, `racket/set`) | system install (`racket --version` ≥ 8.0) | n/a |
| Items 001–005 (`mcp/core/types/*.rkt`, ✅) | the five modules the types barrel re-exports | produced by items 001–005 | n/a |
| Item 006+007 (`mcp/core/errors.rkt`, ✅, both halves) | the module the top barrel additionally re-exports | produced by items 006–007 | n/a |

No databases, queues, HTTP servers, or network dependencies — and the portability test's entire
purpose is to MECHANICALLY confirm that remains true transitively, not just by inspection.

### Environment Configuration — CORRECTED `raco` note (verify-before-trust, per this item's brief)

- **Environment variables / secrets / config files:** none.
- **Ports:** none must be free.
- **Working directory:** run tests from the **repo root** (`/home/tlam/racket-mcp`) so the
  `mcp/...` collection + relative requires resolve.
- **`raco` status in THIS session — VERIFIED, not assumed:**
  `racket --version` → `Welcome to Racket v8.18 [cs].`
  `raco make mcp/core/types/constants.rkt mcp/core/types/guards.rkt
  mcp/core/types/spec-2025-11-25.rkt mcp/core/types/spec-2026-07-28.rkt
  mcp/core/types/types.rkt mcp/core/errors.rkt` → **exit 0, no output (clean compile).**
  `raco test mcp/core/types/` → exit 0, reports "750 tests passed" (with intermediate
  `pinned check count` lines from spec-2025-11-25-test/spec-2026-07-28-test/types-test).
  `raco test mcp/core/test/errors-test.rkt` → exit 0, "errors-test.rkt: all checks executed",
  "129 tests passed". **Conclusion: `raco` (both `make` and `test` subcommands) works correctly
  and reports results directly in this environment.** Item 007's prose ("`raco` IS BROKEN in
  this sandbox … the `raco` snap wrapper … silently exits 1") describes a PRIOR, DIFFERENT
  session's environment quirk (a different Racket install / snap-wrapper path,
  `/home/rev/Linux/Projects/racket_mcp` vs this session's `/home/tlam/racket-mcp` — note even
  the repo root path differs, confirming a different machine/session) and does NOT describe
  THIS session. **Do not propagate the `racket <file>` direct-run workaround into this item's
  own Manual Validation Checklist as if it were still necessary** — use plain `raco make` /
  `raco test` as the canonical commands, and if a future session's `raco` IS observed broken,
  fall back to the direct-run technique THEN (re-verifying first), not pre-emptively.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0 (this session: 8.18).
  - `raco make mcp/core/types/*.rkt mcp/core/errors.rkt` → exit 0 (items 001–007 baseline).
  - `raco test mcp/core/types/ mcp/core/test/errors-test.rkt` → exit 0, 750+129 tests passed
    (the regression baseline this item must not break).
  - `test -f mcp/core/types/types.rkt && test -f mcp/core/errors.rkt` → items 005/007 present.
  - `test ! -f mcp/core/types/main.rkt && test ! -f mcp/core/main.rkt` → confirms these are
    genuinely NEW files this item creates (verified during spec research: neither exists yet,
    nor does any `info.rkt` anywhere under `mcp/`).

### Manual Validation Checklist

- [x] **Build/compile:** `raco make mcp/core/types/main.rkt mcp/core/main.rkt` compiles clean,
      exit 0 (the outcome-based check — do NOT assert absence of one specific error substring; a
      `require`-level collision and a `provide`-level collision produce two DIFFERENT error
      strings, and `prefix-in` on the two spec modules' requires should make both moot, but exit
      0 is the actual gate, not eyeballing an error message).
- [x] **Regression — prior items still green:** `raco test mcp/core/types/ mcp/core/test/
      errors-test.rkt` → still 750+129 tests passed, 0 new failures (the barrel files must not
      perturb anything already delivered).
- [x] **Barrel re-export verified (REPL):** `racket -e '(require (file
      "mcp/core/main.rkt")) (displayln INTERNAL-ERROR) (displayln (procedure?
      jsonrpc-error->exn))'` → prints `-32603` then `#t`.
- [x] **New barrel/portability/curation tests pass:** `raco test mcp/core/test/` (or wherever
      the new test file(s) live per Implementation step 9's chosen layout) → exit 0, all new
      checks pass.
- [x] **Portability walk verified (REPL smoke, before trusting the formal test):** run the
      `transitive-imports` helper (§Testing strategy Part 2 — the FIXED version with `base-dir`
      threading) against `(file "mcp/core/main.rkt")` in a fresh `racket -e` invocation; manually
      eyeball the printed visited set contains no `racket/system`/`racket/tcp`/`racket/udp`/`net/*`
      entries, AND that every relatively-required project module (e.g.
      `mcp/core/types/constants.rkt`) resolved to its CORRECT path under `mcp/core/types/`, not a
      bogus path missing that directory segment (the path-resolution bug's signature).
- [x] **Drift detection AT 2+ HOPS DEEP (non-vacuous proof):** inject `(require racket/tcp)` into
      a scratch/draft copy of `mcp/core/types/spec-2025-11-25.rkt` (reachable as `main.rkt →
      types.rkt → spec-2025-11-25.rkt`, NOT directly into the barrel file or a module it directly
      `require`s — a 1-hop-only injection does not exercise the relative-path fix); re-run the
      portability check; confirm a `check-false` FAILURE naming `racket/tcp`; revert; re-run;
      confirm clean. Record the failing-run output snippet AND the hop depth used in Validation
      Results below (mirrors item 007's drift-detection discipline).
- [x] **Curation negative checks verified (REPL):** `(dynamic-require '(file
      "mcp/core/types/main.rkt") 'split-loose (lambda () 'not-found))` → `'not-found`;
      `(dynamic-require '(file "mcp/core/main.rkt") 'url-elicitation-data? (lambda () 'not-found))`
      → `'not-found`.
- [x] **No new `define`s in the barrels:** `grep -c '^(define' mcp/core/types/main.rkt
      mcp/core/main.rkt` → `0` for both files (pure require+provide).
- [x] **`module->imports` single-value pitfall avoided:** code review confirms the walk helper
      does NOT use `(define-values (imps _) (module->imports m))` (which raises an arity-mismatch
      in this Racket version) but instead binds the single returned list directly.
- [x] **Relative-path-resolution fix present, not regressed:** code review confirms
      `resolve-mpi` parameterizes `current-load-relative-directory` to the REQUIRING module's own
      directory (`base-dir`) before calling `module-path-index-resolve`, and that `base-dir` is
      threaded through `transitive-imports`/`dir-of` per-module (not a single fixed value reused
      for every module in the walk) — a regression here silently truncates the walk one level
      early for every relatively-required module, exactly the bug this item fixes.
- [x] **Scope boundary checks acknowledged:** confirm (and note in Validation Results) that the
      portability walk does not claim to cover test-submodule-only requires, and that the two
      barrels' `require` graph was inspected and confirmed to have no cycle.
- [x] **Health checks pass:** N/A.

### Expected Outcomes

The two new files export NOTHING beyond what `all-from-out` mechanically re-exports from their
`require`d siblings (zero new `define`s). The new test file(s) add:

- **barrel re-export checks:** ≥ 7 (one per underlying module, Part 1).
- **portability-walk checks:** ≥ 2 (one per barrel entry point: `types/main.rkt`,
  `core/main.rkt`) × the size of `banned-module-paths` (8 banned paths) = ≥ 16 individual
  `check-false` assertions, OR ≥ 2 if implemented as one aggregate assertion per barrel
  (recommend per-banned-path granularity for a more informative failure message — record the
  choice).
- **curation negative checks:** ≥ 5 (at least 3 from `spec-2025-11-25.rkt`'s internal helpers,
  ≥ 2 from `errors.rkt`'s private data-gate helpers, per Part 3).
- **Total new checks: ≥ ~25–30**, atop the inherited 750 (types) + 129 (errors) = 879 existing
  checks, none regressed.

### Validation Results

```markdown
## Validation Results (completed during implementation — Racket 8.18, repo root /home/tlam/racket-mcp)
- [x] Service started: N/A (pure module-composition item, no services)
- [x] Build verified: `raco make mcp/core/types/main.rkt mcp/core/main.rkt` → exit 0, no output
      (clean). No require-time or provide-time collision reported — the `prefix-in r25:/r26:`
      design compiled first try.
- [x] Regression verified: `raco test mcp/core/types/ mcp/core/test/errors-test.rkt` → exit 0,
      879 tests passed (750 types + 129 errors), 0 new failures. Full tree
      `raco test mcp/core/types/ mcp/core/test/` → exit 0, **908 tests passed** (879 inherited +
      29 new in main-test.rkt).
- [x] Barrel re-export verified: via `racket -e '(require (file "mcp/core/main.rkt")) …'` and the
      Part 1 checks — `INTERNAL-ERROR` = -32603; `is-jsonrpc-request?`, `r25:jsonrpc-request?`,
      `r26:related-task-metadata-task-id`, `facade-text-content?`, `mcp-error?`,
      `protocol-error?`, `jsonrpc-error->exn` all `procedure? = #t`. (r25:/r26: prefixes resolve.)
- [x] Portability walk verified: visited-module-path set size = **219** for `core/main.rkt`;
      all 8 banned paths absent for BOTH `types/main.rkt` and `core/main.rkt` (16 `check-false`
      pass). All 7 relatively-required project modules resolved to correct absolute paths under
      `mcp/core/` / `mcp/core/types/` (constants, guards, spec-2025-11-25, spec-2026-07-28,
      errors, types, types/main); zero bogus CWD-relative paths (the
      `racket-mcp/types/constants.rkt` bug signature checked for and absent → `#f`).
- [x] Drift detection verified AT 2 HOPS DEEP: injected `(require racket/tcp)` into
      `mcp/core/types/spec-2025-11-25.rkt` (reachable `main.rkt → types.rkt →
      spec-2025-11-25.rkt`). Re-run → 2 `check-false` FAILURES:
      `"types/main.rkt transitively imports banned module racket/tcp"` and
      `"core/main.rkt transitively imports banned module racket/tcp"`, "2/29 test failures",
      exit 1. Reverted → `29 tests passed`, exit 0.
- [x] Curation negative checks verified: `split-loose`, `h-opt`, `put!` via `types/main.rkt` →
      `'not-found`; `url-elicitation-data?`, `unsupported-version-data?` via `main.rkt` →
      `'not-found` (5/5).
- [x] No-new-defines verified: `grep -c '^(define' …` → `mcp/core/main.rkt:0`,
      `mcp/core/types/main.rkt:0`.
- [x] module->imports single-value pitfall avoided: `direct-imports` binds the single returned
      list (`(define phase-groups (module->imports m))`), no `define-values`.
- [x] Relative-path-resolution fix present: `resolve-mpi` parameterizes
      `current-load-relative-directory` to `base-dir`; `dir-of` derives each child's base from
      its own `path-only`; `transitive-imports` threads `(module . base-dir)` pairs per-module.
- [x] Scope-boundary notes acknowledged: test-submodules out of scope of `module->imports`;
      one-directional DAG confirmed (no cycle).
- [x] Database tables verified: N/A
- [x] API endpoints verified: N/A
- [x] Screenshots captured: N/A (no UI)
```

### Test commands run and results

All from repo root `/home/tlam/racket-mcp`, Racket v8.18 [cs].

```
$ raco make mcp/core/types/*.rkt mcp/core/errors.rkt        # baseline inputs
  → exit 0 (clean)
$ raco test mcp/core/types/ mcp/core/test/errors-test.rkt   # baseline regression
  → 879 tests passed, exit 0   (750 types + 129 errors)

$ raco make mcp/core/types/main.rkt mcp/core/main.rkt       # the two new barrels
  → exit 0, no output (no require-time / provide-time collision; prefix-in design clean)

$ raco test mcp/core/test/main-test.rkt                     # new barrel/portability/curation suite
  → 29 tests passed, exit 0

$ raco test mcp/core/types/ mcp/core/test/                  # whole tree
  → 908 tests passed, exit 0   (879 inherited, 0 regressed; +29 new)

$ grep -c '^(define' mcp/core/types/main.rkt mcp/core/main.rkt
  mcp/core/types/main.rkt:0
  mcp/core/main.rkt:0
```

**Portability-walk smoke (fresh `make-base-namespace`, `core/main.rkt`):** visited count 219;
project modules all resolved correctly (constants/guards/spec-2025-11-25/spec-2026-07-28/errors/
types/types-main under `mcp/core/[types/]`); bogus CWD-relative `racket-mcp/types/constants.rkt`
present? `#f`.

**Drift-injection transcript (2 hops: `(require racket/tcp)` into `spec-2025-11-25.rkt`):**
```
FAILURE
name:       check-false
message:    "types/main.rkt transitively imports banned module racket/tcp"
FAILURE
name:       check-false
message:    "core/main.rkt transitively imports banned module racket/tcp"
2/29 test failures      (exit 1)
```
After revert: `29 tests passed` (exit 0).

---

## Decisions & Trade-offs

- **Barrel re-export = per-module `(all-from-out …)`, not a hand-picked list.** Both barrels
  ship exactly the `require`/`provide` forms in §Build contract Parts A/B, verbatim. `raco make`
  exit 0 on both; `grep -c '^(define'` = 0 for both → confirmed pure re-export, zero new logic,
  zero `_meta`-type scope creep.
- **`prefix-in r25:/r26:` on the two spec modules.** Applied exactly as the spec's Decision
  prescribes (mirrors `types.rkt`'s own internal pattern). Compiled clean first try — the
  834-identifier `spec-2025-11-25` × `spec-2026-07-28` require-level collision never surfaced
  because both are prefixed; no `except-out`/`rename-out` needed anywhere. Re-exported under
  their prefixed names (`r25:jsonrpc-request?`, `r26:related-task-metadata-task-id`), confirmed
  reachable through the TOP barrel via Part 1 checks.
- **Representative-binding identifiers (verified against the real files, since the spec did not
  re-enumerate every binding):** item 005 façade predicate is `facade-text-content?` — the
  spec's suggested `facade-implementation?` does NOT exist in `types.rkt` (the façade structs are
  content/error-shaped, e.g. `facade-text-content?`, `facade-internal-error?`); substituted.
  item 007's `jsonrpc-error->exn`, item 006's `mcp-error?`/`protocol-error?`, item 003's
  `r25:jsonrpc-request?` (the `struct-out jsonrpc-request` predicate), item 004's
  `r26:related-task-metadata-task-id` all confirmed present.
- **Banned-path comparison mechanism chosen: path-tail regexp** —
  `(regexp-match? (regexp (format "/~a(\\.rkt)?$" banned-sym)) (path->string m))` applied only to
  `path?`-shaped visited names. In THIS environment (Racket 8.18) every `racket/*` collection
  module resolves through `module-path-index-resolve` → `resolved-module-path-name` to a `path?`
  pointing into the installed `collects/` tree (e.g. `.../collects/racket/contract.rkt`), so the
  path-tail check is the robust form; symbol-shaped names never occurred in the 219-module
  visited set, so no symbol-comparison branch was needed (kept the `(path? m)` guard so a
  hypothetical symbol name simply never matches a banned path rather than erroring).
- **Test file location: single `mcp/core/test/main-test.rkt`** covering BOTH barrels (Parts 1/2/3
  in one file) so the portability-walk helper is defined once and reused for both entry points.
  Picked up by `raco test mcp/core/test/`; `raco test mcp/core/types/` still passes the inherited
  750 unchanged.
- **`racket/port` survives the actual walk (not a transitive dep).** The conservatively-banned
  `racket/port` is NOT present in either barrel's transitive closure — the `check-false` for it
  passes, confirming the ban is satisfied, not merely declared.
- **Scope boundaries confirmed:** (a) test-submodule requires are out of scope of
  `module->imports` (accepted limit); (b) the two barrels form a one-directional DAG — verified
  no cycle: `main.rkt → {types/main.rkt, errors.rkt}`, and none of the five `types/` modules nor
  `errors.rkt` requires back up into either barrel.

---

## Completion Reminder

On completion, the implementer MUST:

1. **Update `docs/aide/progress.md` — Stage S1 barrel deliverable line.** Flip the
   `mcp/core/types/main.rkt` + `mcp/core/main.rkt` barrels line (currently 📋 at progress.md
   line ~52) 📋 → **✅**. Never revert an icon backward.
2. **Touch the `mcp/core/types/test/` + `mcp/core/test/errors-test.rkt` deliverable line**
   (progress.md line ~53) ONLY to the extent this item's own new tests land alongside it — per
   Acceptance criteria's note, do NOT mark that line fully ✅ on this item alone if item 009's
   closeout demo/test pass is still expected to touch it; coordinate the exact wording with
   whatever item 009 finds when it runs (a brief note like "barrel + portability + curation
   tests added by item 008; demo + final closeout by item 009" is acceptable if the line is
   shared).
3. **Per queue-001, this item completes Stage S1's M1+M2 deliverable list in full EXCEPT item
   009's closeout demo.** With items 001–008 all ✅, Stage S1's `### Deliverables` list
   (roadmap.md lines 78–86) is entirely satisfied except the demo script item 009 separately
   adds; the progress.md Stage S1 status line itself (`## Stage S1 — … — 📋` at progress.md line
   41) should likely flip to 🚧 or remain 📋 pending item 009's own closeout pass — DO NOT flip
   the Stage S1 HEADER to ✅ in this item (that is item 009's call once the demo + final
   parity-matrix/progress edits land, per queue-001 Item 009's own description "Completes Stage
   S1; unblocks queue-002 / Stage S2").
4. **Touch the §9 parity-matrix rows** (if `docs/aide/roadmap.md` §9 exists with per-module
   rows distinct from the Stage-S1 testing-criteria bullet already touched by items 006/007) to
   note that `core/types/*` and `core/errors/*` now have a curated barrel entry point, mirroring
   the TS SDK's public/internal package-export split (architecture §1.3) — confirm whether §9 is
   a separate section from what's already been touched, and update only what is genuinely new
   (the barrel's existence), not re-litigate the per-module `partial`/`full` status items
   003–007 already set.
5. Leave items 001–007's own files and their individual progress.md/parity-matrix entries
   UNTOUCHED beyond what is explicitly required above — this item adds two new files + tests; it
   does not re-open or re-grade the already-✅ deliverables it re-exports.
