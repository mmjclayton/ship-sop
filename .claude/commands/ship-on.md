---
description: Enable ship-sop auto-mode. Sets trigger.mode to "auto" in ship-sop.config.json so the SessionStop hook runs the configured gates after each session.
ship_sop_version: "2026-04-25"
---

Flip ship-sop auto-mode on. With auto-mode enabled, the SessionStop hook runs the configured gates (security, compliance, doc-builder by default) after each Claude Code session, against the diff vs. the default branch.

## Workflow

1. Locate `ship-sop.config.json`:
   - Project-level (`./ship-sop.config.json`) — preferred.
   - User-global (`~/.claude/ship-sop.config.json`) — fallback if no project-level config exists.
2. If neither exists, prompt the operator: "No ship-sop.config.json found. Create at <project> | <user-global>?" Use the project-level template at `~/Projects/ship-sop/docs/templates/ship-sop.config.json` (or pull from the installed location).
3. Set `.trigger.mode = "auto"`.
4. Verify the SessionStop hook is wired in `.claude/settings.json`. If absent, surface the install command:

```bash
# Project-level hook (recommended)
mkdir -p .claude
jq '.hooks.Stop = [{"command": "scripts/auto-ship-hook.sh"}] // .hooks.Stop' .claude/settings.json > .claude/settings.json.tmp
mv .claude/settings.json.tmp .claude/settings.json
```

Or instruct the operator to re-run `setup.sh` from the ship-sop repo.

5. Confirm in chat:

```
ship-sop auto-mode: ON
Config: <path>
Hook: <wired | needs-install>
Active gates: <list of agents with enabled: true>
```

If the hook is not wired, the gate plan is dormant — surface this clearly.

## Idempotent

Re-running `/ship-on` when already on is a no-op with a confirmation message. No error.

## Side effects

- Modifies `ship-sop.config.json` (one field).
- Does **not** modify `.claude/settings.json` automatically — the operator does that via `setup.sh` or a manual edit, with consent. This is deliberate: auto-injecting into settings.json without consent surprises operators.

## Inverse

`/ship-off` flips the same field to `"manual"`, leaving the hook wired but inactive.
