# ship-sop

**Project type:** code

Code review execution and evidence for Claude Code and Codex. Agent SOP owns
session context and the lifecycle hooks; ship-sop owns the review workflow.
Shared session start/end: `docs/sop/claude-agent-sop.md`. Runtime bindings:
`docs/sop/codex.md`. Project conventions here take precedence on project details.

## Key Documents & Dispatch

| When you need to... | Start at | Notes |
|---|---|---|
| Understand behaviour | `README.md` | Public contract |
| Locate work | `Backlog.md` | Read the relevant P-number only |
| Change receipt generation | `scripts/ship-receipt.sh` | Validates through installed Agent SOP policy |
| Change Codex execution | `scripts/codex-review.sh` | Independent read-only clones; retains local evidence |
| Change a workflow | `.agents/skills/ship/SKILL.md`, `.claude/commands/ship.md` | Both runtimes share the receipt contract |
| Change installation | `setup.sh`, `scripts/install-codex.sh` | Preserve customisations and self-install protection |
| Change policy | `docs/templates/ship-sop.config.json` | Shared validation is upstream in Agent SOP |
| Recover project knowledge | `docs/agent-memory/` | Relevant decisions, gotchas and handoffs |
| Review current architecture work | `docs/build-plans/review-hardening.md` | Older phase plans are historical |

## Stack

Bash, jq and Git. Codex reviews require an authenticated Codex CLI. Release
publication requires gh. CI is `.github/workflows/ci.yml`.

## Key Commands

```bash
bash tests/codex-install.sh
shellcheck -S warning setup.sh scripts/auto-ship-hook.sh scripts/{install-codex,setup-codex,codex-review,ship-receipt}.sh tests/codex-install.sh
bash setup.sh /path/to/project --runtime codex
```

## Backlog Management

`Backlog.md` owns work-item state. Status precedes type. Never delete an item;
close it with a reason. `[SHIPPED]` requires merge to main, `[VERIFIED]` requires
confirmation where it runs. A branch awaiting merge remains `[IN PROGRESS]`.

## Common Mistakes

- A Markdown `Covers:` line does not establish coverage. A complete, valid JSON
  receipt is required. BLOCK and INCOMPLETE results cannot produce one.
- Review committed HEAD. After a code or executable-instruction fix, review again;
  do not relabel old evidence with the new SHA.
- Use the trusted installed runner. A worktree path in a prompt is not isolation.
- Hook registration is not runtime verification. The current trigger is Agent
  SOP's user-scope Stop/push hooks. Legacy directive files are not the live path.
- Preserve self-install inode/path checks and existing user customisations.

## Change and verification rules

Read the work item and implementation, add a discriminating fixture for behaviour
changes, run the checks above, and follow the shared session-close workflow once.
The coordinating session owns records; specialists return findings.
Ship via a branch and PR; main is protected. Publication needs user authorisation.
Do not edit upstream Agent SOP replicas directly: fix them in agent-sop and sync.
New non-obvious decisions belong in `docs/agent-memory/`; session records in
`docs/recent-work/`. Feature inventory changes when work merges. Build plans are
planning context, not a second mandatory session log.
