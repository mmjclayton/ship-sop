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
grep -q '^| alpha | 4 | 3 | 2 | 2 | 5 | 2 | 0 | 1 | 1 | 2 | 1 |$' "$WORK/table"
printf 'PASS: table output\n'

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
printf 'PASS: differing copies are reported\n'

if bash "$SOURCE/scripts/receipt-totals.sh" "$WORK/missing" 2>/dev/null; then echo 'FAIL: missing root accepted'; exit 1; fi
if bash "$SOURCE/scripts/receipt-totals.sh" 2>/dev/null; then echo 'FAIL: no roots accepted'; exit 1; fi
printf 'PASS: bad arguments refused\n'
