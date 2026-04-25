# ship-sop — Pre-merge quality pipeline for Claude Code sessions

> Tests, security, compliance, diagrams. Auto-fires on session-end or manually via `/ship`. Companion to agent-sop.

---

## Agent SOP

All agents working on this project follow the Claude Code Agent SOP (`docs/sop/claude-agent-sop.md`). The SOP defines the standard file structure, never-delete-without-a-trace policy, session checklists, and update triggers. This file (CLAUDE.md) is the authority on project-specific conventions. The SOP is the authority on process.

ship-sop dogfoods both itself (the SessionStop hook is wired in `.claude/settings.json`) and agent-sop (the file set in this repo follows the SOP conventions).

---

## Build Plans — READ FIRST

Always check `docs/build-plans/` at the start of any session to see what has shipped, what is in flight, and what is next.

Current phase files:
- `docs/build-plans/phase-0-foundation.md` — Shipped 2026-04-25 (initial scaffold + dogfood)

---

## Key Documents & Dispatch

| When you need to... | Start at | Notes |
|---------------------|----------|-------|
| Read cross-session context | `docs/agent-memory.md` | Decisions, gotchas, invariants |
| Check shipped features or roadmap | `docs/feature-map.md` | Shipped inventory |
| Check or update work items | `Backlog.md` | Single source of truth |
| Read phase architecture | `docs/build-plans/phase-0-foundation.md` | Batch log + locked decisions |
| Understand the spec | `docs/ship-sop.md` | Six gates, escape hatches, integration with agent-sop |
| Modify a reviewer agent | `.claude/agents/<name>.md` | One file per agent — installed user-scope by setup.sh |
| Modify a slash command | `.claude/commands/<name>.md` | `/ship`, `/release`, `/ship-on`, `/ship-off` |
| Modify the SessionStop hook | `scripts/auto-ship-hook.sh` | Bash script; throttle + directive emission |
| Modify defaults | `docs/templates/ship-sop.config.json` | Per-agent toggles, throttle, release config |
| Modify the installer | `setup.sh` | Detects self-install via SCRIPT_DIR == TARGET |
| Read the public-facing pitch | `README.md` | What ships into the world |

Test: no automated test runner — this is a markdown + bash project. Manual dogfood is the test (run `bash scripts/auto-ship-hook.sh` against a real diff and inspect `.ship/.pending-auto-fire.md`).
After shipping: update Backlog.md + docs/feature-map.md + docs/build-plans/phase-N.md Batch Log

### Current Priority Items (as of 2026-04-25)

**Done — no active priorities.** ship-sop is at "released, working, no immediate roadmap." Open the Backlog and look at the [SHIPPED] block to see what landed in P1-P5. New items will appear here when surfaced.

Likely future candidates (not yet filed):
- Dogfood `/release` end-to-end on the next ship-sop change
- CI workflow that runs the gates without a Claude session (currently auto-mode requires a Claude session)
- `setup.sh --uninstall` for clean removal (the README documents the manual procedure)

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

- **Type:** Markdown + bash library (no compiled code, no test runner)
- **Key technologies:** bash 4+, jq, gh CLI (for `/release` only), Claude Code v2.1.101+
- **Hosting:** GitHub (`mmjclayton/ship-sop`)
- **CI:** None yet — see "Likely future candidates" above
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

# Cut a release (from main, clean tree, gh authenticated)
# /release  ← inside a Claude Code session

# Inspect the public-facing repo
gh repo view mmjclayton/ship-sop
```

---

## Common Mistakes — Read Before Working

- **Stop hooks cannot invoke `@agent` directly.** They run as plain shell scripts. ship-sop's hook (`scripts/auto-ship-hook.sh`) writes `.ship/.pending-auto-fire.md` and pipes a context message to stdout — the *next-turn model* reads the directive and runs the gates. If you're tempted to make the hook "smarter" by invoking agents directly, it can't.
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
- README.md and docs/ship-sop.md reflect the new behaviour
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
6. ship-sop's auto-mode hook is wired on this repo. Expect a directive at `.ship/.pending-auto-fire.md` after sessions that produced a >10-line diff.

---

## Session & Memory Hygiene

Memory files live at `~/.claude/projects/[project-hash]/memory/`.

### Session start: run `/restart-sop`

### Session end: run `/update-sop`

Both commands are documented in agent-sop's installed slash commands at `~/.claude/commands/`.

---

## Recent Work (rollup)

<!-- Auto-generated by /update-sop Step 8b from docs/recent-work/*.md. Do not edit by hand — directory contents are the source of truth. Per-session entry files use filename pattern YYYY-MM-DD_<agent-id>_<slug>.md. See docs/guides/multi-agent-parallel-sessions.md. -->

<!-- recent-work-rollup:start -->
*Auto-generated from `docs/recent-work/`. Last refreshed: 2026-04-25.*

- 2026-04-25 `solo`: P1-P5: Initial scaffold, dogfood, docs-only fix, agent-sop install
<!-- recent-work-rollup:end -->

---

## Deprioritised

*Items moved here from priority lists above. Never removed.*
