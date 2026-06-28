# Item 018: Stage S2 Demo + Closeout

**Queue:** queue-002.md:55–56  
**Stage:** S2 (closes it)  
**Depends on:** items 010–017 (all ✅)  
**Unblocks:** queue-003 / Stage S3

---

## Description

Add `mcp/core/demo/s2-demo.rkt` — the Stage S2 witness script, analogous to `mcp/core/demo/s1-demo.rkt` (item 009). It exercises three S2 subsystems end-to-end as a downstream consumer, requiring only the public module paths:

1. **M3 validator** — compile a JSON Schema, validate a good value, validate a bad value and print the structured `validation-error` path+message list.
2. **M5a URI template** — expand a template with variable bindings, match the result URI back, print both.
3. **M5e stdio framing** — serialize ≥2 messages, concatenate the frames, feed into a read-buffer, read them back in order, print the round-tripped messages.

Then update `docs/aide/progress.md` to close out Stage S2: flip the stage-overview row to ✅, check the demo acceptance box, and remove two now-stale caveats that referred to items 016 (stdio) and 017 (portability) as pending. The parity-matrix rows touched by item 017 (`validators/*`, `util/schema`, `uriTemplate`, `toolNameValidation`, `metadataUtils`, `auth`) already read `partial` in the progress narrative — item 018 does **not** re-flip them, only confirms they are recorded and notes the S2 closeout in the narrative if appropriate.

No new modules, no new protocol types, no external services. Pure consumer over ✅ items 010–017.

---

## Acceptance Criteria

- [ ] `mcp/core/demo/s2-demo.rkt` exists; first line is `#lang racket/base`; uses `(require …)` of the exact public module paths listed in Implementation Steps §1; no `all-defined-out`; no fabricated stubs.
- [ ] `racket mcp/core/demo/s2-demo.rkt` runs from the repo root, exits 0, prints all three arms including the structured `validation-error` path and message for the bad value and the round-tripped stdio messages.
- [ ] `raco test mcp/core/demo/s2-demo.rkt` passes — the `module+ test` assertions execute green.
- [ ] `raco test mcp/core/validators/ mcp/core/util/ mcp/core/shared/` exits 0, check count ≥ the item-017 baseline.
- [ ] `docs/aide/progress.md` stage-overview table row for S2 reads `✅` (was `📋`).
- [ ] `docs/aide/progress.md` Stage S2 section header reads `✅` (was `📋`; currently :66 `## Stage S2 — Foundation … — 📋`).
- [ ] `docs/aide/progress.md` S2 demo acceptance box reads `[x]` (was `[ ]`).
- [ ] The stale `(except stdio.rkt/M5e …)` caveat on the S2 `raco test` acceptance box (currently progress.md:83) is removed.
- [ ] The stale `(except shared/test/stdio-test.rkt — lands with item 016/M5e)` caveat in the S2 deliverables bullet (currently progress.md:79) is removed.
- [ ] Item 018 does **not** touch S3+ rows, does not re-flip already-✅ boxes, and does not revert any checked box.

---

## Implementation Steps

### 1. Read the template

Read `mcp/core/demo/s1-demo.rkt` (163 lines) to absorb the structural idioms: `#lang racket/base`, numbered arms, `(module+ main …)` for the transcript, `(module+ test …)` for CI-checkable assertions, and `racket/pretty` for struct display. Mirror the comment header style.

### 2. Create `mcp/core/demo/s2-demo.rkt`

#### Header comment (mirror s1-demo.rkt:1–31)

Document: what stage this witnesses, the three arms, that it is a pure consumer, and that `racket mcp/core/demo/s2-demo.rkt` prints the transcript while `raco test` makes the assertions non-vacuous.

#### Requires

```racket
(require racket/pretty
         (only-in (file "../validators/from-json-schema.rkt")
                  make-racket-native-provider)
         (only-in (file "../validators/provider.rkt")
                  provider-compile validate
                  validation-ok? validation-ok-value
                  validation-errors? validation-errors-errors
                  validation-error-path validation-error-message)
         (only-in (file "../shared/uri-template.rkt")
                  uri-template-expand uri-template-match)
         (only-in (file "../shared/stdio.rkt")
                  serialize-message make-read-buffer
                  read-buffer-append! read-buffer-read-message!))
```

Use `(file "…")` relative paths, same as s1-demo.rkt:37–47 for the barrel require. The `file` form resolves relative to the `.rkt` source at expand time, so `racket mcp/core/demo/s2-demo.rkt` works from any working directory.

#### Arm 1 — M3 validator (top-level setup, before `module+ main`)

```racket
;; ---- Arm 1: M3 JSON Schema validator ----
(define prov (make-racket-native-provider))

;; schema: object with required "name" (string) and optional "age" (number)
(define schema
  (hasheq 'type "object"
          'properties (hasheq 'name (hasheq 'type "string")
                              'age  (hasheq 'type "number"))
          'required '("name")))

(define handle (provider-compile prov schema))

(define good-value (hasheq 'name "Alice" 'age 30))
(define bad-value  (hasheq 'age 30))   ; missing required "name"

(define good-result (validate handle good-value))
(define bad-result  (validate handle bad-value))
```

Verify: `good-result` is `validation-ok?`; `bad-result` is `validation-errors?` with a non-empty error list. These are top-level so the `module+ test` assertions can reference them without re-running.

#### Arm 2 — M5a URI template (top-level)

```racket
;; ---- Arm 2: URI template expand + match ----
(define tmpl "/users/{id}/posts/{post}")
(define tmpl-vars (hasheq 'id "42" 'post "hello-world"))

(define expanded-uri (uri-template-expand tmpl tmpl-vars))
(define matched-vars (uri-template-match tmpl expanded-uri))
```

`expanded-uri` → `"/users/42/posts/hello-world"`.  
`matched-vars` → a hash with `'id` and `'post` (or `#f` on no-match — assertion guards against this).

#### Arm 3 — M5e stdio round-trip (top-level)

```racket
;; ---- Arm 3: stdio frame encode/decode ----
(define msg-a (hasheq 'jsonrpc "2.0" 'method "ping" 'id 1))
(define msg-b (hasheq 'jsonrpc "2.0" 'result (hasheq) 'id 1))

(define framed-a (serialize-message msg-a))
(define framed-b (serialize-message msg-b))
(define framed-concat (bytes-append framed-a framed-b))

(define rb (make-read-buffer))
(read-buffer-append! rb framed-concat)
(define rt-a (read-buffer-read-message! rb))
(define rt-b (read-buffer-read-message! rb))
(define rt-c (read-buffer-read-message! rb))  ; should be #f — buffer empty
```

`rt-a` and `rt-b` are jsexpr hashes equal to `msg-a`/`msg-b`; `rt-c` is `#f`.

#### `module+ main` transcript

Mirror s1-demo.rkt:106–134. Print a header, then:

- **Arm 1 header:** print `good-result` via `pretty-print`; assert `validation-ok?`; print the `validation-errors-errors` list for `bad-result` — each error's `validation-error-path` and `validation-error-message`.
- **Arm 2 header:** print `expanded-uri`, print `matched-vars` via `pretty-print`.
- **Arm 3 header:** print `rt-a`, `rt-b` via `pretty-print`; print `rt-c` to confirm `#f`.
- Closing `=== demo complete ===` line.

#### `module+ test` assertions

Mirror s1-demo.rkt:137–163. Non-vacuous, CI-checkable:

```racket
(module+ test
  (require rackunit)
  ;; arm 1
  (check-true  (validation-ok? good-result)     "good value → validation-ok")
  (check-equal? (validation-ok-value good-result) good-value "ok value preserved")
  (check-true  (validation-errors? bad-result)  "bad value → validation-errors")
  (let ([errs (validation-errors-errors bad-result)])
    (check-true (pair? errs)                    "at least one error")
    (check-true (string? (validation-error-message (car errs))) "error has string message")
    (check-true (regexp-match? #rx"name" (validation-error-message (car errs)))
                               "error message names the missing property")
    (check-true (list?   (validation-error-path    (car errs))) "error has list path"))
  ;; arm 2
  (check-equal? expanded-uri "/users/42/posts/hello-world" "expand correct")
  (check-true   (hash? matched-vars)            "match returns hash not #f")
  (check-equal? (hash-ref matched-vars 'id   #f) "42"          "matched id")
  (check-equal? (hash-ref matched-vars 'post #f) "hello-world" "matched post")
  ;; arm 3
  (check-true  (hash? rt-a)  "first message decoded")
  (check-true  (hash? rt-b)  "second message decoded")
  (check-false rt-c          "buffer empty → #f")
  (check-equal? (hash-ref rt-a 'method #f) "ping" "round-tripped method")
  (check-equal? (hash-ref rt-b 'id     #f) 1      "round-tripped id"))
```

### 3. Edit `docs/aide/progress.md`

Four surgical edits — use `grep` to locate exact line numbers at edit time since they may shift:

**Edit A — stage overview row:**  
`grep -n "S2 | Validators" docs/aide/progress.md` → find the table row (currently :28).  
Change `📋` → `✅` in that row.

**Edit B — demo acceptance box:**  
`grep -n "Demo: register schema" docs/aide/progress.md` → find the `[ ]` box (currently :90).  
Change `[ ]` → `[x]`.

**Edit C — remove stale stdio-test caveat in deliverables:**  
`grep -n "except shared/test/stdio-test" docs/aide/progress.md` → find the bullet (currently :79).  
Remove the substring ` (except shared/test/stdio-test.rkt — lands with item 016/M5e)` from that bullet, leaving the `✅` deliverable line intact.

**Edit D — remove stale M5e caveat on the raco-test acceptance box:**  
`grep -n "except stdio.rkt/M5e" docs/aide/progress.md` → find the `[x]` line (currently :83).  
Remove the parenthetical `(except stdio.rkt/M5e — orphaned-until-S6a per roadmap.md:118; stdio coverage + the framing box land with item 016)` — the box already reads `[x]` so only the caveat text needs trimming.

**Edit E — flip Stage S2 section header:**  
`grep -n "## Stage S2" docs/aide/progress.md` → find the section header (currently :66).  
Change `📋` → `✅` in the trailing status token of that line (e.g. `— 📋` → `— ✅`).

**Scope guard:** do not touch S3+ rows, do not uncheck any box, do not re-flip already-✅ items.

---

## Testing Strategy

Run the demo, run the demo test submodule, then confirm the full S2 test suite is still green.

```bash
racket mcp/core/demo/s2-demo.rkt
raco test mcp/core/demo/s2-demo.rkt
raco test mcp/core/validators/ mcp/core/util/ mcp/core/shared/
```

---

## Dependencies

| Item | Module(s) | Status |
|------|-----------|--------|
| 010 | `mcp/core/validators/provider.rkt` | ✅ |
| 011 | `mcp/core/validators/from-json-schema.rkt` | ✅ |
| 012 | `mcp/core/util/schema.rkt` | ✅ |
| 013 | `mcp/core/shared/uri-template.rkt` | ✅ |
| 014 | `mcp/core/shared/tool-name-validation.rkt` | ✅ |
| 015 | `mcp/core/shared/metadata-utils.rkt`, `auth.rkt` | ✅ |
| 016 | `mcp/core/shared/stdio.rkt` | ✅ |
| 017 | `mcp/core/test/s2-portability-test.rkt` | ✅ |
| Template | `mcp/core/demo/s1-demo.rkt` (structural model) | ✅ |

---

## Decisions & Trade-offs

- **Top-level arm definitions** — all three arms (`good-result`, `bad-result`, `expanded-uri`, `matched-vars`, `rt-a`/`rt-b`/`rt-c`) are computed at module top-level so both `module+ main` and `module+ test` reference the same values without re-running; same pattern as s1-demo.rkt.
- **`file` requires** — relative to source file (not CWD), so `racket mcp/core/demo/s2-demo.rkt` works from any directory; no `define-runtime-path` needed (no external fixture files).
- **Transcript format** — per-arm headers match s1-demo.rkt style; structured error list printed via `for` loop over `validation-errors-errors` to show path+message pairs clearly.
- **`rt-c` sentinel** — explicitly read a third message after two-message buffer to confirm `#f` on empty; check-false assertion in test makes this non-vacuous.
- **No `json` require** — arms 1–3 use only the imported S2 API surface; no raw JSON parse/emit needed in the demo itself.

---

## Completion Reminder

After implementation and tests pass:

1. Mark item 018 itself: `docs/aide/progress.md` item row `📋` → `🚧` → `✅`.
2. Confirm Stage S2 overview row reads `✅` (Edit A above).
3. Confirm Stage S2 section header reads `✅` (Edit E above).
4. Confirm S2 demo acceptance box reads `[x]` (Edit B above).
5. Confirm the two stale caveats (Edits C and D) are removed.
6. Confirm parity-matrix rows for `validators/*`, `util/schema`, `uriTemplate`, `toolNameValidation`, `metadataUtils`, `auth` still read `partial` in the progress narrative (item 018 does not advance them further — that is S9's job).

---

## Project-Specific Notes

- Racket demo script only; no external services, no subprocess, no network.
- `file` requires (relative to script source) let `racket mcp/core/demo/s2-demo.rkt` run from any cwd — same idiom as s1-demo.rkt:51.
- Completes Stage S2 and unblocks S3 / queue-003.
- Item 018 owns **only**: the demo script, the Stage S2 status flip, the demo acceptance box, and the two stale-caveat cleanups. Everything else in S2 was owned by items 010–017.
