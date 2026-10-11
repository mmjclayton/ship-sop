#!/usr/bin/env bash
#
# Fixtures for the push gate (scripts/hooks/sop-push-gate.sh), the rules it reads
# from sop-lib.sh (project type, reviewer scope, receipt validation, coverage) and
# the Codex dispatcher (sop-codex-hook.sh).
#
# Fixtures are real repositories with a bare origin, built in a temp dir, so
# default-branch detection and merge-base behave as in production. HOME is
# redirected so the suite never touches the machine's real settings.
#
# The gate must be silent (exit 0, empty stderr) whenever its condition does not
# hold, and may only exit 0 or 2: Claude Code treats any other exit as "allow".
#
# Run from the repo root: bash tests/push-gate.sh

set -u

SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
HOOKS_DIR="$SOURCE/scripts/hooks"
PUSH="$HOOKS_DIR/sop-push-gate.sh"
PTYPE="$HOOKS_DIR/sop-project-type.sh"
CODEX_HOOK="$HOOKS_DIR/sop-codex-hook.sh"

TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd -P)
# A suite that stops early (an unbound variable, a missing helper) must not
# report success: the trap fails it unless the last line ran.
SUITE_DONE=0
suite_trap() {
    local rc=$?
    [ "$SUITE_DONE" = 1 ] || { echo "FAIL: suite stopped before its last check" >&2; rc=1; }
    rm -rf "$TMP"
    exit "$rc"
}
trap suite_trap EXIT

export HOME="$TMP/home"
mkdir -p "$HOME"
unset CODEX_HOME AGENT_SOP_RUNTIME AGENT_SOP_CONFIG_HOME
export AGENT_SOP_USER_HOME="$HOME"

GIT="git -c user.email=t@t -c user.name=t -c commit.gpgsign=false"

pass=0
fail=0
failed=""
ok()  { echo "PASS: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1 - $2"; fail=$((fail + 1)); failed="$failed $1"; }

# ── Fixture builders ──────────────────────────────────────────────────────────

# make_receipt <root> <output> [names-json]: a schema-1 receipt of successful
# reviewers for the fixture's policy; names limits it to those reviewers.
make_receipt() (
    . "$HOOKS_DIR/sop-lib.sh"
    local root="$1" output="$2" names="${3:-null}" head
    head=$(git -C "$root" rev-parse HEAD)
    jq -n --arg head "$head" --arg base "$(sop_range_base "$root")" \
      --arg tree "$(git -C "$root" rev-parse 'HEAD^{tree}')" \
      --arg policy "$(sop_policy_digest "$root/ship-sop.config.json")" \
      --slurpfile cfg "$root/ship-sop.config.json" --argjson names "$names" \
      '{schema_version:1,head:$head,base:$base,tree:$tree,policy_sha256:$policy,
        tests:{status:"PASS",evidence:"fixture tests"},
        reviewers:[$cfg[0].agents|to_entries[]|select(.value.enabled)|
          . as $e|select($names == null or ($names | index($e.key)) != null)|
          {name:.key,version:"fixture-v1",model:"fixture",verdict:"PASS",findings:[]}]}' > "$output"
)

# make_repo <dir> [prose|code]: a bare origin at <dir>.git and a clone at <dir>
# with one commit pushed to main. "prose" adds Backlog.md and a CLAUDE.md with no
# code signal (a non-code project); "code" adds package.json as well.
make_repo() {
    local dir="$1" kind="${2:-}"
    $GIT init -q --bare -b main "$dir.git"
    $GIT clone -q "$dir.git" "$dir" 2>/dev/null
    (
        cd "$dir" || exit 1
        echo "# app" > README.md
        if [ -n "$kind" ]; then
            mkdir -p docs/reviews
            printf '# Backlog\n\n### P1 - First thing\n`[OPEN] [Feature]`\n\nbody\n\n---\n' > Backlog.md
            printf '# CLAUDE\n' > CLAUDE.md
        fi
        [ "$kind" != code ] || echo '{ "name": "fixture", "private": true }' > package.json
        $GIT add -A >/dev/null
        $GIT commit -q -m "init"
        $GIT push -q -u origin main 2>/dev/null
    )
}

# commit_code <dir> <msg>: twelve new lines of JavaScript, committed.
commit_code() {
    (
        cd "$1" || exit 1
        for i in $(seq 1 12); do echo "line $RANDOM $i" >> src.js; done
        $GIT add -A >/dev/null
        $GIT commit -q -m "$2"
    )
}

# configure <dir> <config-file>: commit the config to main and push it.
configure() {
    cp "$2" "$1/ship-sop.config.json"
    (cd "$1" && $GIT add -A >/dev/null && $GIT commit -q -m "chore: ship-sop config" && $GIT push -q origin main 2>/dev/null)
}

# run_hook <script> <cwd> <json-extra> [env VAR=val ...]: feeds the hook a
# synthesised input JSON and captures exit, stdout and stderr.
run_hook() {
    local script="$1" cwd="$2" extra="$3"; shift 3
    local json
    json=$(printf '{"session_id":"s1","cwd":"%s"%s}' "$cwd" "$extra")
    HOOK_OUT="$TMP/out"; HOOK_ERR="$TMP/err"
    ( cd "$cwd" 2>/dev/null || cd "$TMP" || exit 1; env "$@" bash "$script" >"$HOOK_OUT" 2>"$HOOK_ERR" <<<"$json" )
    HOOK_EXIT=$?
    # Suite-wide invariant: the gate may only exit 0 (silently) or 2 (refusing).
    if [ "$script" = "${PUSH:-}" ]; then
        case "$HOOK_EXIT" in
            0) [ ! -s "$HOOK_ERR" ] || bad "push-gate-invariant" "exit 0 with stderr '$(head -2 "$HOOK_ERR")' for $extra" ;;
            2) ;;
            *) bad "push-gate-invariant" "exit $HOOK_EXIT for $extra: $(head -2 "$HOOK_ERR")" ;;
        esac
    fi
}

head_of() { git -C "$1" rev-parse HEAD; }

# push_json <command>: the PreToolUse(Bash) fields for a push-gate case. Defined
# before any case: a case that calls it before its definition feeds the hook no
# command, and the hook is then silent for the wrong reason.
push_json() { printf ',"tool_name":"Bash","tool_input":{"command":"%s"}' "$1"; }
# jq_push_json <command>: the same, for commands with backslashes or quotes.
jq_push_json() { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | sed 's/^{/,/; s/}$//'; }

refused()  { [ "$HOOK_EXIT" = 2 ] && grep -q "push refused" "$HOOK_ERR"; }
allowed()  { [ "$HOOK_EXIT" = 0 ] && [ ! -s "$HOOK_ERR" ]; }

CFG="$TMP/auto-config.json"
cat > "$CFG" <<'JSON'
{ "trigger": { "mode": "auto", "throttle": { "min_diff_lines": 10, "skip_branch_patterns": ["^wip/"] } },
  "agents": { "security-reviewer": { "enabled": true, "block_on": "CRITICAL" },
              "code-reviewer": { "enabled": true, "block_on": "HIGH" },
              "diagram-builder": { "enabled": false, "block_on": "never" } } }
JSON

# ── Project type ──────────────────────────────────────────────────────────────
# ship-sop fires for coding and for nothing else; one function decides what
# "coding" is, and these cases pin it.

ptype() { bash "$PTYPE" "$1" 2>/dev/null; }

PROSE_T="$TMP/prose-type"; make_repo "$PROSE_T" prose
CODE_T="$TMP/code-type"; make_repo "$CODE_T" code
mkdir -p "$TMP/notrepo"
if [ "$(ptype "$PROSE_T")" = "non-code" ]; then ok "type-prose-is-non-code"; else bad "type-prose-is-non-code" "got '$(ptype "$PROSE_T")'"; fi
if [ "$(ptype "$CODE_T")" = "code" ]; then ok "type-manifest-is-code"; else bad "type-manifest-is-code" "got '$(ptype "$CODE_T")'"; fi
if [ "$(ptype "$TMP/notrepo")" = "non-code" ]; then ok "type-not-a-repo-is-non-code"; else bad "type-not-a-repo-is-non-code" "got '$(ptype "$TMP/notrepo")'"; fi
if [ "$(cd "$CODE_T" && bash "$PTYPE")" = "code" ]; then ok "type-defaults-to-current-repo"; else bad "type-defaults-to-current-repo" "got '$(cd "$CODE_T" && bash "$PTYPE")'"; fi

TYPED="$TMP/typed"; mkdir -p "$TYPED"
echo '{}' > "$TYPED/package.json"
printf '# X\n\n**Project type:** non-code\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "non-code" ]; then ok "type-declaration-overrides-manifest"; else bad "type-declaration-overrides-manifest" "got '$(ptype "$TYPED")'"; fi
rm -f "$TYPED/package.json"
printf '# X\n\nProject type: Code\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "code" ]; then ok "type-declaration-code-without-manifest"; else bad "type-declaration-code-without-manifest" "got '$(ptype "$TYPED")'"; fi
printf '# X\n\n## Auth\n\nsupabase\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "code" ]; then ok "type-auth-heading-is-code"; else bad "type-auth-heading-is-code" "got '$(ptype "$TYPED")'"; fi
printf '# X\n\nStarted from claude-md-template-code.md\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "code" ]; then ok "type-code-template-reference-is-code"; else bad "type-code-template-reference-is-code" "got '$(ptype "$TYPED")'"; fi
printf '# X\n\n## Key Commands\n\n```bash\nnpm test\n```\n\n## Other\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "code" ]; then ok "type-key-commands-test-is-code"; else bad "type-key-commands-test-is-code" "got '$(ptype "$TYPED")'"; fi
printf '# X\n\n## Key Commands\n\n```bash\npython3 check-invariants.py   # the test suite for the prose\n```\n\n## Other\n\nnpm test is not run here.\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "non-code" ]; then ok "type-test-word-in-prose-is-non-code"; else bad "type-test-word-in-prose-is-non-code" "got '$(ptype "$TYPED")'"; fi
# A fenced example is not a declaration; a bulleted or CRLF one is.
printf '# X\n\nHow to declare:\n\n```\n**Project type:** code\n```\n\nProse only here.\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "non-code" ]; then ok "type-fenced-example-is-not-a-declaration"; else bad "type-fenced-example-is-not-a-declaration" "got '$(ptype "$TYPED")'"; fi
printf '# X\n\n- **Project type:** code\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "code" ]; then ok "type-bulleted-declaration-counts"; else bad "type-bulleted-declaration-counts" "got '$(ptype "$TYPED")'"; fi
printf '# X\n\n**Project type:** code\r\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "code" ]; then ok "type-crlf-declaration-counts"; else bad "type-crlf-declaration-counts" "got '$(ptype "$TYPED")'"; fi
printf '# X\n\n## Key Commands\n\n```bash\nnpm test\n```\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "code" ]; then ok "type-key-commands-last-section-counts"; else bad "type-key-commands-last-section-counts" "got '$(ptype "$TYPED")'"; fi
rm -f "$TYPED/CLAUDE.md"; mkdir -p "$TYPED/packages/app" && echo '{}' > "$TYPED/packages/app/package.json"
if [ "$(ptype "$TYPED")" = "non-code" ]; then ok "type-manifest-in-subdirectory-only-is-non-code"; else bad "type-manifest-in-subdirectory-only-is-non-code" "got '$(ptype "$TYPED")'"; fi
rm -rf "$TYPED/packages"
# One invalid byte must not blank the whole parse (the library runs in the C locale).
printf '# X\n\npasted quote: \xff\xfe\n\n**Project type:** code\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "code" ]; then ok "type-invalid-byte-does-not-blank-declaration"; else bad "type-invalid-byte-does-not-blank-declaration" "got '$(ptype "$TYPED")'"; fi
printf '# X\n\n\xff\n## Auth\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "code" ]; then ok "type-invalid-byte-does-not-blank-heuristics"; else bad "type-invalid-byte-does-not-blank-heuristics" "got '$(ptype "$TYPED")'"; fi
printf '# X\n\n## AUTH\n\nx\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "code" ]; then ok "type-heading-case-insensitive"; else bad "type-heading-case-insensitive" "got '$(ptype "$TYPED")'"; fi
printf '# X\n\n## Key commands\n\n```\nNPM TEST\n```\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "code" ]; then ok "type-key-commands-case-insensitive"; else bad "type-key-commands-case-insensitive" "got '$(ptype "$TYPED")'"; fi
printf '# X\n\n**Project type:** code-focused rewrite\n' > "$TYPED/CLAUDE.md"
if [ "$(ptype "$TYPED")" = "code" ]; then ok "type-declaration-followed-by-hyphen"; else bad "type-declaration-followed-by-hyphen" "got '$(ptype "$TYPED")'"; fi

# AGENTS.md is canonical when it declares a type; a bridge without one falls back.
DUAL="$TMP/dual"; mkdir -p "$DUAL"
printf '# Agents\n' > "$DUAL/AGENTS.md"; printf '**Project type:** code\n' > "$DUAL/CLAUDE.md"
if [ "$(ptype "$DUAL")" = "code" ]; then ok "type-bridge-agents-falls-back-to-claude"; else bad "type-bridge-agents-falls-back-to-claude" "got '$(ptype "$DUAL")'"; fi
printf '**Project type:** non-code\n' > "$DUAL/AGENTS.md"
if [ "$(ptype "$DUAL")" = "non-code" ]; then ok "type-agents-declaration-wins"; else bad "type-agents-declaration-wins" "got '$(ptype "$DUAL")'"; fi
printf -- '- **Project type:** code\n' > "$DUAL/AGENTS.md"; printf '**Project type:** non-code\n' > "$DUAL/CLAUDE.md"
if [ "$(ptype "$DUAL")" = "code" ]; then ok "type-bulleted-agents-declaration-wins"; else bad "type-bulleted-agents-declaration-wins" "got '$(ptype "$DUAL")'"; fi
# A dangling AGENTS.md must not downgrade the gate.
DANGLE="$TMP/dangling"; mkdir -p "$DANGLE"
printf '**Project type:** non-code\n' > "$DANGLE/CLAUDE.md"; ln -s missing-instructions "$DANGLE/AGENTS.md"
if [ "$(ptype "$DANGLE")" = "code" ]; then ok "type-dangling-agents-md-stays-code"; else bad "type-dangling-agents-md-stays-code" "got '$(ptype "$DANGLE")'"; fi

# ── Push gate ─────────────────────────────────────────────────────────────────

run_hook "$PUSH" "$CODE_T" "$(push_json 'ls -la')"
if allowed; then ok "push-non-push-command-silent"; else bad "push-non-push-command-silent" "exit $HOOK_EXIT"; fi
run_hook "$PUSH" "$CODE_T" "$(push_json 'git push origin main')"
if allowed; then ok "push-no-shipsop-config-allowed"; else bad "push-no-shipsop-config-allowed" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
run_hook "$PUSH" "$TMP/notrepo" "$(push_json 'git push origin main')"
if allowed; then ok "push-outside-a-repo-allowed"; else bad "push-outside-a-repo-allowed" "exit $HOOK_EXIT"; fi
run_hook "$PUSH" "$CODE_T" ',"tool_name":"Write","tool_input":{"file_path":"x"}'
if allowed; then ok "push-other-tool-silent"; else bad "push-other-tool-silent" "exit $HOOK_EXIT"; fi

GATED="$TMP/gated"; make_repo "$GATED" code
configure "$GATED" "$CFG"
git -C "$GATED" checkout -q -b feat/push
commit_code "$GATED" "feat: needs review"
run_hook "$PUSH" "$GATED" "$(push_json 'git push -u origin feat/push')"
if refused && grep -q "SOP_SKIP_GATE=1" "$HOOK_ERR" && grep -q "ship-auto.md" "$HOOK_ERR" && grep -q "@security-reviewer" "$HOOK_ERR" && grep -q "@code-reviewer" "$HOOK_ERR" && ! grep -q "diagram-builder" "$HOOK_ERR"; then ok "push-uncovered-refused-names-enabled-agents"; else bad "push-uncovered-refused-names-enabled-agents" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
# The demand tells the session how to run the agents and never to file findings to Backlog.md.
if grep -q 'isolation: "worktree"' "$HOOK_ERR" && grep -q "file nothing to Backlog.md" "$HOOK_ERR"; then ok "push-demand-names-isolation-and-no-backlog-filing"; else bad "push-demand-names-isolation-and-no-backlog-filing" "stderr='$(cat "$HOOK_ERR")'"; fi

run_hook "$PUSH" "$GATED" "$(push_json 'gh pr create --fill')"
if refused; then ok "push-gh-pr-create-refused"; else bad "push-gh-pr-create-refused" "exit $HOOK_EXIT"; fi

# Branches matching skip_branch_patterns and manual mode are not gated.
git -C "$GATED" checkout -q -b wip/try
run_hook "$PUSH" "$GATED" "$(push_json 'git push origin wip/try')"
if allowed; then ok "push-skip-branch-pattern-allowed"; else bad "push-skip-branch-pattern-allowed" "exit $HOOK_EXIT"; fi
git -C "$GATED" checkout -q feat/push
jq '.trigger.mode = "manual"' "$CFG" > "$GATED/ship-sop.config.json"
run_hook "$PUSH" "$GATED" "$(push_json 'git push origin feat/push')"
if allowed; then ok "push-manual-mode-allowed"; else bad "push-manual-mode-allowed" "exit $HOOK_EXIT"; fi
git -C "$GATED" checkout -q -- ship-sop.config.json

run_hook "$PUSH" "$GATED" "$(push_json 'SOP_SKIP_GATE=1 git push -u origin feat/push')"
if [ "$HOOK_EXIT" = 0 ] && [ -s "$GATED/.ship/bypass.log" ] && grep -q "$(head_of "$GATED")" "$GATED/.ship/bypass.log"; then ok "push-skip-env-allowed-and-logged"; else bad "push-skip-env-allowed-and-logged" "exit $HOOK_EXIT log='$(cat "$GATED/.ship/bypass.log" 2>/dev/null)'"; fi

# Shell-wrapped invocations are caught; a push verb inside quoted prose is not.
run_hook "$PUSH" "$GATED" "$(push_json "bash -c 'git push origin feat/push'")"
if [ "$HOOK_EXIT" = 2 ]; then ok "push-bash-c-wrapper-refused"; else bad "push-bash-c-wrapper-refused" "exit $HOOK_EXIT"; fi
run_hook "$PUSH" "$GATED" "$(push_json 'sh -c \"gh pr create --fill\"')"
if [ "$HOOK_EXIT" = 2 ]; then ok "push-sh-c-double-quoted-refused"; else bad "push-sh-c-double-quoted-refused" "exit $HOOK_EXIT"; fi
# A wrapper whose body is not a push, followed by a real push, is still refused, and a
# non-push wrapper alone passes cleanly (both once crashed the gate and let a push through).
run_hook "$PUSH" "$GATED" "$(push_json "bash -c 'ls' && git push origin feat/push")"
if [ "$HOOK_EXIT" = 2 ]; then ok "push-after-nonpush-wrapper-refused"; else bad "push-after-nonpush-wrapper-refused" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
run_hook "$PUSH" "$GATED" "$(push_json "eval 'ls' && git push origin feat/push")"
if [ "$HOOK_EXIT" = 2 ]; then ok "push-after-nonpush-eval-refused"; else bad "push-after-nonpush-eval-refused" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
run_hook "$PUSH" "$GATED" "$(push_json "T=/tmp; TMPDIR=\$T bash -c 'echo \$TMPDIR; mktemp'")"
if allowed; then ok "push-nonpush-wrapper-clean"; else bad "push-nonpush-wrapper-clean" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
# The gate keys on ship-sop.config.json, not on Backlog.md or other project files.
SLIM="$TMP/slim-gated"; cp -R "$GATED" "$SLIM"
git -C "$SLIM" rm -q --ignore-unmatch Backlog.md CLAUDE.md >/dev/null
$GIT -C "$SLIM" commit -qm "slim: no tracker" >/dev/null
run_hook "$PUSH" "$SLIM" "$(push_json 'git push origin feat/push')"
if [ "$HOOK_EXIT" = 2 ]; then ok "push-gated-without-backlog"; else bad "push-gated-without-backlog" "exit $HOOK_EXIT"; fi
rm -f "$SLIM/ship-sop.config.json"
run_hook "$PUSH" "$SLIM" "$(push_json 'git push origin feat/push')"
if [ "$HOOK_EXIT" = 0 ]; then ok "push-ungated-without-ship-sop-config"; else bad "push-ungated-without-ship-sop-config" "exit $HOOK_EXIT"; fi

# Forms that once slipped past the gate. Each must be refused.
for c in "git -C $GATED push origin feat/push" "git -c core.x=y push" "git --git-dir $GATED/.git push" \
    "bash -e -c 'git push'" "bash --login -c 'git push'" "bash -o pipefail -c 'git push'" "git 'push' origin feat/push" \
    "gh -R o/r pr create --fill" "/usr/bin/git push" "\\git push" "bash -O extglob -c 'git push'" "bash -c -- 'git push'" \
    "git p'u'sh origin feat/push" "python3 -c \"import os; os.system('git push')\"" "bash <<< 'git push'" \
    "git \\
push origin feat/push" "git -C . \\
  push" 'git pu\sh origin feat/push' "echo 'git push' | bash" "printf 'git push\\n' | sh" "bash -s <<<'git push'"; do
    run_hook "$PUSH" "$GATED" "$(jq_push_json "$c")"
    if refused; then ok "push-form-refused: $c"; else bad "push-form-refused: $c" "exit $HOOK_EXIT $(head -1 "$HOOK_ERR")"; fi
done
NESTED=$(printf '%s' "bash -c 'bash -c \"bash -c \\\"bash -c git push\\\"\"'")
run_hook "$PUSH" "$GATED" "$(jq_push_json "$NESTED")"
if refused; then ok "push-escaped-nested-wrapper-refused"; else bad "push-escaped-nested-wrapper-refused" "exit $HOOK_EXIT cmd=$NESTED"; fi
# A stray << on one line does not hide a push on the next.
run_hook "$PUSH" "$GATED" "$(push_json 'echo '"'"'<<x'"'"'\ngit push origin feat/push')"
if [ "$HOOK_EXIT" = 2 ]; then ok "push-after-stray-heredoc-marker-refused"; else bad "push-after-stray-heredoc-marker-refused" "exit $HOOK_EXIT"; fi
run_hook "$PUSH" "$GATED" "$(push_json 'echo $((1<<x))\ngit push origin feat/push')"
if [ "$HOOK_EXIT" = 2 ]; then ok "push-after-arithmetic-shift-refused"; else bad "push-after-arithmetic-shift-refused" "exit $HOOK_EXIT"; fi
# A here-document fed to a shell runs its body, whichever side of the marker the shell is on.
run_hook "$PUSH" "$GATED" "$(push_json 'bash <<EOF\ngit push origin feat/push\nEOF')"
if [ "$HOOK_EXIT" = 2 ]; then ok "push-heredoc-to-shell-refused"; else bad "push-heredoc-to-shell-refused" "exit $HOOK_EXIT"; fi
for c in 'cat <<EOF | bash\ngit push origin feat/push\nEOF' 'cat <<EOF | tee x.sh | bash\ngit push\nEOF' 'cat <<'"'"'EOF'"'"' | sh\ngit push\nEOF'; do
    run_hook "$PUSH" "$GATED" "$(push_json "$c")"
    if [ "$HOOK_EXIT" = 2 ]; then ok "push-heredoc-piped-to-shell-refused: $c"; else bad "push-heredoc-piped-to-shell-refused: $c" "exit $HOOK_EXIT"; fi
done
run_hook "$PUSH" "$GATED" "$(push_json 'cat <<EOF | tee notes.md\nthen git push\nEOF')"
if [ "$HOOK_EXIT" = 0 ]; then ok "push-heredoc-piped-to-tee-allowed"; else bad "push-heredoc-piped-to-tee-allowed" "exit $HOOK_EXIT"; fi
run_hook "$PUSH" "$GATED" "$(push_json 'cat > notes.md <<EOF\nrun bash -c x first\nthen git push\nEOF')"
if [ "$HOOK_EXIT" = 0 ]; then ok "push-doc-heredoc-mentioning-shell-allowed"; else bad "push-doc-heredoc-mentioning-shell-allowed" "exit $HOOK_EXIT"; fi
run_hook "$PUSH" "$GATED" "$(push_json 'cat > notes.md <<EOF\nremember to git push\nEOF')"
if [ "$HOOK_EXIT" = 0 ]; then ok "push-heredoc-body-prose-allowed"; else bad "push-heredoc-body-prose-allowed" "exit $HOOK_EXIT"; fi
# Commands that only look similar pass.
for c in "git stash push" "git log --format=push" "npm run push-stats" "bash -c 'ls' && sh -c 'pwd'" "python3 -c 'print(1)'" "gh pr view" "cd /tmp/digit && ls" \
    "npm test \\
  --silent" "bash -c 'ls' \\
  && echo done"; do
    run_hook "$PUSH" "$GATED" "$(jq_push_json "$c")"
    if [ "$HOOK_EXIT" = 0 ]; then ok "push-lookalike-allowed: $c"; else bad "push-lookalike-allowed: $c" "exit $HOOK_EXIT"; fi
done
# The bypass form the refusal message suggests does bypass.
run_hook "$PUSH" "$GATED" "$(push_json 'cd . && SOP_SKIP_GATE=1 git push origin feat/push')"
if [ "$HOOK_EXIT" = 0 ]; then ok "push-suggested-bypass-form-works"; else bad "push-suggested-bypass-form-works" "exit $HOOK_EXIT"; fi
# The bypass counts only on the push itself: a message that mentions it is not one.
: > "$GATED/.ship/bypass.log"
run_hook "$PUSH" "$GATED" "$(push_json 'git commit -m \"SOP_SKIP_GATE=1\" && git push origin feat/push')"
if [ "$HOOK_EXIT" = 2 ] && [ ! -s "$GATED/.ship/bypass.log" ]; then ok "push-skip-in-message-not-a-bypass"; else bad "push-skip-in-message-not-a-bypass" "exit $HOOK_EXIT log='$(cat "$GATED/.ship/bypass.log")'"; fi
# Fails closed: an internal error refuses instead of exiting 1 (which Claude Code allows).
BROKEN="$TMP/broken-hooks"; mkdir -p "$BROKEN"; cp "$PUSH" "$HOOKS_DIR/sop-lib.sh" "$BROKEN/"
printf '\nsop_is_push_command() { printf "%%s" "$undefined_in_fixture"; }\n' >> "$BROKEN/sop-lib.sh"
SAVED_PUSH=$PUSH; PUSH=""
run_hook "$BROKEN/sop-push-gate.sh" "$GATED" "$(push_json 'git push origin feat/push')"
PUSH=$SAVED_PUSH
if [ "$HOOK_EXIT" = 2 ] && grep -q "push gate internal error" "$HOOK_ERR"; then ok "push-gate-internal-error-refuses"; else bad "push-gate-internal-error-refuses" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
# Without jq the gate cannot parse input: it refuses push-like commands and passes others.
NOJQ="$TMP/nojq-bin"; mkdir -p "$NOJQ"; for b in bash dirname grep sed cat; do ln -sf "$(command -v $b)" "$NOJQ/$b"; done
run_hook "$PUSH" "$GATED" "$(push_json 'git push origin feat/push')" PATH="$NOJQ"
if [ "$HOOK_EXIT" = 2 ] && grep -q "jq is not installed" "$HOOK_ERR"; then ok "push-no-jq-refuses-push"; else bad "push-no-jq-refuses-push" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
run_hook "$PUSH" "$GATED" "$(push_json 'echo new > Projects-github-notes.txt')" PATH="$NOJQ"
if [ "$HOOK_EXIT" = 0 ]; then ok "push-no-jq-passes-other"; else bad "push-no-jq-passes-other" "exit $HOOK_EXIT"; fi

run_hook "$PUSH" "$GATED" "$(push_json "eval 'git push'")"
if [ "$HOOK_EXIT" = 2 ]; then ok "push-eval-wrapper-refused"; else bad "push-eval-wrapper-refused" "exit $HOOK_EXIT"; fi
run_hook "$PUSH" "$GATED" "$(push_json 'echo done && `git push`')"
if [ "$HOOK_EXIT" = 2 ]; then ok "push-backtick-refused"; else bad "push-backtick-refused" "exit $HOOK_EXIT"; fi
run_hook "$PUSH" "$GATED" "$(push_json 'echo \"remember to run git push after this\"')"
if allowed; then ok "push-verb-in-quoted-prose-silent"; else bad "push-verb-in-quoted-prose-silent" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
run_hook "$PUSH" "$GATED" "$(push_json "cat > notes.md <<EOF\nRemember to run git push and then gh pr create.\nEOF")"
if allowed; then ok "push-verb-in-heredoc-body-silent"; else bad "push-verb-in-heredoc-body-silent" "exit $HOOK_EXIT stderr='$(head -1 "$HOOK_ERR")'"; fi
run_hook "$PUSH" "$GATED" "$(push_json "cat > notes.md <<EOF\nplain notes\nEOF\ngit push -u origin feat/push")"
if [ "$HOOK_EXIT" = 2 ]; then ok "push-after-heredoc-still-refused"; else bad "push-after-heredoc-still-refused" "exit $HOOK_EXIT"; fi
run_hook "$PUSH" "$GATED" "$(push_json "git commit -m 'then git push'")"
if allowed; then ok "push-verb-in-commit-message-silent"; else bad "push-verb-in-commit-message-silent" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi

# A Markdown report alone is not coverage; a valid receipt is.
printf '# report\n\nCovers: %s\n' "$(head_of "$GATED")" > "$GATED/docs/reviews/20260904-110000-ship-auto.md"
run_hook "$PUSH" "$GATED" "$(push_json 'git push -u origin feat/push')"
if refused; then ok "push-markdown-covers-line-is-not-coverage"; else bad "push-markdown-covers-line-is-not-coverage" "exit $HOOK_EXIT"; fi
make_receipt "$GATED" "$GATED/docs/reviews/20260904-110000-ship-auto.json"
run_hook "$PUSH" "$GATED" "$(push_json 'git push -u origin feat/push')"
if allowed; then ok "push-covered-allowed"; else bad "push-covered-allowed" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
# Committing the receipt keeps coverage; a later code commit loses it.
(cd "$GATED" && $GIT add -A >/dev/null && $GIT commit -q -m "docs: ship report")
run_hook "$PUSH" "$GATED" "$(push_json 'git push -u origin feat/push')"
if allowed; then ok "push-covered-after-committing-receipt"; else bad "push-covered-after-committing-receipt" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
commit_code "$GATED" "feat: more code"
run_hook "$PUSH" "$GATED" "$(push_json 'git push -u origin feat/push')"
if refused; then ok "push-later-code-commit-uncovers"; else bad "push-later-code-commit-uncovers" "exit $HOOK_EXIT"; fi

# ── Project type at the gate ──────────────────────────────────────────────────
# A prose repository with an auto config gets no gate; a declaration opts it in,
# and a non-code declaration over a manifest is honoured.
PROSE="$TMP/prose"; make_repo "$PROSE" prose
configure "$PROSE" "$CFG"
git -C "$PROSE" checkout -q -b feat/prose
commit_code "$PROSE" "feat: a script in a prose repo"
run_hook "$PUSH" "$PROSE" "$(push_json 'git push -u origin feat/prose')"
if allowed; then ok "push-non-code-project-allowed"; else bad "push-non-code-project-allowed" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
printf '\n**Project type:** code\n' >> "$PROSE/CLAUDE.md"
run_hook "$PUSH" "$PROSE" "$(push_json 'git push -u origin feat/prose')"
if [ "$HOOK_EXIT" = 2 ] && grep -q "ship-auto.md" "$HOOK_ERR"; then ok "push-declared-code-refused"; else bad "push-declared-code-refused" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi

CONTRA="$TMP/contra"; make_repo "$CONTRA" code
printf '# CLAUDE\n\n**Project type:** non-code\n' > "$CONTRA/CLAUDE.md"
configure "$CONTRA" "$CFG"
git -C "$CONTRA" checkout -q -b feat/c
commit_code "$CONTRA" "feat: code under a non-code declaration"
run_hook "$PUSH" "$CONTRA" "$(push_json 'git push -u origin feat/c')"
if allowed; then ok "push-declared-non-code-honoured"; else bad "push-declared-non-code-honoured" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi

# Code lines only: a docs-only branch gets no gate, whatever skip_docs_only says.
LOOSE="$TMP/loose"; make_repo "$LOOSE" code
jq '.trigger.throttle.skip_docs_only = false' "$CFG" > "$TMP/loose.json"
configure "$LOOSE" "$TMP/loose.json"
git -C "$LOOSE" checkout -q -b feat/prose-in-code
(cd "$LOOSE" && for i in $(seq 1 20); do echo "para $i" >> notes.md; done && $GIT add -A >/dev/null && $GIT commit -q -m "docs: notes")
run_hook "$PUSH" "$LOOSE" "$(push_json 'git push -u origin feat/prose-in-code')"
if allowed; then ok "push-docs-only-branch-allowed"; else bad "push-docs-only-branch-allowed" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
# A covered code branch stays covered through a later docs-only commit.
git -C "$LOOSE" checkout -q main && git -C "$LOOSE" checkout -q -b feat/covered
commit_code "$LOOSE" "feat: code to cover"
make_receipt "$LOOSE" "$LOOSE/docs/reviews/20260904-120000-ship-auto.json"
(cd "$LOOSE" && $GIT add -A >/dev/null && $GIT commit -q -m "docs: ship report")
(cd "$LOOSE" && for i in $(seq 1 20); do echo "more $i" >> notes.md; done && $GIT add -A >/dev/null && $GIT commit -q -m "docs: more notes")
run_hook "$PUSH" "$LOOSE" "$(push_json 'git push -u origin feat/covered')"
if allowed; then ok "push-covered-survives-docs-commit"; else bad "push-covered-survives-docs-commit" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi

# A documentation file renamed into a code file, with logic added, is code.
RENAME="$TMP/rename"; make_repo "$RENAME" code
cp "$CFG" "$RENAME/ship-sop.config.json"
(cd "$RENAME" && for i in $(seq 1 30); do echo "prose line $i" >> notes.md; done && $GIT add -A >/dev/null && $GIT commit -q -m "chore: config + notes" && $GIT push -q origin main 2>/dev/null)
git -C "$RENAME" checkout -q -b feat/rename
(cd "$RENAME" && git mv notes.md gen.js && for i in $(seq 1 12); do echo "code($i);" >> gen.js; done && $GIT add -A >/dev/null && $GIT commit -q -m "feat: notes become code")
run_hook "$PUSH" "$RENAME" "$(push_json 'git push -u origin feat/rename')"
if [ "$(git -C "$RENAME" diff --numstat origin/main..HEAD | grep -c '=>')" -ge 1 ] && refused; then ok "push-rename-doc-to-code-counts"; else bad "push-rename-doc-to-code-counts" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi

# ── Reviewer scope by path ────────────────────────────────────────────────────
# An enabled reviewer with `paths` joins the gate only when the range touches a
# matching file; the gate and the receipt validator read the same rule.
SCOPED_CFG="$TMP/scoped.json"
cat > "$SCOPED_CFG" <<'JSON'
{ "trigger": { "mode": "auto", "throttle": { "min_diff_lines": 10, "skip_branch_patterns": ["^wip/"] } },
  "agents": { "security-reviewer": { "enabled": true, "block_on": "CRITICAL", "paths": ["^scripts/", "\\.sh$"] },
              "code-reviewer": { "enabled": true, "block_on": "HIGH" } } }
JSON
SCOPED="$TMP/scoped"; make_repo "$SCOPED" code
configure "$SCOPED" "$SCOPED_CFG"
git -C "$SCOPED" checkout -q -b feat/js-only
commit_code "$SCOPED" "feat: js work"
run_hook "$PUSH" "$SCOPED" "$(push_json 'git push origin feat/js-only')"
if refused && grep -q "@code-reviewer" "$HOOK_ERR" && ! grep -q "security-reviewer" "$HOOK_ERR"; then ok "push-scoped-agent-out-of-scope-not-demanded"; else bad "push-scoped-agent-out-of-scope-not-demanded" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
make_receipt "$SCOPED" "$SCOPED/docs/reviews/20260924-100000-ship-auto.json" '["code-reviewer"]'
(cd "$SCOPED" && $GIT add -A >/dev/null && $GIT commit -q -m "docs: ship report")
run_hook "$PUSH" "$SCOPED" "$(push_json 'git push origin feat/js-only')"
if allowed; then ok "push-scoped-receipt-without-out-of-scope-agent-covers"; else bad "push-scoped-receipt-without-out-of-scope-agent-covers" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
(cd "$SCOPED" && mkdir -p scripts && for i in $(seq 1 12); do echo "echo $i" >> scripts/run.sh; done && $GIT add -A >/dev/null && $GIT commit -q -m "feat: shell work")
run_hook "$PUSH" "$SCOPED" "$(push_json 'git push origin feat/js-only')"
if refused && grep -q "@security-reviewer" "$HOOK_ERR" && grep -q "@code-reviewer" "$HOOK_ERR"; then ok "push-scoped-agent-in-scope-demanded"; else bad "push-scoped-agent-in-scope-demanded" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
make_receipt "$SCOPED" "$SCOPED/docs/reviews/20260924-110000-ship-auto.json" '["code-reviewer"]'
(cd "$SCOPED" && $GIT add -A >/dev/null && $GIT commit -q -m "docs: partial ship report")
run_hook "$PUSH" "$SCOPED" "$(push_json 'git push origin feat/js-only')"
if refused && grep -q "@security-reviewer" "$HOOK_ERR"; then ok "push-scoped-receipt-missing-in-scope-agent-does-not-cover"; else bad "push-scoped-receipt-missing-in-scope-agent-does-not-cover" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
make_receipt "$SCOPED" "$SCOPED/docs/reviews/20260924-120000-ship-auto.json"
(cd "$SCOPED" && $GIT add -A >/dev/null && $GIT commit -q -m "docs: full ship report")
run_hook "$PUSH" "$SCOPED" "$(push_json 'git push origin feat/js-only')"
if allowed; then ok "push-scoped-full-receipt-covers"; else bad "push-scoped-full-receipt-covers" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi

# Every enabled reviewer out of scope: no gate, and the push proceeds.
NOSCOPE="$TMP/noscope"; make_repo "$NOSCOPE" code
jq '.agents |= with_entries(.value.paths = ["^scripts/"])' "$SCOPED_CFG" > "$TMP/noscope.json"
configure "$NOSCOPE" "$TMP/noscope.json"
git -C "$NOSCOPE" checkout -q -b feat/js
commit_code "$NOSCOPE" "feat: js work"
run_hook "$PUSH" "$NOSCOPE" "$(push_json 'git push -u origin feat/js')"
if allowed; then ok "push-every-agent-out-of-scope-allowed"; else bad "push-every-agent-out-of-scope-allowed" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi

# A malformed scope is an invalid policy, not a silent skip.
for badcase in 'paths-not-array:"^scripts/"' 'paths-bad-regex:["("]'; do
    BADNAME=${badcase%%:*}; BADVAL=${badcase#*:}
    BAD="$TMP/$BADNAME"; make_repo "$BAD" code
    jq --argjson v "$BADVAL" '.agents["security-reviewer"].paths = $v' "$SCOPED_CFG" > "$TMP/$BADNAME.json"
    configure "$BAD" "$TMP/$BADNAME.json"
    git -C "$BAD" checkout -q -b feat/js
    commit_code "$BAD" "feat: js work"
    run_hook "$PUSH" "$BAD" "$(push_json 'git push origin feat/js')"
    if refused && grep -q "configuration invalid" "$HOOK_ERR"; then ok "push-$BADNAME-invalid"; else bad "push-$BADNAME-invalid" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi
done

# ── Receipt run counts ────────────────────────────────────────────────────────
# A version-2 receipt carries launches, rechecks and block_rounds per reviewer.
V2="$TMP/v2"; make_repo "$V2" code
configure "$V2" "$CFG"
git -C "$V2" checkout -q -b feat/counted
commit_code "$V2" "feat: counted work"
make_receipt "$V2" "$TMP/v2-base.json"
jq '.schema_version = 2' "$TMP/v2-base.json" > "$V2/docs/reviews/20260924-130000-ship-auto.json"
run_hook "$PUSH" "$V2" "$(push_json 'git push origin feat/counted')"
if refused; then ok "push-v2-receipt-without-counts-does-not-cover"; else bad "push-v2-receipt-without-counts-does-not-cover" "exit $HOOK_EXIT"; fi
jq '.schema_version = 2 | .reviewers |= map(. + {launches: 1, rechecks: 2, block_rounds: 4, usage: null})' "$TMP/v2-base.json" > "$V2/docs/reviews/20260924-130000-ship-auto.json"
run_hook "$PUSH" "$V2" "$(push_json 'git push origin feat/counted')"
if refused; then ok "push-v2-receipt-more-block-rounds-than-runs-does-not-cover"; else bad "push-v2-receipt-more-block-rounds-than-runs-does-not-cover" "exit $HOOK_EXIT"; fi
jq '.schema_version = 2 | .reviewers |= map(. + {launches: 1, rechecks: 2, block_rounds: 2, usage: null})' "$TMP/v2-base.json" > "$V2/docs/reviews/20260924-130000-ship-auto.json"
run_hook "$PUSH" "$V2" "$(push_json 'git push origin feat/counted')"
if allowed; then ok "push-v2-receipt-with-counts-covers"; else bad "push-v2-receipt-with-counts-covers" "exit $HOOK_EXIT stderr='$(cat "$HOOK_ERR")'"; fi

# ── Library rules: policy, receipts and coverage ──────────────────────────────
LIBREPO="$TMP/librepo"
git init -q -b main "$LIBREPO"
mkdir -p "$LIBREPO/docs/reviews" "$LIBREPO/.agents/skills/example"
printf '**Project type:** code\n' > "$LIBREPO/AGENTS.md"
printf 'base\n' > "$LIBREPO/code.sh"
printf '{"trigger":{"mode":"auto"},"agents":{"code-reviewer":{"enabled":true,"block_on":"HIGH"}}}\n' > "$LIBREPO/ship-sop.config.json"
$GIT -C "$LIBREPO" add .
$GIT -C "$LIBREPO" commit -qm base
LIBBASE=$(git -C "$LIBREPO" rev-parse HEAD)
git -C "$LIBREPO" update-ref refs/remotes/origin/main "$LIBBASE"
git -C "$LIBREPO" switch -qc feature/test
seq 1 15 >> "$LIBREPO/code.sh"
$GIT -C "$LIBREPO" commit -qam change
LIBHEAD=$(git -C "$LIBREPO" rev-parse HEAD)

lib() { bash -c '. "$1/sop-lib.sh"; shift; "$@"' _ "$HOOKS_DIR" "$@"; }

printf 'Example: Covers: %s\nVerdict: BLOCK\n' "$LIBHEAD" > "$LIBREPO/docs/reviews/example-ship-auto.md"
if [ -n "$(lib sop_shipsop_gate "$LIBREPO")" ]; then ok "lib-markdown-stamp-is-not-coverage"; else bad "lib-markdown-stamp-is-not-coverage" "no gate demanded"; fi
cp "$LIBREPO/ship-sop.config.json" "$TMP/libconfig"
printf '{invalid\n' > "$LIBREPO/ship-sop.config.json"
if lib sop_shipsop_gate "$LIBREPO" | grep -q "configuration invalid"; then ok "lib-invalid-policy-demands-repair"; else bad "lib-invalid-policy-demands-repair" "$(lib sop_shipsop_gate "$LIBREPO")"; fi
cp "$TMP/libconfig" "$LIBREPO/ship-sop.config.json"
POLICY_OK=1
for mutation in '.trigger.throttle=false' '.trigger.throttle.min_diff_lines=null' '.agents["code-reviewer"].block_on=false' '.trigger.mode="sometimes"'; do
    jq "$mutation" "$TMP/libconfig" > "$TMP/invalid-policy.json"
    if lib sop_policy_valid "$TMP/invalid-policy.json"; then POLICY_OK=0; bad "lib-policy-rejects: $mutation" "accepted"; fi
done
cat "$TMP/libconfig" "$TMP/libconfig" > "$TMP/invalid-policy.json"
if lib sop_policy_valid "$TMP/invalid-policy.json"; then POLICY_OK=0; bad "lib-policy-rejects-multiple-documents" "accepted"; fi
if lib sop_policy_valid "$TMP/libconfig" && [ "$POLICY_OK" = 1 ]; then ok "lib-policy-validation-rejects-false-null-and-multiple-documents"; fi

jq -n --arg head "$LIBHEAD" --arg base "$LIBBASE" \
  --arg tree "$(git -C "$LIBREPO" rev-parse 'HEAD^{tree}')" \
  --arg policy "$(lib sop_policy_digest "$LIBREPO/ship-sop.config.json")" \
  '{schema_version:1,head:$head,base:$base,tree:$tree,policy_sha256:$policy,
    tests:{status:"PASS",evidence:"real fixture"},
    reviewers:[{name:"code-reviewer",version:"v1",model:"fixture",verdict:"PASS",findings:[]}]}' > "$TMP/valid.json"
if lib sop_receipt_valid "$LIBREPO" "$TMP/valid.json"; then ok "lib-valid-receipt-accepted"; else bad "lib-valid-receipt-accepted" "rejected"; fi
for mutation in \
  '.reviewers[0].verdict="BLOCK"' \
  '.reviewers[0].verdict="INCOMPLETE"' \
  '.reviewers=[]' \
  '.reviewers += .reviewers' \
  '.reviewers[0].findings=[{severity:"HIGH",file:"code.sh",line:1,message:"bug"}]' \
  '.reviewers[0].findings=[{severity:"UNKNOWN",file:"code.sh",line:1,message:"bug"}]' \
  '.tests.status="FAIL"' \
  '.tests.evidence=""' \
  '.tree="0000000000000000000000000000000000000000"' \
  '.policy_sha256="stale"' \
  '.base=.head' \
  '.schema_version=3'; do
    jq "$mutation" "$TMP/valid.json" > "$TMP/invalid.json"
    if lib sop_receipt_valid "$LIBREPO" "$TMP/invalid.json"; then bad "lib-receipt-rejects: $mutation" "accepted"; else ok "lib-receipt-rejects: $mutation"; fi
done
# A finding below the reviewer's block_on threshold does not block.
jq '.reviewers[0].findings=[{severity:"MEDIUM",file:"code.sh",line:1,message:"style"}]' "$TMP/valid.json" > "$TMP/medium.json"
if lib sop_receipt_valid "$LIBREPO" "$TMP/medium.json"; then ok "lib-receipt-finding-below-threshold-accepted"; else bad "lib-receipt-finding-below-threshold-accepted" "rejected"; fi

cp "$TMP/valid.json" "$LIBREPO/docs/reviews/valid-ship-auto.json"
if lib sop_shipsop_covered "$LIBREPO" "$LIBHEAD"; then ok "lib-valid-receipt-covers-head"; else bad "lib-valid-receipt-covers-head" "not covered"; fi
$GIT -C "$LIBREPO" add docs/reviews
$GIT -C "$LIBREPO" commit -qm evidence
if lib sop_shipsop_covered "$LIBREPO" "$(git -C "$LIBREPO" rev-parse HEAD)"; then ok "lib-committing-receipt-preserves-coverage"; else bad "lib-committing-receipt-preserves-coverage" "not covered"; fi
# Executable Markdown (skills, agents, AGENTS.md) counts as code.
printf '# executable instructions\n' > "$LIBREPO/.agents/skills/example/SKILL.md"
$GIT -C "$LIBREPO" add .agents
$GIT -C "$LIBREPO" commit -qm instructions
if [ "$(lib sop_code_lines "$LIBREPO" "$LIBHEAD" HEAD true)" -gt 0 ] && ! lib sop_shipsop_covered "$LIBREPO" HEAD; then ok "lib-executable-markdown-invalidates-coverage"; else bad "lib-executable-markdown-invalidates-coverage" "still covered"; fi
# Content-preserving renames into or out of instruction paths invalidate coverage.
printf 'Previously inert instruction\n' > "$LIBREPO/notes.md"
$GIT -C "$LIBREPO" add notes.md && $GIT -C "$LIBREPO" commit -qm notes
INSTR_BASE=$(git -C "$LIBREPO" rev-parse HEAD)
jq --arg head "$INSTR_BASE" --arg tree "$(git -C "$LIBREPO" rev-parse 'HEAD^{tree}')" '.head=$head | .tree=$tree' "$TMP/valid.json" > "$LIBREPO/docs/reviews/valid-ship-auto.json"
mkdir -p "$LIBREPO/src"
git -C "$LIBREPO" mv notes.md src/AGENTS.md
$GIT -C "$LIBREPO" commit -qm rename-into-instructions
if lib sop_shipsop_covered "$LIBREPO" HEAD; then bad "lib-rename-into-instructions-uncovers" "still covered"; else ok "lib-rename-into-instructions-uncovers"; fi
INSTR_HEAD=$(git -C "$LIBREPO" rev-parse HEAD)
jq --arg head "$INSTR_HEAD" --arg tree "$(git -C "$LIBREPO" rev-parse 'HEAD^{tree}')" '.head=$head | .tree=$tree' "$TMP/valid.json" > "$LIBREPO/docs/reviews/valid-ship-auto.json"
git -C "$LIBREPO" mv src/AGENTS.md notes.md
$GIT -C "$LIBREPO" commit -qm rename-out-of-instructions
if lib sop_shipsop_covered "$LIBREPO" HEAD; then bad "lib-rename-out-of-instructions-uncovers" "still covered"; else ok "lib-rename-out-of-instructions-uncovers"; fi
# A one-line nested AGENTS.md still demands review, below min_diff_lines.
git -C "$LIBREPO" update-ref refs/remotes/origin/main HEAD
printf 'One instruction\n' > "$LIBREPO/src/AGENTS.md"
$GIT -C "$LIBREPO" add src/AGENTS.md
$GIT -C "$LIBREPO" commit -qm nested-instruction
if [ -n "$(lib sop_shipsop_gate "$LIBREPO")" ]; then ok "lib-nested-instructions-demand-review"; else bad "lib-nested-instructions-demand-review" "no gate"; fi

# ── Codex dispatcher ──────────────────────────────────────────────────────────
CODEX_INPUT=$(jq -nc --arg cwd "$GATED" '{cwd:$cwd,session_id:"codex-fixture",tool_name:"Bash",tool_input:{command:"git push origin HEAD"}}')
printf '%s' "$CODEX_INPUT" | CODEX_HOME="$TMP/codex" bash "$CODEX_HOOK" PreToolUse > "$TMP/cx.out" 2> "$TMP/cx.err"; CX=$?
if [ "$CX" = 2 ] && grep -q '\[ship-sop\] push refused' "$TMP/cx.err" && grep -q 'ship skill' "$TMP/cx.err"; then ok "codex-dispatcher-refuses-uncovered-push"; else bad "codex-dispatcher-refuses-uncovered-push" "exit $CX: $(cat "$TMP/cx.err")"; fi
for ev in SessionStart UserPromptSubmit Stop; do
    printf '%s' "$CODEX_INPUT" | bash "$CODEX_HOOK" "$ev" > "$TMP/cx.out" 2> "$TMP/cx.err"; CX=$?
    if [ "$CX" = 0 ] && [ ! -s "$TMP/cx.out" ] && [ ! -s "$TMP/cx.err" ]; then ok "codex-dispatcher-retired-$ev-is-a-no-op"; else bad "codex-dispatcher-retired-$ev-is-a-no-op" "exit $CX"; fi
done
bash "$CODEX_HOOK" Unknown < /dev/null > /dev/null 2> "$TMP/cx.err"; CX=$?
if [ "$CX" = 1 ] && grep -q 'expected PreToolUse' "$TMP/cx.err"; then ok "codex-dispatcher-rejects-unknown-event"; else bad "codex-dispatcher-rejects-unknown-event" "exit $CX"; fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "push-gate: $pass passed, $fail failed"
SUITE_DONE=1
[ "$fail" -eq 0 ] || { echo "Failed:$failed"; exit 1; }
exit 0
