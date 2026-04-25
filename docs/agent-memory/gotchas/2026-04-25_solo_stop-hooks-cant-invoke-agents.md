---
date: 2026-04-25
agent_id: solo
title: SessionStop hooks cannot invoke @agent calls
---

# SessionStop hooks cannot invoke @agent calls

## What

Claude Code's SessionStop hooks run as plain shell scripts at the OS level. They cannot directly invoke `@compliance-reviewer`, `@diagram-builder`, or any other `@agent` — those calls require a model turn (the agent registry only exists in the context of a Claude Code session, not in a shell-script subprocess).

If you're tempted to "make the hook smarter" by having it invoke agents, stop. It can't.

## Why this matters

The whole architecture of ship-sop's auto-mode is shaped by this constraint:
1. The hook script writes a directive file (`.ship/.pending-auto-fire.md`) listing which gates to run.
2. The hook pipes a context message to stdout (Claude Code injects it into the *next turn's* context).
3. The next user turn: the model sees the directive, reads the file, and runs `@agent` calls itself.

This produces a one-turn lag between session-end and review output, which is the right trade-off but only obvious once you understand why.

## How to spot the trap

Symptoms that someone forgot this constraint:
- A hook script that calls `claude` or `claude-code` as a subprocess to invoke agents (heavy, doubles tokens)
- A hook script that tries to `exec` an agent definition file
- A "why didn't the agents run at session-end?" bug report — the answer is "they ran on the next turn; check `.ship/.pending-auto-fire.md` to see what was scheduled"

## Fix

Don't fight the constraint. The directive pattern is the correct shape. If you want immediate review output, use `/ship` manually — that runs in the current turn.

## Related

See `docs/agent-memory/decisions/2026-04-25_solo_hook-writes-directive-not-agents.md` for the full reasoning.
