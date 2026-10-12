# Phase 0 — Foundation

Status: Shipped 2026-04-25

---

## Problem

Every code change you ship needs the same hygiene: tests pass, no security regressions, no PII leaks or compliance drift, documentation kept in sync. Doing this manually means it gets skipped under pressure. Doing it via a CI step happens too late — after you've already opened a PR.

ship-sop's foundation: a four-gate pipeline (tests, security, compliance, diagrams) that fires automatically on session-end via a SessionStop hook, or manually via `/ship`. Companion to agent-sop, but standalone.

---

## Scope

| Batch | What | Priority |
|-------|------|----------|
| 0.1 | Initial scaffold — three reviewer agents, four slash commands, hook script, setup.sh, README | P0 |
| 0.2 | Self-install dogfood + post-install fixes | P0 |
| 0.3 | End-to-end auto-mode dogfood + leftover-rename fix | P0 |
| 0.4 | Docs-only detection in hook | P0 |
| 0.5 | agent-sop install for retrospective record | P1 |

---

## Architecture

The pipeline is the product, but the architecture is shaped by three constraints:

1. **SessionStop hooks can't invoke `@agent` calls.** They run as plain bash scripts. So auto-mode is a two-part flow: hook writes a directive file, next-turn model reads it and runs the gates. Detail in `docs/agent-memory/decisions/2026-04-25_solo_hook-writes-directive-not-agents.md`.

2. **Auto-mode warns; manual `/ship` halts.** Same gates, same artifacts, different failure modes. Auto prioritises non-disruption (don't halt the user mid-flow); manual prioritises strict gating (the operator deliberately invoked the check). Detail in `docs/agent-memory/decisions/2026-04-25_solo_auto-mode-warns-manual-ship-halts.md`.

3. **ship-sop is a separate repo, not an agent-sop extension.** Different decision points (per-ship vs. per-session), different release cadences, different audiences. They compose — when both are installed, `compliance-reviewer` auto-files Backlog entries with proper P-numbers — but neither requires the other. Detail in `docs/agent-memory/decisions/2026-04-25_solo_separate-repo-not-extension.md`.

Output paths (all in the consumer project):
- `docs/reviews/<stamp>-{security,compliance,diagrams,ship-auto}.md` — durable audit trail per gate, one consolidated readiness report per fire
- `docs/diagrams/<feature>.md` — Mermaid state + sequence diagrams (diagram-builder)
- `docs/api/<service>.md` — endpoint catalog with schemas (diagram-builder)
- `docs/ARCHITECTURE.md` — Δ log appended on architectural changes (diagram-builder)
- `.ship/.pending-auto-fire.md` — directive file the hook writes for the next-turn model (gitignored)
- `.ship/.last-auto-fire` and `.last-diff-hash` — throttle state (gitignored)

Config:
- `ship-sop.config.json` at the repo root — per-agent toggles, throttle, release config
- `docs/templates/ship-sop.schema.json` — JSON Schema reference (`$schema` link in the config)

---

## Key Decisions Locked In

- **[LOCKED]** Separate repo from agent-sop. Do not propose merging back as an extensions/ folder.
- **[LOCKED]** SessionStop hook writes a directive file; the model on the next turn runs the gates. No subprocess invocation of `claude` from the hook.
- **[LOCKED]** Auto-mode never halts the session on hard-block findings — strong warning only. Manual `/ship` halts.
- **[LOCKED]** `/release` is always manual. No SessionStop or pre-push hook fires it.
- **[LOCKED]** `diagram-builder` stays narrow (Mermaid + API catalog + Δ log). Codemap and README work belongs to `doc-updater`.
- **[LOCKED]** Initial scope is four gates, not six. `intent-reviewer` and `pm-reviewer` were dropped pre-initial-commit. They can be added later if a recurring miss surfaces; not before.

---

## Batch Log

- **2026-04-25: Batch 0.1 shipped — `bd05f40 feat: initial scaffold`.** Three agents (compliance-reviewer, diagram-builder, release-notes-writer), four commands (/ship, /release, /ship-on, /ship-off), hook script, setup.sh, README, LICENSE, ship-sop.md spec, config + schema templates. 14 files, 1904 lines total.
- **2026-04-25: Batch 0.2 shipped — `e82ccd5 chore: dogfood ship-sop on itself + post-install fixes`.** Self-install detection in setup.sh (`SCRIPT_DIR == TARGET`), expanded next-steps output, hook flow documentation in docs/ship-sop.md, install artifacts (`ship-sop.config.json`, `.claude/settings.json`, `.gitignore`) committed.
- **2026-04-25: Batch 0.3 shipped — `7db908e docs: add Uninstall section to README` + `31f984e test: dogfood auto-mode pipeline + fix leftover rename string`.** README Uninstall section, end-to-end manual fire of the SessionStop hook against a 38-line diff, four review artifacts in docs/reviews/, leftover "Ship-pipeline" string in directive header replaced with "ship-sop."
- **2026-04-25: Batch 0.4 shipped — `bc2e9d7 fix: docs-only detection in auto-ship-hook`.** Hook now detects when every changed file matches `^docs/`, `\.(md|mdx)$`, or `^README` and filters the agent list to advisory gates only. `Mode: docs-only` banner added to directive output.
- **2026-04-25: Batch 0.5 shipped — agent-sop install (this commit).** CLAUDE.md, Backlog.md (P1-P5 retrospective), feature-map.md, six decisions and four gotchas captured under `docs/agent-memory/`, this build plan filled in retrospectively, recent-work entry written.
- **2026-04-25: Batch 0.6 shipped — `91294b1 feat(P9): expand default reviewer set` + `c25d04c docs(P9): split Common extensions`.** Default config grew from 3 reviewer gates (security, compliance, diagram-builder) to 6 — added `code-reviewer` (HIGH), `silent-failure-hunter` (HIGH), `pr-test-analyzer` (advisory + auto_file_backlog: false). Language-specific reviewers stay per-project. README split "Common extensions" into language-reviewer block + 2-row stack-specific table (`database-reviewer`, `performance-optimizer`). Decision file at `docs/agent-memory/decisions/2026-04-25_solo_default-reviewer-set-expansion.md`. Code-review artifact at `docs/reviews/2026-04-25_solo_P9.md` (APPROVE, 3 LOW findings addressed inline).

---

## Deploy Checklist

- [x] Three reviewer agents installed at `~/.claude/agents/` (verified via system reminder during build session)
- [x] Four slash commands registered in Claude Code's skill list (verified via system reminder showing `/ship`, `/release`, `/ship-on`, `/ship-off`)
- [x] SessionStop hook wired in `.claude/settings.json`
- [x] `ship-sop.config.json` at repo root with sensible defaults
- [x] Public README + spec doc + LICENSE
- [x] Pushed to GitHub (`mmjclayton/ship-sop`, public)
- [x] Companion projects pointer added to agent-sop README
- [x] Backlog, feature-map, decisions, gotchas, and build plan capture what shipped
- [N/A] All tests passing (no test runner — markdown + bash project)

---

## Open Questions

- Should ship-sop ship a CI workflow template (GitHub Actions) that runs the gates without a Claude session, for contributor PRs? [UNRESOLVED — file as future P-number when there's evidence anyone needs it]
- Should `release-notes-writer` support reading from a `CHANGELOG.md` (existing project) rather than only emitting one? [UNRESOLVED — would matter for projects already maintaining a changelog manually]
- Should there be a `--dry-run` mode for `/ship` that produces the readiness report without writing review files to `docs/reviews/`? [UNRESOLVED — useful for "is this ready?" questions without polluting the audit trail]
