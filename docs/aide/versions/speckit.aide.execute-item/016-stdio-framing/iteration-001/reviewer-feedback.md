# Reviewer Feedback — Item 016 (stdio framing, M5e)

**Verdict: APPROVED — no revision needed.** Every Acceptance Criterion is objectively met; no correctness bug found. Gates re-run green by the reviewer.

## Gates (re-run, repo root)

| Gate | Result |
|---|---|
| `raco make mcp/core/shared/stdio.rkt` | exit 0, clean |
| `raco test mcp/core/shared/` | **317 passed**, 0 fail (was 269; +48 stdio — matches worker claim) |
| `raco test mcp/core/validators/ mcp/core/util/` | **402 passed**, 0 fail (300 + 102, matches spec Decisions (i)) |

## Focus-area findings

1. **THE PINNED DEFECT — CLEAN.** `read-buffer-read-message!` (stdio.rkt:169-191) contains NO `with-handlers`. The sole parse handler is confined to `try-parse-json-line` (stdio.rkt:83-98), wrapping only `read-json` and catching `exn:fail?` → `'PARSE-FAIL`. The envelope check `jsonrpc-message?` + its `error` raise (stdio.rkt:188-191) are OUTSIDE any handler. The skip decision keys on the `ok?` flag (`(not ok?)` at stdio.rkt:187), never on value truthiness. JSON `false` → `read-json` → Racket `#f` → `(values #f #t)` (a SUCCESS) → reaches envelope check → RAISES. Tests: `{"not":...}` raises (stdio-test.rkt:248-253); `false`/`null`/`42`/`true`/`"hi"` each raise (stdio-test.rkt:255-276); non-JSON / debug / unbalanced / `{invalidJson:true}` / empty / trailing-garbage all SKIP (stdio-test.rkt:195-246). Both behaviours present and passing.

2. **Three pinned behaviours — all correct.**
   - Encoder emits single `\n`: stdio.rkt:110 (`#"\n"`); asserted ends-in-10, not-`\r\n` (stdio-test.rkt:49-55).
   - CRLF tolerance: `strip-trailing-cr` (stdio.rkt:63-67) applied on receive at stdio.rkt:183; `\r\n` decodes `check-equal?` to `\n` form (stdio-test.rkt:292-303); non-JSON CRLF line still skipped (stdio-test.rkt:284).
   - Overflow: `>` strict (stdio.rkt:155), clear BEFORE raise (stdio.rkt:156), `error` is `exn:fail?` with message "ReadBuffer exceeded maximum size of ~a bytes". Exactly-max allowed, custom cap, single-shot, max=0 edge, empty-chunk no-op, clear-before-throw reuse all asserted (stdio-test.rkt:308-360, incl. `#rx"ReadBuffer exceeded maximum size"`).

3. **Byte-level buffering — correct.** `read-buffer-append!` takes `bytes?`; multibyte UTF-8 split at a located `0xC3` lead byte reassembles (non-vacuous test asserts the lead byte exists first, stdio-test.rkt:160-177).

4. **Public surface — exactly 8 exports.** stdio.rkt:35-43: `serialize-message`, `deserialize-message`, `make-read-buffer`, `read-buffer?`, `read-buffer-append!`, `read-buffer-read-message!`, `read-buffer-clear!`, `STDIO-DEFAULT-MAX-BUFFER-SIZE`. No `all-defined-out`. Internal helpers (`jsonrpc-message?`, `strip-trailing-cr`, `try-parse-json-line`) and struct accessors/mutators (`read-buffer-bytes`, `set-read-buffer-bytes!`, `read-buffer-max-size`) are NOT provided. `STDIO-DEFAULT-MAX-BUFFER-SIZE = (* 10 1024 1024)` = 10485760 (stdio.rkt:49).

5. **Imports = S1 + json only.** `(require json "../main.rkt")` (stdio.rkt:32-33). No `racket/system`/subprocess/socket/`net/*`. Per-module sweep correctly deferred to item 017 (carve-out honored).

6. **Acceptance-criteria completeness.** Walked the checklist (spec :172-198) and the fixture-mapping table (:304-325). Every listed fixture/behaviour is ported and asserted, including the queue-headline multi-message round-trip (stdio-test.rkt:133), all-four envelope kinds (request/notification/result/error, stdio-test.rkt:365-383 — exceeds the 3 required), `deserialize-message` string+bytes valid + array/null/scalar raise (stdio-test.rkt:71-94), raw-preserve nested-key divergence (stdio-test.rkt:96-102), embedded-`\n`/`\r` single-frame premise (stdio-test.rkt:179-190), no `(module+ test)`. Nothing claimed-but-missing.

7. **progress.md (R5 scope).** Item 016's two owned edits are correct: deliverable line :78 → ✅ with as-built summary; framing box :88 → `[x]`. Demo box (:90) correctly left `[ ]` (item 018). The other checked boxes (catch-all :83, parity rows :89, tests line :79, s2-portability line :80, parity-matrix paragraph :337) belong to item 017 and carry item-017 attribution text — they are co-resident in the uncommitted working tree, not an item-016 overreach. No contradictory 016 edit.

## Observations (non-blocking, not item-016 fixes)

- **Stale caveat (item 017's row):** progress.md:79 reads "except `shared/test/stdio-test.rkt` — lands with item 016/M5e", but item 016 has now delivered that test. The caveat is stale and should be dropped/updated — but :79 is an item-017-owned line, so flagging as observation only per task instructions.
- **NOTE (theoretical, not a defect):** `try-parse-json-line` confirms whole-line parse by reading remaining bytes with `(read-bytes (expt 2 20) p)` (stdio.rkt:94) — a 1 MB cap. A single line whose JSON value is followed by >1 MB of whitespace then trailing non-whitespace would not be detected as garbage. Not reachable by any fixture and not a realistic frame; mentioned only for completeness. No change requested.
