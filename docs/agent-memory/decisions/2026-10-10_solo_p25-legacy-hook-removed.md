# The project-scope auto-ship-hook.sh is removed, not kept as reference

**Date:** 2026-10-10
**Agent:** solo

Supersedes the "What stays here" paragraph of `2026-09-04_solo_auto-mode-trigger-moves-to-agent-sop.md`.

We deleted `scripts/auto-ship-hook.sh` from the repository instead of keeping it as reference. Shipping a 456-line script that nothing runs was flagged by the 2026-10-10 independent review, and setup was still copying and wiring it whenever agent-sop's hooks were absent.

Setup must still recognise copies left by older installs without the source file to compare against. It holds the git blob hashes of all seven shipped versions (`LEGACY_HOOK_BLOBS` in `setup.sh`): a project copy matching one is deleted, anything else is reported as locally modified and kept. Add nothing to that list; the script will not ship again.

Consequence: artifact retention (`artifacts.retain_ship_artifact_days`) lived only in the hook and is gone; the key was already deprecated in the schema.

P18 described faults in the hook's own state machine and closes as superseded: agent-sop reads coverage from validated receipts (decision `2026-09-08_solo_validated-review-evidence.md`) and has no stamp or directive file to go stale. P19's remaining item (d), no reviewer instruction declaring diff content untrusted, is fixed in the same change.
