# Work Item 017: S2 validators/util/shared portability sweep + parity-matrix touch

> **Queue:** `docs/aide/queue/queue-002.md` — Item 017
> **Stage:** S2 (Foundation: validators, schema, shared utilities — L0 part 2)
> **Modules touched (TEST + DOCS only, no module source changes):** the seven built non-I/O S2 modules — `mcp/core/validators/provider.rkt` (M3, item 010), `mcp/core/validators/from-json-schema.rkt` (M3, item 011), `mcp/core/util/schema.rkt` (M4, item 012), `mcp/core/shared/uri-template.rkt` (M5a, item 013), `mcp/core/shared/tool-name-validation.rkt` (M5b, item 014), `mcp/core/shared/metadata-utils.rkt` (M5c, item 015), `mcp/core/shared/auth.rkt` (M5d, item 015). **Deliberately EXCLUDES** `mcp/core/shared/stdio.rkt` (M5e, item 016) — the one S2 module permitted to touch byte-stream I/O (see Edge Case below).
> **Source vision:** `docs/aide/vision.md` §6 (Portability NFR — runtime-neutral core L0–L2 loads with **no** subprocess/socket module), G3 (parity-matrix discipline).
> **Source roadmap:** `docs/aide/roadmap.md` Stage S2 — acceptance line `roadmap.md:131` (parity rows `validators/*`, `util/schema`, `uriTemplate`, `toolNameValidation`, `metadataUtils`, `auth` marked `partial`); `roadmap.md:23` (each stage updates the §9 parity matrix rows it touches).
> **Source architecture:** `docs/aide/architecture.md` §4.1 (Runtime-neutral core L0–L2 imports no subprocess/socket).
> **S1 template (REUSE, do not re-derive):** `mcp/core/test/main-test.rkt:43-114` — the existing restricted-namespace transitive portability walk over the two S1 barrels. Item 017 points the SAME walk at the S2 module roots.
> **Status:** ✅ Delivered — `mcp/core/test/s2-portability-test.rkt` (63 checks green); parity rows flipped `partial`; teeth-check RED→reverted confirmed. No module source changed.

---

## Description

This item closes Stage S2's two outstanding cross-cutting obligations. It writes **no module source** — it is a single new test file plus the progress/roadmap parity-matrix edits.

**1. The collection-wide S2 restricted-load portability proof.** Items 010–015 each ship a *per-module* portability walk inside their own test (e.g. `uri-template-test.rkt:336-344`). What is still missing — and what every prior item's "Decisions" deferred to **item 017** — is the **single, collection-spanning** sweep that asserts the Portability NFR for all S2 non-I/O modules at once: requiring any of the seven modules in (Modules touched) pulls in **no** subprocess/socket module, transitively, at any import depth. This mirrors what `main-test.rkt` already does for the two S1 barrels, now extended to S2's leaves.

**2. The parity-matrix touch.** Flip the six S2 parity rows (`validators/*`, `util/schema`, `uriTemplate`, `toolNameValidation`, `metadataUtils`, `auth`) to `partial` — *modules exist and round-trip TS fixtures; full cross-SDK conformance exercise is deferred to S9*. Record this in `progress.md` (the narrative + the acceptance box) and reconcile `roadmap.md` §9.

### The mechanism (reuse the S1 walk verbatim)

`main-test.rkt:49-105` already defines everything the sweep needs; **copy it** (or factor it — see Decisions) into the new test:
- `banned-module-paths` (`main-test.rkt:49-51`) = `'(racket/system racket/port racket/tcp racket/udp net/url net/http-client net/sendurl racket/sandbox)`.
- `resolve-mpi` / `dir-of` / `direct-imports` / `transitive-imports` / `banned-hit?` / `check-portable!` (`main-test.rkt:60-105`) — a fresh `make-base-namespace`, a transitive `module->imports` BFS, base-dir threading for relative requires, and a regexp banned-hit match.

For **each** of the seven S2 roots, run `check-portable!` (asserts no banned module is transitively reachable) **plus** a **teeth-proving non-vacuity guard** (below). The bare `(> (set-count visited) 1)` guard from `uri-template-test.rkt:336-341` is **NOT sufficient here** and MUST be strengthened — see "Non-vacuity: the truncation hazard" — because it is provably blind to a silently-truncated walk.

#### Per-root base-dir is load-bearing (PINNED)

The walk threads a `base-dir` so a relatively-required module (`../main.rkt`) resolves against the **requiring module's own directory**, not the CWD (`main-test.rkt:53-59`). A wrong base-dir makes the relative require fail to resolve, `module->imports` raises, `direct-imports`' `with-handlers` swallows it, and the walk **silently truncates one level early** — losing the entire S1 subtree. **The seven roots span THREE directories** (`validators/`, `util/`, `shared/`) — unlike the S1 template and every per-module walk, which each used a single dir where `(path-only root)` was obviously right. So the base-dir for each root MUST be `(path-only <that-root-path>)`, **computed per root**, NEVER a single shared `here`-derived base-dir. An implementer who factors a `(check-root path)` helper but threads one shared base-dir gets the truncation for every root in the "wrong" collection — and a count-only guard waves it through.

#### Non-vacuity: the truncation hazard (PINNED — strengthen the guard)

A truncated walk that never reaches the S1 subtree still reports `visited ≈ 79` (racket/base's own closure) and **passes `> 1` green** — empirically confirmed (a wrong-base-dir `metadata-utils` walk reports `visited=79`, S1 subtree reached `#f`, `> 1` passes). A correct S1-importing walk visits **220–233** modules; `tool-name-validation` visits **82**; a broken one ~79 — so no count threshold cleanly separates correct from broken. Prove teeth by **path presence**, per root:
- **The six S1-importing roots** (`provider`, `from-json-schema`, `util/schema`, `uri-template`, `metadata-utils`, `auth`): assert `visited` contains a resolved path matching a known S1 edge — e.g. `#rx"core/main\\.rkt"` or `#rx"spec-2026"` — proving the relative `../main.rkt` edge actually resolved (not truncated). A bare count threshold is brittle; path-presence is the honest proof.
- **`tool-name-validation.rkt`** (NO S1 edge — base-collections-only per item 014): assert `visited` contains `racket/string` or `racket/list` resolved (its only declared imports) — e.g. a path matching `#rx"/(string|list)\\.rkt$"` — or floor at `>= 50`. `> 1` is meaningless here.

A small positive-match helper mirrors `banned-hit?` but asserts presence: `(check-true (for/or ([m (in-set visited)]) (and (path? m) (regexp-match? RX (path->string m)))) "walk truncated — S1 edge not reached for <root>")`.

### Edge Case — stdio.rkt (M5e) is DELIBERATELY isolated from the sweep (PINNED)

The queue designates `mcp/core/shared/stdio.rkt` as "the only S2 module permitted to touch I/O." The sweep MUST therefore **not** walk `stdio.rkt`. Three facts the implementer must honor:

- **(a) Why excluded:** M5e is the newline-delimited framing buffer; it is byte/bytes manipulation (no real device I/O of its own), but the queue frames it as the I/O carve-out and item 016 (`016-stdio-framing.md:156`) explicitly states the formal sweep + isolation are **item 017's job** and that 017 isolates stdio. Walking it is out of scope; do not add it to the roots list.
- **(b) Ordering — 016 may not have landed yet.** As of this spec, `mcp/core/shared/stdio.rkt` does **not exist** (`progress.md:78` is 📋; item 016 has a spec but is unexecuted). The sweep references each root by an explicit path and lists ONLY the seven non-I/O modules — it never globs `mcp/core/shared/*.rkt` — so a missing `stdio.rkt` changes nothing. **If 016 lands first**, `stdio.rkt` simply remains absent from the roots list (still isolated); **if it has not landed**, the test must still not import it. Either way the sweep is identical. Do **not** make the test conditional on `stdio.rkt`'s existence.
- **(c) Do not glob.** Enumerate the seven roots literally. A `directory-list`/glob over `shared/` would silently pick up `stdio.rkt` the moment 016 lands, breaking the carve-out. Literal paths are the safeguard.

### Scope guards (do NOT cross)

- **No module source edits.** This item adds ONE test file + edits `progress.md` (and reconciles `roadmap.md`). It does not modify any `.rkt` under `validators/`, `util/`, or `shared/`.
- **No rewrite of existing tests.** The per-module walks in `validators/test/`, `util/test/`, `shared/test/` stay as-is. Item 017 ADDS a sweep; it does not delete or refactor the existing suites. (If factoring the walk into a shared helper — see Decisions — `main-test.rkt` MUST stay green and its behaviour unchanged.)
- **No stdio in the roots.** See Edge Case.

---

## Acceptance Criteria

- [x] `mcp/core/test/s2-portability-test.rkt` exists as `#lang racket/base` (`(require rackunit racket/set racket/path racket/runtime-path)` — same requires as `main-test.rkt:13-16`). A single collection-spanning test mirroring `main-test.rkt`.
- [x] It defines (copied or factored from `main-test.rkt:49-105`) `banned-module-paths` + the `resolve-mpi`/`dir-of`/`direct-imports`/`transitive-imports`/`banned-hit?`/`check-portable!` helper set. `banned-module-paths` matches `main-test.rkt:49-51` exactly.
- [x] It walks **exactly these seven roots**, each via a path built from `define-runtime-path here "."` + `build-path here ".." …` (mirroring `main-test.rkt:107-114`): `validators/provider.rkt`, `validators/from-json-schema.rkt`, `util/schema.rkt`, `shared/uri-template.rkt`, `shared/tool-name-validation.rkt`, `shared/metadata-utils.rkt`, `shared/auth.rkt`.
- [x] **Per-root base-dir.** Each root's walk is seeded with `base-dir = (path-only <that-root-path>)`, computed **per root** (NOT a single shared `here`-derived base-dir). If the walk is factored behind a `(check-root path)` helper, the helper derives the base-dir from its own `path` argument. (Load-bearing: a shared base-dir silently truncates roots in the "wrong" collection — see Description.)
- [x] For each root: `check-portable!` asserts NO `banned-module-paths` entry is transitively reachable.
- [x] **Teeth-proving non-vacuity guard, per root** (replaces bare `(> (set-count visited) 1)`, which is provably blind to a truncated walk): the six S1-importing roots (`provider`, `from-json-schema`, `util/schema`, `uri-template`, `metadata-utils`, `auth`) each assert `visited` contains an S1-edge path (`#rx"core/main\\.rkt"` or `#rx"spec-2026"`); `tool-name-validation.rkt` asserts `visited` contains `racket/string`/`racket/list` (`#rx"/(string|list)\\.rkt$"`) or floors at `>= 50`.
- [x] **Teeth / mutation check performed.** The implementer temporarily adds `(require racket/tcp)` to one swept root, runs the sweep, confirms it goes **RED** (the banned-module assertion fires), then reverts — proving the sweep can fail. Recorded in Decisions.
- [x] `mcp/core/shared/stdio.rkt` is **NOT** in the roots list, with an in-file comment stating it is excluded **as a root** (the permitted-I/O carve-out, M5e) — and clarifying that if any swept module ever transitively imports `stdio.rkt`, the sweep would walk into it and (correctly) surface stdio's banned imports as the *importing* module's portability regression (stdio is not exempt from portability). The roots are enumerated literally (no `directory-list`/glob over `shared/`).
- [x] `raco test mcp/core/validators/ mcp/core/util/ mcp/core/shared/` is green (exit 0) — all existing S2 per-module suites still pass (this item touches none of them).
- [x] `raco test mcp/core/test/s2-portability-test.rkt` passes (exit 0) — no subprocess/socket module pulled in by any of the seven non-I/O modules; all seven teeth-proving guards hold.
- [x] `raco test mcp/core/test/` (the dir-wide superset, MANDATORY) passes (exit 0) — runs the new sweep AND `main-test.rkt`/`errors-test.rkt`, catching any factor-path regression in `main-test.rkt`.
- [x] **If the walk was factored** out of `main-test.rkt`: `raco test mcp/core/test/main-test.rkt` is green and its check count is unchanged from before the factoring. (N/A if the helper was copied, not factored.)
- [x] **Parity acceptance box** (`progress.md:88`): `[ ] Parity rows validators/*, util/schema, uriTemplate, toolNameValidation, metadataUtils, auth marked partial` → `[x]`.
- [x] **Catch-all raco box** (`progress.md:82`): `[ ] raco test over all S2 modules passes` → `[x]` **with an explicit scope caveat** so it does not contradict the still-📋 stdio rows (`progress.md:78` deliverable 📋, `progress.md:87` "stdio framing (M5e)" box `[ ]`). Reword the box (or annotate it) as e.g. `[x] raco test over all S2 modules passes (except stdio.rkt/M5e — orphaned-until-S6a per roadmap.md:118; stdio coverage + the framing box land with item 016)`. Do NOT flip it to a bare `[x]`. (`progress.md:89` demo box stays unchecked — owned by item 018.)
- [x] **Parity narrative** (`progress.md:336`): an item-017 sentence is appended recording which rows flipped to `partial` and the collection-wide restricted-load result.
- [x] **Roadmap §9** reconciled: grep `roadmap.md` for the six row names; flip any materialized status cells to `partial`. If §9 has **no materialized table** (it does not today — `progress.md:336` notes "no separate materialized table until the S9 closeout pass"; `roadmap.md:131` already states the requirement as an S2 acceptance line), record that fact in the progress narrative and make no roadmap edit beyond confirming the acceptance line stands.
- [x] **Item-017 progress marker** flipped 📋 → 🚧 → ✅ (add an S2 Deliverables line for the sweep, e.g. `✅ mcp/core/test/s2-portability-test.rkt — collection-wide S2 restricted-load portability sweep (item 017; stdio.rkt M5e isolated)`), and the per-module-tests deliverable line `progress.md:79` flipped to ✅ **with the same scope caveat** — e.g. `✅ Tests under validators/test/, util/test/, shared/test/ (except shared/test/stdio-test.rkt — lands with item 016/M5e)` — since `shared/test/stdio-test.rkt` does not exist until 016. Do NOT flip `:79` to a bare ✅ that reads as covering stdio.

---

## Implementation Steps

1. **Read the template once:** `mcp/core/test/main-test.rkt:43-114` (the walk + its application to the two S1 barrels) and `mcp/core/shared/test/uri-template-test.rkt:336-344` (the non-vacuity guard). These are the only inputs needed; do not re-read the module sources.
2. **Create `mcp/core/test/s2-portability-test.rkt`** (`#lang racket/base`):
   - Same `require`s as `main-test.rkt:13-16`.
   - Copy the `banned-module-paths` definition + the six walk helpers from `main-test.rkt:49-105` verbatim (OR factor — see Decisions; if factoring, the helper module must also be required by `main-test.rkt` WITHOUT changing its behaviour, and `main-test.rkt` must stay green).
   - `(define-runtime-path here ".")`; build the seven root paths via `(simplify-path (build-path here ".." <coll> <file>))` (mirror `main-test.rkt:108-109`).
   - For each root: in a fresh `(parameterize ([current-namespace (make-base-namespace)]) …)` (per `uri-template-test.rkt:336-344`), run ONE walk with **per-root base-dir `(path-only <root-path>)`** (NOT a shared `here`-derived dir — see Description "Per-root base-dir is load-bearing"), then assert on that one `visited` set BOTH (i) `check-portable!`'s banned-module checks AND (ii) the **teeth-proving non-vacuity guard**: S1-edge path presence (`#rx"core/main\\.rkt"`/`#rx"spec-2026"`) for the six S1-importing roots, `racket/string`/`racket/list` presence (`#rx"/(string|list)\\.rkt$"`) or `>= 50` for `tool-name-validation`. Do NOT use the bare `(> (set-count visited) 1)` guard — it is blind to a truncated walk.
   - A leading comment block: states the file is the S2 collection-wide Portability-NFR sweep, lists the seven non-I/O roots, and records the **stdio.rkt M5e carve-out** — stdio is excluded **as a root** (not exempt from portability; if any swept module ever imports it the sweep walks in and correctly flags stdio's banned imports against the importing module); the literal-paths-not-glob rationale; the 016-may-not-have-landed note.
3. **Run the sweeps** (see Testing Strategy) — including the **mandatory** `raco test mcp/core/test/` (runs both the new sweep and `main-test.rkt`, so a factor-path regression cannot ship green). Fix any banned-hit or vacuous-walk failure by inspecting the offending module's imports — but a failure here means a *module* regressed portability, which is out of this item's edit scope; surface it rather than editing the module silently.
4. **Teeth / mutation check (prove the sweep can FAIL).** Temporarily add `(require racket/tcp)` to ONE swept root (e.g. `util/schema.rkt`), run `raco test mcp/core/test/s2-portability-test.rkt`, and confirm it goes **RED** (the `racket/tcp` banned-module assertion fires for that root). Then **revert** the edit and confirm green again. Record the observed RED→revert→green in Decisions. (Without this, nothing proves the banned-module assertions actually bite.)
5. **Parity edits:**
   - `progress.md:88` box → `[x]`; `progress.md:82` box → `[x]` **with the stdio/M5e scope caveat** (see Acceptance Criteria — do not leave it reading as "all S2 modules including stdio").
   - Append the item-017 sentence to the parity-matrix-progression narrative at `progress.md:336` (follow the existing `**Item 0NN (Stage S2):** …` sentence pattern; name the six rows, state `partial`, cite `raco test mcp/core/test/s2-portability-test.rkt` green + the three-collection sweep; note stdio/M5e coverage is deferred to item 016/S6a).
   - Add the S2 Deliverables line for the sweep and flip `progress.md:79` to ✅ **with the same stdio-test caveat**.
   - `grep -n "validators/\*\|util/schema\|uriTemplate\|toolNameValidation\|metadataUtils\|auth" docs/aide/roadmap.md`; if a materialized §9 table cell exists, flip to `partial`; else record "no materialized table; acceptance line `roadmap.md:131` stands" in the progress narrative.
6. **Update progress marker** 📋 → 🚧 → ✅ for item 017 (see Completion Reminder).

---

## Testing Strategy

One-line strategy: a single `rackunit` restricted-namespace transitive-import walk (copied from the S1 template) over the seven non-I/O S2 module roots, asserting no banned subprocess/socket module is transitively reachable from any of them, each guarded against a vacuous (empty) walk; no external services, `raco test` only.

Exact commands (all MANDATORY, all must exit 0):

```
raco test mcp/core/validators/ mcp/core/util/ mcp/core/shared/
raco test mcp/core/test/
```

`raco test mcp/core/test/` runs BOTH the new `s2-portability-test.rkt` AND the existing `main-test.rkt`/`errors-test.rkt` — it is the natural superset (the new file lives in that dir). It is mandatory (not optional) specifically so that if the walk helper was **factored** out of `main-test.rkt`, any resulting regression in `main-test.rkt` is caught here rather than shipping green. (Running the file-only `raco test mcp/core/test/s2-portability-test.rkt` is fine for a fast inner loop, but the dir-wide run is the acceptance gate.) If the walk was factored, additionally confirm `main-test.rkt`'s check count is unchanged from before the factoring.

---

## Dependencies

- **Items 010–015** — the seven S2 modules the sweep walks must exist (they do; `progress.md:71-77` are ✅).
- **Item 016** (`mcp/core/shared/stdio.rkt`, M5e) — a *soft/ordering* dependency only: the sweep deliberately isolates stdio and never imports it, so item 017 can complete whether or not 016 has landed (see Edge Case (b)). No hard blocker.
- **S1 template** — `mcp/core/test/main-test.rkt:43-114` (the walk this item reuses) and `mcp/core/shared/test/uri-template-test.rkt:336-341` (the non-vacuity guard).
- **TS checkout** (`typescript-sdk/`) — **NOT needed** for this item (no wire/fixture parity work; pure portability + docs).

---

## Decisions & Trade-offs

*Recorded on delivery.*

- **Copy vs factor the walk helper → COPIED.** The `main-test.rkt:49-105` block (`banned-module-paths` + `resolve-mpi`/`dir-of`/`direct-imports`/`transitive-imports`/`banned-hit?`/`check-portable!`) was **copied verbatim** into `s2-portability-test.rkt` (the spec default). Rationale: zero risk to the green S1 suite; ~45 lines of duplication is the cheaper trade vs editing `main-test.rkt`. `main-test.rkt` was therefore NOT touched (its check count is unchanged; the dir-wide `raco test mcp/core/test/` run re-exercises it green). `check-portable!` is retained verbatim per the copy mandate; the actual sweep uses a small `check-root` wrapper that performs ONE walk per root and asserts BOTH the banned-module checks AND the teeth guard on the same `visited` set (the spec's "one walk, assert both" requirement, which the namespace-internal `check-portable!` cannot satisfy alone).
- **Per-root base-dir → CONFIRMED `(path-only <root>)` per root.** `check-root` derives `base-dir = (path-only root-path)` from its own `path` argument — never a single shared `here`-derived dir. The seven roots span three directories (`validators/`, `util/`, `shared/`); a shared base-dir would silently truncate roots in the "wrong" collection. Observed `visited` counts (non-truncation evidence): `provider` 228, `from-json-schema` 232, `util/schema` 233, `uri-template` 220, `metadata-utils` 220, `auth` 220 (all six with the S1 `core/main.rkt`/`spec-2026` edge present), `tool-name-validation` 82 (no S1 edge — base-collections-only, floored ≥50). All match spec expectations (≈220–233 / ≈82).
- **Teeth / mutation check → RED→reverted→green, CONFIRMED.** Injected `(require racket/tcp)` into `mcp/core/util/schema.rkt`; `raco test mcp/core/test/s2-portability-test.rkt` went RED (`1/63 test failures`: "util/schema.rkt transitively imports banned module racket/tcp" at the `check-false` for racket/tcp). Reverted the edit; `git diff mcp/core/` empty (module byte-identical); sweep green again (63 passed). Proves the banned-module assertions bite.
- **Roadmap §9 materialization → NO materialized table.** `grep` of `roadmap.md` for the six row names: they appear only in the `roadmap.md:131` S2 acceptance line ("Parity matrix rows for `validators/*`, `util/schema`, `uriTemplate`, `toolNameValidation`, `metadataUtils`, `auth` … marked `partial`") and the module bullets (`:113`, `:117`) — there is no status-cell parity table to edit. Per spec, recorded in the `progress.md:336` narrative that the acceptance line stands; no `roadmap.md` edit made.

---

## Completion Reminder

On delivery, in `docs/aide/progress.md`:
- Flip the item-017 status 📋 → 🚧 → ✅ (add the S2 Deliverables sweep line; flip `progress.md:79` to ✅ **with the "except shared/test/stdio-test.rkt — lands with item 016" caveat**, since that file does not exist until 016).
- Check `progress.md:88` (parity rows `partial`) and `progress.md:82` (raco over all S2 modules) — but `:82` MUST carry the **"except stdio.rkt/M5e — orphaned-until-S6a per `roadmap.md:118`; stdio coverage + the framing box land with item 016"** scope caveat so it does not contradict the still-📋 `:78`/`:87` stdio rows. Do NOT flip `:82`/`:79` to bare checks. Leave `progress.md:89` (demo) and `:87` (stdio framing) for items 018/016.
- Append the item-017 parity-matrix-progression sentence at `progress.md:336` (note stdio/M5e coverage deferred to 016/S6a).
- Reconcile `roadmap.md` §9 per Acceptance Criteria (flip cells if materialized; else note the acceptance line stands).

---

## Project-Specific note

Racket `raco test` item. Pure Portability-NFR test + docs/parity edits — **no external services, no module source changes, no TS checkout**. The whole deliverable is one new `rackunit` file (`mcp/core/test/s2-portability-test.rkt`) reusing the S1 portability walk, plus `progress.md`/`roadmap.md` parity-matrix edits. The single highest-risk mistake is letting `stdio.rkt` (M5e) into the swept roots — keep the roots a literal seven-element list and never glob `shared/`.
