# A flat hook entry in settings.json is discarded without any error

**Date:** 2026-08-03
**Agent:** solo

**The surprise.** `.claude/settings.json` containing `{"hooks":{"Stop":[{"command":"scripts/auto-ship-hook.sh"}]}}` parses cleanly, lists the right command, and the hook never runs. Claude Code requires each entry to nest its command:

```json
{"matcher": "*", "hooks": [{"type": "command", "command": "scripts/auto-ship-hook.sh"}]}
```

The flat form is silently dropped. No warning at session start, no stderr, nothing in the transcript.

**The misleading prior expectation.** That a settings file which is valid JSON and names the command is therefore wired. Every check ship-sop had — the installer's idempotency probe, the uninstall probe, `/ship-on`'s "hook: wired" report — asked "is this command mentioned under `.hooks.Stop`?", which the broken shape answers yes to. So the tooling agreed the hook was installed for three months while it had never once executed.

Compounding it, `README.md`'s troubleshooting section pre-explains silence as a normal throttle outcome ("the hook exits silently on every throttle path…"), so the natural diagnosis of "nothing happened" was a throttle, not a dead wire.

**The rule.** Never assert a hook is wired by searching for its command string. Assert against the shape the harness actually executes:

```bash
jq -e '[.hooks.Stop[]?.hooks[]?.command] | index("scripts/auto-ship-hook.sh")' .claude/settings.json
```

That expression only matches through a nested `hooks` array, so a flat entry fails it. It is now the shared `HOOK_NESTED_PROBE` in `setup.sh`, the post-install assertion, and a CI job that fails the build if the wired entry ever goes flat again.

Generalised: when a config format has a shape requirement the parser enforces by *ignoring* non-conforming entries, a presence check is not a wiring check. Test the effect, not the text. The strongest evidence here was empirical, not schema-derived — every other working hook on the machine used the nested shape, and in `hst-tracker` the dead ship-sop entry sat in the same `Stop` array as a correctly-shaped prettier hook that ran fine.

Shipped as P14. See `docs/recent-work/2026-08-03_solo_full-review-and-p14-hook-wiring.md`.
