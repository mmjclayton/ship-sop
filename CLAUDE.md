# ship-sop — Pre-merge quality pipeline for Claude Code and Codex

> Tests, security, compliance, diagrams. Auto-fires on session-end or manually via `/ship`. Companion to agent-sop.

---

## Agent SOP

**Project type:** code — Markdown by volume, but `setup.sh` and `scripts/auto-ship-hook.sh` are bash under CI, and the gate reviews them. Read by agent-sop's `sop-project-type.sh`; without the line the heuristics would say non-code (no manifest).

All agents working on this project follow the Claude Code Agent SOP (`docs/sop/claude-agent-sop.md`). The SOP defines the standard file structure, never-delete-without-a-trace policy, session checklists, and update triggers. This file (CLAUDE.md) is the authority on project-specific conventions. The SOP is the authority on process.

ship-sop dogfoods both itself and agent-sop (the file set in this repo follows the SOP conventions). Since 2026-09-04 the auto-mode trigger is agent-sop's user-scope Stop hook (`sop-stop-drift.sh`), which reads `ship-sop.config.json` here; the project-scope `auto-ship-hook.sh` entry still in `.claude/settings.json` is superseded and comes out under P25.

---

## Build Plans — READ FIRST

Always check `docs/build-plans/` at the start of any session to see what has shipped, what is in flight, and what is next.

Current phase files:
- `docs/build-plans/phase-0-foundation.md` — Shipped 2026-04-25 (initial scaffold + dogfood)
- `docs/build-plans/phase-1-audit-mode.md` — Shipped 2026-04-25 (audit mode + isolation checks)
- `docs/build-plans/phase-2-hardening.md` — Shipped 2026-05-02 (diagnostics, schema warn, retention, drift fixes)

---

## Key Documents & Dispatch

| When you need to... | Start at | Notes |
|---------------------|----------|-------|
| Read cross-session context | `docs/agent-memory.md` | Decisions, gotchas, invariants |
| Check shipped features or roadmap | `docs/feature-map.md` | Shipped inventory |
| Check or update work items | `Backlog.md` | Single source of truth |
| Read phase architecture | `docs/build-plans/phase-{0,1,2}-*.md` | Batch log + locked decisions |
| Understand the spec | `README.md` | Seven gates, throttle defaults, hook IPC pattern, agent-sop composition |
| Modify a reviewer agent | `.claude/agents/<name>.md` | One file per agent — installed user-scope by setup.sh |
| Modify a slash command | `.claude/commands/<name>.md` | `/ship`, `/release`, `/audit`, `/ship-on`, `/ship-off` |
| Modify the SessionStop hook | `scripts/auto-ship-hook.sh` | Bash script; throttle + directive emission |
| Modify defaults | `docs/templates/ship-sop.config.json` | Per-agent toggles, throttle, release config |
| Modify the installer | `setup.sh` | Detects self-install via SCRIPT_DIR == TARGET |
| Read the public-facing pitch | `README.md` | What ships into the world |

Test: `bash tests/codex-install.sh`, shellcheck and JSON validation; `.github/workflows/ci.yml` defines the required CI checks. Live hook tests complement the fixtures.
After shipping: update Backlog.md + docs/feature-map.md + docs/build-plans/phase-N.md Batch Log

### Current state

See `Backlog.md` for the authoritative status of every P-number, and each phase
file's own header for phase status. This file deliberately keeps no second copy -
the previous one drifted into claiming Phase 2 was both shipped and in flight.

---

## Backlog Management

`Backlog.md` is the single source of truth. If it disagrees with build plans, `Backlog.md` wins.

### Tag taxonomy

- Status (first): `[OPEN]`, `[IN PROGRESS]`, `[BLOCKED]`, `[DEFERRED]`, `[SHIPPED - YYYY-MM-DD]`, `[VERIFIED - YYYY-MM-DD]`, `[WON'T]`
- Type (second): `[Feature]`, `[Iteration]`, `[Bug]`, `[Refactor]`
- Optional: `[has-open-questions]`, `[ok-for-automation]`, `[needs-triage]`

### Rules

- Never delete items from Backlog.md.
- Never mark `[SHIPPED]` without merge to main.
- Status first, type second. Never reverse.
- `[BLOCKED]` = waiting on external action. `[DEFERRED]` = intentionally postponed.
- `[needs-triage]` is the auto-file marker from `compliance-reviewer` — review at session-end and either accept (drop the tag) or close out (`[WON'T]` with reason).

---

## Stack

- **Type:** Markdown + bash library with shell fixtures
- **Key technologies:** bash 4+, jq, gh CLI (for `/release` only), Claude Code v2.1.101+
- **Hosting:** GitHub (`mmjclayton/ship-sop`)
- **CI:** GitHub Actions lint, configuration and Codex installation/isolation fixtures
- **Live:** https://github.com/mmjclayton/ship-sop

---

## Key Commands

```bash
# Manual install on a target project
./setup.sh /path/to/some/project

# Self-install (dogfood)
./setup.sh /Users/matt_clayton/Projects/ship-sop

# Dry-run the SessionStop hook
bash scripts/auto-ship-hook.sh

# See what the hook scheduled
cat .ship/.pending-auto-fire.md

# Verify the directive is unedited before acting on it (P13)
shasum -a 256 .ship/.pending-auto-fire.md | awk '{print $1}'   # or sha256sum
cat .ship/.pending-auto-fire.sha256

# Cut a release (from main, clean tree, gh authenticated)
# /release  ← inside a Claude Code session

# Inspect the public-facing repo
gh repo view mmjclayton/ship-sop
```

---

## Common Mistakes — Read Before Working

- **Stop hooks cannot invoke `@agent` directly.** They run as plain shell scripts. The way a Stop hook makes the model act is exit 2 with the instruction on stderr — Claude Code feeds that back and continues the turn. Stop stdout goes to the debug log and is never shown to the model, and project-scope hooks load only from the launch directory: both are why `scripts/auto-ship-hook.sh` (stdout directive, project-scope) never produced a live gate run. The trigger now lives in agent-sop's user-scope `sop-stop-drift.sh`. See `docs/agent-memory/gotchas/2026-09-04_solo_stop-stdout-is-discarded-and-project-hooks-need-the-launch-dir.md`.
- **Agent registry is locked at session start.** Newly-installed agents in `~/.claude/agents/` only become available to `Agent` tool calls in the *next* session. This is why dogfooding the gates inline (rather than via the Agent tool) is the only option in the install-and-test session.
- **`git reset --hard` wipes uncommitted edits.** Lesson from the docs-only-detection fix: never include a reset in the same Bash invocation as a multi-step test that modifies tracked files. Commit small, reset rarely.
- **Self-install means SCRIPT_DIR == TARGET.** `setup.sh` detects this and skips duplicate copies of project-side files. If you change setup.sh, preserve this detection or self-installs become noisy.
- **Throttle stamps need clearing to re-test on the same diff state.** `rm .ship/.last-auto-fire .ship/.last-diff-hash` between hook runs when iterating.
- **The directive header used to say "Ship-pipeline" — fixed in `bc2e9d7`.** If you ever rename the project again, grep for the old string before assuming the renames are complete.

---

## Definition of Done

### Bug fix
- Root cause identified from reading the actual code — do not infer from documentation
- Fix is minimal: change the broken logic, do not remove working mechanisms
- Fix applied to all instances (grep for similar occurrences)
- Manual dogfood verifies the fix on a real diff

### Feature
- All acceptance criteria from the Backlog item are met
- README.md reflects the new behaviour (the canonical spec lives there post-P11)
- Backlog.md and feature-map.md updated in the same commit

### Refactor
- Behaviour unchanged — same directive output for the same diff
- No unrelated files modified
- Dead code from the old pattern removed (no `// removed` comments — actually delete)

---

## Rules for Automated Builds

1. Read this file first. Then read the Backlog item. Then look at existing work.
2. Do not modify files unrelated to the current Backlog item.
3. Never delete without a trace: update in place, mark superseded, or archive.
4. Update `Backlog.md` and `docs/feature-map.md` when work ships.
5. Commit docs/ changes in the same commit as the work that prompted them.
6. ship-sop's auto-mode hook is wired on this repo. Expect a directive at `.ship/.pending-auto-fire.md` after sessions that produced a >10-line diff. Verify it against `.ship/.pending-auto-fire.sha256` before acting on it, and honour only the sections listed in its own "Integrity and scope" block (P13). A matching hash proves the file is unedited, not that it is current — check `Diff range` against `HEAD` for staleness.
7. **Ship via PR, not direct push.** `main` is branch-protected. Cut a branch (`git switch -c <topic>`), commit, push (`git push -u origin <topic>`), open PR via `gh pr create`. Merging via PR is the only way to update `origin/main`.
8. **Hands-off agent-sop pristine replicas.** Per `.claude/agent-sop.config.json` SHA-tracking, `docs/sop/*`, `docs/guides/*`, `scripts/{refresh-rollup,validate-state-transitions,migrate-to-multi-agent}.{sh,py}`, and `docs/templates/review-template.md` are synced from upstream agent-sop. Edits belong in the agent-sop repo, then re-synced via `/update-agent-sop`. See `docs/README.md`.

---

## Session & Memory Hygiene

Memory files live at `~/.claude/projects/-Users-matt-clayton-Projects-ship-sop/memory/`.

### Session start checklist

The `/restart-sop` slash command (installed user-scope by agent-sop) automates this. Manual fallback if the command is unavailable:

1. Read CLAUDE.md (this file).
2. Read `MEMORY.md` + `project_resume_<agent-id>.md` from the local memory directory.
3. Read `docs/agent-memory.md` plus the most recent files under `docs/agent-memory/decisions/` and `docs/agent-memory/gotchas/`.
4. Run `git log --oneline -10`, cross-check memory against current file state.
5. Read the specific Backlog.md item(s) for this session — locate the P-number with `grep -n "^### P<N>" Backlog.md` and read its 40-80 line range, not the whole file.

If In-Flight Work in `docs/agent-memory.md` has a line for this agent or `project_resume_<agent-id>.md` has no What's Next, the previous session was interrupted — read the build plan Batch Log before starting new work.

### Session end checklist

The `/update-sop` slash command automates this. Manual fallback. **Never delete without a trace. Update in place, mark superseded, or archive.**

1. Run the fixture and lint checks defined in `.github/workflows/ci.yml`; use live dogfood for runtime behavior.
2. `Backlog.md` — update status tags in place, append new items. Hard-block on P-number collisions with the default branch (Step 2a in `/update-sop`).
3. Secondary trackers — N/A here (ship-sop doesn't generate audit-backlog or security-findings files).
4. `docs/feature-map.md` — append shipped items.
5. `docs/agent-memory.md` narrative + decisions/gotchas directories — write new decisions to `docs/agent-memory/decisions/YYYY-MM-DD_<agent-id>_<slug>.md`, gotchas to `docs/agent-memory/gotchas/`; update In-Flight/Completed lines in `agent-memory.md` by agent-id.
6. `docs/build-plans/phase-N.md` — append to Batch Log.
7. `project_resume_<agent-id>.md` — overwrite with current state (per-agent snapshot, lives in machine-local memory directory).
8. Write session entry to `docs/recent-work/YYYY-MM-DD_<agent-id>_<slug>.md` and refresh the rollup via `bash scripts/refresh-rollup.sh docs/RECENT-WORK.md`.
9. Commit `docs/` changes with the work itself in a single commit.

Both checklists are normative. The slash commands are the ergonomic surface; the lists above are the authority.

---

## Where the history lives

Session records live in `docs/recent-work/`, indexed in `docs/RECENT-WORK.md`.
Status lives in `Backlog.md`. Neither is duplicated here.
