#!/usr/bin/env bash
# Totals from ship-sop receipts: how often gates ran, blocked and found issues.
# Usage: receipt-totals.sh [--json] REPO_ROOT...
# Receipts are read from REPO_ROOT/docs/reviews/*-ship-auto.json. A receipt seen
# in several clones (same head, base and file name) counts once, under the first
# root given. Launches, re-checks and block rounds exist only in schema version 2
# receipts; version 1 receipts count towards receipts and findings only.
# Findings are those recorded in the final receipt: open items plus fixed ones
# recorded as INFO. Block rounds count review rounds that found a blocking issue.
set -euo pipefail
FORMAT=table
if [ "${1:-}" = --json ]; then FORMAT=json; shift; fi
[ $# -gt 0 ] || { echo 'Usage: receipt-totals.sh [--json] REPO_ROOT...' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo 'jq is required' >&2; exit 1; }

rows=$(mktemp); trap 'rm -f "$rows"' EXIT
skipped=0
for root in "$@"; do
    [ -d "$root" ] || { echo "Not a directory: $root" >&2; exit 2; }
    project=$(basename "$(cd "$root" && pwd -P)")
    for f in "$root"/docs/reviews/*-ship-auto.json; do
        [ -f "$f" ] || continue
        if ! jq -e '(.head | type == "string") and (.reviewers | type == "array")' "$f" >/dev/null 2>&1; then
            echo "skip   $f (not a receipt)" >&2; skipped=$((skipped + 1)); continue
        fi
        jq -c --arg project "$project" --arg file "$(basename "$f")" \
            '{project: $project, key: "\(.head)|\(.base)|\($file)", schema: (.schema_version // 1), reviewers: .reviewers}' "$f" >> "$rows"
    done
done

summary=$(jq -s '
  unique_by(.key)
  | group_by(.project)
  | map({
      project: .[0].project,
      receipts: length,
      schema_v2: (map(select(.schema == 2)) | length),
      gates_that_blocked: (map(select(.schema == 2 and any(.reviewers[]; (.block_rounds // 0) > 0))) | length),
      launches: ([.[] | select(.schema == 2) | .reviewers[].launches // 0] | add // 0),
      rechecks: ([.[] | select(.schema == 2) | .reviewers[].rechecks // 0] | add // 0),
      block_rounds: ([.[] | select(.schema == 2) | .reviewers[].block_rounds // 0] | add // 0),
      findings: ([.[].reviewers[].findings[]?.severity] | group_by(.) | map({key: .[0], value: length}) | from_entries)
    })' "$rows")

if [ "$FORMAT" = json ]; then
    printf '%s\n' "$summary"
else
    printf '| Project | Receipts | v2 | Gates that blocked (v2) | Block rounds | Launches | Re-checks | CRITICAL | HIGH | MEDIUM | LOW | INFO |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    jq -r '.[] | "| \(.project) | \(.receipts) | \(.schema_v2) | \(.gates_that_blocked) | \(.block_rounds) | \(.launches) | \(.rechecks) | \(.findings.CRITICAL // 0) | \(.findings.HIGH // 0) | \(.findings.MEDIUM // 0) | \(.findings.LOW // 0) | \(.findings.INFO // 0) |"' <<< "$summary"
fi
[ "$skipped" = 0 ] || echo "$skipped file(s) skipped; see above" >&2
