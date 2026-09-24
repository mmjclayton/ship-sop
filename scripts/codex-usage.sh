#!/usr/bin/env bash
# Sum one reviewer's Codex run telemetry into the receipt's usage object.
#
#   codex-usage.sh [--agent NAME] EVIDENCE_DIR...
#
# Each EVIDENCE_DIR is a "Review evidence:" directory printed by codex-review.sh
# (metadata.json inside carries per-turn usage and a telemetry_status). Prints
# one JSON object when every run's telemetry is available, or `null` when any
# run's is not, so a partial sum never reads as the total; the run lacking
# telemetry is named on stderr. Exit 2 on a directory that is not evidence for
# the named reviewer, or on evidence from two different reviewers.
set -euo pipefail
AGENT=''
while [ $# -gt 0 ]; do
    case "$1" in
        --agent) [ $# -ge 2 ] || { echo '--agent needs a value' >&2; exit 2; }; AGENT=$2; shift 2 ;;
        --) shift; break ;;
        -*) echo "Unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
[ $# -ge 1 ] || { echo 'Usage: codex-usage.sh [--agent NAME] EVIDENCE_DIR...' >&2; exit 2; }
command -v jq >/dev/null || { echo 'jq is required' >&2; exit 1; }
FILES=()
for d in "$@"; do
    [ -f "$d/metadata.json" ] || { echo "Not a review evidence directory: $d" >&2; exit 2; }
    jq -e 'type == "object" and (.agent | type == "string") and has("usage") and has("telemetry_status")' "$d/metadata.json" >/dev/null 2>&1 \
        || { echo "Unreadable or pre-telemetry metadata: $d/metadata.json" >&2; exit 2; }
    FILES+=("$d/metadata.json")
done
AGENTS=$(jq -rs '[.[].agent] | unique | .[]' "${FILES[@]}")
[ "$(printf '%s\n' "$AGENTS" | wc -l | tr -d ' ')" = 1 ] || { echo "Evidence from more than one reviewer: $(printf '%s ' $AGENTS)" >&2; exit 2; }
[ -z "$AGENT" ] || [ "$AGENTS" = "$AGENT" ] || { echo "Evidence belongs to $AGENTS, not $AGENT" >&2; exit 2; }
MISSING=$(jq -rs '.[] | select(.telemetry_status != "available" or (.usage | type) != "array") | .agent + " run with telemetry " + (.telemetry_status // "unknown" | tostring)' "${FILES[@]}")
if [ -n "$MISSING" ]; then
    printf '%s\n' "$MISSING" | sed 's/^/usage unknown: /' >&2
    echo null
    exit 0
fi
EVIDENCE='[]'
for d in "$@"; do EVIDENCE=$(jq -c --arg n "$(basename "$d")" '. + [$n]' <<< "$EVIDENCE"); done
jq -s --arg source codex-review --argjson evidence "$EVIDENCE" '
  {source: $source,
   runs: length,
   turns: ([.[].usage | length] | add),
   elapsed_seconds: ([.[].elapsed_seconds // 0] | add),
   tokens: ([.[].usage[]] | reduce .[] as $t ({}; reduce ($t | to_entries[] | select(.value | type == "number")) as $e (.; .[$e.key] += $e.value))),
   evidence: $evidence}
' "${FILES[@]}"
