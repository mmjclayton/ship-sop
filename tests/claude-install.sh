#!/usr/bin/env bash
# Claude installs must not enable a reviewer that Claude cannot launch.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export AGENT_SOP_USER_HOME="$WORK/user"
unset CODEX_HOME

install_claude() {
    mkdir -p "$WORK/$1"
    bash "$SOURCE/setup.sh" "$WORK/$1" --runtime claude --no-hook > "$WORK/$1.log" 2>&1
}

install_claude missing
jq -e '.agents["silent-failure-hunter"].enabled == false' "$WORK/missing/ship-sop.config.json" >/dev/null
jq -e '.agents["code-reviewer"].enabled == true' "$WORK/missing/ship-sop.config.json" >/dev/null
grep -q 'silent-failure-hunter disabled' "$WORK/missing.log"
printf 'PASS: absent silent-failure-hunter profile is disabled in a new config\n'

printf -- '---\nname: silent-failure-hunter\n---\n' > "$AGENT_SOP_USER_HOME/.claude/agents/silent-failure-hunter.md"
install_claude present
jq -e '.agents["silent-failure-hunter"].enabled == true' "$WORK/present/ship-sop.config.json" >/dev/null
printf 'PASS: installed silent-failure-hunter profile stays enabled\n'

rm "$AGENT_SOP_USER_HOME/.claude/agents/silent-failure-hunter.md"
mkdir -p "$WORK/existing"
cp "$SOURCE/docs/templates/ship-sop.config.json" "$WORK/existing/ship-sop.config.json"
cp "$WORK/existing/ship-sop.config.json" "$WORK/existing-before"
install_claude existing
cmp "$WORK/existing-before" "$WORK/existing/ship-sop.config.json"
printf 'PASS: existing config is never rewritten\n'
