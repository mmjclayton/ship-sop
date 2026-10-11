# `docs/` orientation

Audience: anyone landing in this tree without context. Some files are ship-sop's
product surface, and some are history kept for reference.

## Product surface (modify in this repo)

- `templates/ship-sop.config.json` - default config
- `templates/ship-sop.schema.json` - JSON Schema for the config
- `templates/review-template.md` - review-artifact template
- `feature-map.md` - shipped-features inventory
- `ship-sop.md` - redirect stub; the spec lives in the top-level `README.md`
- `benchmark/p40/` - the blind precision sample of ship-gate blocks (P40)

## History (read, do not rewrite)

- `agent-memory.md`, `agent-memory/decisions/`, `agent-memory/gotchas/` - decisions and lessons, as reference reading
- `recent-work/`, `RECENT-WORK.md` - earlier session records; no longer written
- `build-plans/` - phase plans and batch logs; planning context
- `backlog-archive.md` - closed Backlog items moved by `scripts/archive-backlog.sh`

## Runtime artifacts

`reviews/` accumulates review output. Two filename conventions coexist:

| Pattern | Origin | Lifecycle |
|---|---|---|
| `YYYY-MM-DD_<agent-id>_P<n>.md` | Earlier per-item review records | Permanent audit trail; never auto-pruned |
| `YYYYMMDD-HHMMSS-<gate>.md`, `<stamp>-ship-auto.md` and `.json` | `/ship` reports and receipts | Not pruned automatically; delete old reports by hand if needed |

`artifacts.retain_ship_artifact_days` is a deprecated schema key and is not read.
