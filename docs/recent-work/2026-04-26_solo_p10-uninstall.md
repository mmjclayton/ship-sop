# P10: setup.sh --uninstall + manual-fallback rewrite

**Date:** 2026-04-26
**Agent:** solo
**Commits:** a673ceb

Closed the `setup.sh` round-trip story: install was canonical, uninstall was a manual `rm` recipe in the README. P10 replaces the recipe with `setup.sh --uninstall`.

The uninstaller mirrors the install footprint and adds three flags:

- `--keep-config` — preserve `ship-sop.config.json` across reinstalls (per-project tuning survives).
- `--keep-artifacts` — preserve `.ship/` runtime directory (cooldown stamps, pending directives).
- `--force` — remove user-scope agents and commands even if locally modified (default behaviour skips modified files with a notice).

Safety layer: SHA-256 hash check before removing each user-scope file. If the file's hash differs from the source repo's, the file is treated as locally customised and skipped (notice printed). `--force` overrides. `shasum` is the primary tool with no fallback in this script — acceptable since macOS and modern Linux both ship it.

`README.md` Uninstall section rewritten: CLI command first, flag table, "files never auto-removed" list, and a manual-fallback `rm` recipe retained for the case where the ship-sop clone is gone.

Drive-by fix: install Next-Steps and manual-uninstall lists in `setup.sh` and `README.md` had not been updated when `/audit` was added (P7); both lists now include `audit.md`.

Touched: `setup.sh` (uninstaller + flag plumbing + version-detection drift), `README.md` (Uninstall section overhaul + audit fix-up), `Backlog.md`, `docs/feature-map.md`.

## Open follow-ups

- Dogfood the uninstaller end-to-end against a real consumer project (hst-tracker) to confirm the `.claude/settings.json` jq-edit leaves other hooks intact.
- Consider whether non-interactive shells (CI runners) need `read -t 30` timeouts on the prompts in `setup.sh`. Currently they hang waiting for input.
