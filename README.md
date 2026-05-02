# ship-sop

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-v2.1.101+-orange.svg)](https://code.claude.com/docs/en/changelog)

Pre-merge quality pipeline for Claude Code sessions. Runs language-agnostic gates — **tests, security, compliance, code quality, silent-failure detection, test-coverage analysis, diagrams + API catalog** — against the diff between your branch and the default branch. Fires automatically on session-end via a hook, or manually via `/ship`.

## Why

Every code change you ship needs the same hygiene: tests pass, no security regressions, no PII leaks or compliance drift, documentation kept in sync. Doing this manually means it gets skipped under pressure. Doing it via a CI step happens too late — after you've already opened a PR.

ship-sop runs these checks **at session-end automatically**, so the gate is closer to the work and the feedback loop is tight. You can also run the same pipeline manually via `/ship` when you want strict-gate behaviour before opening a PR.

## What runs

| # | Gate | Owner | Hard block? |
|---|------|-------|-------------|
| 1 | Tests | project's runner (`npm test` / `pytest` / `cargo test` / `go test`) | Yes — on failure |
| 2 | Security | `@security-reviewer` (from agent-sop or your own install) | Yes — on CRITICAL |
| 3 | Compliance | `@compliance-reviewer` — PII / GDPR / HIPAA-applicability | Yes — on CRITICAL |
| 4 | Code quality | `@code-reviewer` — language-agnostic quality, error handling, dead code | Yes — on HIGH |
| 5 | Silent failures | `@silent-failure-hunter` — empty catches, swallowed errors, dangerous fallbacks | Yes — on HIGH |
| 6 | Test coverage | `@pr-test-analyzer` — behavioural coverage of changed code | Never — advisory |
| 7 | Diagrams + API catalog + ARCHITECTURE Δ | `@diagram-builder` | Never — advisory |

Plus a manual `/release` command that runs `@release-notes-writer` to generate CHANGELOG entries and a tagged GitHub Release. Releases are always deliberate.

**Language-specific reviewers are not in the default set.** Add `typescript-reviewer`, `python-reviewer`, `go-reviewer`, etc. per project — see "Common extensions" below.

## Two modes

**Auto** (default after install) — a SessionStop hook reads `ship-sop.config.json`, applies throttle rules, runs the configured gates against the session's diff. Findings inject a strong warning into the next turn's context but never halt the session — auto-mode prioritises non-disruption.

**Manual** — `/ship` runs the same gates and writes the same artifacts, but **halts on hard-block failures**. Use when you want strict-gate behaviour before opening a PR.

Both modes share the same agents, the same config, and produce the same artifacts. The trigger and failure mode differ.

## How auto-mode actually executes

Non-obvious detail worth understanding: Claude Code's SessionStop hooks run as plain shell scripts — they cannot themselves invoke `@agent` calls (that requires a model turn). ship-sop splits the work in two:

1. **At session-stop:** `scripts/auto-ship-hook.sh` runs throttle checks and writes a directive file at `.ship/.pending-auto-fire.md` listing which gates to run, the diff range, and the report destination. Stdout from the hook is piped into the *next turn's* context window.
2. **On the next user turn:** the model sees the directive in context, reads `.ship/.pending-auto-fire.md`, and invokes the configured `@compliance-reviewer`, `@diagram-builder`, etc. against the captured diff range.

Practical flow: you finish a session → the hook fires silently → next time you start a turn in the same project, the model picks up the pending directive and runs the gates before responding to your prompt. Findings land in `docs/reviews/` and surface in the model's reply.

This means:
- **Auto-mode reviews are not instantaneous.** They run on the next turn, not at session-end.
- **Findings appear inside the model's response**, not as a separate notification. Watch the reply for the auto-review summary.
- **The directive file is the audit trail of what the hook scheduled.** Inspect `.ship/.pending-auto-fire.md` if the behaviour seems unexpected.

If you want immediate review output, run `/ship` manually — that invokes the gates in the current turn.

## Per-agent toggles

`ship-sop.config.json` controls which agents run:

```json
{
  "trigger": { "mode": "auto" },
  "agents": {
    "security-reviewer":     { "enabled": true, "block_on": "CRITICAL" },
    "compliance-reviewer":   { "enabled": true, "block_on": "CRITICAL", "auto_file_backlog": true },
    "code-reviewer":         { "enabled": true, "block_on": "HIGH" },
    "silent-failure-hunter": { "enabled": true, "block_on": "HIGH" },
    "pr-test-analyzer":      { "enabled": true, "block_on": "never", "auto_file_backlog": false },
    "diagram-builder":       { "enabled": true, "block_on": "never" }
  }
}
```

Disable any gate by flipping `enabled: false`. Make any gate advisory by setting `block_on: "never"`. `/ship-on` and `/ship-off` flip the trigger mode without editing the file.

### Common extensions

Add language- and stack-specific gates as your project needs them. The schema permits arbitrary agent keys; the hook reads them dynamically.

**Language reviewers** — pick the one that matches the project's stack. One is enough; ship-sop is opinionated against running every reviewer in the registry.

```json
{
  "agents": {
    "typescript-reviewer": { "enabled": true, "block_on": "HIGH" },
    "python-reviewer":     { "enabled": true, "block_on": "HIGH" },
    "go-reviewer":         { "enabled": true, "block_on": "HIGH" },
    "rust-reviewer":       { "enabled": true, "block_on": "HIGH" }
  }
}
```

**Stack-specific gates** — opt in when the project's surface area justifies the cost.

| Agent | Opt in when | Suggested `block_on` |
|---|---|---|
| `database-reviewer` | Project has SQL or migrations | `HIGH` |
| `performance-optimizer` | Latency SLAs, mobile, real-time, or perf-sensitive | `never` (advisory) |

## Throttle defaults

Auto-mode skips when:
- Diff is below 10 lines (exploratory poking)
- Cooldown of 5 min hasn't elapsed since last fire on the same diff state
- Branch matches `^wip/`, `^spike/`, or `^exp/`

All configurable in `ship-sop.config.json`.

## Quick start

```bash
git clone https://github.com/<user>/ship-sop ~/Projects/ship-sop
cd ~/Projects/ship-sop

./setup.sh /path/to/your/project
```

That installs:
- Three agents into `~/.claude/agents/` (`compliance-reviewer`, `diagram-builder`, `release-notes-writer`)
- Five slash commands into `~/.claude/commands/` (`/ship`, `/release`, `/audit`, `/ship-on`, `/ship-off`)
- `scripts/auto-ship-hook.sh` into the project (executable)
- `ship-sop.config.json` at the project root (with defaults)
- An entry in `.claude/settings.json` wiring the SessionStop hook (with consent prompt)

The default config also references three additional gates — `code-reviewer`, `silent-failure-hunter`, `pr-test-analyzer` — that ship-sop does not vendor. They come from agent-sop or your existing user-scope agent install at `~/.claude/agents/`. Same model `security-reviewer` uses.

Pass `--no-hook` to skip the hook wiring (manual `/ship` only).

Then in a Claude Code session in your project:

```
/ship          # run the pipeline manually against the current diff
/audit         # whole-codebase compliance scan (use at launch-readiness milestones)
/ship-off      # disable auto-mode
/ship-on       # enable auto-mode
/release       # cut a tagged GitHub Release (always manual)
```

## Outputs

Every gate writes a durable artifact under `docs/reviews/`:

```
docs/reviews/
├── 20260425-153012-ship-report.md         # the readiness summary
├── 20260425-153012-security.md
├── 20260425-153012-compliance.md
├── 20260425-153012-code-reviewer.md
├── 20260425-153012-silent-failure-hunter.md
├── 20260425-153012-pr-test-analyzer.md
└── 20260425-153012-diagram-builder.md
```

Each enabled gate writes its own artifact — the tree above shows the default 6-gate set.

`diagram-builder` additionally produces:

```
docs/
├── ARCHITECTURE.md            # Δ log appended per ship that changes architecture
├── diagrams/<feature>.md      # Mermaid state + sequence diagrams
└── api/<service>.md           # endpoint catalog with schemas
```

Hand-edited docs (no `<!-- generated by diagram-builder -->` marker) are never overwritten — diagram-builder writes alongside them as `<path>.generated.md`.

## Compliance scope

`compliance-reviewer` covers PII handling, GDPR, HIPAA-applicability, and data retention.

- **GDPR** — applies by default; disable in `compliance.config.json` with `"gdpr": false`
- **HIPAA** — advisory only; flags when health / medical / clinical data appears in the diff so you can confirm covered-entity status. Does not enforce HIPAA on non-covered projects.
- **CCPA** — off by default; opt in via config
- **Project-specific** — SOC 2, PCI-DSS, etc. configurable in `compliance.config.json`

Not legal advice. A sanity gate, not counsel.

## Composes with agent-sop

[agent-sop](https://github.com/mmjclayton/agent-sop) is the companion library for session discipline (start/end checklists, cross-session memory, parallel multi-agent sessions). The two are independent but pair naturally:

- **agent-sop** manages session lifecycle and curates `Backlog.md`, `docs/agent-memory/`, build plans
- **ship-sop** runs quality gates against the diff and auto-files Backlog entries using agent-sop's conventions

If you use both: `compliance-reviewer` files `[OPEN][Bug][needs-triage]` Backlog entries with proper P-numbers; `release-notes-writer` reads `[SHIPPED]` items and Batch Logs as primary sources.

If you use only ship-sop: agents write findings to `docs/reviews/` only; release notes fall back to conventional-commit parsing.

## Composes with doc-updater

If you use Claude Code's reference `doc-updater` agent (or have your own), it stays in its lane:

| Agent | Scope | Trigger |
|-------|-------|---------|
| `doc-updater` | Codemaps, README refresh, module import/export graphs | On-demand: `/update-codemaps`, `/update-docs` |
| `diagram-builder` (this) | Mermaid diagrams, API catalog, ARCHITECTURE Δ log | Auto: every `/ship` |

## Requirements

- Claude Code v2.1.101+
- `bash`, `git`, `jq` (auto-mode hook)
- `gh` CLI (only for `/release`)

## Troubleshooting

**Auto-mode doesn't seem to fire after a session.**
The hook exits silently on every throttle path (no git repo, no config, jq missing, branch matches `^wip/`/`^spike/`/`^exp/`, diff below `min_diff_lines`, cooldown not elapsed, same-diff hash, no enabled agents, …). Set `SHIP_SOP_DEBUG=1` to surface the exact reason on stderr:

```bash
SHIP_SOP_DEBUG=1 bash scripts/auto-ship-hook.sh
# [ship-sop] skip: cooldown elapsed=42s < 300s
```

**Config typos silently disable a gate.**
The hook now warns on unknown keys at config load (e.g. `enabld: true` for `enabled`). Look for `[ship-sop] config warning: unknown key '...'` lines on stderr.

**`docs/reviews/` is bloating.**
Set `artifacts.retain_ship_artifact_days` (integer, days) in `ship-sop.config.json` to auto-prune ship-sop's `YYYYMMDD-HHMMSS-*.md` artifacts. Agent-sop's permanent `YYYY-MM-DD_<agent-id>_P<n>.md` reviews are never touched.

```json
{ "artifacts": { "retain_ship_artifact_days": 90 } }
```

## Uninstall

```bash
cd ~/Projects/ship-sop      # or wherever you cloned ship-sop
./setup.sh /path/to/your/project --uninstall
```

That removes the same install footprint setup.sh added: user-scope agents and commands, the project's `scripts/auto-ship-hook.sh`, `ship-sop.config.json`, the schema template, the `.gitignore` block, and the SessionStop hook entry in `.claude/settings.json`.

### Uninstall flags

| Flag | Effect |
|------|--------|
| `--keep-config` | Keep `ship-sop.config.json` (preserve per-project tuning across reinstalls) |
| `--keep-artifacts` | Keep `.ship/` runtime directory (cooldown stamps, pending directives) |
| `--force` | Remove user-scope agents and commands even if locally modified |

By default, the uninstaller is **safe**: any user-scope agent or command whose hash differs from the source (i.e., you've customized it) is skipped with a notice. `--force` removes them anyway.

### Files never auto-removed

- `docs/reviews/` — review history; audit trail
- `docs/agent-memory/` — any decisions or gotchas captured by reviewer agents
- `docs/diagrams/`, `docs/api/`, `docs/ARCHITECTURE.md` — generated by `diagram-builder`; treat as you would any other generated docs

These survive uninstall by design. Remove manually if you don't want them.

<details>
<summary><b>Manual fallback</b> — if you can't run <code>setup.sh</code> (e.g. the ship-sop clone is gone)</summary>

```bash
# User-scope (affects all projects)
rm ~/.claude/agents/{compliance-reviewer,diagram-builder,release-notes-writer}.md
rm ~/.claude/commands/{ship,release,ship-on,ship-off,audit}.md

# Project-scope (per project; run in project root)
rm ship-sop.config.json
rm scripts/auto-ship-hook.sh
rm -f docs/templates/ship-sop.schema.json
rm -rf .ship/

# Remove the SessionStop hook entry, keeping any other hooks intact
jq 'del(.hooks.Stop[]? | select(.command == "scripts/auto-ship-hook.sh"))' .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json

# Remove the .gitignore block
awk '/^# ship-sop runtime artifacts$/ { skip=2; next } skip>0 { skip--; next } { print }' .gitignore > .gitignore.tmp && mv .gitignore.tmp .gitignore
```

</details>

## Contributing

Changes ship via pull request to `main` — direct pushes to `main` are blocked. The flow:

1. Branch from `main` (`git switch -c <topic>`).
2. Make changes following ship-sop's own SOP — every shipped change updates `Backlog.md`, `docs/feature-map.md`, the relevant phase plan in `docs/build-plans/`, and a `docs/recent-work/` entry. See `CLAUDE.md` for the full session-end checklist.
3. Push the branch (`git push -u origin <topic>`) and open a PR via `gh pr create`.
4. Merge once green.

ship-sop dogfoods itself: open a PR with a >10-line diff and the SessionStop hook will queue an auto-mode review for the next turn. Manual `/ship` is also available before pushing.

## License

MIT. Copyright (c) 2026 Matt Clayton.
