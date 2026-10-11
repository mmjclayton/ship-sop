---
description: Enable ship-sop auto-mode. Sets trigger.mode to "auto" in ship-sop.config.json so the agent-sop push gate (`sop-push-gate.sh`, user-scope PreToolUse hook) refuses a push or PR until the configured gates have reviewed HEAD.
ship_sop_version: "2026-04-25"
---

Flip ship-sop auto-mode on. With auto-mode enabled, the agent-sop push gate (`sop-push-gate.sh`, user-scope PreToolUse hook) refuses the agent's `git push` and `gh pr create` until a validated `/ship` receipt covers HEAD, reviewing the diff vs. the default branch. The template default (P27) enables three: `security-reviewer`, `silent-failure-hunter`, `code-reviewer`; `compliance-reviewer`, `pr-test-analyzer` and `diagram-builder` ship disabled and are added per run with `/ship --with <agent>` or per project by flipping `enabled`. Read the actual list from `ship-sop.config.json` rather than repeating it from here.

## Workflow

0. Check the project type: `bash ~/.claude/scripts/hooks/agent-sop/sop-project-type.sh`. If it prints `non-code`, stop: "ship-sop's automatic gate fires only on code projects; auto-mode would be inert here. Declare `**Project type:** code` in CLAUDE.md first if this repository's scripts should be reviewed." Do not write the config.
1. Locate `ship-sop.config.json`:
   - Project-level (`./ship-sop.config.json`) — preferred.
   - User-global (`~/.claude/ship-sop.config.json`) — fallback if no project-level config exists.
2. If neither exists, prompt the operator: "No ship-sop.config.json found. Create at <project> | <user-global>?" Use the project-level template at `~/Projects/ship-sop/docs/templates/ship-sop.config.json` (or pull from the installed location).
3. Set `.trigger.mode = "auto"`.
4. Verify the agent-sop push gate (`sop-push-gate.sh`, user-scope) is registered in `~/.claude/settings.json`. Read-only check — this command never writes to that file:

```bash
jq -e '[.hooks.PreToolUse[]?.hooks[]?.command | select(test("sop-push-gate"))] | length > 0' ~/.claude/settings.json >/dev/null 2>&1 \
  && echo "hook: wired" || echo "hook: needs-install"
```

If it reports `needs-install`, tell the operator to run `bash scripts/install-hooks.sh` from the agent-sop checkout (or agent-sop's `setup.sh`). Do not offer a hand-rolled `jq` edit: `setup.sh` merges idempotently, migrates pre-P14 flat entries, preserves other hooks in the same array, and asserts the result is parseable. A one-liner does none of that — the version that used to live here replaced a whole hooks array (destroying other hooks) and wrote a 0-byte `settings.json` when the file was absent.

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
