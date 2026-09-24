#!/usr/bin/env bash
# Assemble and validate a gate receipt from real reviewer and test results.
set -euo pipefail
BASE=''; HEAD_REF=HEAD; RESULTS=''; TESTS=''; OUTPUT=''
RUNTIME=${AGENT_SOP_RUNTIME:-codex}
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || { echo 'Each option needs a value' >&2; exit 2; }
    case "$1" in
        --base) BASE=$2 ;; --head) HEAD_REF=$2 ;; --results) RESULTS=$2 ;;
        --tests) TESTS=$2 ;; --output) OUTPUT=$2 ;; --runtime) RUNTIME=$2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift 2
done
case "$RUNTIME" in
    codex) CONFIG_HOME=${CODEX_HOME:-${AGENT_SOP_USER_HOME:-$HOME}/.codex} ;;
    claude) CONFIG_HOME=${AGENT_SOP_USER_HOME:-$HOME}/.claude ;;
    *) echo 'runtime must be claude or codex' >&2; exit 2 ;;
esac
export AGENT_SOP_RUNTIME="$RUNTIME" AGENT_SOP_CONFIG_HOME="$CONFIG_HOME"
LIB="$CONFIG_HOME/scripts/hooks/agent-sop/sop-lib.sh"
[ -f "$LIB" ] || { echo 'INCOMPLETE: install current agent-sop hooks first' >&2; exit 1; }
# shellcheck disable=SC1090
. "$LIB"
declare -F sop_receipt_valid >/dev/null || { echo 'INCOMPLETE: update agent-sop receipt support' >&2; exit 1; }
ROOT=$(git rev-parse --show-toplevel)
[ -n "$BASE" ] && [ -f "$RESULTS" ] && [ -f "$TESTS" ] && [ -n "$OUTPUT" ] || {
    echo 'Required: --base REF --results reviewers.json --tests tests.json --output docs/reviews/STAMP-ship-auto.json' >&2
    exit 2
}
case "$OUTPUT" in *-ship-auto.json) ;; *) echo 'Output must end in -ship-auto.json' >&2; exit 2 ;; esac
[ ! -e "$OUTPUT" ] || { echo 'Use a new receipt filename; existing evidence is immutable' >&2; exit 2; }
jq -se 'length == 1 and (.[0] | type == "array")' "$RESULTS" >/dev/null || { echo 'INCOMPLETE: results must contain one JSON array' >&2; exit 1; }
jq -se 'length == 1 and (.[0] | type == "object")' "$TESTS" >/dev/null || { echo 'INCOMPLETE: tests must contain one JSON object' >&2; exit 1; }
CONFIG=$(sop_effective_config "$ROOT")
BASE=$(git rev-parse --verify "$BASE^{commit}")
HEAD_SHA=$(git rev-parse --verify "$HEAD_REF^{commit}")
TREE=$(git rev-parse "$HEAD_SHA^{tree}")
mkdir -p "$(dirname "$OUTPUT")"
TMP=$(mktemp "${OUTPUT}.XXXXXX")
trap 'rm -f "$TMP"' EXIT
jq -n --arg base "$BASE" --arg head "$HEAD_SHA" --arg tree "$TREE" \
    --arg policy "$(sop_policy_digest "$CONFIG")" \
    --slurpfile results "$RESULTS" --slurpfile tests "$TESTS" \
    '{schema_version:1,base:$base,head:$head,tree:$tree,policy_sha256:$policy,
      tests:$tests[0],reviewers:$results[0]}' > "$TMP"
if ! sop_receipt_valid "$ROOT" "$TMP"; then
    echo 'BLOCK/INCOMPLETE: results, tests, policy or review range do not qualify; no receipt written' >&2
    exit 1
fi
# Hard-link creation refuses races with another writer choosing the same output.
ln "$TMP" "$OUTPUT"
printf 'PASS: validated receipt %s for %s\n' "$OUTPUT" "$HEAD_SHA"
