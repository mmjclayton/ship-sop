#!/usr/bin/env bash
# P25: setup no longer installs the project-scope auto-ship-hook.sh and retires
# any copy and settings entry an earlier install left behind. Needs full history:
# the shipped versions exist only as blobs in it.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK=$(mktemp -d)
SUITE_DONE=0
suite_trap() { local rc=$?; [ "$SUITE_DONE" = 1 ] || { echo "FAIL: suite stopped before its last check" >&2; rc=1; }; rm -rf "$WORK"; exit "$rc"; }
trap suite_trap EXIT
export AGENT_SOP_USER_HOME="$WORK/user"
unset CODEX_HOME
OTHER_HOOK='{"type":"command","command":"scripts/other-stop.sh"}'

# Every blob setup recognises must be a real shipped version, and every shipped
# version must be recognised.
listed=$(sed -n "/^LEGACY_HOOK_BLOBS='/,/'$/p" "$SOURCE/setup.sh" | tr -d "'" | sed 's/^LEGACY_HOOK_BLOBS=//' | sort)
shipped=$(git -C "$SOURCE" log --format=%H -- scripts/auto-ship-hook.sh |
    while read -r c; do git -C "$SOURCE" rev-parse -q --verify "$c^:scripts/auto-ship-hook.sh" || true
        git -C "$SOURCE" rev-parse -q --verify "$c:scripts/auto-ship-hook.sh" || true; done | sort -u)
[ -n "$shipped" ] || { echo 'FAIL: no hook history; run from a full clone'; exit 1; }
[ "$listed" = "$shipped" ] || { echo 'FAIL: LEGACY_HOOK_BLOBS differs from the shipped versions'; exit 1; }
LEGACY_BLOB=$(printf '%s\n' "$listed" | tail -n1)
printf 'PASS: blob list matches every shipped version\n'

legacy_project() {
    mkdir -p "$WORK/$1/scripts" "$WORK/$1/.claude"
    git -C "$SOURCE" cat-file blob "$LEGACY_BLOB" > "$WORK/$1/scripts/auto-ship-hook.sh"
    jq -n --argjson other "$OTHER_HOOK" '{hooks:{Stop:[
        {matcher:"*",hooks:[{type:"command",command:"scripts/auto-ship-hook.sh"},$other]},
        {command:"scripts/auto-ship-hook.sh"}]}}' > "$WORK/$1/.claude/settings.json"
}
# Valid JSON, no legacy entry, and the other hook kept.
retired_settings() {
    jq -e --argjson other "$OTHER_HOOK" '
        ([.. | objects | select(.command? == "scripts/auto-ship-hook.sh")] | length == 0)
        and ([.hooks.Stop[].hooks[]?] == [$other])' "$1" >/dev/null
}

# Fresh install: nothing legacy is written, and the user-scope push gate is registered.
mkdir -p "$WORK/fresh"
bash "$SOURCE/setup.sh" "$WORK/fresh" --runtime claude < /dev/null > "$WORK/fresh.log" 2>&1
test ! -e "$WORK/fresh/scripts/auto-ship-hook.sh"
test ! -e "$WORK/fresh/.claude/settings.json"
grep -q "Push gate registered" "$WORK/fresh.log"
printf 'PASS: fresh install wires no project Stop hook and registers the user-scope push gate\n'

# Upgrade of an earlier install: both entry shapes removed, other hook kept,
# unmodified script removed.
legacy_project upgrade
bash "$SOURCE/setup.sh" "$WORK/upgrade" --runtime claude --no-hook > "$WORK/upgrade.log" 2>&1
test ! -e "$WORK/upgrade/scripts/auto-ship-hook.sh"
retired_settings "$WORK/upgrade/.claude/settings.json"
printf 'PASS: upgrade retires the legacy script and entries, keeps other hooks\n'

# A locally modified copy is kept; --force removes it.
legacy_project modified
printf '# local edit\n' >> "$WORK/modified/scripts/auto-ship-hook.sh"
bash "$SOURCE/setup.sh" "$WORK/modified" --runtime claude --no-hook > "$WORK/modified.log" 2>&1
test -f "$WORK/modified/scripts/auto-ship-hook.sh"
grep -q 'locally modified' "$WORK/modified.log"
retired_settings "$WORK/modified/.claude/settings.json"
bash "$SOURCE/setup.sh" "$WORK/modified" --runtime claude --no-hook --force > "$WORK/forced.log" 2>&1
test ! -e "$WORK/modified/scripts/auto-ship-hook.sh"
printf 'PASS: modified legacy script is kept and reported, --force removes it\n'

# Without jq the entry cannot be edited: keep the script it points at, say so,
# and exit non-zero.
legacy_project nojq
mkdir -p "$WORK/nojqbin"
for tool in bash git cp mv rm mkdir chmod mktemp cat grep sed dirname basename find sort head tr cut wc date; do
    path=$(command -v "$tool") && ln -sf "$path" "$WORK/nojqbin/$tool"
done
printf -- '---\nname: silent-failure-hunter\n---\n' > "$WORK/nojq-profile.md"
mkdir -p "$WORK/nojq/.claude/agents"; cp "$WORK/nojq-profile.md" "$WORK/nojq/.claude/agents/silent-failure-hunter.md"
cp "$WORK/nojq/.claude/settings.json" "$WORK/nojq-before"
if PATH="$WORK/nojqbin" bash "$SOURCE/setup.sh" "$WORK/nojq" --runtime claude --no-hook > "$WORK/nojq.log" 2>&1; then
    echo 'FAIL: setup reported success with the legacy entry still registered'; exit 1
fi
test -f "$WORK/nojq/scripts/auto-ship-hook.sh"
cmp "$WORK/nojq-before" "$WORK/nojq/.claude/settings.json"
grep -q 'remove the scripts/auto-ship-hook.sh hook entry' "$WORK/nojq.log"
printf 'PASS: without jq the entry and its script are kept and setup exits non-zero\n'

# Unreadable user settings: the gate cannot be registered, setup says so and exits
# non-zero, and the user's file is left as it was.
mkdir -p "$AGENT_SOP_USER_HOME/.claude"
printf '{not json\n' > "$AGENT_SOP_USER_HOME/.claude/settings.json"
cp "$AGENT_SOP_USER_HOME/.claude/settings.json" "$WORK/bad-settings-before"
mkdir -p "$WORK/badsettings"
if bash "$SOURCE/setup.sh" "$WORK/badsettings" --runtime claude < /dev/null > "$WORK/badsettings.log" 2>&1; then
    echo 'FAIL: setup reported success without registering the gate'; exit 1
fi
grep -q 'could not parse' "$WORK/badsettings.log"
grep -q 'push gate could not be installed' "$WORK/badsettings.log"
cmp "$WORK/bad-settings-before" "$AGENT_SOP_USER_HOME/.claude/settings.json"
rm "$AGENT_SOP_USER_HOME/.claude/settings.json"
printf 'PASS: unreadable user settings are reported and left untouched\n'

# An entry under another event is removed too, and a regular file keeps its mode.
legacy_project other-event
jq '.hooks.SessionStart = [{matcher:"*",hooks:[{type:"command",command:"scripts/auto-ship-hook.sh"}]}]' \
    "$WORK/other-event/.claude/settings.json" > "$WORK/tmp.json" && mv "$WORK/tmp.json" "$WORK/other-event/.claude/settings.json"
chmod 600 "$WORK/other-event/.claude/settings.json"
bash "$SOURCE/setup.sh" "$WORK/other-event" --runtime claude --no-hook > "$WORK/other-event.log" 2>&1
find "$WORK/other-event/.claude/settings.json" -perm 600 | grep -q .
retired_settings "$WORK/other-event/.claude/settings.json"
jq -e '.hooks.SessionStart == []' "$WORK/other-event/.claude/settings.json" >/dev/null
test ! -e "$WORK/other-event/scripts/auto-ship-hook.sh"
printf 'PASS: entries under any event are removed; mode preserved\n'

# A symlinked settings file is edited at its target inside home, and the link kept.
mkdir -p "$WORK/home/dotfiles"
legacy_project linked
mv "$WORK/linked/.claude/settings.json" "$WORK/home/dotfiles/settings.json"
ln -s "$WORK/home/dotfiles/settings.json" "$WORK/linked/.claude/settings.json"
HOME="$WORK/home" bash "$SOURCE/setup.sh" "$WORK/linked" --runtime claude --no-hook > "$WORK/linked.log" 2>&1
test -L "$WORK/linked/.claude/settings.json"
retired_settings "$WORK/home/dotfiles/settings.json"
printf 'PASS: symlinked settings edited at a target inside home; link kept\n'

# A link to a target outside the project and home is not followed; nor is a broken one.
mkdir -p "$WORK/elsewhere"
legacy_project outside
mv "$WORK/outside/.claude/settings.json" "$WORK/elsewhere/settings.json"
cp "$WORK/elsewhere/settings.json" "$WORK/outside-before"
ln -s "$WORK/elsewhere/settings.json" "$WORK/outside/.claude/settings.json"
if HOME="$WORK/home" bash "$SOURCE/setup.sh" "$WORK/outside" --runtime claude --no-hook > "$WORK/outside.log" 2>&1; then
    echo 'FAIL: setup followed a link outside the project and home'; exit 1
fi
cmp "$WORK/outside-before" "$WORK/elsewhere/settings.json"
test -f "$WORK/outside/scripts/auto-ship-hook.sh"
grep -q 'resolves outside the project and home' "$WORK/outside.log"
# A linked .claude directory gets the same check as a linked file.
legacy_project dirlink
mkdir -p "$WORK/elsewhere/claude-dir"
mv "$WORK/dirlink/.claude/settings.json" "$WORK/elsewhere/claude-dir/settings.json"
rmdir "$WORK/dirlink/.claude"; ln -s "$WORK/elsewhere/claude-dir" "$WORK/dirlink/.claude"
cp "$WORK/elsewhere/claude-dir/settings.json" "$WORK/dirlink-before"
if HOME="$WORK/home" bash "$SOURCE/setup.sh" "$WORK/dirlink" --runtime claude --no-hook > "$WORK/dirlink.log" 2>&1; then
    echo 'FAIL: setup followed a linked .claude directory outside the project and home'; exit 1
fi
cmp "$WORK/dirlink-before" "$WORK/elsewhere/claude-dir/settings.json"
# A link to a file in home that is not a Claude settings file is not edited.
legacy_project notsettings
mv "$WORK/notsettings/.claude/settings.json" "$WORK/home/dotfiles/other.json"
ln -s "$WORK/home/dotfiles/other.json" "$WORK/notsettings/.claude/settings.json"
cp "$WORK/home/dotfiles/other.json" "$WORK/notsettings-before"
if HOME="$WORK/home" bash "$SOURCE/setup.sh" "$WORK/notsettings" --runtime claude --no-hook > "$WORK/notsettings.log" 2>&1; then
    echo 'FAIL: setup edited a linked file that is not a Claude settings file'; exit 1
fi
cmp "$WORK/notsettings-before" "$WORK/home/dotfiles/other.json"
grep -q 'not a Claude settings file' "$WORK/notsettings.log"
legacy_project dangling
rm "$WORK/dangling/.claude/settings.json"
ln -s "$WORK/nowhere.json" "$WORK/dangling/.claude/settings.json"
if bash "$SOURCE/setup.sh" "$WORK/dangling" --runtime claude --no-hook > "$WORK/dangling.log" 2>&1; then
    echo 'FAIL: setup ignored a broken settings symlink'; exit 1
fi
test -f "$WORK/dangling/scripts/auto-ship-hook.sh"
grep -q 'broken symlink' "$WORK/dangling.log"
printf 'PASS: links outside the project and home, linked directories, non-settings files and broken links are left alone\n'

# Uninstall without jq cannot edit the entry: it says so and exits non-zero.
legacy_project uninstall-nojq
if PATH="$WORK/nojqbin" bash "$SOURCE/setup.sh" "$WORK/uninstall-nojq" --runtime claude --uninstall > "$WORK/uninstall-nojq.log" 2>&1; then
    echo 'FAIL: uninstall reported success with the legacy entry still registered'; exit 1
fi
grep -q 'Uninstall incomplete' "$WORK/uninstall-nojq.log"
if grep -q 'Done. ship-sop is uninstalled' "$WORK/uninstall-nojq.log"; then echo 'FAIL: contradictory Done line'; exit 1; fi
test -f "$WORK/uninstall-nojq/scripts/auto-ship-hook.sh"
printf 'PASS: incomplete uninstall is reported and exits non-zero\n'

# Uninstall still removes both.
legacy_project uninstall
bash "$SOURCE/setup.sh" "$WORK/uninstall" --runtime claude --uninstall > "$WORK/uninstall.log" 2>&1
test ! -e "$WORK/uninstall/scripts/auto-ship-hook.sh"
retired_settings "$WORK/uninstall/.claude/settings.json"
printf 'PASS: uninstall removes the legacy script and entries\n'
SUITE_DONE=1
