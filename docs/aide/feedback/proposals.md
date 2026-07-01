# Feedback Proposals (human review required)

The self-improve step writes here instead of self-applying when a change would
touch a Protected invariant (P1/P2) or is a control-flow / structural change
(P5). These are NOT applied automatically. Review, then apply by hand or tell
feedback to proceed.

Format per proposal: timestamp · target skill · proposed change · why · which
invariant blocked auto-apply.

- 2026-06-27 · `speckit.aide.execute-item` (Next Step decision, Auto Mode) · **Prioritize executing specced-but-unexecuted (📋) items before create-item specs further-ahead items.** Today step 2 ("queue has items lacking a spec? → create-item --auto") fires before any "is there a 📋 item with a spec waiting to be executed?" check, so the chain will spec+execute item 018 next while item 016 (spec exists, `stdio.rkt` deliverable still 📋, progress.md:78) stays unexecuted. · **Why:** item 018 ("S2 demo + closeout") depends on 016 — its demo encodes/decodes a stdio frame (M5e). Executing 018 before 016 will block/fail at the demo step. More generally, leaving specced 📋 items behind risks dependency-order breakage. Proposed: add a Next-Step branch *before* the create-item branch — "any item with a spec file but 📋 status → execute-item --auto <that-item> first." · **Blocked by:** P5 (control-flow / structural change to the chain ordering — not auto-applied). Note: item 017 itself was correctly scoped 016-independent (stdio isolated), so this is a chain-ordering issue, not an item-017 defect.
