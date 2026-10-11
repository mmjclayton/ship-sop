#!/usr/bin/env bash
#
# ship-sop push gate: a user-scope PreToolUse(Bash) hook (Codex reaches it
# through sop-codex-hook.sh).
#
# Refuses `git push` and `gh pr create` (exit 2, reason on stderr) when all of:
#   - the repo under `cwd` is a code project with a ship-sop.config.json
#   - ship-sop.config.json has trigger.mode "auto"
#   - the code diff vs the default branch is at or over min_diff_lines
#   - no valid docs/reviews/*-ship-auto.json receipt covers HEAD
#
# It gates on "no review run covers HEAD", a fact a script can check, rather
# than on "are there findings", a model judgement.
#
# Bypass: prefix every push in the command with SOP_SKIP_GATE=1. Every bypass is
# appended to .ship/bypass.log with the HEAD it skipped, so it is greppable later.
# The bypass is for a person. Nothing the gate prints names it: stderr goes to the
# model, and a refusal that explains how to skip itself invites the skip (P44).
#
# Fails closed: Claude Code treats any exit other than 2 as "allow", so an
# internal error here once let pushes through silently. Any exit other than 0 or 2
# becomes a refusal that names the error, a library missing any function the gate
# needs is a refusal, and once a command is known to be a push every check that
# cannot be completed refuses rather than allows.

set -u
sop_gate_fail_closed() {
    local rc=$?
    case $rc in
        0|2) ;;
        *) printf '[ship-sop] push gate internal error (exit %s); command refused. Fix the hook (run its fixtures), or disable it in settings until it is fixed.\n' "$rc" >&2
           exit 2 ;;
    esac
}
trap sop_gate_fail_closed EXIT

# refuse <reason>: refuse the command (exit 2) with a reason on stderr.
refuse() { printf '[ship-sop] push refused: %s\n' "$1" >&2; exit 2; }

# Every function the library defines: the gate calls them directly or through
# the library, except sop_bypasses_since_receipt, which /ship calls. A call to a
# missing function sits inside `$(...)` or `|| exit 0` and would read as "no
# demand", so each is checked before any is used. scripts/ship-receipt.sh
# carries the same list; tests/push-gate.sh keeps them equal to the library.
SOP_GATE_FUNCTIONS='sop_have_jq sop_read_input sop_field sop_sha256 sop_repo_root sop_is_gated_repo
sop_instruction_file sop_claude_prose sop_type_from_file sop_declared_project_type sop_code_signals
sop_project_type sop_is_code_repo sop_default_branch sop_range_base sop_cmd_matches_push
sop_is_push_command sop_strip_heredocs sop_instruction_pattern sop_instructions_changed
sop_code_lines sop_effective_config sop_policy_valid sop_policy_digest sop_changed_files_json
sop_agents_in_scope sop_receipt_valid sop_shipsop_covered sop_shipsop_gate sop_bypasses_since_receipt'

# looks_like_push: a loose match, used only when the input cannot be parsed or the
# library cannot run. It over-refuses rather than miss a push.
# Escapes become spaces and quotes and backslashes go first, so quoting tricks
# (git p'u'sh, g"i"t push, git pu\sh) still match; any \u00 escape counts as a
# push, since its letters cannot be read without decoding.
looks_like_push() {
    # Bash only: this runs when tools may be missing, and a failed tool must not
    # read as "not a push".
    local flat=$1 re_push='git[^[:alnum:]_-].*push|pr[^[:alnum:]_-]+(create|new)'
    flat=${flat//\\n/ }; flat=${flat//\\t/ }
    flat=${flat//\'/}; flat=${flat//\"/}; flat=${flat//\\/}
    [[ $flat =~ $re_push ]] && return 0
    # Any \u00 escape: its letters cannot be read without decoding, and the tool
    # name itself may be the escaped part.
    [[ $1 == *u00* ]]
}

# A missing or incomplete library refuses anything that looks like a push and lets
# other commands through, so the setup that repairs it can still run.
LIB="$(dirname "${BASH_SOURCE[0]}")/sop-lib.sh"
LIB_PROBLEM=''
if [ ! -f "$LIB" ]; then
    LIB_PROBLEM="the push gate library is missing at $LIB"
else
    # shellcheck source=sop-lib.sh
    . "$LIB" 2>/dev/null || LIB_PROBLEM="the push gate library at $LIB failed to load"
    missing=''
    for fn in $SOP_GATE_FUNCTIONS; do declare -F "$fn" >/dev/null || missing="$missing $fn"; done
    [ -n "$LIB_PROBLEM" ] || [ -z "$missing" ] || LIB_PROBLEM="the push gate library at $LIB lacks:$missing"
fi
if [ -n "$LIB_PROBLEM" ]; then
    INPUT=$(cat 2>/dev/null || true)
    looks_like_push "$INPUT" && refuse "$LIB_PROBLEM. Re-run ship-sop setup.sh."
    exit 0
fi

if ! sop_have_jq; then
    INPUT=$(cat 2>/dev/null || true)
    looks_like_push "$INPUT" && refuse "jq is not installed, so the push gate cannot check this command. Install jq and retry."
    exit 0
fi
sop_read_input
if ! printf '%s' "$SOP_INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
    looks_like_push "$SOP_INPUT" && refuse "the hook input is not a JSON object, so the push gate cannot check this command."
    exit 0
fi

[ "$(sop_field '.tool_name')" = "Bash" ] || exit 0
CMD=$(sop_field '.tool_input.command')
[ -n "$CMD" ] || exit 0

# Match a push or PR-create that would actually execute: as a simple command
# (start, after a separator, after a leading VAR=val assignment), inside the
# quoted body of a `bash -c` / `sh -c` / `eval` wrapper, but not inside prose
# quoted as an argument. Rule lives in sop-lib.sh so the fixture suite and
# any future consumer test the same implementation.
sop_is_push_command "$CMD" || exit 0

# From here the command is a push: anything that cannot be determined refuses.
CWD=$(printf '%s' "$SOP_INPUT" | jq -r 'if (.cwd | type) == "string" then .cwd else empty end' 2>/dev/null) || CWD=''
[ -n "$CWD" ] && [ -d "$CWD" ] || refuse "the hook input has no usable cwd, so the push gate cannot tell which repository this push is from."
ROOT=$(sop_repo_root "$CWD")
sop_is_gated_repo "$ROOT" || exit 0

HEAD=$(git -C "$ROOT" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) \
    || refuse "cannot read HEAD in $ROOT, so the push gate cannot check coverage. Commit first, then push again."

# sop_bypass_applies <command>: true when every push in the command carries the
# SOP_SKIP_GATE=1 assignment on its own segment, outside quotes. A message or an
# echo that mentions it is not a bypass, and neither is a bypass on another
# segment (`SOP_SKIP_GATE=1 git log --grep push; git push`).
sop_bypass_applies() {
    local seg found=0
    while IFS= read -r seg; do
        seg=$(printf '%s' "$seg" | sed -E 's/^[[:space:](]+//')
        [ -n "$seg" ] || continue
        sop_is_push_command "$seg" || continue
        printf '%s\n' "$seg" | grep -Eq '^SOP_SKIP_GATE=1[[:space:]]+([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(git|gh)[[:space:]]' || return 1
        found=1
    done < <(printf '%s\n' "$1" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" | awk '{ gsub(/&&|\|\||[;&|`]/, "\n"); print }')
    [ "$found" = 1 ]
}

if sop_bypass_applies "$CMD"; then
    if ! { mkdir -p "$ROOT/.ship" && printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$HEAD" "$CMD" >> "$ROOT/.ship/bypass.log"; } 2>/dev/null; then
        printf '[ship-sop] warning: gate bypassed, but %s/.ship/bypass.log could not be written, so this bypass is not recorded.\n' "$ROOT" >&2
    fi
    exit 0
fi

GATE=$(sop_shipsop_gate "$ROOT") || refuse "the gate check failed in $ROOT (exit $?), so coverage of HEAD is unknown."
[ -n "$GATE" ] || exit 0

{
    printf '[ship-sop] push refused - %s\n' "$GATE"
    printf 'Write that report, then push again.\n'
} >&2

exit 2
