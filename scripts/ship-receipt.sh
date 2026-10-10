#!/usr/bin/env bash
# Assemble and validate a gate receipt from real reviewer and test results.
set -euo pipefail
BASE=''; HEAD_REF=HEAD; RESULTS=''; TESTS=''; OUTPUT=''
RUNTIME=${AGENT_SOP_RUNTIME:-codex}
CHECK_LIB=false
# agent-sop library functions ship-sop calls: the first three here, the last two
# from /ship and $ship. The check is by name only. The oldest agent-sop known to
# provide all of them, with receipt schema version 2, is 0a1e5ee (P112,
# 2026-09-24); CI tests against that commit and against agent-sop main.
REQUIRED_SOP_FUNCTIONS='sop_effective_config sop_policy_digest sop_receipt_valid sop_agents_in_scope sop_changed_files_json'
MIN_AGENT_SOP='0a1e5ee (2026-09-24)'
while [ $# -gt 0 ]; do
    if [ "$1" = --check-lib ]; then CHECK_LIB=true; shift; continue; fi
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
[ -f "$LIB" ] || { echo "INCOMPLETE: agent-sop hooks not installed at $LIB; install agent-sop $MIN_AGENT_SOP or later" >&2; exit 1; }
# Load it once in a throwaway shell so a broken library is reported, not fatal.
if ! load_error=$(bash -euo pipefail -c '. "$1"' _ "$LIB" 2>&1); then
    echo "INCOMPLETE: $LIB failed to load; reinstall agent-sop $MIN_AGENT_SOP or later${load_error:+: $load_error}" >&2
    exit 1
fi
# shellcheck disable=SC1090
. "$LIB"
missing=''
for fn in $REQUIRED_SOP_FUNCTIONS; do declare -F "$fn" >/dev/null || missing="$missing $fn"; done
if [ -n "$missing" ]; then
    echo "INCOMPLETE: installed agent-sop is older than ship-sop needs (missing:$missing); update to agent-sop $MIN_AGENT_SOP or later" >&2
    exit 1
fi
if [ "$CHECK_LIB" = true ]; then echo "agent-sop library at $LIB provides every function ship-sop needs"; exit 0; fi
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

# Under Codex, every reviewer entry must match a run that scripts/codex-review.sh
# recorded in .ship/reviews/ (P38): same reviewer, commit and base, a clean exit,
# no timeout, and the same final verdict. Claude subagents leave no such record.
# The session can write .ship/ too, so this raises the cost of a false receipt
# rather than preventing one.
evidence_matches() { # name verdict
    local meta dir last rc
    for meta in "$ROOT"/.ship/reviews/*-"$1".*/metadata.json; do
        [ -f "$meta" ] || continue
        dir=$(dirname "$meta")
        # The record must be this repository's own, not a link to another clone.
        [ "$(cd "$dir" 2>/dev/null && pwd -P)" = "$REVIEWS_DIR/$(basename "$dir")" ] || continue
        rc=0
        jq -e --arg a "$1" --arg h "$HEAD_SHA" --arg b "$BASE" \
            '.agent == $a and .head == $h and .base == $b and .exit_code == 0 and .timed_out == false' \
            "$meta" >/dev/null 2>&1 || rc=$?
        if [ "$rc" -ge 2 ]; then echo "warn: unreadable run record $meta" >&2; fi
        [ "$rc" = 0 ] || continue
        [ -f "$dir/result.md" ] || continue
        # As the runner requires: exactly one verdict line, and it is the last.
        [ "$(grep -Ec '^Verdict: (PASS|BLOCK|INCOMPLETE)[[:space:]]*$' "$dir/result.md")" = 1 ] || continue
        last=$(awk 'NF { line = $0 } END { sub(/[[:space:]]+$/, "", line); print line }' "$dir/result.md")
        [ "$last" = "Verdict: $2" ] && return 0
    done
    return 1
}
if [ "$RUNTIME" = codex ]; then
    jq -e 'length > 0 and all(.[]; type == "object" and (.name | type) == "string" and (.verdict | type) == "string")' \
        "$RESULTS" >/dev/null 2>&1 || { echo 'INCOMPLETE: results must list at least one reviewer, each with a string name and verdict' >&2; exit 1; }
    rows=$(jq -r '.[] | [.name, .verdict] | @tsv' "$RESULTS") || { echo 'INCOMPLETE: cannot read reviewer results' >&2; exit 1; }
    REVIEWS_DIR="$(cd "$ROOT" && pwd -P)/.ship/reviews"
    unmatched=''
    while IFS=$'\t' read -r name verdict; do
        [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "INCOMPLETE: invalid reviewer name in results: $name" >&2; exit 1; }
        evidence_matches "$name" "$verdict" || unmatched="$unmatched $name"
    done <<< "$rows"
    if [ -n "$unmatched" ]; then
        echo "INCOMPLETE: no Codex runner evidence in .ship/reviews/ matches${unmatched} at $HEAD_SHA (base $BASE) with the same verdict; run the reviewer with codex-review.sh, or no receipt is written" >&2
        exit 1
    fi
fi
TREE=$(git rev-parse "$HEAD_SHA^{tree}")
mkdir -p "$(dirname "$OUTPUT")"
TMP=$(mktemp "${OUTPUT}.XXXXXX")
trap 'rm -f "$TMP"' EXIT
jq -n --arg base "$BASE" --arg head "$HEAD_SHA" --arg tree "$TREE" \
    --arg policy "$(sop_policy_digest "$CONFIG")" \
    --slurpfile results "$RESULTS" --slurpfile tests "$TESTS" \
    '{schema_version:2,base:$base,head:$head,tree:$tree,policy_sha256:$policy,
      tests:$tests[0],reviewers:$results[0]}' > "$TMP"
if ! sop_receipt_valid "$ROOT" "$TMP"; then
    echo 'BLOCK/INCOMPLETE: results, tests, policy or review range do not qualify; no receipt written' >&2
    exit 1
fi
# Hard-link creation refuses races with another writer choosing the same output.
ln "$TMP" "$OUTPUT"
printf 'PASS: validated receipt %s for %s\n' "$OUTPUT" "$HEAD_SHA"
