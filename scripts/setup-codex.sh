#!/usr/bin/env bash
# Native Codex installation; auto-mode composes with agent-sop's shared gates.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
TARGET=''; NO_HOOK=false; REMOVE=false; FORCE=false
for arg in "$@"; do
    case "$arg" in
        --no-hook) NO_HOOK=true ;; --uninstall) REMOVE=true ;; --force) FORCE=true ;;
        --keep-config|--keep-artifacts) ;; # shared data is always retained by Codex uninstall
        --help|-h) echo 'setup.sh <project> --runtime codex [--no-hook] [--force] [--uninstall]'; exit 0 ;;
        -*) echo "Unknown option: $arg" >&2; exit 2 ;;
        *) [ -z "$TARGET" ] || { echo 'Only one target is allowed' >&2; exit 2; }; TARGET="$arg" ;;
    esac
done
[ -n "$TARGET" ] || { echo 'A target project is required' >&2; exit 2; }
TARGET=$(cd "$TARGET" && pwd -P)
CODEX_DIR="${CODEX_HOME:-${AGENT_SOP_USER_HOME:-$HOME}/.codex}"
ARGS=(); [ "$FORCE" = false ] || ARGS+=(--force)
if [ "$REMOVE" = true ]; then
    bash "$SOURCE/scripts/install-codex.sh" --uninstall ${ARGS[@]+"${ARGS[@]}"}
    if [ "$SOURCE" != "$TARGET" ] && [ -f "$TARGET/scripts/codex-review.sh" ]; then
        if [ "$FORCE" = true ] || cmp -s "$SOURCE/scripts/codex-review.sh" "$TARGET/scripts/codex-review.sh"; then rm "$TARGET/scripts/codex-review.sh"; fi
    fi
    echo 'Shared config, AGENTS.md, reviews, records and agent-sop hooks retained. Set trigger.mode to manual to disable shared auto-mode.'
    exit 0
fi
# Validate the dependency before installing any ship-sop assets.
if [ "$NO_HOOK" = false ]; then
    if [ ! -f "$TARGET/Backlog.md" ] || [ ! -f "$TARGET/docs/sop/claude-agent-sop.md" ]; then
        echo 'Auto-mode needs agent-sop scaffolding in this target. Run agent-sop setup.sh <project> --runtime codex first.' >&2
        exit 1
    fi
    if [ ! -f "$CODEX_DIR/scripts/hooks/agent-sop/sop-codex-hook.sh" ] ||
       ! jq -e --arg wrapper "bash \"$CODEX_DIR/scripts/hooks/agent-sop/sop-codex-hook.sh\"" '([.hooks.Stop[]?.hooks[]?.command | select(. == ($wrapper + " Stop"))] | length > 0) and ([.hooks.PreToolUse[]?.hooks[]?.command | select(. == ($wrapper + " PreToolUse"))] | length > 0)' "$CODEX_DIR/hooks.json" >/dev/null 2>&1; then
        echo 'Codex auto-mode requires agent-sop setup.sh <project> --runtime codex first; or use --no-hook for manual mode.' >&2
        exit 1
    fi
fi
bash "$SOURCE/scripts/install-codex.sh" ${ARGS[@]+"${ARGS[@]}"}
mkdir -p "$TARGET/scripts" "$TARGET/docs/reviews" "$TARGET/docs/templates" "$TARGET/.ship"
for path in scripts/codex-review.sh docs/templates/ship-sop.schema.json; do
    [ "$SOURCE" != "$TARGET" ] || continue
    if [ ! -f "$TARGET/$path" ] || [ "$FORCE" = true ]; then
        [ ! -f "$TARGET/$path" ] || cp "$TARGET/$path" "$TARGET/$path.bak"
        cp "$SOURCE/$path" "$TARGET/$path"
    else echo "keep $TARGET/$path (existing; use --force to replace)"; fi
done
if [ ! -f "$TARGET/ship-sop.config.json" ]; then
    if [ "$NO_HOOK" = true ]; then jq '.trigger.mode="manual"' "$SOURCE/docs/templates/ship-sop.config.json" > "$TARGET/ship-sop.config.json"
    else cp "$SOURCE/docs/templates/ship-sop.config.json" "$TARGET/ship-sop.config.json"; fi
fi
if [ ! -f "$TARGET/AGENTS.md" ]; then
    printf '# ship-sop\n\nUse $ship to review changes and $release for deliberate releases.\nRead CLAUDE.md for project conventions when present.\nAuto-mode uses agent-sop user hooks; reviewers use the installed user-scope ship-sop runner.\n' > "$TARGET/AGENTS.md"
fi
if ! grep -q '^\.ship/' "$TARGET/.gitignore" 2>/dev/null; then printf '\n# ship-sop runtime artifacts\n.ship/\n' >> "$TARGET/.gitignore"; fi
echo 'Codex ship-sop installed. Use $ship; auto-mode uses agent-sop hooks. Reload the session for new skills/agents.'
