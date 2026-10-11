# ship-sop

**Project type:** code

Code review gates for Claude Code and Codex: the review workflow, receipts, and
the user-scope push gate that enforces them. Self-contained; no other repository
is needed to build, test or install it. Project conventions here take precedence
on project details.

## Working rules

- `Backlog.md` is the list of work and its status. Update an item's status tag when its state changes.
- Ask only when the answer would materially change the result; otherwise make the call, state the assumption, and carry on.
- Pushes go through the review gate (ship-sop) where the project has `ship-sop.config.json`.
- Never use the gate's user-only override (see the README) unless the user explicitly instructs it in this session.
- When files disagree, code and git win, then this file, then `Backlog.md`.

## Key Documents & Dispatch

| When you need to... | Start at | Notes |
|---|---|---|
| Understand behaviour | `README.md` | Public contract |
| Locate work | `Backlog.md` | Read the relevant P-number only |
| Change the push gate or its rules | `scripts/hooks/sop-lib.sh`, then `scripts/hooks/sop-push-gate.sh` | Gate, receipt check and `/ship` share the library; fixtures in `tests/push-gate.sh` |
| Change receipt generation | `scripts/ship-receipt.sh` | Validates through the installed `sop-lib.sh` |
| Change Codex execution | `scripts/codex-review.sh` | Independent read-only clones; retains local evidence |
| Change a workflow | `.agents/skills/ship/SKILL.md`, `.claude/commands/ship.md` | Both runtimes share the receipt contract |
| Change installation | `setup.sh`, `scripts/install-hooks.sh`, `scripts/install-codex.sh` | Preserve customisations and self-install protection |
| Change a reviewer agent, a slash command or the receipt tool | `.claude/agents/`, `.codex/agents/`, `.claude/commands/`, `scripts/ship-receipt.sh` | Add the new blob to `scripts/shipped-user-files.txt` |
| Change policy | `docs/templates/ship-sop.config.json` | Validated by `sop_policy_valid` in `sop-lib.sh` |
| Plan or check the gate-value measurement | `docs/build-plans/2026-10-12-gate-value.md` | Live measurement on Edward work |
| Read history from before ship-sop was self-contained | `archive/` | Old session records, agent memory and phase plans; nothing reads them |

## Stack

Bash, jq and Git. Codex reviews require an authenticated Codex CLI. Release
publication requires gh. CI is `.github/workflows/ci.yml`.

## Key Commands

```bash
for t in tests/*.sh; do bash "$t" || echo "FAILED: $t"; done
shellcheck -S warning setup.sh scripts/*.sh scripts/hooks/*.sh tests/*.sh
bash scripts/validate-state-transitions.sh   # before committing a Backlog.md change
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
- Hook registration is not runtime verification. The live trigger is the
  user-scope push gate (`scripts/hooks/sop-push-gate.sh`). Legacy directive files
  and the old project-scope Stop hook are not the live path.
- The push gate may only exit 0 or 2; any other exit is "allow" to Claude Code.
  Keep its fail-closed trap and the suite's exit-code invariant.
- The installed copy under `~/.claude/scripts/hooks/ship-sop/` is what runs, not
  the repository file; re-run setup to test a change end to end.
- Preserve self-install inode/path checks and existing user customisations.

## Change and verification rules

Read the work item and implementation, add a discriminating fixture for behaviour
changes and run the checks above.
The coordinating session owns records; specialists return findings.
Ship via a branch and PR; main is protected. Publication needs user authorisation.
New non-obvious decisions belong in the Backlog item that makes them. Earlier
session records and agent memory are in `archive/` as history and are no longer
written; status is in `Backlog.md`. Feature inventory changes when work merges.
Build plans are planning context.
