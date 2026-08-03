# SessionStart hook is the automation path; /restart-sop is a backstop

**Date:** 2026-08-03
**Agent:** solo

We chose a **SessionStart hook** as ship-sop's primary automatic trigger over hooking the gate pickup into agent-sop's `/restart-sop` command, because a command the operator has to remember to type is not automation.

The operator asked for ship-sop to run automatically, "triggered from the `/restart-sop` command I run for agent-sop ideally, so I don't have to continually invoke a skill". Taken literally that names `/restart-sop`. Taken by intent it names *not typing anything*, and a harness-executed hook satisfies that strictly better — it fires whether or not the command is run.

The binding constraint is unchanged (see `docs/agent-memory/gotchas/2026-04-25_solo_stop-hooks-cant-invoke-agents.md`): hooks cannot invoke `@agent`. So every path is two-step — a hook injects context, a model turn dispatches. The design that follows:

- **Primary:** SessionStop writes the directive; SessionStart verifies integrity and freshness and injects the pointer into the opening context; the model dispatches. Nothing typed.
- **Backstop:** `/restart-sop` performs the same pickup for when it is typed anyway. Both share one idempotent routine keyed on a consumed marker, or a session that starts and is then given `/restart-sop` dispatches six gate agents twice.
- **Enforcement:** a `PreToolUse` hook on `git push` / `gh pr create` is the only surface that can actually refuse. It gates on "no gate run covers `HEAD`" — a deterministic fact a hook can check — rather than on "are there findings", which is a model judgement.
- **Deterministic checks move into the hook.** shellcheck, `jq empty` and a staged-secret scan need no model. Inside the hook they are instant, free, and cannot be reasoned past. Model gates stay for judgement work.

The `/restart-sop` step must ship in the **agent-sop repo**, guarded on `ship-sop.config.json` existing, and arrive here via `/update-agent-sop`. `/restart-sop` is a pristine replica under `CLAUDE.md` rule 8; a downstream edit would be silently reverted by the next sync — the exact bug class P14 existed to remove.

Rejected: patching `~/.claude/commands/restart-sop.md` from ship-sop's `setup.sh`. It would work until the next sync, then fail silently, which is worse than not working at all.

Written up in full in `docs/build-plans/phase-3-automation-and-correctness.md`. Filed as P16.
