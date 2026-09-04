---
description: Enable ship-sop auto-mode. Sets trigger.mode to "auto" in ship-sop.config.json so the agent-sop Stop hook (`sop-stop-drift.sh`, user-scope) runs the configured gates after each session.
ship_sop_version: "2026-04-25"
---

Flip ship-sop auto-mode on. With auto-mode enabled, the agent-sop Stop hook (`sop-stop-drift.sh`, user-scope) runs the configured gates after each Claude Code session, against the diff vs. the default branch. The default set is six: `security-reviewer`, `compliance-reviewer`, `code-reviewer`, `silent-failure-hunter`, `pr-test-analyzer`, `diagram-builder`. Read the actual list from `ship-sop.config.json` rather than repeating it from here.

## Workflow

1. Locate `ship-sop.config.json`:
   - Project-level (`./ship-sop.config.json`) — preferred.
   - User-global (`~/.claude/ship-sop.config.json`) — fallback if no project-level config exists.
2. If neither exists, prompt the operator: "No ship-sop.config.json found. Create at <project> | <user-global>?" Use the project-level template at `~/Projects/ship-sop/docs/templates/ship-sop.config.json` (or pull from the installed location).
3. Set `.trigger.mode = "auto"`.
4. Verify the agent-sop Stop hook (`sop-stop-drift.sh`, user-scope) is wired in `.claude/settings.json`. Read-only check — this command never writes to that file:

```bash
jq -e '[.hooks.Stop[]?.hooks[]?.command] | index("scripts/auto-ship-hook.sh")' .claude/settings.json >/dev/null 2>&1 \
  && echo "hook: wired" || echo "hook: needs-install"
```

If it reports `needs-install`, tell the operator to run `setup.sh /path/to/project` from the ship-sop repo. Do not offer a hand-rolled `jq` edit: `setup.sh` merges idempotently, migrates pre-P14 flat entries, preserves other hooks in the same array, and asserts the result is parseable. A one-liner does none of that — the version that used to live here replaced `.hooks.Stop` wholesale (destroying any other Stop hook) and wrote a 0-byte `settings.json` when the file was absent.

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
