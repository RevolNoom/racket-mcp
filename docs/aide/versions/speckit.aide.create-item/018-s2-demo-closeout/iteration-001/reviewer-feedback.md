# Reviewer feedback — Item 018: Stage S2 Demo + Closeout (iteration 001)

**Overall:** 7/10. The demo design is sound and **all five hardcoded API shapes
verified accurate against source** — a worker following the requires + arm code
verbatim ships a demo that runs, exits 0, and (if actually tested) passes. Two
real gaps push this to `needs_revision`: (1) the `module+ test` assertions are
**never executed** by any command the spec lists, and (2) the S2 closeout is
**incomplete** — the S2 section header is left reading `📋`.

---

## API accuracy verification (the load-bearing part) — ALL PASS

1. **`validation-error-path` is a LIST.** Confirmed `mcp/core/validators/provider.rkt:51`
   `(struct validation-error (path message) #:transparent)`; `from-json-schema.rkt`
   populates path via `(append path (list …))` from `'()` (`:300,:334,:340,:353`).
   `(list? (validation-error-path …))` is correct.
   `validation-errors-errors` returns a NON-EMPTY list (`#:guard` enforces it,
   provider.rkt:58-64), so `(car errs)` is safe. Accessors `validation-ok-value`,
   `validation-error-message`, `validation-error-path` all provided (provider.rkt:112-114). ✔
   - **Note (stronger assertion available):** for the bad value `(hasheq 'age 30)`
     the single error is the `required` failure emitted at **root**, so its path is
     `'()` (NOT `'("name")`) and its message is exactly `"missing required property: name"`
     (from-json-schema.rkt:340). `(list? path)` passes on `'()` and is safe, but a
     vacuity-hardening pair would lock the behaviour:
     `(check-equal? (validation-error-path (car errs)) '())` and
     `(check-equal? (validation-error-message (car errs)) "missing required property: name")`.
     The path is empty-list, not `["name"]` — worth stating in the spec so the
     worker doesn't assert `'("name")` by mistake.

2. **`make-racket-native-provider`** is the real exported name
   (`from-json-schema.rkt:142,:402`). ✔

3. **`uri-template-match`** returns a **symbol-keyed `hasheq`** on success
   (uri-template.rkt:382-390, `string->symbol` at :386), `#f` on no-match (:375)
   and on a nameless-capture (:380). Expand reads symbol keys via
   `(string->symbol name)` (:249). `"/users/{id}/posts/{post}"` + `(hasheq 'id "42"
   'post "hello-world")` → simple single-name parts → `"/users/42/posts/hello-world"`;
   match regex `^/users/([^/,]+)/posts/([^/,]+)$` recovers `id="42"`,
   `post="hello-world"` (no `/` or `,`, non-exploded → single strings).
   `(hash-ref matched-vars 'id)` → `"42"`, `'post` → `"hello-world"`. ✔

4. **stdio arm — the critical envelope check.** `serialize-message`,
   `make-read-buffer`, `read-buffer-append!`, `read-buffer-read-message!` all
   provided (stdio.rkt:35-43); empty buffer → no `\n` → `#f` (rt-c). ✔
   The danger was that `read-buffer-read-message!` **raises** (not skips) on a
   parse-OK-but-bad-envelope line (stdio.rkt:189-191), so the two demo messages
   MUST pass the S1 `jsonrpc-message?` guard. Verified:
   - `msg-a (hasheq 'jsonrpc "2.0" 'method "ping" 'id 1)` → `is-jsonrpc-request?`
     PASSES (guards.rkt:75: valid jsonrpc, valid-id 1, string method, no
     result/error, only keys jsonrpc/id/method).
   - `msg-b (hasheq 'jsonrpc "2.0" 'result (hasheq) 'id 1)` → `is-jsonrpc-result-response?`
     PASSES (guards.rkt:105). Note `json-object?` requires **immutable hasheq**
     (guards.rkt:42 `(and (hash? v) (immutable? v) (hash-eq? v))`); both the
     `hasheq` literals and `read-json`'s output are immutable hasheq, and the
     guard runs on the **parsed** value, so `result {}` → empty immutable hasheq
     satisfies it. Messages are YIELDED, never skipped/raised. ✔
   - Round-trip: `(hash-ref rt-a 'method)` → `"ping"`, `(hash-ref rt-b 'id)` → `1`
     (exact int survives JSON). ✔

5. **Template structural claims.** s1-demo.rkt has `module+ main` at :106 (cited
   :106-134 ✔), `module+ test` at :137 (cited :137-163 ✔), `(file "…")` requires
   :37-47 ✔, `define-runtime-path` :51 ✔, header :1-31 ✔. All line cites accurate.

---

## Critical gaps (drive needs_revision)

### C1 — `module+ test` assertions are NEVER RUN by the spec's commands (vacuous as written)
The spec leans hard on "`raco test` makes the assertions non-vacuous"
(Description, Steps §2 header, §"module+ test"). But:
- **Testing Strategy** (`:192-195`) runs `racket mcp/core/demo/s2-demo.rkt` — that
  executes `module+ main` ONLY, never `module+ test`.
- **Acceptance #3** (`:28`) runs `raco test mcp/core/validators/ mcp/core/util/
  mcp/core/shared/` — which **excludes `mcp/core/demo/`**, so the demo's test
  submodule is not picked up.
Net: the carefully-written 14 `check-*` assertions are dead code under the stated
commands. Contrast item 009, which **explicitly** ran `raco test
mcp/core/demo/s1-demo.rkt` (009 spec :518) and added `mcp/core/demo/` to the
canonical green command (009 :523).
**Fix:** add `raco test mcp/core/demo/s2-demo.rkt` to the Testing Strategy block,
and add an acceptance criterion: "`raco test mcp/core/demo/s2-demo.rkt` exits 0,
all module+ test checks pass." Otherwise the non-vacuity guarantee is fictional.

### C2 — S2 closeout incomplete: the S2 SECTION HEADER is left as `📋`
S1 sets the convention: BOTH the overview-table row (`progress.md:27` `✅`) AND the
section header (`progress.md:41` `## Stage S1 … — ✅`) are flipped. Item 018's
Edit A + Acceptance #4 only flip the overview-table **row** (`:28`). The S2
**section header** at `progress.md:66` (`## Stage S2 … — 📋`) is never touched, so
a worker following the spec literally ships a progress.md where the overview row
says `✅` but the section header still says `📋` — an inconsistent, half-closed
stage.
**Fix:** add **Edit E** — `grep -n "## Stage S2" docs/aide/progress.md` →
flip the trailing `— 📋` to `— ✅` (currently :66) — and a matching acceptance box.

---

## Verified-correct progress edits (A–D)
- **Edit A** target `| S2 | Validators` (`:28`, `📋`→`✅`) — unambiguous (one row). ✔
- **Edit B** `Demo: register schema` (`:90`, `[ ]`→`[x]`) — unambiguous. ✔
- **Edit C** ` (except shared/test/stdio-test.rkt — lands with item 016/M5e)` on
  the deliverables bullet (`:79`) — exact substring present; removal correct now 016 is ✅. ✔
- **Edit D** `(except stdio.rkt/M5e — orphaned-until-S6a per roadmap.md:118; stdio
  coverage + the framing box land with item 016)` on the raco-test box (`:83`) —
  exact text present; box already `[x]`, trim only. ✔
- Parity rows (`validators/*`, `util/schema`, `uriTemplate`, `toolNameValidation`,
  `metadataUtils`, `auth`) already read `partial` at `:89` and `:73-77`; spec
  correctly says NOT to re-flip them (R5 scope guard intact). ✔

---

## Suggested (non-blocking)
- **S1.** Step 1 / Dependencies say s1-demo is "178 lines"; it is **163 lines**
  (`wc -l`). Update so the worker doesn't think the file was truncated.
- **S2.** Acceptance #3 hardcodes "≥671 checks". This number is a frozen claim
  from the 017 baseline — instruct the worker to **re-derive** the baseline count
  (run the three-dir `raco test` before adding the demo) rather than trust the
  literal, since it's easy to drift. (Adding C1's `raco test …/demo/` changes the
  total too — keep the two counts separate.)
- **S3.** Strengthen the arm-1 path/message assertion per the note in API point 1
  (assert path `'()` and the exact "missing required property: name" message) so
  arm 1 is not merely "an error of some shape exists."
- **S4.** Consider asserting `(equal? rt-a msg-a)` / `(equal? rt-b msg-b)` (full
  jsexpr equality, hasheq round-trips cleanly here) instead of only spot-checking
  one field each — cheap, and proves the whole frame round-tripped.
