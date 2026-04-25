---
date: 2026-04-25
agent_id: solo
title: Agent registry is locked at session start; new installs only work next session
---

# Agent registry is locked at session start; new installs only work next session

## What

When Claude Code starts a session, it loads the list of available agents from `~/.claude/agents/` and `<project>/.claude/agents/`. That list is **fixed for the duration of the session**. If you install a new agent file mid-session (e.g., by running `setup.sh`), the model in the current session cannot invoke it via the `Agent` tool — the new agent is not in the registry.

The agent will be available in the *next* session, when Claude Code re-reads the directories.

## How it bit ship-sop

During the build session for ship-sop:
1. We wrote `compliance-reviewer.md`, `diagram-builder.md`, `release-notes-writer.md` to `.claude/agents/`.
2. We ran `setup.sh` which copied them to `~/.claude/agents/`.
3. We then dogfooded by running the auto-ship-hook and trying to invoke `@compliance-reviewer` etc. as the "next-turn model."
4. The Agent tool's `subagent_type` parameter only listed agents that were known at session start. The new ones were not callable.

We worked around it by executing the gates inline (model reads the agent's prompt + applies its checklist directly). That's a faithful simulation of what the actual next-session model would do, but not via the Agent tool.

## How to spot the trap

- "I just installed an agent, but `@<agent-name>` doesn't work in my Agent tool calls."
- "The directive lists `@compliance-reviewer` but invoking it errors out."

## Fix

End the current session. Start a new one. The new agents will appear in the registry. This is the same constraint that informed the directive pattern — the hook can't itself run agents because there's no model context, and even if there were, the new agents wouldn't be in the registry mid-session.

## Implication for development

When iterating on ship-sop's agents:
- Edit the `.md` files freely in the current session.
- To **test** the agent, end the session and start a new one in the target project.
- The dogfood demo I ran in the build session was inline-execution; the real demo (running gates via the Agent tool) requires a fresh session.
