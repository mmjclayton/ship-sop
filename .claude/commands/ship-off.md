---
description: Disable ship-sop auto-mode. Sets trigger.mode to "manual" so the SessionStop hook becomes a no-op. /ship and /release continue to work manually.
ship_sop_version: "2026-04-25"
---

Flip ship-sop auto-mode off. The SessionStop hook stays wired but becomes a no-op — it reads the config, sees `trigger.mode: "manual"`, and exits silently. Manual `/ship` and `/release` continue to work.

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
| `auto` | SessionStop hook fires the configured gates against the diff |
| `manual` | Hook runs but exits early; `/ship` and `/release` work as normal |
| `off` | Hook exits even earlier; equivalent to manual but signals "I want this fully disabled" |

Use `manual` for short-term pauses (debugging, exploration sessions). Use `off` if you want the install present but truly inert — typically while testing the pipeline itself, or on projects where you've decided not to adopt it.

## Idempotent

Re-running `/ship-off` when already off is a no-op with a confirmation message.

## Side effects

- Modifies `ship-sop.config.json` (one field).
- Does not unwire the hook from `.claude/settings.json`. Run setup.sh with `--uninstall-hook` to remove the wiring entirely.
