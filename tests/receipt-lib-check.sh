#!/usr/bin/env bash
# ship-receipt.sh refuses an installed library that is missing, broken or lacks a
# function it calls, says which one, and says how to reinstall.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK=$(mktemp -d)
SUITE_DONE=0
suite_trap() { local rc=$?; [ "$SUITE_DONE" = 1 ] || { echo "FAIL: suite stopped before its last check" >&2; rc=1; }; rm -rf "$WORK"; exit "$rc"; }
trap suite_trap EXIT
export AGENT_SOP_USER_HOME="$WORK/user"
unset CODEX_HOME
LIB="$AGENT_SOP_USER_HOME/.claude/scripts/hooks/ship-sop/sop-lib.sh"
check() { bash "$SOURCE/scripts/ship-receipt.sh" --check-lib --runtime claude > "$WORK/out" 2>&1; }

if check; then echo 'FAIL: missing library accepted'; exit 1; fi
grep -q 'push-gate library not installed' "$WORK/out"
grep -q 're-run ship-sop setup.sh' "$WORK/out"
printf 'PASS: missing library names the fix\n'

mkdir -p "$(dirname "$LIB")"
for fn in sop_effective_config sop_policy_digest sop_receipt_valid sop_changed_files_json; do
    printf '%s() { :; }\n' "$fn"
done > "$LIB"
if check; then echo 'FAIL: library without sop_agents_in_scope accepted'; exit 1; fi
grep -q 'missing: sop_agents_in_scope' "$WORK/out"
printf 'PASS: incomplete library is refused and the missing function named\n'

printf 'sop_agents_in_scope() { :; }\n' >> "$LIB"
check
grep -q 'provides every function' "$WORK/out"
bash "$SOURCE/scripts/ship-receipt.sh" --runtime claude --check-lib > "$WORK/out" 2>&1
grep -q 'provides every function' "$WORK/out"
printf 'PASS: complete library accepted, with --check-lib in any position\n'

cp "$LIB" "$WORK/good-lib"
printf 'false\n' >> "$LIB"
if check; then echo 'FAIL: library that fails to load accepted'; exit 1; fi
grep -q 'failed to load' "$WORK/out"
printf 'if then\n' > "$LIB"
if check; then echo 'FAIL: library with a syntax error accepted'; exit 1; fi
grep -q 'failed to load' "$WORK/out"
cp "$WORK/good-lib" "$LIB"
printf 'PASS: a library that fails to load is reported, not silent\n'

# The library ship-sop itself ships provides every function the receipt tool needs.
cp "$SOURCE/scripts/hooks/sop-lib.sh" "$LIB"
check
printf 'PASS: the shipped library passes the check\n'

# Setup installs the library, even with --no-hook, so the check passes straight after.
rm -rf "$AGENT_SOP_USER_HOME"
mkdir -p "$WORK/project"
bash "$SOURCE/setup.sh" "$WORK/project" --runtime claude --no-hook > "$WORK/setup.log" 2>&1
grep -q 'provides every function ship-sop needs' "$WORK/setup.log"
check
printf 'PASS: Claude setup installs a library that passes the check\n'
SUITE_DONE=1
