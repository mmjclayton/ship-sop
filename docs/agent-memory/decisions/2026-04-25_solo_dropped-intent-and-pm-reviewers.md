---
date: 2026-04-25
agent_id: solo
title: Dropped intent-reviewer and pm-reviewer from initial scope
---

# Dropped intent-reviewer and pm-reviewer from initial scope

## Decision

The initial design considered six gates. Ship-sop ships with four. The two dropped:
- **`intent-reviewer`** — would diff implementation vs. Backlog item / `--intent` string and grade acceptance criteria PASS/PARTIAL/FAIL.
- **`pm-reviewer`** — product manager critique, two modes (`spec` pre-code, `coherence` advisory at ship-time).

Both files were drafted, then deleted before the initial commit.

## Why

Operator (matt) trimmed scope: *"i think ignore the pm reviewer for now, i don't need it. probably the intent reviewer for now too."*

The judgment calls behind the trim:

- **Intent-reviewer overlaps with disciplined Backlog usage.** If the operator is rigorous about writing acceptance criteria in `Backlog.md`, they're already comparing implementation to those criteria during code review. The agent automates the comparison but adds another gate to maintain. Worth it later if "did this match what was asked" becomes a recurring miss; not worth it on initial release with no signal that it would.

- **PM-reviewer ship-time use is too late.** PM input is most valuable *before* code is written, when the spec can still cheaply change. By ship-time the design is sunk. A coherence-mode advisory gate would mostly produce next-iteration follow-ups — useful but not essential for v1.

- **Pipeline width matters.** Six gates per session is a lot of model time and a lot of artifacts. Four is enough to be useful without being noisy.

## Consequences

- Pipeline is leaner: tests → security → compliance → diagrams.
- `/ship` and the auto-hook only invoke three reviewer agents (security from agent-sop or user install, plus ship-sop's compliance and diagrams). Releases cost less.
- If "did the implementation match intent" becomes a recurring miss, intent-reviewer can be added without breaking the pipeline shape — just another agent in `.claude/agents/` and an entry in `ship-sop.config.json`.

## Reversibility

Easy. Drafts of both agents existed in this conversation and can be reconstructed from the design discussion if revived. The design notes for what each would have done are preserved in `docs/feature-map.md` under "Not on the table."
