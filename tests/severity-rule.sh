#!/usr/bin/env bash
# P43: the impact rule that decides CRITICAL/HIGH is one sentence block for Claude
# (/ship gives it to reviewers) and Codex (codex-review.sh puts it in the prompt),
# and every place that steers a review hands reviewers their threshold.
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")/.." && pwd)
SHIP="$SOURCE/.claude/commands/ship.md"; SKILL="$SOURCE/.agents/skills/ship/SKILL.md"
RUNNER="$SOURCE/scripts/codex-review.sh"; LIB="$SOURCE/scripts/hooks/sop-lib.sh"
fail() { echo "FAIL: $1"; exit 1; }
claude=$(grep -o 'Severity rule for this gate:.*list the findings\.' "$SHIP") || fail '/ship carries no severity rule'
codex=$(grep -o 'Severity rule for this gate:.*list the findings\.' "$RUNNER") || fail 'codex-review.sh carries no severity rule'
[ "$claude" = "$codex" ] || fail '/ship and codex-review.sh carry different severity rules'
# The rule's substance, not just its equality.
for phrase in 'only when the finding has user or data impact' 'counts as user or data impact whether or not it has been exploited' 'do not lower its severity' 'a threshold of never means advisory'; do
    printf '%s' "$claude" | grep -qF "$phrase" || fail "severity rule lost: $phrase"
done
grep -qF 'Give each reviewer its `block_on` as its blocking threshold, and this rule verbatim' "$SHIP" || fail '/ship does not hand reviewers their threshold and the rule'
grep -qF 'only these block' "$SHIP" || fail '/ship does not limit blocking to the threshold'
grep -qF "finding at or above that reviewer's \`block_on\`" "$SHIP" || fail '/ship block_rounds not tied to the threshold'
grep -qF 'recorded as INFO with the fix' "$SHIP" || fail '/ship does not say how a fixed threshold finding is recorded'
grep -qF -- '--block-on <block_on>' "$SKILL" || fail 'the Codex skill does not pass each threshold'
grep -qF "Fix only findings at or above their reviewer's threshold" "$SKILL" || fail 'the Codex skill does not limit fixes to the threshold'
grep -qF "finding at or above that reviewer's block_on" "$SKILL" || fail 'the Codex skill block_rounds not tied to the threshold'
tr '\n' ' ' < "$SKILL" | tr -s ' ' | grep -qF 'Count a block round only when a finding met the threshold' || fail 'the Codex skill does not limit block rounds to the threshold'
grep -qF 'Record a fixed' "$SKILL" || fail 'the Codex skill does not say how a fixed threshold finding is recorded'
grep -qF -- 'each with --block-on set to its block_on' "$LIB" || fail 'the Codex push-gate demand does not ask for --block-on'
grep -qF 'give each reviewer its block_on above and the severity rule from /ship' "$LIB" || fail 'the Claude push-gate demand does not hand over the threshold'
printf 'PASS: Claude and Codex share one severity rule, every review path passes thresholds, and only threshold findings block\n'
