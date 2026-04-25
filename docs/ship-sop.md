# ship-sop

A pre-merge quality pipeline for Claude Code sessions. Four gates run against the diff between your current branch and the default branch — automatically on session-end, or manually via `/ship`.

## What this is

ship-sop runs four checks before you ship code, each producing a durable artifact:

| # | Gate | Owner | Hard block? |
|---|------|-------|-------------|
| 1 | Tests | (project's test runner — `npm test` / `pytest` / `cargo test` / `go test`) | Yes — on failure |
| 2 | Security | `@security-reviewer` (from agent-sop or your own install) | Yes — on CRITICAL |
| 3 | Compliance | `@compliance-reviewer` (this library) | Yes — on CRITICAL |
| 4 | Diagrams + API catalog + ARCHITECTURE Δ | `@diagram-builder` (this library) | Never — advisory |

Plus a separate, always-manual `/release` command that runs `@release-notes-writer` to generate CHANGELOG entries and a tagged GitHub Release.

## What this is not

- **Not a replacement for `agent-sop`.** ship-sop is a quality gate; agent-sop is session discipline. They work in parallel: agent-sop manages start/end checklists and cross-session memory, ship-sop runs gates before merge. If you use both, ship-sop auto-files Backlog entries using agent-sop conventions; if you use only ship-sop, it writes findings to `docs/reviews/` only.
- **Not a deployer.** It produces a readiness verdict and writes documentation. It does not push, tag, or publish — those are explicit operator actions.
- **Not a replacement for `doc-updater`.** `diagram-builder` is narrow: ship-time Mermaid diagrams + API catalog + ARCHITECTURE Δ log. For broader codemap and README maintenance, invoke `@doc-updater` directly.

## Two modes

### Auto mode (default after install)

A SessionStop hook (`scripts/auto-ship-hook.sh`) reads `ship-sop.config.json`, applies throttle rules, and runs the configured gates against the session's accumulated diff.

When auto-mode finds a CRITICAL issue: it **does not halt your session**. Instead, it injects a strong warning into the next turn's context, with file:line references, plus writes the durable review artifact. You decide whether to fix immediately, defer, or override.

The throttle defaults skip the auto-fire when:
- Diff is below 10 lines (exploratory poking)
- Cooldown window (5 min) hasn't elapsed since last fire on the same diff state
- Branch matches `^wip/`, `^spike/`, or `^exp/` — explicit "I'm exploring" signal

### Manual mode

`/ship` runs the same gates and writes the same artifacts, but **halts the session on hard-block failures**. The operator fixes the finding, re-runs `/ship`, then ships.

Use manual mode when:
- You want strict-gate behaviour before opening a PR
- You're running ship-sop on a CI agent and want non-zero exit codes on block
- Auto-mode is off (`trigger.mode: "manual"`)

Both modes use the same agents, the same config, and produce the same artifacts. The difference is who pulls the trigger and how the failure surfaces.

## Configuration

`ship-sop.config.json` at the repo root (or `~/.claude/ship-sop.config.json` for user-global default):

```json
{
  "trigger": {
    "mode": "auto",
    "throttle": {
      "min_diff_lines": 10,
      "cooldown_seconds": 300,
      "skip_branch_patterns": ["^wip/", "^spike/", "^exp/"]
    }
  },
  "agents": {
    "security-reviewer": { "enabled": true, "block_on": "CRITICAL" },
    "compliance-reviewer": { "enabled": true, "block_on": "CRITICAL", "auto_file_backlog": true },
    "diagram-builder": { "enabled": true, "block_on": "never" }
  },
  "release": {
    "auto_publish": false,
    "default_branch": "main"
  }
}
```

Per-agent toggles let you turn any gate off without uninstalling. `block_on: "never"` makes a gate advisory only.

## Installation

```bash
git clone https://github.com/<user>/ship-sop ~/Projects/ship-sop
cd ~/Projects/ship-sop
./setup.sh /path/to/your/project
```

This installs:
- Three agents into `~/.claude/agents/` (compliance-reviewer, diagram-builder, release-notes-writer)
- Four slash commands into `~/.claude/commands/` (ship, release, ship-on, ship-off)
- `scripts/auto-ship-hook.sh` into the project (executable)
- `ship-sop.config.json` at the project root (with defaults)
- An entry in `.claude/settings.json` wiring the SessionStop hook (with consent prompt)

`setup.sh --no-hook` skips the hook wiring — useful for projects where you only want manual `/ship` and `/release`.

## Outputs and artifacts

Every gate writes to `docs/reviews/<stamp>-<gate>.md` for the durable audit trail:

```
docs/reviews/
├── 20260425-153012-ship-report.md       # the readiness summary
├── 20260425-153012-security.md          # security-reviewer findings
├── 20260425-153012-compliance.md        # compliance-reviewer findings
└── 20260425-153012-diagram-builder.md   # diagram-builder summary
```

`diagram-builder` additionally writes its content to:

```
docs/
├── ARCHITECTURE.md            # Δ log appended per ship that changes architecture
├── diagrams/
│   └── <feature>.md           # Mermaid state + sequence diagrams
└── api/
    └── <service>.md           # endpoint catalog with schemas
```

Hand-edited docs (no `<!-- generated by diagram-builder -->` marker) are never overwritten. Diagram-builder writes to `<path>.generated.md` instead and surfaces the conflict.

## Compliance scope

`compliance-reviewer` covers PII handling, GDPR, HIPAA-applicability, and data retention.

- **GDPR** — applies by default. Disable with `compliance.config.json` → `"gdpr": false`.
- **HIPAA** — advisory only. Flags when health/medical/clinical data appears in the diff so you can confirm covered-entity status. Does not enforce HIPAA on non-covered projects.
- **CCPA** — off by default; opt in via config.
- **Project-specific** — add SOC 2, PCI-DSS, etc. in `compliance.config.json`.

The agent does not give legal advice. It's a sanity gate, not counsel.

## Release flow

`/release` is **always manual**. Releases are public commitments — they get a human pulling the trigger every time.

```
Release plan:
  Version: 0.3.0
  Tag: v0.3.0
  Commit: a1b2c3d "feat: add auto-mode hook"
  Notes: .ship/release-notes-0.3.0.md (12 entries)
  Bump source: feat: commit triggered minor bump

Proceed? [y/N]
```

On confirm: writes a new section to `CHANGELOG.md`, commits it, tags `v0.3.0`, pushes the tag, creates the GitHub Release via `gh`.

`/release --no-publish` rehearses without publishing. `/release --draft` creates a draft release. `/release --version <X.Y.Z>` overrides the auto-bumped version.

## Composes with agent-sop

If `agent-sop` is also installed:

- `compliance-reviewer` auto-files findings as `[OPEN][Bug][needs-triage]` Backlog entries using agent-sop's P-numbering and tag taxonomy
- `release-notes-writer` reads `Backlog.md` `[SHIPPED]` items + build-plan Batch Logs as primary sources, falling back to commits
- `diagram-builder` works the same regardless

If only ship-sop is installed: agents write findings to `docs/reviews/` only and skip Backlog auto-filing. Release notes fall back to conventional-commit parsing.

## Composes without claude-code-specific patterns

ship-sop is also runnable as a plain CLI:

```bash
./scripts/auto-ship-hook.sh --manual
```

This is a stub for projects that want CI integration. Full CI mode (running gates without a Claude session) is out of scope for the initial release — auto-mode through Claude Code is the primary use case.
