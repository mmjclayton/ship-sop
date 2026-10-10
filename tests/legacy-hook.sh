#!/usr/bin/env bash
# P25: setup no longer installs the project-scope auto-ship-hook.sh and retires
# any copy and settings entry an earlier install left behind. Needs full history:
# the shipped versions exist only as blobs in it.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
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
register_agent_sop() {
    mkdir -p "$AGENT_SOP_USER_HOME/.claude/scripts/hooks/agent-sop"
    touch "$AGENT_SOP_USER_HOME/.claude/scripts/hooks/agent-sop/sop-stop-drift.sh"
    jq -n --arg c "bash \"$AGENT_SOP_USER_HOME/.claude/scripts/hooks/agent-sop/sop-stop-drift.sh\"" \
        '{hooks:{Stop:[{matcher:"*",hooks:[{type:"command",command:$c}]},{matcher:"*",hooks:[{type:"prompt",prompt:"x"}]}]}}' \
        > "$AGENT_SOP_USER_HOME/.claude/settings.json"
}

# Fresh install, no agent-sop hooks: nothing legacy is written.
mkdir -p "$WORK/fresh"
bash "$SOURCE/setup.sh" "$WORK/fresh" --runtime claude < /dev/null > "$WORK/fresh.log" 2>&1
test ! -e "$WORK/fresh/scripts/auto-ship-hook.sh"
test ! -e "$WORK/fresh/.claude/settings.json"
grep -q "user-scope hooks, which are not registered" "$WORK/fresh.log"
printf 'PASS: fresh install wires no project Stop hook and reports agent-sop hooks absent\n'

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

# A registered agent-sop hook (alongside a non-command hook) is reported as such.
register_agent_sop
mkdir -p "$WORK/wired"
bash "$SOURCE/setup.sh" "$WORK/wired" --runtime claude < /dev/null > "$WORK/wired.log" 2>&1
grep -q "user-scope hooks: registered" "$WORK/wired.log"
printf '{not json\n' > "$AGENT_SOP_USER_HOME/.claude/settings.json"
mkdir -p "$WORK/unknown"
bash "$SOURCE/setup.sh" "$WORK/unknown" --runtime claude < /dev/null > "$WORK/unknown.log" 2>&1
grep -q "Could not check agent-sop's hooks" "$WORK/unknown.log"
rm "$AGENT_SOP_USER_HOME/.claude/settings.json"
printf 'PASS: registered and unreadable agent-sop hook states are reported\n'

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
grep -q 'links outside the project and home' "$WORK/outside.log"
legacy_project dangling
rm "$WORK/dangling/.claude/settings.json"
ln -s "$WORK/nowhere.json" "$WORK/dangling/.claude/settings.json"
if bash "$SOURCE/setup.sh" "$WORK/dangling" --runtime claude --no-hook > "$WORK/dangling.log" 2>&1; then
    echo 'FAIL: setup ignored a broken settings symlink'; exit 1
fi
test -f "$WORK/dangling/scripts/auto-ship-hook.sh"
grep -q 'broken symlink' "$WORK/dangling.log"
printf 'PASS: links outside the project and home, and broken links, are left alone\n'

# A stale agent-sop registration stops setup before anything is retired.
mkdir -p "$AGENT_SOP_USER_HOME/.claude"
jq -n '{hooks:{Stop:[{matcher:"*",hooks:[{type:"command",command:"bash /elsewhere/sop-stop-drift.sh"}]}]}}' > "$AGENT_SOP_USER_HOME/.claude/settings.json"
legacy_project stale
cp "$WORK/stale/.claude/settings.json" "$WORK/stale-before"
if bash "$SOURCE/setup.sh" "$WORK/stale" --runtime claude < /dev/null > "$WORK/stale.log" 2>&1; then
    echo 'FAIL: stale registration accepted'; exit 1
fi
grep -q 'stale or nonstandard' "$WORK/stale.log"
cmp "$WORK/stale-before" "$WORK/stale/.claude/settings.json"
test -f "$WORK/stale/scripts/auto-ship-hook.sh"
rm "$AGENT_SOP_USER_HOME/.claude/settings.json"
printf 'PASS: stale agent-sop registration stops setup and retires nothing\n'

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
