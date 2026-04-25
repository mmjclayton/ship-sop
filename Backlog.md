# ship-sop — Backlog

Single source of truth for all work items. Never delete without a trace — update in place, mark superseded, or archive.

## Tag Taxonomy

- Status (first): `[OPEN]`, `[IN PROGRESS]`, `[BLOCKED]`, `[DEFERRED]`, `[SHIPPED - YYYY-MM-DD]`, `[VERIFIED - YYYY-MM-DD]`, `[WON'T]`
- Type (second): `[Feature]`, `[Iteration]`, `[Bug]`, `[Refactor]`
- Optional: `[has-open-questions]`, `[ok-for-automation]`, `[needs-triage]`

**Tag rules:**
- Status first, type second. Never reverse.
- `[BLOCKED]` = waiting on an external action.
- `[DEFERRED]` = intentionally postponed with no external blocker.
- `[WON'T]` requires inline reason.
- `[VERIFIED]` means tested in production.
- `[needs-triage]` is the auto-file marker from `compliance-reviewer`.
- P-numbers are assigned sequentially, never reused, and do not imply priority.

## Item Sizing

Each item should be small enough to ship in a single PR with a single clear outcome. If the title or description needs "and" or multiple top-level bullets, split it into separate P-numbered items.

---

## P-Numbered Items

### P1 — Initial scaffold (3 reviewer agents, 4 slash commands, hook, config, setup)
`[SHIPPED - 2026-04-25] [Feature]`

Scaffold ship-sop as a companion library to agent-sop. Pre-merge quality pipeline runnable from a Claude Code session.

**Shipped contents:**
- `compliance-reviewer` — PII / GDPR / HIPAA-applicability scan; auto-files Backlog entries
- `diagram-builder` — Mermaid state + sequence diagrams, API endpoint catalog, ARCHITECTURE Δ log
- `release-notes-writer` — CHANGELOG entries + GitHub Release body from Backlog/BatchLog/commits
- `/ship` slash command — manual entrypoint to the four-gate pipeline
- `/release` slash command — always-manual tagged release
- `/ship-on`, `/ship-off` — config-mode toggles
- `scripts/auto-ship-hook.sh` — SessionStop hook with throttle (min diff, cooldown, branch patterns) and config-driven per-agent toggles
- `setup.sh` — installs into a target project with consent prompt for hook wiring
- `docs/templates/ship-sop.config.json` + `.schema.json` — config template + JSON schema
- `README.md`, `docs/ship-sop.md`, `LICENSE` (MIT)

**Commit:** `bd05f40`

---

### P2 — Dogfood self-install + post-install rough-edge fixes
`[SHIPPED - 2026-04-25] [Iteration]`

Run `setup.sh` against ship-sop's own repo as the dogfood test. Fix three rough edges surfaced by the install.

**Shipped contents:**
- Self-install detection: `setup.sh` now compares `SCRIPT_DIR == TARGET` and skips duplicate copies of project-side files (cleaner output for dogfood)
- Next-steps output: explicit instruction to commit `ship-sop.config.json` + `.claude/settings.json` + `.gitignore` after install
- Hook flow documented: `docs/ship-sop.md` "How the hook actually executes" subsection explaining the SessionStop → directive file → next-turn pattern

**Acceptance criteria met:**
- Three reviewer agents installed at `~/.claude/agents/`
- Four slash commands installed at `~/.claude/commands/`
- `.claude/settings.json` wired with the SessionStop hook (consent-prompted)
- `ship-sop.config.json` at the project root
- `.gitignore` excludes `.ship/`

**Commit:** `e82ccd5`

---

### P3 — End-to-end dogfood of the auto-mode pipeline + leftover-rename fix
`[SHIPPED - 2026-04-25] [Iteration]`

Manually fire the SessionStop hook against a real diff (Uninstall section added to README) and execute the gates inline. Validates the full flow end-to-end.

**What was tested:**
1. Hook detected 38-line diff (above 10-line throttle) ✓
2. Hook resolved diff range correctly ✓
3. Hook wrote `.ship/.pending-auto-fire.md` directive listing the three enabled gates ✓
4. Hook stamped `.last-auto-fire` and `.last-diff-hash` for cooldown/dedup ✓
5. Hook emitted next-turn context message ✓
6. Acted as next-turn model: ran security, compliance, diagram-builder gates inline against the diff ✓
7. All three gates returned APPROVE; tests skipped (no runner) ✓
8. Per-gate review files + consolidated `ship-auto.md` written to `docs/reviews/` ✓

**Bug fix:** the directive header still said "Ship-pipeline auto-mode" — leftover string from the pre-rename codebase. Now reads "ship-sop auto-mode".

**Commits:** `7db908e` (Uninstall README section), `31f984e` (test artifacts + leftover-rename fix)

---

### P4 — Docs-only detection in the SessionStop hook
`[SHIPPED - 2026-04-25] [Bug]`

Mirror `/ship`'s docs-only behaviour in `scripts/auto-ship-hook.sh`. Previously the hook ran every enabled agent regardless of diff content — security and compliance gates fired on README-only changes and reliably returned APPROVE, producing noise.

**What changed:**
- Docs-only detection added: scans every changed file against `^docs/`, `\.(md|mdx)$`, `^README`. If all files match, sets `DOCS_ONLY=true`.
- Agent filter: when `DOCS_ONLY=true`, the directive includes only advisory gates (`block_on: "never"`). Hard-blocking gates skip cleanly. Config-driven, no hardcoded names.
- Directive annotation: `Mode: docs-only (hard-blocking gates skipped — only advisory gates listed below)` line appears at the top when docs-only mode is active.

**Acceptance criteria met:**
- 10-line README-only commit triggers the hook
- Directive correctly lists only `@diagram-builder`
- Docs-only banner appears at the top of the directive
- Mixed-file diffs continue to list all enabled agents

**Commit:** `bc2e9d7`

---

### P5 — Install agent-sop on ship-sop for retrospective record
`[SHIPPED - 2026-04-25] [Feature]`

Install agent-sop into ship-sop with the base template. Backfill CLAUDE.md, Backlog.md, feature-map.md, decisions, gotchas, build plan, and recent-work entry to capture what already shipped (P1-P4). Not for driving new work — for recording the history that surfaced during the initial scaffold + dogfood session.

**Shipped contents:**
- agent-sop file set: `CLAUDE.md`, `Backlog.md`, `docs/agent-memory.md`, `docs/feature-map.md`, `docs/build-plans/phase-0-foundation.md`, `docs/sop/*`, `docs/guides/*`, `docs/templates/review-template.md`
- Backfilled this Backlog with P1-P5 retroactive items (this entry being P5)
- Decisions captured under `docs/agent-memory/decisions/`
- Gotchas captured under `docs/agent-memory/gotchas/`
- Phase 0 build plan with retrospective Batch Log
- Recent-work entry summarising 2026-04-25 session

**Why retrospective:** ship-sop is at "released, working, no immediate roadmap." agent-sop's primary value is across sessions on active work, but its secondary value is durable record of what was decided and why — that record is worth capturing now, while the context is fresh.

---

## Shipped Archive

*Items below are shipped or verified. Never removed. Move items here when Backlog.md exceeds ~2,000 lines and items are older than 90 days.*

(Empty — all P-numbered items above are still in the recent block.)
