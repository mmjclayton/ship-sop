# 2026-08-03 — P15: installer damage and the first CI

**Agent:** solo
**Branch:** `fix/p15-installer-damage-and-ci`

---

## What shipped

Batch 3.2 of Phase 3. Three installer defects and the repo's first automated checks. Each defect was reproduced before being touched, and each fix was proven against the reproduction.

### `.gitignore` over-delete

The uninstall awk set `skip = 2` after `next` had already consumed the marker line. The block setup.sh writes is two lines (`# ship-sop runtime artifacts` and `.ship/`), so only one further line may be skipped. The old value ate the first user line after the block while the summary printed "other entries kept".

Reproduced with a `.gitignore` ending `.ship/` then `.env.local`: `.env.local` came back gone. Fixed to `skip = 1` in `setup.sh` and in the copy-pasted `README.md` fallback. Regression check: install, append a sentinel immediately after the block, uninstall, assert the sentinel survives.

### Symlinked clone deleting ship-sop's own source

`SCRIPT_DIR` and `TARGET` both used logical `pwd`, which keeps the symlink in the path. With `~/ship-sop -> ~/Projects/ship-sop`, the self-install check compared two different strings for the same directory, returned false, and `--uninstall` proceeded to delete the real source files.

Fixed with `pwd -P` at both sites, plus an `-ef` guard in `remove_if_unmodified` that compares device and inode so it holds even when the paths differ textually. The guard sits *before* the `--force` branch, because `--force` is about overriding local modifications, not about deleting the file we install from.

Proven by A/B through a real symlinked clone. Pre-fix: `scripts/auto-ship-hook.sh`, `docs/templates/ship-sop.schema.json` and `ship-sop.config.json` all deleted. Post-fix: "Self-install detected", everything survives.

### `/ship-on`'s wiring snippet

Two defects in four lines, both reproduced. `jq '.hooks.Stop = [{...}] // .hooks.Stop'` always replaces the array wholesale, so a co-located user hook was destroyed. And the `mv` ran unconditionally, so with no `settings.json` present the jq failed and a 0-byte `settings.json` was installed. Meanwhile the same file's "Side effects" section claimed it does not modify settings.json.

Replaced with a read-only probe and a pointer to `setup.sh`, which merges idempotently, migrates pre-P14 entries, preserves other hooks and asserts the result. Its stale "security, compliance, doc-builder by default" line was corrected at the same time — six gates now, and `doc-builder` was renamed to `diagram-builder` long ago.

### First CI

`.github/workflows/ci.yml`. shellcheck `-S warning` and `bash -n` blocking on ship-sop's own two scripts (`setup.sh`, `scripts/auto-ship-hook.sh`), both already clean. The four agent-sop replicas run advisory-only via `continue-on-error`, because their fixes belong upstream and are re-synced through `/update-agent-sop` — a finding there must not block a ship-sop PR. Plus `jq empty` across five JSON files and a P14 regression guard that fails the build if the wired hook entry is flat or absent.

`CLAUDE.md:78` claimed a CI candidate was "filed in `Backlog.md` if needed". It was not, and there was no `.github/`. Now there is.

## The mistake worth recording

Running `--uninstall` during testing removed the user-scope agents and commands from the real `~/.claude/`, because user-scope removal is not scoped to the target project. `/ship`, `/audit`, `/release`, `/ship-on`, `/ship-off` and all three vendored agents disappeared mid-session.

Recovery was a plain reinstall answering `n` to the hook prompt, which restored all eight files without touching the wiring. Test procedure now sets `HOME` to a throwaway directory for anything that runs uninstall.

The underlying behaviour is a real defect, filed as **P24**: uninstalling from one project silently disarms every other installed project. The remaining projects keep their hook and their config, so auto-mode keeps firing — into agents that are no longer there. Under P17's rule that must report MISSING, but P17 has not shipped and the hook does not check agent presence today.

Worth noting that this is the second time in two batches that the interesting finding came from running the thing rather than reading it.

## Verification

- `.gitignore` sentinel survives install → uninstall; ship-sop block removed; pre-existing entries intact
- Symlink A/B: pre-fix deletes three source files, post-fix detects self-install and preserves all
- Both `/ship-on` snippet defects reproduced before removal
- shellcheck `-S warning` and `bash -n` clean on both ship-sop scripts
- Five JSON files valid; workflow YAML parses
- P14 not regressed: fresh install still produces the nested shape
