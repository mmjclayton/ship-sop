#!/usr/bin/env bash
# ship-receipt.sh refuses an installed library that is missing, broken or lacks a
# function it calls, says which one, and says how to reinstall.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK=$(mktemp -d)
SUITE_DONE=0
suite_trap() { local rc=$?; [ "$SUITE_DONE" = 1 ] || { echo "FAIL: suite stopped before its last check" >&2; rc=1; }; rm -rf "$WORK"; exit "$rc"; }
trap suite_trap EXIT
export SHIP_SOP_USER_HOME="$WORK/user"
unset CODEX_HOME
LIB="$SHIP_SOP_USER_HOME/.claude/scripts/hooks/ship-sop/sop-lib.sh"
check() { bash "$SOURCE/scripts/ship-receipt.sh" --check-lib --runtime claude > "$WORK/out" 2>&1; }

if check; then echo 'FAIL: missing library accepted'; exit 1; fi
grep -q 'push-gate library not installed' "$WORK/out"
grep -q 're-run ship-sop setup.sh' "$WORK/out"
printf 'PASS: missing library names the fix\n'

mkdir -p "$(dirname "$LIB")"
REQUIRED=$(sed -n "/^REQUIRED_SOP_FUNCTIONS='/,/'\$/p" "$SOURCE/scripts/ship-receipt.sh" | tr -d "'" | sed 's/^REQUIRED_SOP_FUNCTIONS=//' | tr ' ' '\n' | grep .)
# The receipt functions and the push gate's (here sop_is_push_command) are both checked.
for missing_fn in sop_agents_in_scope sop_is_push_command; do
    for fn in $REQUIRED; do
        [ "$fn" = "$missing_fn" ] || printf '%s() { :; }\n' "$fn"
    done > "$LIB"
    if check; then echo "FAIL: library without $missing_fn accepted"; exit 1; fi
    grep -q "missing: $missing_fn" "$WORK/out"
done
printf 'PASS: incomplete library is refused and the missing function named, gate functions included\n'
for fn in $REQUIRED; do [ "$fn" = sop_agents_in_scope ] || printf '%s() { :; }\n' "$fn"; done > "$LIB"

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
rm -rf "$SHIP_SOP_USER_HOME"
mkdir -p "$WORK/project"
bash "$SOURCE/setup.sh" "$WORK/project" --runtime claude --no-hook > "$WORK/setup.log" 2>&1
grep -q 'provides every function ship-sop needs' "$WORK/setup.log"
check
printf 'PASS: Claude setup installs a library that passes the check\n'

# An installed library edited so it fails the check (setup keeps edited copies)
# makes setup exit non-zero, as the Codex setup does.
printf '\nunset -f sop_shipsop_gate\n' >> "$LIB"
if bash "$SOURCE/setup.sh" "$WORK/project" --runtime claude --no-hook > "$WORK/setup2.log" 2>&1; then
    echo 'FAIL: setup succeeded with a failing library check'; exit 1
fi
grep -q 'missing: sop_shipsop_gate' "$WORK/setup2.log"
grep -q 'installed library check failed' "$WORK/setup2.log"
printf 'PASS: setup exits non-zero when the installed library fails the check\n'
SUITE_DONE=1
