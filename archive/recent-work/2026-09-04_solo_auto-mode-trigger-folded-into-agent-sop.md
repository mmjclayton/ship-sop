# 2026-09-04 — auto-mode trigger folded into agent-sop; P16 superseded, P25 filed

**Agent:** solo
**Branch:** `docs/fold-auto-trigger-into-agent-sop`

---

## What shipped

Docs-only reconciliation after agent-sop P97. No script here changed.

- **Root cause of four months of silence recorded.** `scripts/auto-ship-hook.sh` fires correctly when run by hand in a clone of a live consumer repo; it never ran in a real session because project-scope hooks load only from the launch directory (sessions here start in `~`), and its stdout directive could never have reached the model because Claude Code discards Stop hook stdout. Gotcha: `docs/agent-memory/gotchas/2026-09-04_solo_stop-stdout-is-discarded-and-project-hooks-need-the-launch-dir.md`.
- **Trigger moves upstream.** agent-sop's user-scope `sop-stop-drift.sh` reads `ship-sop.config.json` and exits 2 with the gate demand in the same turn; `sop-push-gate.sh` refuses `git push` / `gh pr create` until a report names an ancestor of HEAD with no code change since. ship-sop keeps the gates, agents, schema, report format and `/ship`. Decision: `docs/agent-memory/decisions/2026-09-04_solo_auto-mode-trigger-moves-to-agent-sop.md`.
- **Backlog.** P16 → `[WON'T]`, superseded. P20 annotated: the push/PR gate half shipped upstream (bypass token `SOP_SKIP_GATE=1`, logged). P25 filed to retire the project-scope wiring in `setup.sh`, CI, this repo and three consumer repos.
- **README** hero, Why, Two modes, How auto-mode executes (rewritten to the one-step design, previous design explained), hook-visibility note, Composes-with-agent-sop, Requirements floor to 2.1.251, Directive-integrity section marked legacy. **CLAUDE.md** dogfood line and the Stop-hook gotcha bullet. `/ship`, `/ship-on`, `/ship-off` descriptions reworded from "SessionStop hook" to the agent-sop Stop hook. Feature-map "Why not" row for the old trigger.

Left in place on purpose: `setup.sh` wiring, the CI nested-shape assertion, `.claude/settings.json` entry — all P25, so this batch stays docs-only and CI stays green.
