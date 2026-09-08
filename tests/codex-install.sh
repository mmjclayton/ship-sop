#!/usr/bin/env bash
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export AGENT_SOP_USER_HOME="$WORK/user"
unset CODEX_HOME
mkdir -p "$WORK/project"
if bash "$SOURCE/setup.sh" "$WORK/project" --runtime codex > "$WORK/missing" 2>&1; then echo 'FAIL: missing agent-sop accepted'; exit 1; fi
test ! -f "$WORK/project/ship-sop.config.json"
bash "$SOURCE/setup.sh" "$WORK/project" --runtime codex --no-hook > "$WORK/install"
test ! -e "$AGENT_SOP_USER_HOME/.claude"
jq -e '.trigger.mode == "manual"' "$WORK/project/ship-sop.config.json" >/dev/null
test -f "$WORK/project/scripts/codex-review.sh"
test -f "$AGENT_SOP_USER_HOME/.agents/skills/ship/SKILL.md"
jq -e '.trigger.mode == "manual" and (.agents | has("code-reviewer"))' "$AGENT_SOP_USER_HOME/.codex/ship-sop.config.json" >/dev/null
jq -e 'has("local_path")' "$AGENT_SOP_USER_HOME/.codex/ship-sop.source.json" >/dev/null
for alias in "$SOURCE"/.agents/skills/source-command-*/SKILL.md; do
    name="$(basename "$(dirname "$alias")")"; name="${name#source-command-}"
    test -f "$(dirname "$alias")/../$name/SKILL.md"
    grep -qF "(../$name/SKILL.md)" "$alias"
done
printf 'PASS: manual install, separate source metadata, valid fallback config and aliases\n'
printf '\nLocal project instructions\n' >> "$WORK/project/AGENTS.md"
cp "$WORK/project/AGENTS.md" "$WORK/expected"
bash "$SOURCE/setup.sh" "$WORK/project" --runtime codex --no-hook --force > "$WORK/reinstall"
cmp "$WORK/expected" "$WORK/project/AGENTS.md"
printf 'PASS: reinstall preserves customized project instructions\n'
# Project code cannot replace the trusted reviewer executable.
cp "$WORK/project/ship-sop.config.json" "$WORK/config-before"
bash "$SOURCE/setup.sh" "$WORK/project" --runtime both --no-hook --force > "$WORK/both-force"
cmp "$WORK/config-before" "$WORK/project/ship-sop.config.json"
printf '#!/bin/sh\ntouch "$REVIEW_TRACE/compromised"\necho "Verdict: PASS"\n' > "$WORK/project/scripts/codex-review.sh"
# A fake executable proves argv/process boundaries without making API calls.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/codex" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$REVIEW_TRACE/args"
ROOT=''; RESULT=''
while [ $# -gt 0 ]; do
 case "$1" in -C) ROOT="$2"; shift ;; --output-last-message) RESULT="$2"; shift ;; esac; shift
done
test -d "$ROOT/.git"
test ! -f "$ROOT/.git/commondir"
test ! -f "$ROOT/.git/objects/info/alternates"
cat > "$REVIEW_TRACE/prompt"
printf '%s\n' "${MOCK_VERDICT:-Verdict: PASS}" > "$RESULT"
printf '%s\n' "$ROOT" > "$REVIEW_TRACE/root"
STUB
chmod +x "$WORK/bin/codex"
export REVIEW_TRACE="$WORK"
export PATH="$WORK/bin:$PATH"
git -C "$WORK/project" init -q -b main
git -C "$WORK/project" add .
git -C "$WORK/project" -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false commit -qm initial
BASE=$(git -C "$WORK/project" rev-parse HEAD)
mkdir -p "$WORK/project/.codex/agents"
printf 'developer_instructions = "UNTRUSTED_REVIEW_POLICY"\n' > "$WORK/project/.codex/agents/silent-failure-hunter.toml"
printf 'echo example\n' > "$WORK/project/example.sh"
git -C "$WORK/project" add .
git -C "$WORK/project" -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false commit -qm changed
(cd "$WORK/project" && bash "$AGENT_SOP_USER_HOME/.codex/scripts/ship-sop/codex-review.sh" --base "$BASE" --agent silent-failure-hunter) > "$WORK/review"
grep -q '^--ignore-user-config$' "$WORK/args"
grep -q '^plugins$' "$WORK/args"
grep -q '^apps$' "$WORK/args"
grep -q '^read-only$' "$WORK/args"; grep -q '^hooks$' "$WORK/args"
grep -q 'Verdict: PASS' "$WORK/review"
! grep -q UNTRUSTED_REVIEW_POLICY "$WORK/prompt"
test "$(cat "$WORK/root")" != "$WORK/project"
test ! -d "$(cat "$WORK/root")"
test ! -e "$WORK/compromised"
printf 'PASS: reviewer runs in independent clone with read-only sandbox and cleans up\n'
export MOCK_VERDICT=$'Verdict: PASS\nVerdict: BLOCK'
if (cd "$WORK/project" && bash "$AGENT_SOP_USER_HOME/.codex/scripts/ship-sop/codex-review.sh" --base "$BASE" --agent silent-failure-hunter) > "$WORK/conflict" 2>&1; then
    echo 'FAIL: conflicting verdicts accepted'; exit 1
fi
unset MOCK_VERDICT
if (cd "$WORK/project" && bash "$AGENT_SOP_USER_HOME/.codex/scripts/ship-sop/codex-review.sh" --base "$BASE" --agent nonexistent) > "$WORK/unknown" 2>&1; then echo 'FAIL: unknown reviewer accepted'; exit 1; fi
grep -q INCOMPLETE "$WORK/unknown"
printf '# ship-sop runtime artifacts\n.ship/\n' > "$WORK/project/.gitignore"
mkdir -p "$WORK/project/.ship"
printf 'preserve\n' > "$WORK/project/.ship/state"
bash "$SOURCE/setup.sh" "$WORK/project" --runtime claude --uninstall > "$WORK/claude-uninstall"
grep -q '^.ship/$' "$WORK/project/.gitignore"
test -f "$WORK/project/.ship/state"
test -f "$WORK/project/ship-sop.config.json"
bash "$SOURCE/setup.sh" "$WORK/project" --runtime codex --uninstall > "$WORK/uninstall"
test -f "$WORK/project/AGENTS.md"; test -f "$WORK/project/ship-sop.config.json"
test ! -f "$AGENT_SOP_USER_HOME/.agents/skills/ship/SKILL.md"
printf 'PASS: missing reviewers fail and uninstall preserves project data\n'

# A wrapper on disk does not validate registrations pointing elsewhere.
mkdir -p "$WORK/project/docs/sop" "$AGENT_SOP_USER_HOME/.codex/scripts/hooks/agent-sop"
printf '# SOP\n' > "$WORK/project/docs/sop/claude-agent-sop.md"
printf '# Backlog\n' > "$WORK/project/Backlog.md"
printf '#!/bin/sh\n' > "$AGENT_SOP_USER_HOME/.codex/scripts/hooks/agent-sop/sop-codex-hook.sh"
printf '{"hooks":{"Stop":[{"hooks":[{"command":"bash /missing/sop-codex-hook.sh Stop"}]}],"PreToolUse":[{"hooks":[{"command":"bash /missing/sop-codex-hook.sh PreToolUse"}]}]}}\n' > "$AGENT_SOP_USER_HOME/.codex/hooks.json"
if bash "$SOURCE/setup.sh" "$WORK/project" --runtime codex > "$WORK/stale-hooks" 2>&1; then
    echo 'FAIL: stale hook registrations accepted'; exit 1
fi
printf 'PASS: stale registered hook paths rejected\n'

mkdir -p "$AGENT_SOP_USER_HOME/.claude" "$WORK/project/.claude"
printf '{"hooks":{"Stop":[{"hooks":[{"command":"bash /missing/sop-stop-drift.sh"}]}]}}\n' > "$AGENT_SOP_USER_HOME/.claude/settings.json"
printf '{"hooks":{"Stop":[{"hooks":[{"command":"scripts/auto-ship-hook.sh"}]}]}}\n' > "$WORK/project/.claude/settings.json"
cp "$WORK/project/.claude/settings.json" "$WORK/legacy-before"
if bash "$SOURCE/setup.sh" "$WORK/project" --runtime claude > "$WORK/stale-claude-hooks" 2>&1; then
    echo 'FAIL: stale Claude registration accepted'; exit 1
fi
cmp "$WORK/legacy-before" "$WORK/project/.claude/settings.json"
printf 'PASS: stale unified hooks cannot retire the legacy handler\n'
