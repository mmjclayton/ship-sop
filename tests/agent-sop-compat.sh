#!/usr/bin/env bash
# ship-sop refuses an agent-sop library that lacks a function it calls, and says
# which one and which agent-sop version to install.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export AGENT_SOP_USER_HOME="$WORK/user"
LIB="$AGENT_SOP_USER_HOME/.claude/scripts/hooks/agent-sop/sop-lib.sh"
check() { bash "$SOURCE/scripts/ship-receipt.sh" --check-lib --runtime claude > "$WORK/out" 2>&1; }

if check; then echo 'FAIL: missing library accepted'; exit 1; fi
grep -q 'agent-sop hooks not installed' "$WORK/out"
grep -q '0a1e5ee' "$WORK/out"
printf 'PASS: missing library names the minimum agent-sop\n'

mkdir -p "$(dirname "$LIB")"
for fn in sop_effective_config sop_policy_digest sop_receipt_valid sop_changed_files_json; do
    printf '%s() { :; }\n' "$fn"
done > "$LIB"
if check; then echo 'FAIL: library without sop_agents_in_scope accepted'; exit 1; fi
grep -q 'missing: sop_agents_in_scope' "$WORK/out"
printf 'PASS: older library is refused and the missing function named\n'

printf 'sop_agents_in_scope() { :; }\n' >> "$LIB"
check
grep -q 'provides every function' "$WORK/out"
printf 'PASS: complete library accepted\n'

rm "$LIB"
mkdir -p "$WORK/project"
bash "$SOURCE/setup.sh" "$WORK/project" --runtime claude --no-hook > "$WORK/setup.log" 2>&1
grep -q '/ship cannot write receipts until agent-sop is installed' "$WORK/setup.log"
printf 'PASS: Claude setup warns when the library is missing\n'
