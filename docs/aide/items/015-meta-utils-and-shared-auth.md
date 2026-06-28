# Work Item 015: `_meta` metadata utils + shared `AuthInfo` (M5c + M5d)

> **Queue:** `docs/aide/queue/queue-002.md` — Item 015
> **Stage:** S2 (Foundation: validators, schema, shared utilities — L0 part 2)
> **Modules:** **M5c** (`_meta` metadata utils) — `mcp/core/shared/metadata-utils.rkt`; **M5d** (shared auth) — `mcp/core/shared/auth.rkt`. Two cohesive shared modules grouped by size + cohesion: M5c is the display-name helper + the reserved-`_meta`-key surface (mirroring TS `metadataUtils.ts` + `types/constants.ts`); M5d is the `AuthInfo` struct + token/metadata helpers (mirroring the `AuthInfo` shape at TS `types/types.ts:435` + the non-OAuth helpers). Both have **NO consumer inside S2** — they are built ahead of their consumers (M5c → high-level server M12b/S6b `register-tool`; M5d → S8 client + server auth).
> **Source vision:** `docs/aide/vision.md` §6 (Portability NFR — core L0–L2 loads without subprocess/socket; both are pure non-I/O modules), G1 (wire/behaviour parity with the TS SDK — the display-name precedence, the eight reserved `_meta` keys, and the `AuthInfo` field surface must match TS).
> **Source roadmap:** `docs/aide/roadmap.md` Stage S2 → Deliverables (`mcp/core/shared/metadata-utils.rkt` (M5c), `mcp/core/shared/auth.rkt` (M5d)) + Testing/validation criterion (parity rows `metadataUtils`, `auth` → `partial`).
> **Source architecture:** `docs/aide/architecture.md` M5c/M5d (shared utils; depend on S1 only), §1.3 (public/internal boundary, explicit `provide`), §4.1 (Runtime-neutral core L0–L2 imports no subprocess/socket).
> **Reference impl (authoritative):** MCP TypeScript SDK v2 at `typescript-sdk/`:
>   - `packages/core/src/shared/metadataUtils.ts` — the 26-line `getDisplayName` (precedence `title` → `annotations.title` → `name`, with the empty-string-title fallthrough).
>   - `packages/core/src/types/constants.ts` — the **eight** reserved `_meta` keys (the five S1 captured **plus** the three W3C trace-context keys `traceparent` / `tracestate` / `baggage`, SEP-414).
>   - `packages/core/src/types/types.ts:435` — the `AuthInfo` interface (`token`, `clientId`, `scopes`, optional `expiresAt`, optional `resource` URL, optional `extra`).
>   - `packages/core/src/shared/auth.ts` + `authUtils.ts` — the **token/metadata helpers only** (NOT the OAuth zod schemas in `auth.ts`).
>   - Test fixtures: `packages/core/test/shared/auth.test.ts`, `authUtils.test.ts`.
> **Source (S1):** `mcp/core/types/constants.rkt` (the five reserved `_meta` key string constants already exported), `mcp/core/types/spec-2026-07-28.rkt` (the `request-meta` `_meta` envelope, item 004) — M5c round-trips with these.
> **Status:** ✅ Complete — both modules + tests delivered; `raco test mcp/core/shared/` → 269 pass (38 metadata-utils + 39 auth + 192 prior).

---

## Description

Implement two cohesive shared modules for `racket-mcp`, both importing **only S1** (types M1 + errors M2) and both pure non-I/O (no subprocess, no socket).

### (1) `mcp/core/shared/metadata-utils.rkt` (M5c)

Mirrors TS `metadataUtils.ts` + the reserved-`_meta`-key portion of `types/constants.ts`. Two responsibilities:

**(1a) `get-display-name`** — the display-name precedence helper. TS `getDisplayName(metadata) → string`:

1. if `title` is **not `undefined` and not `''`** → return `title`;
2. else if `annotations.title` is present **and truthy** (tools only) → return `annotations.title`;
3. else fall back to `name`.

The **empty-string-title fallthrough** is load-bearing: a `title` of `""` is treated as absent (rung 1 fails) and the function falls through to `annotations.title` then `name`. The high-level server (M12b / S6b `register-tool`) needs this.

**(1b) Reserved `_meta` key surface** — the constants for the reserved keys plus accessors/setters that respect the reserved-key namespace and **round-trip with the S1 `_meta` envelope** (`request-meta`, item 004, `2026-07-28` spec). Reconcile the **5-vs-8 discrepancy** (below).

### (2) `mcp/core/shared/auth.rkt` (M5d)

The **`AuthInfo` struct** (the shape at TS `types/types.ts:435`) + token/metadata **helpers** (the non-OAuth helpers from `shared/auth.ts` + `authUtils.ts`). Field surface to mirror **exactly**: `token`, `clientId`, `scopes`, optional `expiresAt`, optional `resource` (a URL), optional `extra`. This is the shared struct the S8 client + server auth both consume. **NO OAuth logic here** — struct + helpers only (the OAuth zod schemas in TS `auth.ts` are out of scope; they belong to S8/M14).

---

### M5c framing — `get-display-name` (read carefully)

**Input form — PINNED: symbol-keyed JSON-object hash (the wire/duck-typed form).** TS `getDisplayName` is **duck-typed** over an object exposing `.title`, `.annotations?.title`, `.name`. The Racket port operates on the **symbol-keyed `json-object?` hash** — the form `read-json` already produces everywhere in this codebase (every S1 `…->json` emits one) and the form `tool->json` / `resource->json` / `prompt->json` produce. This is chosen over a struct-dispatch zoo (over `base-metadata` / `tool` / `resource` / `resource-template` / `prompt` / `implementation`) because:

- it mirrors the TS duck-typed object **1:1** (`(hasheq 'name "n" 'title "t" 'annotations (hasheq 'title "a"))`);
- it round-trips with the wire form (the JSON the server advertises);
- it keeps the tests light (no need to construct a full multi-field `tool` struct just to exercise the `annotations.title` rung);
- it needs no struct import, so the rung-2 (`annotations.title`) case is reachable without S1's `tool` constructor arity.

The precedence reads `(hash-ref md 'title #f)`, then — **guarding that `annotations` is a hash** — `(hash-ref annotations 'title #f)`, then `(hash-ref md 'name)`:

```racket
;; (get-display-name md) -> string?   ; md : symbol-keyed json-object hash
(define (get-display-name md)
  (define title (hash-ref md 'title #f))
  (define annotations (hash-ref md 'annotations #f))
  (cond
    [(and (string? title) (not (string=? title ""))) title]          ; rung 1: non-empty STRING title
    [(and (hash? annotations)                                        ; rung 2: annotations.title (tools) —
          (let ([at (hash-ref annotations 'title #f)])               ;   ONLY when annotations is a hash
            (and (string? at) (not (string=? at "")) at)))]
    [else (hash-ref md 'name)]))                                     ; rung 3: name (no default — raises if absent)
```

> **Empty-string-title fallthrough (PINNED).** TS checks `metadata.title !== undefined && metadata.title !== ''`. A `title` of `""` is **absent**, so `{name:'n', title:''}` → `'n'`, and `{name:'n', title:'', annotations:{title:'a'}}` → `'a'`. Port this — `(string=? title "")` must fall through, NOT return `""`. Same empty-string guard on `annotations.title` (TS's `annotations?.title` is truthy-tested, so `''` is falsy and falls through to `name`).

> **C1 — `annotations` MUST be `hash?`-guarded before the inner `hash-ref` (PINNED, CRITICAL — latent crash).** The input is the **wire form `read-json` produces**, and `read-json` will yield `'annotations → (json-null)` (the symbol `'null` by default) or a non-hash (`"x"`, a number, a list) for a malformed/odd object. The naive `(hash-ref (hash-ref md 'annotations (hasheq)) 'title #f)` only defaults when `annotations` is **absent** — when it is **present but `null`/non-hash**, the inner `hash-ref` raises a contract error and `get-display-name` **crashes**. TS's `metadata.annotations?.title` uses optional chaining: a `null`/missing `annotations` yields `undefined` and falls through to `name`. The Racket port MUST reach the same outcome via the explicit `(hash? annotations)` guard — a `null`/non-hash `annotations` is treated as **no annotations-title** and falls through to `name`. **Pin with tests:** `(get-display-name (hasheq 'name "n" 'annotations (json-null)))` → `"n"` and `(get-display-name (hasheq 'name "n" 'annotations "garbage"))` → `"n"` — both return `"n"`, neither raises. (Reaching `(json-null)` in the test requires `(require json)`.)

> **S5 — non-string / `null` `title` is a DELIBERATE divergence from TS, NOT a verbatim port (PINNED).** TS rung 1 is `title !== undefined && title !== ''`, so TS returns `null` for `title: null` and `42` for `title: 42`. The Racket `(and (string? title) …)` guard is **stricter** — a non-string `title` falls through to `annotations.title`/`name`. This is intentional (a display name must be a string; returning `null`/`42` would be a downstream footgun) and is arguably **better** than TS, but it IS a divergence — so this is **not** a byte-for-byte port at the title rungs, and the module doc block + Decisions (b) MUST say so (do **not** claim "verbatim TS" for the title rungs). **Pin with a test:** `(get-display-name (hasheq 'name "n" 'title (json-null)))` → `"n"`.

> **`name` is required; absence raises (PINNED — S1 domain, S6 must be ASSERTED).** TS types `name: string` as required on `BaseMetadata`; if `md` has no `'name` key, the rung-3 `(hash-ref md 'name)` raises (no default supplied). This matches TS's static contract (a metadata object without `name` is ill-typed). Document the input domain ("a metadata object always carries `name`"); do NOT invent a `""`/`#f` fallback for missing `name` — that would diverge from TS and silently mask a malformed object. (Mirrors item 014's "input domain documented, contract error surfaces" resolution.) **Because an unfalsifiable "it raises" invariant rots, this MUST be asserted:** `(check-exn exn:fail? (λ () (get-display-name (hasheq 'title ""))))` — empty title + no annotations + no name reaches rung 3 and raises.

> **Struct-convenience overload is OUT of scope (PINNED — do NOT add).** Do not add a parallel `get-display-name` that dispatches on the S1 `tool`/`resource`/`prompt` structs. M12b can call `(get-display-name (tool->json t))` (or build a 3-key hash) at its call site. A struct-dispatch overload over six heterogeneous struct types is drift-prone and unnecessary; if a future item proves M12b needs a struct entry point, that item adds it. Keep ONE surface: the hash form.

### M5c framing — reserved `_meta` keys + the 5-vs-8 reconciliation (read carefully)

**The discrepancy (flag, do NOT lose).** TS `types/constants.ts` defines **eight** reserved `_meta` keys:

| # | TS constant | Key string | Captured in S1? | Source |
|---|---|---|---|---|
| 1 | `PROTOCOL_VERSION_META_KEY` | `io.modelcontextprotocol/protocolVersion` | ✅ `PROTOCOL-VERSION-META-KEY` (`constants.rkt:61`) | spec |
| 2 | `CLIENT_INFO_META_KEY` | `io.modelcontextprotocol/clientInfo` | ✅ `CLIENT-INFO-META-KEY` (`constants.rkt:62`) | spec |
| 3 | `CLIENT_CAPABILITIES_META_KEY` | `io.modelcontextprotocol/clientCapabilities` | ✅ `CLIENT-CAPABILITIES-META-KEY` (`constants.rkt:63`) | spec |
| 4 | `LOG_LEVEL_META_KEY` (deprecated) | `io.modelcontextprotocol/logLevel` | ✅ `LOG-LEVEL-META-KEY` (`constants.rkt:64`) | spec |
| 5 | `RELATED_TASK_META_KEY` | `io.modelcontextprotocol/related-task` | ✅ `RELATED-TASK-META-KEY` (`constants.rkt:60`) | spec |
| 6 | `TRACEPARENT_META_KEY` | `traceparent` | ❌ **missing** | SEP-414 |
| 7 | `TRACESTATE_META_KEY` | `tracestate` | ❌ **missing** | SEP-414 |
| 8 | `BAGGAGE_META_KEY` | `baggage` | ❌ **missing** | SEP-414 |

S1 captured **five** (keys 1–5, all `io.modelcontextprotocol/…`-prefixed); the **three W3C trace-context keys** (keys 6–8, `traceparent` / `tracestate` / `baggage`, SEP-414) were **not** captured. These three are **unprefixed** plain strings — an explicit exception to the `_meta` key-prefix rule — reserved by the spec for OpenTelemetry-style distributed-trace propagation.

> **Resolution — PINNED: define the three missing constants in M5c.** M5c **defines** `TRACEPARENT-META-KEY "traceparent"`, `TRACESTATE-META-KEY "tracestate"`, `BAGGAGE-META-KEY "baggage"` (net-new, SEP-414) and aggregates **all eight** reserved keys in one place (re-exporting the five S1 constants from `constants.rkt` + adding the three trace keys), so the 5-vs-8 gap is **closed and documented**, not silently dropped. The alternative (scope the three out + file an S1 follow-up against `constants.rkt`) is permitted but **not** chosen here — defining them in M5c is the lower-friction path and keeps the full reserved set co-located with the accessor surface. Document the discrepancy + the SEP-414 unprefixed exception in the module doc block.

> **The SDK does NOT interpret trace-context values (PINNED).** `traceparent` / `tracestate` / `baggage` pass through `_meta` **untouched** — the SDK never parses or validates the W3C header formats. They ride in the unreserved-key passthrough (`request-meta-rest`) of the S1 envelope and are re-emitted verbatim. M5c's accessors read/write them as opaque values. Do NOT add W3C trace-context parsing — that is out of scope.

**Accessor/setter surface (PINNED — operate on the `_meta` hash).** Provide accessors/setters over a symbol-keyed `_meta` hash (the wire form of the envelope), plus a reserved-key predicate:

```racket
(define reserved-meta-key-strings (list PROTOCOL-VERSION-META-KEY … BAGGAGE-META-KEY))   ; all 8 strings
(define reserved-meta-keys        (map string->symbol reserved-meta-key-strings))         ; all 8 as hash-key symbols
(reserved-meta-key? k)            ; -> boolean?  ; k a symbol or string; member of the 8
(meta-ref  meta key [default])    ; -> value     ; read a key (reserved or not) from a _meta hash
(meta-set  meta key value)        ; -> meta'     ; functional set (returns a NEW hash; meta unchanged)
```

- **Key normalization (PINNED — MUST be tested on a PREFIXED key, S2).** `read-json` keys every JSON object with **symbols**, so a wire `_meta` hash keyed by `"traceparent"` appears as symbol `'traceparent`, and `"io.modelcontextprotocol/protocolVersion"` as the symbol `|io.modelcontextprotocol/protocolVersion|`. The accessors accept the key as **either** a string (the `…-META-KEY` constant) **or** a symbol, normalizing to the symbol form internally (mirror S1's `(string->symbol …-META-KEY)` pattern in `spec-2026-07-28.rkt:438-442`). So `(meta-ref meta TRACEPARENT-META-KEY)` and `(meta-ref meta 'traceparent)` are equivalent. **Test the equivalence on a PREFIXED key** (the risky one — `(string->symbol "io.modelcontextprotocol/logLevel")` is the pipe-quoted symbol, not a short word): set with the string `LOG-LEVEL-META-KEY` and read back with BOTH the string and `(string->symbol LOG-LEVEL-META-KEY)` — both return the value.
- **`meta-ref` missing-key-without-default returns `#f` (PINNED — S3).** `(meta-ref meta key)` with NO `default` arg on a key not present returns **`#f`** (it does NOT raise) — the helper is a present-or-`#f` probe, not a `hash-ref`-style raiser. `(meta-ref meta key default)` returns `default` when absent. PINNED so callers may use it as an existence probe without a guard. (Implement as `(hash-ref meta (normalize key) default)` with `default` defaulting to `#f`.)
- **`meta-set` is functional (PINNED).** Returns a **new** immutable hash; never mutates the input. Mirrors the codebase's `put`/`hash-set` discipline (the S1 envelope uses immutable `hasheq`).
- **Reserved-namespace respect (PINNED).** `meta-set` does NOT forbid writing reserved keys (the helper is the legitimate way to set them); `reserved-meta-key?` exists so callers can DETECT a reserved key (e.g. to avoid clobbering it with a user-supplied unreserved key). Document: writing an unreserved key leaves all reserved keys untouched, and vice-versa.

> **S1 — M5c's 8-key set is NOT S1's `request-meta-reserved-keys` (PINNED, two-notions-of-reserved boundary).** M5c's `reserved-meta-keys` = {the 5 `io.modelcontextprotocol/…` keys} ∪ {`traceparent`, `tracestate`, `baggage`} = **8**. S1's `request-meta-reserved-keys` (`spec-2026-07-28.rkt:443-445`) = {`progressToken`} ∪ {the 5 prefixed keys} = **6**. The intersection is only the 5 prefixed keys. Two consequences a future caller WILL trip over: (i) `progressToken` is reserved at the S1 `RequestParams` level but is **NOT** one of the 8 namespaced `_meta` keys, so `(reserved-meta-key? 'progressToken)` → **`#f`**; (ii) the 3 trace keys are in M5c's set but ride S1's **unreserved** `request-meta-rest`. This divergence MUST be documented in the module doc block AND pinned with a negative test: `(check-false (reserved-meta-key? 'progressToken))` (with a comment: it IS reserved at the S1 RequestParams level, but it is not a namespaced `_meta` reserved key).

**Round-trip with the S1 `_meta` envelope (PINNED — exact fixture, C5/S7).** The acceptance test asserts the three trace keys survive an S1 round-trip: a `_meta` hash carrying `traceparent`/`tracestate`/`baggage` (+ the three S1-required reserved keys protocolVersion/clientInfo/clientCapabilities) → `json->request-meta` lands the trace keys in `request-meta-rest` (they are NOT in S1's `request-meta-reserved-keys`) → `request-meta->json` re-emits them verbatim → `(meta-ref re-emitted TRACEPARENT-META-KEY)` etc. return the original values.

> **C5 — the S1-required reserved keys MUST be VALID sub-objects, not bare strings (PINNED, CRITICAL — else the test fails for the wrong reason).** `json->request-meta` (`spec-2026-07-28.rkt:455-471`) does NOT accept arbitrary values for the three required reserved keys — it runs `clientInfo` through `json->implementation` (needs `name` + `version`) and `clientCapabilities` through `json->client-capabilities`, and requires a non-absent `protocolVersion`. A bare-string `clientInfo → "x"` (the naive reading of "minimal valid values") **crashes `json->implementation`**, and Part 4 then fails on an unrelated decode error — **masking** whether the trace keys actually round-trip. So the fixture is PINNED to concrete valid sub-objects:
>
> ```racket
> ;; keys are the S1 …-META-KEY strings, string->symbol'd to match read-json's symbol keys
> (hasheq (string->symbol PROTOCOL-VERSION-META-KEY)     "2026-07-28"
>         (string->symbol CLIENT-INFO-META-KEY)          (hasheq 'name "c" 'version "1")
>         (string->symbol CLIENT-CAPABILITIES-META-KEY)  (hasheq)
>         'traceparent "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
>         'tracestate  "vendor1=value1"
>         'baggage     "userId=alice")
> ```
>
> The executor MUST **confirm `(hasheq)` is accepted by `json->client-capabilities`** before relying on it (read `spec-2026-07-28.rkt:395-398` — `client-capabilities` wraps the raw object, so an empty `hasheq` is accepted; if a future S1 change tightens it, supply the minimal accepted shape). This proves the trace keys pass through S1's unreserved passthrough untouched (and documents that S1's `request-meta` treats them as unreserved `rest` — the very reason M5c must own their constants).

### M5d framing — `AuthInfo` struct + helpers (read carefully)

**Struct shape — PINNED, field surface EXACT.** Mirror TS `AuthInfo` (`types/types.ts:435`) field-for-field, kebab-cased, `#:transparent`:

```racket
(struct auth-info (token client-id scopes expires-at resource extra) #:transparent)
```

| TS field | Type | Racket field | Contract | Required? |
|---|---|---|---|---|
| `token` | `string` | `token` | `string?` | **required** |
| `clientId` | `string` | `client-id` | `string?` | **required** |
| `scopes` | `string[]` | `scopes` | `(listof string?)` | **required** (may be `'()`) |
| `expiresAt?` | `number` (seconds since epoch) | `expires-at` | `(opt/c exact-nonnegative-integer?)` | optional → `#f` |
| `resource?` | `URL` | `resource` | `(opt/c string?)` | optional → `#f` |
| `extra?` | `Record<string, unknown>` | `extra` | `(opt/c json-object?)` | optional → `#f` |

> **`scopes` is REQUIRED (PINNED).** TS types `scopes: string[]` (no `?`), so it is always present — empty list when none, never absent. The struct field is required; the smart constructor defaults it to `'()`.

> **`resource` is a STRING, not a parsed URL (PINNED — portability).** TS holds `resource` as a `URL` object. The Racket port holds the **URL string** (the wire form — `resource` serializes to a string anyway). **Do NOT use `net/url`:** the full `net/url` module transitively pulls `racket/tcp` (a socket dependency), which would **violate the Portability NFR** (core L0–L2 loads with no subprocess/socket) and break item 017's restricted-load sweep. Holding the string keeps M5d socket-free. (If S8 later needs a parsed form, it may wrap with the pure `net/url-structs` — structs only, no tcp — at that layer; that is out of scope here.) Document this trade-off in the module + on the field.

> **Optional fields default to `#f` (PINNED).** Absent `expires-at` / `resource` / `extra` are `#f` (the codebase's `opt/c`/`#f` convention, e.g. `request-meta`'s optionals). `#f` ≠ a present-but-empty value.

**Helpers — PINNED (token + metadata, NO OAuth).** The in-scope helpers from `auth.ts` + `authUtils.ts` are the **non-OAuth** ones (the OAuth zod schemas in `auth.ts` — `OAuthMetadataSchema` etc. — are S8/M14, **excluded here**). Provide at minimum:

```racket
(make-auth-info #:token t #:client-id c
                [#:scopes '()] [#:expires-at #f] [#:resource #f] [#:extra #f])  ; smart constructor
(auth-info-expired? ai [now-seconds])    ; -> boolean?   ; TOKEN helper: expires-at present AND <= now
(auth-info-has-scope? ai scope)          ; -> boolean?   ; METADATA helper: scope ∈ scopes
(auth-info->json ai)                     ; -> json-object?  ; wire round-trip (camelCase keys)
(json->auth-info h)                      ; -> auth-info?    ; wire round-trip
```

- **`auth-info-expired?` (token helper, PINNED).** `expires-at` is seconds since epoch. `(auth-info-expired? ai)` ⇔ `(and (auth-info-expires-at ai) (<= (auth-info-expires-at ai) (or now (current-seconds))))`. When `expires-at` is `#f` (no expiry recorded) → **`#f`** (not expired / unknown). The optional `now-seconds` arg makes the helper deterministically testable (do NOT make the test depend on wall-clock). **`expires-at = 0` is a valid epoch (PINNED — S4 falsy-omit trap):** `0` is a truthy `exact-nonnegative-integer?` in Racket, so `(auth-info-expired? (make-auth-info … #:expires-at 0) 1)` → `#t` (NOT a `#f`-no-expiry fallthrough). A naive `(and (auth-info-expires-at ai) …)` works because `0` is truthy in Racket — but pin it with a test so a future "falsy" refactor cannot regress it.
- **`auth-info-has-scope?` (metadata helper, PINNED).** `(and (member scope (auth-info-scopes ai)) #t)`.
- **JSON round-trip keys (PINNED — camelCase + omit-on-`#f`).** `auth-info->json` emits `token` / `clientId` / `scopes`, and (when non-`#f`) `expiresAt` / `resource` / `extra`, omitting absent optionals (mirror S1's `put`-skips-`#f` discipline). **`expires-at = 0` is emitted (S4):** the omit test is `#f`-valued, NOT falsy-valued — `0` is present, so `(hash-has-key? (auth-info->json (make-auth-info … #:expires-at 0)) 'expiresAt)` → `#t`. **`extra = (hasheq)` (present-but-empty) is emitted (S4):** `#f` ≠ empty hash, so an empty-but-present `extra` round-trips as a present `{}` (assert it survives). `json->auth-info` is the inverse. This is the wire form S8 server-side verification produces and client-side consumes.
- **`json->auth-info` DECODE-REJECT discipline (PINNED — C2/C4, security-relevant).** The decoder is NOT a silent `#f`-filler — it follows the codebase's `h-req`/`json->struct` self-reject discipline. It MUST:
  - read the camelCase wire keys `token` / `clientId` / `scopes` / `expiresAt` / `resource` / `extra` (NOT kebab-case) — proven by a **literal-wire** decode test (C4), not just a self-symmetric round-trip;
  - **raise** (an `exn:fail?` — `h-req`-style "required field missing" or a contract violation) when `token` or `clientId` is **absent**, or when `token`/`clientId` is a **non-string**, or when `scopes` is **absent or not a list of strings**. Silently building an `auth-info` with `#f` token is a **security footgun** (an unauthenticated token treated as authenticated) — REJECT, do not tolerate. This is exactly the project's "decoder silently accepts malformed input" trap; the rejection contract is PINNED and MUST be asserted with `check-exn` (see Testing Strategy auth Part 7).
  - Implementation note: route required-field reads through the same `h-req` helper S1 decoders use (so the "missing required field" message is consistent), and let `make-auth-info`'s field contracts (below) catch the type violations — i.e. `json->auth-info` builds via `make-auth-info`, inheriting its `auth-info/c` rejection.
- **`make-auth-info` / `auth-info/c` enforce the field contracts (PINNED — C3, MUST be falsified by a test).** A `#:transparent` struct with a never-exercised contract is indistinguishable from one with no contract — so the contract claim is **unfalsifiable** unless a test feeds it a bad value. `make-auth-info` MUST be contracted (via `define/contract`, a `provide`d `contract-out`, or an explicit `auth-info/c` guard inside the constructor) so that `#:token 5` / `#:expires-at -1` / `#:scopes "read"` / `#:resource 5` / `#:extra "x"` each raise `exn:fail:contract?`. At least three of these MUST be asserted (see Testing Strategy auth Part 8) or the contract claim is unproven. (`expires-at -1` must violate `exact-nonnegative-integer?` — the reason the field is `nonnegative`, not bare `integer?`.)
- **`resourceUrlFromServerUrl` / `checkResourceAllowed` are OUT of scope here (PINNED).** Those `authUtils.ts` helpers operate on parsed URLs (origin + path-prefix matching) and belong to S8's resource-indicator handling; pulling them in now would force URL parsing (the `net/url`/tcp portability hazard above) for no S2 consumer. Note them as S8 work; do NOT implement them in M5d.

### Imports + portability (PINNED — both modules)

- **M5c** imports **S1** — specifically `constants.rkt` (the five reserved-key string constants) via `mcp/core/main.rkt` (or `mcp/core/types/constants.rkt` directly); plus `racket/base`. It defines the three trace-key constants itself. No transport/engine/role module, **no `net/*`, no `racket/system`, no `racket/tcp`/`racket/udp`, no subprocess/socket.**
- **M5d** imports `racket/base` + `racket/contract` (for the field contracts) + S1's `json-object?` (via `mcp/core/main.rkt`) for the `extra`/`->json` contracts. Same portability ban: **no `net/url` (it pulls `racket/tcp`)**, no subprocess/socket.
- **Both import only S1** (the queue's ceiling). Neither pulls a transport, engine, or role.
- **Restricted-load portability is deferred to item 017** — the collection-wide S2 restricted-namespace sweep (which includes `metadata-utils.rkt` + `auth.rkt`) is item 017's job. This item does NOT add a per-module `module->imports` walk (consistent with item 014). Honor the no-`net/*`/no-socket import discipline; item 017 proves it.

### Scope guards (explicit — do NOT cross these lines)

- **No OAuth logic.** No OAuth zod-schema analogues (`OAuthMetadataSchema`, `OAuthTokensSchema`, client registration, etc.) — those are S8/M14. M5d is the `AuthInfo` struct + token/metadata helpers ONLY.
- **No W3C trace-context parsing.** `traceparent`/`tracestate`/`baggage` pass through opaque; M5c does not parse/validate their header formats.
- **No `net/url`.** Holds `resource` as a string; full `net/url` pulls `racket/tcp` (socket) and breaks portability.
- **No struct-dispatch `get-display-name` overload.** One surface: the symbol-keyed hash form.
- **No name mutation / no canonicalization.** `get-display-name` reads precedence; it does not transform.
- **No `(module+ test …)`** in either module — tests live under `mcp/core/shared/test/` (consistent with items 010–014).
- **Explicit `provide`** — never `(all-defined-out)` (architecture §1.3). No internal helper leaks.

---

## Acceptance Criteria

### M5c — `mcp/core/shared/metadata-utils.rkt`

- [ ] `mcp/core/shared/metadata-utils.rkt` exists as `#lang racket/base` with an explicit curated `provide`. It lives in the existing `mcp/core/shared/` collection (created by item 013).
- [ ] Exports exactly: `get-display-name`; the eight reserved-key string constants (`PROTOCOL-VERSION-META-KEY`, `CLIENT-INFO-META-KEY`, `CLIENT-CAPABILITIES-META-KEY`, `LOG-LEVEL-META-KEY`, `RELATED-TASK-META-KEY` re-exported from S1, **plus** `TRACEPARENT-META-KEY`, `TRACESTATE-META-KEY`, `BAGGAGE-META-KEY` defined here); `reserved-meta-keys` (the 8-element symbol list) and/or `reserved-meta-key-strings`; `reserved-meta-key?`; `meta-ref`; `meta-set`. No internal helpers leak.
- [ ] **`get-display-name` precedence (G1).** `(get-display-name (hasheq 'name "n" 'title "t"))` → `"t"`; `(get-display-name (hasheq 'name "n" 'title "" 'annotations (hasheq 'title "a")))` → `"a"` (empty-string-title fallthrough into annotations.title); `(get-display-name (hasheq 'name "n" 'title ""))` → `"n"` (empty-string-title + no annotations → name); `(get-display-name (hasheq 'name "n"))` → `"n"` (no title, no annotations → name); `(get-display-name (hasheq 'name "n" 'annotations (hasheq 'title "a")))` → `"a"` (no title → annotations.title); `(get-display-name (hasheq 'name "n" 'title "t" 'annotations (hasheq 'title "a")))` → `"t"` (title wins over annotations.title); `(get-display-name (hasheq 'name "n" 'annotations (hasheq 'title "")))` → `"n"` (empty annotations.title falls through to name).
- [ ] **`get-display-name` malformed-`annotations` does NOT crash (C1).** `(get-display-name (hasheq 'name "n" 'annotations (json-null)))` → `"n"` and `(get-display-name (hasheq 'name "n" 'annotations "garbage"))` → `"n"` — a `null`/non-hash `annotations` falls through to `name`, neither raises. (The `(hash? annotations)` guard is present.)
- [ ] **`get-display-name` non-string `title` falls through (S5 divergence).** `(get-display-name (hasheq 'name "n" 'title (json-null)))` → `"n"` (Racket's `string?` guard is stricter than TS; documented divergence, not verbatim).
- [ ] **`get-display-name` missing `name` raises (S6).** `(check-exn exn:fail? (λ () (get-display-name (hasheq 'title ""))))` — no `name` key reaches rung 3 and raises (no `#f`/`""` fallback).
- [ ] **Trace-key constants exist (5-vs-8 reconciliation).** `TRACEPARENT-META-KEY` = `"traceparent"`, `TRACESTATE-META-KEY` = `"tracestate"`, `BAGGAGE-META-KEY` = `"baggage"`; `(length reserved-meta-keys)` = **8**; each of the eight key symbols is a member of `reserved-meta-keys`; `(reserved-meta-key? 'traceparent)` → `#t`, `(reserved-meta-key? TRACEPARENT-META-KEY)` → `#t` (string form accepted), `(reserved-meta-key? 'someUserKey)` → `#f`.
- [ ] **Two-notions-of-reserved boundary (S1).** `(reserved-meta-key? 'progressToken)` → `#f` — `progressToken` is reserved at the S1 `RequestParams` level (`request-meta-reserved-keys`) but is NOT one of the 8 namespaced `_meta` reserved keys. (Asserted negative + documented in the module doc block.)
- [ ] **`_meta` accessor/setter round-trip + non-reserved untouched.** Starting from a `_meta` hash, `meta-set` each reserved key (e.g. `traceparent`, `logLevel`) and `meta-ref` it back to the value written; a non-reserved key already present (e.g. `'someUserKey`) is left untouched by those `meta-set`s (`(meta-ref result 'someUserKey)` unchanged); `meta-set` returns a NEW hash (input unchanged — functional).
- [ ] **Accessor key normalization on a PREFIXED key (S2).** `(define m (meta-set (hasheq) LOG-LEVEL-META-KEY "debug"))` then BOTH `(meta-ref m LOG-LEVEL-META-KEY)` → `"debug"` AND `(meta-ref m (string->symbol LOG-LEVEL-META-KEY))` → `"debug"` — a string-keyed set is readable by the equivalent symbol (and vice-versa), proven on a prefixed (pipe-quoted-symbol) key, not just a short word.
- [ ] **`meta-ref` missing-key behaviour (S3).** `(meta-ref (hasheq) 'absent)` → `#f` (no `default` arg, missing key → `#f`, does NOT raise); `(meta-ref (hasheq) 'absent 'dflt)` → `'dflt`.
- [ ] **Trace keys pass through the S1 `_meta` envelope (C5/S7).** A `_meta` hash carrying `traceparent`, `tracestate`, AND `baggage` plus the three required reserved keys **as valid sub-objects** (the pinned fixture — `clientInfo` = `(hasheq 'name "c" 'version "1")`, `clientCapabilities` = `(hasheq)`, `protocolVersion` = a version string), fed through S1 `json->request-meta` then `request-meta->json`, re-emits all three trace keys verbatim; `(meta-ref re-emitted TRACEPARENT-META-KEY)` / `…TRACESTATE…` / `…BAGGAGE…` each return the original value. (Documents that S1's `request-meta` treats the trace keys as unreserved passthrough — the reason M5c owns their constants.)
- [ ] Module doc block documents: the `get-display-name` precedence + empty-string fallthrough + the **non-string-title / null-`annotations` divergences from TS** (not verbatim); the **5-vs-8 reserved-key discrepancy** and the SEP-414 unprefixed-key exception; the **two-notions-of-reserved** boundary (M5c's 8 ≠ S1's `request-meta-reserved-keys`); that the SDK does NOT interpret trace-context values.

### M5d — `mcp/core/shared/auth.rkt`

- [ ] `mcp/core/shared/auth.rkt` exists as `#lang racket/base` with an explicit curated `provide`. Lives in `mcp/core/shared/`.
- [ ] Exports exactly: the struct `auth-info` (with `auth-info?` / `auth-info-token` / `auth-info-client-id` / `auth-info-scopes` / `auth-info-expires-at` / `auth-info-resource` / `auth-info-extra`); `make-auth-info`; `auth-info-expired?`; `auth-info-has-scope?`; `auth-info->json`; `json->auth-info`. No internal helpers leak.
- [ ] **Field surface EXACT (G1).** `auth-info` has **exactly** the fields `token`, `client-id`, `scopes`, `expires-at`, `resource`, `extra` — in that order — and NO others. (Assert via `(struct->vector (make-auth-info …))` length = 7 [tag + 6 fields] and accessor presence; assert no extra accessor exists.)
- [ ] **Construct + required/optional.** `(make-auth-info #:token "t" #:client-id "c")` builds an `auth-info` with `scopes` = `'()`, `expires-at`/`resource`/`extra` = `#f`; supplying `#:scopes (list "read" "write") #:expires-at 1700000000 #:resource "https://api.example.com/mcp" #:extra (hasheq 'k "v")` populates each field.
- [ ] **`make-auth-info` / `auth-info/c` REJECT bad field values (C3 — contract is falsified).** Each of: `(make-auth-info #:token 5 #:client-id "c")` (non-string token); `(make-auth-info #:token "t" #:client-id "c" #:expires-at -1)` (negative → violates `exact-nonnegative-integer?`); `(make-auth-info #:token "t" #:client-id "c" #:scopes "read")` (string, not a list); `(make-auth-info #:token "t" #:client-id "c" #:resource 5)` (non-string resource); `(make-auth-info #:token "t" #:client-id "c" #:extra "x")` (non-json-object extra) — raises `exn:fail:contract?`. **At least three of these MUST be asserted** (the contract is otherwise unfalsifiable).
- [ ] **`auth-info-expired?` (token helper).** `(auth-info-expired? (make-auth-info #:token "t" #:client-id "c" #:expires-at 100) 200)` → `#t` (expired); `… #:expires-at 300) 200)` → `#f` (not yet); with `expires-at` = `#f` → `#f` (no expiry → not expired); boundary `(… #:expires-at 200) 200)` → `#t` (`<=`); **`expires-at = 0` (S4):** `(auth-info-expired? (make-auth-info #:token "t" #:client-id "c" #:expires-at 0) 1)` → `#t` (epoch 0 is a real expiry, not a `#f`-fallthrough).
- [ ] **`auth-info-has-scope?` (metadata helper).** `(auth-info-has-scope? (make-auth-info #:token "t" #:client-id "c" #:scopes (list "read" "write")) "read")` → `#t`; `… "admin")` → `#f`; empty scopes → `#f`.
- [ ] **JSON encode + round-trip.** `(json->auth-info (auth-info->json ai))` reconstructs `ai` (`check-equal?` on a fully-populated `ai` and on a minimal `ai`); `auth-info->json` emits camelCase keys `token`/`clientId`/`scopes` and omits **`#f`** optionals (a minimal `ai`'s json has NO `expiresAt`/`resource`/`extra` keys); **`expires-at = 0` IS emitted (S4):** `(hash-has-key? (auth-info->json (make-auth-info #:token "t" #:client-id "c" #:expires-at 0)) 'expiresAt)` → `#t`; **empty-but-present `extra` IS emitted (S4):** an `ai` with `#:extra (hasheq)` round-trips with a present (empty) `extra`.
- [ ] **JSON decode reads camelCase from a LITERAL wire hash (C4 — round-trip de-vacuumed).** `(json->auth-info (hasheq 'token "t" 'clientId "c" 'scopes (list "read") 'expiresAt 100 'resource "https://x/mcp"))` `check-equal?`s `(make-auth-info #:token "t" #:client-id "c" #:scopes (list "read") #:expires-at 100 #:resource "https://x/mcp")` — proves the decoder honors `clientId`/`expiresAt` (camelCase), not kebab-case (a self-symmetric round-trip would pass even if both sides used the wrong key).
- [ ] **`json->auth-info` REJECTS malformed wire input (C2 — security-relevant).** `(check-exn exn:fail? (λ () (json->auth-info (hasheq 'clientId "c" 'scopes '()))))` (missing `token`); `(check-exn exn:fail? (λ () (json->auth-info (hasheq 'token "t" 'scopes '()))))` (missing `clientId`); `(check-exn exn:fail? (λ () (json->auth-info (hasheq 'token 5 'clientId "c" 'scopes '()))))` (non-string token); `(check-exn exn:fail? (λ () (json->auth-info (hasheq 'token "t" 'clientId "c" 'scopes "read"))))` (`scopes` not a list). The decoder MUST raise, NOT silently build an `auth-info` with an `#f`/garbage token.
- [ ] **`resource` is a string.** A populated `ai`'s `resource` field is a `string?` (not a parsed URL object); the module imports NO `net/url`.
- [ ] Module doc block documents: the field surface mirrors TS `AuthInfo` (`types/types.ts:435`); the `resource`-as-string portability decision (no `net/url`/tcp); the `json->auth-info` decode-reject discipline (raise on missing/ill-typed required fields); that NO OAuth logic lives here.

### Both / cross-cutting

- [ ] **Imports = S1 only.** Each module requires only `mcp/core/main.rkt` (or `mcp/core/types/constants.rkt`) + base collections (`racket/base`, M5d also `racket/contract`). Neither requires a transport/engine/role/subprocess/socket module, and **neither requires `net/*`** (no `net/url`). (The transitive restricted-load proof is item 017's collection-wide sweep — not duplicated here.)
- [ ] **No `(module+ test …)`** in either module — tests live in `mcp/core/shared/test/metadata-utils-test.rkt` and `mcp/core/shared/test/auth-test.rkt`.
- [ ] `raco make mcp/core/shared/metadata-utils.rkt mcp/core/shared/auth.rkt` exits 0 (compiles clean, no warnings).
- [ ] `raco test mcp/core/shared/` passes (exit 0) — the two new modules + tests compile and run cleanly alongside the existing `uri-template` (item 013) and `tool-name-validation` (item 014) suites. Sibling suites `raco test mcp/core/validators/` and `raco test mcp/core/util/` remain green (this item touches neither).
- [ ] **Progress** (`docs/aide/progress.md`): flip the `metadata-utils.rkt` AND `auth.rkt` Stage-S2 deliverable lines (📋 → 🚧 → ✅). The parity-matrix `metadataUtils` / `auth` rows flip to `partial` in **item 017**, NOT here (see Completion Reminder).

---

## Implementation Steps

1. **Re-read the references** for shape + behaviour:
   - `typescript-sdk/packages/core/src/shared/metadataUtils.ts` — the `getDisplayName` precedence + the empty-string/`undefined` guard order.
   - `typescript-sdk/packages/core/src/types/constants.ts` — the **eight** reserved `_meta` keys (note keys 6–8 `traceparent`/`tracestate`/`baggage` are SEP-414, unprefixed).
   - `typescript-sdk/packages/core/src/types/types.ts:435` — the `AuthInfo` field list + the `expiresAt` (seconds since epoch) and `resource` (URL) doc comments.
   - `mcp/core/types/constants.rkt:60-64` — the five S1 reserved-key string constants (already `provide`d).
   - `mcp/core/types/spec-2026-07-28.rkt:436-487` — the `request-meta` envelope: `request-meta-reserved-keys`, `json->request-meta`, `request-meta->json` (note the trace keys are NOT in the reserved list → they pass through `rest`).
2. **The design decisions are PINNED** (do not re-decide): `get-display-name` over a symbol-keyed hash (no struct overload); define the 3 trace constants in M5c + aggregate all 8; `auth-info` struct with the EXACT 6-field surface; `resource` as a string (no `net/url`); helpers `auth-info-expired?` / `auth-info-has-scope?` / json round-trip; NO OAuth logic; both import only S1.
3. **Write `mcp/core/shared/metadata-utils.rkt`** (`#lang racket/base`):
   - `(require mcp/core/main.rkt)` (or `mcp/core/types/constants.rkt`) for the five S1 reserved-key constants. NO `net/*`.
   - Module doc block: the precedence + empty-string fallthrough + the **non-string-title / null-`annotations` divergences from TS** (not verbatim); the 5-vs-8 reconciliation + SEP-414 unprefixed exception; the **two-notions-of-reserved** boundary (M5c's 8 ≠ S1's `request-meta-reserved-keys`; `progressToken` is S1-reserved but not a namespaced `_meta` key); SDK-does-not-interpret-trace-values note; the no-`net/*` portability note.
   - `get-display-name` per the pinned cond (rung 1 non-empty STRING title → rung 2 `(hash? annotations)`-guarded non-empty annotations.title → rung 3 `name` with no default). The `(hash? annotations)` guard (C1) is mandatory — a `null`/non-hash `annotations` must fall through, not crash.
   - `TRACEPARENT-META-KEY` / `TRACESTATE-META-KEY` / `BAGGAGE-META-KEY` = the three plain strings.
   - `reserved-meta-key-strings` (all 8) + `reserved-meta-keys` (`(map string->symbol …)`).
   - `reserved-meta-key?` (accept string or symbol; normalize to symbol; `memq` against `reserved-meta-keys`).
   - `meta-ref` / `meta-set` (normalize key string-or-symbol to symbol; `meta-ref` no-default → `#f`, S3; `meta-set` functional via `hash-set`).
   - Explicit `provide` block.
4. **Write `mcp/core/shared/auth.rkt`** (`#lang racket/base`):
   - `(require racket/contract)` + `(require mcp/core/main.rkt)` for `json-object?` + the `h-req`-style required-field helper (reuse S1's, or a local equivalent). NO `net/url`.
   - Module doc block: AuthInfo field surface mirrors TS `types.ts:435`; `resource`-as-string (no `net/url`/tcp) decision; the `json->auth-info` decode-reject discipline; NO-OAuth scope note.
   - `(struct auth-info (token client-id scopes expires-at resource extra) #:transparent)` + `auth-info/c` contract.
   - `make-auth-info` smart constructor (keyword args, defaults `scopes='()`, optionals `#f`) — **contracted** (via `contract-out`/`define/contract`/explicit guard) so bad field values raise `exn:fail:contract?` (C3).
   - `auth-info-expired?` (optional `now-seconds`, default `(current-seconds)`; `#f` expires-at → `#f`; `<=` boundary; `expires-at = 0` is a real expiry, S4).
   - `auth-info-has-scope?`.
   - `auth-info->json` (camelCase keys, omit `#f` optionals via `put`-skips-`#f`; `0`/empty-hash are NOT omitted, S4) + `json->auth-info` (inverse — reads camelCase, **raises** on missing/ill-typed `token`/`clientId`/`scopes` per the decode-reject discipline, C2; build via `make-auth-info` to inherit `auth-info/c`).
   - Explicit `provide` (`struct-out auth-info` + the helpers).
5. **Write the tests** `mcp/core/shared/test/metadata-utils-test.rkt` + `mcp/core/shared/test/auth-test.rkt` (see Testing Strategy). Port the precedence + field-surface + helper behaviours; assert the S1 envelope round-trip for the trace keys.
6. **Run** `raco make` on both modules, then `raco test mcp/core/shared/`. Fix any failure. Confirm `raco test mcp/core/validators/` and `raco test mcp/core/util/` still pass (untouched).
7. **Update progress** (see Completion Reminder).

---

## Testing Strategy

Two fixture/behaviour-port test files under `mcp/core/shared/test/`, both `#lang racket/base` with `(require rackunit …)`. No external services; `raco test` only.

### `metadata-utils-test.rkt`

`(require rackunit json (file "../metadata-utils.rkt") mcp/core/main.rkt)` — `json` for `(json-null)` (the C1/S5 malformed-input cases); `mcp/core/main.rkt` for the S1 `request-meta` round-trip + the S1 `…-META-KEY` constants.

**Part 1 — `get-display-name` precedence (G1).** The seven happy-path cases from the acceptance criteria: title-wins, empty-title→annotations.title, empty-title→name, no-title→annotations.title, no-title-no-annotations→name, title-over-annotations, empty-annotations.title→name. Each a `check-equal?`.

**Part 1b — `get-display-name` malformed/irregular input (C1, S5, S6).**
- `(check-equal? (get-display-name (hasheq 'name "n" 'annotations (json-null))) "n")` — `null` annotations, NO crash (C1).
- `(check-equal? (get-display-name (hasheq 'name "n" 'annotations "garbage")) "n")` — non-hash annotations, NO crash (C1).
- `(check-equal? (get-display-name (hasheq 'name "n" 'title (json-null))) "n")` — non-string title falls through (S5 divergence).
- `(check-exn exn:fail? (λ () (get-display-name (hasheq 'title ""))))` — missing `name` raises (S6).

**Part 2 — reserved-key constants + predicate + the two-notions boundary.** `(check-equal? TRACEPARENT-META-KEY "traceparent")` (+ tracestate/baggage); `(check-equal? (length reserved-meta-keys) 8)`; each of the 8 key symbols `(check-true (and (memq k reserved-meta-keys) #t))`; `(check-true (reserved-meta-key? 'traceparent))`; `(check-true (reserved-meta-key? TRACEPARENT-META-KEY))`; `(check-false (reserved-meta-key? 'someUserKey))`; **`(check-false (reserved-meta-key? 'progressToken))`** with a comment: reserved at the S1 `RequestParams` level (`request-meta-reserved-keys`) but NOT a namespaced `_meta` reserved key (S1).

**Part 3 — `meta-ref` / `meta-set` round-trip, non-reserved untouched, key normalization, missing-key.** Start `(define m0 (hasheq 'someUserKey "keep"))`; `(define m1 (meta-set m0 'traceparent "00-abc-01"))`; `(check-equal? (meta-ref m1 'traceparent) "00-abc-01")`; `(check-equal? (meta-ref m1 'someUserKey) "keep")` (untouched); `(check-equal? (meta-ref m0 'traceparent) #f)` (m0 unchanged — functional, no-default → `#f`); also `meta-set` a reserved `logLevel` key and read back.
- **Prefixed-key string/symbol equivalence (S2):** `(define ml (meta-set (hasheq) LOG-LEVEL-META-KEY "debug"))`; `(check-equal? (meta-ref ml LOG-LEVEL-META-KEY) "debug")`; `(check-equal? (meta-ref ml (string->symbol LOG-LEVEL-META-KEY)) "debug")` — string-set readable by the equivalent (pipe-quoted) symbol.
- **Missing-key default (S3):** `(check-equal? (meta-ref (hasheq) 'absent) #f)` (no default → `#f`, no raise); `(check-equal? (meta-ref (hasheq) 'absent 'dflt) 'dflt)`.

**Part 4 — trace keys pass through the S1 envelope (C5/S7) — PINNED fixture.** Build the wire `_meta` hash with the three S1-required reserved keys **as valid sub-objects** (NOT bare strings — see the C5 pin):
```racket
(define meta-in
  (hasheq (string->symbol PROTOCOL-VERSION-META-KEY)    "2026-07-28"
          (string->symbol CLIENT-INFO-META-KEY)         (hasheq 'name "c" 'version "1")
          (string->symbol CLIENT-CAPABILITIES-META-KEY) (hasheq)
          'traceparent "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
          'tracestate  "vendor1=value1"
          'baggage     "userId=alice"))
(define re-emitted (request-meta->json (json->request-meta meta-in)))
(check-equal? (meta-ref re-emitted TRACEPARENT-META-KEY) "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
(check-equal? (meta-ref re-emitted TRACESTATE-META-KEY)  "vendor1=value1")
(check-equal? (meta-ref re-emitted BAGGAGE-META-KEY)     "userId=alice")
```
If `json->client-capabilities` rejects `(hasheq)` (confirm against `spec-2026-07-28.rkt:395-398` first — it should accept, as it wraps the raw object), substitute the minimal accepted capabilities shape. (Confirms all three trace keys survive S1's unreserved `rest` passthrough untouched.)

### `auth-test.rkt`

`(require rackunit (file "../auth.rkt"))`.

**Part 1 — construct + defaults.** `make-auth-info` minimal (token+client-id) → scopes `'()`, optionals `#f`; fully-populated → each field set. `check-equal?` on accessors.

**Part 2 — field surface EXACT.** Assert the struct has exactly 6 fields in order: `(check-equal? (vector-length (struct->vector (make-auth-info #:token "t" #:client-id "c"))) 7)` (tag + 6 fields); assert each accessor returns the right field; (optionally) confirm via `struct-info`/doc that no 7th field exists.

**Part 3 — `auth-info-expired?` (token helper).** expired (`#:expires-at 100`, now 200 → `#t`); not-yet (`300`, now 200 → `#f`); boundary (`200`, now 200 → `#t`); no-expiry (`#f` → `#f`); **`expires-at = 0` (S4):** `(check-true (auth-info-expired? (make-auth-info #:token "t" #:client-id "c" #:expires-at 0) 1))` — epoch 0 is a real expiry, not a falsy fallthrough.

**Part 4 — `auth-info-has-scope?` (metadata helper).** member → `#t`; non-member → `#f`; empty scopes → `#f`.

**Part 5 — JSON encode (omit-on-`#f`) + symmetric round-trip.** Fully-populated `ai`: `(check-equal? (json->auth-info (auth-info->json ai)) ai)`; minimal `ai`: same, AND `(check-false (hash-has-key? (auth-info->json minimal) 'expiresAt))` (+ `resource`/`extra` absent); assert camelCase `(check-true (hash-has-key? (auth-info->json ai) 'clientId))`.
- **`expires-at = 0` IS emitted (S4):** `(check-true (hash-has-key? (auth-info->json (make-auth-info #:token "t" #:client-id "c" #:expires-at 0)) 'expiresAt))`.
- **empty-but-present `extra` IS emitted (S4):** for `(define e0 (make-auth-info #:token "t" #:client-id "c" #:extra (hasheq)))`, `(check-true (hash-has-key? (auth-info->json e0) 'extra))` AND `(check-equal? (auth-info-extra (json->auth-info (auth-info->json e0))) (hasheq))` — `#f` ≠ empty hash; an empty `extra` survives.

**Part 6 — JSON decode from a LITERAL wire hash (C4 — de-vacuumed).** Hand-build the wire hash (NOT via `auth-info->json`) and assert the decoder reads camelCase:
```racket
(check-equal?
  (json->auth-info (hasheq 'token "t" 'clientId "c" 'scopes (list "read") 'expiresAt 100 'resource "https://x/mcp"))
  (make-auth-info #:token "t" #:client-id "c" #:scopes (list "read") #:expires-at 100 #:resource "https://x/mcp"))
```
Proves `json->auth-info` honors `clientId`/`expiresAt` (camelCase) — a self-symmetric round-trip alone would pass even if encode AND decode both used the wrong key.

**Part 7 — `json->auth-info` REJECTS malformed wire input (C2 — security-relevant).**
- `(check-exn exn:fail? (λ () (json->auth-info (hasheq 'clientId "c" 'scopes '()))))` — missing `token`.
- `(check-exn exn:fail? (λ () (json->auth-info (hasheq 'token "t" 'scopes '()))))` — missing `clientId`.
- `(check-exn exn:fail? (λ () (json->auth-info (hasheq 'token 5 'clientId "c" 'scopes '()))))` — non-string `token`.
- `(check-exn exn:fail? (λ () (json->auth-info (hasheq 'token "t" 'clientId "c" 'scopes "read"))))` — `scopes` not a list.
The decoder MUST raise (per the codebase `h-req`/`json->struct` self-reject discipline), NOT silently build an `auth-info` with an `#f`/garbage token (a security footgun).

**Part 8 — `make-auth-info` REJECTS bad field values (C3 — contract falsified).** At minimum three of:
- `(check-exn exn:fail:contract? (λ () (make-auth-info #:token 5 #:client-id "c")))` — non-string token.
- `(check-exn exn:fail:contract? (λ () (make-auth-info #:token "t" #:client-id "c" #:expires-at -1)))` — negative (violates `exact-nonnegative-integer?`).
- `(check-exn exn:fail:contract? (λ () (make-auth-info #:token "t" #:client-id "c" #:scopes "read")))` — string, not a list.
- (optional) `#:resource 5` (non-string), `#:extra "x"` (non-json-object).
Without these the `auth-info/c` contract claim is unfalsifiable (a `#:transparent` struct with an unexercised contract is identical to one with none).

**Part 9 — `resource` is a string.** `(check-true (string? (auth-info-resource (make-auth-info #:token "t" #:client-id "c" #:resource "https://api.example.com/mcp"))))`.

### Fixture provenance

- `get-display-name` cases ← TS `metadataUtils.ts` precedence semantics (TS has no dedicated test file for it; the cases are derived from the documented precedence + the empty-string guard — record this in the test header).
- `AuthInfo` field surface ← TS `types/types.ts:435`. The OAuth zod-schema fixtures in `auth.test.ts` are **out of scope** (no OAuth logic); the `authUtils.test.ts` `resourceUrlFromServerUrl`/`checkResourceAllowed` fixtures are **deferred to S8** (those helpers are not implemented here). Note this in the test header so a reviewer does not expect them.

---

## Dependencies

- **Upstream work items:**
  - **S1 (items 001–008)** — M5c re-exports the five reserved-key string constants from `mcp/core/types/constants.rkt` and round-trips with the `request-meta` envelope from `mcp/core/types/spec-2026-07-28.rkt` (item 004); M5d uses `json-object?` from S1. Both require S1 via `mcp/core/main.rkt`.
  - **Item 013** created the `mcp/core/shared/` + `mcp/core/shared/test/` collection directories, into which these two modules + their tests are added.
- **Downstream consumers (informational):**
  - **S6b** high-level server (`mcp/server/mcp.rkt`, M12b) — `register-tool` calls `get-display-name` (and may consult the reserved `_meta` keys). M5c has NO S2 consumer; it ships fully tested standalone.
  - **S8** auth (M14) — client `mcp/client/auth.rkt` + server `mcp/server/auth/` both consume `auth-info`; the `resourceUrlFromServerUrl`/`checkResourceAllowed` helpers (deferred here) land in S8. M5d has NO S2 consumer.
  - **Item 017** — the S2 collection-wide restricted-load portability sweep includes both modules AND flips the parity-matrix `metadataUtils` / `auth` rows to `partial`. (This item does NOT flip those rows.)
  - **Item 018** — the S2 demo headline is schema + URI template + stdio; it MAY optionally touch these modules.
- **Tooling/runtime:** Racket ≥ 8.x (`raco`, `rackunit`). The `typescript-sdk/` checkout MUST be present for **authoring** (behaviour from `metadataUtils.ts` / `constants.ts` / `types.ts:435`); the Racket tests do NOT parse the `.ts` at runtime (fixtures transcribed into Racket assertions).

---

## Decisions & Trade-offs

To be updated during implementation.

The **design decisions below are PINNED at spec time** (real choices, not options). The **post-build outcome** (require list as built, exact check counts) is *to be updated during implementation*.

**(a) `get-display-name` operates on a symbol-keyed JSON-object hash, not a struct-dispatch zoo.** Mirrors the TS duck-typed object 1:1, round-trips with the wire form, keeps the `annotations.title` rung testable without constructing a full multi-field `tool` struct, and avoids drift across six heterogeneous S1 struct types. M12b calls `(get-display-name (tool->json t))` or builds a 3-key hash. **To be updated during implementation.**

**(b) Empty-string title is treated as absent (fallthrough); but the title rungs are NOT a verbatim TS port.** TS's `title !== undefined && title !== ''` is matched for the empty-string case: `""` falls through rung 1 (and a `""` annotations.title falls through rung 2). The empty-string-title→annotations.title→name path is the load-bearing test. **Two deliberate divergences from TS (documented, not verbatim):** (i) **non-string `title`/`annotations.title`** — Racket's `(and (string? …) …)` guard is stricter than TS's `!== ''`, so a `null`/`42` title falls through (TS would *return* it); intentional, a display name must be a string (S5). (ii) **`null`/non-hash `annotations`** — guarded by `(hash? annotations)` so it falls through to `name` rather than crashing on the inner `hash-ref` (TS's optional chaining tolerates `null`); this is the C1 latent-crash fix. The module doc block must state both divergences; do not call the title rungs a byte-for-byte port. **To be updated during implementation.**

**(c) The three missing trace-context constants are defined in M5c (5-vs-8 reconciliation).** `traceparent`/`tracestate`/`baggage` (SEP-414, unprefixed) were not captured in S1; M5c defines them + aggregates all eight reserved keys in one place, closing the gap rather than silently dropping it. The alternative (file an S1 follow-up against `constants.rkt`) was considered and not chosen — co-locating the full set with the accessors is lower-friction. The SDK does not interpret the trace values; they pass through `_meta` untouched (and ride S1's `request-meta-rest` unreserved passthrough). **To be updated during implementation.**

**(d) `auth-info` mirrors the TS `AuthInfo` field surface EXACTLY (6 fields, `#:transparent`).** `token`/`client-id`/`scopes` required, `expires-at`/`resource`/`extra` optional → `#f`. `scopes` is required (TS `string[]`, no `?`) defaulting to `'()` in the constructor. The exact-surface test guards against field drift. **To be updated during implementation.**

**(e) `resource` is held as a STRING, not a parsed URL (portability).** Full `net/url` transitively pulls `racket/tcp` (a socket), violating the Portability NFR + breaking item 017's restricted-load sweep. Holding the URL string keeps M5d socket-free and matches the wire form. A pure parsed form (`net/url-structs`, no tcp) may be added at S8 if needed. **To be updated during implementation.**

**(f) Helpers are token/metadata only — NO OAuth.** `auth-info-expired?` (token), `auth-info-has-scope?` (metadata/scopes), `make-auth-info`, json round-trip. The OAuth zod schemas in TS `auth.ts` and the URL helpers in `authUtils.ts` (`resourceUrlFromServerUrl`/`checkResourceAllowed`) are S8/M14 and excluded here (the latter also for the `net/url` portability hazard). **To be updated during implementation.**

**(f2) `json->auth-info` self-rejects malformed wire input; `make-auth-info`/`auth-info/c` is contract-enforced (C2/C3/C4 — security + falsifiability).** `json->auth-info` follows the codebase's `h-req`/`json->struct` discipline: it raises (not silently `#f`-fills) on a missing/non-string `token` or `clientId` or a non-list `scopes` — silently accepting a missing token in an auth struct is a security footgun. `make-auth-info` is contracted so bad field values raise `exn:fail:contract?`. Both are PINNED **because the contracts are otherwise unfalsifiable** — a `#:transparent` struct with an unexercised contract is identical to one with none, and a self-symmetric JSON round-trip passes even if encode+decode share a wrong key. The Testing Strategy mandates `check-exn` rejection tests (auth Parts 7–8) + a literal-wire camelCase decode test (auth Part 6). **To be updated during implementation.**

**(g) Restricted-load portability deferred to item 017.** No per-module `module->imports` walk here (consistent with item 014); the collection-wide S2 sweep including both modules is item 017, which also flips the parity rows. **To be updated during implementation.**

**(h) Post-build outcomes (recorded at implementation).**
- **Require lists as built:** M5c = `(require "../main.rkt")` (relative S1 barrel — `mcp/core/main.rkt` is not a registered collection path; corrected to the codebase convention used by `util/schema.rkt`). M5d = `(require racket/contract "../main.rkt")`. Both NO `net/*`, NO subprocess/socket (grep clean — the only `net/`/`subprocess` hits are doc-block comments).
- **Exact check counts:** `raco test mcp/core/shared/` → **269 passed / 0 failed** (192 from items 013+014 + the two new suites). New suites alone: metadata-utils-test = **38**, auth-test = **39**. Sibling suites unaffected: `raco test mcp/core/validators/` → 300; `raco test mcp/core/util/` → 102.
- **`raco make`:** both modules → exit 0, clean (no warnings).
- **`get-display-name` input form:** symbol-keyed hash (confirmed); no struct overload shipped.
- **`resource` form:** string (confirmed); no `net/url`.
- **No `(module+ test …)`** in either module; tests under `mcp/core/shared/test/`.
- **`make-auth-info` contract mechanism:** `define/contract` (NOT `contract-out`). Rationale — `contract-out` only checks at the module boundary, so the internal `json->auth-info → make-auth-info` path would bypass it and the C2 non-string-token rejection test would fail; `define/contract` checks every call (internal included), keeping the decoder's type-rejection real.
- **S1 round-trip helpers:** `json->request-meta` / `request-meta->json` are re-exported `r26:`-prefixed via `types/main.rkt`, so the Part-4 envelope test calls `r26:json->request-meta` / `r26:request-meta->json`.

---

## Project-Specific Adaptations (Racket / raco / rackunit)

This is a **Racket library, not a service** — same adaptation pattern as items 010–014. The generic "Testing Prerequisites" template (Required Services / database / API endpoint / ports / health checks) does **not** apply and is adapted:

- **Required Services → None.** Pure Racket library; no external services, databases, message queues, HTTP servers, sockets, subprocesses, or network. Both modules are L0 and load-portable by construction (proven by item 017's collection-wide sweep). No I/O at all (no logger even — unlike item 014; these modules are pure data + functions).
- **Database / API endpoint / ports sections → N/A.** Removed; replaced by the Racket toolchain row below.
- **Required toolchain:** Racket ≥ 8.x (`raco test`, `rackunit`). (This env: Racket v8.18 [cs], per item 013.)
- **TS checkout role:** present at `typescript-sdk/`; **required for authoring** (behaviour from `metadataUtils.ts` / `constants.ts` / `types.ts:435`); not parsed at test runtime.
- **Manual Validation Checklist → specialized** to `raco make` / `raco test` + a REPL smoke check (below). No "service started" / "health check" / "screenshots" rows.
- **Language/naming:** `#lang racket/base`; kebab-case bindings; explicit `(provide …)` never `all-defined-out` (architecture §1.3); S1-only imports, no `net/*` (architecture §4.1 portability).
- **Collection directory:** `mcp/core/shared/` + `mcp/core/shared/test/` already exist (item 013). This item adds `metadata-utils.rkt`, `auth.rkt`, `test/metadata-utils-test.rkt`, `test/auth-test.rkt`.
- **No-consumer-in-S2 note:** like items 013/014, both modules have NO S2 consumer; they ship fully tested standalone and are wired up by S6b (M5c) / S8 (M5d).

---

## Testing Prerequisites (CRITICAL)

### Required Services

**None (pure Racket library; no external services).** No databases, message queues, HTTP servers, sockets, subprocesses, or network dependencies. No I/O whatsoever (no logger). The TS checkout is a **parity reference** read while authoring, not a runtime dependency.

| "Service" | Why | How to obtain | Port |
|---|---|---|---|
| Racket ≥ 8.x runtime | compile + run modules and tests (`raco`, `rackunit`) | system install (`racket --version` ≥ 8.0; this env: v8.18) | n/a |
| `typescript-sdk/` checkout | read while authoring to lift the display-name precedence (`metadataUtils.ts`), the eight reserved keys (`constants.ts`), and the `AuthInfo` shape (`types.ts:435`) — G1 parity | already present at repo root | n/a |

### Environment Configuration

- **Environment variables / secrets / config files / free ports:** none required.
- **Racket version:** ≥ 8.x (verified for item 013: v8.18 [cs]).
- **Working directory:** run `raco test` from the **repo root** so the `mcp/...` collection path resolves.
- **How to run:**
  - `raco make mcp/core/shared/metadata-utils.rkt mcp/core/shared/auth.rkt` — compile both modules clean.
  - `raco test mcp/core/shared/` — run all shared-collection tests (picks up the two new test files + the existing `uri-template` + `tool-name-validation` suites recursively), exit 0.
- **Pre-flight checks:**
  - `racket --version` → ≥ 8.0.
  - `raco test mcp/core/shared/` (pre-change) → green (items 013+014's 192 checks pass) so the baseline is known.

### Manual Validation Checklist

- [ ] `racket --version` ≥ 8.0.
- [ ] `raco make mcp/core/shared/metadata-utils.rkt mcp/core/shared/auth.rkt` → exit 0, no warnings.
- [ ] `raco test mcp/core/shared/` → exit 0; all checks pass (new + existing).
- [ ] `raco test mcp/core/validators/` → exit 0 (300 checks, untouched).
- [ ] `raco test mcp/core/util/` → exit 0 (102 checks, untouched).
- [ ] REPL smoke (metadata): `(require (file "mcp/core/shared/metadata-utils.rkt") json)` then `(get-display-name (hasheq 'name "n" 'title "" 'annotations (hasheq 'title "a")))` → `"a"`; **C1:** `(get-display-name (hasheq 'name "n" 'annotations (json-null)))` → `"n"` (no crash); `(length reserved-meta-keys)` → `8`; `(reserved-meta-key? 'traceparent)` → `#t`; `(reserved-meta-key? 'progressToken)` → `#f`.
- [ ] REPL smoke (auth): `(require (file "mcp/core/shared/auth.rkt"))` then `(auth-info-expired? (make-auth-info #:token "t" #:client-id "c" #:expires-at 100) 200)` → `#t`; `(auth-info-has-scope? (make-auth-info #:token "t" #:client-id "c" #:scopes (list "read")) "read")` → `#t`; `(string? (auth-info-resource (make-auth-info #:token "t" #:client-id "c" #:resource "https://x/mcp")))` → `#t`; **C2:** `(json->auth-info (hasheq 'clientId "c" 'scopes '()))` raises (missing token).
- [ ] Grep both modules for `net/` / `racket/system` / `racket/tcp` / `racket/udp` / `subprocess` → **no match** (portability discipline; item 017 proves transitively).
- [ ] Confirm neither module contains `(module+ test …)`.

### Expected Outcomes (concrete)

- **`get-display-name`:** the seven precedence cases return exactly `"t"`, `"a"`, `"n"`, `"n"`, `"a"`, `"t"`, `"n"` respectively (see Acceptance Criteria). Empty-string title NEVER returned. **Malformed input (C1/S5/S6):** `null`/non-hash `annotations` → `"n"` (no crash); non-string `title` → `"n"` (falls through); missing `name` → raises.
- **Reserved keys:** `(length reserved-meta-keys)` = **8**; `TRACEPARENT-META-KEY`/`TRACESTATE-META-KEY`/`BAGGAGE-META-KEY` = `"traceparent"`/`"tracestate"`/`"baggage"`; `reserved-meta-key?` accepts both string + symbol forms; an arbitrary user key → `#f`; **`progressToken` → `#f`** (S1 two-notions boundary).
- **`_meta` round-trip:** a written reserved key reads back identical; a pre-existing non-reserved key survives untouched; `meta-set` is non-mutating; `meta-ref` no-default-on-missing → `#f` (S3); string/symbol key equivalence holds on a prefixed key (S2); `traceparent`/`tracestate`/`baggage` ALL survive the S1 `json->request-meta` → `request-meta->json` cycle verbatim (with the pinned valid-sub-object fixture, C5/S7).
- **`auth-info`:** exactly 6 fields (`token`/`client-id`/`scopes`/`expires-at`/`resource`/`extra`); minimal construct → `scopes='()`, optionals `#f`; `auth-info-expired?` true at/after expiry (`<=`), false before / when `#f`, true for `expires-at=0` (S4); `auth-info-has-scope?` true iff member; json round-trip reconstructs (`check-equal?`) with camelCase keys + omitted `#f` optionals (but `0`/empty-hash emitted, S4); **literal-wire decode reads camelCase** (C4); **`json->auth-info` raises on missing/ill-typed `token`/`clientId`/`scopes`** (C2); **`make-auth-info` raises `exn:fail:contract?` on bad field values** (C3); `resource` is a `string?`.
- **Counts:** `raco test mcp/core/shared/` exits 0 with the two new suites' checks added to the existing 192; sibling suites stay at 300 (validators) / 102 (util).
- **Portability:** no `net/*` / subprocess / socket reference in either module.

### Validation Documentation Template

Record at completion (fill the bracketed values):

```
Item 015 — validation record
- Racket version: [racket --version output]
- raco make (both modules): [exit code; warnings?]
- raco test mcp/core/shared/   : [N checks passed / 0 failed]
    - metadata-utils-test.rkt alone: [N]
    - auth-test.rkt alone:           [N]
    - (existing uri-template + tool-name-validation: 192)
- raco test mcp/core/validators/ : [300 expected]
- raco test mcp/core/util/       : [102 expected]
- get-display-name 7 cases:      [pass/fail]
- get-display-name C1 (null/non-hash annotations no-crash): [pass/fail]
- get-display-name S5 (non-string title fallthrough):       [pass/fail]
- get-display-name S6 (missing name raises):                [pass/fail]
- reserved-meta-keys length:     [8]
- trace constants:               [traceparent/tracestate/baggage present]
- progressToken not reserved (S1):                          [#f: yes/no]
- meta-ref no-default missing → #f (S3):                    [pass/fail]
- meta-ref string/symbol key equiv on prefixed key (S2):    [pass/fail]
- _meta S1 envelope round-trip:  [traceparent/tracestate/baggage all survived: yes/no]
- auth-info field surface:       [exactly 6 fields: yes/no]
- auth-info-expired? boundary:   [<= at expiry: pass/fail]; expires-at=0 expired (S4): [pass/fail]
- json round-trip (full+minimal):[check-equal? pass/fail; #f-optionals omitted: yes/no]
- json encode 0/empty-extra emitted (S4):                   [pass/fail]
- json decode literal-wire camelCase (C4):                  [pass/fail]
- json->auth-info rejects malformed (C2, missing/non-string token, bad scopes): [pass/fail]
- make-auth-info rejects bad fields (C3, ≥3 check-exn):     [pass/fail]
- resource is string:            [yes/no]; net/url imported: [no expected]
- (module+ test …) present:      [no expected]
- net/* | subprocess | socket grep: [no match expected]
- Decisions & Trade-offs (h) updated with as-built require lists + counts: [yes/no]
```

---

## Completion Reminder

On completion, **`docs/aide/progress.md` MUST be updated** (the icon discipline is forward-only — 📋 → 🚧 → ✅, never reverted):

- Flip the **Stage S2 deliverable lines** for `mcp/core/shared/metadata-utils.rkt` (M5c) and `mcp/core/shared/auth.rkt` (M5d) from 📋 → 🚧 (on start) → ✅ (on completion), each with a one-line as-built summary mirroring the items 013/014 deliverable lines (transliteration source, key decisions, check count).
- **Do NOT** flip the parity-matrix `metadataUtils` / `auth` rows or the Stage-S2 acceptance boxes here — those belong to **item 017** (the collection-wide portability sweep + parity-row flips) and **item 018** (the S2 demo + closeout). This item owns only its two deliverable lines.
- Record the as-built require lists, the exact `raco test` check counts, and the `get-display-name` input form + `resource` form in **Decisions & Trade-offs (h)**.
