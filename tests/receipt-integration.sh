#!/usr/bin/env bash
# Receipt assembly against the real library. SOP_LIB may name another sop-lib.sh
# (tests/receipt-contract.sh passes a stub); the default is the one ship-sop ships.
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")/.." && pwd)
SOP_LIB=${SOP_LIB:-$SOURCE/scripts/hooks/sop-lib.sh}
[ -f "$SOP_LIB" ] || { echo "FAIL: no library at $SOP_LIB"; exit 1; }
WORK=$(mktemp -d)
SUITE_DONE=0
suite_trap() { local rc=$?; [ "$SUITE_DONE" = 1 ] || { echo "FAIL: suite stopped before its last check" >&2; rc=1; }; rm -rf "$WORK"; exit "$rc"; }
trap suite_trap EXIT
unset SHIP_SOP_USER_HOME SHIP_SOP_RUNTIME SHIP_SOP_CONFIG_HOME
export CODEX_HOME="$WORK/codex"
mkdir -p "$CODEX_HOME/scripts/hooks/ship-sop"
cp "$SOP_LIB" "$CODEX_HOME/scripts/hooks/ship-sop/sop-lib.sh"
git init -q -b main "$WORK/repo"
cd "$WORK/repo"
git config user.name Test
git config user.email test@example.invalid
printf '**Project type:** code\n' > AGENTS.md
cp "$SOURCE/docs/templates/ship-sop.config.json" ship-sop.config.json
printf 'base\n' > code.sh
git add .; git commit -qm base
BASE=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$BASE"
printf 'change\n' >> code.sh
git commit -qam change
jq '[.agents | to_entries[] | select(.value.enabled) |
  {name:.key,version:"fixture-v1",model:"fixture",verdict:"PASS",findings:[],launches:1,rechecks:0,block_rounds:0,usage:null}]' ship-sop.config.json > "$WORK/results.json"
printf '{"status":"PASS","evidence":"integration fixture"}\n' > "$WORK/tests.json"
run_receipt() {
    bash "$SOURCE/scripts/ship-receipt.sh" --base "$BASE" --results "$WORK/results.json" \
      --tests "$WORK/tests.json" --output "$1"
}
# Runner evidence in the shape scripts/codex-review.sh writes (P38): a
# <stamp>-<agent>.XXXXXX directory with metadata.json and result.md. Keep this in
# step with the runner.
evidence() { # agent verdict-text head [exit_code] [timed_out] [base] [agent-in-metadata]
    local dir
    mkdir -p .ship/reviews
    dir=$(mktemp -d ".ship/reviews/20261010T000000Z-$1.XXXXXX")
    jq -n --arg a "${7:-$1}" --arg h "$3" --arg b "${6:-$BASE}" --argjson e "${4:-0}" --argjson t "${5:-false}" \
        '{agent:$a,head:$h,base:$b,exit_code:$e,timed_out:$t}' > "$dir/metadata.json"
    printf 'Findings: none\n\n%s\n' "$2" > "$dir/result.md"
    printf '%s\n' "$dir"
}
clear_security() { rm -rf .ship/reviews/*-security-reviewer.*; }
refused() { # output reason-pattern
    if run_receipt "$1" 2> "$WORK/refusal"; then echo "FAIL: $1 written without matching evidence"; exit 1; fi
    grep -q "$2" "$WORK/refusal" || { echo "FAIL: $1 refused for the wrong reason:"; cat "$WORK/refusal"; exit 1; }
    test ! -e "$1"
}
HEAD_SHA=$(git rev-parse HEAD)
refused docs/reviews/no-evidence-ship-auto.json 'no Codex runner evidence'
evidence code-reviewer 'Verdict: PASS' "$HEAD_SHA" >/dev/null
evidence silent-failure-hunter 'Verdict: PASS' "$HEAD_SHA" >/dev/null
# Each condition alone makes the security-reviewer record not count.
case_refused() { # label evidence-args...
    clear_security; evidence security-reviewer "${@:2}" >/dev/null
    refused "docs/reviews/$1-ship-auto.json" 'security-reviewer'
}
case_refused verdict-mismatch 'Verdict: BLOCK' "$HEAD_SHA"
case_refused other-head 'Verdict: PASS' "$BASE"
case_refused other-base 'Verdict: PASS' "$HEAD_SHA" 0 false 0000000000000000000000000000000000000000
case_refused exit-code 'Verdict: PASS' "$HEAD_SHA" 1 false
case_refused timed-out 'Verdict: PASS' "$HEAD_SHA" 0 true
case_refused other-agent 'Verdict: PASS' "$HEAD_SHA" 0 false "$BASE" code-reviewer
case_refused two-verdicts $'Verdict: BLOCK\nVerdict: PASS' "$HEAD_SHA"
clear_security; d=$(evidence security-reviewer 'Verdict: PASS' "$HEAD_SHA"); printf '{not json\n' > "$d/metadata.json"
refused docs/reviews/corrupt-meta-ship-auto.json 'security-reviewer'
grep -q 'unreadable run record' "$WORK/refusal"
clear_security; d=$(evidence security-reviewer 'Verdict: PASS' "$HEAD_SHA")
mkdir -p "$WORK/other-clone"; mv "$d" "$WORK/other-clone/rec"; ln -s "$WORK/other-clone/rec" "$d"
refused docs/reviews/linked-record-ship-auto.json 'security-reviewer'
clear_security
cp "$WORK/results.json" "$WORK/results-kept.json"
jq '.[0].name = "../x"' "$WORK/results-kept.json" > "$WORK/results.json"
refused docs/reviews/bad-name-ship-auto.json 'invalid reviewer name'
for bad in '[]' '[1]' '[{"name":"code-reviewer"}]'; do
    printf '%s\n' "$bad" > "$WORK/results.json"
    refused docs/reviews/malformed-ship-auto.json 'at least one reviewer'
done
cp "$WORK/results-kept.json" "$WORK/results.json"
# A genuine record qualifies, trailing whitespace on the verdict line included.
evidence security-reviewer 'Verdict: PASS   ' "$HEAD_SHA" >/dev/null
run_receipt docs/reviews/valid-ship-auto.json
# Codex usage may be null (codex-usage.sh prints null when telemetry is missing),
# so P45's usage rule does not apply there.
jq -e 'all(.reviewers[]; .usage == null) and (has("usage_note") | not) and .bypasses == []' docs/reviews/valid-ship-auto.json >/dev/null \
    || { echo 'FAIL: Codex receipt with null usage not written as before'; exit 1; }
. "$CODEX_HOME/scripts/hooks/ship-sop/sop-lib.sh"
sop_shipsop_covered "$PWD" "$(git rev-parse HEAD)"
if run_receipt docs/reviews/valid-ship-auto.json 2>/dev/null; then echo 'FAIL: overwrote evidence'; exit 1; fi
cp "$WORK/tests.json" "$WORK/tests-original.json"
printf '{"status":"FAIL","evidence":"later failure"}\n' >> "$WORK/tests.json"
if run_receipt docs/reviews/multidoc-ship-auto.json 2>/dev/null; then echo 'FAIL: discarded later test result'; exit 1; fi
cp "$WORK/tests-original.json" "$WORK/tests.json"
cp "$WORK/results.json" "$WORK/results-original.json"
cat "$WORK/results-original.json" >> "$WORK/results.json"
if run_receipt docs/reviews/multiresults-ship-auto.json 2>/dev/null; then echo 'FAIL: discarded later reviewer result'; exit 1; fi
cp "$WORK/results-original.json" "$WORK/results.json"
cp ship-sop.config.json "$CODEX_HOME/ship-sop.config.json"
mv ship-sop.config.json "$WORK/config.saved"
run_receipt docs/reviews/fallback-ship-auto.json
mv "$WORK/config.saved" ship-sop.config.json
jq 'map(del(.launches))' "$WORK/results-original.json" > "$WORK/results.json"
if run_receipt docs/reviews/uncounted-ship-auto.json 2>/dev/null; then echo 'FAIL: wrote a version-2 receipt without run counts'; exit 1; fi
cp "$WORK/results-original.json" "$WORK/results.json"
jq '.[0].verdict="BLOCK"'  "$WORK/results.json" > "$WORK/blocked.json"
mv "$WORK/blocked.json" "$WORK/results.json"
if run_receipt docs/reviews/blocked-ship-auto.json 2>/dev/null; then echo 'FAIL: wrote blocked receipt'; exit 1; fi
test ! -e docs/reviews/blocked-ship-auto.json
# Reviewer scope by path (P33): the template scopes security-reviewer, so a
# TypeScript-only range needs no security result, while the shell range above
# (code.sh) did. A receipt lacking an in-scope reviewer is still refused.
git checkout -q -b scoped "$BASE"
printf 'export const x = 1\n' > lib.ts
git add lib.ts; git commit -qm 'feat: ts only'
evidence code-reviewer 'Verdict: PASS' "$(git rev-parse HEAD)" >/dev/null
evidence silent-failure-hunter 'Verdict: PASS' "$(git rev-parse HEAD)" >/dev/null
sop_agents_in_scope ship-sop.config.json "$(sop_changed_files_json . "$BASE" HEAD)" | jq -e 'map(.key) | index("security-reviewer") == null and index("code-reviewer") != null' >/dev/null || { echo 'FAIL: scope rule did not exclude the scoped reviewer on a ts-only range'; exit 1; }
sop_agents_in_scope ship-sop.config.json "$(sop_changed_files_json . "$BASE" "$(git rev-parse main)")" | jq -e 'map(.key) | index("security-reviewer") != null' >/dev/null || { echo 'FAIL: scope rule did not include the scoped reviewer on the shell range'; exit 1; }
jq 'map(select(.name != "security-reviewer"))' "$WORK/results-original.json" > "$WORK/results.json"
run_receipt docs/reviews/scoped-ship-auto.json
jq 'map(select(.name != "code-reviewer"))' "$WORK/results-original.json" > "$WORK/results.json"
if run_receipt docs/reviews/scoped-missing-ship-auto.json 2>/dev/null; then echo 'FAIL: accepted a receipt missing an in-scope reviewer'; exit 1; fi
test ! -e docs/reviews/scoped-missing-ship-auto.json
# Claude subagents leave no runner evidence; that runtime is unchanged.
mkdir -p "$WORK/user/.claude/scripts/hooks/ship-sop"
cp "$SOP_LIB" "$WORK/user/.claude/scripts/hooks/ship-sop/sop-lib.sh"
rm -rf .ship/reviews
jq 'map(select(.name != "security-reviewer"))' "$WORK/results-original.json" > "$WORK/results.json"
# P45: null usage under Claude is refused without --usage-unavailable, and the
# reason is stored as usage_note with it.
if SHIP_SOP_USER_HOME="$WORK/user" bash "$SOURCE/scripts/ship-receipt.sh" --runtime claude --base "$BASE" \
    --results "$WORK/results.json" --tests "$WORK/tests.json" --output docs/reviews/claude-ship-auto.json 2> "$WORK/usage.err"; then
    echo 'FAIL: wrote a Claude receipt with null usage and no --usage-unavailable'; exit 1
fi
grep 'no usage for:' "$WORK/usage.err" | grep 'code-reviewer' | grep -q 'silent-failure-hunter' || { echo 'FAIL: null-usage refusal did not name the reviewers'; cat "$WORK/usage.err"; exit 1; }
test ! -e docs/reviews/claude-ship-auto.json
jq 'map(del(.usage))' "$WORK/results.json" > "$WORK/results-nousage.json"
if SHIP_SOP_USER_HOME="$WORK/user" bash "$SOURCE/scripts/ship-receipt.sh" --runtime claude --base "$BASE" \
    --results "$WORK/results-nousage.json" --tests "$WORK/tests.json" --output docs/reviews/claude-ship-auto.json 2>/dev/null; then
    echo 'FAIL: wrote a Claude receipt with absent usage'; exit 1
fi
if SHIP_SOP_USER_HOME="$WORK/user" bash "$SOURCE/scripts/ship-receipt.sh" --runtime claude --base "$BASE" --usage-unavailable '  ' \
    --results "$WORK/results.json" --tests "$WORK/tests.json" --output docs/reviews/claude-ship-auto.json 2>/dev/null; then
    echo 'FAIL: accepted a blank --usage-unavailable reason'; exit 1
fi
SHIP_SOP_USER_HOME="$WORK/user" bash "$SOURCE/scripts/ship-receipt.sh" --runtime claude --base "$BASE" \
    --usage-unavailable 'notifications were lost when the session compacted' \
    --results "$WORK/results.json" --tests "$WORK/tests.json" --output docs/reviews/claude-ship-auto.json
jq -e '.usage_note == "notifications were lost when the session compacted"' docs/reviews/claude-ship-auto.json >/dev/null \
    || { echo 'FAIL: usage_note not stored'; exit 1; }
# P45: the tool records the bypass listing itself; no log means [].
jq -e '.bypasses == []' docs/reviews/claude-ship-auto.json >/dev/null || { echo 'FAIL: no bypasses not recorded as []'; exit 1; }
jq -e '.written_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' docs/reviews/claude-ship-auto.json >/dev/null \
    || { echo 'FAIL: receipt has no UTC written_at'; exit 1; }
jq -e 'has("block_tests") | not' docs/reviews/claude-ship-auto.json >/dev/null || { echo 'FAIL: block_tests added without --block-tests'; exit 1; }
# P44: Claude usage from task notifications; the tool adds the totals from the runs.
claude_receipt() { # output [extra args...]
    local out=$1; shift
    SHIP_SOP_USER_HOME="$WORK/user" bash "$SOURCE/scripts/ship-receipt.sh" --runtime claude --base "$BASE" \
        --results "$WORK/results.json" --tests "$WORK/tests.json" --output "$out" "$@"
}
# One launch and two re-checks of one agent instance: subagent_tokens is
# cumulative (the last figure, 2000, counts, not the sum), duration_ms is per run.
jq 'map(select(.name != "security-reviewer") | .rechecks = 2 | .block_rounds = 1
      | .usage = {source: "claude-task-notification", runs: [{instance: 1, tokens: 1200, duration_ms: 3000},
          {instance: 1, tokens: 1800, duration_ms: 600}, {instance: 1, tokens: 2000, duration_ms: 400}]})' \
    "$WORK/results-original.json" > "$WORK/results.json"
printf '[{"commit":"%s","result":"PASS","evidence":"bash tests/run.sh: 4 passed"}]\n' "$(git rev-parse HEAD)" > "$WORK/block-tests.json"
claude_receipt docs/reviews/usage-ship-auto.json --block-tests "$WORK/block-tests.json" 2> "$WORK/usage.err"
jq -e 'all(.reviewers[]; .usage.tokens.total_tokens == 2000 and .usage.duration_ms == 4000)
       and .block_tests == [{"commit": .head, "result": "PASS", "evidence": "bash tests/run.sh: 4 passed"}]' \
    docs/reviews/usage-ship-auto.json >/dev/null || { echo 'FAIL: usage totals or block_tests not recorded'; cat docs/reviews/usage-ship-auto.json; exit 1; }
if grep -q 'no --block-tests' "$WORK/usage.err"; then echo 'FAIL: complained about block tests that were given'; exit 1; fi
# A block round without block tests is refused (P44 review); an explicit empty
# array is accepted (the companion report gives the reason).
if claude_receipt docs/reviews/no-block-tests-ship-auto.json 2> "$WORK/usage.err"; then echo 'FAIL: wrote a blocked receipt without block tests'; exit 1; fi
grep -q 'no --block-tests file was given' "$WORK/usage.err" || { echo 'FAIL: refusal did not name the missing block tests'; exit 1; }
test ! -e docs/reviews/no-block-tests-ship-auto.json
printf '[]\n' > "$WORK/block-tests.json"
claude_receipt docs/reviews/empty-block-tests-ship-auto.json --block-tests "$WORK/block-tests.json" >/dev/null
jq -e '.block_tests == []' docs/reviews/empty-block-tests-ship-auto.json >/dev/null || { echo 'FAIL: empty block tests not recorded'; exit 1; }
for bad in '{"commit":"x"}' 'not json' '[] []'; do
    printf '%s\n' "$bad" > "$WORK/block-tests.json"
    if claude_receipt docs/reviews/bad-block-tests-ship-auto.json --block-tests "$WORK/block-tests.json" 2>/dev/null; then
        echo "FAIL: accepted block tests: $bad"; exit 1
    fi
    test ! -e docs/reviews/bad-block-tests-ship-auto.json
done
if claude_receipt docs/reviews/missing-block-tests-ship-auto.json --block-tests "$WORK/none.json" 2>/dev/null; then echo 'FAIL: accepted a missing block tests file'; exit 1; fi
# P45: with every usage present the receipt carries no usage_note, and the
# flag is refused because there is nothing for it to explain.
jq -e 'has("usage_note") | not' docs/reviews/usage-ship-auto.json >/dev/null || { echo 'FAIL: usage_note added without the flag'; exit 1; }
printf '[]\n' > "$WORK/block-tests.json"
if claude_receipt docs/reviews/needless-note-ship-auto.json --block-tests "$WORK/block-tests.json" --usage-unavailable 'x' 2> "$WORK/usage.err"; then
    echo 'FAIL: accepted --usage-unavailable with every usage present'; exit 1
fi
grep -q 'every reviewer has usage' "$WORK/usage.err" || { echo 'FAIL: needless-flag refusal gave the wrong reason'; cat "$WORK/usage.err"; exit 1; }
# P45: bypass-log entries are stored as strings, one per entry.
mkdir -p .ship
printf '%s\n' '2026-10-12T01:00:00Z aaa1111 git push origin feat' '2026-10-12T02:00:00Z bbb2222 git push origin feat' > .ship/bypass.log
claude_receipt docs/reviews/bypasses-ship-auto.json --block-tests "$WORK/block-tests.json" >/dev/null
jq -e '.bypasses == ["2026-10-12T01:00:00Z aaa1111 git push origin feat", "2026-10-12T02:00:00Z bbb2222 git push origin feat"]' \
    docs/reviews/bypasses-ship-auto.json >/dev/null || { echo 'FAIL: bypass entries not stored'; jq .bypasses docs/reviews/bypasses-ship-auto.json; exit 1; }
# An unreadable log is stored as the listing's own "unreadable: ..." line.
rm -f .ship/bypass.log; mkdir .ship/bypass.log
claude_receipt docs/reviews/unreadable-bypasses-ship-auto.json --block-tests "$WORK/block-tests.json" >/dev/null
jq -e '.bypasses | length == 1 and (.[0] | startswith("unreadable: "))' docs/reviews/unreadable-bypasses-ship-auto.json >/dev/null \
    || { echo 'FAIL: unreadable listing not stored as its string'; exit 1; }
rmdir .ship/bypass.log
# A listing that fails or prints nothing is INCOMPLETE: no receipt.
USER_LIB="$WORK/user/.claude/scripts/hooks/ship-sop/sop-lib.sh"
cp "$USER_LIB" "$WORK/lib.saved"
for broken in 'sop_bypasses_since_receipt() { return 0; }' 'sop_bypasses_since_receipt() { echo none; return 3; }'; do
    cp "$WORK/lib.saved" "$USER_LIB"; printf '%s\n' "$broken" >> "$USER_LIB"
    if claude_receipt docs/reviews/no-listing-ship-auto.json --block-tests "$WORK/block-tests.json" 2> "$WORK/usage.err"; then
        echo "FAIL: wrote a receipt when the listing failed: $broken"; exit 1
    fi
    grep -q 'INCOMPLETE: the bypass listing failed' "$WORK/usage.err" || { echo 'FAIL: listing refusal gave the wrong reason'; cat "$WORK/usage.err"; exit 1; }
    test ! -e docs/reviews/no-listing-ship-auto.json
done
cp "$WORK/lib.saved" "$USER_LIB"
echo 'PASS: Claude usage is required unless --usage-unavailable gives a reason; the tool records the bypass listing and refuses without one'
echo 'PASS: receipts record written_at, Claude usage totals from the runs, and block tests'
echo 'PASS: real receipts qualify, reject BLOCK, preserve existing evidence, honour reviewer scope and require run counts'
echo 'PASS: Codex receipts need matching runner evidence (commit, base, clean exit, verdict); Claude unchanged'

SUITE_DONE=1
