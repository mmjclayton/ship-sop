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
export AGENT_SOP_USER_HOME="$WORK/user"
unset CODEX_HOME
LIST="$SOURCE/scripts/shipped-agents.txt"
AGENTS="$AGENT_SOP_USER_HOME/.claude/agents"
SETTINGS="$AGENT_SOP_USER_HOME/.claude/settings.json"
blob() { git hash-object --no-filters "$1"; }
gate_count() { jq '[.hooks[]?[]?.hooks[]?.command | select(test("sop-push-gate"))] | length' "$SETTINGS"; }

# Every agent setup ships is listed, so an installed copy of it counts as unedited.
for src in "$SOURCE"/.claude/agents/*.md; do
    grep -qx "$(blob "$src") $(basename "$src")" "$LIST" || { echo "FAIL: $(basename "$src") at its current content is not in scripts/shipped-agents.txt"; exit 1; }
done
test -f "$SOURCE/.claude/agents/security-reviewer.md"; test -f "$SOURCE/.claude/agents/code-reviewer.md"
printf 'PASS: every shipped agent, including the two gate reviewers, is listed\n'

mkdir -p "$WORK/project"
git init -q -b main "$WORK/project"
printf '# Backlog\n' > "$WORK/project/Backlog.md"
bash "$SOURCE/setup.sh" "$WORK/project" --runtime claude > "$WORK/install.log" 2>&1
for name in security-reviewer code-reviewer compliance-reviewer diagram-builder release-notes-writer; do
    cmp "$SOURCE/.claude/agents/$name.md" "$AGENTS/$name.md"
done
test "$(gate_count)" = 1
jq -e --arg c "bash \"$AGENT_SOP_USER_HOME/.claude/scripts/hooks/ship-sop/sop-push-gate.sh\"" \
    '[.hooks.PreToolUse[].hooks[].command] == [$c]' "$SETTINGS" >/dev/null
test -x "$AGENT_SOP_USER_HOME/.claude/scripts/hooks/ship-sop/sop-push-gate.sh"
grep -q 'Push gate registered' "$WORK/install.log"
grep -q 'provides every function ship-sop needs' "$WORK/install.log"
printf 'PASS: fresh install creates five agents and registers one push gate\n'

# An older shipped version is updated; an edited copy is kept; --force replaces it.
OLD=$(awk '$2 == "compliance-reviewer.md" { print $1; exit }' "$LIST")
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
test ! -e "$AGENT_SOP_USER_HOME/.claude/scripts/hooks/ship-sop"
test ! -e "$AGENTS/compliance-reviewer.md"; test ! -e "$AGENTS/security-reviewer.md"
cmp "$WORK/edited" "$AGENTS/code-reviewer.md"
printf 'PASS: uninstall removes the gate and unedited agents, keeps edited ones\n'

bash "$SOURCE/setup.sh" "$WORK/project" --runtime claude --force > "$WORK/force.log" 2>&1
cmp "$SOURCE/.claude/agents/code-reviewer.md" "$AGENTS/code-reviewer.md"
printf 'PASS: --force replaces an edited agent\n'

# --no-hook installs the gate scripts (receipts need the library) but registers nothing.
rm -rf "$AGENT_SOP_USER_HOME"
mkdir -p "$WORK/manual"
bash "$SOURCE/setup.sh" "$WORK/manual" --runtime claude --no-hook > "$WORK/manual.log" 2>&1
test -x "$AGENT_SOP_USER_HOME/.claude/scripts/hooks/ship-sop/sop-lib.sh"
test ! -e "$SETTINGS"
grep -q 'Push gate not registered (--no-hook)' "$WORK/manual.log"
printf 'PASS: --no-hook installs the scripts without registering the gate\n'
SUITE_DONE=1
