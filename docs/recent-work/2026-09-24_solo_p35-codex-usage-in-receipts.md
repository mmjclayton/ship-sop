# Codex usage in receipts

Shipped P35 on the user's instruction, closing the piece P34 left out.
`scripts/codex-usage.sh` sums one reviewer's Codex run telemetry (launches and
re-checks) from the runner's evidence directories into the receipt's `usage`
object, prints null when any run lacked telemetry so a partial sum never reads
as a total, and refuses evidence from another reviewer or from before
telemetry existed. Installed and uninstalled beside the runner; `$ship` step 4
names it; CI runs its test. Claude stays null.

The runner's per-turn usage carries five counters (input, cached input, cache
write, output, reasoning output); 62 of the 72 evidence directories on this
machine have it, the rest predate telemetry or ran without it. The agent-sop
copy of `codex-review.sh` is a pre-P32 version without telemetry; it is not the
installed runner and is left for P23 (replica drift).
