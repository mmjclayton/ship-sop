---
name: ship-on
description: Set ship-sop trigger mode to auto while preserving project configuration.
---

Read ship-sop.config.json from the project, else the Codex user config directory.
For ship-on, verify project type is code before changing anything. If no config
exists, create the project config from docs/templates/ship-sop.config.json when
available. Otherwise report the missing installation.
Use jq and a validated temporary file to change only .trigger.mode to "auto";
preserve all other fields and write through an existing symlink. Verify the value.
For auto-mode check that Codex hooks.json has agent-sop Stop and PreToolUse entries
and their scripts exist. Inline hooks in config.toml are also supported by Codex.
If missing, report auto-mode as inactive and repair using agent-sop's
scripts/install-hooks.sh --runtime codex when installation is authorized.
Never register scripts/auto-ship-hook.sh for Codex. Report mode, config path,
active reviewers and whether hooks are actually configured. No release or push.
