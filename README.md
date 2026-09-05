# ship-sop

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-v2.1.251+-orange.svg)](https://code.claude.com/docs/en/changelog)

Pre-merge quality pipeline for Claude Code sessions. Runs language-agnostic gates — **tests, security, compliance, code quality, silent-failure detection, test-coverage analysis, diagrams + API catalog** — against the diff between your branch and the default branch. Runs manually via `/ship`; the automatic trigger now lives in [agent-sop](https://github.com/mmjclayton/agent-sop)'s user-scope hooks (see [Two modes](#two-modes)).

## Why

Every code change you ship needs the same hygiene: tests pass, no security regressions, no PII leaks or compliance drift, documentation kept in sync. Doing this manually means it gets skipped under pressure. Doing it via a CI step happens too late — after you've already opened a PR.

ship-sop runs these checks **when the agent stops with an unreviewed code diff**, so the gate is closer to the work and the feedback loop is tight. You can also run the same pipeline manually via `/ship` when you want strict-gate behaviour before opening a PR.

## What runs

Three gates by default (P27, 2026-09-05), each a read-only reviewer agent run in an isolated worktree against the code diff:

| Gate | Agent | Hard block? | Why it is on by default |
|---|---|---|---|
| Security | `@security-reviewer` | on CRITICAL | found a real HIGH and a path-traversal CRITICAL in the two consumer repos on record |
| Silent failures | `@silent-failure-hunter` | on HIGH | found both CRITICALs in the 2026-09-04/05 agent-sop runs with a 998-byte definition |
| Code quality | `@code-reviewer` | on HIGH | the artefact contract agent-sop's Step 1b asserts |

Tests run first through the project's own runner; a failure halts the ship.

Three more ship disabled and are added per run with `/ship --with <agent>` or per project by flipping `enabled`:

| Gate | Agent | Add when |
|---|---|---|
| Compliance | `@compliance-reviewer` | the diff touches routes, schema or migrations, logging, analytics SDK init, or a manifest (its own trigger list) |
| Test coverage | `@pr-test-analyzer` | tests changed and you want the gap list |
| Diagrams | `@diagram-builder` | a route, state machine or multi-collaborator handler changed |

Measured on the two agent-sop runs that set these defaults: the six-agent set cost 417k-561k tokens per ship, roughly 64k fixed per agent launched regardless of diff size; compliance and diagram-builder were 23% of that for zero findings. `/release` (manual) runs `@release-notes-writer` for CHANGELOG entries and a tagged GitHub Release.

**Language-specific reviewers are not in the default set.** Add `typescript-reviewer`, `python-reviewer`, `go-reviewer`, etc. per project — see "Common extensions" below.

### Relationship to agent-sop's Step 1b reviewer gate

One run serves both. On a code project with `trigger.mode: "auto"`, the gate run the Stop hook demands is also the Step 1b reviewer turn: the session writes the `*-ship-auto.md` report (with `Covers: <sha>`) and cites it from the Backlog entry's `review:` line, which `scripts/validate-state-transitions.sh --assert-review` accepts. Until 2026-09-05 the two were documented as intentionally independent runs on the same diff; that was a straight duplicate and is gone.

## Two modes

**Auto** (default after install) — agent-sop's user-scope `sop-stop-drift.sh` Stop hook reads `ship-sop.config.json`, applies the throttle rules, and when the code diff against the default branch has no gate report covering HEAD it exits 2 naming the enabled agents and the report path, so the model runs the gates before it finishes the turn. agent-sop's `sop-push-gate.sh` then refuses `git push` / `gh pr create` until a report covers HEAD (`SOP_SKIP_GATE=1` bypasses once, logged). Findings never halt the session — auto-mode prioritises non-disruption. Install with `bash scripts/install-hooks.sh` from the agent-sop checkout (superseded 2026-09-04: ship-sop's own project-scope `scripts/auto-ship-hook.sh` Stop hook, see [How auto-mode actually executes](#how-auto-mode-actually-executes)).

**Manual** — `/ship` runs the same gates and writes the same artifacts, but **halts on hard-block failures**. Use when you want strict-gate behaviour before opening a PR.

Both modes share the same agents, the same config, and produce the same artifacts. The trigger and failure mode differ.

## How auto-mode actually executes

Hooks run as plain shell scripts and cannot themselves invoke `@agent` calls; a model turn has to do that. Since 2026-09-04 the trigger is agent-sop's user-scope Stop hook, and it works in one step:

1. **When the agent stops:** `sop-stop-drift.sh` (from agent-sop) reads `ship-sop.config.json`, applies the throttle, computes the code diff from the merge-base with the default branch, and checks whether any `docs/reviews/*-ship-auto.md` carries a `Covers: <sha>` line for an ancestor of HEAD with no code change since.
2. **If not covered:** it exits 2 with the list of enabled agents, the range, and the report path. Claude Code feeds that to the model and the turn continues, so the gates run and the report is written before the agent finishes. Nothing is typed and nothing waits for the next session.

Why the previous design was replaced. `scripts/auto-ship-hook.sh` was a project-scope Stop hook that wrote `.ship/.pending-auto-fire.md` and printed a directive to stdout for "the next turn". Two harness facts made that inert: project-scope hooks in `.claude/settings.json` load only from the directory Claude Code was launched in (sessions launched from `~` never register them), and Stop hook stdout is written to the debug log and never shown to the model. The script itself fired correctly when run by hand; the harness never ran it in a real session, and would have discarded its output if it had. The only auto-mode report ever produced was this repo's own dogfood on 2026-04-25. Full account: `docs/agent-memory/gotchas/2026-09-04_solo_stop-stdout-is-discarded-and-project-hooks-need-the-launch-dir.md`.

`scripts/auto-ship-hook.sh` stays in the repo, and `setup.sh` still copies and wires it for now; removing that wiring, the CI guard that asserts it, and the entries already in consumer repos is P25. A leftover project-scope entry is harmless (it writes `.ship/` files nobody reads) — the agent-sop context hook flags a leftover `.ship/.pending-auto-fire.md` so it gets cleaned up.

This means:
- **Auto-mode reviews happen in the same turn** the drift is detected, at the first stop after the code changed.
- **Findings appear inside the model's response.** Gate agents run in the background by default from Claude Code 2.1.198; the hook's reason text tells the model to collect every result before writing the report.
- **The report is the audit trail.** A report that names an ancestor of HEAD with no code change since is what "covered" means; no stamp files are involved.

If you want review output on demand, run `/ship` manually — that invokes the gates in the current turn and, per its own instructions, collects every gate result before reporting a verdict.

### Directive integrity

*Legacy as of 2026-09-04: this section describes the superseded project-scope hook's directive file. The agent-sop Stop hook passes its demand through the hook's exit-2 reason, which no file on disk can edit, so no sidecar is needed. Kept for consumer repos that still carry the old entry.*

`.ship/.pending-auto-fire.md` is persistent state that sits on disk between turns and tells the next model turn what to run. Anything with repo write access can edit it, which makes it the same persistence vector agent-sop's `docs/sop/security.md` rule 1 covers for `CLAUDE.md` and `Backlog.md`.

**The hook writes a `.ship/.pending-auto-fire.sha256` sidecar** and the reader checks it first. Three outcomes, deliberately distinct:

| Result | Meaning | Reader behaviour |
|--------|---------|------------------|
| Match | The file is exactly what the hook wrote | Honour the whole directive |
| Differ | Edited since the hook wrote it | Report, do not run the gates |
| Sidecar missing or `UNAVAILABLE` | No SHA-256 tool on the writing host, or the sidecar was removed | Fall back to the section check; say integrity was unverifiable. **Not** treated as tampering |

That third row matters: conflating "unverifiable" with "tampered" would suppress the gates entirely on any host lacking `shasum`, which is most Linux containers. The hook emits a verification command matching whichever tool it found, rather than hardcoding one.

**Fallback section check.** When the hash cannot be verified, the reader falls back to checking the directive contains only the sections the hook emits. Be clear about the strength of this: the section list ships *inside* the file it describes, so anything that rewrites the directive can rewrite the list too. It stops naive appended prose and nothing more. It is a speed bump, not a control.

**What the hash does and does not buy.** It is tamper *evidence*, not authentication — whatever can rewrite the directive can rewrite the sidecar. It reliably catches a partial write or an edit by something that did not know the sidecar existed.

**It does not detect staleness.** Nothing deletes the directive after it is consumed, so a directive from an earlier run still matches its own sidecar perfectly. Staleness is a separate check: compare the recorded `Diff range` against the current `HEAD`. If the range no longer ends at `HEAD`, the directive describes an older state and should be regenerated rather than gated.

`SHIP_SOP_DEBUG=1` prints the hash the hook wrote and the sidecar path.

### A note on what the hook can see

The Stop hook computes the diff **at stop**, from committed HEAD. Uncommitted work and work still running in background subagents are not in that range, so they are gated at the first stop after they are committed. If you need a specific change gated now, run `/ship` manually rather than relying on the stop hook to have seen it.

## Per-agent toggles

`ship-sop.config.json` controls which agents run. The trigger reads `trigger.mode`, `trigger.throttle.min_diff_lines`, `trigger.throttle.skip_branch_patterns`, and per agent `enabled` and `block_on`; nothing else.

```json
{
  "trigger": { "mode": "auto", "throttle": { "min_diff_lines": 10, "skip_branch_patterns": ["^wip/", "^spike/", "^exp/"] } },
  "agents": {
    "security-reviewer":     { "enabled": true,  "block_on": "CRITICAL" },
    "silent-failure-hunter": { "enabled": true,  "block_on": "HIGH" },
    "code-reviewer":         { "enabled": true,  "block_on": "HIGH" },
    "pr-test-analyzer":      { "enabled": false, "block_on": "never" },
    "compliance-reviewer":   { "enabled": false, "block_on": "CRITICAL" },
    "diagram-builder":       { "enabled": false, "block_on": "never" }
  }
}
```

Disable any gate by flipping `enabled: false`; make one advisory with `block_on: "never"`; add one for a single run with `/ship --with <agent>`. `/ship-on` and `/ship-off` flip the trigger mode without editing the file. Keys from older configs (`skip_docs_only`, `cooldown_seconds`, `auto_file_backlog`, `release.*`, `artifacts.*`) are still accepted by the schema and read by nothing.

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

Auto-mode fires only on **code projects**, and counts only **code lines** (documentation extensions — `.md`, `.markdown`, `.txt`, `.rst` — are always excluded; a rename is classified by both names). The operator's rule since 2026-09-04: ship-sop fires for coding and for nothing else. What counts as a code project is agent-sop's shared rule, `sop-project-type.sh`: an explicit `**Project type:** code|non-code` line in CLAUDE.md wins, otherwise the heuristics in agent-sop's `compliance-checklist.md`. `/ship` and `/ship-on` apply the same rule.

Auto-mode also skips when the diff has fewer than `min_diff_lines` code lines (default 10), when a gate report already names an ancestor of HEAD with no code change since, or when the branch matches a `skip_branch_patterns` entry.

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

One report per ship under `docs/reviews/`, written by the session after every agent has returned:

```
docs/reviews/20260905-100415-ship-auto.md   # first line: Covers: <sha>; one row per agent; findings with dispositions
```

The agent-sop push gate and Stop hook read only the `Covers:` line (an ancestor of HEAD with no code change since). The rest is for people. `diagram-builder`, when enabled, additionally writes under `docs/diagrams/` and appends to `docs/ARCHITECTURE.md`; hand-edited files without its `<!-- generated by diagram-builder -->` marker are never overwritten.

## Compliance scope

`compliance-reviewer` covers PII handling, GDPR, HIPAA-applicability, and data retention.

- **GDPR** — applies by default; disable in `compliance.config.json` with `"gdpr": false`
- **HIPAA** — advisory only; flags when health / medical / clinical data appears in the diff so you can confirm covered-entity status. Does not enforce HIPAA on non-covered projects.
- **CCPA** — off by default; opt in via config
- **Project-specific** — SOC 2, PCI-DSS, etc. configurable in `compliance.config.json`

Not legal advice. A sanity gate, not counsel.

## Composes with agent-sop

[agent-sop](https://github.com/mmjclayton/agent-sop) is the companion library for session discipline (start/end checklists, cross-session memory, parallel multi-agent sessions). The two are independent but pair naturally:

- **agent-sop** manages session lifecycle and curates `Backlog.md`, `docs/agent-memory/`, build plans — and, since 2026-09-04, carries the user-scope Stop hook and push gate that trigger ship-sop's auto-mode
- **ship-sop** defines the gates, the agents, the config schema and the report format, runs them via `/ship`, and auto-files Backlog entries using agent-sop's conventions

If you use both: `compliance-reviewer` files `[OPEN][Bug][needs-triage]` Backlog entries with proper P-numbers; `release-notes-writer` reads `[SHIPPED]` items and Batch Logs as primary sources.

If you use only ship-sop: agents write findings to `docs/reviews/` only; release notes fall back to conventional-commit parsing.

## Composes with doc-updater

If you use Claude Code's reference `doc-updater` agent (or have your own), it stays in its lane:

| Agent | Scope | Trigger |
|-------|-------|---------|
| `doc-updater` | Codemaps, README refresh, module import/export graphs | On-demand: `/update-codemaps`, `/update-docs` |
| `diagram-builder` (this) | Mermaid diagrams, API catalog, ARCHITECTURE Δ log | Auto: every `/ship` |

## Requirements

- Claude Code v2.1.251+ (agent-sop's floor; the Stop hook relies on exit-2 handling and on the 2.1.222 worktree-isolation fix)
- `bash`, `git`, `jq` (auto-mode hook, installed from agent-sop)
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

# Remove the SessionStop hook entry, keeping any other hooks intact.
# Handles both the current nested shape and pre-P14 flat entries.
# The guard matters: without it, a missing settings.json leaves a stray .tmp
# behind, and a settings.json with no ship-sop entry gains an empty
# .hooks.Stop it never had.
if [ -f .claude/settings.json ] && jq -e \
     '([.hooks.Stop[]?.hooks[]?.command] + [.hooks.Stop[]?.command]) | index("scripts/auto-ship-hook.sh")' \
     .claude/settings.json >/dev/null 2>&1; then
  jq '.hooks.Stop = [ .hooks.Stop[]?
        | select((.command? // "") != "scripts/auto-ship-hook.sh")
        | if (has("hooks") and ([.hooks[]?.command] | index("scripts/auto-ship-hook.sh")))
          then (.hooks |= map(select((.command? // "") != "scripts/auto-ship-hook.sh")))
             | select((.hooks | length) > 0)
          else . end ]' \
     .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
fi

# Remove the .gitignore block
awk '/^# ship-sop runtime artifacts$/ { skip=1; next } skip>0 { skip--; next } { print }' .gitignore > .gitignore.tmp && mv .gitignore.tmp .gitignore
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
