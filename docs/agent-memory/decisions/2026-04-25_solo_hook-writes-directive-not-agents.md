---
date: 2026-04-25
agent_id: solo
title: SessionStop hook writes a directive file; next-turn model runs the gates
---

# SessionStop hook writes a directive file; next-turn model runs the gates

## Decision

`scripts/auto-ship-hook.sh` is a plain bash script. It does **not** invoke `@compliance-reviewer`, `@diagram-builder`, etc. Instead, it writes `.ship/.pending-auto-fire.md` listing the gates to run, and the *next-turn model* in the project reads the directive and runs them.

## Why

Claude Code's SessionStop hooks execute as shell scripts at the OS level. They cannot directly invoke `@agent` calls — that requires a model turn (the agent registry only exists in the context of a Claude Code session).

The only way to "run agents on session-end" is two-part:
1. **At session-stop:** the hook writes a directive and pipes a context message to stdout. Claude Code injects that stdout into the *next turn's* context window.
2. **On the next user turn:** the model sees the directive in context, reads the directive file, and runs the agents itself.

This is a one-turn lag, not a one-session lag. The user finishes a session → hook fires silently → next time they prompt the model in the same project, the model picks up the directive and runs the gates before responding to the prompt.

## Consequences

- **Auto-mode reviews are not instantaneous.** Findings appear inside the model's response on the next turn, not as a separate notification at session-end.
- **The directive file is the audit trail of what the hook scheduled.** Inspect `.ship/.pending-auto-fire.md` if behaviour seems unexpected.
- **For immediate review output, use `/ship` manually** — that runs the gates in the current turn, not the next one.

## Alternatives considered

- **Hook spawns a Claude Code subprocess in headless mode to run the gates.** Rejected: heavy, requires Claude Code to be on $PATH, doubles token cost, breaks the hook's "fast and silent" property. The directive pattern keeps the hook minimal and lets the existing session do the work.
- **Hook writes findings directly via static analysis tools.** Rejected: ship-sop's gates are reviewer-agent driven (LLM judgment), not static-rule driven. A bash script can't substitute for an agent's compliance reasoning.

## Caveat

This means the hook can't "block ship" in the strict sense — a CRITICAL finding becomes a strong warning in the next-turn context, not a halt. That's why ship-sop has two modes: auto (warns) and manual `/ship` (halts). The split was deliberate, not a workaround for the directive pattern.
