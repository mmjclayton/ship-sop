# 2026-08-03 — Full project review, Phase 3 plan, and P14 hook wiring

**Agent:** solo
**Branch:** `fix/p14-hook-wiring-shape`

---

## What happened

Ran a seven-dimension review of the whole project (hook, installer, security threat model, slash commands, agent definitions, docs-vs-reality, mission gaps and the agent-sop boundary). Each dimension was followed by an adversarial verifier instructed to refute rather than agree, defaulting to refuted under uncertainty and checking `docs/agent-memory/decisions/` before allowing any "missing feature" finding to stand. 48 findings survived, 8 were refuted. Report at `docs/reviews/2026-08-03_solo_full-project-review.md`.

The headline finding was verified by hand before being acted on, because everything else depended on it.

## The finding that reframed the phase

**The SessionStop hook has never fired, in any project, since P1.**

`setup.sh` wrote `{"hooks":{"Stop":[{"command":"scripts/auto-ship-hook.sh"}]}}`. Claude Code requires each entry to nest its command inside a `hooks` array with an explicit `type`. The flat form is valid JSON, so nothing errors — the harness simply discards the entry.

Evidence, independent of the review:

- Every working hook on this machine (user scope, `hst-tracker`, `design-agent`) uses the nested shape. ship-sop was the only settings file with zero nested entries.
- In `hst-tracker/.claude/settings.json` the dead ship-sop entry sits in the same `Stop` array as a correctly-shaped prettier hook that does run. The contrast is visible in one file.
- `.ship/.last-auto-fire` is frozen at install time in both live installs — 27 July here, 2 May in `hst-tracker`, across hundreds of commits since.

This is why the pipeline has always been invoked by hand. The operator requirement for automatic runs and the top correctness bug turned out to be the same item.

## Shipped (P14)

- Nested shape at all four write sites and in this repo's own `.claude/settings.json`.
- Three shared selector constants replacing the three inlined flat-shape jq expressions. Install and uninstall previously carried independent copies, which is how they drifted; now they cannot.
- Migration branch rewrites a pre-P14 flat entry in place instead of appending a second one.
- Uninstall handles both shapes: drops legacy flat entries, strips only our command from nested entries, removes entries left with no commands, and leaves other people's hooks alone.
- Post-install assertion exits non-zero when the entry is not reachable through the nested probe. A silently-unwired hook is the exact failure this batch removes, so it fails loudly.
- README manual-fallback jq updated, since the old command would no longer match what is installed.

Verified on throwaway repos across five cases: fresh install, re-run idempotency (entry count stays 1), legacy migration alongside a user hook (migrated in place, user hook intact), uninstall of each shape, and the assertion rejecting the flat shape while accepting the nested one.

## Deliberately not done

- **`hst-tracker` repair deferred to after Batch 3.5.** Re-enabling auto-mode there now would start firing the current hook, which still writes a literal `HEAD` as its diff range and stamps the throttle at directive emission rather than gate completion. That would replace a dead gate with a confidently-wrong one on the repo that matters most. Dead is the safer of the two states for a few more batches.
- **P12/P13 not backfilled into `docs/feature-map.md`.** Real drift, filed as P23. Kept out of this diff to respect "do not modify files unrelated to the current Backlog item".

## Still unproven

The shape is verified correct against every working example on this machine and against the probe. "The hook fires at session stop" is only observable when a session actually ends — `.ship/.last-auto-fire` advancing without anyone running the script by hand is the acceptance test, and it happens on the next session boundary, not in this one.

## Filed

Phase 3 plan at `docs/build-plans/phase-3-automation-and-correctness.md`: 10 batches, P14 through P23, ordered so nothing blocks on later work. The automation design is written up there — SessionStart hook as the primary path, `/restart-sop` as an idempotent backstop, a `PreToolUse` push gate as the only surface that can actually refuse, and deterministic checks moved into the hook where they cost nothing and cannot be reasoned past.

Two decisions left open for the operator: whether automatic dispatch is default-on or opt-in for the first release, and whether the push gate ships default or behind a flag.
