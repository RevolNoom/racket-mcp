# Reviewer Feedback — Work Queue 002 (Stage S2 Foundation)

**Artifact under review:** `docs/aide/versions/speckit.aide.create-queue/iteration-001-q2/queue-002.md`
(identical copy also at `docs/aide/queue/queue-002.md`)
**Reviewer role:** Reviewer in the AIDE create-queue workflow.
**Date:** 2026-06-22.
**Verdict:** Strong queue. Faithful S2 scope, correct numbering, good sizing. A handful of
**reference-path / "mirroring" claims are factually wrong against the actual TS checkout**, and a
few S2 acceptance criteria silently under-cover what the corresponding TS test suites exercise.
These are accuracy/coverage issues the Worker will trip on, not structural ones. **Needs a light
revision** before it goes to create-item.

---

## 1. Scope fidelity — does it cover all of S2, and only S2?

**Module coverage: complete and correctly mapped.** Every S2 module from roadmap §S2 has a home:

| Module | Roadmap deliverable | Queue item | OK? |
|--------|--------------------|-----------|-----|
| M3 port | `validators/provider.rkt` | 010 | ✅ |
| M3 default | `validators/from-json-schema.rkt` | 011 | ✅ |
| M4 | `util/schema.rkt` | 012 | ✅ |
| M5a | `shared/uri-template.rkt` | 013 | ✅ |
| M5b | `shared/tool-name-validation.rkt` | 014 | ✅ |
| M5c | `shared/metadata-utils.rkt` | 015 | ✅ |
| M5d | `shared/auth.rkt` | 015 | ✅ |
| M5e | `shared/stdio.rkt` | 016 | ✅ |

Plus item 017 (portability/parity-matrix touch) and item 018 (demo + closeout), both of which mirror
the S1 precedent (queue-001 items 008/009) faithfully. No module is missing.

**No bleed into S3+.** I checked specifically for the classic leak points and the queue stays clean:
- The M6 transport port, M10 in-memory adapter, M11 engine, and all role modules are explicitly named
  as "deferred to queue-003 and later" (header line 7). Good.
- M5e/`stdio.rkt` framing is built here (L0 cohesion) but the queue is **scrupulously correct** that it
  is orphaned until S6a/M7, repeating the note in three places (header, "Why", item 016). This matches
  roadmap §S2 deliverables line 118 word-for-word in intent. Excellent discipline — this is exactly the
  kind of thing that usually gets mis-scoped, and it didn't.
- The `related-request-id` transport option is **not** smuggled in here (it correctly lives in S3/M6).

**One genuine scope subtlety the queue gets RIGHT:** item 015's M5c (`metadata-utils.rkt`) is the
*accessor/helper* layer, while the reserved `_meta` key **string constants**
(`io.modelcontextprotocol/related-task`, `…/protocolVersion`, `…/clientInfo`, `…/clientCapabilities`,
`…/logLevel`) were already delivered in S1 (`mcp/core/types/constants.rkt`, lines 60–64, item 001) and
the `_meta` envelope structs in item 004. The queue treats M5c as "read/write the reserved keys" over
that S1 substrate — which is correct and avoids re-implementing the constants. Good catch by the author.

---

## 2. Accuracy of "mirroring TS …" claims — **this is where the queue needs work**

The queue leans hard on parity claims ("mirroring TS X", "cross-checked against the TS test"). Several
are **factually wrong** against the actual `typescript-sdk/` checkout. Each will mislead the Worker.

### 2.1 BLOCKER-ish: the `uriTemplate.test.ts` path is wrong (header line 6 + item 013)
The queue header (line 6) and item 013 both cite `core/src/shared/uriTemplate.test.ts`. **That file does
not exist.** The TS tests live in a separate `test/` tree:
`typescript-sdk/packages/core/test/shared/uriTemplate.test.ts`. Same for every other test fixture the
queue references: `toolNameValidation.test.ts`, `stdio.test.ts`, `auth.test.ts`, `authUtils.test.ts`,
and the validators suite (`test/validators/validators.test.ts`) all sit under `packages/core/test/…`,
**not** alongside the sources in `src/`. The header's "Relevant files" list at line 6 mixes `src/`
source paths with a `.test.ts` that is only valid under `test/`. A Worker following the literal path
will `ls` and find nothing. **Fix:** correct all `*.test.ts` references to `packages/core/test/shared/…`
(and `packages/core/test/validators/validators.test.ts`).

### 2.2 BLOCKER-ish: "mirroring TS `fromJsonSchema.ts`" (item 011) is misleading
Item 011 says the default Racket provider implements a documented keyword subset "mirroring TS
`fromJsonSchema.ts`." **`fromJsonSchema.ts` contains no keyword logic.** It is a 43-line thin wrapper
that calls `validator.getValidator(schema)` and adapts the result to a Standard-Schema shape. The actual
JSON-Schema keyword evaluation in TS is done by **Ajv** (`ajvProvider.ts`) and **cfWorker**
(`cfWorkerProvider.ts`) — both external libraries the vision §8 **explicitly excludes** from the Racket
port, and which §4.5 says are "collapsed to a single Racket-native provider." So item 011's keyword set
is a **net-new Racket-native design**, not a mirror of `fromJsonSchema.ts`. The misframing matters: a
Worker told to "mirror `fromJsonSchema.ts`" will open a 43-line wrapper, see no keywords, and be
confused about the source of truth. **Fix:** reword to "implements a Racket-native keyword subset (the
Ajv/cfWorker collapse from vision §4.5/§8); `fromJsonSchema.ts` is mirrored only for the *wrapper shape*
(schema-in, validate-fn-out), while the keyword semantics target the behaviour the `validators.test.ts`
suite asserts."

### 2.3 The validator port shape is a 2-op split of a 1-method TS interface (item 010)
TS `validators/types.ts` exposes a single-method interface `jsonSchemaValidator.getValidator<T>(schema)
→ (input) => result` — i.e. compile-and-validate fused into one returned closure. Item 010 splits this
into two explicit port operations ("**compile** schema → handle" and "**validate** value → result").
That's a reasonable, arguably more idiomatic Racket factoring, but it is **not** a 1:1 mirror of the TS
port. The queue should say so, so the parity-matrix reviewer in S9 isn't surprised. **Fix:** note that
the Racket port intentionally splits `getValidator` into compile/validate; cite `validators/types.ts`
`jsonSchemaValidator` as the source interface.

### 2.4 M5d/`AuthInfo` physically lives in TS `types/types.ts`, not `auth.ts` (item 015)
Item 015 says the `AuthInfo` struct is built "mirroring TS `auth.ts` + `authUtils.ts`." In the checkout,
**`AuthInfo` is defined in `packages/core/src/types/types.ts:435`** (fields: `token`, `clientId`,
`scopes`, optional `expiresAt`, optional `resource` (a URL), optional `extra`). The TS `shared/auth.ts`
is ~250 lines of **OAuth metadata Zod schemas** (`OAuthMetadataSchema`, `OAuthClientInformation`,
`OAuthTokens`, …) and `authUtils.ts` is `resourceUrlFromServerUrl` / `checkResourceAllowed`. The
vision's collection map (§5.2 / §4.6) deliberately *relocates* `AuthInfo` into `mcp/core/shared/auth.rkt`,
so the queue is faithful to the vision — but the "mirroring `auth.ts`" pointer will send the Worker to
the wrong file for the struct shape. **Fix:** point the `AuthInfo` field list at `types/types.ts:435`,
and reserve the `auth.ts`/`authUtils.ts` pointer for the token/metadata *helpers*. Also state the exact
field surface (`token`/`clientId`/`scopes`/`expiresAt?`/`resource?`/`extra?`) so item 015's "field
surface matches the TS `AuthInfo` shape" acceptance test is checkable.

### 2.5 M5c/`metadataUtils.ts` is only `getDisplayName` (item 015)
Item 015 says M5c mirrors `metadataUtils.ts` for reserved-key read/write. The actual
`shared/metadataUtils.ts` is **26 lines containing only `getDisplayName`** (title → annotations.title →
name precedence). The reserved-key handling the item describes is *correct as a Racket design* (it sits
over the S1 constants), but it is **not** what `metadataUtils.ts` does. **Fix:** either (a) add
`get-display-name` to item 015's M5c surface to genuinely mirror the TS module, or (b) drop the
"mirroring `metadataUtils.ts`" framing and state M5c mirrors the S1 `_meta` reserved-key constants
(`types/constants.ts`) plus a Racket reserved-key accessor layer. Option (a) is more faithful to parity
discipline — `getDisplayName` will be needed by M12b in S6b anyway.

---

## 3. Testability / coverage gaps (acceptance criteria under-cover the TS baselines)

The framework (every item ends in a concrete `raco test`) is right. But two items assert *less* than the
TS suites they claim parity with, which weakens the G1 parity guarantee.

### 3.1 Item 011 validator keyword set is narrower than `validators.test.ts` exercises
The queue's "minimum supported set" is `type`, `properties`, `required`, `enum`, `items`, `format`
(`date-time`/`uri`/`email`). The TS `test/validators/validators.test.ts` additionally exercises:
`minLength`/`maxLength`, `pattern`, numeric `minimum`/`maximum` (range), `additionalProperties: false`,
array length constraints, `uniqueItems`, and `default`, plus 2020-12 meta-keys (`$schema`/`$id`). The
queue says results are "cross-checked against a TS Ajv-validated baseline" — but the supported subset
won't reproduce the baseline's behaviour for any schema using those keywords. This is fine **if** the
unsupported-keyword policy (ignore-with-warning vs reject) is explicit and tested, which item 011 does
require — but the queue should name the **specific** common keywords it is deliberately deferring
(`pattern`, `minLength`/`maxLength`, `minimum`/`maximum`, `additionalProperties`, `uniqueItems`) rather
than the open-ended "any keyword outside this set." Tool input schemas in the wild routinely use
`minLength`/`pattern`/`additionalProperties`; deferring them is a defensible week-1 cut, but it should be
a **named, conscious** cut, not an implicit one. **Recommendation:** enumerate the deferred-but-common
keywords explicitly and add an acceptance assertion that each is handled per the documented policy (the
current "a test asserts that *an* unsupported keyword is handled" — singular — is too thin given how many
common ones are out).

### 3.2 Item 016 (stdio framing) omits three real behaviours of TS `ReadBuffer`
The TS `shared/stdio.ts` `ReadBuffer` does three things item 016 never mentions, all directly testable
and all part of "newline-delimited JSON framing":
1. **Max-buffer-size enforcement** — `STDIO_DEFAULT_MAX_BUFFER_SIZE = 10 MB`; `append` throws if the
   accumulated buffer exceeds it (DoS guard). An unbounded Racket decoder would diverge from TS here.
2. **CRLF tolerance** — lines are `.replace(/\r$/, '')` before parse, so `\r\n`-terminated frames work.
3. **Non-JSON-line skipping** — a `SyntaxError` (non-JSON line, e.g. hot-reload debug output) is
   *skipped* (`continue`), while a schema-validation error still throws. This is a deliberate,
   behaviour-defining detail of the stdio frame decoder.
Item 016's acceptance test covers only multi-message + partial-frame buffering. **Recommendation:** add
the max-buffer-overflow case and at least the CRLF case to item 016; mention the skip-non-JSON-line
policy so the Worker doesn't "fix" it into a hard error. (`stdio.test.ts` in the checkout has fixtures
for these.)

### 3.3 Reserved-key set in item 015 is incomplete vs the checkout
Item 015 lists five reserved `_meta` keys (protocol version, client info, client capabilities,
related-task, deprecated log level). The checkout's `types/constants.ts` defines **eight**: the five
above **plus** `TRACEPARENT_META_KEY` (`traceparent`), `TRACESTATE_META_KEY` (`tracestate`), and
`BAGGAGE_META_KEY` (`baggage`) — the W3C trace-context keys, with a dedicated `traceContextMeta.test.ts`.
S1 item 001 captured the five `io.modelcontextprotocol/*` keys but (per `constants.rkt` lines 60–64) did
**not** capture the three trace-context keys. This is an upstream S1 gap surfacing in S2: if M5c is meant
to "respect the reserved-key namespace," it should know about all eight. **Recommendation:** either note
in item 015 that trace-context keys are out of S2 scope (and file an S1 follow-up), or have M5c define
the three missing constants. At minimum, flag the discrepancy so it isn't silently lost.

---

## 4. Numbering & no-duplicates — clean

- S1 delivered items 001–009 (confirmed against `docs/aide/items/` and the on-disk
  `mcp/core/types/*.rkt` + `mcp/core/errors.rkt`). Queue-002 runs 010–018, sequential, no gaps, no
  overlap. ✅
- Header correctly states "continuing after queue-001's item 009." ✅
- The duplicate copy at `docs/aide/queue/queue-002.md` is **byte-identical** to the version under review
  (verified by `diff`). Harmless, matches the queue-001 precedent (queue-001 also lives under
  `docs/aide/queue/`). No action needed beyond awareness.

---

## 5. Sizing — appropriate, with one watch-item

Nine items, week-sized batch, each a real sub-multi-day unit. Consistent with queue-001's 9-item S1
batch. Two notes:

- **Item 011 is the heaviest** and rightly separated from the item-010 port (the queue explicitly
  justifies this in "Why this batch"). Given §3.1 (the keyword surface is larger than stated if you want
  real Ajv parity), 011 is the one item at risk of overrunning a multi-day slot. Keeping its subset
  *small and explicitly bounded* (per §3.1) is what keeps it week-sized — so the fix in §3.1 also
  protects the sizing.
- **Item 015 bundles M5c + M5d.** Justified by cohesion/size and I agree both are small. But note that if
  §2.4 (add `getDisplayName` + correct `AuthInfo` field surface) and §3.3 (trace-context keys) are taken
  on, item 015 grows. It would still fit, but it's the second item to watch. No split recommended yet.
- Items 010 and 014 are on the lighter side but not trivially small (the port-design and the
  fixture-parity table respectively carry real work). Acceptable.

---

## 6. Format — matches the queue-001 precedent

`### Item NNN: Title` + prose description, no checkbox lists inside items, a "Why this batch" preamble,
and a closeout item that flips progress boxes + parity rows. All consistent with queue-001. The
expanded header (Relevant-files list, orphaned-until-S6a callout) is an improvement over queue-001, not a
regression — provided the file paths in it are corrected (§2.1).

---

## 7. Prioritized fix list

1. **(accuracy)** Fix every `*.test.ts` path to `packages/core/test/shared/…` (and
   `…/test/validators/validators.test.ts`). Header line 6 + item 013. — §2.1
2. **(accuracy)** Reframe item 011: keyword subset is a Racket-native design (Ajv/cfWorker collapse),
   not a mirror of the keyword-free `fromJsonSchema.ts`. — §2.2
3. **(accuracy)** Item 015: point `AuthInfo` at `types/types.ts:435` and state its exact field surface;
   reserve `auth.ts`/`authUtils.ts` for the helpers. — §2.4
4. **(coverage)** Item 016: add max-buffer-size overflow + CRLF + skip-non-JSON-line behaviours and
   tests. — §3.2
5. **(coverage)** Item 011: name the deliberately-deferred common keywords (`pattern`, `minLength`/
   `maxLength`, `minimum`/`maximum`, `additionalProperties`, `uniqueItems`) and test the policy for each,
   not just "an" unsupported keyword. — §3.1
6. **(accuracy/coverage)** Item 015: either add `getDisplayName` to M5c or drop the "mirroring
   `metadataUtils.ts`" claim; and reconcile the 5-vs-8 reserved-key set (trace-context keys). — §2.5, §3.3
7. **(clarity)** Item 010: note the deliberate compile/validate split vs the TS single-method
   `getValidator`. — §2.3

None of these are structural; the queue's scope, numbering, sizing, and format are sound. The revision is
about making the parity pointers true and the acceptance criteria match the TS baselines they invoke.
