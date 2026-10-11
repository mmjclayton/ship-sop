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

- `build-plans/2026-10-12-gate-value.md` - the plan to measure the gate's cost and value on live work

## History (read, do not rewrite)

- `backlog-archive.md` - closed Backlog items moved by `scripts/archive-backlog.sh`
- Older records (session logs, agent memory, phase build plans) are in the top-level `archive/` folder; nothing reads them

## Runtime artifacts

`reviews/` accumulates review output. Two filename conventions coexist:

| Pattern | Origin | Lifecycle |
|---|---|---|
| `YYYY-MM-DD_<agent-id>_P<n>.md` | Earlier per-item review records | Permanent audit trail; never auto-pruned |
| `YYYYMMDD-HHMMSS-<gate>.md`, `<stamp>-ship-auto.md` and `.json` | `/ship` reports and receipts | Not pruned automatically; delete old reports by hand if needed |

`artifacts.retain_ship_artifact_days` is a deprecated schema key and is not read.
