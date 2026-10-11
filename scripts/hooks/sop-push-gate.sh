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
# Bypass: prefix the push itself with SOP_SKIP_GATE=1. Every bypass is appended
# to .ship/bypass.log with the HEAD it skipped, so it is greppable later.
#
# Fails closed: Claude Code treats any exit other than 2 as "allow", so an
# internal error here once let pushes through silently. Any exit other than 0 or 2
# becomes a refusal that names the error.

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
. "$(dirname "${BASH_SOURCE[0]}")/sop-lib.sh"

if ! sop_have_jq; then
    # Without jq the input cannot be parsed; refuse only what looks like a push.
    # Raw JSON: escapes (\" \t) sit between the words, so match loosely and over-refuse.
    if grep -Eq 'git[^[:alnum:]_-].*push|pr[^[:alnum:]_-]+(create|new)'; then
        printf '[ship-sop] push refused: jq is not installed, so the push gate cannot check this command. Install jq and retry.\n' >&2
        exit 2
    fi
    exit 0
fi
sop_read_input

[ "$(sop_field '.tool_name')" = "Bash" ] || exit 0
CMD=$(sop_field '.tool_input.command')
[ -n "$CMD" ] || exit 0

# Match a push or PR-create that would actually execute: as a simple command
# (start, after a separator, after a leading VAR=val assignment), inside the
# quoted body of a `bash -c` / `sh -c` / `eval` wrapper, but not inside prose
# quoted as an argument. Rule lives in sop-lib.sh so the fixture suite and
# any future consumer test the same implementation.
sop_is_push_command "$CMD" || exit 0

CWD=$(sop_field '.cwd')
[ -n "$CWD" ] || CWD="$PWD"
ROOT=$(sop_repo_root "$CWD")
sop_is_gated_repo "$ROOT" || exit 0

HEAD=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null) || exit 0

# The bypass counts only as an assignment on the push itself, outside quotes: a commit
# message or an echo that mentions it is not a bypass (review finding).
if printf '%s\n' "$CMD" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" \
    | grep -Eq '(^|[;&|(][[:space:]]*)SOP_SKIP_GATE=1[[:space:]]+([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(git[^;&|]*[[:space:]]push|gh[^;&|]*[[:space:]]pr[[:space:]]+(create|new))'; then
    mkdir -p "$ROOT/.ship" 2>/dev/null
    printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$HEAD" "$CMD" >> "$ROOT/.ship/bypass.log" 2>/dev/null
    exit 0
fi

GATE=$(sop_shipsop_gate "$ROOT")
[ -n "$GATE" ] || exit 0

{
    printf '[ship-sop] push refused - %s\n' "$GATE"
    printf 'Write that report, then push again. To bypass once (recorded in .ship/bypass.log), put SOP_SKIP_GATE=1 directly before the push itself, for example: SOP_SKIP_GATE=1 git push\n'
} >&2

exit 2
