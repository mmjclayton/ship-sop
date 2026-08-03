# setup.sh --uninstall removes user-scope files globally, not per-project

**Date:** 2026-08-03
**Agent:** solo

**The surprise.** Running `./setup.sh /tmp/throwaway-project --uninstall --force` during P15 regression testing deleted the real `~/.claude/agents/{compliance-reviewer,diagram-builder,release-notes-writer}.md` and `~/.claude/commands/{ship,release,ship-on,ship-off,audit}.md`. The `/ship`, `/audit` and `/release` commands vanished from the live session mid-batch, along with all three vendored agents.

**The misleading prior expectation.** That `--uninstall <target>` is scoped to `<target>`. It is not: `remove_user_scope_files()` deletes from `$HOME/.claude`, which is global by construction. The target argument controls only the project-side removal (hook script, config, `.gitignore` block, settings entry).

**The rule.**

1. Any test that runs `--uninstall` must isolate `HOME`:
   ```bash
   HOME="$SCRATCH/fakehome" bash setup.sh "$TARGET" --uninstall --force
   ```
   Everything else in the installer derives user scope from `$HOME`, so this is sufficient and cheap.
2. Recovery, if it happens anyway, is a plain reinstall answering `n` to the hook prompt — that restores all eight user-scope files without touching the wiring:
   ```bash
   yes n | ./setup.sh /path/to/any/project
   ```

**Why it matters beyond testing.** This is a live defect for real operators, filed as **P24**. Uninstalling ship-sop from one project you no longer want gated removes the agents and commands every *other* installed project depends on. Those projects keep their hook, their config and their `ship-sop.config.json`, so auto-mode keeps firing — into agents that are no longer on disk. A clean uninstall in project A becomes silent gate loss in projects B and C.

Under P17's rule that must surface as MISSING rather than as a pass, but P17 has not shipped and the hook does not check agent presence today. Until then, treat `--uninstall` as a machine-level operation, not a project-level one.

Second batch running where the finding came from executing the thing rather than reading it.
