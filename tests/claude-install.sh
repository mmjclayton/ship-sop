#!/usr/bin/env bash
# Claude installs must not enable a reviewer that Claude cannot launch.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export AGENT_SOP_USER_HOME="$WORK/user"
unset CODEX_HOME
PROFILE="$AGENT_SOP_USER_HOME/.claude/agents/silent-failure-hunter.md"
mkdir -p "$(dirname "$PROFILE")"

install_claude() {
    mkdir -p "$WORK/$1"
    bash "$SOURCE/setup.sh" "$WORK/$1" --runtime claude --no-hook > "$WORK/$1.log" 2>&1
}

install_claude missing
jq -e '.agents["silent-failure-hunter"].enabled == false' "$WORK/missing/ship-sop.config.json" >/dev/null
jq -e '.agents["code-reviewer"].enabled == true' "$WORK/missing/ship-sop.config.json" >/dev/null
grep -q 'silent-failure-hunter disabled' "$WORK/missing.log"
find "$WORK/missing/ship-sop.config.json" -perm 644 | grep -q .
[ -z "$(find "$WORK/missing" -maxdepth 1 -name 'ship-sop.config.json.*')" ]
printf 'PASS: absent silent-failure-hunter profile is disabled in a new, readable config\n'

printf -- '---\nname: silent-failure-hunter\n---\n' > "$PROFILE"
install_claude present
cmp "$SOURCE/docs/templates/ship-sop.config.json" "$WORK/present/ship-sop.config.json"
if grep -q 'silent-failure-hunter disabled' "$WORK/present.log"; then echo 'FAIL: reviewer disabled despite profile'; exit 1; fi
rm "$PROFILE"
mkdir -p "$WORK/project-scope/.claude/agents"
printf -- '---\nname: silent-failure-hunter\n---\n' > "$WORK/project-scope/.claude/agents/silent-failure-hunter.md"
install_claude project-scope
jq -e '.agents["silent-failure-hunter"].enabled == true' "$WORK/project-scope/ship-sop.config.json" >/dev/null
printf 'PASS: user- or project-scope profile leaves the template unchanged\n'

mkdir -p "$WORK/existing"
cp "$SOURCE/docs/templates/ship-sop.config.json" "$WORK/existing/ship-sop.config.json"
cp "$WORK/existing/ship-sop.config.json" "$WORK/existing-before"
install_claude existing
cmp "$WORK/existing-before" "$WORK/existing/ship-sop.config.json"
printf 'PASS: existing config is never rewritten\n'

# A failed edit must leave no config, so a rerun retries instead of skipping.
mkdir -p "$WORK/bin" "$WORK/nojq"
printf '#!/bin/sh\nexit 1\n' > "$WORK/bin/jq"; chmod +x "$WORK/bin/jq"
if PATH="$WORK/bin:$PATH" bash "$SOURCE/setup.sh" "$WORK/nojq" --runtime claude --no-hook > "$WORK/nojq.log" 2>&1; then
    echo 'FAIL: setup succeeded without a working jq'; exit 1
fi
grep -q 'jq is required' "$WORK/nojq.log"
test ! -e "$WORK/nojq/ship-sop.config.json"
[ -z "$(find "$WORK/nojq" -maxdepth 1 -name 'ship-sop.config.json.*')" ]
printf 'PASS: failed edit leaves no config and names jq\n'
