#!/usr/bin/env bash
# P43: the impact rule that decides CRITICAL/HIGH is the same sentence block for
# Claude (/ship tells reviewers) and Codex (codex-review.sh puts it in the prompt).
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")/.." && pwd)
claude=$(grep -o 'Severity rule for this gate:.*threshold\.' "$SOURCE/.claude/commands/ship.md")
codex=$(grep -o "Severity rule for this gate:.*threshold\." "$SOURCE/scripts/codex-review.sh")
[ -n "$claude" ] || { echo 'FAIL: /ship carries no severity rule'; exit 1; }
[ "$claude" = "$codex" ] || { echo 'FAIL: /ship and codex-review.sh carry different severity rules'; exit 1; }
grep -q -- '--block-on <block_on>' "$SOURCE/.agents/skills/ship/SKILL.md" || { echo 'FAIL: the Codex skill does not pass each threshold'; exit 1; }
grep -q "only these block" "$SOURCE/.claude/commands/ship.md" || { echo 'FAIL: /ship does not limit blocking to the threshold'; exit 1; }
printf 'PASS: Claude and Codex share one severity rule, and only threshold findings block\n'
