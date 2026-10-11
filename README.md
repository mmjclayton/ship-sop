# ship-sop

Code review gates for Claude Code and Codex. ship-sop runs your tests and a set
of isolated reviewer agents against the committed change, records the result in
a validated receipt tied to that commit, and can refuse an agent's push until
such a receipt exists.

[MIT licensed](LICENSE).

## What it does

- **Review gate (`ship`).** Runs the project's tests, then the reviewers you
  enable (security, correctness, silent failures, and optionally test coverage,
  compliance and architecture) against the diff from the default branch to
  `HEAD`. Reviewers are read-only and isolated: Claude subagents run in their own
  worktrees, Codex reviewers in independent clones with a read-only sandbox. The
  session collects every result and writes one report.
- **Receipts.** Each run produces a readable report and a JSON receipt that binds
  the reviewer verdicts, findings and test result to the commit, tree, review base
  and policy. A receipt that is blocked, incomplete or written for different code
  is rejected.
- **Push gate.** A user-scope `PreToolUse` hook refuses the agent's `git push` and
  `gh pr create` in an auto-mode project until a valid receipt covers `HEAD`. It
  ignores prose-only changes and non-code projects, and fails closed on internal
  errors.
- **Audit and release.** A whole-repository compliance audit (`audit`) and a
  deliberate release workflow (`release`) that can prepare notes without
  publishing. `ship` itself never commits, pushes or publishes.

In a blind sample of 29 blocking findings from one project, both graders rated 14
as real defects and 2 as false positives; see the
[P40 report](docs/benchmark/p40/report.md) for the method and its limits.

## Who it is for

Developers who let Claude Code or Codex write and push code and want a
consistent review step before that code leaves the machine, with a record of what
was reviewed. It is a discipline aid for an agent that follows the workflow. It is
not a control against a session that sets out to skip review; that needs reviewers
that run outside the session, for example in CI.

## Quick start

You need Git, Bash and `jq`, plus Claude Code or Codex. Codex reviews use an
authenticated Codex CLI; publishing a GitHub release also needs `gh`.

```bash
git clone https://github.com/mmjclayton/ship-sop.git
bash ship-sop/setup.sh /path/to/project --runtime claude   # or codex, or both
```

Claude is the default runtime. Restart your agent session after installing and
complete any hook trust review it asks for. Then, in the project:

| Task | Claude Code | Codex |
|---|---|---|
| Review the committed code diff | `/ship` | `$ship` |
| Turn automatic review on (the default) | `/ship-on` | `$ship-on` |
| Switch to manual review | `/ship-off` | `$ship-off` |
| Audit the whole repository for compliance issues | `/audit` | `$audit` |
| Prepare or publish a release | `/release` | `$release` |

Use `ship --base <ref>` to choose a diff base, or `ship --with <agent>` to add a
reviewer for one run. The review range ends at committed `HEAD`; uncommitted
changes are not covered.

## What setup changes

| Where | What | Runtime |
|---|---|---|
| `~/.claude/agents/` | `security-reviewer`, `code-reviewer`, `compliance-reviewer`, `diagram-builder`, `release-notes-writer` | Claude |
| `~/.claude/commands/` | `ship`, `ship-on`, `ship-off`, `audit`, `release` | Claude |
| `~/.agents/skills/`, `$CODEX_HOME/agents/` | The same workflows as skills, and the reviewer profiles | Codex |
| `~/.claude/scripts/hooks/ship-sop/` (Codex: `$CODEX_HOME/scripts/hooks/ship-sop/`) | The push gate and its library | Both |
| `~/.claude/settings.json` (Codex: `$CODEX_HOME/hooks.json`) | One `PreToolUse` entry for the push gate; other hooks are kept and the file is backed up first | Both |
| `~/.claude/scripts/ship-sop/`, `$CODEX_HOME/scripts/ship-sop/` | The receipt tool and, for Codex, the reviewer runner | Both |
| The project | `ship-sop.config.json`, `docs/templates/ship-sop.schema.json`, `docs/reviews/`, and `.ship/` added to `.gitignore` | Both |

Re-running setup from an updated checkout updates installed files that you have
not edited and keeps the ones you have, naming each one it keeps. `--force`
replaces edited files too. An existing `ship-sop.config.json` is never rewritten.

- `--no-hook` installs everything except the push-gate registration, for manual
  review only. A new Codex config is then created in manual mode.
- For Claude, ship-sop does not ship a `silent-failure-hunter` profile. If setup
  creates a new Claude-only config and finds none in `~/.claude/agents/` or the
  project's `.claude/agents/`, it disables that reviewer and says so.
- Setup moves a push gate installed by an earlier version to the ship-sop path,
  and removes the retired project-scope `scripts/auto-ship-hook.sh` and its
  settings entry. Edited copies are kept.

### Removing it

```bash
bash ship-sop/setup.sh /path/to/project --runtime claude --uninstall
bash ship-sop/setup.sh /path/to/project --runtime codex --uninstall
```

Uninstall removes the push-gate registration and scripts, the agents, commands
or skills you have not edited, and (Claude) the project config and `.ship/`. Add
`--keep-config` and `--keep-artifacts` to keep those, or `--force` to remove
edited files as well. Review history in `docs/reviews/` is never removed.
User-scope files are shared by every project on the machine, so removing them
affects all of them. To stop automatic review in one project only, run
`/ship-off` there instead.

## Configuration

Edit `ship-sop.config.json` in the project. The defaults:

| Reviewer | Enabled | Blocks on | Runs when the diff touches |
|---|---|---|---|
| `security-reviewer` | Yes | CRITICAL | shell, server/auth/route code, HTML templates, env and container files, workflows, SQL |
| `silent-failure-hunter` | Yes | HIGH or CRITICAL | any code |
| `code-reviewer` | Yes | HIGH or CRITICAL | any code |
| `pr-test-analyzer` | No | Advisory | any code |
| `compliance-reviewer` | No | CRITICAL | any code |
| `diagram-builder` | No | Advisory | any code |

- `enabled` and `block_on` set each reviewer; `block_on: "never"` makes it advisory.
- `paths` (an array of regular expressions) scopes a reviewer: it joins only when
  a changed path matches. Without `paths` it runs on every code diff; an empty
  array never runs it. The push gate, the receipt check and `ship` read the same
  rule.
- `trigger.mode` is `auto` (push gate active), `manual` or `off`.
- `trigger.throttle.min_diff_lines` (default 10) and `skip_branch_patterns`
  (default `^wip/`, `^spike/`, `^exp/`) decide when the push gate applies.
  Documentation-only changes never trigger it; changes to executable instructions
  (skills, commands, agent profiles, `AGENTS.md`, `CLAUDE.md`) always do.
- The gate applies to code projects only. Declare `**Project type:** code` (or
  `non-code`) in `AGENTS.md` or `CLAUDE.md` to override the detection, which
  otherwise looks for a manifest such as `package.json` or a test command.

See the [default config](docs/templates/ship-sop.config.json) and the
[schema](docs/templates/ship-sop.schema.json) for every setting.

To bypass the gate once, put `SOP_SKIP_GATE=1` directly before the push, for
example `SOP_SKIP_GATE=1 git push`. Each bypass is logged to `.ship/bypass.log`.

### Reports and receipts

Reports go in `docs/reviews/<timestamp>-ship-auto.md`, with a companion
`*-ship-auto.json` receipt written by `scripts/ship-receipt.sh`. The receipt
records each reviewer's verdict, findings, launches, re-checks and blocking rounds,
and, under Codex, token usage from the runner's telemetry (null when unknown,
never zero). A receipt for an earlier commit still covers `HEAD` when only
documentation has changed since.

A valid receipt proves that a complete set of results was recorded for that
commit and range, under the current policy, with no blocking findings. Test
results are reported by the session and are not re-run. Under Codex,
`ship-receipt.sh` also checks each verdict against the runner's own record in
`.ship/reviews/`; Claude subagents leave no such record. The push gate checks the
receipt, not the run records.

`scripts/receipt-totals.sh REPO_ROOT...` totals receipts across projects: gates,
blocking rounds, reviewer launches and findings by severity (`--json` for raw
output). `SHIP_REVIEW_MODEL` selects the Codex reviewer model and
`SHIP_REVIEW_TIMEOUT_SECONDS` bounds a reviewer run (default 600, maximum 3600).

## Optional: working rules for your project

These four rules suit a project that uses ship-sop. Paste them into the project's
`CLAUDE.md` or `AGENTS.md` if you want them:

```markdown
## Working rules

- `Backlog.md` is the list of work and its status; update an item's status tag when its state changes.
- Ask only when the answer would materially change the result; otherwise make the call, state the assumption, and carry on.
- Pushes go through the review gate (ship-sop) where the project has `ship-sop.config.json`.
- When files disagree, code and git win, then this file, then `Backlog.md`.
```

`scripts/validate-state-transitions.sh` checks `Backlog.md` status changes against
those tags, and `scripts/archive-backlog.sh` moves old closed items to
`docs/backlog-archive.md`.

## Contributing

See [project conventions](CLAUDE.md). The fixtures are the `tests/*.sh` scripts;
`tests/legacy-hook.sh` and `tests/install-agents.sh` need a full clone. Run them
all with:

```bash
for t in tests/*.sh; do bash "$t" || echo "FAILED: $t"; done
shellcheck -S warning setup.sh scripts/*.sh scripts/hooks/*.sh tests/*.sh
```

The [CI workflow](.github/workflows/ci.yml) runs every fixture and checks the
shell scripts and JSON. Propose changes through a pull request. When you change a
reviewer agent in `.claude/agents/`, add its new blob to
`scripts/shipped-agents.txt` so installed copies of it keep updating.

ship-sop is maintained by one person. There is no support commitment or release
schedule; pin a commit if you depend on it.
