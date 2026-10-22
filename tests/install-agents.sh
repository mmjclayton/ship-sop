#!/usr/bin/env bash
# setup.sh (Claude) installs the five reviewer agents and the push gate: an agent
# is installed where absent, updated where it matches a shipped version, and kept
# where it was edited; the gate is registered once and uninstall removes it.
# Needs full history: older agent versions exist only as blobs in it.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK=$(mktemp -d)
SUITE_DONE=0
suite_trap() { local rc=$?; [ "$SUITE_DONE" = 1 ] || { echo "FAIL: suite stopped before its last check" >&2; rc=1; }; rm -rf "$WORK"; exit "$rc"; }
trap suite_trap EXIT
export SHIP_SOP_USER_HOME="$WORK/user"
unset CODEX_HOME
LIST="$SOURCE/scripts/shipped-user-files.txt"
AGENTS="$SHIP_SOP_USER_HOME/.claude/agents"
SETTINGS="$SHIP_SOP_USER_HOME/.claude/settings.json"
blob() { git hash-object --no-filters "$1"; }
gate_count() { jq '[.hooks[]?[]?.hooks[]?.command | select(test("sop-push-gate"))] | length' "$SETTINGS"; }

# Every agent, command and the receipt tool setup ships is listed, so an installed
# copy of it counts as unedited.
for src in "$SOURCE"/.claude/agents/*.md "$SOURCE"/.claude/commands/*.md "$SOURCE/scripts/ship-receipt.sh" "$SOURCE/scripts/worktree-tidy.sh"; do
    grep -qx "$(blob "$src") $(basename "$src")" "$LIST" || { echo "FAIL: $(basename "$src") at its current content is not in scripts/shipped-user-files.txt"; exit 1; }
done
test -f "$SOURCE/.claude/agents/security-reviewer.md"; test -f "$SOURCE/.claude/agents/code-reviewer.md"
printf 'PASS: every shipped agent, command, the receipt tool and worktree tidy is listed\n'

mkdir -p "$WORK/project"
git init -q -b main "$WORK/project"
printf '# Backlog\n' > "$WORK/project/Backlog.md"
bash "$SOURCE/setup.sh" "$WORK/project" --runtime claude > "$WORK/install.log" 2>&1
for name in security-reviewer code-reviewer compliance-reviewer diagram-builder release-notes-writer; do
    cmp "$SOURCE/.claude/agents/$name.md" "$AGENTS/$name.md"
done
test "$(gate_count)" = 1
jq -e --arg c "bash \"$SHIP_SOP_USER_HOME/.claude/scripts/hooks/ship-sop/sop-push-gate.sh\"" \
    '[.hooks.PreToolUse[].hooks[].command] == [$c]' "$SETTINGS" >/dev/null
test -x "$SHIP_SOP_USER_HOME/.claude/scripts/hooks/ship-sop/sop-push-gate.sh"
grep -q 'Push gate registered' "$WORK/install.log"
grep -q 'provides every function ship-sop needs' "$WORK/install.log"
cmp "$SOURCE/scripts/worktree-tidy.sh" "$SHIP_SOP_USER_HOME/.claude/scripts/ship-sop/worktree-tidy.sh"
printf 'PASS: fresh install creates five agents and registers one push gate\n'

# The registered command, exactly as written to settings.json, refuses an
# uncovered push from an auto-mode code repository.
GIT="git -c user.email=t@t -c user.name=t -c commit.gpgsign=false"
$GIT init -q --bare -b main "$WORK/origin.git"
$GIT clone -q "$WORK/origin.git" "$WORK/e2e" 2>/dev/null
echo '{ "name": "e2e", "private": true }' > "$WORK/e2e/package.json"
cp "$SOURCE/docs/templates/ship-sop.config.json" "$WORK/e2e/ship-sop.config.json"
(cd "$WORK/e2e" && $GIT add -A && $GIT commit -qm init && $GIT push -q -u origin main 2>/dev/null)
(cd "$WORK/e2e" && git checkout -q -b feat/x && for i in $(seq 1 20); do echo "console.log($i)" >> app.js; done && $GIT add -A && $GIT commit -qm "feat: code")
REGISTERED=$(jq -r '.hooks.PreToolUse[].hooks[].command' "$SETTINGS")
jq -nc --arg cwd "$WORK/e2e" '{session_id:"e2e",cwd:$cwd,tool_name:"Bash",tool_input:{command:"git push -u origin feat/x"}}' > "$WORK/push.json"
rc=0; sh -c "$REGISTERED" < "$WORK/push.json" > /dev/null 2> "$WORK/push.err" || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: installed gate exit $rc: $(cat "$WORK/push.err")"; exit 1; }
grep -q 'push refused' "$WORK/push.err"
printf 'PASS: the installed, registered gate refuses an uncovered push\n'
# No shipped agent points at retired files or commands.
if grep -nE 'docs/sop/|sop-checker|/update-sop|/restart-sop' "$SOURCE"/.claude/agents/*.md "$SOURCE"/.codex/agents/*.toml; then echo 'FAIL: an agent points at a retired file or command'; exit 1; fi
printf 'PASS: agents name no retired files or commands\n'

# An older shipped version is updated; an edited copy is kept; --force replaces it.
CUR=$(blob "$SOURCE/.claude/agents/compliance-reviewer.md")
OLD=$(awk -v cur="$CUR" '$2 == "compliance-reviewer.md" && $1 != cur { print $1; exit }' "$LIST")
[ "$OLD" != "$(blob "$SOURCE/.claude/agents/compliance-reviewer.md")" ]
git -C "$SOURCE" cat-file blob "$OLD" > "$AGENTS/compliance-reviewer.md"
printf '\nMy own rule.\n' >> "$AGENTS/code-reviewer.md"
cp "$AGENTS/code-reviewer.md" "$WORK/edited"
bash "$SOURCE/setup.sh" "$WORK/project" --runtime claude > "$WORK/reinstall.log" 2>&1
cmp "$SOURCE/.claude/agents/compliance-reviewer.md" "$AGENTS/compliance-reviewer.md"
grep -q 'update compliance-reviewer.md' "$WORK/reinstall.log"
cmp "$WORK/edited" "$AGENTS/code-reviewer.md"
grep -q 'keep   code-reviewer.md (edited locally' "$WORK/reinstall.log"
test "$(gate_count)" = 1
printf 'PASS: an older shipped agent is updated, an edited one kept, and the gate not duplicated\n'

# Uninstall removes the gate registration and scripts and unedited agents (older
# shipped versions too), and keeps the edited one.
git -C "$SOURCE" cat-file blob "$OLD" > "$AGENTS/compliance-reviewer.md"
bash "$SOURCE/setup.sh" "$WORK/project" --runtime claude --uninstall > "$WORK/uninstall.log" 2>&1
test "$(gate_count)" = 0
test ! -e "$SHIP_SOP_USER_HOME/.claude/scripts/hooks/ship-sop"
test ! -e "$SHIP_SOP_USER_HOME/.claude/scripts/ship-sop/worktree-tidy.sh"
test ! -e "$AGENTS/compliance-reviewer.md"; test ! -e "$AGENTS/security-reviewer.md"
cmp "$WORK/edited" "$AGENTS/code-reviewer.md"
printf 'PASS: uninstall removes the gate and unedited agents, keeps edited ones\n'

bash "$SOURCE/setup.sh" "$WORK/project" --runtime claude --force > "$WORK/force.log" 2>&1
cmp "$SOURCE/.claude/agents/code-reviewer.md" "$AGENTS/code-reviewer.md"
printf 'PASS: --force replaces an edited agent\n'

# --no-hook installs the gate scripts (receipts need the library) but registers nothing.
rm -rf "$SHIP_SOP_USER_HOME"
mkdir -p "$WORK/manual"
bash "$SOURCE/setup.sh" "$WORK/manual" --runtime claude --no-hook > "$WORK/manual.log" 2>&1
test -x "$SHIP_SOP_USER_HOME/.claude/scripts/hooks/ship-sop/sop-lib.sh"
test ! -e "$SETTINGS"
grep -q -- '--no-hook: hook settings left unchanged' "$WORK/manual.log"
grep -q 'none (use /ship and /release manually)' "$WORK/manual.log"
printf 'PASS: --no-hook installs the scripts without registering the gate, and says none is registered\n'
# With a registration already present, --no-hook leaves it and names it.
bash "$SOURCE/setup.sh" "$WORK/manual" --runtime claude > /dev/null 2>&1
cp "$SETTINGS" "$WORK/settings-before"
bash "$SOURCE/setup.sh" "$WORK/manual" --runtime claude --no-hook > "$WORK/manual2.log" 2>&1
cmp "$WORK/settings-before" "$SETTINGS"
grep -qF "  bash \"$SHIP_SOP_USER_HOME/.claude/scripts/hooks/ship-sop/sop-push-gate.sh\"" "$WORK/manual2.log"
printf 'PASS: --no-hook leaves an existing registration in place and names it\n'

# An upgrade updates unedited earlier commands and the receipt tool (a machine set up
# before P41 kept copies that point at the old agent-sop install), keeps edited ones.
UP="$WORK/upgrade"; mkdir -p "$UP/.claude/commands" "$UP/.claude/scripts/ship-sop" "$WORK/up-project"
git init -q -b main "$WORK/up-project"; printf '# Backlog\n' > "$WORK/up-project/Backlog.md"
git -C "$SOURCE" show 84b9f49:.claude/commands/ship.md > "$UP/.claude/commands/ship.md"
git -C "$SOURCE" show 84b9f49:scripts/ship-receipt.sh > "$UP/.claude/scripts/ship-sop/ship-receipt.sh"
{ git -C "$SOURCE" show 84b9f49:.claude/commands/release.md; printf '\nlocal note\n'; } > "$UP/.claude/commands/release.md"
{ git -C "$SOURCE" show 84b9f49:.claude/commands/ship-on.md; printf '\nlocal note\n'; } > "$UP/.claude/commands/ship-on.md"
SHIP_SOP_USER_HOME="$UP" bash "$SOURCE/setup.sh" "$WORK/up-project" --runtime claude > "$WORK/upgrade.log" 2>&1
cmp "$SOURCE/.claude/commands/ship.md" "$UP/.claude/commands/ship.md"
cmp "$SOURCE/scripts/ship-receipt.sh" "$UP/.claude/scripts/ship-sop/ship-receipt.sh"
grep -q 'local note' "$UP/.claude/commands/release.md"
grep -q 'keep   release.md' "$WORK/upgrade.log"
if grep -q 'hooks/agent-sop' "$UP/.claude/commands/ship.md" "$UP/.claude/scripts/ship-sop/ship-receipt.sh"; then echo "FAIL: an updated copy still points at hooks/agent-sop"; exit 1; fi
grep -q 'ship-on.md points at the retired agent-sop path' "$WORK/upgrade.log"
if grep -q 'release.md points at the retired' "$WORK/upgrade.log"; then echo "FAIL: warned about a copy that does not use the agent-sop path"; exit 1; fi
printf 'PASS: an upgrade updates unedited earlier commands and the receipt tool and keeps edited ones\n'

SUITE_DONE=1
