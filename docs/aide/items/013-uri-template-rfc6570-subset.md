# Work Item 013: URI templates — RFC 6570 subset (M5a)

> **Queue:** `docs/aide/queue/queue-002.md` — Item 013
> **Stage:** S2 (Foundation: validators, schema, shared utilities — L0 part 2)
> **Module:** M5a (URI templates) — `mcp/core/shared/uri-template.rkt`. The RFC 6570 (subset) URI-template engine used by MCP **resource templates**. It provides `expand(template, vars) → uri` (fill a template's expressions from a variable map) and `match(template, uri) → vars` (recover the variables a URI binds for a template). It is consumed by the high-level server's resource-template surface (S6b, M12b: `register-resource` templated form). It has **NO consumer inside S2** — it is built ahead of its consumer.
> **Source vision:** `docs/aide/vision.md` §6 (Portability NFR — core L0–L2 loads without subprocess/socket; this is a pure non-I/O string module), G1 (wire/behaviour parity with the TS SDK — the expand/match results must match TS `UriTemplate` for the ported fixtures).
> **Source roadmap:** `docs/aide/roadmap.md` Stage S2 → Deliverables line (`mcp/core/shared/uri-template.rkt` (M5a) — RFC 6570 subset expand/match) + Testing/validation criterion (`URI template expand/match round-trips TS uriTemplate.test.ts fixtures (G1)`).
> **Source architecture:** `docs/aide/architecture.md` M5a (shared util; depends on S1 only), §1.3 (public/internal boundary, curated `main.rkt`, explicit `provide`), §4.1 (Runtime-neutral core L0–L2 import no subprocess/socket).
> **Reference impl (authoritative):** MCP TypeScript SDK v2 at `typescript-sdk/` — `packages/core/src/shared/uriTemplate.ts` (the `UriTemplate` class: `isTemplate`, `parse`, `expand`, `match`, `variableNames`, and the per-operator expand/regex tables) and `packages/core/test/shared/uriTemplate.test.ts` (the fixture suite this item ports 1:1). **Framing:** this is a near-direct **transliteration** of `uriTemplate.ts` into idiomatic Racket — same operator set, same expand semantics, same regex-based match semantics, same edge-case behaviour. Unlike item 012 (where input forms were net-new), here both the inputs and the outputs are ported as-is; the only adaptation is Racket naming/data shapes (a `hash` of variables instead of a JS object, kebab-case function names, multiple-values or `#f` for no-match).
> **Status:** ✅ Complete — delivered 2026-06-23 (108 checks pass, 0 fail; portability + ReDoS verified).

---

## Description

Implement `mcp/core/shared/uri-template.rkt`, the **URI-template engine** for `racket-mcp`. Given a URI template string carrying RFC 6570 expressions (e.g. `http://example.com/users/{username}`, `/search{?q,limit}`, `{/list*}`), it provides two operations:

1. **`uri-template-expand`** — `(uri-template-expand template vars) → uri-string`. Substitutes a variable map into the template's expressions, applying the per-operator prefix/separator/encoding rules, producing a concrete URI string.
2. **`uri-template-match`** — `(uri-template-match template uri) → vars-or-no-match`. Compiles the template to a regular expression and matches the given URI against it, recovering the variable bindings (a `hash` of name→value, where an exploded variable yields a list of strings). Returns a clear **no-match** result (see below) when the URI does not fit the template.

This is a **subset** of RFC 6570 — specifically the operators and forms the TS `UriTemplate` implementation actually exercises (enumerated below). It is **NOT** a full Level-4 RFC 6570 implementation; do **not** over-claim. The build target is **byte-for-byte parity with the TS results** for the ported fixtures (vision goal **G1**): every fixture in `uriTemplate.test.ts` maps to a Racket test case asserting the same `expand`/`match` output.

### Framing — direct transliteration of `uriTemplate.ts` (read carefully)

The TS source is a single `UriTemplate` class. This item ports its behaviour, not its OO shape. The mapping by role:

| TS member | Role | Racket analogue |
|---|---|---|
| `new UriTemplate(template)` + `parse()` | parse the template string into a list of literal-text parts and expression parts (each expr: `{name, operator, names, exploded}`) | an internal `parse-template` returning a list of parts; OR a parsed-template value (see "Surface decision" below) |
| `expand(variables)` | fill the parts from the variable map, applying per-operator rules | `uri-template-expand` |
| `match(uri)` | build a regex from the parts, match the URI, recover variables (or `null`) | `uri-template-match` |
| `variableNames` getter | the list of variable names the template references | `uri-template-variables` (a public accessor — see Scope) |
| `isTemplate(str)` (static) | does a string contain any non-empty template expression? | `uri-template?` (a public predicate) |
| `toString()` | the original template string | not separately exposed (the caller holds the string) |

The TS implementation also carries **DoS-hardening limits** (`MAX_TEMPLATE_LENGTH`, `MAX_VARIABLE_LENGTH`, `MAX_TEMPLATE_EXPRESSIONS`, `MAX_REGEX_LENGTH`) and a **ReDoS guard** on exploded patterns (CVE-2026-0621). These are part of the ported behaviour — see "Security limits" below.

### Surface decision — function-based vs parsed-template value (PINNED)

The two public entry points are **`uri-template-expand`** and **`uri-template-match`**, each taking the **template string** as the first argument (mirroring the queue's `expand(template, vars)` / `match(template, uri)` signatures). This is the committed public surface:

```racket
(uri-template-expand template-string vars)  ; -> uri-string
(uri-template-match   template-string uri)  ; -> (hash name -> (or/c string? (listof string?)))  OR  #f
(uri-template?        string)               ; -> boolean? (the isTemplate predicate)
(uri-template-variables template-string)    ; -> (listof string?) (the variableNames getter)
```

Internally, `expand`/`match`/`variables` all funnel through one **`parse-template`** that produces the parts list (literal strings + expression records), so the parse is written once. **Decided:** the public surface is **string-first functions** (not an exposed compiled-template struct) — it matches the queue signatures exactly and keeps the surface minimal for the single S6b consumer. A future item MAY add a `compile`/parsed-template value if profiling shows repeated re-parsing is a cost (S6b resource-template registration), but that is **out of scope here** — note it in Decisions. Each operation re-parses the template; the templates are tiny, so this is correct and adequate.

### The RFC 6570 subset — operators the TS implementation exercises (enumerate EXACTLY)

The operator is the **first character** of an expression `{…}` if it is one of `+ # . / ? &` (else the operator is the empty string — simple expansion). The TS `getOperator` recognizes exactly this set; the mapper MUST cover **all six plus the empty (simple) form**. The `*` suffix on a name marks **explode**. Multiple comma-separated names are supported. The behaviour table (ported verbatim from `uriTemplate.ts` `expandPart` + `partToRegExp`):

| Operator | Form | Expand behaviour (per TS `expandPart`) | Match regex (per TS `partToRegExp`) |
|---|---|---|---|
| *(none)* | `{var}` | percent-encode each value (full `encodeURIComponent`), join multi-value with `,` | `([^/,]+)` (or `([^/,]+(?:,[^/,]+)*)` if exploded) |
| `+` | `{+var}` | **reserved** expansion — encode with `encodeURI` (do NOT encode reserved chars `/`, `:`, etc.), join with `,` | `(.+)` |
| `#` | `{#var}` | prefix `#`, reserved encoding (`encodeURI`), join with `,` | `(.+)` |
| `.` | `{.var}` | prefix `.`, full encoding, join with `.` | `\.([^/,]+)` |
| `/` | `{/var}` | prefix `/`, full encoding, join with `/` | `/([^/,]+)` (or `/([^/,]+(?:,[^/,]+)*)` if exploded) |
| `?` | `{?var}` or `{?a,b}` | prefix `?`, `name=value` pairs joined with `&`; multi-name → `?a=…&b=…` | `\?name=([^&]+)` for the first name, `&name=([^&]+)` for subsequent |
| `&` | `{&var}` | prefix `&`, `name=value` pairs joined with `&` | `\&name=([^&]+)` first, `&name=([^&]+)` subsequent |

> **Multi-name (`{x,y}`) and explode (`{var*}`) are PINNED parts of the subset** — the fixtures exercise both (`{x,y}` → `1024,768`; `{/list*}` match → `("red" "green" "blue")`; `{?tags*}` → `?tags=nodejs,typescript,testing`; `{?q,page,limit}` → multi-query). The mapper MUST handle them, matching the exact TS join/separator behaviour. Specifically, replicate these TS quirks faithfully:
> - **Simple multi-name expand quirk:** for a non-query/non-form operator with `names.length > 1` (e.g. `{x,y}`), TS takes the FIRST element of any array value and joins the present values with `,` (it does NOT explode each — see `expandPart`'s `part.names.length > 1` branch). Port this exactly.
> - **Query/form multi-name:** `{?a,b,c}` emits `?a=…&b=…&c=…`, **skipping undefined variables** (an absent name produces no pair). Arrays under `?`/`&` join their elements with `,` into a single `name=v1,v2,…`.
> - **`?`→`&` continuation:** `expand` tracks whether a query parameter has already been emitted; a SECOND `{?…}` expression after the first is rewritten from `?` to `&` (so `{?a}{?b}` → `?a=1&b=2`, NOT `?a=1?b=2`). Port this `hasQueryParam` logic (fixture: `should handle repeated operators`).

### Encoding — match TS `encodeValue` exactly (PINNED)

TS `encodeValue(value, operator)`:
- operator `+` or `#` → `encodeURI(value)` (reserved-expansion: leaves `/ : ? # [ ] @ ! $ & ' ( ) * + , ; =` and unreserved alphanumerics unencoded; encodes spaces → `%20` etc.);
- **all other operators** → `encodeURIComponent(value)` (encodes reserved chars too: space → `%20`, `/` → `%2F`, etc.).

JS `encodeURI`/`encodeURIComponent` have **specific** unreserved/reserved sets. Racket's `racket/contract`-free string utilities differ. **Decision (PINNED):** implement two small encoders — `encode-uri` (the `encodeURI` set) and `encode-uri-component` (the `encodeURIComponent` set) — as **pure string functions over the UTF-8 byte encoding**, replicating the JS character classes, **NOT** via `net/url` (BANNED by the Portability NFR; `net/uri-codec`/`net/url`'s `uri-encode` uses a different reserved set and would diverge from JS). The two JS sets to replicate:
> - **`encodeURIComponent` unreserved (left as-is):** `A–Z a–z 0–9 - _ . ! ~ * ' ( )`. Everything else → `%XX` over UTF-8 bytes (uppercase hex).
> - **`encodeURI` unreserved (left as-is):** the above PLUS the reserved/delimiter set `; , / ? : @ & = + $ # [ ]`. Everything else → `%XX`.

The fixture `should encode reserved characters` (`{var}` with `value with spaces` → `value%20with%20spaces`) and `{+path}/here` with `/foo/bar` → `/foo/bar/here` (reserved `/` preserved) pin the two paths. **Match these two fixtures exactly; if any other fixture probes a specific encoded char, that pins the encoder too.** Document the encoder character classes in the module doc block so the JS-parity intent is explicit.

> **Encoding is a string→string transform, NO `net/url`.** This is the single most important portability constraint for THIS module: the obvious Racket reach for URI encoding is `net/url`/`net/uri-codec`, which is (a) **banned** by the portability sweep and (b) **semantically divergent** from JS `encodeURIComponent`/`encodeURI`. The encoders MUST be hand-rolled over bytes. The restricted-load test (Part 7) specifically guards that `net/url` did not leak in.

### Match semantics — regex build + recovery (ported from TS `match`)

`uri-template-match`:
1. Build a regex by walking the parts: each literal-text part is **regex-escaped** and appended; each expression part contributes its operator's capture-group pattern (table above), recording the variable name(s) and the exploded flag for each group. Anchor with `^…$`.
2. Match the URI against the compiled regex. **No match → return the no-match result** (see below); the URI does not fit the template (wrong literal prefix, extra trailing segments, missing segments — e.g. `/users/123/extra` and `/users` both fail `/users/{id}`).
3. On match, build the result `hash`: for each captured group, strip a trailing `*` from the name; if the variable is **exploded AND the captured value contains a comma**, split on `,` into a list of strings; else the value is the single string. (Ports TS `result[cleanName] = exploded && value.includes(',') ? value.split(',') : value`.)

> **No-match result shape (PINNED):** TS returns `null`. The idiomatic Racket analogue is **`#f`** (so callers test `(and (uri-template-match t u) …)`). **Decided:** `uri-template-match` returns **`#f`** on no match and an immutable `hash` (symbol-keyed, mirroring jsexpr conventions — see below) on match. Document this so the S6b consumer can branch cleanly. **(Alternative considered + rejected:** raising on no-match — rejected because no-match is an expected, non-exceptional outcome the consumer routes on.)

> **Result hash key type (PINNED):** the variable-binding hash uses **symbol** keys (`(hasheq 'username "fred")`), matching the project's jsexpr/`read-json` convention (symbol keys) and item 011/012's symbol-keyed boundary. The TS object has string keys; the Racket port uses symbols for consistency with the rest of the core. **Pin this in a test** (assert `(hash-ref result 'username)`, not `(hash-ref result "username")`). The variable map passed to `expand` likewise uses **symbol** keys. (If a later reviewer prefers string keys for closer TS parity, that is a one-line change — but symbol keys are the committed choice and MUST be tested explicitly so the boundary is unambiguous.)

### Variable map (input to `expand`) — shape (PINNED)

`vars` is an immutable `hash` (symbol-keyed) of `name → (or/c string? (listof string?))` — a string value or a list of strings (the array case, for explode/multi). This mirrors the TS `Variables = Record<string, string | string[]>`. **Absent / `#f` / undefined variables** are treated as TS treats `undefined`: the expression expands to the empty string (and, under `?`/`&`, contributes no pair). Pin the absent-variable behaviour (fixtures `should handle empty variables`, `should handle undefined variables`).

### Security limits — port the TS hardening (PINNED, do NOT drop)

The TS class enforces (and the fixtures assert) these limits. Port them as module constants and the same guard points:
- **`MAX-TEMPLATE-LENGTH` = 1_000_000** — template string length cap (checked at parse).
- **`MAX-VARIABLE-LENGTH` = 1_000_000** — per variable name AND per variable value length cap (checked when encoding a value and when validating names).
- **`MAX-TEMPLATE-EXPRESSIONS` = 10_000** — cap on the number of `{…}` expressions in one template (checked during parse). The fixture `should handle maximum template expression limit` builds exactly 10_000 and asserts **no** throw (the cap is a `>` not `>=` — 10_000 is allowed, 10_001 throws).
- **`MAX-REGEX-LENGTH` = 1_000_000** — cap on the generated match regex length (checked in `match`).
- **ReDoS guard (CVE-2026-0621):** the exploded-pattern regexes (`([^/,]+(?:,[^/,]+)*)`) MUST NOT catastrophically backtrack on adversarial input like `,,,,,…` (50 commas) or `/,,,,…`. The fixtures `should not be vulnerable to ReDoS with exploded path patterns` (`{/id*}`) and `should not be vulnerable to ReDoS with exploded simple patterns` (`{id*}`) assert the match completes in **< 100 ms**. Racket's regex engine (`pregexp`/`regexp`) on the SAME pattern shape must be verified non-pathological — the port uses the **same regex shape** TS settled on (which is already the de-ReDoS'd form per the CVE fix), and the test asserts the timing bound on the Racket side too.

> **Malformed-template handling (PINNED — match TS):** TS `parse` **throws** on an **unclosed** expression (`{` with no following `}` — `indexOf('}')` returns −1). The Racket port **raises** an S1 error (`make-protocol-error` / `make-mcp-error`) on an unclosed brace. **BUT** an **empty** expression `{}` does **NOT** throw (`getNames` filters empty names → the expression contributes nothing), and `{,}` does **NOT** throw. `{a}{` (a trailing unclosed brace after a valid expression) **DOES** throw. Replicate this exact set (fixture `should handle malformed template expressions`): `{unclosed}` → no throw (it is closed!), `{unclosed` → throw, `{}` → no throw, `{,}` → no throw, `{a}{` → throw. (Note the fixture name is `'{unclosed'` — the OPENING-only string — that is the throw case; a properly-closed `{unclosed}` is just a variable named `unclosed`.)

> **Variable name parsing (ported from TS `getNames`):** strip the operator prefix, `split(',')`, for each name `replace('*','')` then `trim()`, then **filter out empty names**. So `{ }` (whitespace-only) and `{}` yield no names. The `*` (explode) is detected by `expr.includes('*')` at the expression level. Variable name length is validated against `MAX-VARIABLE-LENGTH`. Special characters in names are permitted (fixture `{$var_name}` → expands `$var_name`); names are matched verbatim (after `*`/whitespace stripping) — porting `getNames` exactly handles this.

> **`name` is the SAFE analogue of TS `names[0]`, NOT `(first names)` (issue #1 — the empty-name footgun).** TS stores `const name = names[0]!` on each expression part. When `getNames` returns an **empty** list (the `{}` and `{,}` cases — all names filtered out), TS `names[0]` is `undefined` and the part is **still pushed** (it later expands to `""` and contributes no capture group). The natural Racket transliteration `(define name (first names))` **RAISES `first: contract violation`** on the empty list — which would crash `expand`/`match` on `{}`/`{,}`, contradicting the pinned "no throw / `expand("{}")` → `""`". So the part record's `name` field MUST be the SAFE access **`(and (pair? names) (first names))`** (defaulting to `#f` when there are no names), and every consumer of `name` (the simple single-name expand branch, the match-group recovery) MUST tolerate a `#f` name (an empty-name part expands to `""` and binds no result key). **The footgun is the `names[0]` access at the part-record level, NOT `getNames` itself** — "port `getNames` exactly" does NOT warn about it, hence this explicit note. (Pinned + exercised in Part 6: `expand("{}")` → `""`, `match("{}","")` → `#f`, no crash.)

### Round-trip non-bijection — document which forms do NOT recover identical vars (PINNED)

`expand` then `match` is **NOT** a bijection for every operator/value — the round-trip test must account for this. Document the known non-recoverable cases (so the test asserts the CORRECT recovered value, not a naive "identical to input" expectation):

- **Encoded values:** `expand` percent-encodes (`value with spaces` → `value%20with%20spaces`); `match` recovers the **encoded** string `value%20with%20spaces` (the TS `match` does **NOT** decode — it returns the raw captured substring). So a round-trip of a space-bearing value does NOT recover the original — it recovers the encoded form. **Pin this:** the round-trip test for encoded values asserts the recovered value is the encoded string (TS parity — TS `match` does not URL-decode).
- **Reserved (`+`/`#`) values:** `match` for `+`/`#` uses `(.+)` (greedy, matches everything including `/`), so a template with a `+` expression followed by literal text can match ambiguously; the fixtures restrict `+`/`#` to expand-only or simple cases — port only what the fixtures cover.
- **Multi-name simple `{x,y}`:** `expand({x:1024,y:768})` → `1024,768`. There is **no fixture** that matches `{x,y}` back (the comma-joined form is ambiguous to split per-name), so the round-trip for multi-name simple is **expand-only** in the fixtures. Do NOT invent a match assertion the TS suite does not make.
- **Exploded arrays:** `{/list*}` match of `/red,green,blue` → `("red" "green" "blue")` (a list); but `expand` of `{/list*}` is not separately fixtured for the array — assert exactly what the TS suite asserts per form, not a synthesized inverse.
- **Empty/undefined → empty string:** `expand` of an absent variable yields `""`; that empty contributes nothing to match, so the round-trip of an empty/undefined variable is expand-only (no var to recover).

> **The round-trip test is fixture-driven, not synthesized.** For each TS fixture, port EXACTLY the assertion the TS test makes (the expand result, OR the match result, OR both where the TS test does both). Where the queue says "expand a template with vars and assert the URI, then match that URI back", apply that ONLY to fixtures where TS itself round-trips (the simple `{username}` and multi-segment path cases — `http://example.com/users/{username}` ↔ `fred`, `/users/{username}/posts/{postId}` ↔ `fred`/`123`, `/api/{version}/{resource}/{id}` ↔ `v1`/`users`/`123`). For non-bijective forms, port the one-directional assertion the TS suite makes. **Do not assert a round-trip the TS suite does not.**

### Imports — S1 ONLY

The module requires:
- `mcp/core/main.rkt` (the S1 barrel: types M1 + errors M2 — for `make-protocol-error` / `make-mcp-error` to raise on malformed templates / limit violations); and
- Racket base string/regex/list utilities: `racket/string`, `racket/list`, and the built-in `regexp`/`pregexp` (all part of `racket/base` or portable, non-I/O collections).

It MUST NOT require any transport, engine, role, subprocess, or socket module, and **MUST NOT require `net/url`, `net/uri-codec`, `net/http-client`, or any `net/*` module** (the encoders are hand-rolled; see "Encoding"). Restricted-load portability MUST stay clean — the item-008/010/011/012 transitive-`module->imports` walk mechanism is reused (this item's test runs a `uri-template.rkt`-rooted load check; the collection-wide sweep is item 017). This module is M5a, the **first** `mcp/core/shared/` module — this item **creates the `mcp/core/shared/` and `mcp/core/shared/test/` collection directories**.

### Scope guard (explicit — do NOT cross these lines)

- **Subset, not full RFC 6570.** Implement exactly the operators/forms the TS `uriTemplate.ts` exercises (the seven-row table above). Do NOT add Level-4 features TS omits (e.g. prefix modifiers `{var:3}`, the `;` path-parameter operator) — they are not in the TS impl and not fixtured. If a future need arises, a later item adds them.
- **No `net/url` / `net/uri-codec` / any `net/*`.** The encoders are hand-rolled to match JS `encodeURI`/`encodeURIComponent` exactly. (Portability NFR + JS-parity; pinned.)
- **No transport/engine/role/server logic.** This is a pure L0 string module. S6b's resource-template surface is the CONSUMER; this module stops at `(expand, match, variables, is-template?)`.
- **No URL/decode on match.** TS `match` returns the **raw captured substring** (no percent-decoding). Port that — do NOT decode recovered values (the round-trip-non-bijection note depends on this).
- **No new validation/error semantics beyond TS.** Raise on the SAME conditions TS throws (unclosed brace, length/expression-count caps) using S1 errors; otherwise behave exactly as TS.
- **No `(module+ test …)` in `uri-template.rkt`** — tests live in the separate `test/uri-template-test.rkt` (consistent with items 010/011/012; keeps the portability walk faithful and the test-only requires — `rackunit`, `racket/set`, `racket/path` — out of the module's closure).

---

## Acceptance Criteria

- [x] `mcp/core/shared/uri-template.rkt` exists as `#lang racket/base` with an explicit, curated `provide` (no `(provide (all-defined-out))`). The `mcp/core/shared/` collection directory is **created by this item** (first M5 module).
- [x] The module exports exactly: **`uri-template-expand`** (`(uri-template-expand template vars) → string`), **`uri-template-match`** (`(uri-template-match template uri) → (or/c hash? #f)`), **`uri-template?`** (the `isTemplate` predicate, `string → boolean?`), and **`uri-template-variables`** (the `variableNames` accessor, `string → (listof string?)`). It does NOT leak internal parse/encode/regex helpers.
- [x] **`isTemplate` parity (`uri-template?`).** `#t` for `{foo}`, `/users/{id}`, `http://example.com/{path}/{file}`, `/search{?q,limit}`; `#f` for `""`, `plain string`, `http://example.com/foo/bar`, `{}` (empty braces don't count), `{ }` (whitespace-only doesn't count) — exactly the TS `isTemplate` fixtures.
- [x] **Simple expansion.** `(uri-template-expand "http://example.com/users/{username}" (hasheq 'username "fred"))` → `"http://example.com/users/fred"`; `(uri-template-variables "http://example.com/users/{username}")` → `'("username")`. Multi-name `{x,y}` with `{x:1024,y:768}` → `"1024,768"`, variables `'("x" "y")`.
- [x] **Reserved-character encoding.** `(uri-template-expand "{var}" (hasheq 'var "value with spaces"))` → `"value%20with%20spaces"` (full encoding). `{+path}/here` with `path = "/foo/bar"` → `"/foo/bar/here"` (reserved expansion, `/` preserved), variables `'("path")`.
- [x] **Operator prefixes (each pinned, ported from TS fixtures):** `X{#var}` with `var="/test"` → `"X#/test"` (fragment, reserved encoding); `X{.var}` with `var="test"` → `"X.test"` (label); `X{/var}` → `"X/test"` (path); `X{?var}` → `"X?var=test"` (query); `X{&var}` → `"X&var=test"` (form continuation). Each asserts `variables` = `'("var")`.
- [x] **Multi-variable + nested path expand.** `/api/{version}/{resource}/{id}` with `{version:v1, resource:users, id:123}` → `/api/v1/users/123`, variables `'("version" "resource" "id")`. `///{a}////{b}////` with `{a:1,b:2}` → `///1////2////` (empty segments preserved). Overlapping names `{var}{vara}` with `{var:1, vara:2}` → `12`, variables `'("var" "vara")`.
- [x] **Query expand — arrays + multi-name + continuation.** `/search{?tags*}` with `tags=("nodejs" "typescript" "testing")` → `/search?tags=nodejs,typescript,testing`. `/search{?q,page,limit}` with the three vars → `/search?q=test&page=1&limit=10`. `{?a}{?b}{?c}` with `{a:1,b:2,c:3}` → `?a=1&b=2&c=3` (the `?`→`&` continuation, fixture `should handle repeated operators`).
- [x] **Match — simple + multi + nested.** `(uri-template-match "http://example.com/users/{username}" "http://example.com/users/fred")` → `(hasheq 'username "fred")`. `/users/{username}/posts/{postId}` ↔ `/users/fred/posts/123` → `(hasheq 'username "fred" 'postId "123")`. `/api/{version}/{resource}/{id}` ↔ `/api/v1/users/123` → the three bindings. `///{a}////{b}////` ↔ `///1////2////` → `(hasheq 'a "1" 'b "2")`.
- [x] **Match — query parameters.** `/search{?q}` ↔ `/search?q=test` → `(hasheq 'q "test")`. `/search{?q,page}` ↔ `/search?q=test&page=1` → `(hasheq 'q "test" 'page "1")`. **Missing query param → `#f`:** `(uri-template-match "/search{?q,page}" "/search?q=test")` → `#f` (the regex requires the literal `&page=([^&]+)` group, so an omitted `page` does not match — high-value for the S6b router).
- [x] **Match — exploded arrays.** `(uri-template-match "{/list*}" "/red,green,blue")` → `(hasheq 'list '("red" "green" "blue"))` (a LIST value, comma-split because exploded).
- [x] **No-match → `#f` (pinned).** `(uri-template-match "/users/{username}" "/posts/123")` → `#f`. Partial/over-match: `(uri-template-match "/users/{id}" "/users/123/extra")` → `#f`; `(uri-template-match "/users/{id}" "/users")` → `#f`. Length mismatches: `(uri-template-match "/api/{param}" "/api/")` → `#f`, `"/api"` → `#f`, `"/api/value/extra"` → `#f`. (Ports the TS `null` returns as `#f`.)
- [x] **Result hash keys are SYMBOLS (pinned).** A match result is queried as `(hash-ref result 'username)` (symbol key), NOT `(hash-ref result "username")`. Asserted explicitly so the symbol/string boundary is unambiguous (consistent with the jsexpr convention + items 011/012).
- [x] **Round-trip parity (G1, the queue headline).** For each TS fixture that the TS suite itself round-trips (simple `{username}`, `/users/{username}/posts/{postId}`, `/api/{version}/{resource}/{id}`), expand vars → URI, then match URI → recover the SAME vars (symbol-keyed). For non-bijective forms, port the one-directional TS assertion (do NOT assert an inverse the TS suite omits). The recovered values for ENCODED inputs match TS exactly (match does NOT decode — the recovered value is the encoded substring).
- [x] **Empty / undefined variables.** `(uri-template-expand "{empty}" (hasheq))` → `""`; `(uri-template-expand "{empty}" (hasheq 'empty ""))` → `""`. `(uri-template-expand "{a}{b}{c}" (hasheq 'b "2"))` → `"2"` (absent `a`/`c` contribute nothing). Ports `should handle empty variables` / `should handle undefined variables`.
- [x] **Special characters in variable names.** `(uri-template-expand "{$var_name}" (hasheq '$var_name "value"))` → `"value"` (a `$`/`_`-bearing name parses and binds). Ports `should handle special characters in variable names`.
- [x] **Malformed-template handling (pinned, matches TS throw set).** `(uri-template-expand "{unclosed" …)` (or any operation on `"{unclosed"`) **raises** an S1 error (unclosed brace). `"{a}{"` (trailing unclosed) **raises**. `"{}"` does **NOT** raise (empty expr → no variable). `"{,}"` does **NOT** raise. `"{unclosed}"` (properly closed) does **NOT** raise (it is a variable named `unclosed`). `(check-exn exn:fail? …)` / `(check-not-exn …)` per row — ports `should handle malformed template expressions`.
- [x] **Security limits (pinned, ported).** A template with **10_000** expressions parses without raising (`should handle maximum template expression limit`); a template/variable at length **100_000** expands+matches fine (`should handle extremely long input strings`); a variable name of length **10_000** does not raise (`should handle maximum variable name length`); a 1000×-repeated 10-expression template expands without raising (`should handle deeply nested template expressions`). Limit constants (`MAX-TEMPLATE-LENGTH`, `MAX-VARIABLE-LENGTH`, `MAX-TEMPLATE-EXPRESSIONS`, `MAX-REGEX-LENGTH`) are defined and enforced at the same guard points as TS.
- [x] **ReDoS guard (CVE-2026-0621, pinned).** `(uri-template-match "{/id*}" (string-append "/" (make-string 50 #\,)))` and `(uri-template-match "{id*}" (make-string 50 #\,))` each complete in **< 100 ms** (assert an elapsed-time bound, mirroring the TS tests). The Racket regex on the de-ReDoS'd pattern shape does not catastrophically backtrack. **Pair the timing bound with a result-value assertion** so a "fast but wrong" regex refactor cannot pass: `{id*}` vs 50 commas → `#f` (a string of only commas has no non-comma segment, so it does not match `([^/,]+…)`); `{/id*}` vs `'/'+50 commas` → `#f` likewise. Assert BOTH the `< 100 ms` AND the `#f` per case.
- [x] **Pathological / invalid-UTF-8 input does not crash.** `(uri-template-match "/api/{param}" (string-append "/api/" (make-string 100000 #\a)))` does not raise/hang (`should handle pathological regex patterns`); expanding/matching a value with replacement/non-ASCII characters does not raise (`should handle invalid UTF-8 sequences` — port as a non-ASCII / Unicode value case, since Racket strings are already valid Unicode).
- [x] **Encoding parity — JS sets replicated (pinned).** The `encodeURIComponent` path encodes space → `%20` and reserved chars (`/`→`%2F`, etc.) while leaving the JS unreserved set (`- _ . ! ~ * ' ( )` + alphanumerics) untouched; the `encodeURI` path (operators `+`/`#`) additionally leaves `; , / ? : @ & = + $ # [ ]` untouched. **No `net/url` / `net/uri-codec` used** (verified by the portability test). At minimum the two fixtured cases (`value with spaces`→`value%20with%20spaces`; `/foo/bar` under `+` unchanged) pass; add a focused encoder unit test for a reserved char under both paths to pin the divergence.
- [x] **Multibyte UTF-8 encode parity (byte-vs-codepoint guard, pinned).** One concrete multibyte assertion: `(uri-template-expand "{var}" (hasheq 'var "é"))` → `"%C3%A9"` (UTF-8 bytes, uppercase hex), NOT `%E9` (codepoint). Pins that the encoder works over UTF-8 **bytes**, not codepoints — the exact failure mode of a naive per-`char` encoder.
- [x] **`*` explode value-shape boundaries (pinned).** The explode array branch handles a **single-element** list (`{?tags*}` + `'("solo")` → `"?tags=solo"`) and an **empty** list (`{?tags*}` + `'()` → `""`, NOT `"?tags="`, NOT a raise). For a simple `{list*}`, an empty list → `""`. Pin both boundaries.
- [x] **Imports = S1 ONLY (verified by a restricted-namespace load test).** The module requires only `mcp/core/main.rkt` (+ portable base collections `racket/string`/`racket/list`). It requires NO transport/engine/role/subprocess/socket module and **NO `net/url` / `net/uri-codec` / `net/*`**. A fresh `(make-base-namespace)` requiring `uri-template.rkt` and walking `module->imports` transitively shows EMPTY intersection with the banned set (`racket/system racket/tcp racket/udp net/url net/uri-codec net/http-client net/sendurl racket/sandbox racket/port`).
- [x] **No `(module+ test …)` in `uri-template.rkt`** — tests live in `mcp/core/shared/test/uri-template-test.rkt`.
- [x] `raco test mcp/core/shared/` passes (exit 0) — module + new test compile and run cleanly within the new collection.
- [x] `raco make mcp/core/shared/uri-template.rkt` exits 0 (compiles clean, no warnings about missing/non-portable modules).
- [x] Parity-matrix discipline: the `uriTemplate` row advances to `partial`. Update `docs/aide/progress.md` per the Completion Reminder — flip the `uri-template.rkt` deliverable line (📋 → 🚧 → ✅) AND check the Stage-S2 **URI-template** acceptance box (this item owns it).

---

## Implementation Steps

1. **Re-read the reference for shape + behaviour:** `typescript-sdk/packages/core/src/shared/uriTemplate.ts` (the operator set, `getOperator`/`getNames`, `encodeValue`, `expandPart` per-operator branches incl. the `hasQueryParam` `?`→`&` continuation and the `names.length > 1` simple-multi branch, `partToRegExp`, `match`'s capture-recovery + the exploded-comma-split, and the four limit constants + the ReDoS-safe pattern shapes) and `typescript-sdk/packages/core/test/shared/uriTemplate.test.ts` (every fixture — enumerate the groups: `isTemplate`, `simple string expansion`, `reserved expansion`, `fragment`/`label`/`path`/`query`/`form continuation`, `matching`, `edge cases`, `complex patterns`, `matching complex patterns`, `security and edge cases`). Re-read item 008's portability-walk test for the `module->imports` walk to reuse.
2. **The public surface + result/var-hash key types are PINNED** (do not re-decide): `uri-template-expand` / `uri-template-match` / `uri-template?` / `uri-template-variables`, each string-first; `vars` and the match-result hash are **symbol-keyed immutable hashes**; no-match → **`#f`**; `match` does NOT decode; encoders are hand-rolled (NO `net/*`); malformed (unclosed brace) → raise an S1 error.
3. **Write `mcp/core/shared/uri-template.rkt`.** Use `#lang racket/base`. In order:
   - `(require racket/string racket/list "../main.rkt")` (S1 barrel for `make-protocol-error`/`make-mcp-error`). NO `net/*`.
   - A module-level **doc block** recording: the transliteration framing (port of TS `uriTemplate.ts`); the **RFC-6570-subset operator table** (the seven rows) + the explicit note it is a SUBSET (not full RFC 6570); the **encoding character classes** for `encode-uri` vs `encode-uri-component` (JS-parity, NO `net/url`); the **match semantics** (regex build, no-decode, exploded-comma-split, `#f` no-match); the **symbol-keyed** var/result convention; the **security limits** + ReDoS note; and the **malformed-template throw set** (unclosed → raise; `{}`/`{,}` → no raise).
   - The **limit constants** (`MAX-TEMPLATE-LENGTH` `MAX-VARIABLE-LENGTH` `MAX-TEMPLATE-EXPRESSIONS` `MAX-REGEX-LENGTH`).
   - The two **hand-rolled encoders** `encode-uri` / `encode-uri-component` (over UTF-8 bytes, JS unreserved sets). Internal only.
   - `parse-template` → a list of parts (literal strings + expression records `(name operator names exploded)`); enforces unclosed-brace raise + expression-count cap + name-length cap; `getNames`/`getOperator` logic ported. **The part record's `name` field = `(and (pair? names) (first names))` — the SAFE analogue of TS `names[0]`, defaulting to `#f` when `names` is empty (the `{}`/`{,}` case). Do NOT write `(first names)` — it raises on the empty list and crashes `expand`/`match` on legal empty-name templates (issue #1). The single-name `expand` branch and the match-group recovery MUST tolerate a `#f` name (expand → `""`, bind no key).**
   - `uri-template?` (`isTemplate`): regex `#px"\\{[^}\\s]+\\}"`.
   - `uri-template-variables`: `parse-template` then flat-map the expression parts' names.
   - **`uri-template-expand`**: walk parts; literal → append; expression → `expand-part` (per-operator branch, with the `hasQueryParam` `?`→`&` continuation thread and the `names.length > 1` simple-multi quirk; absent var → empty; **`#f`-name (empty-name) part → empty; empty-list array value → empty (contributes no `?`/`&` pair); single-element array handled by the same join loop**); encode via the right encoder per operator over **UTF-8 bytes** (so a multibyte char → multiple `%XX`).
   - **`uri-template-match`**: build the anchored regex (regex-escape literals; per-operator capture pattern from the table; record name+exploded per group); enforce `MAX-REGEX-LENGTH`; `regexp-match`; no match → `#f`; on match, build the symbol-keyed result hash (strip `*`, exploded-comma-split → list).
   - The explicit `(provide uri-template-expand uri-template-match uri-template? uri-template-variables)` block (NOT the internal helpers).
4. **Write the test** `mcp/core/shared/test/uri-template-test.rkt` (see Testing Strategy). Port EVERY fixture group 1:1 (Part 1–7 below), the round-trip parity (G1) for the round-trippable fixtures, the no-match `#f` cases, the symbol-key assertion, the malformed-template throw set, the security-limit + ReDoS-timing cases, the encoder divergence unit check, and the restricted-load portability sub-test (reuse the item-008 walk; entry point = `uri-template.rkt`; confirm no `(module+ test …)` in `uri-template.rkt`).
5. **Run** `raco make mcp/core/shared/uri-template.rkt` then `raco test mcp/core/shared/`. Fix any failure. Confirm `raco test mcp/core/validators/` and `raco test mcp/core/util/` still pass (this item touches neither M3 nor M4).
6. **Update progress + parity matrix** (see Completion Reminder).

---

## Testing Strategy

The test is a **fixture-port + expand/match round-trip test**: it ports each `uriTemplate.test.ts` fixture 1:1, asserting the SAME `expand`/`match` result the TS suite asserts (G1 parity), plus the round-trip (expand→match recovers vars) for the fixtures TS itself round-trips, the no-match `#f` cases, the symbol-key boundary, the malformed-template throw set, the security/ReDoS cases, an encoder-divergence unit check, and the restricted-load portability sub-test.

**Test file:** `mcp/core/shared/test/uri-template-test.rkt` (`#lang racket/base`; `(require rackunit racket/string racket/list "../uri-template.rkt")` plus `racket/set`/`racket/path` for the portability walk). No `json` needed (templates and values are strings; the var/result hashes are plain `hasheq`).

Small helpers keep assertions terse:
```racket
(define (exp t vars) (uri-template-expand t vars))
(define (mat t uri)  (uri-template-match t uri))
;; (round-trips? t vars uri) -> asserts (exp t vars) = uri AND (mat t uri) recovers vars.
```

### Part 1 — `isTemplate` (`uri-template?`)

- True set: `{foo}`, `/users/{id}`, `http://example.com/{path}/{file}`, `/search{?q,limit}`.
- False set: `""`, `plain string`, `http://example.com/foo/bar`, `{}` (empty braces), `{ }` (whitespace-only).

### Part 2 — Expansion (each operator)

- **Simple:** `http://example.com/users/{username}` + `{username:fred}` → `http://example.com/users/fred`; `variables` → `'("username")`. Multi-name `{x,y}` + `{x:1024,y:768}` → `1024,768`; `variables` → `'("x" "y")`.
- **Reserved encoding:** `{var}` + `{var:"value with spaces"}` → `value%20with%20spaces`.
- **Reserved (`+`):** `{+path}/here` + `{path:"/foo/bar"}` → `/foo/bar/here`; `variables` → `'("path")`.
- **Fragment (`#`):** `X{#var}` + `{var:"/test"}` → `X#/test`.
- **Label (`.`):** `X{.var}` + `{var:"test"}` → `X.test`.
- **Path (`/`):** `X{/var}` + `{var:"test"}` → `X/test`.
- **Query (`?`):** `X{?var}` + `{var:"test"}` → `X?var=test`.
- **Form continuation (`&`):** `X{&var}` + `{var:"test"}` → `X&var=test`.
- **Complex:** `/api/{version}/{resource}/{id}` → `/api/v1/users/123`; `/search{?tags*}` + array → `/search?tags=nodejs,typescript,testing`; `/search{?q,page,limit}` → `/search?q=test&page=1&limit=10`.

### Part 3 — Matching

- **Simple:** `http://example.com/users/{username}` ↔ `http://example.com/users/fred` → `(hasheq 'username "fred")`. **Assert the SYMBOL key** `(hash-ref m 'username)` = `"fred"`.
- **Multi-var:** `/users/{username}/posts/{postId}` ↔ `/users/fred/posts/123` → `(hasheq 'username "fred" 'postId "123")`.
- **No match → `#f`:** `/users/{username}` ↔ `/posts/123` → `#f`.
- **Exploded array:** `{/list*}` ↔ `/red,green,blue` → `(hasheq 'list '("red" "green" "blue"))` (LIST value).
- **Complex match:** `/api/{version}/{resource}/{id}` ↔ `/api/v1/users/123` → the three bindings; `/search{?q}` ↔ `/search?q=test`; `/search{?q,page}` ↔ `/search?q=test&page=1`.
- **Missing query param → `#f`:** `/search{?q,page}` ↔ `/search?q=test` (page omitted) → `#f` — the built regex requires the literal `&page=([^&]+)` group, so an absent trailing query param is a NO-match. (High value for the S6b resource router, which must NOT bind a template when a required query var is missing.)
- **Partial/over match → `#f`:** `/users/{id}` ↔ `/users/123/extra` → `#f`; `/users/{id}` ↔ `/users` → `#f`.

### Part 4 — Round-trip parity (G1)

For each fixture TS itself round-trips, assert BOTH directions:
- `http://example.com/users/{username}` + `{username:fred}` → URI `http://example.com/users/fred` → match recovers `(hasheq 'username "fred")`.
- `/users/{username}/posts/{postId}` + `{username:fred, postId:123}` → URI → recovers both.
- `/api/{version}/{resource}/{id}` + the three → URI → recovers the three.
- **Document (in a comment + assertion) the non-bijective forms:** an encoded value (`value with spaces`) round-trips to the ENCODED substring (`value%20with%20spaces`) on match — assert the recovered value is the encoded form (TS `match` does not decode). Multi-name simple `{x,y}` and exploded-array expand are expand-ONLY in TS (no inverse fixture) — do NOT assert an inverse.

### Part 5 — Edge cases (ported)

- **Empty variables:** `{empty}` + `(hasheq)` → `""`; `{empty}` + `(hasheq 'empty "")` → `""`.
- **Undefined variables:** `{a}{b}{c}` + `(hasheq 'b "2")` → `"2"`.
- **Special chars in names:** `{$var_name}` + `(hasheq '$var_name "value")` → `"value"`.
- **Nested path segments:** `/api/{version}/{resource}/{id}` (also in Part 2/3).
- **Overlapping names:** `{var}{vara}` + `{var:1, vara:2}` → `12`; `variables` → `'("var" "vara")`.
- **Empty segments:** `///{a}////{b}////` + `{a:1,b:2}` → `///1////2////`; match recovers `(hasheq 'a "1" 'b "2")`.
- **Repeated operators (`?`→`&`):** `{?a}{?b}{?c}` + `{a:1,b:2,c:3}` → `?a=1&b=2&c=3`; `variables` → `'("a" "b" "c")`.

### Part 6 — Malformed templates (the throw set, pinned)

- `(check-exn exn:fail? (lambda () (uri-template-variables "{unclosed")))` — unclosed brace raises (note: the TS fixture string is `'{unclosed'`, OPENING-only).
- `(check-exn exn:fail? (lambda () (uri-template-variables "{a}{")))` — trailing unclosed raises.
- `(check-not-exn (lambda () (uri-template-variables "{}")))` — empty expr, no raise.
- `(check-not-exn (lambda () (uri-template-variables "{,}")))` — comma-only, no raise.
- `(check-not-exn (lambda () (uri-template-variables "{unclosed}")))` — properly closed, no raise (a variable named `unclosed`).
- (Drive the raise/no-raise through whichever entry point parses — `uri-template-variables` parses unconditionally, so it is the cleanest probe.)
- **Empty-name expressions MUST be exercised through `expand` AND `match`, not only `variables` (issue #1 — the `names[0]` footgun).** `uri-template-variables` tolerates an empty names list by flat-mapping to nothing, so it passes even if a port crashes on `(first '())` inside `expand`/`match`. Probe the actual TS-pinned behaviour (TS pushes the part with `name = names[0] = undefined`, and the part expands to `""` / contributes no capture group): add
  - `(check-not-exn (lambda () (uri-template-expand "{}" (hasheq))))` AND `(check-equal? (uri-template-expand "{}" (hasheq)) "")`;
  - `(check-not-exn (lambda () (uri-template-expand "{,}" (hasheq))))` AND `(check-equal? (uri-template-expand "{,}" (hasheq)) "")`;
  - `(check-equal? (uri-template-match "{}" "") #f)` (TS `match("{}","")` → `null`: the empty-name part contributes no capture group, the built regex is `^$`, but the empty part still pushed a name-less group expectation in TS that yields `null` — assert `#f`; pin whatever the implementation produces here, but it MUST NOT crash). Also `(check-equal? (uri-template-match "{}" "x") #f)`. **(G1 honesty note:** TS actually **throws** on `match("{}","x")` — `name=names[0]=undefined`, `undefined.replace` crashes. The Racket port returning `#f` here is a **deliberate hardening over TS** enabled by the safe-`#f`-name design, **not** byte-for-byte TS parity. This is the one place the empty-name handling intentionally diverges from TS; the "MUST NOT crash" robustness intent takes precedence over literal parity for this degenerate input.)
  - **Result-hash shape for the empty-name part (pinned):** an empty-name part contributes **no key** to a successful match result hash (it has no name to bind) — it does NOT add a `#f`-keyed or `""`-keyed entry. So a template like `a{}b` matching `ab` yields `(hasheq)` (no spurious empty key), NOT `(hasheq #f "")` or `(hasheq '|| "")`. Pin this with `(check-equal? (uri-template-match "a{}b" "ab") (hasheq))` (or `#f` if the implementation's `^a()b$`-style group forces a no-match — assert whichever the port produces, but it MUST be one of `(hasheq)`/`#f`, never a crash and never a garbage key).

### Part 7 — Security, ReDoS, and portability

- **Long input:** `/api/{param}` + a 100_000-char value → expand returns `/api/<that>`; match recovers it. (`should handle extremely long input strings`.)
- **Deeply nested:** `{a}…{j}` ×1000 → expand with `{a:1…j:0}` does not raise. (`should handle deeply nested template expressions`.)
- **Max expression count:** a template of exactly 10_000 `{param}` expressions → `parse`/`variables` does not raise. (`should handle maximum template expression limit`.)
- **Max variable name length:** `{<10_000-a's>}` + the matching var → expand does not raise. (`should handle maximum variable name length`.)
- **Pathological match:** `/api/{param}` ↔ `/api/<100_000 a's>` → no raise/hang. (`should handle pathological regex patterns`.)
- **Non-ASCII / Unicode value (no-crash):** `/api/{param}` + a non-ASCII value (e.g. `"日本語"` or replacement chars) → expand + match do not raise. (Ports `should handle invalid UTF-8 sequences`; Racket strings are valid Unicode so this is a Unicode/special-char value case.)
- **Multibyte encode parity (concrete, byte-vs-codepoint guard):** assert ONE concrete multibyte expansion — e.g. `(uri-template-expand "{var}" (hasheq 'var "é"))` → `"%C3%A9"` (the UTF-8 bytes `0xC3 0xA9`, each `%XX`, uppercase hex), NOT `%E9` (the codepoint) and NOT a 1-byte mangle. This pins that the hand-rolled `encode-uri-component` encodes over **UTF-8 bytes**, not over codepoints — exactly where a naive `char->integer`-per-char encoder breaks. (A 3-byte char like `"あ"` → `"%E3%81%82"` is an equally valid pin; assert at least one multibyte char.)
- **`*` explode value-shape edge cases:** the array branch must handle a **single-element** list (`(uri-template-expand "{?tags*}" (hasheq 'tags '("solo")))` → `"?tags=solo"`) and an **empty** list (`(uri-template-expand "{?tags*}" (hasheq 'tags '()))` → `""` — an empty array contributes no pair, like an absent variable; assert it does NOT produce `"?tags="` or raise). For a simple `{list*}` an empty list expands to `""`. Pin both the single-element and empty-list cases so the explode/join loop is exercised at its boundaries.
- **ReDoS guard (timing-bounded + result-checked):** `(uri-template-match "{/id*}" (string-append "/" (make-string 50 #\,)))` and `(uri-template-match "{id*}" (make-string 50 #\,))` — wrap in `current-inexact-milliseconds` deltas and `(check-true (< elapsed 100))` **AND** `(check-equal? result #f)` per case (a comma-only payload has no `[^/,]+` segment to capture → no match; pairing the timing with the `#f` result prevents a "fast but semantically wrong" regex refactor from passing on timing alone). (Ports the two CVE-2026-0621 tests.)
- **Encoder divergence unit check:** assert `encode-uri-component`-path output for a reserved char (e.g. a value `"a/b"` under `{var}` → `a%2Fb`) AND `encode-uri`-path output for the same under `{+var}` → `a/b` (unencoded). Pins the two JS sets diverge correctly. (Either probe via `expand` with the two operators, or — if the encoders are exported test-locally — directly; PIN via `expand` since the encoders stay internal.)

**Part 7b — restricted-namespace portability (S1 only).** Reuse the transitive `module->imports` walk from item 008/010/011/012 — fresh `(make-base-namespace)`, `namespace-require` `uri-template.rkt`, walk imports threading `current-load-relative-directory` per module dir, assert the FULL banned set (`racket/system racket/tcp racket/udp net/url net/uri-codec net/http-client net/sendurl racket/sandbox racket/port`) has empty intersection with the visited set. **Entry point is `uri-template.rkt` ITSELF.** This **specifically guards** that the encoders did NOT reach for `net/url` or `net/uri-codec`. **Non-vacuity (drift):** temporarily inject `(require net/url)` into a scratch copy, confirm the walk FAILS naming `net/url`, then revert. (Scope note inherited from item 008: `module->imports` does not see into `(module+ test …)` submodules — proves the module's own import graph; this item keeps `uri-template.rkt` free of `module+ test`.)

> **`uri-template.rkt` MUST NOT define a `(module+ test …)` submodule** — tests live in the separate `test/uri-template-test.rkt` (consistent with items 010/011/012). This keeps the portability walk (which does not see into `module+ test`) a faithful proof of the module's own import graph, and keeps the test's heavier requires (`rackunit`, `racket/set`, `racket/path`) out of `uri-template.rkt`'s closure.

### Fixture → ported-test mapping (1:1, the G1 contract)

Every `uriTemplate.test.ts` group maps to a Racket test group:

| TS `describe`/`it` group | Ported Racket part |
|---|---|
| `isTemplate` (true + false sets) | Part 1 |
| `simple string expansion` (simple, multi-var, reserved-char encode) | Part 2 |
| `reserved expansion` (`{+path}`) | Part 2 |
| `fragment` / `label` / `path` / `query` / `form continuation` expansion | Part 2 |
| `matching` (simple, multi, null→`#f`, exploded array) | Part 3 |
| `edge cases` (empty, undefined, special-char names) | Part 5 |
| `complex patterns` (nested path, query arrays, multi-query) | Part 2 |
| `matching complex patterns` (nested, query, multi-query, partial→`#f`) | Part 3 |
| `security and edge cases` (long input, deep nest, malformed, pathological, invalid-UTF-8, length mismatch, repeated ops, overlapping names, empty segments, max-expr, max-name, ReDoS ×2) | Parts 5, 6, 7 |
| (round-trip composition — queue-mandated) | Part 4 |

---

## Dependencies

- **Upstream work items:**
  - **Stage S1 items 001–009** (✅ complete) — `mcp/core/main.rkt` (item 008 barrel: types M1 + errors M2). Provides `make-protocol-error` / `make-mcp-error` for raising on malformed templates (unclosed brace) and limit violations. This is the ONLY project dependency.
- **Downstream consumers (informational):**
  - **S6b** high-level server (`mcp/server/mcp.rkt`, M12b) — the `register-resource` **templated** form uses `uri-template-match` to route an incoming resource URI to its template handler and recover the bound variables, and `uri-template-expand` to render concrete resource URIs. **This module has NO consumer inside S2** — it is built ahead of its S6b consumer (note this explicitly; the item ships and is fully tested standalone).
  - **Item 017** — the S2 collection-wide restricted-load portability sweep includes `mcp/core/shared/uri-template.rkt` (this module). This item already satisfies the sweep (its per-module restricted-load test proves it).
  - **Item 018** — the S2 demo expands + matches a URI template (this module is the production path S6b uses).
- **Tooling/runtime:** Racket ≥ 8.x (`raco`, `rackunit`). The `typescript-sdk/` checkout MUST be present for **authoring** — the behaviour and the fixtures are lifted from `shared/uriTemplate.ts` + `test/shared/uriTemplate.test.ts`. The Racket test does NOT parse the `.ts` at runtime (the fixtures are transcribed into Racket assertions), so a missing checkout would not break the running test but would make the fixture-port un-reproducible.

---

## Decisions & Trade-offs

To be updated during implementation.

The **design decisions below are PINNED at spec time** (real choices, not options). The **post-build outcome** (require list as built, exact check count, drift result, REPL transcript, ReDoS timings) is *to be updated during implementation*.

**(a) Public surface = string-first functions `uri-template-expand` / `uri-template-match` / `uri-template?` / `uri-template-variables`** — matching the queue's `expand(template, vars)` / `match(template, uri)` signatures exactly, with no exposed compiled-template struct. Each operation re-parses the (tiny) template via one shared internal `parse-template`. A `compile`/parsed-template value is deferred to a later item if S6b resource-template registration shows re-parse cost in a profile. **To be updated during implementation** (confirm no profiling pressure surfaced).

**(b) No-match result = `#f`; match result + var map = symbol-keyed immutable `hash`.** TS returns `null`; the Racket port returns `#f` (an expected, non-exceptional outcome the consumer branches on — NOT a raise). The variable/result hashes use SYMBOL keys (`(hasheq 'username "fred")`), matching the jsexpr/`read-json` convention and items 011/012's symbol-keyed boundary; pinned with an explicit `(hash-ref result 'username)` assertion. **To be updated during implementation.**

**(c) Hand-rolled encoders, NO `net/url` / `net/uri-codec` (Portability NFR + JS parity).** `encode-uri` (the JS `encodeURI` unreserved set) and `encode-uri-component` (the JS `encodeURIComponent` unreserved set) are implemented over UTF-8 bytes. `net/url`/`net/uri-codec` are BOTH banned (portability) and semantically divergent from JS (different reserved sets) — using them would break G1 parity. The restricted-load test guards the no-`net/*` invariant; an encoder unit check pins the two sets diverge correctly. **To be updated during implementation** (record the exact unreserved-char sets implemented).

**(d) `match` does NOT decode recovered values (TS parity).** TS `match` returns the raw captured substring (no percent-decoding), so an encoded value round-trips to its ENCODED form, not the original. This makes expand→match NON-bijective for encoded/multi-name/exploded forms; the round-trip test asserts only the round-trips the TS suite itself asserts and pins the encoded-recovery case explicitly. **To be updated during implementation.**

**(e) Subset, not full RFC 6570 (operators the TS impl exercises only).** Exactly `+ # . / ? &` + simple, with multi-name and `*` explode. Prefix modifiers (`{var:3}`), the `;` path-style operator, and other Level-4 features are OUT (TS omits them; no fixture). Documented so the parity claim is honest (the parity matrix row is `partial`, not `done`). **To be updated during implementation.**

**(f) Security limits + ReDoS-safe regex shape ported verbatim.** The four caps (`MAX-TEMPLATE-LENGTH`/`MAX-VARIABLE-LENGTH`/`MAX-TEMPLATE-EXPRESSIONS`/`MAX-REGEX-LENGTH`) and the de-ReDoS'd exploded pattern shape (`([^/,]+(?:,[^/,]+)*)`) are ported from the TS CVE-2026-0621 fix; the ReDoS tests assert a <100 ms timing bound on the Racket regex engine. **To be updated during implementation** (record the measured timings — note timing assertions can be environment-sensitive; if the bound proves flaky on slow CI, the fallback is a generous bound, e.g. <1 s, that still falsifies catastrophic backtracking — record which bound shipped).

**(g) Malformed-template throw set matches TS exactly.** Unclosed brace (`"{unclosed"`, `"{a}{"`) → raise an S1 error; `"{}"`/`"{,}"`/`"{unclosed}"` → no raise. Empty/whitespace names are filtered (`getNames` parity), not errors. **Empty-name parts are pushed (TS parity) with `name` = the SAFE `(and (pair? names) (first names))`, NOT `(first names)` — the `names[0]` footgun (issue #1):** `(first '())` raises and would crash `expand`/`match` on the legal `{}`/`{,}` inputs. An empty-name part expands to `""` and binds no result key (`a{}b`↔`ab` → `(hasheq)`/`#f`, never a garbage `#f`/empty key). Pinned + exercised through expand AND match in Part 6 (not only `uri-template-variables`, which tolerates the empty names list and would mask the crash). **To be updated during implementation.**

**(h) No `(module+ test …)` in `uri-template.rkt`** — tests live in `test/uri-template-test.rkt` (keeps the portability walk faithful and the test-only requires out of the module's closure).

**(i) Post-build outcomes (recorded at implementation).**
- **Require list as built:** `(require racket/string racket/list "../main.rkt")` — exactly S1 + two portable base collections; NO `net/*`. The test additionally `(only-in (file "../../main.rkt") exn:fail:mcp?)` for the malformed-throw assertion.
- **Exact check count:** `raco test mcp/core/shared/` → **108 checks pass, 0 failures, 0 errors** (exit 0). Sibling suites unaffected: `raco test mcp/core/validators/` → 300 pass; `raco test mcp/core/util/` → 102 pass.
- **`raco make`:** `raco make mcp/core/shared/uri-template.rkt` → exit 0, clean (no warnings).
- **Encoder unreserved sets as built:** `encode-uri-component` leaves `A–Z a–z 0–9 - _ . ! ~ * ' ( )` (bytes `45 95 46 33 126 42 39 40 41`); `encode-uri` adds `; , / ? : @ & = + $ # [ ]` (bytes `59 44 47 63 58 64 38 61 43 36 35 91 93`). Everything else → `%XX` over UTF-8 bytes, uppercase hex. Verified: `é`→`%C3%A9`, `あ`→`%E3%81%82`, `a/b`→`a%2Fb` (component) vs `a/b` (uri).
- **ReDoS measured timings:** `{/id*}` vs `/`+50 commas → **0.12 ms**; `{id*}` vs 50 commas → **0.09 ms** (both ≪ 100 ms; both return `#f`). The shipped bound is the spec's **<100 ms** (no widening needed).
- **Portability drift result:** the restricted-load walk over `uri-template.rkt` shows EMPTY intersection with the banned set (`racket/system racket/tcp racket/udp net/url net/uri-codec net/http-client net/sendurl racket/sandbox racket/port`); visited 1 + S1 closure (non-vacuous, `set-count > 1` asserted). Non-vacuity confirmed: a scratch copy with `(require net/url)` injected made the walk report `net/url` hit `#t` (273 modules visited), then was removed.
- **No `(module+ test …)`** in `uri-template.rkt` (confirmed by grep); tests live in `test/uri-template-test.rkt`.

---

## Project-Specific Adaptations (Racket / raco / rackunit)

This is a **Racket library, not a service** — same adaptation pattern as items 010/011/012. The generic "Testing Prerequisites" template (Required Services / database / API endpoint / ports / health checks) does **not** apply and is adapted as follows (documented explicitly per the create-item skill):

- **Required Services → None.** Pure Racket library; no external services, databases, message queues, HTTP servers, sockets, subprocesses, or network. The module is L0 and load-portable by construction (and proven so by the restricted-load test). **Note:** URI encoding MUST be hand-rolled — this module MUST NOT use `net/url` / `net/uri-codec` / any `net/*` (banned by the Portability NFR, and divergent from JS for G1 parity).
- **Database / API endpoint / ports sections → N/A.** Removed; replaced by the Racket toolchain row below.
- **Required toolchain:** Racket ≥ 8.x (`raco test`, `rackunit`). Verified present in this environment: **Racket v8.18 [cs]**.
- **TS checkout role:** present at `typescript-sdk/`; **required for authoring** (behaviour from `shared/uriTemplate.ts`; fixtures from `test/shared/uriTemplate.test.ts`, transcribed into Racket assertions — a fixture-parity item, unlike item 012's structural parity).
- **Manual Validation Checklist → specialized** to `raco make` / `raco test` + a REPL expand/match smoke check (below). No "service started" / "health check" / "screenshots" rows — replaced with N/A or removed.
- **Language/naming:** `#lang racket/base`; kebab-case bindings; explicit `(provide …)` never `all-defined-out` (architecture §1.3); S1-only imports (architecture §4.1).
- **New collection directory:** this item creates `mcp/core/shared/` and `mcp/core/shared/test/` (they do not yet exist) — the **first M5 module**.
- **No-consumer-in-S2 note:** unlike item 012 (consumed by S6b too) this M5a module has NO S2 consumer; it ships fully tested standalone and is wired up by S6b. The S2 demo (item 018) exercises it.

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None (pure Racket library; no external services).** No databases, message queues, HTTP servers, sockets, subprocesses, or network dependencies.

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime | compile + run module and tests (`raco`, `rackunit`) | system install (`racket --version` ≥ 8.0; this env: v8.18) | n/a |
| S1 barrel (`mcp/core/main.rkt`) | the module requires the S1 public surface (errors — `make-protocol-error`) | already present (items 001–008, ✅) | n/a |
| `typescript-sdk/` checkout | read while authoring to lift behaviour from `shared/uriTemplate.ts` and the fixtures from `test/shared/uriTemplate.test.ts` (G1 fixture parity) | already present at repo root | n/a |

### Environment Configuration

- **Environment variables / secrets / config files / free ports:** none required.
- **Racket version:** ≥ 8.x (verified: v8.18 [cs]).
- **Working directory:** run `raco test` from the **repo root** so the `mcp/...` collection path resolves.
- **How to run the tests:**
  - `raco make mcp/core/shared/uri-template.rkt` — compile the URI-template module clean.
  - `raco test mcp/core/shared/` — run all shared-collection tests (picks up `test/uri-template-test.rkt` recursively), exit 0.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0.
  - `raco make mcp/core/main.rkt` → exit 0 (the S1 barrel this item requires loads clean).

### Manual Validation Checklist

*(Not yet built — leave UNCHECKED until implementation completes.)*

- [x] **Build/compile succeeds:** `raco make mcp/core/shared/uri-template.rkt` compiles with no errors/warnings.
- [x] **Module loads in isolation:** `racket -e '(require (file "mcp/core/shared/uri-template.rkt"))'` from repo root succeeds.
- [x] **Tests pass:** `raco test mcp/core/shared/test/uri-template-test.rkt` → all checks pass, exit 0.
- [x] **Collection tests pass:** `raco test mcp/core/shared/` → exit 0.
- [x] **M3/M4 untouched:** `raco test mcp/core/validators/` AND `raco test mcp/core/util/` → still exit 0 (this item modifies neither).
- [x] **Services started:** N/A (no services — pure library).
- [x] **Application runs:** N/A (library; "running" = the require + REPL expand/match smoke check below).
- [x] **Feature verified (REPL expand/match smoke check):** from repo root, expand a template and match the result back — e.g.
      `racket -e '(require (file "mcp/core/shared/uri-template.rkt")) (define u (uri-template-expand "http://example.com/users/{username}" (hasheq (quote username) "fred"))) (list u (uri-template-match "http://example.com/users/{username}" u))'`
      prints `("http://example.com/users/fred" #hasheq((username . "fred")))` (expand fills `fred`, match recovers it). (Record exact transcript in Validation Results.)
- [x] **`isTemplate` verified:** true for `{foo}`/`/users/{id}`/etc.; false for `""`/`plain string`/`{}`/`{ }`.
- [x] **Simple + reserved-char expand verified:** `{username}`→`fred`; `{var}` of `value with spaces`→`value%20with%20spaces`; `{+path}` of `/foo/bar`→`/foo/bar`.
- [x] **All operator prefixes verified:** `#`/`.`/`/`/`?`/`&` each produce the fixtured prefix+format.
- [x] **Multi-name + explode verified:** `{x,y}`→`1024,768`; `{?tags*}`→`?tags=…,…,…`; `{?q,page,limit}`→multi-query; `{?a}{?b}{?c}`→`?a=…&b=…&c=…` (`?`→`&` continuation).
- [x] **Match verified:** simple, multi-var, nested path, query, multi-query → correct symbol-keyed bindings; **`(hash-ref m 'username)` (symbol key) asserted**.
- [x] **Exploded-array match verified:** `{/list*}`↔`/red,green,blue` → `'("red" "green" "blue")` (list value).
- [x] **No-match → `#f` verified:** non-matching, partial, over-match, length-mismatch URIs all → `#f`; **missing query param** (`/search{?q,page}` ↔ `/search?q=test`) → `#f`.
- [x] **Round-trip (G1) verified:** the three round-trippable fixtures expand→match recover the same vars; encoded-value recovery returns the ENCODED substring (match does not decode).
- [x] **Empty/undefined/special-char-name vars verified:** `{empty}`→`""`; `{a}{b}{c}` with only `b`→`2`; `{$var_name}`→`value`.
- [x] **Empty segments + overlapping names verified:** `///{a}////{b}////`→`///1////2////` (and matches back); `{var}{vara}`→`12`.
- [x] **Malformed-template throw set verified:** `"{unclosed"`/`"{a}{"`→raise; `"{}"`/`"{,}"`/`"{unclosed}"`→no raise.
- [x] **Empty-name expand/match verified (issue #1):** `(uri-template-expand "{}" (hasheq))`→`""`; `(uri-template-expand "{,}" (hasheq))`→`""`; `(uri-template-match "{}" "")`→`#f`; `a{}b`↔`ab` → `(hasheq)` or `#f` (never a crash, never a garbage `#f`/empty key). `name` = `(and (pair? names) (first names))`, NOT `(first names)`.
- [x] **Security limits verified:** 10_000 expressions, 100_000-char value, 10_000-char name, 1000×10-expr nest → no raise; caps defined + enforced.
- [x] **ReDoS guard verified (CVE-2026-0621):** `{/id*}` and `{id*}` against 50-comma payloads complete in <100 ms **AND** return `#f` (timing + result both asserted; record measured timings; note the bound shipped if widened).
- [x] **Pathological + Unicode input verified:** 100_000-`a` match input + a non-ASCII value → no raise/hang.
- [x] **Multibyte encode parity verified:** `{var}` of `"é"`→`"%C3%A9"` (UTF-8 bytes, not codepoint `%E9`).
- [x] **`*` explode boundaries verified:** `{?tags*}` + `'("solo")`→`"?tags=solo"`; `{?tags*}` + `'()`→`""` (not `"?tags="`, no raise).
- [x] **Encoder divergence verified:** `{var}` of `a/b`→`a%2Fb`; `{+var}` of `a/b`→`a/b` (the two JS sets diverge correctly); **NO `net/url`/`net/uri-codec` used**.
- [x] **No `(module+ test …)` in `uri-template.rkt` confirmed:** tests live in `test/uri-template-test.rkt`.
- [x] **Portability verified:** the restricted-load test passes (no subprocess/socket — incl. NO `net/url`/`net/uri-codec` — in the transitive import closure of `uri-template.rkt`).
- [x] **Drift / non-vacuity check (portability):** temporarily add `(require net/url)` to a scratch copy, confirm the load test FAILS naming `net/url`, then revert.
- [x] **S1-only imports confirmed:** require list = `racket/string` + `racket/list` + `../main.rkt` (no `net/*`, no transport/engine/role).
- [x] **Health checks pass:** N/A (no running service).

### Expected Outcomes

Concrete, verifiable:

- The module **exports** `uri-template-expand`, `uri-template-match`, `uri-template?`, `uri-template-variables` (and NO internal helpers). `(uri-template? "{foo}")` → `#t`; `(uri-template? "plain")` → `#f`.
- Every `uriTemplate.test.ts` fixture has a ported Racket assertion that produces the **same `expand`/`match` result** the TS suite asserts (G1 parity).
- `expand`→`match` **round-trips** the three round-trippable fixtures (simple `{username}`, multi-segment path) recovering the same symbol-keyed vars; non-bijective forms are asserted one-directionally per the TS suite.
- A **non-matching URI** yields **`#f`** (not a raise, not a partial hash); a **malformed (unclosed-brace) template** **raises** an S1 error; `{}`/`{,}` do NOT raise.
- The module **requires only S1** (+ `racket/string`/`racket/list`) — a restricted-namespace load test confirms NO subprocess/socket and **NO `net/url`/`net/uri-codec`/`net/*`** is pulled in (Portability NFR).
- The **ReDoS** payloads complete in <100 ms (or the recorded widened bound); the four security caps are defined and enforced.
- `raco test mcp/core/shared/` reports all checks passing, 0 failures, 0 errors; `raco test mcp/core/validators/` and `raco test mcp/core/util/` still green (M3/M4 untouched).

### Validation Results

Built and verified 2026-06-23 (Racket v8.18 [cs]).

```markdown
## Validation Results
- [x] Service started: N/A (pure Racket library, no services)
- [x] Application started successfully: N/A (library; `require` + expand/match smoke check ran)
- [x] Build verified: `raco make mcp/core/shared/uri-template.rkt` clean (exit 0, no warnings)
- [x] Module load verified: `(require (file ".../uri-template.rkt"))` succeeds — smoke check:
      `(uri-template-expand "http://example.com/users/{username}" (hasheq 'username "fred"))` then match →
      `'("http://example.com/users/fred" #hasheq((username . "fred")))`
- [x] Tests verified: `raco test mcp/core/shared/` → 108 checks pass, 0 failures, 0 errors
- [x] M3/M4 untouched: `raco test mcp/core/validators/` (300 pass) AND `raco test mcp/core/util/` (102 pass) → still exit 0
- [x] isTemplate verified: true/false sets per fixtures
- [x] Simple + reserved-char expand verified: {username}→fred; {var} of "value with spaces"→value%20with%20spaces; {+path} of /foo/bar→/foo/bar
- [x] All operator prefixes verified: # . / ? & each correct
- [x] Multi-name + explode verified: {x,y}→1024,768; {?tags*}→?tags=…,…,…; {?q,page,limit}; {?a}{?b}{?c}→?a=…&b=…&c=… (?→& continuation)
- [x] Match verified: simple/multi/nested/query/multi-query → symbol-keyed bindings; (hash-ref m 'username) asserted
- [x] Exploded-array match verified: {/list*}↔/red,green,blue → '("red" "green" "blue") (list)
- [x] No-match → #f verified: non-match/partial/over-match/length-mismatch + missing-query-param ({?q,page}↔?q=test) → #f
- [x] Round-trip (G1) verified: three round-trippable fixtures recover same vars; encoded recovery = encoded substring (no decode)
- [x] Empty/undefined/special-char-name vars verified: {empty}→""; {a}{b}{c} only b→2; {$var_name}→value
- [x] Empty segments + overlapping names verified: ///{a}////{b}////→///1////2////; {var}{vara}→12
- [x] Malformed throw set verified: "{unclosed"/"{a}{"→raise (exn:fail:mcp?); "{}"/"{,}"/"{unclosed}"→no raise
- [x] Empty-name expand/match verified (issue #1): expand("{}")→""; expand("{,}")→""; match("{}","")→#f; match("{}","x")→#f; a{}b↔ab→#f (no crash, no garbage key); name=(and (pair? names) (first names))
- [x] Security limits verified: 10_000 exprs / 100_000-char value / 10_000-char name / 1000×10-expr nest → no raise; caps enforced
- [x] ReDoS guard verified (CVE-2026-0621): {/id*} + {id*} vs 50-comma payload → <100 ms (measured 0.12 ms / 0.09 ms) AND result #f
- [x] Pathological + Unicode input verified: 100_000-a match + non-ASCII value (日本語) → no raise/hang
- [x] Multibyte encode parity verified: {var} of "é"→"%C3%A9" (UTF-8 bytes, not codepoint %E9); "あ"→"%E3%81%82"
- [x] Explode boundaries verified: {?tags*}+'("solo")→"?tags=solo"; {?tags*}+'()→"" (not "?tags=", no raise); {list*}+'()→""
- [x] Encoder divergence verified: {var} of a/b→a%2Fb; {+var} of a/b→a/b; NO net/url/net/uri-codec used
- [x] No (module+ test …) in uri-template.rkt confirmed (tests in test/uri-template-test.rkt)
- [x] Portability verified: restricted-load walk over uri-template.rkt — empty intersection with banned set (incl. no net/url, no net/uri-codec)
- [x] Portability drift check: injected (require net/url) into a scratch copy → walk reported net/url hit #t (273 modules), then removed
- [x] S1-only imports confirmed: require list = racket/string + racket/list + ../main.rkt (no net/*)
- [x] Database tables verified: N/A
- [x] Seed data verified: N/A
- [x] API endpoints verified: N/A
- [x] Screenshots captured: N/A (no UI)
```

---

## Completion Reminder

On completion, the implementer MUST update **`docs/aide/progress.md`** (Stage S2 section), advancing the icon **📋 → 🚧 → ✅**:

1. Flip the deliverable line **`📋 mcp/core/shared/uri-template.rkt (M5a) — RFC 6570 subset expand/match`** from 📋 → 🚧 (on start) → ✅ (on delivery + all acceptance criteria pass). Never revert an icon backward.
2. **Check the Stage-S2 URI-template acceptance box** — **`[ ] URI template expand/match round-trips TS uriTemplate.test.ts fixtures (G1)`**. **This box belongs to THIS item** (it owns the URI-template deliverable). Check it on delivery.
3. Do **not** check the other broad Stage-S2 acceptance boxes that depend on sibling items (the `raco test over all S2 modules`, tool-name, stdio-framing, and the catch-all demo boxes belong to items 014–018). The `Schema normalization` and `Validator keyword coverage` boxes are already checked (items 010/011/012) — leave them.
4. **Parity matrix:** per Stage S2 discipline, advance the **`uriTemplate` row to `partial`** (the subset expand/match now exists and ports the fixtures; full conformance + the collection-wide sweep land with item 017 and S9). Add a sentence to the parity-matrix progression paragraph recording that the `uriTemplate` row is now `partial` (mirroring the item-010/011/012 entries).
5. Leave all other S2 deliverable lines (`validators/*` ✅; `util/schema.rkt` ✅; the other `shared/*` utils — M5b–M5e — still 📋; tests-under-other-dirs) at their current status — this item delivers only `uri-template.rkt` + its test (and creates the `mcp/core/shared/` collection).
