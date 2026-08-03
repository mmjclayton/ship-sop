# A dead gate beats a confidently-wrong one: hst-tracker repair deferred

**Date:** 2026-08-03
**Agent:** solo

We chose to **leave `hst-tracker`'s ship-sop install broken until after Batch 3.5** rather than repair it alongside P14, because re-enabling auto-mode on the current hook would replace a gate that does nothing with a gate that reports the wrong thing.

P14 fixed the `.claude/settings.json` shape, so repairing `hst-tracker` was a two-line change and the Phase 3 plan originally scoped it into Batch 3.1. Against that: the hook as it stands still writes a literal `HEAD` as its `Diff range` (making its own staleness check a tautology) and stamps the throttle at directive emission rather than at gate completion (so an interrupted turn leaves that commit permanently ungated). Both are fixed in Batch 3.5, neither is fixed now.

`hst-tracker` is the repo where being wrong costs the most. A dead gate is visibly dead — `.last-auto-fire` frozen since 2 May is a fact anyone can check. A gate that fires against a stale merge base and reports PASS is invisibly wrong, and it is exactly the false-PASS outcome the whole Phase 3 correctness track exists to remove.

So the ordering rule: **do not enable an automation on a consumer repo until the state machine behind it is correct.** Turn it on here first, where it is dogfooded and observable, and promote it outward after 3.5.

The plan and Backlog were amended to match rather than leaving the commitment silently unmet — the deferral is recorded in Batch 3.1's own text and in the phase Deploy Checklist, not dropped.
