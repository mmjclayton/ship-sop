# Agent Memory

Shared context for all agents working on this project. Read at the start of every session. Update at the end. Never delete without a trace — update in place, mark superseded, or archive.

---

## Key Documents

See CLAUDE.md Key Documents & Dispatch table.

---

## Key Source Files for Current Work

| Area | File |
|------|------|
| Reviewer agents (the gates' prompts) | `.claude/agents/{compliance-reviewer,diagram-builder,release-notes-writer}.md` |
| Slash commands | `.claude/commands/{ship,release,audit,ship-on,ship-off}.md` |
| SessionStop hook (throttle + directive emission) | `scripts/auto-ship-hook.sh` |
| Installer (with self-install detection) | `setup.sh` |
| Default config + JSON schema | `docs/templates/ship-sop.{config,schema}.json` |
| Public spec + pitch | `README.md` (canonical post-P11; `docs/ship-sop.md` is now a redirect stub) |

---

## In-Flight Work

*(none — Phase 0 and Phase 1 complete; no active P-numbers in `[IN PROGRESS]` state)*

---

## Decisions Made

See `docs/agent-memory/decisions/`. One file per decision. Index of what's there as of 2026-04-25:

- `separate-repo-not-extension` — why ship-sop is its own repo, not an agent-sop folder
- `hook-writes-directive-not-agents` — why the SessionStop hook writes a directive file
- `auto-mode-warns-manual-ship-halts` — different failure modes for auto vs. manual `/ship`
- `dropped-intent-and-pm-reviewers` — why initial scope is four gates not six
- `diagram-builder-narrow-vs-doc-updater` — staying narrow to avoid duplicating doc-updater
- `release-stays-manual` — `/release` never auto-fires
- `audit-mode-not-diff-bound` — compliance-reviewer takes a mode flag (diff vs audit)
- `default-reviewer-set-expansion` — language-agnostic defaults: code-reviewer + silent-failure-hunter + pr-test-analyzer; language reviewers stay per-project

---

## Gotchas and Lessons

See `docs/agent-memory/gotchas/`. One file per gotcha. Index as of 2026-04-25:

- `stop-hooks-cant-invoke-agents` — the architectural constraint that shaped auto-mode
- `agent-registry-locked-at-session-start` — why same-session dogfood is inline-only
- `git-reset-wipes-uncommitted-edits` — lesson from the docs-only-detection fix iteration
- `throttle-stamps-need-clearing-to-retest` — `.ship/.last-*` interferes with iteration

---

## ship-sop's Preferences

- **Terse review writing.** compliance-reviewer and security-reviewer findings should follow the agent-sop code-reviewer "Finding Voice" style — exact line numbers, exact symbol names, concrete fixes. No hedging, no "I noticed that...", no restating what the diff already says.
- **No `intent-reviewer` or `pm-reviewer` until evidence accumulates.** Per the dropped-agents decision. Don't propose adding them on speculation.
- **Stay narrow on `diagram-builder`.** Mermaid + API catalog + Δ log only. Codemap and README work belongs to `doc-updater`. Resist scope creep.
- **`/release` always manual.** No auto-publish via hooks. If that ever changes it must be explicit, not default.
- **Audit mode does NOT auto-file Backlog entries.** Operator triages.
- **No emojis in any agent file or slash command.** Plain markdown.

---

## Completed Work

- 2026-04-25 `solo`: P1 — Initial scaffold (3 reviewer agents, 4 slash commands, hook, setup, config, README) — `bd05f40`
- 2026-04-25 `solo`: P2 — Self-install dogfood + post-install fixes — `e82ccd5`
- 2026-04-25 `solo`: P3 — End-to-end auto-mode dogfood + leftover-rename fix — `7db908e`, `31f984e`
- 2026-04-25 `solo`: P4 — Docs-only detection in hook — `bc2e9d7`
- 2026-04-25 `solo`: P5 — agent-sop install for retrospective record — `b0ea04c`
- 2026-04-25 `solo`: P6 — Multi-tenant isolation scan + lawful-basis severity bump — `3b679e0`
- 2026-04-25 `solo`: P7 — `/audit` command + whole-codebase mode + shadow-controls check — `82e06c1`
- 2026-04-25 `solo`: P9 — Default reviewer set expansion (code-reviewer + silent-failure-hunter + pr-test-analyzer)

---

## Archived

*(none yet — project is too young to have superseded narrative content)*
