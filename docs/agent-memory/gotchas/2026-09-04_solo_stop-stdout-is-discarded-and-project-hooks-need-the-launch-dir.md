# Stop hook stdout is discarded, and project-scope hooks need the launch directory

**Date:** 2026-09-04
**Agent:** solo

**The surprise.** `scripts/auto-ship-hook.sh` was correct. Run by hand with `SHIP_SOP_DEBUG=1` inside a throwaway `git clone --shared` of a live consumer repo on its working branch, it passed every throttle guard, wrote all four `.ship/` files and printed its directive. Yet no consumer repo on this machine had a `.ship/` state file newer than 2026-07-27, and the only `*-ship-auto.md` report ever written was this repo's own dogfood from 2026-04-25.

Two harness facts explain it, neither visible from inside the script:

1. **Project-scope hooks load only from the launch directory.** `<repo>/.claude/settings.json` is read where Claude Code starts. A session launched in `~` that then runs `cd ~/Projects/foo` never registers foo's Stop hook. `CLAUDE_PROJECT_DIR` stays at the launch directory; only the `cwd` field in the hook's input JSON follows the `cd`. The maintainer launches from `~`: this week's heavy consumer-repo transcripts sit in the home-directory project folder.
2. **Stop hook stdout never reaches the model.** Claude Code writes it to the debug log. Stdout becomes context only for `SessionStart`, `UserPromptSubmit`, `UserPromptExpansion` and `PostModelSwitch`. The line at `auto-ship-hook.sh:33` ("Claude Code injects stdout from Stop hooks into the next turn's context") was wrong. A Stop hook that wants the model to act must exit 2 with the instruction on stderr.

So every install probe that reported "hook wired" was true and irrelevant, and P16's SessionStart pickup would have fixed the second fact but not the first.

**Rule.** A hook that must fire for the maintainer's sessions is user-scope and resolves the repo from `cwd`. A Stop hook that needs the model to act exits 2. Verify a hook by its side effects on disk after a real session, never by reading the settings file. Applied in agent-sop P97; this repo's project-scope wiring is superseded.
