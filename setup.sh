#!/usr/bin/env bash
#
# ship-sop Setup Script
#
# Installs ship-sop into a target project:
#   - Three reference agents into ~/.claude/agents/
#   - Four slash commands into ~/.claude/commands/
#   - scripts/auto-ship-hook.sh into the project
#   - ship-sop.config.json at the project root (with defaults)
#   - An entry in .claude/settings.json wiring the SessionStop hook (with consent)
#
# Usage:
#   ./setup.sh /path/to/your/project [--no-hook] [--force]
#
# Options:
#   --no-hook   Skip the SessionStop hook wiring (manual /ship and /release only)
#   --force     Overwrite existing files
#
# Existing files are skipped (not overwritten) unless --force is passed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────

NO_HOOK=false
FORCE=false
TARGET=""

# ── Parse arguments ───────────────────────────────────────────────────────────

usage() {
    echo "Usage: $(basename "$0") /path/to/project [--no-hook] [--force]"
    echo ""
    echo "Options:"
    echo "  --no-hook   Skip the SessionStop hook wiring (manual /ship only)"
    echo "  --force     Overwrite existing files"
    echo ""
    echo "Run this from the ship-sop repo directory."
    exit 1
}

for arg in "$@"; do
    case "$arg" in
        --no-hook) NO_HOOK=true ;;
        --force)   FORCE=true ;;
        --help|-h) usage ;;
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

TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || {
    echo "Error: directory does not exist: $TARGET"
    exit 1
}

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
    read -r response
    response="${response:-$default}"
    [[ "$response" =~ ^[Yy]$ ]]
}

# ── Pre-flight ────────────────────────────────────────────────────────────────

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
echo "Installing hook script + config in $TARGET"

mkdir -p "$TARGET/scripts" "$TARGET/docs/reviews" "$TARGET/.ship"

if copy_if_missing "$SCRIPT_DIR/scripts/auto-ship-hook.sh" "$TARGET/scripts/auto-ship-hook.sh"; then
    chmod +x "$TARGET/scripts/auto-ship-hook.sh"
fi

# Default config — only created if missing
copy_if_missing "$SCRIPT_DIR/docs/templates/ship-sop.config.json" "$TARGET/ship-sop.config.json" || true
copy_if_missing "$SCRIPT_DIR/docs/templates/ship-sop.schema.json" "$TARGET/docs/templates/ship-sop.schema.json" || true

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

        if [ ! -f "$SETTINGS" ]; then
            cat > "$SETTINGS" <<'EOF'
{
  "hooks": {
    "Stop": [
      { "command": "scripts/auto-ship-hook.sh" }
    ]
  }
}
EOF
            echo "  create .claude/settings.json with SessionStop hook"
        else
            if command -v jq >/dev/null 2>&1; then
                # Idempotent merge: add the hook entry only if not already present
                if jq -e '.hooks.Stop[]? | select(.command == "scripts/auto-ship-hook.sh")' "$SETTINGS" >/dev/null 2>&1; then
                    echo "  skip   .claude/settings.json (hook already wired)"
                else
                    tmp="$(mktemp)"
                    jq '.hooks //= {} | .hooks.Stop //= [] | .hooks.Stop += [{"command": "scripts/auto-ship-hook.sh"}]' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
                    echo "  update .claude/settings.json (added SessionStop hook)"
                fi
            else
                echo "  warn   jq not installed; please add the following to .claude/settings.json manually:"
                echo "         {\"hooks\":{\"Stop\":[{\"command\":\"scripts/auto-ship-hook.sh\"}]}}"
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
echo "  1. Open ship-sop.config.json in $TARGET and confirm the defaults"
echo "     (per-agent toggles, throttle, release branch)."
echo ""
echo "  2. Verify the install:"
echo "     - ~/.claude/agents/{compliance-reviewer,diagram-builder,release-notes-writer}.md"
echo "     - ~/.claude/commands/{ship,release,ship-on,ship-off}.md"
echo "     - $TARGET/scripts/auto-ship-hook.sh (executable)"
echo ""
echo "  3. Try a dry run:"
echo "     - Make a small commit, then in a Claude Code session in this project,"
echo "       run /ship to see the manual pipeline."
echo "     - End the session normally; auto-mode should fire if enabled."
echo ""
echo "  4. Toggle modes any time:"
echo "     /ship-on     enable auto-mode"
echo "     /ship-off    disable auto-mode (manual /ship still works)"
echo ""
