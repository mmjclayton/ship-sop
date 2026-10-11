#!/usr/bin/env bash
# Native Codex installation: skills, reviewer agents, the reviewer runner and the
# user-scope push gate (registered in $CODEX_HOME/hooks.json unless --no-hook).
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
command -v jq >/dev/null || { echo 'setup-codex: jq is required' >&2; exit 1; }
ARGS=(); [ "$FORCE" = false ] || ARGS+=(--force)
if [ "$REMOVE" = true ]; then
    bash "$SOURCE/scripts/install-hooks.sh" --runtime codex --uninstall
    bash "$SOURCE/scripts/install-codex.sh" --uninstall ${ARGS[@]+"${ARGS[@]}"}
    if [ "$SOURCE" != "$TARGET" ] && [ -f "$TARGET/scripts/codex-review.sh" ]; then
        if [ "$FORCE" = true ] || cmp -s "$SOURCE/scripts/codex-review.sh" "$TARGET/scripts/codex-review.sh"; then rm "$TARGET/scripts/codex-review.sh"; fi
    fi
    echo 'Shared config, AGENTS.md, reviews and records retained.'
    exit 0
fi
bash "$SOURCE/scripts/install-codex.sh" ${ARGS[@]+"${ARGS[@]}"}
HOOK_ARGS=(--runtime codex); [ "$NO_HOOK" = false ] || HOOK_ARGS+=(--no-register)
bash "$SOURCE/scripts/install-hooks.sh" "${HOOK_ARGS[@]}"
# Receipts need the installed library; refuse to report success without it.
bash "$SOURCE/scripts/ship-receipt.sh" --check-lib --runtime codex >/dev/null
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
    printf '# ship-sop\n\nUse $ship to review changes and $release for deliberate releases.\nRead CLAUDE.md for project conventions when present.\nAuto-mode uses the user-scope ship-sop push gate; reviewers use the installed user-scope ship-sop runner.\n' > "$TARGET/AGENTS.md"
fi
if ! grep -q '^\.ship/' "$TARGET/.gitignore" 2>/dev/null; then printf '\n# ship-sop runtime artifacts\n.ship/\n' >> "$TARGET/.gitignore"; fi
if [ "$NO_HOOK" = true ]; then
    echo 'Codex ship-sop installed in manual mode (push gate not registered). Use $ship. Reload the session for new skills/agents.'
else
    echo 'Codex ship-sop installed. Use $ship; the push gate is registered in hooks.json. Reload the session for new skills/agents.'
fi
