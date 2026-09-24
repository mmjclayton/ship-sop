# ship-sop

Code review gates for Claude Code and Codex, with isolated reviewers, validated
review receipts and usage telemetry. Run your project's tests, inspect the
committed change and collect findings with evidence tied to the reviewed code.

[MIT licensed](LICENSE). Companion to
[agent-sop](https://github.com/mmjclayton/agent-sop), which manages session context,
project records and the hooks used for automatic review.

## What it does

- Runs configurable reviewers for correctness, security and silent failures.
- Offers optional test-coverage, compliance and architecture reviews.
- Produces a validated JSON receipt and a readable report with findings and dispositions.
- Rejects blocked, incomplete or stale review evidence.
- Retains Codex reviewer usage, timing and timeout diagnostics.
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

| Reviewer | Enabled | Blocks on | Runs when the diff touches |
|---|---|---|---|
| `security-reviewer` | Yes | CRITICAL | shell, server/auth/route code, HTML templates, env and container files, workflows, SQL |
| `silent-failure-hunter` | Yes | HIGH or CRITICAL | any code |
| `code-reviewer` | Yes | HIGH or CRITICAL | any code |
| `pr-test-analyzer` | No | Advisory | any code |
| `compliance-reviewer` | No | CRITICAL | any code |
| `diagram-builder` | No | Advisory | any code |

Set `enabled` per reviewer and use `block_on: "never"` for advisory findings.
Set `paths` (an array of regular expressions) to scope a reviewer to the files
where it earns its run: with `paths`, the reviewer joins the gate only when a
path changed in the review range matches one of the patterns; without `paths`
it runs on every code diff; an empty array never runs it. The Stop hook demand,
the receipt validator and `ship` read the same rule, so a receipt is complete
when it carries every reviewer in scope for its own range. `ship --with <agent>`
adds a reviewer for one run regardless of scope. The default `paths` on
`security-reviewer` come from the 2026-09-24 gate-yield review (zero blocking
findings in eleven gates on a TypeScript viewer, a CRITICAL on shell scripts);
tune them per project.
See the [default config](docs/templates/ship-sop.config.json) and
[config schema](docs/templates/ship-sop.schema.json) for the full settings.

Reports go in `docs/reviews/<timestamp>-ship-auto.md`. They record tests,
reviewer results and findings. A validated companion `*-ship-auto.json` receipt binds completion, tests and
findings to the commit, tree, review base and policy, and (schema version 2,
since 2026-09-24) records per reviewer how many agents were launched, how many
re-checks ran and how many rounds blocked, so gate cost rests on counts rather
than estimates; a `usage` object is recorded only when the runtime reports one.
Markdown `Covers:` lines
are informational and old Markdown-only reports no longer satisfy the gate.
An ancestor receipt remains usable only when no code or executable instructions changed. Missing or failed reviewer results are incomplete, not a pass.

## Automatic review

Auto-mode uses **agent-sop's user-scope hooks**. When the agent stops with an
uncovered code diff, the Stop hook requests the configured review. The push hook
checks coverage before supported `git push` and `gh pr create` calls.

By default it applies to code projects with at least 10 changed code lines.
Executable instruction changes, including applicable Markdown skills, commands
and policy files, require review even below that threshold. Ordinary prose-only
changes and branches starting with `wip/`, `spike/` or `exp/` are skipped.
Invalid configured policy produces an error. Set `trigger.mode` to `manual` to
disable automatic review.

**Earlier Codex runtime verification:** a fresh-session test completed the automatic cycle:
production Stop continuation, all configured reviewers, a covering report and a
successful push to a local Git remote. See the [runtime test record](docs/reviews/2026-09-08_codex-auto-runtime.md).
That test predates structured receipts. The
[hardening review and verification record](docs/reviews/20260908-hardening-ship-auto.md)
covers the subsequent receipt contract, installation and timeout checks, together
with independent source reviews. These checks do not establish a general quality
or cost advantage over native agent workflows.
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

## Evidence and cost diagnostics

Codex reviews retain events, results and usage under `.ship/reviews/`. Unknown
usage is null, never zero. `SHIP_REVIEW_MODEL` selects an explicit model;
`SHIP_REVIEW_TIMEOUT_SECONDS` bounds a reviewer run (default 600, maximum 3600).
The three-reviewer default is unchanged pending measured defect yield and cost.
Receipt generation needs current Agent SOP hooks. Upgrade both projects together.
See `docs/build-plans/review-hardening.md` for the contract and evaluation plan.
