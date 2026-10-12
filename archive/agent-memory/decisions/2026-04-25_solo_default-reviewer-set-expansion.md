# Default reviewer set expansion: code-reviewer + silent-failure-hunter + pr-test-analyzer

**Date:** 2026-04-25
**Agent:** solo
**Item:** P9

## Context

ship-sop's Phase 0 default reviewer set was three agents: `security-reviewer` (CRITICAL), `compliance-reviewer` (CRITICAL), `diagram-builder` (advisory). That covers vulnerabilities, privacy/compliance, and ship-time documentation — but leaves three signal gaps:

1. **General code quality** — function/file size, missing error handling, dead code, missing tests for new paths. `security-reviewer` is OWASP-focused; this is broader.
2. **Silent failures** — empty catches, `.catch(() => [])`, swallowed errors, lost stack traces. A class of bug that corrupts data without paging anyone, missed by both `security-reviewer` (not a vulnerability) and `code-reviewer` (only flagged in passing).
3. **Test-coverage quality** — does the diff's new code actually have tests? Behavioural coverage, not just line coverage.

Trigger: hst-tracker (the canonical dogfood project) hand-tuned its `ship-sop.config.json` to add `typescript-reviewer` and `pr-test-analyzer`, plus pinned five reviewer agents into `.claude/agents/`. The TS-specific addition is correct *for that project*, but the underlying instinct — "the default set is too narrow" — applies generally. P9 promotes the language-agnostic subset of that instinct into the template.

## Decision

Add three reviewers to `docs/templates/ship-sop.config.json` (the default template that every fresh install receives):

| Agent | block_on | auto_file_backlog | Rationale |
|---|---|---|---|
| `code-reviewer` | `HIGH` | (default true) | Language-agnostic. CRITICAL territory belongs to `security-reviewer`; HIGH is the right severity for quality findings. |
| `silent-failure-hunter` | `HIGH` | (default true) | Single-purpose, language-agnostic. Different signal class from `code-reviewer`. HIGH because silent failures corrupt data invisibly. |
| `pr-test-analyzer` | `never` | `false` | Test-coverage gaps are legitimate (refactors, doc edits, WIP commits). Hard-blocking would create false-positive friction. `auto_file_backlog: false` prevents Backlog churn on every interim ship. |

## Locked rules

- **[LOCKED]** Language-specific reviewers (`typescript-reviewer`, `python-reviewer`, `go-reviewer`, `rust-reviewer`, `java-reviewer`, `csharp-reviewer`, `kotlin-reviewer`, `cpp-reviewer`, `flutter-reviewer`) **do not** belong in the default template. ship-sop installs onto Python, Go, Rust, etc. projects too — language reviewers are per-project decisions. The README's "Common extensions" section documents the pattern.
- **[LOCKED]** `pr-test-analyzer` is advisory (`block_on: never`) and silent (`auto_file_backlog: false`). Coverage drift is signal, not a hard-block. Operators who want strict-coverage gating can flip `block_on` per project.
- **[LOCKED]** `code-reviewer` and `silent-failure-hunter` block on HIGH, not CRITICAL. CRITICAL is reserved for `security-reviewer` and `compliance-reviewer` — the gates that protect against vulnerabilities and legal/regulatory exposure. HIGH is the right severity bar for code quality.
- **[LOCKED]** Bundle-vs-config split: ship-sop's `setup.sh` only copies `compliance-reviewer`, `diagram-builder`, `release-notes-writer` into `~/.claude/agents/`. The new defaults (`code-reviewer`, `silent-failure-hunter`, `pr-test-analyzer`) come from agent-sop or the user's existing install — same model `security-reviewer` already uses. ship-sop does not vendor what it doesn't author.

## On-demand agents (deliberately not gates)

The agent registry is large. The following were considered and rejected as default ship-time gates:

- `tdd-guide` — pre-work, not pre-ship. Belongs in CLAUDE.md "start any [Feature] or [Bug]" rule, not the ship pipeline.
- `build-error-resolver`, `*-build-resolver` — fire on broken builds, not green diffs.
- `planner`, `architect`, `code-architect`, `code-explorer` — design-time.
- `doc-updater` — broader than ship-time; overlaps `diagram-builder`'s narrow scope.
- `refactor-cleaner` — runs ad-hoc cleanup tools (knip, depcheck, ts-prune); not a per-diff gate.
- `comment-analyzer`, `type-design-analyzer` — useful but low signal-to-cost on every >10-line diff.
- `performance-optimizer` — too cross-cutting for a default gate; opt-in for perf-sensitive projects.
- `gan-*`, `sop-checker`, `harness-optimizer`, `loop-operator`, `chief-of-staff` — meta/specialized.

## Throttle considerations

`pr-test-analyzer` raised the question of whether advisory gates should run on every >10-line diff or only on PR-ready diffs. Decision: throttle stays gate-uniform. Adding gate-level throttle conditions (PR-only, file-pattern, diff-size-per-gate) balloons the schema and the hook script; tuning happens via `min_diff_lines` and `cooldown_seconds` at the project level.

## Migration

Existing ship-sop installs do not auto-update. Operators on older configs who want the new defaults run:

```bash
# Either copy the template fresh
cp ~/Projects/ship-sop/docs/templates/ship-sop.config.json ./ship-sop.config.json

# Or hand-edit to add the three new agents
```

## Out of scope

- Auto-migration of existing `ship-sop.config.json` files (operators may have intentionally pruned the default set).
- A "language pack" installer (`./setup.sh /path --typescript`). Considered, deferred — manual config edit is fine for now.
- Severity escalation rules per-project (e.g., bump `code-reviewer` to CRITICAL on launch-critical repos). Not in scope; the schema already permits per-project override.
