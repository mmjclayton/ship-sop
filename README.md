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
- Produces a JSON receipt, checked for completeness and binding to the commit, and a readable report with findings and dispositions.
- Rejects receipts that are blocked, incomplete or written for different code. The session reports reviewer verdicts and test results itself; see [What a receipt proves](#what-a-receipt-proves).
- Retains Codex reviewer usage, timing and timeout diagnostics.
- Provides a whole-repository compliance audit and a separate release workflow.

`ship` does not commit, push or publish. Releases are deliberate actions through
`release`, with support for preparing notes without publishing.

## Quick start

You need Git, Bash, `jq`, and Claude Code or Codex. Codex reviews use an
authenticated Codex CLI; GitHub release publication also needs `gh`.

Install agent-sop first (commit `0a1e5ee` of 24 September 2026 or later), then
ship-sop into the same existing project:

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
`security-reviewer` come from agent-sop. ship-sop does not ship a Claude
`silent-failure-hunter`: when setup creates a new Claude-only config and finds no
`silent-failure-hunter.md` in `~/.claude/agents/` or the project's `.claude/agents/`,
it disables that reviewer and says so. Supply the profile and set `enabled` back
to `true` to use it. Writing that config needs `jq`; without it, setup stops
before writing one.

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
than estimates. Under Codex, `usage` is the sum of the reviewer's run telemetry
produced by `scripts/codex-usage.sh` from the runner's evidence directories, or
null when any run lacked telemetry; under Claude it is null, since the runtime
reports no subagent usage.
Markdown `Covers:` lines
are informational and old Markdown-only reports no longer satisfy the gate.
An ancestor receipt remains usable only when no code or executable instructions changed. Missing or failed reviewer results are incomplete, not a pass.

## What a receipt proves

A receipt that passes validation proves that a complete set of results was
recorded for this commit and its review range, under the current policy, with no
blocking findings. The session gathers reviewer verdicts and test results and
passes them to `scripts/ship-receipt.sh`. Test results are never checked against
a test run.

When `scripts/ship-receipt.sh` writes the receipt, what else it checks depends on
the runtime:

| `--runtime` | Reviewer verdicts checked against | A hand-written `PASS` result file |
|---|---|---|
| `codex` | The runner's record in this repository's `.ship/reviews/`: each reviewer needs a run by `codex-review.sh` on the same commit and base, with a clean exit, no timeout and the same final verdict | Refused by `ship-receipt.sh` unless matching run records are also written by hand |
| `claude` | Nothing; Claude subagents leave no record ship-sop can read | Produces a receipt that passes validation |

The run-record check happens only in `ship-receipt.sh`. agent-sop's Stop and push
gates validate the receipt itself (commit, tree, base, policy, reviewers in scope,
no blocking findings) and do not look at `.ship/reviews/`, so a receipt written
straight into `docs/reviews/` without `ship-receipt.sh` satisfies the gates under
either runtime. The calling session also chooses `--runtime` and can write
`.ship/`. The Codex check makes a false receipt harder to produce through the
supported tool; it does not stop a session that bypasses the tool.

ship-sop is a discipline aid for an agent that follows the workflow, in line with
agent-sop's cooperative hooks. It is not a control against a session that chooses
to skip review. Enforcing review against such a session needs reviewers that run
outside it, for example in CI.

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

ship-sop no longer ships a project-scope hook. Re-running setup on a project
installed before 2026-10-10 removes the old `.claude/settings.json` entry, keeping
any other hooks, and then the old `scripts/auto-ship-hook.sh` unless it was edited
locally. Setup stops first if agent-sop's hook registration is stale, and exits
non-zero if it could not finish the removal. See [Codex runtime details](docs/sop/codex.md).

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

See [project conventions](CLAUDE.md). The fixtures are the `tests/*.sh` scripts;
`tests/receipt-integration.sh` also needs `AGENT_SOP_SOURCE` set to an agent-sop
checkout, and `tests/legacy-hook.sh` needs a full clone.

The [CI workflow](.github/workflows/ci.yml) runs every fixture, checks shell
scripts and JSON, and runs the cross-package test against agent-sop `main` and
against the oldest supported agent-sop. Propose changes through a pull request.

ship-sop is maintained by one person, alongside agent-sop. There is no support
commitment or release schedule; pin a commit if you depend on it.

## Evidence and cost diagnostics

Codex reviews retain events, results and usage under `.ship/reviews/`. Unknown
usage is null, never zero. `SHIP_REVIEW_MODEL` selects an explicit model;
`SHIP_REVIEW_TIMEOUT_SECONDS` bounds a reviewer run (default 600, maximum 3600).
The three-reviewer default is unchanged pending measured defect yield and cost.

`scripts/receipt-totals.sh REPO_ROOT...` totals the receipts in one or more
projects: receipts, gates that blocked at least once, block rounds, reviewer
launches and re-checks, and findings by severity (`--json` for raw output). A
receipt present in several clones counts once. It exits 1 when a file could not
be read or a root has no receipts. It
measures what the gates recorded. It does not show what would have happened
without them; that needs a comparison run.

Receipt generation needs the agent-sop library. `ship-receipt.sh --check-lib`
reports whether the installed library loads and defines every function ship-sop
calls, naming any that is missing and the minimum agent-sop. It checks names, not
behaviour; CI covers behaviour by running the cross-package test at the minimum
agent-sop and at `main`. Setup runs the check.
Upgrade both projects together.
See `docs/build-plans/review-hardening.md` for the contract and evaluation plan.
