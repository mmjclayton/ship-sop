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
- Four slash commands into `~/.claude/commands/` (`/ship`, `/release`, `/ship-on`, `/ship-off`)
- `scripts/auto-ship-hook.sh` into the project (executable)
- `ship-sop.config.json` at the project root (with defaults)
- An entry in `.claude/settings.json` wiring the SessionStop hook (with consent prompt)

The default config also references three additional gates — `code-reviewer`, `silent-failure-hunter`, `pr-test-analyzer` — that ship-sop does not vendor. They come from agent-sop or your existing user-scope agent install at `~/.claude/agents/`. Same model `security-reviewer` uses.

Pass `--no-hook` to skip the hook wiring (manual `/ship` only).

Then in a Claude Code session in your project:

```
/ship          # run the pipeline manually
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

`compliance-reviewer` covers:

- **GDPR** — applies by default; disable in `compliance.config.json`
- **HIPAA** — advisory only; flags when health/clinical data appears so you can confirm covered-entity status
- **CCPA** — off by default; opt in via config
- **Project-specific** — SOC 2, PCI-DSS, etc. configurable

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

## Uninstall

ship-sop adds files at three scopes. Removing them is straightforward and safe — none of the install steps modify code outside the install paths.

**User-scope (affects all projects):**

```bash
rm ~/.claude/agents/{compliance-reviewer,diagram-builder,release-notes-writer}.md
rm ~/.claude/commands/{ship,release,ship-on,ship-off}.md
```

**Project-scope (per project):**

```bash
# In the project root
rm ship-sop.config.json
rm scripts/auto-ship-hook.sh
rm -rf .ship/
# Optional: remove the SessionStop hook from .claude/settings.json
jq 'del(.hooks.Stop[] | select(.command == "scripts/auto-ship-hook.sh"))' .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
```

**Generated artifacts (keep or discard at your discretion):**

- `docs/reviews/` — review history; safe to keep as audit trail
- `docs/diagrams/`, `docs/api/`, `docs/ARCHITECTURE.md` — generated by `diagram-builder`; treat as you would any other generated docs

## License

MIT. Copyright (c) 2026 Matt Clayton.
