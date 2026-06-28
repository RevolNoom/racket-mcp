# Approved Version — Item 015 (`_meta` metadata utils M5c + shared `AuthInfo` M5d)

**Approved at:** iteration-001 (no revision needed).
**Reviewer rating:** 10/10, `needs_revision: false`.

## Delivered artifacts (latest approved)
- `mcp/core/shared/metadata-utils.rkt` (M5c) — `get-display-name` + the 8 reserved `_meta` key constants (5 re-exported from S1 + `traceparent`/`tracestate`/`baggage` defined here, SEP-414) + `reserved-meta-key?`/`meta-ref`/`meta-set`. S1-only import.
- `mcp/core/shared/auth.rkt` (M5d) — `auth-info` struct (6-field exact surface) + `make-auth-info` (`define/contract`) + `auth-info-expired?`/`auth-info-has-scope?`/`auth-info->json`/`json->auth-info`. `racket/contract` + S1 import; `resource` held as a string (no `net/url`).
- `mcp/core/shared/test/metadata-utils-test.rkt` — 38 checks.
- `mcp/core/shared/test/auth-test.rkt` — 39 checks.

Snapshot of the approved source is in `iteration-001/{metadata-utils,auth,metadata-utils-test,auth-test}.rkt`.

## Validation record
```
Item 015 — validation record
- Racket version: v8.18 [cs]
- raco make (both modules): exit 0, no warnings
- raco test mcp/core/shared/   : 269 passed / 0 failed
    - metadata-utils-test.rkt alone: 38
    - auth-test.rkt alone:           39
    - (existing uri-template + tool-name-validation: 192)
- raco test mcp/core/validators/ : 300 (unchanged)
- raco test mcp/core/util/       : 102 (unchanged)
- get-display-name 7 cases:      pass
- get-display-name C1 (null/non-hash annotations no-crash): pass
- get-display-name S5 (non-string title fallthrough):       pass
- get-display-name S6 (missing name raises):                pass
- reserved-meta-keys length:     8
- trace constants:               traceparent/tracestate/baggage present
- progressToken not reserved (S1):                          #f: yes
- meta-ref no-default missing → #f (S3):                    pass
- meta-ref string/symbol key equiv on prefixed key (S2):    pass
- _meta S1 envelope round-trip:  traceparent/tracestate/baggage all survived: yes
- auth-info field surface:       exactly 6 fields: yes
- auth-info-expired? boundary:   <= at expiry: pass; expires-at=0 expired (S4): pass
- json round-trip (full+minimal):check-equal? pass; #f-optionals omitted: yes
- json encode 0/empty-extra emitted (S4):                   pass
- json decode literal-wire camelCase (C4):                  pass
- json->auth-info rejects malformed (C2):                   pass
- make-auth-info rejects bad fields (C3, 5 check-exn):      pass
- resource is string:            yes; net/url imported: no
- (module+ test …) present:      no
- net/* | subprocess | socket grep: no match (doc-comments only)
- Decisions & Trade-offs (h) updated with as-built require lists + counts: yes
```
