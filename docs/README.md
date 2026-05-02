# `docs/` orientation

Audience: anyone landing in this tree without context. Some files are ship-sop's own product surface, some are pristine replicas synced from upstream agent-sop, and some are SOP-generated history. Knowing which is which avoids breaking integrations.

## ship-sop's own surface (modify freely in this repo)

- `ship-sop.md` — redirect stub; the spec lives in the top-level `README.md` post-P11
- `feature-map.md` — shipped-features inventory
- `agent-memory.md` — narrative cross-session context
- `templates/ship-sop.config.json` — default config
- `templates/ship-sop.schema.json` — JSON Schema for the config

## agent-sop pristine replicas (do **not** modify in this repo)

These files are SHA-tracked against upstream `agent-sop` via `.claude/agent-sop.config.json` and synced via `/update-agent-sop`. Edits belong in the agent-sop repo, then re-synced here.

- `sop/{claude-agent-sop,security,sandboxing,harness-configuration,compliance-checklist}.md` — agent-sop's SOP corpus
- `guides/{optional-patterns,multi-agent-context-routing,multi-agent-parallel-sessions,managed-agents-integration,sop-hill-climbing,sop-common-mistakes}.md` — agent-sop's how-to library
- `templates/review-template.md` — agent-sop's review-artifact template
- `agent-memory/in-flight/README.md` — convention doc

## SOP-generated (per agent-sop conventions)

Written by `/update-sop` on session-end. Browse for project history; the rollup in the top-level `CLAUDE.md` is regenerated from these.

- `recent-work/YYYY-MM-DD_<agent-id>_<slug>.md` — per-session summaries
- `agent-memory/decisions/YYYY-MM-DD_<agent-id>_<slug>.md` — locked architectural decisions
- `agent-memory/gotchas/YYYY-MM-DD_<agent-id>_<slug>.md` — gotchas and lessons
- `build-plans/phase-N.md` — per-phase batch logs

## Runtime artifacts

`reviews/` accumulates gate output. Two filename conventions coexist — pruning logic must respect both:

| Pattern | Origin | Lifecycle |
|---|---|---|
| `YYYY-MM-DD_<agent-id>_P<n>.md` | agent-sop's `/update-sop` Step 2c | **Permanent audit trail; never auto-pruned** |
| `YYYYMMDD-HHMMSS-<gate>.md` (and `<stamp>-ship-auto.md`) | ship-sop's gate artifacts | Prunable via `artifacts.retain_ship_artifact_days` in `ship-sop.config.json` |

The retention prune in `scripts/auto-ship-hook.sh` filters strictly to ship-sop's stamp format using a precise digit-count glob, so agent-sop's permanent reviews are never affected.
