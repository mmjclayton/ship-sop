#!/usr/bin/env bash
# Assemble and validate a gate receipt from real reviewer and test results.
set -euo pipefail
#
# Optional --block-tests FILE (P44): a JSON array of {commit, result, evidence},
# one entry per blocked review round, recording the project's tests run at the
# blocked commit before its fix. It becomes the receipt's block_tests field.
# A Claude reviewer's usage may carry only its runs; the totals are added here
# from them, so nobody sums by hand. Every receipt records written_at (UTC).
BASE=''; HEAD_REF=HEAD; RESULTS=''; TESTS=''; OUTPUT=''; BLOCK_TESTS=''
RUNTIME=${SHIP_SOP_RUNTIME:-codex}
CHECK_LIB=false
# Functions of the installed push-gate library (scripts/hooks/sop-lib.sh) that
# ship-sop calls, here, from /ship and $ship, and from the push gate. This is the
# gate's own SOP_GATE_FUNCTIONS list, so --check-lib also answers "can the gate
# run?". The check is by name only; it catches a missing, broken or hand-edited
# install. tests/push-gate.sh keeps the two lists equal.
REQUIRED_SOP_FUNCTIONS='sop_have_jq sop_read_input sop_field sop_sha256 sop_repo_root sop_is_gated_repo
sop_instruction_file sop_claude_prose sop_type_from_file sop_declared_project_type sop_code_signals
sop_project_type sop_is_code_repo sop_default_branch sop_range_base sop_cmd_matches_push
sop_is_push_command sop_strip_heredocs sop_instruction_pattern sop_instructions_changed
sop_code_lines sop_effective_config sop_policy_valid sop_policy_digest sop_changed_files_json
sop_agents_in_scope sop_receipt_valid sop_shipsop_covered sop_shipsop_gate sop_bypasses_since_receipt'
REINSTALL='re-run ship-sop setup.sh for this project'
while [ $# -gt 0 ]; do
    if [ "$1" = --check-lib ]; then CHECK_LIB=true; shift; continue; fi
    [ $# -ge 2 ] || { echo 'Each option needs a value' >&2; exit 2; }
    case "$1" in
        --base) BASE=$2 ;; --head) HEAD_REF=$2 ;; --results) RESULTS=$2 ;;
        --tests) TESTS=$2 ;; --output) OUTPUT=$2 ;; --runtime) RUNTIME=$2 ;;
        --block-tests) BLOCK_TESTS=$2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift 2
done
case "$RUNTIME" in
    codex) CONFIG_HOME=${CODEX_HOME:-${SHIP_SOP_USER_HOME:-$HOME}/.codex} ;;
    claude) CONFIG_HOME=${SHIP_SOP_USER_HOME:-$HOME}/.claude ;;
    *) echo 'runtime must be claude or codex' >&2; exit 2 ;;
esac
export SHIP_SOP_RUNTIME="$RUNTIME" SHIP_SOP_CONFIG_HOME="$CONFIG_HOME"
LIB="$CONFIG_HOME/scripts/hooks/ship-sop/sop-lib.sh"
[ -f "$LIB" ] || { echo "INCOMPLETE: ship-sop push-gate library not installed at $LIB; $REINSTALL" >&2; exit 1; }
# Load it once in a throwaway shell so a broken library is reported, not fatal.
if ! load_error=$(bash -euo pipefail -c '. "$1"' _ "$LIB" 2>&1); then
    echo "INCOMPLETE: $LIB failed to load; $REINSTALL${load_error:+: $load_error}" >&2
    exit 1
fi
# shellcheck disable=SC1090
. "$LIB"
missing=''
for fn in $REQUIRED_SOP_FUNCTIONS; do declare -F "$fn" >/dev/null || missing="$missing $fn"; done
if [ -n "$missing" ]; then
    echo "INCOMPLETE: installed library at $LIB lacks functions ship-sop needs (missing:$missing); $REINSTALL" >&2
    exit 1
fi
if [ "$CHECK_LIB" = true ]; then echo "library at $LIB provides every function ship-sop needs"; exit 0; fi
ROOT=$(git rev-parse --show-toplevel)
[ -n "$BASE" ] && [ -f "$RESULTS" ] && [ -f "$TESTS" ] && [ -n "$OUTPUT" ] || {
    echo 'Required: --base REF --results reviewers.json --tests tests.json --output docs/reviews/STAMP-ship-auto.json [--block-tests block-tests.json]' >&2
    exit 2
}
case "$OUTPUT" in *-ship-auto.json) ;; *) echo 'Output must end in -ship-auto.json' >&2; exit 2 ;; esac
[ ! -e "$OUTPUT" ] || { echo 'Use a new receipt filename; existing evidence is immutable' >&2; exit 2; }
jq -se 'length == 1 and (.[0] | type == "array")' "$RESULTS" >/dev/null || { echo 'INCOMPLETE: results must contain one JSON array' >&2; exit 1; }
jq -se 'length == 1 and (.[0] | type == "object")' "$TESTS" >/dev/null || { echo 'INCOMPLETE: tests must contain one JSON object' >&2; exit 1; }
if [ -n "$BLOCK_TESTS" ]; then
    [ -f "$BLOCK_TESTS" ] && jq -se 'length == 1 and (.[0] | type == "array")' "$BLOCK_TESTS" >/dev/null 2>&1 \
        || { echo 'INCOMPLETE: --block-tests must name a file holding one JSON array' >&2; exit 1; }
fi
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
BLOCK_TESTS_JSON=null
[ -z "$BLOCK_TESTS" ] || BLOCK_TESTS_JSON=$(jq -c . "$BLOCK_TESTS")
# Claude usage totals are derived from the runs when every run carries both
# figures as numbers; anything else is left as given for the validator to judge.
jq -n --arg base "$BASE" --arg head "$HEAD_SHA" --arg tree "$TREE" \
    --arg policy "$(sop_policy_digest "$CONFIG")" --arg written "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --slurpfile results "$RESULTS" --slurpfile tests "$TESTS" --argjson block_tests "$BLOCK_TESTS_JSON" \
    'def totals: if type == "object" and .source == "claude-task-notification"
          and (.runs | type == "array" and length > 0 and all(.[]; type == "object" and (.tokens | type == "number") and (.duration_ms | type == "number")))
        then (if has("tokens") then . else . + {tokens: {total_tokens: ([.runs[].tokens] | add)}} end)
           | (if has("duration_ms") then . else . + {duration_ms: ([.runs[].duration_ms] | add)} end)
        else . end;
     {schema_version:2,base:$base,head:$head,tree:$tree,policy_sha256:$policy,written_at:$written,
      tests:$tests[0],
      reviewers:($results[0] | map(if type == "object" and has("usage") then .usage |= totals else . end))}
     + (if $block_tests == null then {} else {block_tests: $block_tests} end)' > "$TMP"
# A blocked round with no test result recorded loses the test-catch measure
# (P44); say so, without refusing a receipt the policy allows.
if [ -z "$BLOCK_TESTS" ] && jq -e 'any(.reviewers[]; (.block_rounds // 0) > 0)' "$TMP" >/dev/null 2>&1; then
    echo 'warn: a reviewer recorded a block round but no --block-tests file was given; the receipt will not show whether the tests caught it' >&2
fi
if ! sop_receipt_valid "$ROOT" "$TMP"; then
    echo 'BLOCK/INCOMPLETE: results, tests, policy or review range do not qualify; no receipt written' >&2
    exit 1
fi
# Hard-link creation refuses races with another writer choosing the same output.
ln "$TMP" "$OUTPUT"
printf 'PASS: validated receipt %s for %s\n' "$OUTPUT" "$HEAD_SHA"
