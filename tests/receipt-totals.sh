#!/usr/bin/env bash
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
reviewer() { # name launches rechecks block_rounds severities...
    local name=$1 l=$2 r=$3 b=$4; shift 4
    jq -n --arg n "$name" --argjson l "$l" --argjson r "$r" --argjson b "$b" --args \
        '{name:$n,verdict:"PASS",launches:$l,rechecks:$r,block_rounds:$b,
          findings:[$ARGS.positional[] | {severity:., file:"a.sh", line:1, message:"m"}]}' "$@"
}
receipt() { # dir file head schema reviewers-json
    mkdir -p "$1/docs/reviews"
    jq -n --arg h "$3" --argjson s "$4" --argjson r "$5" \
        '{schema_version:$s,base:"b",head:$h,tree:"t",policy_sha256:"p",tests:{status:"PASS",evidence:"x"},reviewers:$r}' \
        > "$1/docs/reviews/$2-ship-auto.json"
}
receipt "$WORK/alpha" 20260101-000000 h1 2 "[$(reviewer code 1 2 1 LOW INFO), $(reviewer sec 1 0 0)]"
receipt "$WORK/alpha" 20260102-000000 h2 2 "[$(reviewer code 1 0 0 MEDIUM)]"
receipt "$WORK/alpha" 20250101-000000 h0 1 "[$(reviewer code 1 0 0 LOW)]"
mkdir -p "$WORK/alpha-clone/docs/reviews"
cp "$WORK/alpha/docs/reviews/20260101-000000-ship-auto.json" "$WORK/alpha-clone/docs/reviews/"
receipt "$WORK/alpha" 20260104-000000 h4 3 "[$(reviewer code 2 0 1 HIGH)]"

bash "$SOURCE/scripts/receipt-totals.sh" --json "$WORK/alpha" "$WORK/alpha-clone" > "$WORK/out.json" 2> "$WORK/err"
jq -e 'length == 1 and .[0].project == "alpha"' "$WORK/out.json" >/dev/null
jq -e '.[0] | .receipts == 4 and .schema_v2 == 3 and .gates_that_blocked == 2
    and .block_rounds == 2 and .launches == 5 and .rechecks == 2
    and .findings == {"HIGH":1,"INFO":1,"LOW":2,"MEDIUM":1}' "$WORK/out.json" >/dev/null
printf 'PASS: totals dedupe clones, count v2 and later runs, count findings\n'

bash "$SOURCE/scripts/receipt-totals.sh" "$WORK/alpha" > "$WORK/table" 2>/dev/null
grep -q '^| alpha | 4 | 3 | 2 | 2 | 5 | 2 | 0 | 1 | 1 | 2 | 1 | 0 | n/a | n/a | 0 / 0 / 0 / 2 | 0 / 4 | 0 | n/a | n/a |$' "$WORK/table" \
    || { echo 'FAIL: alpha table row'; cat "$WORK/table"; exit 1; }
# No costed change: tokens and minutes are unknown, not 0; two blocked changes lack block tests.
jq -e '.[0] | .tokens == null and .reviewer_minutes == null and .tokens_by_source == {} and .blocked_without_block_tests == 2' "$WORK/out.json" >/dev/null \
    || { echo 'FAIL: uncosted totals or no-record count'; cat "$WORK/out.json"; exit 1; }
printf 'PASS: table output\n'

# Cost and test-catch (P44). A change's tokens and minutes count only when every
# reviewer in it has usage; Claude and Codex shapes are both read; block_tests
# results are counted.
claude_usage() { # tokens duration_ms
    jq -n --argjson t "$1" --argjson d "$2" \
        '{source:"claude-task-notification",runs:[{instance:1,tokens:$t,duration_ms:$d}],tokens:{total_tokens:$t},duration_ms:$d}'
}
codex_usage='{"source":"codex-review","runs":1,"turns":2,"elapsed_seconds":60,"tokens":{"input_tokens":1000,"cached_input_tokens":400,"output_tokens":200},"evidence":["x"]}'
with_usage() { jq --argjson u "$2" '. + {usage: $u}' <<< "$1"; }
receipt "$WORK/gamma" 20261013-000000 g1 2 "[$(with_usage "$(reviewer code 1 1 1 INFO)" "$(claude_usage 30000 120000)"), $(with_usage "$(reviewer sec 1 0 0)" "$codex_usage")]"
jq '. + {block_tests: [{commit:"c", result:"PASS", evidence:"npm test passed"}]}' "$WORK/gamma/docs/reviews/20261013-000000-ship-auto.json" > "$WORK/g.json"
mv "$WORK/g.json" "$WORK/gamma/docs/reviews/20261013-000000-ship-auto.json"
receipt "$WORK/gamma" 20261014-000000 g2 2 "[$(with_usage "$(reviewer code 1 0 0)" "$(claude_usage 10000 60000)")]"
# One reviewer without usage: the change has no cost figure, not a partial one.
receipt "$WORK/gamma" 20261015-000000 g3 2 "[$(with_usage "$(reviewer code 2 1 2)" "$(claude_usage 50000 60000)"), $(with_usage "$(reviewer sec 1 0 0)" null)]"
jq '. + {block_tests: [{commit:"c", result:"FAIL", evidence:"1 failing"}, {commit:"d", result:"NOT_AVAILABLE", evidence:"no suite"}]}' "$WORK/gamma/docs/reviews/20261015-000000-ship-auto.json" > "$WORK/g.json"
mv "$WORK/g.json" "$WORK/gamma/docs/reviews/20261015-000000-ship-auto.json"
# A malformed usage object is unknown, not a crash or a skipped receipt.
receipt "$WORK/gamma" 20261016-000000 g4 2 "[$(with_usage "$(reviewer code 1 0 0)" '{"source":"claude-task-notification","tokens":"lots"}')]"
bash "$SOURCE/scripts/receipt-totals.sh" --json "$WORK/gamma" > "$WORK/cost.json"
jq -e '.[0] | .receipts == 4 and .changes_with_usage == 2 and .tokens == 41200 and .reviewer_minutes == 4
    and .tokens_by_source == {"claude-task-notification": 40000, "codex-review": 1200}
    and .per_change.reviewer_minutes_min == 1 and .per_change.reviewer_minutes_max == 3
    and .blocked_without_block_tests == 0
    and .per_change.tokens_median == 20600 and .per_change.tokens_min == 10000 and .per_change.tokens_max == 31200
    and .per_change.block_rounds_median == 0.5 and .per_change.block_rounds_max == 2
    and .block_tests == {"PASS":1,"FAIL":1,"NOT_AVAILABLE":1}
    and ([.changes[] | select(.head == "g3")][0] | .tokens == null and .reviewer_minutes == null and .block_rounds == 2)
    and ([.changes[] | select(.head == "g1")][0] | .tokens == 31200 and .reviewer_minutes == 3)' "$WORK/cost.json" >/dev/null \
    || { echo 'FAIL: cost and test-catch totals'; cat "$WORK/cost.json"; exit 1; }
bash "$SOURCE/scripts/receipt-totals.sh" "$WORK/gamma" > "$WORK/table"
grep -q '^| gamma | 4 | 4 | 2 | 3 | 7 | 2 | 0 | 0 | 0 | 0 | 1 | 2 | 41200 | 4 | 1 / 1 / 1 / 0 | 0 / 4 | 0 | n/a | n/a |$' "$WORK/table" \
    || { echo 'FAIL: cost table row'; cat "$WORK/table"; exit 1; }
printf 'PASS: tokens, reviewer minutes and block-test results per change and in total\n'

# Runs without totals: one launch and two re-checks of one instance report
# cumulative tokens (the last counts, not the sum); a second launch adds its own.
receipt "$WORK/delta" 20261017-000000 d1 2 "[$(with_usage "$(reviewer code 2 2 0)" '{"source":"claude-task-notification","runs":[
  {"instance":1,"tokens":116735,"duration_ms":35522},{"instance":1,"tokens":123830,"duration_ms":16202},
  {"instance":1,"tokens":125807,"duration_ms":5082},{"instance":2,"tokens":78636,"duration_ms":3194}]}')]"
bash "$SOURCE/scripts/receipt-totals.sh" --json "$WORK/delta" > "$WORK/delta.json"
jq -e '.[0].tokens == 204443 and .[0].changes[0].reviewer_minutes == 1' "$WORK/delta.json" >/dev/null \
    || { echo 'FAIL: cumulative tokens were summed, or durations were not'; cat "$WORK/delta.json"; exit 1; }
printf 'PASS: cumulative instance tokens count once; per-run durations add up\n'

# P45: receipts with a usage_note are counted; bypass entries are counted over
# receipts that carry the field, and an "unreadable:" listing separately.
receipt "$WORK/epsilon" 20261018-000000 e1 2 "[$(with_usage "$(reviewer code 1 0 0)" null)]"
jq '. + {usage_note: "notifications lost", bypasses: ["2026-10-18T01:00:00Z a git push", "2026-10-18T02:00:00Z b git push"]}' \
    "$WORK/epsilon/docs/reviews/20261018-000000-ship-auto.json" > "$WORK/e.json"
mv "$WORK/e.json" "$WORK/epsilon/docs/reviews/20261018-000000-ship-auto.json"
receipt "$WORK/epsilon" 20261019-000000 e2 2 "[$(with_usage "$(reviewer code 1 0 0)" "$(claude_usage 100 1000)")]"
jq '. + {bypasses: []}' "$WORK/epsilon/docs/reviews/20261019-000000-ship-auto.json" > "$WORK/e.json"
mv "$WORK/e.json" "$WORK/epsilon/docs/reviews/20261019-000000-ship-auto.json"
receipt "$WORK/epsilon" 20261020-000000 e3 2 "[$(with_usage "$(reviewer code 1 0 0)" "$(claude_usage 100 1000)")]"
jq '. + {bypasses: ["unreadable: /x/.ship/bypass.log"]}' "$WORK/epsilon/docs/reviews/20261020-000000-ship-auto.json" > "$WORK/e.json"
mv "$WORK/e.json" "$WORK/epsilon/docs/reviews/20261020-000000-ship-auto.json"
receipt "$WORK/epsilon" 20261021-000000 e4 2 "[$(with_usage "$(reviewer code 1 0 0)" "$(claude_usage 100 1000)")]"
bash "$SOURCE/scripts/receipt-totals.sh" --json "$WORK/epsilon" > "$WORK/eps.json"
jq -e '.[0] | .receipts == 4 and .receipts_with_usage_note == 1 and .receipts_with_bypass_record == 3
    and .bypasses == 2 and .unreadable_bypass_listings == 1 and .changes_with_usage == 3
    and ([.changes[] | select(.head == "e1")][0] | .usage_note == true and (.bypasses | length) == 2)' "$WORK/eps.json" >/dev/null \
    || { echo 'FAIL: usage-note and bypass counts'; cat "$WORK/eps.json"; exit 1; }
bash "$SOURCE/scripts/receipt-totals.sh" "$WORK/epsilon" > "$WORK/table"
grep -q '| 0 / 0 / 0 / 0 | 1 / 4 | 3 | 2 | 1 |$' "$WORK/table" || { echo 'FAIL: usage-note and bypass columns'; cat "$WORK/table"; exit 1; }
jq -e '.[0] | .bypasses == null and .unreadable_bypass_listings == null and .receipts_with_bypass_record == 0' "$WORK/out.json" >/dev/null \
    || { echo 'FAIL: bypass counts not null when no receipt carries the field'; exit 1; }
# Only an unreadable listing: one record, no bypasses, one unreadable. A hand-
# edited numeric entry is ignored rather than crashing the totals.
receipt "$WORK/zeta" 20261022-000000 z1 2 "[$(with_usage "$(reviewer code 1 0 0)" "$(claude_usage 100 1000)")]"
jq '. + {bypasses: ["unreadable: /x/.ship/bypass.log"]}' "$WORK/zeta/docs/reviews/20261022-000000-ship-auto.json" > "$WORK/z.json"
mv "$WORK/z.json" "$WORK/zeta/docs/reviews/20261022-000000-ship-auto.json"
bash "$SOURCE/scripts/receipt-totals.sh" "$WORK/zeta" > "$WORK/table"
grep -q '| 0 / 1 | 1 | 0 | 1 |$' "$WORK/table" || { echo 'FAIL: unreadable-only table row'; cat "$WORK/table"; exit 1; }
receipt "$WORK/eta" 20261023-000000 t1 2 "[$(with_usage "$(reviewer code 1 0 0)" "$(claude_usage 100 1000)")]"
jq '. + {bypasses: [1, "2026-10-23T01:00:00Z a git push", {"x": 1}]}' "$WORK/eta/docs/reviews/20261023-000000-ship-auto.json" > "$WORK/t.json"
mv "$WORK/t.json" "$WORK/eta/docs/reviews/20261023-000000-ship-auto.json"
bash "$SOURCE/scripts/receipt-totals.sh" --json "$WORK/eta" > "$WORK/eta.json" || { echo 'FAIL: totals crashed on a numeric bypasses entry'; exit 1; }
jq -e '.[0] | .receipts == 1 and .bypasses == 1 and .unreadable_bypass_listings == 0' "$WORK/eta.json" >/dev/null \
    || { echo 'FAIL: numeric bypasses entry miscounted'; cat "$WORK/eta.json"; exit 1; }
printf 'PASS: receipts with a usage note and recorded bypasses are counted; unreadable and hand-edited listings handled\n'

# Unreadable receipts and empty roots are reported and fail the run; the
# totals for the rest still print.
printf 'not json\n' > "$WORK/alpha/docs/reviews/20260103-000000-ship-auto.json"
receipt "$WORK/alpha" 20260105-000000 h5 2 '["not an object"]'
mkdir -p "$WORK/empty"
if bash "$SOURCE/scripts/receipt-totals.sh" "$WORK/alpha" "$WORK/empty" > "$WORK/partial" 2> "$WORK/err"; then
    echo 'FAIL: skipped files and an empty root exited 0'; exit 1
fi
[ "$(grep -c '^skip ' "$WORK/err")" = 2 ]
grep -q 'has no receipts' "$WORK/err"
grep -q '^| alpha | 4 |' "$WORK/partial"
printf 'PASS: unreadable receipts and empty roots are reported with a non-zero exit\n'

# A copy with the same key but different content is reported.
mkdir -p "$WORK/beta/docs/reviews"
jq '.reviewers[0].block_rounds = 0' "$WORK/alpha/docs/reviews/20260101-000000-ship-auto.json" > "$WORK/beta/docs/reviews/20260101-000000-ship-auto.json"
bash "$SOURCE/scripts/receipt-totals.sh" --json "$WORK/alpha-clone" "$WORK/beta" > /dev/null 2> "$WORK/err" || true
grep -q 'differs between' "$WORK/err"
rm -rf "$WORK/beta"; mkdir -p "$WORK/beta/docs/reviews"
jq '.schema_version = 3' "$WORK/alpha-clone/docs/reviews/20260101-000000-ship-auto.json" > "$WORK/beta/docs/reviews/20260101-000000-ship-auto.json"
bash "$SOURCE/scripts/receipt-totals.sh" --json "$WORK/alpha-clone" "$WORK/beta" > /dev/null 2> "$WORK/err" || true
grep -q 'differs between' "$WORK/err"
printf 'PASS: differing copies are reported\n'

if bash "$SOURCE/scripts/receipt-totals.sh" "$WORK/missing" 2>/dev/null; then echo 'FAIL: missing root accepted'; exit 1; fi
if bash "$SOURCE/scripts/receipt-totals.sh" 2>/dev/null; then echo 'FAIL: no roots accepted'; exit 1; fi
printf 'PASS: bad arguments refused\n'
