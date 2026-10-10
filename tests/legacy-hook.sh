#!/usr/bin/env bash
# P25: setup no longer installs the project-scope auto-ship-hook.sh and retires
# any copy and settings entry an earlier install left behind.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export AGENT_SOP_USER_HOME="$WORK/user"
unset CODEX_HOME
# The last shipped version, as an earlier install would have copied it.
LEGACY_BLOB=c4c19edfe4a776a853d5ef132a74de760a93d247
OTHER_HOOK='{"type":"command","command":"scripts/other-stop.sh"}'

legacy_project() {
    mkdir -p "$WORK/$1/scripts" "$WORK/$1/.claude"
    git -C "$SOURCE" cat-file blob "$LEGACY_BLOB" > "$WORK/$1/scripts/auto-ship-hook.sh"
    jq -n --argjson other "$OTHER_HOOK" '{hooks:{Stop:[
        {matcher:"*",hooks:[{type:"command",command:"scripts/auto-ship-hook.sh"},$other]},
        {command:"scripts/auto-ship-hook.sh"}]}}' > "$WORK/$1/.claude/settings.json"
}
no_legacy_entry() {
    ! jq -e '[.. | objects | select(.command? == "scripts/auto-ship-hook.sh")] | length > 0' "$1" >/dev/null
}

# Fresh install, no agent-sop hooks: nothing legacy is written.
mkdir -p "$WORK/fresh"
bash "$SOURCE/setup.sh" "$WORK/fresh" --runtime claude < /dev/null > "$WORK/fresh.log" 2>&1
test ! -e "$WORK/fresh/scripts/auto-ship-hook.sh"
if [ -f "$WORK/fresh/.claude/settings.json" ]; then no_legacy_entry "$WORK/fresh/.claude/settings.json"; fi
grep -q 'agent-sop' "$WORK/fresh.log"
printf 'PASS: fresh install wires no project Stop hook and copies no hook script\n'

# Upgrade of an earlier install: unmodified script and both entry shapes removed,
# another hook in the same entry kept.
legacy_project upgrade
bash "$SOURCE/setup.sh" "$WORK/upgrade" --runtime claude --no-hook > "$WORK/upgrade.log" 2>&1
test ! -e "$WORK/upgrade/scripts/auto-ship-hook.sh"
no_legacy_entry "$WORK/upgrade/.claude/settings.json"
jq -e --argjson other "$OTHER_HOOK" '[.hooks.Stop[].hooks[]?] == [$other]' "$WORK/upgrade/.claude/settings.json" >/dev/null
printf 'PASS: upgrade retires the legacy script and entries, keeps other hooks\n'

# A locally modified copy is not ours to delete.
legacy_project modified
printf '# local edit\n' >> "$WORK/modified/scripts/auto-ship-hook.sh"
bash "$SOURCE/setup.sh" "$WORK/modified" --runtime claude --no-hook > "$WORK/modified.log" 2>&1
test -f "$WORK/modified/scripts/auto-ship-hook.sh"
grep -q 'locally modified' "$WORK/modified.log"
no_legacy_entry "$WORK/modified/.claude/settings.json"
printf 'PASS: modified legacy script is kept and reported\n'

# Uninstall still removes both.
legacy_project uninstall
bash "$SOURCE/setup.sh" "$WORK/uninstall" --runtime claude --uninstall > "$WORK/uninstall.log" 2>&1
test ! -e "$WORK/uninstall/scripts/auto-ship-hook.sh"
no_legacy_entry "$WORK/uninstall/.claude/settings.json"
printf 'PASS: uninstall removes the legacy script and entries\n'
