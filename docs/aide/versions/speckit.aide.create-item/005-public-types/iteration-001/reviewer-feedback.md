# Reviewer Feedback — Item 005: Public types + normalized-superset façade (N1)

**Reviewer:** reviewer (test-edge-case-reviewer, AIDE create-item)
**Date:** 2026-06-19
**Spec:** `docs/aide/versions/speckit.aide.create-item/005-public-types/iteration-001/item.md`
**Verdict:** `needs_revision = true` — overall **7/10**. Strong, implementable spec with an
excellent N1 mental model and a genuinely good test plan. But the §4 façade inventory — which the
spec itself calls "THE IMPLEMENTATION CONTRACT" — contains **field-level inaccuracies that
contradict the two delivered modules it unions**, and the test strategy leaves two cross-revision
present/absent pairs unbuildable from existing fixtures. These would make an implementer build the
wrong façade for the sampling/elicitation params and discover the gaps only at test time (or worse,
write a vacuously-passing test). All findings were cross-checked against the actual delivered
`spec-2025-11-25.rkt` and `spec-2026-07-28.rkt` struct definitions.

---

## What is well-covered (keep)

- **The core N1 testable claim is correctly specified.** Part 1 (both revisions → SAME façade
  struct) with the present/absent matrix, Part 2 (lossless-on-home), Part 3 (cross-revision
  refusal), and Part 6 (anti-vacuous count assertion) together are a strong, non-vacuous suite. The
  insistence on `(facade-X? f25)` AND `(facade-X? f26)` being the SAME predicate is exactly right.
- **The `absent` sentinel discipline is accurate.** Verified: 003 defines
  `(define absent (string->uninterned-symbol "absent"))` and provides `absent`/`absent?`/`present?`;
  004 imports them via `(only-in "spec-2025-11-25.rkt" absent absent? present?)`. The spec's
  requirement to import the ONE `eq?` binding and the `absent` identity test (Part 6 / edge cases)
  is correct and load-bearing.
- **The `presence-vs-revision-capability` ambiguity (Part 5 + Decisions) is the right call** and is
  explicitly flagged so it is not read as a bug. `result-type` being optional-even-in-2026
  (confirmed: `result` struct is `(meta result-type rest)`; absent ⇒ "complete") makes this real.
- **The `ListRootsResult` bare-interface trap is correctly characterized.** Verified against code:
  2025 `(struct list-roots-result (roots meta rest))`, 2026 `(struct list-roots-result (roots))`.
  The Group-3 table (meta = 2025-only, denormalize-to-2026 emits exactly `{roots}`) is accurate,
  and the per-root vs result-level `meta` distinction is correctly drawn.
- **The `Tool.execution` 2025-only classification is correct** (2025 tool has the field, 2026 does
  not) — see the field-NAME nit below, which is cosmetic, not a logic error.
- **The `raco`-broken / `racket <file>` workaround is documented accurately** and matches how
  003/004 tests are actually run.

---

## Missing / incorrect coverage (CRITICAL — would cause wrong build or vacuous test)

### C1. §4 Group 4 mis-models the sampling & elicitation params: `meta` is NOT shared there

The Group-4 table (lines 258–267) places `facade-elicit-request-form-params`/`-url-params` and
`facade-create-message-request-params` under "request params with the `_meta` envelope" and lists
their `meta`/`request-meta` field as **shared**, with only `task` as 2025-only. **This contradicts
the delivered modules.** These three are server→client ("InputRequest") primitives that carry NO
`_meta` envelope in 2026:

| Primitive | 2025 struct fields (verified) | 2026 struct fields (verified) |
|---|---|---|
| `elicit-request-form-params` | `(mode message requested-schema task meta)` | `(mode message requested-schema)` |
| `elicit-request-url-params` | `(mode message elicitation-id url task meta)` | `(mode message elicitation-id url)` |
| `create-message-request-params` | `… tool-choice task meta` | `… tool-choice meta` |

So:
- For the two **elicit** params, `meta` is **2025-only**, not shared (2026 has neither `task` nor
  `meta`). The façade must set BOTH `task` and `meta` to `absent` when normalizing from 2026, and
  `denormalize-to-2026` must refuse a non-absent `meta` as well as a non-absent `task`.
- For `create-message-request-params`, `meta` IS present in both (so shared) but it is a plain
  `(opt/c json-object?)` in BOTH revisions — it is NOT the `request-meta` envelope. Lumping it into
  the `facade-request-meta` superset (the implication of the Group-4 heading) is wrong; only the
  CLIENT request params (`call-tool`, `read-resource`, `get-prompt`, `complete`, paginated list
  requests) carry `request-meta?` in 2026 (verified: `call-tool-request-params/c` 2026 ends in
  `… request-meta?`).

**Fix:** Move the three server→client params (`create-message`, `elicit-form`, `elicit-url`) OUT of
the `_meta`-envelope Group 4. State explicitly that their `meta` is a plain optional JSON object
(2025-only for elicit; shared-plain for create-message), and that the `request-meta` envelope
applies ONLY to the client request params. Otherwise the implementer will give elicit params a
phantom `request-meta` field and the round-trip will emit phantom keys.

### C2. The `facade-request-meta` field-class table conflates two different `meta` shapes

Group 4's `facade-request-meta` row (line 260) is itself correct for the CLIENT request params, but
because C1 mis-routes the server→client params through the same group, the spec implies one
`facade-request-meta` superset covers every params `meta`. It does not. There are effectively TWO
`meta` shapes in play: (a) the 2026 `request-meta` envelope struct (client requests), and (b) a
plain `(opt/c json-object?)` (2025 everywhere; 2026 server→client + notification params). The façade
must not normalize a 2025 flat `_meta` map for `call-tool` into a `facade-request-meta` whose `rest`
holds the flat keys AND simultaneously treat a 2026 server→client plain `meta` as a `request-meta`.
**Fix:** the spec should state, per-primitive, whether the façade `meta` field is a
`facade-request-meta` (client requests only) or a plain optional object (everything else), so the
implementer does not build one over-broad envelope.

### C3. The cross-revision present/absent test cannot be run for `list-roots-result` or
`create-message` as written — no fixtures exist

Part 1 names `tools/call` request, `tools/list` result, and a content block as the minimum pairs,
and those fixtures DO exist in both revisions (`tools-call-request.json` + `2026-tools-call-request.json`,
`list-tools-result.json` + `2026-list-tools-result.json`, content-blocks pair) — good. BUT the
acceptance criteria (lines 383–385) and Part 1 step 4 ALSO require asserting the 2025-only fields
`execution` (on `tool`) and result-level `meta` (on `list-roots-result`) are absent on the 2026
façade. **There is no `list-roots-result` fixture in EITHER revision, and no 2026 fixture pairing
for it** (verified: `ls fixtures/` shows no `*list-roots*`). Same for `create-message`. The spec's
step 10 hand-waves this ("add a couple of cross-revision pairs if a primitive lacks both") but never
PINS which primitives lack fixtures, so an implementer can satisfy the letter of Part 1 with only
the three pairs that happen to exist and silently skip the `list-roots`/`execution`/`task` absence
assertions — which are the EXACT 2025-only-field assertions the queue's testability clause demands.
**Fix:** explicitly enumerate the fixtures the implementer MUST hand-author for the present/absent
matrix: at minimum a 2025 `list-roots-result.json` (with result-level `_meta`) + a 2026
`2026-list-roots-result.json` (bare `{roots}`); a 2025 `tools-call-request.json` already carries
`task`? — verify it does, else add one; and confirm the existing `tool` inside `2026-list-tools-result`
vs a 2025 tool fixture lets you assert `execution` present/absent. Make the 2025-only-field absence
assertions a HARD requirement with named fixtures, not "if lacking."

### C4. Round-trip losslessness (Part 2) is under-specified for the `rest` field on results

Every result struct in BOTH revisions carries a `rest` field (verified: 2025
`list-tools-result (tools next-cursor meta rest)`, 2026
`(tools next-cursor ttl-ms cache-scope meta result-type rest)`). The façade Group-2 table lists
`rest` as a shared field. But `rest` holds *arbitrary leftover keys that differ by revision* (e.g. a
2026 result could have unknown keys a 2025 result never would). The N1 wire-parity rule says
denormalize must refuse to emit a field absent from the target revision — does that apply to opaque
`rest` keys? The spec never says. If a façade carries a `rest` populated from a 2026 message and you
denormalize-to-2025, do the leftover keys pass through (loose results preserve unknowns in BOTH revs,
so arguably yes) or is that a parity violation? Part 2 asserts lossless-on-HOME revision only, which
sidesteps it, but Part 3's refusal tests never address `rest`. **Fix:** state the rule for `rest`
explicitly — recommended: `rest` is shared and passes through on denormalize to either revision (it
is not a revision-gated *named* field; loose-result semantics are identical in both revisions), and
add one round-trip assertion that a result with a non-empty `rest` survives normalize→denormalize on
its home revision (it will otherwise be the easiest field to silently drop, exactly the 003
"phantom-keys / dropped-_meta" failure mode).

### C5. `ElicitResult` open question is RESOLVED in code — spec should stop hedging

Line 218 leaves open "confirm if ElicitResult carries `result-type`." Verified: 2026
`(struct elicit-result (action content meta result-type rest))` — it DOES carry `result-type` (and
`meta` and `rest`); 2025 `(struct elicit-result (action content meta rest))` does not have
`result-type`. So `result-type` is 2026-only on `facade-elicit-result`, consistent with Group 2.
**Fix:** remove the open question; state `result-type` is 2026-only on `facade-elicit-result`. (Note
this also makes `meta`/`rest` shared on elicit-RESULT — distinct from elicit-PARAMS in C1, an easy
confusion to seed if both stay vague.)

---

## Missing / suggested coverage (lower priority)

### S1. No negative test that the façade `meta`-field type is right per-primitive
Given C1/C2, add a test asserting a normalized 2026 `call-tool` façade's `request-meta` field
satisfies `facade-request-meta?` (envelope) while a normalized 2026 `create-message` façade's `meta`
is a plain object / absent (NOT a `facade-request-meta`). This catches the most likely C1/C2
mis-build directly.

### S2. Empty-`rest` vs absent-`rest` distinction untested
A result with no leftover keys: is `rest` an empty `hasheq` or `absent`? The two revisions both use
an empty `hasheq` (003/004 helpers `hash-merge`/`split`). The façade should not introduce `absent`
here. Add an assertion that an all-known-keys result round-trips without a phantom empty `_meta` or
spurious key (reuse 003's absent-vs-null regression). Spec's edge-case list mentions "no phantom
keys" but only for denormalize-to-home; assert it on the façade struct's `rest` too.

### S3. `input-responses`/`request-state` present/absent not pinned to a fixture
Group 4 lists `input-responses`, `request-state` as 2026-only on read/get-prompt/tools-call params
(verified: 2026 `call-tool-request-params (name arguments input-responses request-state meta)`; 2025
`(name arguments task meta)`). Part 1 mentions `input-responses` in the RC-only list but no fixture
is named. `2026-input-responses.json` exists — confirm it is a `tools/call` (or read/get-prompt)
PARAMS fixture usable for the façade present-test, and name it.

### S4. Method→façade dispatch: revision-collision cases untested
`tools/call`, `roots/list`, `elicitation/create`, `sampling/createMessage`, `completion/complete`
exist in BOTH revisions but map to DIFFERENT params/result shapes (2026 adds request-meta /
input-responses). The dispatch table (Group 8) "from a method string to the façade struct's
`json->`/`normalize` pair" must therefore be revision-PARAMETERIZED for these — a bare
`hash[method] → parser` cannot work because one method has two parsers. Part 4 tests
`"initialize"`/`"server/discover"` (single-revision, easy) but never a both-revisions method through
the dispatch. **Add** a dispatch test for `"tools/call"` that resolves to the 2025 parser when
revision=2025 and the 2026 parser when revision=2026. The spec's Decision "model as
`(hash method . (cons revision-aware-parser normalizer))`" hints at this but the test plan does not
exercise it.

### S5. Group-0 aliasing-vs-copy open question left to implementer with no test guard
The spec recommends fresh façade structs + copy (boundary cleanliness) but accepts aliasing. Either
is fine, but if the implementer aliases a 003 struct, the `facade-X?` predicate would be 003's
predicate, and a 2026-normalized value (built from 004's struct) would FAIL `facade-X?` — breaking
the SAME-façade core claim for any Group-0 primitive that gets aliased to ONE revision. **Fix:**
state that aliasing is only acceptable if BOTH revisions' values are converted into the SAME chosen
struct type (i.e. you still need normalizers that rebuild into the aliased struct); pure aliasing of
003's struct without converting 004's values would fail Part 1. This is a real trap given the
shape-identical Group-0 primitives.

---

## Concrete test-case proposals (input → expected)

1. **C1 elicit params absence:** normalize a 2026 `elicit-request-form-params` →
   `(absent? (facade-elicit-request-form-params-task f))` is `#t` AND
   `(absent? (facade-elicit-request-form-params-meta f))` is `#t`. Normalize the 2025 equivalent
   (with `task` and `_meta` set) → both `present?`. `denormalize-...-to-2026` of the 2025 façade
   (task/meta present) → raises.
2. **C2 meta-type discrimination:** normalize 2026 `tools/call` →
   `(facade-request-meta? (facade-call-tool-request-params-meta f))` is `#t`. Normalize 2026
   `create-message` → its `meta` is `absent` or a plain `json-object?`, NOT `facade-request-meta?`.
3. **C3 list-roots present/absent (requires new fixtures):** with hand-authored
   `list-roots-result.json` (has `_meta`) and `2026-list-roots-result.json` (bare `{roots}`):
   `(present? (facade-list-roots-result-meta f25))` = `#t`;
   `(absent? (facade-list-roots-result-meta f26))` = `#t`; both satisfy `facade-list-roots-result?`;
   `(facade-list-roots-result-roots f25)` equal? `(...-roots f26)` when fixtures share roots.
4. **C3 tool execution absence:** a façade `tool` normalized from 2026 →
   `(absent? (facade-tool-execution t))` = `#t`; from 2025 (with `exec` set) → `present?`;
   `denormalize-tool-to-2026` of the 2025 façade → raises.
5. **C4 rest passthrough:** a 2026 `list-tools-result` fixture with an unknown extra top-level key →
   after `normalize-from-2026` → `denormalize-to-2026` → `->json`, the unknown key is still present
   (`jsexpr=?` to fixture). Same for a 2025 result on its home revision.
6. **C5 same-struct under aliasing (if chosen):** assert `(eq? (facade-text-content? f25-block)
   #t)` AND `(facade-text-content? f26-block)` resolve to the SAME predicate, regardless of which
   revision built the input.
7. **S4 dispatch revision-collision:**
   `((dispatch-for "tools/call" 2025) jsexpr-2025)` → a 2025-shaped façade with `task` settable;
   `((dispatch-for "tools/call" 2026) jsexpr-2026)` → a 2026-shaped façade with `request-meta`.
8. **`result-type` open enum (already in spec edge cases — keep):** a 2026 result with
   `resultType:"input_required"` and one with a custom string both survive
   normalize→denormalize-to-2026.

---

## Minor / polish (non-blocking)

- **Field-name nit:** §4 Group 1 calls the field `execution`; the delivered 2025 struct field is
  named `exec` (`(struct tool (… exec output-schema …))`). The façade may name its field `execution`
  for clarity, but the normalizer reads `(r25:tool-exec v)`. State the source accessor is `tool-exec`
  so the implementer does not grep for a non-existent `tool-execution` accessor.
- **Count estimate:** "~75–85 façade structs" is fine as a range; Part 6 records the exact number,
  which is the right anti-drift mechanism. No change needed.
- **Group 6 line 302** has a stray fragment ("`facade-resources-updated`... (shared — listed in
  Group 5; NOT 2025-only), `facade-roots-list-changed-notification`, `facade-tasks-status-notification`")
  that mixes a shared primitive into the 2025-only list mid-sentence; tidy so `roots/list_changed`
  and `tasks/status` notifications (genuinely 2025-only — verified gone in 2026) are clearly listed
  and `resources/updated` is not.

---

## Bottom line

The spec's architecture, N1 reasoning, and test *philosophy* are excellent and the core testable
claim is correctly framed. It fails on **fidelity of the build contract (§4)** for the
sampling/elicitation params (C1/C2 — directly contradicted by the delivered code), on **pinning the
fixtures** the present/absent matrix requires (C3), and on **two under-specified rules** (`rest`
parity C4, dispatch revision-collision S4). Fix C1–C5 and the implementer can build the right thing
without guessing; leave them and the implementer will either build a wrong façade for three params
primitives or write a present/absent test that silently skips the 2025-only-field assertions.
