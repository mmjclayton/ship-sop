#!/usr/bin/env bash
# Totals from ship-sop receipts: how often gates ran, blocked and found issues,
# what the reviews cost and whether the tests caught what blocked.
# Usage: receipt-totals.sh [--json] REPO_ROOT...
# Receipts are read from REPO_ROOT/docs/reviews/*-ship-auto.json. A receipt seen
# in several clones (same head, base and file name) counts once, under the first
# root given; a copy with different content is reported. Rows are keyed by the
# resolved root path and labelled with its directory name. Launches, re-checks
# and block rounds exist from schema version 2; version 1 receipts count towards
# receipts and findings only. Findings are those recorded in the final receipt:
# open items plus fixed ones recorded as INFO. Block rounds count review rounds
# that found a blocking issue.
#
# Cost (P44). Each receipt is one change. A change's tokens and reviewer minutes
# are known only when every reviewer in it recorded usage; one null makes the
# change's figure null, so a partial sum never reads as a total. Tokens are
# Claude's total_tokens (the sum over agent instances of each one's last,
# cumulative figure), or Codex's input_tokens + output_tokens. The runtimes
# count differently, so tokens are also given per source, over the same changes.
# Reviewer minutes add up each reviewer's own run time; reviewers run in
# parallel, so this is not wall-clock time. With no change fully costed, tokens
# and minutes are null in --json and n/a in the table, never 0.
# Test-catch (P44). block_tests results are counted: PASS (the suite passed at
# the blocked commit, so the tests missed what blocked), FAIL and NOT_AVAILABLE;
# a blocked change (v2+) with no block_tests field counts as "no record".
# --json adds a per-change list, and medians and ranges per change.
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
# A usage object this script cannot read counts as unknown (null).
ROW_FILTER='
  def num: if type == "number" and . >= 0 then . else null end;
  def cost: try (
      if type == "object" and .source == "claude-task-notification" then
        # Totals as written, else from the runs: tokens are cumulative per
        # instance (its last figure counts once), duration_ms is per run.
        {source,
         tokens: ((.tokens.total_tokens // ([.runs | group_by(.instance)[] | .[-1].tokens] | add)) | num),
         seconds: ((.duration_ms // ([.runs[].duration_ms] | add)) | num | if . == null then null else . / 1000 end)}
      elif type == "object" and .source == "codex-review" then
        {source,
         tokens: (if (.tokens.input_tokens | num) != null and (.tokens.output_tokens | num) != null
                  then .tokens.input_tokens + .tokens.output_tokens else null end),
         seconds: (.elapsed_seconds | num)}
      else null end
      | if . != null and (.tokens == null or .seconds == null) then null else . end
    ) catch null;
  if (.head | type) == "string" and (.reviewers | type) == "array"
     and all(.reviewers[]; type == "object" and ((.findings // []) | type) == "array")
  then {root: $root, project: $project, file: $file, head: .head,
        key: "\(.head)|\(.base)|\($file)",
        schema: (.schema_version // 1),
        block_tests: [(.block_tests // [] | if type == "array" then .[] else empty end) | objects | .result | strings],
        block_tests_recorded: has("block_tests"),
        reviewers: [.reviewers[] | {launches, rechecks, block_rounds,
          usage: (.usage | cost),
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
jq -rs 'group_by(.key)[] | select((map([.schema, .reviewers, .block_tests] | tojson) | unique | length) > 1)
  | "warn   receipt \(.[0].key) differs between \(map(.root) | unique | join(" and ")); counted under \(.[0].root)"' \
  "$rows" >&2

summary=$(jq -s '
  def round1: . * 10 | round / 10;
  def median: sort | if length == 0 then null elif length % 2 == 1 then .[length / 2 | floor]
              else (.[length / 2 - 1] + .[length / 2]) / 2 end;
  def costed: .schema >= 2 and (.reviewers | length) > 0 and all(.reviewers[]; .usage != null);
  def change: {file, head,
      block_rounds: (if .schema >= 2 then ([.reviewers[].block_rounds // 0] | add // 0) else null end),
      tokens: (if costed then [.reviewers[].usage.tokens] | add else null end),
      reviewer_minutes: (if costed then [.reviewers[].usage.seconds] | add / 60 | round1 else null end),
      tokens_by_source: (if costed then [.reviewers[].usage | {source, tokens}] | group_by(.source)
                           | map({key: .[0].source, value: ([.[].tokens] | add)}) | from_entries else null end),
      blocked: (.schema >= 2 and any(.reviewers[]; (.block_rounds // 0) > 0)),
      block_tests_recorded,
      block_tests: .block_tests};
  unique_by(.key)
  | group_by(.root)
  | map(
      (map(change)) as $changes
      | [$changes[] | select(.tokens != null)] as $costed
      | {
      project: .[0].project,
      root: .[0].root,
      receipts: length,
      schema_v2: (map(select(.schema >= 2)) | length),
      gates_that_blocked: (map(select(.schema >= 2 and any(.reviewers[]; (.block_rounds // 0) > 0))) | length),
      launches: ([.[] | select(.schema >= 2) | .reviewers[].launches // 0] | add // 0),
      rechecks: ([.[] | select(.schema >= 2) | .reviewers[].rechecks // 0] | add // 0),
      block_rounds: ([.[] | select(.schema >= 2) | .reviewers[].block_rounds // 0] | add // 0),
      findings: ([.[].reviewers[].findings[]] | group_by(.) | map({key: .[0], value: length}) | from_entries),
      changes_with_usage: ($costed | length),
      tokens: ([$costed[].tokens] | add),
      reviewer_minutes: ([$costed[].reviewer_minutes] | add | if . == null then null else round1 end),
      tokens_by_source: ([$costed[].tokens_by_source | to_entries[]] | group_by(.key)
                         | map({key: .[0].key, value: ([.[].value] | add)}) | from_entries),
      per_change: {
        tokens_median: ([$costed[].tokens] | median),
        tokens_min: ([$costed[].tokens] | min),
        tokens_max: ([$costed[].tokens] | max),
        reviewer_minutes_median: ([$costed[].reviewer_minutes] | median),
        reviewer_minutes_min: ([$costed[].reviewer_minutes] | min),
        reviewer_minutes_max: ([$costed[].reviewer_minutes] | max),
        block_rounds_median: ([$changes[].block_rounds | numbers] | median),
        block_rounds_max: ([$changes[].block_rounds | numbers] | max)},
      block_tests: ([.[].block_tests[]] | group_by(.) | map({key: .[0], value: length}) | from_entries),
      blocked_without_block_tests: ([$changes[] | select(.blocked and (.block_tests_recorded | not))] | length),
      changes: $changes
    })' "$rows")

if [ "$FORMAT" = json ]; then
    printf '%s\n' "$summary"
else
    printf '| Project | Receipts | v2+ | Gates that blocked (v2+) | Block rounds | Launches | Re-checks | CRITICAL | HIGH | MEDIUM | LOW | INFO | Changes with usage | Tokens | Reviewer minutes | Tests at blocks: pass / fail / n.a. / no record |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    jq -r '.[] | "| \(.project) | \(.receipts) | \(.schema_v2) | \(.gates_that_blocked) | \(.block_rounds) | \(.launches) | \(.rechecks) | \(.findings.CRITICAL // 0) | \(.findings.HIGH // 0) | \(.findings.MEDIUM // 0) | \(.findings.LOW // 0) | \(.findings.INFO // 0) | \(.changes_with_usage) | \(.tokens // "n/a") | \(.reviewer_minutes // "n/a") | \(.block_tests.PASS // 0) / \(.block_tests.FAIL // 0) / \(.block_tests.NOT_AVAILABLE // 0) / \(.blocked_without_block_tests) |"' <<< "$summary"
fi
[ "$problems" = 0 ] || { echo "$problems problem(s) reading receipts; see above" >&2; exit 1; }
