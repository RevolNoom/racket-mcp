# Reviewer feedback — Item 007 (iteration-002): Error DECODE path

**Role:** Reviewer (testing strategy, prerequisites, edge cases).
**Spec:** `docs/aide/versions/speckit.aide.create-item/007-errors-decode/iteration-002/item.md`
**Verdict:** 9/10 — APPROVE. `needs_revision: false`. All iteration-001 blockers (C1, C2, C3)
and all suggested polish (S1/S2/S3/S5) are genuinely resolved; no new issues. Remaining nits are
cosmetic.

---

## Resolution verification (each iteration-001 issue re-checked against source)

### C1 (compile blocker) — RESOLVED.
§Decisions "`json-object?` helper (SETTLED — LOCAL definition, no import)" (item.md:776-795) now
MANDATES a local private helper `(define (json-object? d) (and (hash? d) (hash-eq? d) (immutable? d)))`
and EXPLICITLY warns that `(only-in "types/spec-2025-11-25.rkt" json-object?)` raises a
compile-time "not exported" error because the predicate sits under the "Internal wire helpers
(NOT provided)" comment. Cross-checked all the places that previously mis-recommended the import:
- Implementation step 4 (item.md:290-297): now says "define a LOCAL private `json-object?`",
  "Do NOT write `(only-in …)`", "require list is therefore UNCHANGED."
- Dependencies → Item 003 (item.md:475-478): "the data-gate does NOT import `json-object?` … 007
  uses a LOCAL byte-identical helper instead."
- Testing Prerequisites table (item.md:546): "(NOT `json-object?` — that is a local helper, not
  imported)."
- Project-specific adaptations (item.md:519-523): "LOCAL `json-object?` helper … because that
  predicate is not exported from M1."

The "parity hazard" framing is corrected (item.md:789): "**NOT a parity hazard** — it is the same
logic, not a divergent re-interpretation." I verified the byte-identical claim against source:
`spec-2025-11-25.rkt:51-52` is `(and (hash? v) (immutable? v) (hash-eq? v))`; the spec's helper is
`(and (hash? d) (hash-eq? d) (immutable? d))` — identical conjuncts (the two predicates commute,
so reorder is immaterial). Option (a) (re-export from M1) is correctly retained as out-of-scope
unless the lead authorizes an M1 edit. Clean fix, fully consistent across the document.

### C2 (data-gate vacuous on `-32042`) — RESOLVED.
Test 6c `dun2` (item.md:369-375): `(jsonrpc-error->exn (jsonrpc-error URL-ELICITATION-REQUIRED "x"
(hasheq 'foo 1)))` → asserts `(= (mcp-error-code dun2) URL-ELICITATION-REQUIRED)`,
`(protocol-error? dun2)`, `(equal? (mcp-error-data dun2) (hasheq 'foo 1))`, no throw — pinning the
`'elicitations`-key conjunct (mirrors the `if (errorData.elicitations)` miss at errors.ts:25). The
acceptance criterion (item.md:213-214) and Expected Outcomes (item.md:649-651) both now demand
"a test that a code-only implementation would FAIL." Non-vacuous. Resolved.

### C3 (data-gate vacuous on `-32004`'s second conjunct) — RESOLVED.
Test 6c `dvn` (item.md:379-385): valid `'supported '("2025-11-25")` + `'requested 7` (non-string),
PLUS a `'requested`-MISSING variant `(hasheq 'supported '("2025-11-25"))` → both decode to a
`-32004` generic protocol error, no throw. This pins the `'requested`-is-a-string conjunct that the
old single broken-`'supported` test left untested. Resolved.

### S2/S3 (round-trip auth case + asserted subtype erasure) — RESOLVED.
6d (item.md:388-403) now includes `(make-auth-error MISSING-REQUIRED-CLIENT-CAPABILITY "x"
(hasheq 'capability "roots"))` in the round-trip list AND, for both the base
(`make-mcp-error RESOURCE-NOT-FOUND`) and auth cases, asserts `(check-true (protocol-error? r))`
+ `(check-false (auth-error? r))` — so the base→protocol and auth→protocol subtype erasure is
EXERCISED, not merely documented. The prose no longer over-claims relative to the test. Resolved.

### S1 (special-code reverse fixpoint) — RESOLVED.
6d (item.md:404-413) spells out `(check-equal? (exn->jsonrpc-error (jsonrpc-error->exn j)) j)` for
a SPECIALIZED-branch `j` (`-32042`+elicitations), a `-32004`+good-data `j`, and a generic-code `j`,
with the correct rationale that the specialized fixpoint is the only proof the specialized path
carries data verbatim through a full wire→exn→wire trip. Resolved.

### S5 (no synthesized message on the specialized branch) — RESOLVED.
6a `dem` (item.md:343-351): `-32042` with `message = ""` + good data → `(equal? (exn-message dem)
"")`, with a comment that TS's subclass default messages (errors.ts:47/68) are bypassed because
`fromError` threads the received message. Acceptance criterion (item.md:243-247) added. Resolved.

---

## Independent re-scan for NEW issues — none blocking

- **Anti-vacuous-pass:** the suite now pins BOTH gate conjuncts for each special code (C2 the
  `'elicitations` key, C3 the `'requested` string) — a code-only implementation fails. The
  drift-detection step (flip an assertion → expect FAILURE) is retained. The data-gate is now
  genuinely tested, not decorative.
- **Coverage counts** (Expected Outcomes, item.md:622-629): special-code ≥5, gate fall-through ≥4,
  round-trip ≥5 values + base/auth subtype + 3 reverse-fixpoints, etc., totaling ≥~32 new checks.
  Realistic and matched by the Part-6 spec.
- **Prerequisites:** `raco`-broken workaround, `racket <file>` + SCAN-for-FAILURE, do-not-disable-
  sandbox, repo-root cwd, `(struct-out jsonrpc-error)` supplying the test's needed constructor +
  `jsonrpc-error-message` — all correct (verified `(struct-out jsonrpc-error)` is exported at
  spec-2025-11-25.rkt:119).
- **Seam discipline:** additive build at the DECODE anchor, append-only second `provide`, no edit
  to 006's first block, require-list UNCHANGED (gate adds no import). Façade-vs-exn reconciliation
  (no M2→types.rkt dependency) unchanged and sound. Portability NFR holds trivially.

## Cosmetic nits (NON-blocking — implementer's discretion)

1. The Manual Validation Checklist "Additive-only verified" line (item.md:600) and "Portability
   verified" (item.md:602) still mention "(and possibly one `only-in` require line)" / generic
   phrasing. With C1 settled to the import-free local helper, the ONLY possible new require line is
   the OPTIONAL `json->jsonrpc-error` wrapper (which is recommended OMITted). Harmless but could be
   tightened to "no new require line unless the optional wrapper is chosen." Not worth a revision.
2. `unsupported-version-data?` should test `'requested` with `string?` AND `'supported` with
   `(and (list? …) (andmap string? …))`? The spec mirrors errors.ts exactly (`Array.isArray` only,
   no element-type check — errors.ts:32), so a `'supported` list of non-strings still specializes.
   That is FAITHFUL to TS; no change wanted. Noting only so it is not mistaken for a gap.

## Bottom line

Iteration-002 fixes the one real blocker (C1, the non-existent import) with a correct,
compile-safe, import-free local helper and closes both vacuous-gate holes (C2/C3) plus all polish
(S1/S2/S3/S5). The data-gate is now non-vacuously tested, the subtype-erasure asymmetry is
asserted, and the parity claims all check out against source. Approve — 9/10.
