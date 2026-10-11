---
description: Disable ship-sop auto-mode. Sets trigger.mode to "manual" so the ship-sop push gate (`sop-push-gate.sh`, user-scope) stops demanding a review. /ship and /release continue to work manually.
ship_sop_version: "2026-04-25"
---

Flip ship-sop auto-mode off. The push gate stays wired but lets pushes through — it reads the config, sees `trigger.mode: "manual"`, and exits silently. Manual `/ship` and `/release` continue to work.

## Workflow

1. Locate `ship-sop.config.json` (project-level preferred; user-global fallback).
2. If absent, surface: "No config found — auto-mode wasn't on." Exit.
3. Set `.trigger.mode = "manual"` (use `"off"` instead if the operator wants the gate config preserved but the hook never to run again — ask if intent is unclear).
4. Confirm in chat:

```
ship-sop auto-mode: OFF
Config: <path>
Hook: still wired (no-op until /ship-on)
Manual entrypoints: /ship, /release
```

## When to use which mode

| Mode | Behaviour |
|------|-----------|
| `auto` | The push gate refuses a push or PR until the configured gates have reviewed HEAD |
| `manual` | Hook runs but exits early; `/ship` and `/release` work as normal |
| `off` | Hook exits even earlier; equivalent to manual but signals "I want this fully disabled" |

Use `manual` for short-term pauses (debugging, exploration sessions). Use `off` if you want the install present but truly inert — typically while testing the pipeline itself, or on projects where you've decided not to adopt it.

## Idempotent

Re-running `/ship-off` when already off is a no-op with a confirmation message.

## Side effects

- Modifies `ship-sop.config.json` (one field).
- Does not unwire the hook from `.claude/settings.json`. Run `setup.sh <project> --uninstall` to remove the gate and its registration entirely.
