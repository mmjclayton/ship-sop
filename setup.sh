#!/usr/bin/env bash
#
# ship-sop Setup Script
#
# Installs ship-sop into a target project:
#   - Three reference agents into ~/.claude/agents/
#   - Five slash commands into ~/.claude/commands/
#   - ship-sop.config.json at the project root (with defaults)
#
# Automatic review runs from agent-sop's user-scope hooks. Setup retires the
# project-scope auto-ship-hook.sh and its settings entry left by older installs.
#
# Or removes the same install footprint when --uninstall is passed.
#
# Usage:
#   ./setup.sh /path/to/your/project [--no-hook] [--force]
#   ./setup.sh /path/to/your/project --uninstall [--force] [--keep-config] [--keep-artifacts]
#
# Install options:
#   --no-hook         Skip the agent-sop hook check (manual /ship and /release only)
#   --force           Overwrite existing files (install) / remove locally-modified files (uninstall)
#
# Uninstall options:
#   --uninstall       Reverse the install — remove agents, commands, config, gitignore entry and any legacy hook script or settings entry
#   --keep-config     Keep ship-sop.config.json (project-scope; useful to preserve per-project tuning across re-installs)
#   --keep-artifacts  Keep .ship/ runtime artifacts directory (cooldown stamps, pending directives)
#
# Existing files are skipped (not overwritten) unless --force is passed.
# docs/reviews/ is never auto-removed — it's audit trail.

set -euo pipefail

# pwd -P, not pwd. A logical path keeps the symlink in it, so invoking a
# symlinked clone (~/ship-sop -> ~/Projects/ship-sop) made the self-install
# check below compare two different strings for the same directory, and
# --uninstall then deleted ship-sop's own source (P15).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Runtime selection is stripped before the legacy option parser.
RUNTIME=claude
RUNTIME_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --runtime) [ $# -ge 2 ] || { echo '--runtime needs a value' >&2; exit 2; }; RUNTIME="$2"; shift ;;
        --runtime=*) RUNTIME="${1#*=}" ;;
        *) RUNTIME_ARGS+=("$1") ;;
    esac
    shift
done
case "$RUNTIME" in claude|codex|both) ;; *) echo 'runtime must be claude, codex or both' >&2; exit 2 ;; esac
set -- ${RUNTIME_ARGS[@]+"${RUNTIME_ARGS[@]}"}


if [ "$RUNTIME" = codex ]; then
    exec bash "$SCRIPT_DIR/scripts/setup-codex.sh" "$@"
fi
if [ "$RUNTIME" = both ]; then
    bash "$SCRIPT_DIR/scripts/setup-codex.sh" "$@"
fi

# ── Legacy project hook (retired by P25) ──────────────────────────────────────
#
# Installs before P25 copied scripts/auto-ship-hook.sh into the project and wired
# it as a Stop hook, in the nested shape or the pre-P14 flat shape. Install and
# uninstall both retire them, so both read these constants.

LEGACY_HOOK_PROBE='[(.hooks // {}) | .. | objects | select(.command? == "scripts/auto-ship-hook.sh")] | length > 0'

# Git blob hashes of every shipped auto-ship-hook.sh. A project copy matching one
# is unmodified and safe to delete; anything else is a local edit and is kept.
LEGACY_HOOK_BLOBS='104935d37c983a0511670ce02cb49e88f94ed108
3f8fa9b72046c17e146efc7594a67fd21dad1d3e
40a315fc1b65a7fb1a60dc005cc1cb74721c941c
62fee50bf93e0bb78d30cc1bed6c627962208553
c4c19edfe4a776a853d5ef132a74de760a93d247
ea003ece385291a1fd54dd8c2bb7053192f59a83
fc62bb678d306df823f3af76e8c48c07eb3a0694'

# ── Defaults ──────────────────────────────────────────────────────────────────

NO_HOOK=false
FORCE=false
UNINSTALL=false
KEEP_CONFIG=false
KEEP_ARTIFACTS=false
TARGET=""

# ── Parse arguments ───────────────────────────────────────────────────────────

usage() {
    echo "Usage:"
    echo "  $(basename "$0") /path/to/project [--no-hook] [--force]"
    echo "  $(basename "$0") /path/to/project --uninstall [--force] [--keep-config] [--keep-artifacts]"
    echo ""
    echo "Install options:"
    echo "  --runtime claude|codex|both  (default: claude)"
    echo "  --no-hook         Skip the agent-sop hook check (manual /ship only)"
    echo "  --force           Overwrite existing files (install) / remove locally-modified files (uninstall)"
    echo ""
    echo "Uninstall options:"
    echo "  --uninstall       Reverse the install"
    echo "  --keep-config     Preserve ship-sop.config.json"
    echo "  --keep-artifacts  Preserve .ship/ runtime artifacts directory"
    echo ""
    echo "Run this from the ship-sop repo directory."
    exit 1
}

for arg in "$@"; do
    case "$arg" in
        --no-hook)        NO_HOOK=true ;;
        --force)          FORCE=true ;;
        --uninstall)      UNINSTALL=true ;;
        --keep-config)    KEEP_CONFIG=true ;;
        --keep-artifacts) KEEP_ARTIFACTS=true ;;
        --help|-h)        usage ;;
        -*)
            echo "Unknown option: $arg"
            usage
            ;;
        *)
            if [ -z "$TARGET" ]; then
                TARGET="$arg"
            else
                echo "Unexpected argument: $arg"
                usage
            fi
            ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo "Error: no target directory specified."
    echo ""
    usage
fi

TARGET="$(cd "$TARGET" 2>/dev/null && pwd -P)" || {
    echo "Error: directory does not exist: $TARGET"
    exit 1
}

# Detect self-install (running setup on the source repo itself).
# Use case: dogfooding ship-sop on its own repo. Project-side files like
# docs/templates/ship-sop.schema.json already exist as part of the source —
# we skip those copies to avoid noise.
SELF_INSTALL=false
if [ "$SCRIPT_DIR" = "$TARGET" ]; then
    SELF_INSTALL=true
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

copy_if_missing() {
    local src="$1"
    local dest="$2"

    if [ -f "$dest" ] && [ "$FORCE" = false ]; then
        echo "  skip   $(basename "$dest") (already exists, use --force)"
        return 1
    fi

    mkdir -p "$(dirname "$dest")" || return 2
    cp "$src" "$dest" || return 2
    echo "  create $(basename "$dest")"
    return 0
}

# ── Hash helpers (uninstall integrity check) ──────────────────────────────────

file_hash() {
    if [ ! -f "$1" ]; then
        echo ""
        return
    fi
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        echo ""
    fi
}

# Remove $dest only if its content matches $src (i.e., unmodified since install).
# When $FORCE is true, removes regardless. When the file is missing, prints a
# "skip (not installed)" notice. When the file is locally modified, prints a
# "skip (locally modified, use --force)" notice and leaves it untouched.
remove_if_unmodified() {
    local src="$1"
    local dest="$2"
    local label="${3:-$(basename "$dest")}"

    if [ ! -f "$dest" ]; then
        echo "  skip   $label (not installed)"
        return 0
    fi

    # Never delete the file we install *from*. -ef compares device+inode, so it
    # holds even when the two paths differ textually (symlinked clone, bind
    # mount, ../ in the argument). Checked before --force, because --force is
    # about overriding local modifications, not about deleting the source (P15).
    if [ "$src" -ef "$dest" ]; then
        echo "  skip   $label (source and target are the same file)"
        return 0
    fi

    if [ "$FORCE" = true ]; then
        rm -f "$dest"
        echo "  remove $label (--force)"
        return 0
    fi

    local src_hash dest_hash
    src_hash="$(file_hash "$src")"
    dest_hash="$(file_hash "$dest")"

    if [ -z "$src_hash" ] || [ -z "$dest_hash" ]; then
        echo "  skip   $label (cannot verify integrity, use --force to remove)"
        return 0
    fi

    if [ "$src_hash" = "$dest_hash" ]; then
        rm -f "$dest"
        echo "  remove $label"
    else
        echo "  skip   $label (locally modified, use --force to remove)"
    fi
}

# Set when a legacy file or entry could not be retired; setup then exits non-zero.
LEGACY_PENDING=false

# Remove a project copy of the legacy hook script when it matches a shipped version.
remove_legacy_hook_script() {
    local dest="$1/scripts/auto-ship-hook.sh" blob
    [ -f "$dest" ] || return 0
    if [ "$FORCE" = true ]; then
        rm -f "$dest"; echo "  remove scripts/auto-ship-hook.sh (--force)"; return 0
    fi
    if ! blob=$(git hash-object --no-filters "$dest" 2>&1); then
        echo "  warn   could not hash scripts/auto-ship-hook.sh ($blob); kept" >&2
        LEGACY_PENDING=true; return 0
    fi
    if printf '%s\n' "$LEGACY_HOOK_BLOBS" | grep -qx "$blob"; then
        rm -f "$dest"; echo "  remove scripts/auto-ship-hook.sh (retired: it never ran live; auto-mode runs from agent-sop)"
    else
        echo "  skip   scripts/auto-ship-hook.sh (locally modified, use --force to remove)"
    fi
}

# Remove the legacy hook entry in either shape, under any event, keeping other hooks.
# Returns 0 when no legacy entry remains, 1 when one is still registered.
retire_legacy_hook_entry() {
    local settings="$1/.claude/settings.json" tmp rc=0
    [ -f "$settings" ] || return 0
    if ! command -v jq >/dev/null 2>&1; then
        if grep -q 'scripts/auto-ship-hook.sh' "$settings"; then
            echo "  warn   jq not installed; remove the scripts/auto-ship-hook.sh hook entry from $settings by hand" >&2
            LEGACY_PENDING=true; return 1
        fi
        return 0
    fi
    jq -e "$LEGACY_HOOK_PROBE" "$settings" >/dev/null 2>&1 || rc=$?
    [ "$rc" = 1 ] && return 0
    if [ "$rc" != 0 ]; then
        echo "  warn   could not read $settings as JSON; check it for a scripts/auto-ship-hook.sh entry" >&2
        LEGACY_PENDING=true; return 1
    fi
    if ! tmp=$(mktemp "$settings.XXXXXX"); then
        echo "  warn   cannot create a temporary file beside $settings" >&2
        LEGACY_PENDING=true; return 1
    fi
    # Drop flat entries, strip our command out of nested entries, then drop a
    # nested entry only when OUR removal emptied it. An entry that already had
    # "hooks": [] is inert but not ours to delete (P15). Other hooks stay (P14).
    # cp -p first so the new file keeps the original's mode. A symlinked
    # settings file (dotfile managers) is written through so the link survives;
    # a regular file is replaced by an atomic rename.
    if cp -p "$settings" "$tmp" \
       && jq '.hooks |= with_entries(if (.value | type) == "array" then .value |= [ .[]
          | select((.command? // "") != "scripts/auto-ship-hook.sh")
          | if (type == "object" and has("hooks") and ([.hooks[]?.command] | index("scripts/auto-ship-hook.sh")))
            then (.hooks |= map(select((.command? // "") != "scripts/auto-ship-hook.sh")))
               | select((.hooks | length) > 0)
            else . end ] else . end)' "$settings" > "$tmp" \
       && ! jq -e "$LEGACY_HOOK_PROBE" "$tmp" >/dev/null 2>&1 \
       && if [ -L "$settings" ]; then cat "$tmp" > "$settings" && rm -f "$tmp"; else mv "$tmp" "$settings"; fi; then
        echo "  update .claude/settings.json (removed legacy auto-ship-hook.sh entry)"
        return 0
    fi
    rm -f "$tmp"
    echo "  warn   could not edit $settings; remove the scripts/auto-ship-hook.sh hook entry by hand" >&2
    LEGACY_PENDING=true; return 1
}

# Entry first: deleting the script while an entry still points at it would make
# every session's Stop hook fail.
retire_legacy_hook() {
    if retire_legacy_hook_entry "$1"; then
        remove_legacy_hook_script "$1"
    elif [ -f "$1/scripts/auto-ship-hook.sh" ]; then
        echo "  keep   scripts/auto-ship-hook.sh (its settings entry is still registered)"
    fi
}

# ── Uninstall mode ────────────────────────────────────────────────────────────

uninstall_mode() {
    local target="$1"

    echo ""
    echo "ship-sop uninstall"
    echo "==================="
    echo ""
    echo "Target: $target"
    if [ "$FORCE" = true ]; then
        echo "Mode: --force (remove all installed files, including locally-modified ones)"
    else
        echo "Mode: safe (locally-modified files are kept; pass --force to remove anyway)"
    fi
    echo ""

    local user_claude_dir="${AGENT_SOP_USER_HOME:-$HOME}/.claude"

    remove_if_unmodified "$SCRIPT_DIR/scripts/ship-receipt.sh" "$user_claude_dir/scripts/ship-sop/ship-receipt.sh"

    # User-scope agents
    echo "Removing agents from $user_claude_dir/agents/"
    for src in "$SCRIPT_DIR"/.claude/agents/*.md; do
        [ -f "$src" ] || continue
        remove_if_unmodified "$src" "$user_claude_dir/agents/$(basename "$src")"
    done

    # User-scope commands
    echo ""
    echo "Removing commands from $user_claude_dir/commands/"
    for src in "$SCRIPT_DIR"/.claude/commands/*.md; do
        [ -f "$src" ] || continue
        remove_if_unmodified "$src" "$user_claude_dir/commands/$(basename "$src")"
    done

    # Project-scope files
    if [ "$SELF_INSTALL" = true ]; then
        echo ""
        echo "Self-install detected — skipping project-side file removal (those files are sources)"
    else
        echo ""
        echo "Removing project files from $target"

        remove_if_unmodified \
            "$SCRIPT_DIR/docs/templates/ship-sop.schema.json" \
            "$target/docs/templates/ship-sop.schema.json"

        if [ "$KEEP_CONFIG" = true ]; then
            echo "  keep   ship-sop.config.json (--keep-config)"
        else
            remove_if_unmodified \
                "$SCRIPT_DIR/docs/templates/ship-sop.config.json" \
                "$target/ship-sop.config.json"
        fi
    fi

    # Legacy Stop hook entry and script (entry first)
    echo ""
    if [ "$SELF_INSTALL" = true ]; then
        retire_legacy_hook_entry "$target" || true
    else
        retire_legacy_hook "$target"
    fi

    # .gitignore block
    if [ "$KEEP_ARTIFACTS" = false ] && [ -f "$target/.gitignore" ] && grep -q "^# ship-sop runtime artifacts$" "$target/.gitignore"; then
        local tmp
        tmp="$(mktemp)"
        # The block is two lines: the marker and ".ship/". `next` already
        # consumes the marker, so only ONE further line may be skipped.
        # skip = 2 ate the first user line after the block (P15).
        awk '
            /^# ship-sop runtime artifacts$/ { skip = 1; next }
            skip > 0                         { skip--; next }
            { print }
        ' "$target/.gitignore" > "$tmp" && mv "$tmp" "$target/.gitignore"
        echo "  update .gitignore (removed .ship/ block)"
    elif [ -f "$target/.gitignore" ]; then
        echo "  skip   .gitignore (no ship-sop entries)"
    fi

    # .ship/ runtime artifacts
    if [ "$KEEP_ARTIFACTS" = true ]; then
        echo "  keep   .ship/ (--keep-artifacts)"
    elif [ "$SELF_INSTALL" = false ] && [ -d "$target/.ship" ]; then
        rm -rf "$target/.ship"
        echo "  remove .ship/ runtime artifacts"
    fi

    # Clean up install directories if they're now empty. rmdir refuses to
    # remove non-empty dirs, so this is safe — pre-existing user content stays.
    if [ "$SELF_INSTALL" = false ]; then
        rmdir "$target/scripts" 2>/dev/null && echo "  remove scripts/ (was empty)" || true
        rmdir "$target/docs/templates" 2>/dev/null && echo "  remove docs/templates/ (was empty)" || true
    fi

    # Summary
    echo ""
    if [ "$LEGACY_PENDING" = true ]; then
        echo "Uninstall incomplete: a legacy hook file or entry remains (see warnings above)."
    else
        echo "Done. ship-sop is uninstalled."
    fi
    echo ""
    echo "Files NOT touched (manage these manually):"
    echo "  - docs/reviews/         (audit trail; remove only if you're certain)"
    echo "  - docs/agent-memory/    (any decisions/gotchas captured by agents)"
    echo "  - .gitignore            (only the ship-sop block was removed; other entries kept)"
    if [ "$KEEP_CONFIG" = true ]; then
        echo "  - ship-sop.config.json  (kept via --keep-config)"
    fi
    if [ "$KEEP_ARTIFACTS" = true ]; then
        echo "  - .ship/                (kept via --keep-artifacts)"
    fi
    echo ""
    echo "If you reinstall later, your tuning in ship-sop.config.json is preserved when --keep-config was used."
    echo ""
}

# ── Pre-flight ────────────────────────────────────────────────────────────────

# Dispatch to uninstall mode before the install-flavoured pre-flight runs.
# Uninstall has its own header and a much smaller dependency surface (only jq).
if [ "$UNINSTALL" = true ]; then
    if ! command -v jq >/dev/null 2>&1; then
        echo "Warning: jq not installed. The .claude/settings.json hook entry won't be removed automatically."
        echo "         Install via: brew install jq  (macOS) | apt install jq  (Debian/Ubuntu)"
        echo ""
    fi
    # Removing Claude integration must not remove shared Codex configuration.
    if [ "$RUNTIME" = claude ] && [ -f "${CODEX_HOME:-${AGENT_SOP_USER_HOME:-$HOME}/.codex}/ship-sop.install.json" ]; then
        KEEP_CONFIG=true; KEEP_ARTIFACTS=true
    fi
    uninstall_mode "$TARGET"
    if [ "$LEGACY_PENDING" = true ]; then
        echo "Uninstall finished, but a legacy hook file or entry could not be removed; see the warnings above." >&2
        exit 1
    fi
    exit 0
fi

echo ""
echo "ship-sop setup"
echo "==================="
echo ""
echo "Target: $TARGET"
echo ""

# Check Claude Code version
if command -v claude >/dev/null 2>&1; then
    CLAUDE_VERSION="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
    if [ -n "$CLAUDE_VERSION" ]; then
        REQUIRED="2.1.101"
        LOWEST="$(printf '%s\n%s\n' "$CLAUDE_VERSION" "$REQUIRED" | sort -V | head -n1)"
        if [ "$LOWEST" != "$REQUIRED" ]; then
            echo "Warning: Claude Code $CLAUDE_VERSION detected. ship-sop recommends $REQUIRED+"
            echo ""
        fi
    fi
fi

# Check jq (required for config edits and the hook check)
if ! command -v jq >/dev/null 2>&1; then
    echo "Warning: jq not installed. Auto-mode hook requires jq for config parsing."
    echo "         Install via: brew install jq  (macOS) | apt install jq  (Debian/Ubuntu)"
    echo ""
fi

# Check gh CLI (required for /release)
if ! command -v gh >/dev/null 2>&1; then
    echo "Warning: gh CLI not installed. /release uses gh to publish GitHub Releases."
    echo "         Install via: brew install gh  (macOS) | https://cli.github.com/"
    echo ""
fi

# ── Install reference agents (user-scope) ─────────────────────────────────────

USER_CLAUDE_DIR="${AGENT_SOP_USER_HOME:-$HOME}/.claude"
mkdir -p "$USER_CLAUDE_DIR/agents" "$USER_CLAUDE_DIR/commands"

mkdir -p "$USER_CLAUDE_DIR/scripts/ship-sop"
if copy_if_missing "$SCRIPT_DIR/scripts/ship-receipt.sh" "$USER_CLAUDE_DIR/scripts/ship-sop/ship-receipt.sh"; then :
else result=$?; [ "$result" = 1 ] || { echo 'Receipt tool installation failed' >&2; exit "$result"; }; fi
echo "Installing agents to ~/.claude/agents/"
for src in "$SCRIPT_DIR"/.claude/agents/*.md; do
    [ -f "$src" ] || continue
    dest="$USER_CLAUDE_DIR/agents/$(basename "$src")"
    if [ -f "$dest" ] && [ "$FORCE" = false ]; then
        echo "  skip   $(basename "$src") (already exists, use --force)"
    else
        cp "$src" "$dest"
        echo "  create $(basename "$src")"
    fi
done

# ── Install slash commands (user-scope) ───────────────────────────────────────

echo ""
echo "Installing commands to ~/.claude/commands/"
for src in "$SCRIPT_DIR"/.claude/commands/*.md; do
    [ -f "$src" ] || continue
    dest="$USER_CLAUDE_DIR/commands/$(basename "$src")"
    if [ -f "$dest" ] && [ "$FORCE" = false ]; then
        echo "  skip   $(basename "$src") (already exists, use --force)"
    else
        cp "$src" "$dest"
        echo "  create $(basename "$src")"
    fi
done

# ── Install hook script and config (project-scope) ────────────────────────────

# Default config, only created if missing. Claude ships no silent-failure-hunter
# profile, and an enabled reviewer that cannot launch makes every run INCOMPLETE,
# so a new Claude-only config disables it until the user supplies one. The file is
# built beside the target and renamed once, so a failure leaves no config and a
# rerun starts clean.
create_default_config() {
    local config="$TARGET/ship-sop.config.json" tmp
    local filter='.'
    [ -f "$config" ] && return 0
    if [ "$RUNTIME" = claude ] \
        && [ ! -f "$USER_CLAUDE_DIR/agents/silent-failure-hunter.md" ] \
        && [ ! -f "$TARGET/.claude/agents/silent-failure-hunter.md" ]; then
        filter='.agents["silent-failure-hunter"].enabled = false'
    fi
    if [ "$filter" != '.' ] && ! command -v jq >/dev/null 2>&1; then
        echo "Could not write $config: jq is required to disable silent-failure-hunter. Install jq and re-run setup." >&2
        return 1
    fi
    tmp=$(mktemp "$config.XXXXXX") || { echo "Cannot create a temporary file in $TARGET" >&2; return 1; }
    if [ "$filter" = '.' ]; then
        cp "$SCRIPT_DIR/docs/templates/ship-sop.config.json" "$tmp" || { rm -f "$tmp"; return 1; }
    elif ! jq "$filter" "$SCRIPT_DIR/docs/templates/ship-sop.config.json" > "$tmp"; then
        rm -f "$tmp"
        echo "Could not write $config: jq failed to edit the template." >&2
        return 1
    fi
    if ! chmod 644 "$tmp"; then rm -f "$tmp"; echo "Could not set permissions on $config" >&2; return 1; fi
    if ! mv "$tmp" "$config"; then rm -f "$tmp"; echo "Could not move the new config into $config" >&2; return 1; fi
    if [ "$filter" != '.' ]; then
        echo "  note   silent-failure-hunter disabled: no profile in ~/.claude/agents/ or .claude/agents/"
    fi
}

echo ""
if [ "$SELF_INSTALL" = true ]; then
    echo "Self-install — project-side files already present in source repo"
    mkdir -p "$TARGET/docs/reviews" "$TARGET/.ship"
    # Skip copying docs/templates/ship-sop.schema.json since it lives in the
    # source repo. Still create the user-facing config
    # at the project root (different from the template under docs/templates/).
    create_default_config
else
    echo "Installing config in $TARGET"
    mkdir -p "$TARGET/docs/reviews" "$TARGET/.ship"

    create_default_config
    copy_if_missing "$SCRIPT_DIR/docs/templates/ship-sop.schema.json" "$TARGET/docs/templates/ship-sop.schema.json" || true
fi

# Gitignore additions for .ship/
if [ -f "$TARGET/.gitignore" ]; then
    if ! grep -q "^\.ship/" "$TARGET/.gitignore" 2>/dev/null; then
        echo "" >> "$TARGET/.gitignore"
        echo "# ship-sop runtime artifacts" >> "$TARGET/.gitignore"
        echo ".ship/" >> "$TARGET/.gitignore"
        echo "  update .gitignore (added .ship/)"
    fi
else
    cat > "$TARGET/.gitignore" <<EOF
# ship-sop runtime artifacts
.ship/
EOF
    echo "  create .gitignore"
fi

# ── Automatic review hooks (agent-sop) ────────────────────────────────────────

UNIFIED_SETTINGS="${AGENT_SOP_USER_HOME:-$HOME}/.claude/settings.json"
UNIFIED_STOP="${AGENT_SOP_USER_HOME:-$HOME}/.claude/scripts/hooks/agent-sop/sop-stop-drift.sh"
# absent: no agent-sop Stop hook; wired: registered and present; stale: registered
# but not at the standard path; unknown: jq missing or settings unreadable.
UNIFIED_STATE=absent
if [ -f "$UNIFIED_SETTINGS" ]; then
    if ! command -v jq >/dev/null 2>&1; then
        UNIFIED_STATE=unknown
    else
        rc=0
        jq -e '[.hooks.Stop[]?.hooks[]? | (.command? // "") | strings | select(contains("sop-stop-drift.sh"))] | length > 0' "$UNIFIED_SETTINGS" >/dev/null 2>&1 || rc=$?
        if [ "$rc" = 0 ]; then
            UNIFIED_STATE=wired
            if [ ! -f "$UNIFIED_STOP" ] || ! jq -e --arg command "bash \"$UNIFIED_STOP\"" '[.hooks.Stop[]?.hooks[]? | (.command? // "") | select(. == $command)] | length > 0' "$UNIFIED_SETTINGS" >/dev/null; then
                UNIFIED_STATE=stale
            fi
        elif [ "$rc" != 1 ]; then
            UNIFIED_STATE=unknown
        fi
    fi
fi
if [ "$NO_HOOK" = false ] && [ "$UNIFIED_STATE" = stale ]; then
    echo 'Auto-mode registration is stale or nonstandard; repair agent-sop hooks before retiring the project handler.' >&2
    exit 1
fi

echo ""
if [ "$SELF_INSTALL" = true ]; then
    retire_legacy_hook_entry "$TARGET" || true
else
    retire_legacy_hook "$TARGET"
fi

echo ""
if [ "$NO_HOOK" = true ]; then
    echo "Skipping the agent-sop hook check (--no-hook). Use /ship and /release manually."
elif [ "$UNIFIED_STATE" = wired ]; then
    echo "Auto-mode uses agent-sop's user-scope hooks: registered."
elif [ "$UNIFIED_STATE" = unknown ]; then
    echo "Could not check agent-sop's hooks in $UNIFIED_SETTINGS (jq missing or the file is not valid JSON)." >&2
else
    echo "Auto-mode needs agent-sop's user-scope hooks, which are not registered."
    echo "Install agent-sop (its setup.sh), then /ship-on. /ship works manually meanwhile."
fi
# Receipts need the agent-sop library; /ship cannot finish a review without it.
if ! bash "$SCRIPT_DIR/scripts/ship-receipt.sh" --check-lib --runtime claude; then
    echo "  warn   /ship cannot write receipts until agent-sop is installed or updated" >&2
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Done. Next steps:"
echo ""
echo "  1. Commit the install artifacts:"
echo "     - ship-sop.config.json (project's per-agent toggles + throttle)"
echo "     - .claude/settings.json (if setup removed a legacy hook entry)"
echo "     - .gitignore (additions for .ship/)"
echo ""
echo "     Suggested:"
echo "       git add ship-sop.config.json .claude/settings.json .gitignore"
echo "       git commit -m 'chore: install ship-sop'"
echo ""
echo "  2. Open ship-sop.config.json and confirm the defaults"
echo "     (per-agent toggles, throttle, release branch). Edit before committing"
echo "     if the defaults aren't what you want."
echo ""
echo "  3. Verify the install:"
echo "     - ~/.claude/agents/{compliance-reviewer,diagram-builder,release-notes-writer}.md"
echo "     - ~/.claude/commands/{ship,release,ship-on,ship-off,audit}.md"
echo ""
echo "  4. Try a dry run:"
echo "     - Make a small commit, then in a Claude Code session in this project,"
echo "       run /ship to see the manual pipeline."
echo "     - With agent-sop hooks and auto-mode on, ending a session with an"
echo "       unreviewed code diff requests the configured review."
echo ""
echo "  5. Toggle modes any time:"
echo "     /ship-on     enable auto-mode"
echo "     /ship-off    disable auto-mode (manual /ship still works)"
echo ""
echo "  6. To remove ship-sop later:"
echo "     ./setup.sh $TARGET --uninstall"
echo "     (add --keep-config to preserve your tuning, --force to remove locally-modified files)"
echo ""

if [ "$LEGACY_PENDING" = true ]; then
    echo "" >&2
    echo "Setup finished, but a legacy hook file or entry could not be retired; see the warnings above." >&2
    exit 1
fi
