# Harvested AIDE scripts

Reusable shell scripts the `speckit.aide.self-improve` step harvested from
commands that recurred across multiple work items. The point is to write a
recurring workflow step **once** so every future item runs it the same way
instead of re-deriving the command (and burning tokens) each time.

- **Who writes these:** only the self-improve step, via
  `.claude/skills/speckit.aide.self-improve/scripts/harvest-script.sh`, after
  `tally-commands.sh` shows a command recurring across ≥2 items.
- **Who calls these:** execute-item's worker (and any AIDE skill the
  self-improve step wires up). Prefer an existing script here over re-deriving a
  command — see `docs/aide/EFFICIENCY.md` R6.
- **Provenance:** each script carries a header noting it was harvested and when.
  If you change what one does, log it in `docs/aide/feedback/changelog.md`.

Empty until the first pattern is harvested.
