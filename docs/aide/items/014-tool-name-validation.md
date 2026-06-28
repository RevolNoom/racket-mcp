# Work Item 014: Tool-name validation (M5b)

> **Queue:** `docs/aide/queue/queue-002.md` — Item 014
> **Stage:** S2 (Foundation: validators, schema, shared utilities — L0 part 2)
> **Module:** M5b (tool-name validation) — `mcp/core/shared/tool-name-validation.rkt`. The tool-name conformance checker per **SEP-986** ("Specify Format for Tool Names"). It validates a candidate tool name against the SEP character/length rules, returns a structured `{valid?, warnings}` result, and (separately) emits the advisory warnings. It is consumed by the high-level server's tool-registration surface (S6b, M12b: `register-tool`), which calls it to warn-but-proceed on non-conforming names. It has **NO consumer inside S2** — it is built ahead of its consumer.
> **Source vision:** `docs/aide/vision.md` §6 (Portability NFR — core L0–L2 loads without subprocess/socket; this is a pure non-I/O string module), G1 (wire/behaviour parity with the TS SDK — the accept/reject set + warning strings must match TS `toolNameValidation` for the ported fixtures).
> **Source roadmap:** `docs/aide/roadmap.md` Stage S2 → Deliverables line (`mcp/core/shared/tool-name-validation.rkt` (M5b)) + Testing/validation criterion (`Tool-name validation matches TS toolNameValidation accept/reject set`).
> **Source architecture:** `docs/aide/architecture.md` M5b (shared util; depends on S1 only), §1.3 (public/internal boundary, explicit `provide`), §4.1 (Runtime-neutral core L0–L2 import no subprocess/socket).
> **Reference impl (authoritative):** MCP TypeScript SDK v2 at `typescript-sdk/` — `packages/core/src/shared/toolNameValidation.ts` (the three exports `validateToolName` / `issueToolNameWarning` / `validateAndWarnToolName`, the `TOOL_NAME_REGEX`, the warning strings + guidance lines) and `packages/core/test/shared/toolNameValidation.test.ts` (the fixture suite this item ports 1:1). **Framing:** this is a near-direct **transliteration** of `toolNameValidation.ts` into idiomatic Racket — same rule, same warning order, same warning strings, same accept/reject set, same emission shape. The only adaptations are Racket naming/data shapes (a struct instead of a `{isValid, warnings}` object, kebab-case names, a module logger instead of `console.warn`).
> **Status:** 📋 Planned — not started.

---

## Description

Implement `mcp/core/shared/tool-name-validation.rkt`, the **tool-name conformance checker** for `racket-mcp` per **SEP-986**. The rule (verbatim from the SEP / the TS doc comment):

- Tool names SHOULD be **1–128 characters** in length (inclusive).
- Tool names are **case-sensitive**.
- Allowed characters: uppercase + lowercase ASCII letters (`A-Z`, `a-z`), digits (`0-9`), underscore (`_`), dash (`-`), and dot (`.`). Regex: `/^[A-Za-z0-9._-]{1,128}$/`.
- Tool names SHOULD NOT contain spaces, commas, or other special characters (these produce **advisory** warnings).

The module provides three operations, transliterated from the three TS exports:

1. **`validate-tool-name`** — `(validate-tool-name name) → tool-name-validation`. Returns a struct `(tool-name-validation valid? warnings)` where `valid?` is a boolean and `warnings` is a `(listof string?)`. This is TS `validateToolName(name) → {isValid, warnings}`.
2. **`issue-tool-name-warning`** — `(issue-tool-name-warning name warnings) → void`. Emits the warnings (header + each warning + three fixed guidance lines) via a module logger when `warnings` is non-empty; emits nothing when empty. This is TS `issueToolNameWarning(name, warnings) → void`.
3. **`validate-and-warn-tool-name`** — `(validate-and-warn-tool-name name) → boolean?`. Validates, always issues the warnings (for BOTH invalid AND advisory-valid names), returns `valid?`. This is TS `validateAndWarnToolName(name) → boolean`.

Plus a convenience predicate **`valid-tool-name?`** — `(valid-tool-name? name) → boolean?` — `(tool-name-validation-valid? (validate-tool-name name))`. The build target is **behaviour parity with the TS results** for the ported fixtures (vision goal **G1**): every fixture in `toolNameValidation.test.ts` maps to a Racket test case asserting the same `valid?` / warning-membership / emission behaviour.

### Framing — direct transliteration of `toolNameValidation.ts` (read carefully)

The TS source is three free functions over a regex. This item ports their behaviour, not their shape. The mapping by role:

| TS export | Role | Racket analogue |
|---|---|---|
| `TOOL_NAME_REGEX = /^[A-Za-z0-9._-]{1,128}$/` | the SEP-986 conformance regex | a module constant `tool-name-rx` (`#px"^[A-Za-z0-9._-]{1,128}$"`) + a per-char `valid-tool-name-char?` predicate **derived from the SAME ASCII class** for invalid-char collection (see the C1 PIN below) |
| `validateToolName(name) → {isValid, warnings}` | length checks (early returns) + advisory warnings + invalid-char detection | `validate-tool-name` → `(tool-name-validation valid? warnings)` |
| `issueToolNameWarning(name, warnings) → void` | emit header + each warning + 3 guidance lines via `console.warn`; empty → nothing | `issue-tool-name-warning` → emits via a module logger (`define-logger mcp-tool-name`) |
| `validateAndWarnToolName(name) → boolean` | validate, always warn, return `isValid` | `validate-and-warn-tool-name` → boolean |
| (none — TS has no boolean-only validator) | — | `valid-tool-name?` (convenience predicate over the struct) |

### Return shape — struct + predicate (PINNED), and the queue's "normalizer" misnomer (RESOLVED)

The queue entry (item 014) says: *"Expose a `valid-tool-name?`-style predicate and the normalizer."* This is reconciled with TS's richer `{isValid, warnings}` return as follows:

- **PINNED:** expose BOTH a structured `validate-tool-name` returning `(struct tool-name-validation (valid? warnings) #:transparent)` (warnings = list of strings) AND a boolean `valid-tool-name?` predicate. The struct carries the warnings (the advisory information a valid-but-suspicious name needs); the predicate is the terse accept/reject test.
- **PINNED — there is NO normalizer.** The queue's word **"normalizer" is a misnomer**: TS `toolNameValidation.ts` **never mutates the name** — it validates and warns, it does not transform. **Do NOT invent a name-mutating normalizer that is not in TS** (e.g. one that strips spaces or lowercases). The closest TS analogue of a "normalizer" is **`validate-and-warn-tool-name`** (the boolean + warning-emission combinator that the registration path calls). This discrepancy is called out so the executor does not fabricate a transform the TS SDK does not have and that would silently diverge from G1 parity. If a future MCP revision adds a canonicalization step, a later item adds it; it is **out of scope here**.

The committed public surface:

```racket
(struct tool-name-validation (valid? warnings) #:transparent)
(validate-tool-name          name)            ; -> tool-name-validation
(valid-tool-name?            name)            ; -> boolean?
(issue-tool-name-warning     name warnings)   ; -> void
(validate-and-warn-tool-name name)            ; -> boolean?
```

`provide`d: the struct (and its auto-generated `tool-name-validation?` / `tool-name-validation-valid?` / `tool-name-validation-warnings`) plus the four functions. No internal helpers leak.

### `validateToolName` logic order — port EXACTLY (PINNED)

The order of operations is load-bearing (early returns vs. accumulated advisory warnings). Port it verbatim:

1. **length 0** → early-return `(tool-name-validation #f (list "Tool name cannot be empty"))`.
2. **length > 128** → early-return `(tool-name-validation #f (list (format "Tool name exceeds maximum length of 128 characters (current: ~a)" len)))`.
3. else accumulate **advisory** warnings (these do NOT, by themselves, flip `valid?` — a name can be valid WITH warnings). Push in THIS order:
   - contains `#\space` → `"Tool name contains spaces, which may cause parsing issues"`.
   - contains `#\,` → `"Tool name contains commas, which may cause parsing issues"`.
   - starts-with OR ends-with `#\-` → `"Tool name starts or ends with a dash, which may cause parsing issues in some contexts"`.
   - starts-with OR ends-with `#\.` → `"Tool name starts or ends with a dot, which may cause parsing issues in some contexts"`.
4. then **regex test** against `^[A-Za-z0-9._-]{1,128}$`:
   - if it **FAILS**: collect the **invalid characters** (chars NOT matching `[A-Za-z0-9._-]`, **deduplicated, preserving first-seen order**), push TWO warnings — `(format "Tool name contains invalid characters: ~a" joined)` where `joined` is each invalid char wrapped in double-quotes (`"x"`), comma-space joined in first-seen order — AND `"Allowed characters are: A-Z, a-z, 0-9, underscore (_), dash (-), and dot (.)"` — then return `(tool-name-validation #f warnings)`.
   - if it **passes**: return `(tool-name-validation #t warnings)` (warnings may be non-empty — e.g. `-get-user-` is valid but carries the dash advisory).

> **Invalid-char collection — first-seen dedup (PINNED).** TS does `[...name].filter(char => !/[A-Za-z0-9._-]/.test(char)).filter((char, index, arr) => arr.indexOf(char) === index)` — filter invalid chars, then dedup keeping the FIRST occurrence (preserving first-seen order). Racket `remove-duplicates` over `(filter (lambda (c) (not (valid-tool-name-char? c))) (string->list name))` does exactly this — `remove-duplicates` keeps the first occurrence and preserves order. **Pin this with the multi-char fixture** `user name@domain,com` → invalid chars in first-seen order are space, `@`, comma → message `Tool name contains invalid characters: " ", "@", ","`.

> **C1 — `valid-tool-name-char?` MUST derive from the SAME ASCII class as the regex; `char-alphabetic?` / `char-numeric?` are FORBIDDEN (PINNED, CRITICAL).** There is **one source of truth** for the allowed-character set: the ASCII class `[A-Za-z0-9._-]`. The per-char predicate used by `collect-invalid-chars` MUST be derived from that exact class — implement it as `(define (valid-tool-name-char? c) (and (regexp-match? #px"[A-Za-z0-9._-]" (string c)) #t))` (mirrors TS's per-char `/[A-Za-z0-9._-]/.test(char)`), or an explicit ASCII codepoint range check (`A–Z` 65–90, `a–z` 97–122, `0–9` 48–57, plus `. _ -`). **Do NOT use Racket's `char-alphabetic?` / `char-numeric?`** — they are **Unicode-aware** and therefore WRONG here: `(char-alphabetic? #\ñ)` → `#t` and `(char-numeric? #\٢)` (Arabic-Indic digit) → `#t`, which would make `collect-invalid-chars` skip `ñ` and return `'()` for `user-ñame`. The name would still be `valid? = #f` (the ASCII `tool-name-rx` rejects it), but the **invalid-chars message would be empty** — silently breaking the `"ñ"` fixture (`Tool name contains invalid characters: "ñ"`). The `user-ñame` fixture catches this, but the predicate MUST be pinned to the ASCII class up front so the divergence is never introduced. (The two checks — `tool-name-rx` for the pass/fail decision and `valid-tool-name-char?` for the message — MUST agree on the same character set.)

> **Advisory-vs-invalid distinction (PINNED — do NOT conflate).** The space/comma/dash/dot warnings are **advisory**: they are pushed but do NOT set `valid? = #f`. `valid?` is determined SOLELY by the length checks and the regex test. So `get-user-` and `.get.user.` are **valid (`#t`)** despite carrying a dash/dot advisory; whereas `get user profile` is **invalid (`#f`)** because the space fails the regex (it carries BOTH the space advisory AND the invalid-char warnings). Do not let the presence of an advisory warning flip `valid?`.

### Warning emission — `issueToolNameWarning` analogue (PINNED: module logger)

Racket has no `console.warn`. **PINNED decision:** use a **module logger** via `(define-logger mcp-tool-name)` and emit each line with `log-mcp-tool-name-warning`. This is chosen over `eprintf`-to-stderr because logger output is **observably interceptable/testable** via `racket/logging`'s `with-intercepted-logging` (or a `make-log-receiver`), which is exactly how the test must assert the emission count + ordering + content. `eprintf` would force the test to capture stderr (`with-output-to-string` does not capture `current-error-port` cleanly, and parameterizing `current-error-port` is more brittle). The logger gives a structured, ordered, level-tagged stream the test reads directly. (Document this testability rationale in the module doc block.)

`issue-tool-name-warning` behaviour (port TS exactly): when `warnings` is non-empty, emit, in order:

1. header: `(format "Tool name validation warning for \"~a\":" name)`
2. each warning `w` in `warnings`: `(format "  - ~a" w)` (TWO leading spaces, dash, space)
3. three fixed guidance lines, in this exact order:
   - `"Tool registration will proceed, but this may cause compatibility issues."`
   - `"Consider updating the tool name to conform to the MCP tool naming standard."`
   - `"See SEP: Specify Format for Tool Names (https://github.com/modelcontextprotocol/modelcontextprotocol/issues/986) for more details."`

So the emission count is **`1 (header) + N (warnings) + 3 (guidance)`**. For the TS `issueToolNameWarning` test (`['Warning 1', 'Warning 2']`, N=2) this is **6** emissions. When `warnings` is **empty**, emit **nothing** (0 emissions) — guard the whole block on `(pair? warnings)`.

> **Each line is one log event (PINNED).** TS makes 6 separate `console.warn` calls; the Racket port makes 6 separate `log-mcp-tool-name-warning` calls (one per line), so an interceptor sees 6 ordered events. Do NOT coalesce the lines into a single multi-line `log-warning` — that would make the count 1, not 6, and break the emission-count parity assertion.

> **S5 — captured log lines are TOPIC-PREFIXED; assert with `string-contains?`, NOT `check-equal?` (PINNED).** A log event captured via `with-intercepted-logging` (the `vector-ref l 1` message field) is **prefixed with the logger topic** — Racket renders it as `"mcp-tool-name: <message>"`, not the raw `<message>`. So a captured header line reads `"mcp-tool-name: Tool name validation warning for \"test-tool\":"`, and a captured warning line reads `"mcp-tool-name:   - Warning 1"`. The Part-4 assertions therefore use **`string-contains?`** (substring membership), which is robust to the prefix and is correct as written. **The executor MUST NOT tighten any captured-log assertion into `check-equal?`** against the raw expected line — it would fail on the `mcp-tool-name: ` prefix (and on any future topic rename). Keep captured-log assertions as `string-contains?`. **Distinct from the struct-warnings exact-order test:** the `tool-name-validation-warnings` exact-`check-equal?` assertion (S2 below, Part 2) runs on the **struct field** — the plain warning strings with NO topic prefix — so `check-equal?` is correct THERE. Do not conflate the two: `check-equal?` on the struct warnings (raw strings) vs `string-contains?` on the captured log lines (topic-prefixed).

### `validateAndWarnToolName` — always warn, return validity (PINNED)

`(validate-and-warn-tool-name name)`: call `validate-tool-name`, ALWAYS call `issue-tool-name-warning` with the result's warnings (so BOTH invalid names AND advisory-valid names emit), return `valid?`. Note: because `issue-tool-name-warning` no-ops on empty warnings, a **completely clean** name (e.g. `get-user-profile`) emits **nothing** and returns `#t`; an **advisory-valid** name (e.g. `-get-user-`) emits its dash warning and returns `#t`; an **invalid** name emits and returns `#f`.

### Unicode / char handling — code points, not code units (PINNED parity nuance)

- TS computes `name.length` in **UTF-16 code units**, so an astral-plane character (outside the BMP) counts as **2** for the length checks. TS iterates `[...name]` (the spread), which yields **code points**, so the invalid-char filter sees an astral char as **one** unit. This is a known internal TS inconsistency.
- Racket strings are **code-point sequences**: `string-length` counts code points and `string->list` yields one `char` per code point. So Racket is **consistent** (code points everywhere) and, for astral chars, **more correct** than JS's surrogate-pair `.length`.
- **PINNED parity nuance:** for the **BMP** (every character the TS fixtures use — including `ñ` = U+00F1, which is a single UTF-16 code unit), `string-length`/`string->list` give **identical** counts to JS, so parity is exact. The astral-plane divergence is **documented as a known, acceptable nuance** (the SDK does not ship astral tool names; the SEP allows only `[A-Za-z0-9._-]` anyway, all BMP). No fixture exercises an astral char, so no parity gap is observable. If a reviewer wants belt-and-suspenders, add ONE astral-char test asserting the Racket (code-point) behaviour and noting it diverges from JS `.length` by design — but this is optional and the TS fixtures do not require it.

### Imports — S1 not required; portability constraint still applies (PINNED)

- **PINNED:** this module needs **NO S1 binding**. Unlike item 013 (which raises `make-protocol-error` on malformed templates), tool-name validation **never raises for a `string?` input** — it returns a struct / boolean and emits log warnings. It uses no M1 type and no M2 error. So it does **NOT** `(require "../main.rkt")`. (Stated explicitly so the executor does not add a spurious S1 import "for consistency".)
- **Input domain = `string?` (PINNED — S3/S4).** The "never raises" guarantee holds **only for string inputs**. A non-string input (e.g. `(validate-tool-name 42)`) would raise a `string-length` / `string->list` **contract error** from the underlying base ops — that is NOT a graceful `valid? = #f` result. Since the S6b `register-tool` caller may pass an unsanitized value, the executor MUST **either** (a) document the `string?` domain explicitly in the module doc block + the function doc (the input contract is "a string"; non-strings are a caller bug, surfaced as a contract error), **or** (b) add a `string?` guard at the head of `validate-tool-name` that returns a clean invalid result (e.g. `(tool-name-validation #f (list "Tool name must be a string"))`) for non-strings. **Recommendation:** option (a) — document the string domain and let the contract error surface (it matches TS, where `name: string` is the static type and a non-string is a type error, not a runtime branch); do NOT silently coerce. Whichever is chosen, state it so the "no raising" claim is scoped to strings and the S6b caller knows the contract.
- Required base collections: `racket/base` (logger, `format`), `racket/string` (`string-contains?`, `string-prefix?`, `string-suffix?`, `string-join`), `racket/list` (`remove-duplicates`). All portable, non-I/O.
- It MUST NOT require any transport/engine/role/subprocess/socket module, and **MUST NOT require `net/*`, `racket/system`, `racket/tcp`, `racket/udp`, `racket/sandbox`, or `racket/port`**. The portability constraint holds even though no S1 import is present.
- Tests live under `mcp/core/shared/test/tool-name-validation-test.rkt`.

### Scope guard (explicit — do NOT cross these lines)

- **No normalizer / name mutation.** TS does not transform names; neither does this module. The "normalizer" in the queue is `validate-and-warn-tool-name` (validate + warn + boolean), NOT a string transform. (PINNED above.)
- **No raising (for `string?` inputs).** For any **string** input all functions return / emit; none `raise`s. (Distinguishes this module from item 013.) An empty/over-length/illegal name is a `valid? = #f` result, NOT an exception. **The guarantee is scoped to strings** — a non-string input raises a base-op contract error (see the Imports PINNED note S3/S4: document the `string?` domain or add a `string?` guard).
- **No S1 import.** No `mcp/core/main.rkt` require (no type/error used). Keep the no-`net/*`/no-subprocess/no-socket portability invariant regardless.
- **Exact warning strings.** Port the warning + guidance strings byte-for-byte (they are part of the G1 contract — the TS tests assert substring membership). Do not reword.
- **Restricted-load portability is deferred to item 017.** This item does NOT add a `module->imports` restricted-namespace walk (item 013 added one for the `net/url` encoder risk; M5b has no such risk and item 017 owns the collection-wide S2 sweep that includes `tool-name-validation.rkt`). Note it; do not duplicate the walk here.
- **No `(module+ test …)` in `tool-name-validation.rkt`** — tests live in the separate `test/tool-name-validation-test.rkt` (consistent with items 010/011/012/013; keeps the module's closure free of `rackunit`/`racket/logging`).

---

## Acceptance Criteria

- [ ] `mcp/core/shared/tool-name-validation.rkt` exists as `#lang racket/base` with an explicit, curated `provide` (no `(provide (all-defined-out))`). It lives in the existing `mcp/core/shared/` collection (created by item 013).
- [ ] The module exports exactly: the struct **`tool-name-validation`** (with `tool-name-validation?` / `tool-name-validation-valid?` / `tool-name-validation-warnings`), **`validate-tool-name`** (`name → tool-name-validation`), **`valid-tool-name?`** (`name → boolean?`), **`issue-tool-name-warning`** (`name warnings → void`), and **`validate-and-warn-tool-name`** (`name → boolean?`). It does NOT leak internal helpers (`valid-tool-name-char?`, `collect-invalid-chars`, the logger plumbing).
- [ ] **VALID set (`valid? = #t`, `warnings` length 0).** Each of `getUser`, `get_user_profile`, `user-profile-update`, `admin.tools.list`, `DATA_EXPORT_v2.1`, `a`, and `(make-string 128 #\a)` validates to `valid? = #t` with `(null? warnings)`.
- [ ] **INVALID set (`valid? = #f`, contains the expected warning).** `""` → contains `"Tool name cannot be empty"`; `(make-string 129 #\a)` → contains `"Tool name exceeds maximum length of 128 characters (current: 129)"`; `get user profile` → contains `Tool name contains invalid characters: " "`; `get,user,profile` → contains `Tool name contains invalid characters: ","`; `user/profile/update` → contains `Tool name contains invalid characters: "/"`; `user@domain.com` → contains `Tool name contains invalid characters: "@"`; `user name@domain,com` → contains `Tool name contains invalid characters: " ", "@", ","` (first-seen dedup order); `user-ñame` → contains `Tool name contains invalid characters: "ñ"`. Each asserts `valid? = #f`.
- [ ] **ADVISORY-warning set.** `get user profile` → `valid? = #f` AND warnings contains `"Tool name contains spaces, which may cause parsing issues"`; `get,user,profile` → `valid? = #f` AND warnings contains `"Tool name contains commas, which may cause parsing issues"`; `-get-user` → `valid? = #t` AND warnings contains the dash advisory; `get-user-` → `valid? = #t` + dash advisory; `.get.user` → `valid? = #t` + dot advisory; `get.user.` → `valid? = #t` + dot advisory; `.get.user.` → `valid? = #t` + dot advisory.
- [ ] **EDGE set.** `...` → `valid? = #t` + dot advisory; `---` → `valid? = #t` + dash advisory; `///` → `valid? = #f` + `Tool name contains invalid characters: "/"`; `user@name123` → `valid? = #f` + `Tool name contains invalid characters: "@"`.
- [ ] **`valid-tool-name?` predicate parity.** `(valid-tool-name? "getUser")` → `#t`; `(valid-tool-name? "")` → `#f`; `(valid-tool-name? "-get-user-")` → `#t` (advisory but valid); `(valid-tool-name? "get user profile")` → `#f`; `(valid-tool-name? (make-string 129 #\a))` → `#f`.
- [ ] **`issue-tool-name-warning` — non-empty.** `(issue-tool-name-warning "test-tool" (list "Warning 1" "Warning 2"))` emits exactly **6** log events (header + 2 warnings + 3 guidance) in order: event 0 contains `Tool name validation warning for "test-tool"`; event 1 contains `- Warning 1`; event 2 contains `- Warning 2`; event 3 contains `Tool registration will proceed, but this may cause compatibility issues.`; event 4 contains `Consider updating the tool name`; event 5 contains `See SEP: Specify Format for Tool Names`.
- [ ] **`issue-tool-name-warning` — empty.** `(issue-tool-name-warning "test-tool" '())` emits **0** log events.
- [ ] **`validate-and-warn-tool-name`.** `-get-user-` → returns `#t` AND emits (≥1 event, the dash advisory); `get-user-profile` → returns `#t` AND emits **0** events (completely clean); `get user profile` → returns `#f` AND emits (≥1 event, incl. the space advisory); `""` → returns `#f` AND emits; `(make-string 129 #\a)` → returns `#f` AND emits.
- [ ] **Warning order parity.** For `user name@domain,com` the warnings list is, in order: the space advisory, the comma advisory, the invalid-chars message (`" ", "@", ","`), then the allowed-chars message. (Asserted via `tool-name-validation-warnings` exact order, not just membership.)
- [ ] **Early-return suppression — EXACT-LIST (S1).** The length early-returns leak NO advisory/invalid warning. `(tool-name-validation-warnings (validate-tool-name ""))` is **exactly** `(list "Tool name cannot be empty")` (not just contains). And for an over-length name that ALSO carries flag characters — `(string-append (make-string 129 #\a) " ,@")` (132 chars, with a space, comma, and `@`) — `(tool-name-validation-warnings (validate-tool-name …))` is **exactly** `(list "Tool name exceeds maximum length of 128 characters (current: 132)")` — proving the `> 128` early return fires BEFORE any space/comma/invalid-char accumulation. (Without exact-list assertions a reimplementation that accumulates advisories before the length check passes every membership test yet diverges from TS.)
- [ ] **Advisory push-order — dash-before-dot (S2).** A name that triggers BOTH the dash AND the dot advisory exercises their relative order: `(tool-name-validation-warnings (validate-tool-name "-a."))` is **exactly** `(list "Tool name starts or ends with a dash, which may cause parsing issues in some contexts" "Tool name starts or ends with a dot, which may cause parsing issues in some contexts")` — dash before dot, in that order — and `(valid-tool-name? "-a.")` → `#t` (`-a.` is regex-valid: starts with dash, ends with dot, all chars in the allowed class).
- [ ] **Control-char / embedded-newline (S3).** A name containing a control character — e.g. `(string-append "get" (string #\newline) "user")` — does NOT crash and stays a single invalid-char case: `valid? = #f`, and the invalid-chars message contains the newline char wrapped in quotes (one log event when emitted, no premature line-splitting). Asserts robustness to embedded control chars.
- [ ] **Imports = base only (S1 NOT required).** The module requires only `racket/string` + `racket/list` (+ `racket/base`). It does NOT require `mcp/core/main.rkt` (no type/error used). It requires NO transport/engine/role/subprocess/socket module and **NO `net/*`**. (The transitive restricted-load proof is item 017's collection-wide sweep — not duplicated here.)
- [ ] **No `(module+ test …)` in `tool-name-validation.rkt`** — tests live in `mcp/core/shared/test/tool-name-validation-test.rkt`.
- [ ] `raco make mcp/core/shared/tool-name-validation.rkt` exits 0 (compiles clean, no warnings).
- [ ] `raco test mcp/core/shared/` passes (exit 0) — the new module + test compile and run cleanly alongside the existing `uri-template` suite (item 013). Sibling suites `raco test mcp/core/validators/` and `raco test mcp/core/util/` remain green (this item touches neither).
- [ ] Progress: flip the `tool-name-validation.rkt` deliverable line (📋 → 🚧 → ✅) AND check the Stage-S2 **Tool-name validation** acceptance box (this item owns it). The parity-matrix `toolNameValidation` row flips to `partial` in **item 017**, NOT here (see Completion Reminder).

---

## Implementation Steps

1. **Re-read the reference for shape + behaviour:** `typescript-sdk/packages/core/src/shared/toolNameValidation.ts` (the `TOOL_NAME_REGEX`, the `validateToolName` logic ORDER — length-0 early return, length>128 early return, then the four advisory pushes, then the regex test + invalid-char collection + two pushes; `issueToolNameWarning`'s header + per-warning + 3 guidance lines; `validateAndWarnToolName`'s always-warn-return-validity) and `typescript-sdk/packages/core/test/shared/toolNameValidation.test.ts` (every fixture — the `validateToolName` valid/invalid/advisory `test.each` blocks, the `issueToolNameWarning` 6-emission + 0-emission tests, the `validateAndWarnToolName` `test.each` + the space-warning test, the `edge cases and robustness` block).
2. **The return shape + logger choice are PINNED** (do not re-decide): a `(struct tool-name-validation (valid? warnings) #:transparent)` + a `valid-tool-name?` predicate; emission via `(define-logger mcp-tool-name)` and `log-mcp-tool-name-warning` (one log event per line); NO normalizer (validate-and-warn is the closest analogue); NO S1 import; NO raising.
3. **Write `mcp/core/shared/tool-name-validation.rkt`.** Use `#lang racket/base`. In order:
   - `(require racket/string racket/list)`. NO `mcp/core/main.rkt`, NO `net/*`.
   - A module-level **doc block** recording: the transliteration framing (port of TS `toolNameValidation.ts`); the SEP-986 rule (1–128, case-sensitive, `[A-Za-z0-9._-]`); the **logic order** of `validate-tool-name`; the **exact warning + guidance strings**; the **module-logger** choice + testability rationale (interceptable via `racket/logging`); the **no-normalizer** resolution of the queue's misnomer; the **code-point vs code-unit** Unicode nuance (BMP parity exact, astral divergence documented + acceptable); and the **no-S1-import / portability** note.
   - `(define MAX-TOOL-NAME-LENGTH 128)` and `(define tool-name-rx #px"^[A-Za-z0-9._-]{1,128}$")`.
   - `(define-logger mcp-tool-name)`.
   - `(struct tool-name-validation (valid? warnings) #:transparent)`.
   - Internal `valid-tool-name-char?` — a `char` predicate matching the SAME ASCII class as `tool-name-rx`: `(define (valid-tool-name-char? c) (and (regexp-match? #px"[A-Za-z0-9._-]" (string c)) #t))` (or an explicit ASCII-codepoint range check). **MUST NOT use `char-alphabetic?` / `char-numeric?`** (Unicode-aware → would skip `ñ` and empty the invalid-chars message — see the C1 PIN). And `collect-invalid-chars` (`(remove-duplicates (filter (lambda (c) (not (valid-tool-name-char? c))) (string->list name)))`).
   - **`validate-tool-name`**: port the logic ORDER exactly (length 0 → early return; length > MAX → early return with `(current: N)`; else accumulate advisory warnings in the pinned order — space, comma, dash-start/end, dot-start/end — then regex test; on fail, push the invalid-chars message (`(string-join (map (lambda (c) (format "\"~a\"" c)) chars) ", ")`) + the allowed-chars message and return `valid? = #f`; on pass return `valid? = #t` with the accumulated warnings). Build the warnings list with the pushes appended in order (a `reverse` of an accumulator, or direct `append` — ensure final order matches TS).
   - **`valid-tool-name?`**: `(tool-name-validation-valid? (validate-tool-name name))`.
   - **`issue-tool-name-warning`**: when `(pair? warnings)`, `log-mcp-tool-name-warning` the header, then each `(format "  - ~a" w)`, then the three guidance lines (one log call each). Empty → no-op.
   - **`validate-and-warn-tool-name`**: `validate-tool-name`, `issue-tool-name-warning` with the result's warnings, return `valid?`.
   - The explicit `(provide (struct-out tool-name-validation) validate-tool-name valid-tool-name? issue-tool-name-warning validate-and-warn-tool-name)` block (NOT the internal helpers or the logger).
4. **Write the test** `mcp/core/shared/test/tool-name-validation-test.rkt` (see Testing Strategy). Port EVERY fixture group 1:1 (Parts 1–4 below), assert the struct fields (`valid?` + warnings membership AND, for the multi-char case, exact order), the predicate, the logger emission count/order/content via `with-intercepted-logging`, and the empty-warnings no-op.
5. **Run** `raco make mcp/core/shared/tool-name-validation.rkt` then `raco test mcp/core/shared/`. Fix any failure. Confirm `raco test mcp/core/validators/` and `raco test mcp/core/util/` still pass (untouched).
6. **Update progress + parity matrix** (see Completion Reminder).

---

## Testing Strategy

The test is a **fixture-port table test**: it ports each `toolNameValidation.test.ts` fixture 1:1, asserting the SAME `valid?` / warning behaviour the TS suite asserts (G1 parity), plus the logger-emission count/order/content (TS asserts via a `console.warn` spy; the Racket port asserts via a `racket/logging` interceptor), and the empty-warnings no-op.

**Test file:** `mcp/core/shared/test/tool-name-validation-test.rkt` (`#lang racket/base`; `(require rackunit racket/string racket/list racket/logging (file "../tool-name-validation.rkt"))`). No `json` needed (names are strings; the result is a struct). `racket/logging` provides `with-intercepted-logging` for the emission assertions.

Small helpers keep assertions terse:
```racket
;; (valid? name)    -> boolean  ; the struct's valid? field
;; (warns name)     -> (listof string)  ; the struct's warnings
(define (valid? n) (tool-name-validation-valid? (validate-tool-name n)))
(define (warns  n) (tool-name-validation-warnings (validate-tool-name n)))
(define (has-warning? n msg) (and (member msg (warns n)) #t))
;; (capture-warnings thunk) -> (listof string) ; the ordered emitted log messages
(define (capture-warnings thunk)
  (define out '())
  (with-intercepted-logging
    (lambda (l) (set! out (cons (vector-ref l 1) out)))  ; vector-ref 1 = message string
    thunk
    #:logger (current-logger) 'warning 'mcp-tool-name)
  (reverse out))
```
(The executor confirms the exact `with-intercepted-logging` arity/signature against the installed Racket version — the interceptor receives a log vector `#(level message data topic)`, so `(vector-ref l 1)` is the formatted message string. Filter on the `mcp-tool-name` topic so unrelated log events do not pollute the count.)

### Part 1 — `validateToolName` valid set

For each of `getUser`, `get_user_profile`, `user-profile-update`, `admin.tools.list`, `DATA_EXPORT_v2.1`, `a`, `(make-string 128 #\a)`: `(check-true (valid? n))` AND `(check-true (null? (warns n)))`. (Ports `validateToolName › valid tool names`.)

### Part 2 — `validateToolName` invalid + advisory sets

- **Invalid (`valid? = #f` + expected-warning membership):** `""` / `(make-string 129 #\a)` / `get user profile` / `get,user,profile` / `user/profile/update` / `user@domain.com` / `user name@domain,com` / `user-ñame` — each `(check-false (valid? n))` AND `(check-true (has-warning? n <expected>))` per the criteria table. (Ports `validateToolName › invalid tool names`.)
- **Multi-char invalid order (PINNED):** `(check-true (has-warning? "user name@domain,com" "Tool name contains invalid characters: \" \", \"@\", \",\""))` — first-seen dedup order space/`@`/comma.
- **Advisory (`valid?` per fixture + warning membership):** `get user profile` (`#f`, space advisory), `get,user,profile` (`#f`, comma advisory), `-get-user` (`#t`, dash advisory), `get-user-` (`#t`, dash advisory), `.get.user` (`#t`, dot advisory), `get.user.` (`#t`, dot advisory), `.get.user.` (`#t`, dot advisory). (Ports `validateToolName › warnings for potentially problematic patterns`.)
- **Warning-order parity:** `(check-equal? (warns "user name@domain,com") (list "Tool name contains spaces, which may cause parsing issues" "Tool name contains commas, which may cause parsing issues" "Tool name contains invalid characters: \" \", \"@\", \",\"" "Allowed characters are: A-Z, a-z, 0-9, underscore (_), dash (-), and dot (.)"))` — pins the exact accumulation order.
- **C1 — `ñ` invalid-char message is NON-EMPTY:** `(check-true (has-warning? "user-ñame" "Tool name contains invalid characters: \"ñ\""))` — directly catches a `char-alphabetic?`-based predicate (which would skip `ñ` and emit `Tool name contains invalid characters: ` with an empty list). Pair with `(check-false (valid? "user-ñame"))`.
- **S1 — early-return suppression (EXACT-LIST):** `(check-equal? (warns "") (list "Tool name cannot be empty"))` — the empty case carries ONLY that one warning. And for an over-length name that also carries flag chars: `(check-equal? (warns (string-append (make-string 129 #\a) " ,@")) (list "Tool name exceeds maximum length of 128 characters (current: 132)"))` — the `> 128` early return fires BEFORE any space/comma/invalid-char accumulation, so the list is EXACTLY the length message (132 chars), with no advisory or invalid-char warning leaking. (Membership tests alone would not catch an implementation that accumulates advisories before the length check.)
- **S2 — dash-before-dot push order:** `(check-equal? (warns "-a.") (list "Tool name starts or ends with a dash, which may cause parsing issues in some contexts" "Tool name starts or ends with a dot, which may cause parsing issues in some contexts"))` — both advisories present, dash before dot. `(check-true (valid? "-a."))` (regex-valid: `-a.` is all allowed chars).

### Part 3 — Edge cases + `valid-tool-name?`

- **Edge (ports `edge cases and robustness`):** `...` (`#t`, dot advisory), `---` (`#t`, dash advisory), `///` (`#f`, `"/"` invalid-chars), `user@name123` (`#f`, `"@"` invalid-chars).
- **`valid-tool-name?` predicate:** `getUser`→`#t`, `""`→`#f`, `-get-user-`→`#t`, `get user profile`→`#f`, `(make-string 129 #\a)`→`#f`.
- **(Optional) astral-char nuance:** if included, assert the Racket code-point behaviour for one astral char and comment that it diverges from JS `.length` by design (not required by any TS fixture).

### Part 4 — `issueToolNameWarning` + `validateAndWarnToolName` emission

- **6-emission (ports `issueToolNameWarning › should output warnings to console.warn`):**
  ```racket
  (define ev (capture-warnings (lambda () (issue-tool-name-warning "test-tool" (list "Warning 1" "Warning 2")))))
  (check-equal? (length ev) 6)
  (check-true (string-contains? (list-ref ev 0) "Tool name validation warning for \"test-tool\""))
  (check-true (string-contains? (list-ref ev 1) "- Warning 1"))
  (check-true (string-contains? (list-ref ev 2) "- Warning 2"))
  (check-true (string-contains? (list-ref ev 3) "Tool registration will proceed, but this may cause compatibility issues."))
  (check-true (string-contains? (list-ref ev 4) "Consider updating the tool name"))
  (check-true (string-contains? (list-ref ev 5) "See SEP: Specify Format for Tool Names"))
  ```
- **0-emission (ports `issueToolNameWarning › should handle empty warnings array`):** `(check-equal? (length (capture-warnings (lambda () (issue-tool-name-warning "test-tool" '())))) 0)`.
- **`validateAndWarnToolName` (ports `validateAndWarnToolName › test.each`):** for each row assert BOTH the boolean return AND whether anything was emitted:
  - `-get-user-` → return `#t`, emitted `> 0`.
  - `get-user-profile` → return `#t`, emitted `= 0` (completely clean).
  - `get user profile` → return `#f`, emitted `> 0`.
  - `""` → return `#f`, emitted `> 0`.
  - `(make-string 129 #\a)` → return `#f`, emitted `> 0`.
  Pattern: `(define-values (ret ev) (let ([e '()]) (define r (with-intercepted-logging … (lambda () (validate-and-warn-tool-name n)) …)) (values r e)))` — capture both the return value and the emitted events. (Adapt `capture-warnings` to also thread the return, or run the call once for the return and once under interception; running twice is acceptable since the function is pure aside from logging.)
- **Space-warning-through-warn (ports `validateAndWarnToolName › should include space warning…`):** capture the emissions for `get user profile` and assert one event contains `Tool name contains spaces`.

> **S5 — captured log lines are topic-prefixed.** The `capture-warnings` helper returns lines like `"mcp-tool-name: Tool name validation warning for \"test-tool\":"` (the logger prepends the topic). The Part-4 assertions above use `string-contains?`, which is robust to that prefix. **Do NOT rewrite them as `check-equal?` against the raw expected line** — they would fail on the `mcp-tool-name: ` prefix. (`check-equal?` is correct ONLY for the struct-field `warns` assertions in Parts 2/5, which carry NO topic prefix.)

### Part 5 — Robustness: control chars / embedded newline (S3)

- **Embedded newline stays one invalid-char case:** `(let ([n (string-append "get" (string #\newline) "user")]) (check-false (valid? n)) (check-true (has-warning? n (format "Tool name contains invalid characters: \"~a\"" #\newline))))` — a control char (newline) is collected as an invalid char (not a crash, not a premature line-split); `valid? = #f`. (The newline is NOT in `[A-Za-z0-9._-]`, so it is rejected and reported like any other invalid char.)
- **Emission stays one event per warning even with an embedded newline in the name:** `(check-true (>= (length (capture-warnings (lambda () (validate-and-warn-tool-name (string-append "get" (string #\newline) "user"))))) 1))` — the name's newline does not split a single `log-mcp-tool-name-warning` call into extra events (the count is `1 + N + 3`, unaffected by chars inside `name`).
- **(Non-string domain — S3/S4):** the "never raises" guarantee is scoped to strings. Optionally assert the documented contract: if option (b) (a `string?` guard) was chosen, `(check-equal? (warns 42) (list "Tool name must be a string"))` (or whatever the guard returns); if option (a) (document-only) was chosen, NO test is required (a non-string is a caller contract violation, matching TS's static `name: string`). Do not assert a graceful result the implementation did not commit to.

### Fixture → ported-test mapping (1:1, the G1 contract)

| TS `describe`/`it` group | Fixtures | Ported Racket part |
|---|---|---|
| `validateToolName › valid tool names` | `getUser`, `get_user_profile`, `user-profile-update`, `admin.tools.list`, `DATA_EXPORT_v2.1`, `a`, `a×128` | Part 1 |
| `validateToolName › invalid tool names` | `''`, `a×129`, `get user profile`, `get,user,profile`, `user/profile/update`, `user@domain.com`, `user name@domain,com`, `user-ñame` | Part 2 (invalid set + multi-char order) |
| `validateToolName › warnings for potentially problematic patterns` | `get user profile`, `get,user,profile`, `-get-user`, `get-user-`, `.get.user`, `get.user.`, `.get.user.` | Part 2 (advisory set + order) |
| `issueToolNameWarning` | 6-emission (`['Warning 1','Warning 2']`); 0-emission (`[]`) | Part 4 |
| `validateAndWarnToolName` | `-get-user-`, `get-user-profile`, `get user profile`, `''`, `a×129`; + space-warning test | Part 4 |
| `edge cases and robustness` | `...`, `---`, `///`, `user@name123` | Part 3 |
| (net-new coverage, not a TS group) | early-return suppression (`""`, `a×129 + " ,@"`) — S1; dash-before-dot order (`-a.`) — S2; `ñ` non-empty message — C1; embedded newline / non-string domain — S3/S4 | Parts 2, 5 |

> **`tool-name-validation.rkt` MUST NOT define a `(module+ test …)` submodule** — tests live in the separate `test/tool-name-validation-test.rkt` (consistent with items 010/011/012/013). This keeps `rackunit`/`racket/logging` out of the module's import closure (relevant to item 017's portability sweep).

> **Restricted-load portability is NOT tested here.** Item 013 added a per-module `module->imports` walk because its hand-rolled encoders risked reaching for `net/url`; M5b has no such risk (it touches no I/O or encoding). The collection-wide S2 restricted-load sweep — which includes `tool-name-validation.rkt` — is **item 017**. This item's portability obligation is satisfied by (a) the S1-not-required / no-`net/*` import discipline above and (b) item 017's sweep. Do not duplicate the walk.

---

## Dependencies

- **Upstream work items:**
  - **None functionally required.** Unlike its S2 siblings, M5b imports **no S1 binding** (no type, no error) — it is a self-contained string/predicate module over `racket/string` + `racket/list`. The only structural dependency is that item 013 **created the `mcp/core/shared/` + `mcp/core/shared/test/` collection directories**, into which this module + its test are added.
- **Downstream consumers (informational):**
  - **S6b** high-level server (`mcp/server/mcp.rkt`, M12b) — the `register-tool` surface calls `validate-and-warn-tool-name` (or `validate-tool-name` + its own emission) to warn-but-proceed on a non-conforming tool name at registration time. **This module has NO consumer inside S2** — it ships fully tested standalone and is wired up by S6b.
  - **Item 017** — the S2 collection-wide restricted-load portability sweep includes `mcp/core/shared/tool-name-validation.rkt`, AND flips the parity-matrix `toolNameValidation` row to `partial`. (This item does NOT flip that row.)
  - **Item 018** — the S2 demo MAY exercise tool-name validation (optional; the demo headline is schema + URI template + stdio).
- **Tooling/runtime:** Racket ≥ 8.x (`raco`, `rackunit`, `racket/logging`). The `typescript-sdk/` checkout MUST be present for **authoring** — the behaviour and fixtures are lifted from `shared/toolNameValidation.ts` + `test/shared/toolNameValidation.test.ts`. The Racket test does NOT parse the `.ts` at runtime (fixtures are transcribed into Racket assertions), so a missing checkout would not break the running test but would make the fixture-port un-reproducible.

---

## Decisions & Trade-offs

To be updated during implementation.

The **design decisions below are PINNED at spec time** (real choices, not options). The **post-build outcome** (require list as built, exact check count, the `with-intercepted-logging` signature used) is *to be updated during implementation*.

**(a) Return shape = struct `(tool-name-validation valid? warnings)` + `valid-tool-name?` predicate.** Reconciles the queue's `valid-tool-name?`-style predicate with TS's richer `{isValid, warnings}` return by exposing BOTH — the struct carries the advisory warnings a valid-but-suspicious name needs; the predicate is the terse accept/reject. Struct is `#:transparent` so `check-equal?` works and accessors are `provide`d via `struct-out`. **To be updated during implementation.**

**(b) The queue's "normalizer" is a misnomer — there is NO normalizer.** TS `toolNameValidation.ts` never mutates the name; the closest analogue is `validate-and-warn-tool-name` (validate + emit + boolean). The executor MUST NOT invent a name-mutating transform — it would have no TS counterpart and would break G1 parity. Resolved + pinned so the discrepancy is not silently filled with a fabricated function. **To be updated during implementation.**

**(c) Warning emission via a module logger (`define-logger mcp-tool-name`), not `eprintf`.** Racket has no `console.warn`; the logger is chosen because its output is observably interceptable via `racket/logging`'s `with-intercepted-logging` (or a `make-log-receiver`), which is exactly how the test asserts the 6-event emission count + order + content. One log event per line (NOT a coalesced multi-line message) so the count parity (`1 + N + 3`) holds. **To be updated during implementation** (record the exact interceptor signature used).

**(d) No `raise`, no S1 import.** Every function returns / emits; none raises (an empty/over-length/illegal name is a `valid? = #f` result, not an exception). The module uses no M1 type and no M2 error, so it does NOT `(require "../main.rkt")` — it is base-collections-only (`racket/string` + `racket/list`). The no-`net/*`/no-subprocess/no-socket portability invariant holds regardless and is proven by item 017's collection-wide sweep. **To be updated during implementation** (confirm the require list as built).

**(e) Code points, not code units (Unicode parity nuance).** Racket `string-length`/`string->list` count code points; JS `.length` counts UTF-16 code units (astral char = 2) while `[...name]` iterates code points. For the BMP (every fixture char, incl. `ñ`) the counts are identical → exact parity. The astral-plane divergence (Racket more consistent/correct) is documented as a known, acceptable nuance not exercised by any fixture and not reachable through the `[A-Za-z0-9._-]` rule. **To be updated during implementation.**

**(e2) `valid-tool-name-char?` derives from the SAME ASCII class as `tool-name-rx`; `char-alphabetic?` / `char-numeric?` FORBIDDEN (C1, CRITICAL).** One source of truth for the allowed set: `[A-Za-z0-9._-]`. The per-char predicate (used to collect the invalid-chars message) MUST be `(regexp-match? #px"[A-Za-z0-9._-]" (string c))` or an explicit ASCII range check — NOT Racket's Unicode-aware `char-alphabetic?`/`char-numeric?`, which return `#t` for `ñ` and non-ASCII digits and would empty the invalid-chars message (silently breaking the `"ñ"` fixture even though `valid?` stays `#f` via the ASCII regex). The pass/fail regex and the message predicate MUST agree on the same character set. Pinned + caught by the `ñ` exact-message test. **To be updated during implementation.**

**(e3) Input domain = `string?`; "no raising" is scoped to strings (S3/S4).** The graceful "never raises" guarantee holds only for string inputs; a non-string (e.g. `42`) raises a `string-length`/`string->list` contract error, not a `valid? = #f` result. The executor MUST either (a) document the `string?` domain and let the contract error surface (recommended — matches TS's static `name: string`), or (b) add a `string?` guard returning a clean invalid result. Given the S6b `register-tool` caller, the contract is stated explicitly so callers know non-strings are out of domain. **To be updated during implementation** (record which option shipped).

**(f) Exact warning + guidance strings + push order ported verbatim.** The eight warning strings and three guidance lines are copied byte-for-byte from TS (they are part of the G1 contract — the TS tests assert substring membership; the Racket test also asserts exact accumulation order for the multi-warning `user name@domain,com` case). **To be updated during implementation.**

**(g) Restricted-load portability deferred to item 017.** No per-module `module->imports` walk here (M5b has no encoder/`net/url` risk like item 013 did); the collection-wide S2 sweep including `tool-name-validation.rkt` is item 017, which also flips the parity-matrix row. **To be updated during implementation.**

**(h) Post-build outcomes (recorded at implementation).**
- **Require list as built:** module = `(require racket/string racket/list)` — base only, NO `net/*`, NO `../main.rkt`. Test adds `rackunit` + `racket/logging` (plus `racket/string` + `racket/list`).
- **Exact check count:** `raco test mcp/core/shared/` → **192 tests passed** (84 new tool-name checks + 108 existing uri-template checks). New suite alone (`raco test mcp/core/shared/test/tool-name-validation-test.rkt`) = **84 tests passed**. Sibling suites unaffected: `raco test mcp/core/validators/` → **300 tests passed**; `raco test mcp/core/util/` → **102 tests passed** (both still exit 0).
- **`raco make`:** `raco make mcp/core/shared/tool-name-validation.rkt` → exit 0, clean (no warnings).
- **`with-intercepted-logging` signature used:** `(with-intercepted-logging interceptor thunk #:logger (current-logger) 'warning 'mcp-tool-name)` — interceptor receives the log vector `#(level message data topic)`; `(vector-ref l 1)` is the formatted (topic-prefixed) message string. Topic-filtered on `'mcp-tool-name` so unrelated events do not pollute the count.
- **Input domain:** option (a) shipped — documented `string?` domain in the module doc block; non-strings surface a base-op contract error (no `string?` guard added, no silent coercion). No non-string test asserted.
- **No `(module+ test …)`** in `tool-name-validation.rkt` (confirmed); tests live in `test/tool-name-validation-test.rkt`.

---

## Project-Specific Adaptations (Racket / raco / rackunit)

This is a **Racket library, not a service** — same adaptation pattern as items 010/011/012/013. The generic "Testing Prerequisites" template (Required Services / database / API endpoint / ports / health checks) does **not** apply and is adapted as follows (documented explicitly per the create-item skill):

- **Required Services → None.** Pure Racket library; no external services, databases, message queues, HTTP servers, sockets, subprocesses, or network. The module is L0 and load-portable by construction (proven by item 017's collection-wide sweep). **Note:** no I/O at all — warnings emit to a module logger (in-process, interceptable), not to a socket/file.
- **Database / API endpoint / ports sections → N/A.** Removed; replaced by the Racket toolchain row below.
- **Required toolchain:** Racket ≥ 8.x (`raco test`, `rackunit`, `racket/logging`). (This env: Racket v8.18 [cs], per item 013.)
- **TS checkout role:** present at `typescript-sdk/`; **required for authoring** (behaviour from `shared/toolNameValidation.ts`; fixtures from `test/shared/toolNameValidation.test.ts`, transcribed into Racket assertions — a fixture-parity item).
- **Manual Validation Checklist → specialized** to `raco make` / `raco test` + a REPL validate/warn smoke check (below). No "service started" / "health check" / "screenshots" rows — replaced with N/A or removed.
- **Language/naming:** `#lang racket/base`; kebab-case bindings; explicit `(provide …)` never `all-defined-out` (architecture §1.3); base-collections-only imports, no S1 import (architecture §4.1 portability still honored).
- **Collection directory:** `mcp/core/shared/` + `mcp/core/shared/test/` already exist (created by item 013). This item adds `tool-name-validation.rkt` + `test/tool-name-validation-test.rkt`.
- **No-consumer-in-S2 note:** like item 013, this M5b module has NO S2 consumer; it ships fully tested standalone and is wired up by S6b.

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None (pure Racket library; no external services).** No databases, message queues, HTTP servers, sockets, subprocesses, or network dependencies. Warnings emit to an in-process module logger.

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime | compile + run module and tests (`raco`, `rackunit`, `racket/logging`) | system install (`racket --version` ≥ 8.0; this env: v8.18) | n/a |
| `typescript-sdk/` checkout | read while authoring to lift behaviour from `shared/toolNameValidation.ts` and the fixtures from `test/shared/toolNameValidation.test.ts` (G1 fixture parity) | already present at repo root | n/a |

### Environment Configuration

- **Environment variables / secrets / config files / free ports:** none required.
- **Racket version:** ≥ 8.x (verified for item 013: v8.18 [cs]).
- **Working directory:** run `raco test` from the **repo root** so the `mcp/...` collection path resolves.
- **How to run the tests:**
  - `raco make mcp/core/shared/tool-name-validation.rkt` — compile the module clean.
  - `raco test mcp/core/shared/` — run all shared-collection tests (picks up `test/tool-name-validation-test.rkt` + the existing `test/uri-template-test.rkt` recursively), exit 0.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0.
  - `raco test mcp/core/shared/` (pre-change) → green (item 013's 108 checks pass) so the baseline is known.

### Manual Validation Checklist

*(Not yet built — leave UNCHECKED until implementation completes.)*

- [ ] **Build/compile succeeds:** `raco make mcp/core/shared/tool-name-validation.rkt` compiles with no errors/warnings.
- [ ] **Module loads in isolation:** `racket -e '(require (file "mcp/core/shared/tool-name-validation.rkt"))'` from repo root succeeds.
- [ ] **Tests pass:** `raco test mcp/core/shared/test/tool-name-validation-test.rkt` → all checks pass, exit 0.
- [ ] **Collection tests pass:** `raco test mcp/core/shared/` → exit 0 (new suite + item 013's uri-template suite).
- [ ] **M3/M4 untouched:** `raco test mcp/core/validators/` AND `raco test mcp/core/util/` → still exit 0 (this item modifies neither).
- [ ] **Services started:** N/A (no services — pure library).
- [ ] **Application runs:** N/A (library; "running" = the require + REPL validate/warn smoke check below).
- [ ] **Feature verified (REPL smoke check):** from repo root —
      `racket -e '(require (file "mcp/core/shared/tool-name-validation.rkt")) (list (valid-tool-name? "getUser") (valid-tool-name? "get user profile") (tool-name-validation-warnings (validate-tool-name "-get-user-")))'`
      prints `(#t #f ("Tool name starts or ends with a dash, which may cause parsing issues in some contexts"))`. (Record exact transcript in Validation Results.)
- [ ] **VALID set verified:** `getUser`/`get_user_profile`/`user-profile-update`/`admin.tools.list`/`DATA_EXPORT_v2.1`/`a`/`a×128` → `valid? = #t`, warnings empty.
- [ ] **INVALID set verified:** `''`→empty msg; `a×129`→length msg `(current: 129)`; space/comma/slash/`@`/multi-char/`ñ` → `valid? = #f` + correct invalid-chars message (multi-char in first-seen order `" ", "@", ","`).
- [ ] **ADVISORY set verified:** `-get-user`/`get-user-`/`.get.user`/`get.user.`/`.get.user.` → `valid? = #t` + dash/dot advisory; `get user profile`/`get,user,profile` → `valid? = #f` + space/comma advisory.
- [ ] **EDGE set verified:** `...`(`#t`,dot)/`---`(`#t`,dash)/`///`(`#f`,`"/"`)/`user@name123`(`#f`,`"@"`).
- [ ] **Warning-order verified:** `user name@domain,com` warnings = space, comma, invalid-chars, allowed-chars (exact order).
- [ ] **C1 — `ñ` message non-empty verified:** `user-ñame` → invalid-chars message is `Tool name contains invalid characters: "ñ"` (NOT empty); predicate is NOT `char-alphabetic?`/`char-numeric?`.
- [ ] **S1 — early-return suppression verified (exact list):** `warns("")` = `(list "Tool name cannot be empty")`; `warns(a×129 + " ,@")` = `(list "Tool name exceeds maximum length of 128 characters (current: 132)")` — no advisory/invalid warning leaks past the length early return.
- [ ] **S2 — dash-before-dot order verified:** `warns("-a.")` = (dash advisory, dot advisory) in that order; `valid? = #t`.
- [ ] **S3 — control-char robustness verified:** an embedded newline name → `valid? = #f`, newline reported as an invalid char, emission count unaffected (1+N+3).
- [ ] **S3/S4 — input domain verified:** non-string handling matches the committed option ((a) documented `string?` domain / contract error, or (b) `string?` guard returning a clean invalid result); "no raising" claim scoped to strings.
- [ ] **`valid-tool-name?` verified:** `getUser`→#t; `""`→#f; `-get-user-`→#t; `get user profile`→#f; `a×129`→#f.
- [ ] **`issue-tool-name-warning` verified:** 2 warnings → 6 ordered log events (header + 2 + 3 guidance); `'()` → 0 events.
- [ ] **`validate-and-warn-tool-name` verified:** `-get-user-`→#t+emits; `get-user-profile`→#t+0 emits; `get user profile`→#f+emits; `''`→#f+emits; `a×129`→#f+emits.
- [ ] **Exact warning + guidance strings verified:** byte-for-byte match to TS (no rewording).
- [ ] **No raising verified (string inputs):** no STRING input (empty/over-length/illegal) raises — all return a struct/boolean. (Non-string is out of domain — see S3/S4 row.)
- [ ] **No `(module+ test …)` in `tool-name-validation.rkt` confirmed:** tests live in `test/tool-name-validation-test.rkt`.
- [ ] **S1-not-required / imports confirmed:** require list = `racket/string` + `racket/list` (NO `../main.rkt`, NO `net/*`).
- [ ] **Health checks pass:** N/A (no running service).

### Expected Outcomes

Concrete, verifiable:

- The module **exports** the `tool-name-validation` struct + `validate-tool-name` / `valid-tool-name?` / `issue-tool-name-warning` / `validate-and-warn-tool-name` (and NO internal helpers). `(valid-tool-name? "getUser")` → `#t`; `(valid-tool-name? "get user profile")` → `#f`.
- Every `toolNameValidation.test.ts` fixture has a ported Racket assertion producing the **same `valid?` / warning / emission** result the TS suite asserts (G1 parity) — the full VALID(7) + INVALID(8) + ADVISORY(7) + EDGE(4) sets, the `issueToolNameWarning` 6-event + 0-event tests, and the `validateAndWarnToolName` 5-row + space-warning tests.
- A **non-conforming (string) name** yields **`valid? = #f` with warnings** (never a raise); an **advisory-valid** name yields **`valid? = #t` with non-empty warnings**; a **clean** name yields **`valid? = #t` with empty warnings**. (The no-raise guarantee is scoped to `string?` inputs — S3/S4.)
- `issue-tool-name-warning` emits **`1 + N + 3`** ordered log events for `N` non-empty warnings, **0** for empty.
- The module requires **only base collections** (`racket/string` + `racket/list`) — NO S1 import, NO `net/*` (the transitive restricted-load proof is item 017's sweep).
- `raco test mcp/core/shared/` reports all checks passing, 0 failures, 0 errors; `raco test mcp/core/validators/` and `raco test mcp/core/util/` still green (M3/M4 untouched).

### Validation Results

```markdown
## Validation Results
- [x] Service started: N/A (pure Racket library, no services)
- [x] Application started successfully: N/A (library; `require` + validate/warn smoke check ran)
- [x] Build verified: `raco make mcp/core/shared/tool-name-validation.rkt` clean (exit 0, no warnings)
- [x] Module load verified: `(require (file ".../tool-name-validation.rkt"))` succeeds. Smoke transcript:
      `racket -e '… (list (valid-tool-name? "getUser") (valid-tool-name? "get user profile") (tool-name-validation-warnings (validate-tool-name "-get-user-")))'`
      → `'(#t #f ("Tool name starts or ends with a dash, which may cause parsing issues in some contexts"))`
- [x] Tests verified: `raco test mcp/core/shared/` → 192 tests passed, 0 failures, 0 errors (84 new tool-name + 108 uri-template)
- [x] M3/M4 untouched: `raco test mcp/core/validators/` → 300 passed; `raco test mcp/core/util/` → 102 passed (both exit 0)
- [x] VALID set verified: 7 names → valid? #t, warnings empty
- [x] INVALID set verified: 8 names → valid? #f + correct invalid-chars/length/empty message (multi-char order " ", "@", ",")
- [x] ADVISORY set verified: dash/dot advisories valid; space/comma invalid
- [x] EDGE set verified: ... / --- / /// / user@name123
- [x] Warning-order verified: user name@domain,com → space, comma, invalid-chars, allowed-chars
- [x] C1 ñ message non-empty verified: user-ñame → invalid-chars message "ñ" (predicate is ASCII-class regexp-match?, NOT char-alphabetic?/char-numeric?)
- [x] S1 early-return suppression verified (exact list): warns("")=(empty msg only); warns(a×129+" ,@")=(length msg current:132 only)
- [x] S2 dash-before-dot order verified: warns("-a.")=(dash, dot) in order; valid? #t
- [x] S3 control-char robustness verified: embedded newline → valid? #f, newline reported as invalid char, emission count 1+N+3
- [x] S3/S4 input domain verified: option (a) shipped — documented string? domain, no guard; no-raise scoped to strings
- [x] valid-tool-name? verified: getUser #t; "" #f; -get-user- #t; get user profile #f; a×129 #f
- [x] issue-tool-name-warning verified: 2 warnings → 6 ordered events; '() → 0 events
- [x] validate-and-warn-tool-name verified: -get-user- #t+emits; get-user-profile #t+0; get user profile #f+emits; "" #f+emits; a×129 #f+emits
- [x] Exact warning + guidance strings verified (byte-for-byte vs TS); captured log lines asserted with string-contains? (topic-prefixed), struct warnings with check-equal?
- [x] No raising verified (string inputs): no string input raises (non-string out of domain)
- [x] No (module+ test …) in tool-name-validation.rkt confirmed (tests in test/tool-name-validation-test.rkt)
- [x] S1-not-required / imports confirmed: racket/string + racket/list (no ../main.rkt, no net/*)
- [x] Database tables verified: N/A
- [x] Seed data verified: N/A
- [x] API endpoints verified: N/A
- [x] Screenshots captured: N/A (no UI)
```

---

## Completion Reminder

On completion, the implementer MUST update **`docs/aide/progress.md`** (Stage S2 section), advancing the icon **📋 → 🚧 → ✅**:

1. Flip the deliverable line **`📋 mcp/core/shared/tool-name-validation.rkt (M5b)`** from 📋 → 🚧 (on start) → ✅ (on delivery + all acceptance criteria pass). Add a one-line summary mirroring item 013's deliverable-line style (e.g. `(item 014: TS toolNameValidation.ts transliteration — validate-tool-name struct + valid-tool-name? predicate + issue-tool-name-warning (module logger) + validate-and-warn-tool-name; SEP-986 1–128 + [A-Za-z0-9._-]; advisory vs invalid distinction; first-seen invalid-char dedup; no normalizer (TS has none); base-collections-only, no S1 import. raco test mcp/core/shared/ → <N> checks pass)`). Never revert an icon backward.
2. **Check the Stage-S2 Tool-name acceptance box** — **`[ ] Tool-name validation matches TS toolNameValidation accept/reject set`**. **This box belongs to THIS item** (it owns the tool-name deliverable). Check it on delivery.
3. Do **not** check the other broad Stage-S2 acceptance boxes that depend on sibling items (`raco test over all S2 modules`, stdio-framing, the parity-rows box, the demo box belong to items 015–018). The `URI template`, `Schema normalization`, and `Validator keyword coverage` boxes are already checked (items 010/011/012/013) — leave them.
4. **Parity matrix:** **do NOT flip the `toolNameValidation` row here.** Per Stage S2 discipline, that row advances to `partial` in **item 017** (the collection-wide restricted-load sweep + parity-matrix touch), alongside `validators/*`, `util/schema`, `uriTemplate`, `metadataUtils`, and `auth`. This item delivers the module + its test only; item 017 records the parity-matrix progression.
5. Leave all other S2 deliverable lines (`validators/*` ✅; `util/schema.rkt` ✅; `uri-template.rkt` ✅; the other `shared/*` utils — M5c–M5e — still 📋) at their current status — this item delivers only `tool-name-validation.rkt` + its test into the existing `mcp/core/shared/` collection.
