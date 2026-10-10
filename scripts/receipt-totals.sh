#!/usr/bin/env bash
# Totals from ship-sop receipts: how often gates ran, blocked and found issues.
# Usage: receipt-totals.sh [--json] REPO_ROOT...
# Receipts are read from REPO_ROOT/docs/reviews/*-ship-auto.json. A receipt seen
# in several clones (same head, base and file name) counts once, under the first
# root given; a copy with different content is reported. Rows are keyed by the
# resolved root path and labelled with its directory name. Launches, re-checks
# and block rounds exist from schema version 2; version 1 receipts count towards
# receipts and findings only. Findings are those recorded in the final receipt:
# open items plus fixed ones recorded as INFO. Block rounds count review rounds
# that found a blocking issue.
# Exit status: 0 when every file was read, 1 when a file was skipped or no
# receipts were found (the totals still print), 2 on bad arguments.
set -euo pipefail
FORMAT=table
if [ "${1:-}" = --json ]; then FORMAT=json; shift; fi
[ $# -gt 0 ] || { echo 'Usage: receipt-totals.sh [--json] REPO_ROOT...' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo 'jq is required' >&2; exit 1; }

rows=$(mktemp); trap 'rm -f "$rows"' EXIT
problems=0
# Reviewer entries are reduced to the fields counted here, so a malformed entry
# cannot break the totals; a receipt whose shape is wrong is skipped instead.
ROW_FILTER='
  if (.head | type) == "string" and (.reviewers | type) == "array"
     and all(.reviewers[]; type == "object" and ((.findings // []) | type) == "array")
  then {root: $root, project: $project, key: "\(.head)|\(.base)|\($file)",
        schema: (.schema_version // 1),
        reviewers: [.reviewers[] | {launches, rechecks, block_rounds,
          findings: [(.findings // [])[] | objects | .severity | strings]}]}
  else error("not a receipt") end'
for root in "$@"; do
    [ -d "$root" ] || { echo "Not a directory: $root" >&2; exit 2; }
    resolved=$(cd -- "$root" && pwd -P)
    project=$(basename "$resolved")
    found=0
    for f in "$resolved"/docs/reviews/*-ship-auto.json; do
        [ -f "$f" ] || continue
        if jq -c --arg root "$resolved" --arg project "$project" --arg file "$(basename "$f")" \
            "$ROW_FILTER" "$f" >> "$rows" 2>/dev/null; then
            found=$((found + 1))
        else
            printf 'skip   %q (not a readable receipt)\n' "$f" >&2; problems=$((problems + 1))
        fi
    done
    if [ "$found" = 0 ]; then
        printf 'note   %q has no receipts\n' "$resolved" >&2; problems=$((problems + 1))
    fi
done

# Same key, different content: the copies disagree, so say which count was kept.
jq -rs 'group_by(.key)[] | select((map([.schema, .reviewers] | tojson) | unique | length) > 1)
  | "warn   receipt \(.[0].key) differs between \(map(.root) | unique | join(" and ")); counted under \(.[0].root)"' \
  "$rows" >&2

summary=$(jq -s '
  unique_by(.key)
  | group_by(.root)
  | map({
      project: .[0].project,
      root: .[0].root,
      receipts: length,
      schema_v2: (map(select(.schema >= 2)) | length),
      gates_that_blocked: (map(select(.schema >= 2 and any(.reviewers[]; (.block_rounds // 0) > 0))) | length),
      launches: ([.[] | select(.schema >= 2) | .reviewers[].launches // 0] | add // 0),
      rechecks: ([.[] | select(.schema >= 2) | .reviewers[].rechecks // 0] | add // 0),
      block_rounds: ([.[] | select(.schema >= 2) | .reviewers[].block_rounds // 0] | add // 0),
      findings: ([.[].reviewers[].findings[]] | group_by(.) | map({key: .[0], value: length}) | from_entries)
    })' "$rows")

if [ "$FORMAT" = json ]; then
    printf '%s\n' "$summary"
else
    printf '| Project | Receipts | v2+ | Gates that blocked (v2+) | Block rounds | Launches | Re-checks | CRITICAL | HIGH | MEDIUM | LOW | INFO |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    jq -r '.[] | "| \(.project) | \(.receipts) | \(.schema_v2) | \(.gates_that_blocked) | \(.block_rounds) | \(.launches) | \(.rechecks) | \(.findings.CRITICAL // 0) | \(.findings.HIGH // 0) | \(.findings.MEDIUM // 0) | \(.findings.LOW // 0) | \(.findings.INFO // 0) |"' <<< "$summary"
fi
[ "$problems" = 0 ] || { echo "$problems problem(s) reading receipts; see above" >&2; exit 1; }
