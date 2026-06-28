# Reviewer feedback — Item 017 (S2 portability sweep + parity-matrix touch)

Reviewed: `docs/aide/items/017-s2-portability-and-parity-touch.md` (127 lines, read in full).
Lens: edge-case / "will a worker shipping from this spec ship a bug?"

I empirically ran the proposed walk against all seven roots and ran the documented
base-dir truncation hazard as a live experiment (results inline below). Net: the spec
is detailed and its line targets are all correct, but it has **two substantive gaps**
that would let a worker ship a green-but-vacuous test and a self-contradicting
`progress.md`. Both fixes are cheap.

---

## Focus 1 — Does the test actually FAIL on a banned module and PASS only when clean?

### 1(a) The non-vacuity guard `(> (set-count visited) 1)` is too weak — PROVEN. (CRITICAL)

I ran the verbatim walk against all seven roots. Visited-set sizes:

```
validators/provider.rkt          228
validators/from-json-schema.rkt  232
util/schema.rkt                  233
shared/uri-template.rkt          220
shared/tool-name-validation.rkt   82   <- smallest (base-collections-only, item 014)
shared/metadata-utils.rkt        220
shared/auth.rkt                  220
```

All seven are portability-clean (zero banned hits) — good, the happy path holds and
even the smallest set (82) clears `> 1` by a mile. So `> 1` is *not* the right floor:
the real floor is ~80 (racket/base's own closure). That mismatch is the problem.

The guard's stated job is to catch a vacuous/broken walk. The documented failure mode
is the base-dir-threading truncation hazard (`main-test.rkt:53-59`): a wrong base-dir
makes a relatively-required module resolve against the wrong directory, `module->imports`
raises, the `with-handlers` swallows it, and the walk **silently truncates one level
early** for every relatively-required module. I simulated exactly this for
`metadata-utils.rkt` (which imports *only* `../main.rkt` + `racket/base`) by passing a
wrong base-dir:

```
metadata-utils BROKEN-base-dir: visited=79   (>1 guard passes? #t)
  S1 subtree (core/main / spec-2026) reached? #f
```

So a walk that **never reaches the S1 subtree at all** still reports `visited=79` and
**passes `> 1` green**. For `metadata-utils.rkt` and `auth.rkt` the S1 edge is the
*entire* thing the sweep is supposed to prove beyond the leaf's own (trivially clean)
collection imports — and the guard cannot tell that edge was skipped.

This is amplified by an item-017-specific factor the per-module tests never faced: the
seven roots live in **three different directories** (`validators/`, `util/`, `shared/`).
The S1 template and every per-module walk used a *single* dir, so `(path-only ut-path)`
was obviously right. Here, an implementer who factors a `(check-root path)` helper but
threads a single `here`-derived base-dir (instead of `(path-only path)` per root) gets
the truncation for roots in the "wrong" collection — and the `> 1` guard waves it
through. The spec's step-2 instruction (line 69-70) says "mirror `main-test.rkt:108-109`"
and "reuse the `uri-template-test.rkt:336-344` shape" but never states the load-bearing
rule explicitly: **the base-dir for each root MUST be `(path-only <that-root>)`, computed
per root, never shared.**

**Fixes (do both):**
1. Mandate in the spec + acceptance criteria that each root's base-dir is `(path-only
   <root-path>)`, computed per root.
2. Replace/augment the `> 1` guard with one that proves the walk had teeth for that root:
   - For the six S1-importing roots: assert `visited` contains a resolved path matching
     the S1 barrel / a known S1 module (e.g. `#rx"core/main\\.rkt"` or `#rx"spec-2026"`),
     i.e. the relative edge actually resolved. A bare count threshold (`>= 200`) is
     brittle; a path-presence assertion is the honest non-vacuity proof.
   - For `tool-name-validation.rkt` (no S1 edge): assert `visited` contains
     `racket/string` or `racket/list` resolved (its only declared imports), or floor at
     `>= 50`. `> 1` is meaningless here.

### 1(b) banned-hit regexp — no false-positive/negative found.

`(regexp (format "/~a(\\.rkt)?$" banned-sym))` anchors on a leading `/`, so e.g.
`/mynet/url` does not match `net/url`, and `/racket/port.rkt` matches `racket/port`.
Verified against the live closures — no spurious or missed hits. No action.

### 1(c) Near-miss risk (racket/port for bytes ops) — checked empirically, NONE. (de-risks the spec)

The seven roots' actual imports: `racket/generic`, `racket/list`, `racket/string`,
`racket/contract`, `json`, plus relative `../main.rkt` / `provider.rkt` /
`from-json-schema.rkt`. None of these — including `racket/contract` (large) and `json`
— transitively pulls in any banned module (0 hits across all 228-233-module closures).
The "racket/port for bytes ops" worry does not materialize: `uri-template.rkt`'s
hand-rolled UTF-8 encoding uses `string->bytes/utf-8` (racket/base), not `racket/port`.
The acceptance criterion "`raco test …s2-portability-test.rkt` passes" is satisfiable
**today** for all seven roots. **The spec should add a one-line teeth check** (temporarily
add `(require racket/tcp)` to one root, confirm the sweep goes RED, revert) so the
implementer proves the test can fail — nothing in the current spec forces that, and with
the weak `> 1` guard there is otherwise no evidence the assertions bite.

### 1 — Are the seven roots the right set? Yes.

The seven match progress.md:71-77 (items 010-015) and exclude stdio (016). Correct.

---

## Focus 2 — stdio.rkt (M5e) isolation: airtight as a ROOT, with one nuance to state.

Literal enumeration of seven roots + never globbing `shared/` is the right safeguard and
the Edge-Case (a)/(b)/(c) reasoning is thorough and correct. `stdio.rkt` does not exist
today (progress.md:78 📋); literal paths keep it out whether or not 016 lands first. No
path by which it sneaks in **as a root**.

One nuance the spec slightly over-states: the carve-out makes stdio not a *root* — it does
**not** make stdio invisible to the walk. If a future S2 module ever transitively imports
`stdio.rkt`, the sweep would walk into it and (if stdio uses `racket/port`, which its
byte-stream role makes likely) **correctly fail**. That is desirable behaviour, not a
flaw — but the in-file comment the spec mandates (line 52, 71) should say "excluded **as
a root**; if any swept module ever imports it, that is a portability regression of the
*importing* module," not "the walk isolates stdio" full-stop. Minor wording; prevents a
future maintainer mis-reading the carve-out as "stdio is exempt from portability."

---

## Focus 3 — Copy-vs-factor: default is safe, but the factor-path regression net has a hole. (MEDIUM)

Defaulting to **copy** (Decisions, line 110) is the right call — zero risk to
`main-test.rkt`. The scope guard (line 41) correctly says that if factored, `main-test.rkt`
"MUST stay green and behaviour-identical."

The hole: the **mandatory** test commands (Testing Strategy, lines 88-91) are
`raco test mcp/core/validators/ mcp/core/util/ mcp/core/shared/` and `raco test
mcp/core/test/s2-portability-test.rkt`. Neither runs `main-test.rkt`. The only command
that does — `raco test mcp/core/test/` — is marked **"Optionally"** (line 93). So if an
implementer takes the factor path and skips the optional run, a regression in
`main-test.rkt` (e.g. the factored helper subtly changed behaviour) **ships green**. The
new file lives in the *same* `mcp/core/test/` dir, so `raco test mcp/core/test/` is the
natural superset command anyway.

**Fix:** make `raco test mcp/core/test/` a **mandatory** acceptance command (it runs both
`main-test.rkt` and the new sweep), replacing or supplementing the file-only command on
line 90. At minimum, add an acceptance box: "if the walk was factored: `raco test
mcp/core/test/main-test.rkt` is green and its check count is unchanged."

---

## Focus 4 — Parity-matrix edits: line targets all correct; one acceptance box over-claims.

Line targets — all verified exact:
- `progress.md:88` = `- [ ] Parity rows validators/*, util/schema, uriTemplate, toolNameValidation, metadataUtils, auth marked partial` ✓
- `progress.md:82` = `- [ ] raco test over all S2 modules passes` ✓
- `progress.md:79` = `- 📋 Tests under validators/test/, util/test/, shared/test/` ✓
- `progress.md:336` = the "Parity matrix progression" narrative paragraph ✓
- `roadmap.md:131` = `- Parity matrix rows for validators/*, util/schema, uriTemplate, toolNameValidation, metadataUtils, auth (shared) marked partial` ✓
- `roadmap.md:23` = the "Parity discipline (applies to every stage)" line ✓

"No materialized §9 table" hedge — **correct.** Grepped `roadmap.md`: every "§9" /
"parity matrix" reference is either the per-stage acceptance line or a pointer to
*vision.md* §9 Success Criteria. There is no materialized parity table in `roadmap.md` to
edit; `roadmap.md:131` is the S2 acceptance line and stands. The spec's instruction
(line 58, 77) to grep and record this is right and unambiguous.

### The over-claim: `progress.md:82` "raco test over **all S2 modules** passes" vs unbuilt stdio. (CRITICAL)

The spec flips `progress.md:82` → `[x]` (line 56) justified by the three-collection sweep
being green. But that sweep with `stdio.rkt` **absent** (item 016 unbuilt, progress.md:78
📋) does not test stdio — an S2 deliverable. Flipping `82` to `[x]` therefore creates an
**internal contradiction inside progress.md**:
- `82` `[x]` "raco test over **all** S2 modules passes"
- `87` `[ ]` "stdio framing (M5e) round-trips … standalone"   ← left unchecked (016's job)
- `78` `📋` `stdio.rkt (M5e)` deliverable                      ← left not-started

A reader of the source-of-truth progress doc sees "all S2 modules pass" checked while the
stdio module and its framing box are visibly incomplete. The same applies to
`progress.md:79` ("Tests under … `shared/test/`") which the spec also flips to ✅ (line 59,
76) even though `shared/test/stdio-test.rkt` will not exist until 016.

Note roadmap.md:118 *does* permit deferring stdio to S6a ("may move M5e beside M7 … without
affecting any other S2 deliverable"), so the *intent* (S2's non-I/O surface is complete) is
defensible — but the **wording** of the flipped boxes must reflect that scope, or
progress.md ships self-contradicting checkboxes.

**Fix:** when flipping `82` and `79`, the spec must mandate an explicit scope caveat, e.g.
"raco test over all S2 modules **except `stdio.rkt`/M5e (orphaned-until-S6a per
roadmap.md:118; coverage + the framing box land with item 016)**." Either reword the boxes
in place or add the caveat to the appended narrative so `82`/`79` do not read as
contradicting the still-📋 `78`/`87`. Do not flip them silently.

---

## Focus 5 — Acceptance-criteria completeness.

Most criteria are objectively checkable (file exists, raco exit 0, boxes flipped, comment
present) — good. Two gaps, both already covered above:
- The non-vacuity criterion (line 51/54) is checkable but, as proven in 1(a), is satisfied
  by a broken-but-truncated walk — so "objectively checkable" ≠ "meaningful." Strengthen
  per 1(a).
- No criterion forces a **teeth / mutation check** (prove the sweep goes RED when a banned
  module IS reachable). Add one per 1(c). Without it, a worker can satisfy every box while
  the assertions never actually bite.

Everything else (requires list matches `main-test.rkt:13-16`; `racket/format` not needed
since `format` is racket/base; runtime-path construction) is correct and sufficient.

---

## Summary of required changes

1. (CRITICAL, focus 1a) Strengthen the per-root non-vacuity guard: assert an S1-edge path
   is present in `visited` for the six S1-importing roots (and a real collection import for
   `tool-name-validation`), and explicitly mandate per-root base-dir `(path-only <root>)`.
   `> 1` is provably blind to the documented truncation hazard.
2. (CRITICAL, focus 4) Stop `progress.md:82`/`:79` from contradicting the still-📋 stdio
   rows (`78`/`87`): mandate an explicit "except M5e/stdio, deferred to 016" scope caveat.
3. (MEDIUM, focus 3) Make `raco test mcp/core/test/` mandatory (not "Optionally") so a
   factor-path regression in `main-test.rkt` cannot ship green.
4. (SUGGESTED, focus 1c/5) Add a teeth check: temporarily add `(require racket/tcp)` to one
   root, confirm RED, revert.
5. (SUGGESTED, focus 2) Reword the stdio carve-out comment: excluded **as a root**; a future
   importing module would (correctly) surface stdio's banned imports.

Empirical note for the implementer: a correct verbatim walk yields visited counts
220-233 (S1 importers) and 82 (`tool-name-validation`); a truncated walk yields ~79.
The gap between "correct" and "broken" is invisible to `> 1` but obvious to an S1-edge
path assertion.
