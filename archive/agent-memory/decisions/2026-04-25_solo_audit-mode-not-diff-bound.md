---
date: 2026-04-25
agent_id: solo
title: compliance-reviewer takes a mode flag — diff (default) and audit (whole-codebase)
---

# compliance-reviewer takes a mode flag — diff (default) and audit (whole-codebase)

## Decision

`compliance-reviewer` runs in one of two modes:

| Mode | Trigger | Scope | Output |
|------|---------|-------|--------|
| Diff (default) | `/ship` or SessionStop hook | Files changed in `BASE..HEAD` | `docs/reviews/<stamp>-compliance.md` + Backlog auto-file for HIGH/MEDIUM |
| Audit | `/audit` | Whole codebase, no diff scope | `docs/reviews/<stamp>-audit.md`, no auto-file |

The mode is determined by an `--audit` flag passed in the agent's invocation. When absent, default to diff mode.

## Why

ship-sop's pipeline (Phase 0) is diff-bound by design. Per-ship gates that scan a diff catch *new* gaps as they're introduced. They do not catch *standing* gaps — files or routes that should exist somewhere in the project but don't, or controls that exist but aren't applied.

Real-world evidence: hst-tracker's full code review (2026-04-25) surfaced 14 launch blockers. Three (C8 missing privacy policy, C10 lawful-basis, C11 data-export) are absences that no diff-bound gate could see. They predated ship-sop's installation. ship-sop without audit mode is effectively useless on existing codebases — it only protects forward-going changes from new gaps.

Audit mode is the only way ship-sop catches accumulated debt rather than just new bugs.

## Consequences

- Audit reports typically surface 10-50 findings on existing codebases. **Audit mode does NOT auto-file Backlog entries** — auto-filing would flood `Backlog.md`. Operator triages findings in one pass and files only what they intend to fix.
- Cadence is different from `/ship`: monthly compliance reviews, launch-readiness milestones, post-acquisition due diligence. Not every session.
- Audience is different: `/ship` is the shipper, `/audit` is the compliance reviewer / launch coordinator. Different mental model, different command, different output format.
- Audit mode runs only `compliance-reviewer`, not `security-reviewer` or `diagram-builder`. Whole-codebase compliance audits are the canonical use case; security and diagrams have other invocation paths if a similar audit is wanted.

## Alternatives considered

- **Add `/ship --audit` flag** — Rejected. Conflates two different decision points (per-ship gate vs. periodic compliance sweep). Would also auto-fire as part of SessionStop hook if added to the pipeline list, which would re-find the same standing gaps every session.
- **Make audit mode the only mode** — Rejected. Diff mode catches new gaps cheaply; running a whole-codebase audit on every session-end is wasteful (token cost, time) and the findings are mostly stale.
- **Run audit periodically via cron** — Rejected as the *primary* mechanism, but compatible. Operators can cron `claude /audit` if they want monthly automation. The command is the operator-facing entrypoint either way.

## Reversibility

Easy. `/audit` is opt-in and separate from `/ship`. If audit mode produces no useful signal in practice, deprecate the command. The diff-mode core (which is the heart of ship-sop) is unchanged either way.
