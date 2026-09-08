# ship-sop

Code review gates for Claude Code and Codex. Run your project's tests, ask the
configured reviewers to inspect a change, and collect their findings in one report
before you merge.

[MIT licensed](LICENSE). Companion to
[agent-sop](https://github.com/mmjclayton/agent-sop), which manages session context,
project records and the hooks used for automatic review.

## What it does

- Runs configurable reviewers for correctness, security and silent failures.
- Offers optional test-coverage, compliance and architecture reviews.
- Writes a report with the reviewed commit, findings and their disposition.
- Provides a whole-repository compliance audit and a separate release workflow.

`ship` does not commit, push or publish. Releases are deliberate actions through
`release`, with support for preparing notes without publishing.

## Quick start

You need Git, Bash, `jq`, and Claude Code or Codex. Codex reviews use an
authenticated Codex CLI; GitHub release publication also needs `gh`.

Install agent-sop first, then ship-sop into the same existing project:

```bash
git clone https://github.com/mmjclayton/agent-sop.git
git clone https://github.com/mmjclayton/ship-sop.git

bash agent-sop/setup.sh /path/to/project --runtime codex --code
bash ship-sop/setup.sh /path/to/project --runtime codex

codex -C /path/to/project
```

Use `--runtime claude` for Claude Code or `--runtime both` for both integrations.
Claude is the default when the flag is omitted. Restart your agent session after
installation and complete any hook trust review it requests.

For manual-only Codex setup, add `--no-hook` to ship-sop's setup command. This
creates a new project config in manual mode; it does not reset an existing config.

Codex installs include the default reviewers. For Claude, `code-reviewer` and
`security-reviewer` come from agent-sop; supply a `silent-failure-hunter` profile
in `~/.claude/agents/` or disable that reviewer in the project config.

## Everyday use

Type these in your agent session:

| Task | Claude Code | Codex |
|---|---|---|
| Review the committed code diff | `/ship` | `$ship` |
| Audit the whole repository for compliance issues | `/audit` | `$audit` |
| Enable automatic review | `/ship-on` | `$ship-on` |
| Switch to manual review | `/ship-off` | `$ship-off` |
| Prepare or publish a release | `/release` | `$release` |

Use `ship --base <ref>` to choose a diff base, or `ship --with <agent>` to include
an optional reviewer. Use the `/` or `$` prefix for your runtime.

The review range ends at committed `HEAD`. Uncommitted changes are not covered by
a report for that commit. Codex reviewers run in independent clones with a
read-only sandbox; the parent session collects the results and writes the report.

## Configuration and reports

Edit `ship-sop.config.json` in your project. The defaults are:

| Reviewer | Enabled | Blocks on |
|---|---|---|
| `security-reviewer` | Yes | CRITICAL |
| `silent-failure-hunter` | Yes | HIGH or CRITICAL |
| `code-reviewer` | Yes | HIGH or CRITICAL |
| `pr-test-analyzer` | No | Advisory |
| `compliance-reviewer` | No | CRITICAL |
| `diagram-builder` | No | Advisory |

Set `enabled` per reviewer and use `block_on: "never"` for advisory findings.
See the [default config](docs/templates/ship-sop.config.json) and
[config schema](docs/templates/ship-sop.schema.json) for the full settings.

Reports go in `docs/reviews/<timestamp>-ship-auto.md`. They record tests,
reviewer results and findings. A `Covers: <commit>` line identifies the reviewed
commit; the automatic gate also accepts a covered ancestor when no code has
changed since. Missing or failed reviewer results are incomplete, not a pass.

## Automatic review

Auto-mode uses **agent-sop's user-scope hooks**. When the agent stops with an
uncovered code diff, the Stop hook requests the configured review. The push hook
checks coverage before supported `git push` and `gh pr create` calls.

By default it applies to code projects with at least 10 changed code lines.
Documentation-only changes and branches starting with `wip/`, `spike/` or `exp/`
are skipped. Set `trigger.mode` to `manual` to disable automatic review.

**Codex verification:** a fresh-session test completed the full automatic cycle:
production Stop continuation, all configured reviewers, a covering report and a
successful push to a local Git remote. See the [runtime test record](docs/reviews/2026-09-08_codex-auto-runtime.md).
Start Codex in the project root; other installations still need working, trusted hooks.

The legacy `scripts/auto-ship-hook.sh` is retained for older Claude installs.
Codex does not use it; its debug output is not a test of the current automatic
review path. See [Codex runtime details](docs/sop/codex.md).

## Updates and removal

Re-run setup from an updated checkout. Existing project configuration is retained;
Codex preserves customized skill and reviewer files. `--force` replaces distributed
assets, including locally edited ones, so review those changes first.

To remove the Codex integration, run from the ship-sop checkout:

```bash
bash setup.sh /path/to/project --runtime codex --uninstall
```

This preserves project instructions, configuration, review history and shared
agent-sop hooks. Set the project's trigger mode to `manual` if you also want to
stop automatic review requests. User-scope skill removal affects all projects.

Claude removal uses `--runtime claude --uninstall`; add `--keep-config` and
`--keep-artifacts` to retain configuration and runtime files. Review history is
preserved. Shared agent-sop files are maintained through `update-agent-sop`.

## Contributing

See [project conventions](CLAUDE.md). Run the Codex fixtures with:

```bash
bash tests/codex-install.sh
```

The [CI workflow](.github/workflows/ci.yml) also checks shell scripts and JSON.
Propose changes through a pull request.
