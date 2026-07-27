# P12 + P13 — background-gate semantics and directive integrity

**Date:** 2026-07-27
**Agent:** solo

Three months of agent-sop artefacts synced (last sync 26 April), then both open items shipped.

**Sync:** 6 pristine replicas updated, 4 that had never arrived created — `docs/sop/multi-agent.md`, `docs/guides/cross-layer-rules.md`, `scripts/refresh-in-flight.sh`, `docs/agent-memory/in-flight/README.md`. Zero conflicts. This repo now carries agent-sop's rule 11 (gate integrity), S7, T1, B12, the P66 skip-token unification and the validator silent-exit fix. `last_update_check` 2026-04-26 → 2026-07-27.

**P12** `[Bug]` — gates assumed synchronous subagents. Claude Code 2.1.198 made them background-by-default, so `/ship` could evaluate `block_on` thresholds and report READY on gates that had not returned. `/ship` gains a collect-before-evaluate section placed ahead of the gates; agent-backed gates record verdicts instead of acting inline; README documents that auto-mode findings may surface a turn later than the directive pickup, and that the stop hook only sees the diff at stop.

**P13** `[Iteration]` — `.ship/.pending-auto-fire.md` is persistent state the next turn acts on. The hook now writes a `.sha256` sidecar and the directive carries an "Integrity and scope" section with three explicit outcomes: match, differ, unverifiable. Dogfooded against a real 1394-line diff across clean, tampered, missing-sidecar, `sha256sum`-only and no-hasher-at-all cases.

**The reviewer turn found 5 HIGH, every one a defect in this session's own work.** The worst: P13's first schema table omitted the hook's own `## Auto-mode rules` block while declaring unlisted content to be tampering, so a compliant reader would have refused every directive the hook produces. P13 shipped that way would have been net-negative — a security mechanism that disables the thing it protects. Also caught: a README paragraph still carrying the exact sentence P12 was filed against, the P12 instruction stranded after gates that already halt, a hardcoded `shasum` defeating its own fallback (silent gate suppression on most Linux containers), and a staleness claim that was simply false.

Fourth consecutive review across two repos to find HIGH defects in work its author believed finished. The recurring shape is unchanged: verification exercised the case the author imagined rather than the case the code meets.
