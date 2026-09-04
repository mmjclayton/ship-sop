# The auto-mode trigger moves to agent-sop's user-scope hooks; ship-sop keeps the gates

**Date:** 2026-09-04
**Agent:** solo

We chose to **fold ship-sop's automatic trigger into agent-sop's user-scope Stop hook** rather than fix it in place, because the two facts that kept it inert (project-scope hooks load only from the launch directory; Stop stdout is discarded) apply to any project-scope Stop hook, and agent-sop was shipping a user-scope Stop hook for its own session-end drift in the same batch. One hook computing one set of facts about the repo, with the ship-sop gate as one of them, replaces two hooks that would have had to agree about default-branch detection, merge-base and docs-only filtering.

Division of responsibility from here:

- **ship-sop** owns the gates: which agents, `block_on` levels, the config schema, the report format, `/ship`, `/audit`, `/release`, the compliance and diagram agents. `ship-sop.config.json` is unchanged and remains the per-project switch.
- **agent-sop** owns the triggers: `sop-stop-drift.sh` reads `ship-sop.config.json` (`trigger.mode`, `throttle.min_diff_lines`, `skip_docs_only`, `skip_branch_patterns`, `agents`) and exits 2 with the gate demand when the code diff vs the default branch has no covering report; `sop-push-gate.sh` refuses `git push` / `gh pr create` on the same fact. Both are installed by `bash scripts/install-hooks.sh` in the agent-sop checkout.

Two semantics changed with the move, both recorded in agent-sop's decision `2026-09-04_solo_p97-stop-hook-exit-2-and-coverage-by-fact.md`:

- **Same-turn, not next-turn.** The demand arrives via exit 2 while the agent is still in the turn, so gates run before it finishes. No directive file, no `.pending-auto-fire.md`, no SessionStart pickup, no `/restart-sop` backstop. P16 is superseded.
- **Coverage is read from the report, not stamped.** A report covers HEAD when it carries `Covers: <sha>` for an ancestor with zero code lines since. This removes P18's stamp-at-emission bug (an interrupted turn left a commit permanently ungated) without a new state file.

What stays here: `scripts/auto-ship-hook.sh` remains in the repo as reference and is no longer wired by `setup.sh`; `.ship/.last-auto-fire`, `.last-diff-hash` and the directive pair are legacy. Consumer repos carrying the old project-scope entry (`hst-tracker`, `opportunity-scan`, `os-carry`, this repo) should drop it on their next session — filed as P25.

Rejected: keeping a project-scope hook here and telling the operator to launch from inside the project. A rule the operator must remember is the failure the automation exists to remove.

---
*Supersedes:* `2026-08-03_solo_sessionstart-hook-is-the-automation-path.md` (same intent, wrong scope), P16.
