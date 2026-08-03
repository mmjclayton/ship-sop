#!/usr/bin/env bash
#
# ship-sop Setup Script
#
# Installs ship-sop into a target project:
#   - Three reference agents into ~/.claude/agents/
#   - Five slash commands into ~/.claude/commands/
#   - scripts/auto-ship-hook.sh into the project
#   - ship-sop.config.json at the project root (with defaults)
#   - An entry in .claude/settings.json wiring the SessionStop hook (with consent)
#
# Or removes the same install footprint when --uninstall is passed.
#
# Usage:
#   ./setup.sh /path/to/your/project [--no-hook] [--force]
#   ./setup.sh /path/to/your/project --uninstall [--force] [--keep-config] [--keep-artifacts]
#
# Install options:
#   --no-hook         Skip the SessionStop hook wiring (manual /ship and /release only)
#   --force           Overwrite existing files (install) / remove locally-modified files (uninstall)
#
# Uninstall options:
#   --uninstall       Reverse the install — remove agents, commands, hook script, config, gitignore entry, settings.json hook
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

# ── Hook entry shape (P14) ────────────────────────────────────────────────────
#
# Claude Code discards a hook entry that does not nest its command. Install and
# uninstall must agree on the selector or one of them silently no-ops, so both
# read these three constants rather than inlining their own jq.

# Matches the nested shape the harness actually executes.
HOOK_NESTED_PROBE='[.hooks.Stop[]?.hooks[]?.command] | index("scripts/auto-ship-hook.sh")'

# Matches the pre-P14 flat shape, which parses but never runs. Retained so
# existing installs can be migrated and uninstalled rather than orphaned.
HOOK_LEGACY_PROBE='.hooks.Stop[]? | select((.command? // "") == "scripts/auto-ship-hook.sh")'

HOOK_ENTRY_EXAMPLE='{"hooks":{"Stop":[{"matcher":"*","hooks":[{"type":"command","command":"scripts/auto-ship-hook.sh"}]}]}}'

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
    echo "  --no-hook         Skip the SessionStop hook wiring (manual /ship only)"
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
# scripts/auto-ship-hook.sh and docs/templates/ship-sop.schema.json already
# exist as part of the source — we skip those copies to avoid noise.
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

    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    echo "  create $(basename "$dest")"
    return 0
}

prompt_yn() {
    local prompt="$1"
    local default="${2:-y}"
    local response
    if [ "$default" = "y" ]; then
        printf "%s [Y/n] " "$prompt"
    else
        printf "%s [y/N] " "$prompt"
    fi
    # 30s timeout protects non-interactive shells (CI runners, scripted installs).
    # Falls through to the supplied default rather than hanging.
    if ! read -t 30 -r response 2>/dev/null; then
        echo ""
        echo "  (no input within 30s — using default '$default')"
        response="$default"
    fi
    response="${response:-$default}"
    [[ "$response" =~ ^[Yy]$ ]]
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

    local user_claude_dir="$HOME/.claude"

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
            "$SCRIPT_DIR/scripts/auto-ship-hook.sh" \
            "$target/scripts/auto-ship-hook.sh"

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

    # SessionStop hook entry in .claude/settings.json
    echo ""
    local settings="$target/.claude/settings.json"
    if [ -f "$settings" ]; then
        if command -v jq >/dev/null 2>&1; then
            if jq -e "$HOOK_NESTED_PROBE" "$settings" >/dev/null 2>&1 \
               || jq -e "$HOOK_LEGACY_PROBE" "$settings" >/dev/null 2>&1; then
                local tmp
                tmp="$(mktemp)"
                # Drop legacy flat entries, strip our command out of nested
                # entries, then drop any nested entry left with no commands.
                # Other people's hooks in the same array are preserved (P14).
                jq '.hooks.Stop = [ .hooks.Stop[]?
                      | select((.command? // "") != "scripts/auto-ship-hook.sh")
                      | if has("hooks")
                        then .hooks = [ .hooks[] | select((.command? // "") != "scripts/auto-ship-hook.sh") ]
                        else . end
                      | select((.hooks? // null) == null or (.hooks | length) > 0) ]' \
                   "$settings" > "$tmp" && mv "$tmp" "$settings"
                echo "  update .claude/settings.json (removed SessionStop hook entry)"
            else
                echo "  skip   .claude/settings.json (hook entry not present)"
            fi
        else
            echo "  warn   jq not installed; manually remove the entry where .hooks.Stop[].command == 'scripts/auto-ship-hook.sh' from $settings"
        fi
    else
        echo "  skip   .claude/settings.json (file does not exist)"
    fi

    # .gitignore block
    if [ -f "$target/.gitignore" ] && grep -q "^# ship-sop runtime artifacts$" "$target/.gitignore"; then
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
    echo "Done. ship-sop is uninstalled."
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
    uninstall_mode "$TARGET"
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

# Check jq (required for auto-ship-hook.sh)
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

USER_CLAUDE_DIR="${HOME}/.claude"
mkdir -p "$USER_CLAUDE_DIR/agents" "$USER_CLAUDE_DIR/commands"

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

echo ""
if [ "$SELF_INSTALL" = true ]; then
    echo "Self-install — project-side files already present in source repo"
    mkdir -p "$TARGET/docs/reviews" "$TARGET/.ship"
    # Skip copying scripts/auto-ship-hook.sh and docs/templates/ship-sop.schema.json
    # since they live in the source repo. Still create the user-facing config
    # at the project root (different from the template under docs/templates/).
    copy_if_missing "$SCRIPT_DIR/docs/templates/ship-sop.config.json" "$TARGET/ship-sop.config.json" || true
else
    echo "Installing hook script + config in $TARGET"
    mkdir -p "$TARGET/scripts" "$TARGET/docs/reviews" "$TARGET/.ship"

    if copy_if_missing "$SCRIPT_DIR/scripts/auto-ship-hook.sh" "$TARGET/scripts/auto-ship-hook.sh"; then
        chmod +x "$TARGET/scripts/auto-ship-hook.sh"
    fi

    # Default config — only created if missing
    copy_if_missing "$SCRIPT_DIR/docs/templates/ship-sop.config.json" "$TARGET/ship-sop.config.json" || true
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

# ── Wire SessionStop hook (with consent) ──────────────────────────────────────

if [ "$NO_HOOK" = true ]; then
    echo ""
    echo "Skipping SessionStop hook wiring (--no-hook)."
    echo "Use /ship and /release manually."
else
    echo ""
    if prompt_yn "Wire SessionStop hook in $TARGET/.claude/settings.json so auto-mode fires after each Claude Code session?" "y"; then
        SETTINGS="$TARGET/.claude/settings.json"
        mkdir -p "$TARGET/.claude"

        # Claude Code requires each hook entry to nest its command:
        #   {"matcher": "*", "hooks": [{"type": "command", "command": "..."}]}
        # A flat {"command": "..."} entry parses as JSON but is discarded by the
        # harness, so the hook never runs and nothing reports an error. Every
        # write and every selector below must use the nested shape (P14).
        if [ ! -f "$SETTINGS" ]; then
            cat > "$SETTINGS" <<'EOF'
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "scripts/auto-ship-hook.sh" }
        ]
      }
    ]
  }
}
EOF
            echo "  create .claude/settings.json with SessionStop hook"
        else
            if command -v jq >/dev/null 2>&1; then
                # Idempotent merge: add the hook entry only if not already present
                if jq -e "$HOOK_NESTED_PROBE" "$SETTINGS" >/dev/null 2>&1; then
                    echo "  skip   .claude/settings.json (hook already wired)"
                elif jq -e "$HOOK_LEGACY_PROBE" "$SETTINGS" >/dev/null 2>&1; then
                    # Pre-P14 install: rewrite the dead flat entry in place rather
                    # than appending a second one.
                    tmp="$(mktemp)"
                    jq '.hooks.Stop = [ .hooks.Stop[]
                          | if (.command? // "") == "scripts/auto-ship-hook.sh"
                            then {"matcher": "*", "hooks": [{"type": "command", "command": "scripts/auto-ship-hook.sh"}]}
                            else . end ]' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
                    echo "  update .claude/settings.json (migrated legacy flat hook entry to nested shape)"
                else
                    tmp="$(mktemp)"
                    jq '.hooks //= {} | .hooks.Stop //= [] | .hooks.Stop += [{"matcher": "*", "hooks": [{"type": "command", "command": "scripts/auto-ship-hook.sh"}]}]' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
                    echo "  update .claude/settings.json (added SessionStop hook)"
                fi
            else
                echo "  warn   jq not installed; please add the following to .claude/settings.json manually:"
                echo "         $HOOK_ENTRY_EXAMPLE"
            fi
        fi

        # Post-install assertion. A silently-unwired hook is the failure this
        # whole batch exists to remove, so fail loudly rather than report success.
        if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
            if jq -e "$HOOK_NESTED_PROBE" "$SETTINGS" >/dev/null 2>&1; then
                echo "  verify SessionStop hook entry is parseable by Claude Code"
            else
                echo "" >&2
                echo "  ERROR  .claude/settings.json has no SessionStop hook entry Claude Code can parse." >&2
                echo "         Auto-mode would silently never fire. Expected shape:" >&2
                echo "         $HOOK_ENTRY_EXAMPLE" >&2
                exit 1
            fi
        fi
    else
        echo "Hook wiring skipped. To enable later, re-run setup.sh or edit .claude/settings.json directly."
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Done. Next steps:"
echo ""
echo "  1. Commit the install artifacts:"
echo "     - ship-sop.config.json (project's per-agent toggles + throttle)"
echo "     - .claude/settings.json (SessionStop hook wiring, if not already tracked)"
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
echo "     - $TARGET/scripts/auto-ship-hook.sh (executable)"
echo ""
echo "  4. Try a dry run:"
echo "     - Make a small commit, then in a Claude Code session in this project,"
echo "       run /ship to see the manual pipeline."
echo "     - End the session normally; auto-mode should fire if enabled."
echo ""
echo "  5. Toggle modes any time:"
echo "     /ship-on     enable auto-mode"
echo "     /ship-off    disable auto-mode (manual /ship still works)"
echo ""
echo "  6. To remove ship-sop later:"
echo "     ./setup.sh $TARGET --uninstall"
echo "     (add --keep-config to preserve your tuning, --force to remove locally-modified files)"
echo ""
