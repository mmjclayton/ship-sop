---
date: 2026-04-25
agent_id: solo
title: ship-sop is a separate repo, not an agent-sop extension
---

# ship-sop is a separate repo, not an agent-sop extension

## Decision

ship-sop lives in its own GitHub repository (`mmjclayton/ship-sop`) rather than as an `extensions/ship-pipeline/` folder inside agent-sop or a fork of it.

## Why

agent-sop is about *session discipline* (start/end checklists, cross-session memory, parallel multi-agent sessions). ship-sop is about *pre-merge quality gates* (tests, security, compliance, diagrams). They're different decision points, different audiences, different mental models.

Three reasons separation won:
1. **Different release cadence.** agent-sop iterates slowly and deliberately. Compliance rules and pipeline gates will iterate faster. Separate cadences want separate repos.
2. **ship-sop doesn't structurally need agent-sop.** It uses agent-sop *conventions* (Backlog tags, P-numbers, build-plan format) but those are markdown conventions, not file-path or runtime dependencies. ship-sop works standalone.
3. **agent-sop README signal-to-noise.** Adding 4+ agents and 4+ commands as an "Optional extensions" section dilutes agent-sop's single-message focus.

## Consequences

- Two repos to maintain. Cross-repo coupling is documentation-only.
- agent-sop README has a single "Companion projects" paragraph linking to ship-sop. That's the only diff to agent-sop core.
- ship-sop README explains the composition. When both are installed, `compliance-reviewer` auto-files Backlog entries using agent-sop's P-numbering.
- Folder-as-boundary is cheap to upgrade to repo-as-boundary later. The reverse is harder. Starting with separate repos was the higher-optionality choice.

## Reversibility

Easy to merge ship-sop into agent-sop later if the ergonomics suggest it (single `setup.sh`, single update flow). Hard to split later (git history would need rewriting). Picking separate now preserves the option.
