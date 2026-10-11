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
CODEX_DIR="${CODEX_HOME:-${SHIP_SOP_USER_HOME:-$HOME}/.codex}"
if [ "$NO_HOOK" = true ]; then
    echo "Codex ship-sop installed. --no-hook: $CODEX_DIR/hooks.json was left unchanged. Push-gate registrations in it now:"
    REGISTERED=''
    [ ! -f "$CODEX_DIR/hooks.json" ] || REGISTERED=$(jq -r '[.hooks[]?[]? | .hooks[]? | (.command? // "") | strings | select(test("sop-push-gate|sop-codex-hook"))] | .[]' "$CODEX_DIR/hooks.json" 2>/dev/null || echo "(could not read $CODEX_DIR/hooks.json)")
    if [ -n "$REGISTERED" ]; then printf '%s\n' "$REGISTERED" | sed 's/^/  /'; else echo '  none (use $ship manually)'; fi
else
    echo 'Codex ship-sop installed. Use $ship; the push gate is registered in hooks.json. Reload the session for new skills/agents.'
    # Codex runs hooks.json only with its `hooks` feature on (stable and on by
    # default in codex-cli 0.160) and only once the hook is trusted: a new or
    # changed hook asks for trust at the next session start.
    if command -v codex >/dev/null 2>&1; then
        HOOKS_FEATURE=$(codex features list 2>/dev/null | awk '$1 == "hooks" { print $NF; exit }') || HOOKS_FEATURE=''
        case "$HOOKS_FEATURE" in
            true) echo 'Codex hooks feature: on. Approve the new hook when Codex asks to trust it.' ;;
            false) echo 'Codex hooks feature is OFF, so hooks.json is ignored and the push gate will not run. Set hooks = true under [features] in config.toml, then restart Codex.' >&2; exit 1 ;;
            *) echo 'Could not read the Codex hooks feature state (codex features list); check that hooks are enabled, then approve the new hook when Codex asks to trust it.' >&2 ;;
        esac
    else
        echo 'codex not found on PATH: once installed, check that its hooks feature is on (codex features list) and approve the hook when asked.'
    fi
fi
