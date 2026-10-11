#!/usr/bin/env bash
#
# Install ship-sop's push gate user-scope and register it as a PreToolUse hook.
#
# Why user-scope: project-scope hooks in <repo>/.claude/settings.json load only
# from the directory Claude Code was launched in, so a session launched from ~
# that cd's into a project never sees them. A user-scope hook fires in every
# session and resolves the repository from the hook's own `cwd` input.
#
# Usage:
#   bash scripts/install-hooks.sh [--runtime claude|codex] [--settings <path>] [--dest <dir>]
#                                 [--no-register] [--uninstall] [--dry-run]
#
# Defaults (Claude): --settings ~/.claude/settings.json, --dest ~/.claude/scripts/hooks/ship-sop
# Defaults (Codex):  --settings $CODEX_HOME/hooks.json,  --dest $CODEX_HOME/scripts/hooks/ship-sop
#
# --no-register installs the scripts (receipt validation needs sop-lib.sh) but
# leaves the hook settings, and any older hooks registered there, untouched.
#
# Idempotent. Other hooks are preserved, and the settings file is backed up to
# <settings>.bak-<timestamp> before any write. An installed script edited
# locally is kept and named, never overwritten or removed.
#
# Migration: an older install placed these scripts under .../scripts/hooks/agent-sop/.
# Install removes every registration that points there, then deletes the old
# copies whose content matches a shipped version (scripts/legacy-agent-sop-hooks.txt).
# Edited copies are kept and named.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/hooks"
LEGACY_BLOBS="$SCRIPT_DIR/legacy-agent-sop-hooks.txt"
SETTINGS=""
DEST=""
RUNTIME=claude
UNINSTALL=false
DRY_RUN=false
REGISTER=true

while [ $# -gt 0 ]; do
    case "$1" in
        --runtime)  [ $# -ge 2 ] || { echo "install-hooks: --runtime needs a value" >&2; exit 1; }; RUNTIME="$2"; shift ;;
        --settings) [ $# -ge 2 ] || { echo "install-hooks: --settings needs a value" >&2; exit 1; }; SETTINGS="$2"; shift ;;
        --dest)     [ $# -ge 2 ] || { echo "install-hooks: --dest needs a value" >&2; exit 1; }; DEST="$2"; shift ;;
        --no-register) REGISTER=false ;;
        --uninstall) UNINSTALL=true ;;
        --dry-run)  DRY_RUN=true ;;
        -h|--help)
            awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

USER_ROOT="${AGENT_SOP_USER_HOME:-$HOME}"
case "$RUNTIME" in
    claude) RUNTIME_HOME="$USER_ROOT/.claude"; SETTINGS="${SETTINGS:-$RUNTIME_HOME/settings.json}" ;;
    codex)  RUNTIME_HOME="${CODEX_HOME:-$USER_ROOT/.codex}"; SETTINGS="${SETTINGS:-$RUNTIME_HOME/hooks.json}" ;;
    *) echo "install-hooks: runtime must be claude or codex" >&2; exit 1 ;;
esac
DEST="${DEST:-$RUNTIME_HOME/scripts/hooks/ship-sop}"
LEGACY_DEST="$RUNTIME_HOME/scripts/hooks/agent-sop"
MANIFEST="$DEST/.installed"

command -v jq >/dev/null 2>&1 || { echo "install-hooks: jq is required (brew install jq)" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "install-hooks: git is required" >&2; exit 1; }

FILES="sop-lib.sh sop-push-gate.sh sop-project-type.sh sop-codex-hook.sh"
for f in $FILES; do
    [ -f "$SRC/$f" ] || { echo "install-hooks: missing $SRC/$f" >&2; exit 1; }
done
[ -f "$LEGACY_BLOBS" ] || { echo "install-hooks: missing $LEGACY_BLOBS" >&2; exit 1; }

PUSH_CMD="bash \"$DEST/sop-push-gate.sh\""
[ "$RUNTIME" != codex ] || PUSH_CMD="bash \"$DEST/sop-codex-hook.sh\" PreToolUse"

blob() { git hash-object --no-filters "$1" 2>/dev/null; }
recorded() { [ -f "$MANIFEST" ] && awk -v f="$1" '$2 == f { print $1; exit }' "$MANIFEST"; }

# A dotfiles-managed settings file is often a symlink. `mv` over the link would
# replace it with a plain file, so resolve the chain and write to the real file.
resolve_settings_target() {
    local p="$SETTINGS" link i=0
    while [ -L "$p" ] && [ "$i" -lt 10 ]; do
        link=$(readlink "$p")
        case "$link" in
            /*) p="$link" ;;
            *)  p="$(cd "$(dirname "$p")" && pwd)/$link" ;;
        esac
        i=$((i + 1))
    done
    printf '%s' "$p"
}

backup_settings() {
    local target
    target=$(resolve_settings_target)
    [ -f "$target" ] || return 0
    cp "$target" "$target.bak-$(date +%Y%m%d-%H%M%S)" || { echo "install-hooks: could not back up $target" >&2; exit 1; }
}

write_settings() {
    local tmp target
    target=$(resolve_settings_target)
    tmp=$(mktemp) || { echo "install-hooks: could not create a temporary file" >&2; exit 1; }
    if printf '%s' "$1" > "$tmp" && jq empty "$tmp" 2>/dev/null; then
        mv "$tmp" "$target" || { rm -f "$tmp"; echo "install-hooks: could not write $target" >&2; exit 1; }
    else
        rm -f "$tmp"
        echo "install-hooks: refusing to write invalid JSON to $target" >&2
        exit 1
    fi
}

read_settings() {
    if [ -e "$SETTINGS" ] && [ ! -f "$SETTINGS" ]; then
        echo "install-hooks: $SETTINGS exists and is not a regular file" >&2; exit 1
    fi
    CURRENT='{}'
    [ ! -f "$SETTINGS" ] || CURRENT=$(cat "$SETTINGS") || { echo "install-hooks: could not read $SETTINGS" >&2; exit 1; }
    # An empty file reads as {}; jq prints nothing on empty input.
    case "$CURRENT" in *[![:space:]]*) ;; *) CURRENT='{}' ;; esac
}

# jq: drop every hook command starting with one of $prefixes, then any entry or
# event that removal emptied. Other hooks are kept.
JQ_DROP='def drop_prefixes($prefixes):
    .hooks = ((.hooks // {}) | with_entries(.value |= map(
          .hooks = ((.hooks // []) | map(select((.command // "") as $c | any($prefixes[]; . as $p | $c | startswith($p)) | not)))
        ) | .value |= map(select((.hooks | length) > 0)))
      | with_entries(select((.value | length) > 0)));'

# ── Uninstall ────────────────────────────────────────────────────────────────
if [ "$UNINSTALL" = true ]; then
    if [ -f "$SETTINGS" ]; then
        # Only entries this installer wrote: commands that run a script under $DEST.
        NEW=$(jq --arg d "bash \"$DEST/" "$JQ_DROP"' drop_prefixes([$d])' "$SETTINGS" 2>/dev/null) \
            || { echo "install-hooks: could not parse $SETTINGS" >&2; exit 1; }
        if [ "$DRY_RUN" = true ]; then
            printf '%s\n' "$NEW"
        elif [ "$NEW" != "$(jq . "$SETTINGS")" ]; then
            backup_settings
            write_settings "$NEW"
        fi
    fi
    [ "$DRY_RUN" = false ] || exit 0
    for f in $FILES; do
        [ -f "$DEST/$f" ] || continue
        if [ "$SRC/$f" -ef "$DEST/$f" ]; then continue; fi
        cur=$(blob "$DEST/$f")
        if [ "$cur" = "$(blob "$SRC/$f")" ] || [ "$cur" = "$(recorded "$f")" ]; then
            rm -f "$DEST/$f" || exit 1
        else
            echo "keep $DEST/$f (edited locally; delete it yourself)"
        fi
    done
    rm -f "$MANIFEST"
    rmdir "$DEST" 2>/dev/null || true
    echo "install-hooks: ship-sop push gate removed from $SETTINGS and $DEST"
    exit 0
fi

# ── Install scripts ───────────────────────────────────────────────────────────
if [ "$DRY_RUN" = false ]; then
    mkdir -p "$DEST" || exit 1
    NEXT_MANIFEST=$(mktemp) || exit 1
    for f in $FILES; do
        want=$(blob "$SRC/$f") || { rm -f "$NEXT_MANIFEST"; echo "install-hooks: cannot hash $SRC/$f" >&2; exit 1; }
        if [ "$SRC/$f" -ef "$DEST/$f" ]; then printf '%s %s\n' "$want" "$f" >> "$NEXT_MANIFEST"; continue; fi
        if [ -f "$DEST/$f" ]; then
            cur=$(blob "$DEST/$f")
            if [ "$cur" != "$want" ] && [ "$cur" != "$(recorded "$f")" ]; then
                echo "keep $DEST/$f (edited locally; compare it with $SRC/$f and reconcile by hand)"
                [ -z "$(recorded "$f")" ] || printf '%s %s\n' "$(recorded "$f")" "$f" >> "$NEXT_MANIFEST"
                continue
            fi
        fi
        cp "$SRC/$f" "$DEST/$f" && chmod +x "$DEST/$f" || { rm -f "$NEXT_MANIFEST"; exit 1; }
        printf '%s %s\n' "$want" "$f" >> "$NEXT_MANIFEST"
    done
    mv "$NEXT_MANIFEST" "$MANIFEST" || { rm -f "$NEXT_MANIFEST"; exit 1; }
fi

if [ "$REGISTER" = false ]; then
    echo "install-hooks: scripts in $DEST (push gate not registered: --no-register)"
    exit 0
fi

# ── Register the push gate ────────────────────────────────────────────────────
# A missing settings file is read as {}; only a real install creates it, so
# --dry-run writes nothing.
read_settings

# Registrations from an older install under .../hooks/agent-sop/ go, under any event.
# Codex hooks.json files once pointed at the Claude copies, so both are matched there.
LEGACY_PREFIXES=$(jq -nc --arg a "bash \"$LEGACY_DEST/sop-" --arg b "bash \"$USER_ROOT/.claude/scripts/hooks/agent-sop/sop-" \
    --arg runtime "$RUNTIME" 'if $runtime == "codex" then [$a, $b] else [$a] end')

NEW=$(jq --argjson prefixes "$LEGACY_PREFIXES" --arg dest "bash \"$DEST/" --arg push "$PUSH_CMD" "$JQ_DROP"'
    def ensure(ev; m; cmd; t):
        .hooks[ev] = ((.hooks[ev] // []) |
            if any(.[]?.hooks[]?; (.command // "") == cmd) then .
            else . + [{ matcher: m, hooks: [{ type: "command", command: cmd, timeout: t }] }]
            end);
    drop_prefixes($prefixes)
    # Retired hook registrations under our own $dest (any event) go too.
    | .hooks |= with_entries(.value |= map(
          .hooks = ((.hooks // []) | map(select(((.command // "") | startswith($dest)) and
                               ((.command // "") | test("(sop-session-context|sop-stop-drift|sop-memory-index|sop-worktree-claim)\\.sh|sop-codex-hook\\.sh\"? (SessionStart|UserPromptSubmit|Stop)$")) | not)))
        ) | .value |= map(select((.hooks | length) > 0)))
    | .hooks |= with_entries(select((.value | length) > 0))
    | ensure("PreToolUse"; "Bash"; $push; 10)
' <<< "$CURRENT" 2>/dev/null) || { echo "install-hooks: could not parse $SETTINGS" >&2; exit 1; }

if [ "$DRY_RUN" = true ]; then
    printf '%s\n' "$NEW"
    exit 0
fi

[ -n "$NEW" ] || { echo "install-hooks: no settings produced from $SETTINGS" >&2; exit 1; }
if [ "$NEW" != "$CURRENT" ] || [ ! -f "$SETTINGS" ] || [ ! -s "$SETTINGS" ]; then
    mkdir -p "$(dirname "$(resolve_settings_target)")" || { echo "install-hooks: could not create the directory for $SETTINGS" >&2; exit 1; }
    backup_settings
    write_settings "$NEW"
    echo "install-hooks: registered the push gate in $SETTINGS (backup written alongside)"
else
    echo "install-hooks: $SETTINGS already up to date"
fi

# Old copies go only after the settings no longer point at them, and only when
# unedited. A file that is its own source (a --dest inside a checkout) is never touched.
retire_legacy_copies() {
    local path name b
    [ -d "$LEGACY_DEST" ] || return 0
    for path in "$LEGACY_DEST"/*; do
        [ -f "$path" ] || continue
        name=$(basename "$path")
        if [ -e "$SRC/$name" ] && [ "$SRC/$name" -ef "$path" ]; then continue; fi
        grep -q "^[0-9a-f]\{40\} $name\$" "$LEGACY_BLOBS" || continue
        b=$(blob "$path") || { echo "keep $path (cannot hash it; delete it yourself)"; continue; }
        if grep -qx "$b $name" "$LEGACY_BLOBS"; then
            rm -f "$path" || exit 1
            echo "remove $path (replaced by $DEST)"
        else
            echo "keep $path (edited locally; no longer registered, delete it yourself)"
        fi
    done
    rmdir "$LEGACY_DEST" 2>/dev/null || true
}
retire_legacy_copies
echo "install-hooks: scripts in $DEST"
echo "  PreToolUse(Bash) -> sop-push-gate.sh (refuses push/PR when ship-sop auto-mode has no receipt for HEAD)"
exit 0
