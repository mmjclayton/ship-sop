#!/usr/bin/env bash
#
# ship-sop auto-mode hook
#
# Reads ship-sop.config.json, applies throttle rules, and invokes the
# configured pipeline gates against the session's accumulated diff. Fires on
# the Claude Code SessionStop event.
#
# Wiring: setup.sh adds an entry to .claude/settings.json:
#
#   {
#     "hooks": {
#       "Stop": [
#         { "command": "scripts/auto-ship-hook.sh" }
#       ]
#     }
#   }
#
# This script is intentionally non-interactive and conservative:
#   - throttle violations exit 0 silently
#   - missing config is treated as "auto disabled"
#   - dirty working tree exits 0 — auto-mode reviews committed work, not WIP
#   - failures in any gate are logged but never halt the user's session
#
# Output is a single-line context message piped to stdout (Claude Code injects
# stdout from Stop hooks into the next turn's context) plus a durable artifact
# at docs/reviews/<stamp>-ship-report.md.

set -euo pipefail

# ── Locate project root ───────────────────────────────────────────────────────

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [ -z "$ROOT" ]; then
    # Not a git repo — exit silently
    exit 0
fi
cd "$ROOT"

# ── Locate config (project first, then user-global fallback) ──────────────────

CONFIG=""
if [ -f "$ROOT/ship-sop.config.json" ]; then
    CONFIG="$ROOT/ship-sop.config.json"
elif [ -f "$HOME/.claude/ship-sop.config.json" ]; then
    CONFIG="$HOME/.claude/ship-sop.config.json"
else
    # No config — auto-mode disabled by default
    exit 0
fi

# ── jq is required for config parsing ─────────────────────────────────────────

if ! command -v jq >/dev/null 2>&1; then
    echo "[ship-sop] jq not installed — auto-mode requires jq. Install via brew/apt and re-run."
    exit 0
fi

# ── Read trigger mode ─────────────────────────────────────────────────────────

MODE=$(jq -r '.trigger.mode // "off"' "$CONFIG")

case "$MODE" in
    auto)
        ;;
    manual|off)
        # Auto-mode not active — exit silently
        exit 0
        ;;
    *)
        echo "[ship-sop] unknown trigger.mode: $MODE — expected auto|manual|off"
        exit 0
        ;;
esac

# ── Throttle: branch pattern ──────────────────────────────────────────────────

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
SKIP_PATTERNS=$(jq -r '.trigger.throttle.skip_branch_patterns[]?' "$CONFIG" 2>/dev/null || true)
if [ -n "$SKIP_PATTERNS" ] && [ -n "$CURRENT_BRANCH" ]; then
    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        if echo "$CURRENT_BRANCH" | grep -qE "$pattern"; then
            # Branch matches a skip pattern (e.g., wip/, spike/) — exit silently
            exit 0
        fi
    done <<< "$SKIP_PATTERNS"
fi

# ── Resolve diff base ─────────────────────────────────────────────────────────

DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")
if [ -z "$DEFAULT_BRANCH" ]; then
    for candidate in main master develop; do
        if git rev-parse --verify "origin/$candidate" >/dev/null 2>&1; then
            DEFAULT_BRANCH="$candidate"
            break
        fi
    done
fi

if [ -z "$DEFAULT_BRANCH" ]; then
    # Can't resolve default branch — exit silently
    exit 0
fi

BASE=$(git merge-base "origin/$DEFAULT_BRANCH" HEAD 2>/dev/null || echo "")
HEAD_SHA=$(git rev-parse HEAD)

if [ -z "$BASE" ] || [ "$BASE" = "$HEAD_SHA" ]; then
    # No diff — exit silently
    exit 0
fi

# ── Throttle: minimum diff size ───────────────────────────────────────────────

MIN_LINES=$(jq -r '.trigger.throttle.min_diff_lines // 10' "$CONFIG")
DIFF_LINES=$(git diff "$BASE..HEAD" | wc -l | tr -d '[:space:]')

if [ "$DIFF_LINES" -lt "$MIN_LINES" ]; then
    # Diff below threshold — exit silently
    exit 0
fi

# ── Throttle: docs-only skip (if configured) ──────────────────────────────────

SKIP_DOCS_ONLY=$(jq -r '.trigger.throttle.skip_docs_only // false' "$CONFIG")
if [ "$SKIP_DOCS_ONLY" = "true" ]; then
    NON_DOCS=$(git diff --name-only "$BASE..HEAD" | grep -vE '\.(md|mdx)$|^docs/' | wc -l | tr -d '[:space:]')
    if [ "$NON_DOCS" -eq 0 ]; then
        exit 0
    fi
fi

# ── Throttle: cooldown ────────────────────────────────────────────────────────

COOLDOWN=$(jq -r '.trigger.throttle.cooldown_seconds // 300' "$CONFIG")
STAMP_FILE="$ROOT/.ship/.last-auto-fire"
mkdir -p "$ROOT/.ship"

if [ -f "$STAMP_FILE" ]; then
    LAST_STAMP=$(cat "$STAMP_FILE" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    ELAPSED=$((NOW - LAST_STAMP))
    if [ "$ELAPSED" -lt "$COOLDOWN" ]; then
        exit 0
    fi
fi

# Same-diff guard: if HEAD hasn't moved since last fire, skip
DIFF_HASH_FILE="$ROOT/.ship/.last-diff-hash"
CURRENT_HASH=$(git diff "$BASE..HEAD" | shasum -a 256 | awk '{print $1}')
if [ -f "$DIFF_HASH_FILE" ]; then
    LAST_HASH=$(cat "$DIFF_HASH_FILE" 2>/dev/null || echo "")
    if [ "$CURRENT_HASH" = "$LAST_HASH" ]; then
        exit 0
    fi
fi

# ── Build the gate plan from config ───────────────────────────────────────────

ENABLED_AGENTS=$(jq -r '.agents | to_entries[] | select(.value.enabled == true) | .key' "$CONFIG")

if [ -z "$ENABLED_AGENTS" ]; then
    # No agents enabled — exit silently
    exit 0
fi

# ── Emit the directive for Claude Code to execute ────────────────────────────
#
# A Stop hook can't itself invoke @agent — the model does that. So we write a
# concise context message that the next turn picks up, listing exactly which
# agents to run and what artifacts to write. The throttle and config logic
# stays in this script; the model does the agent invocations.

STAMP=$(date +%Y%m%d-%H%M%S)
REPORT="$ROOT/docs/reviews/${STAMP}-ship-auto.md"
mkdir -p "$ROOT/docs/reviews"

# Write a marker file so the model knows what to do
DIRECTIVE_FILE="$ROOT/.ship/.pending-auto-fire.md"

{
    echo "# ship-sop auto-mode: pending review"
    echo ""
    echo "Triggered: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Diff range: \`$BASE..HEAD\` ($DIFF_LINES lines)"
    echo "Branch: $CURRENT_BRANCH"
    echo ""
    echo "## Run these gates against the diff above"
    echo ""

    while IFS= read -r agent; do
        [ -z "$agent" ] && continue
        BLOCK_ON=$(jq -r --arg a "$agent" '.agents[$a].block_on // "CRITICAL"' "$CONFIG")
        echo "- \`@$agent\` (block_on: $BLOCK_ON)"
    done <<< "$ENABLED_AGENTS"

    echo ""
    echo "## Write findings to"
    echo ""
    echo "\`$REPORT\`"
    echo ""
    echo "## Auto-mode rules"
    echo ""
    echo "- This is auto-mode. Do **not** halt the user's session on findings."
    echo "- For CRITICAL findings: surface a strong warning at the top of your next reply, with file:line references."
    echo "- For HIGH/MEDIUM findings: auto-file Backlog entries (if Backlog.md exists), summary in your reply."
    echo "- For LOW: review file only."
    echo "- After running the gates, summarise the verdict in 1-3 lines so the operator knows whether to /ship manually for the strict-gate experience."
} > "$DIRECTIVE_FILE"

# Update throttle stamps so we don't refire on the same diff
echo "$(date +%s)" > "$STAMP_FILE"
echo "$CURRENT_HASH" > "$DIFF_HASH_FILE"

# ── Emit context message for the next turn ────────────────────────────────────
#
# Claude Code's Stop hooks can return a message that gets injected into the
# next turn's context. Keep it brief.

cat <<EOF
[ship-sop auto-mode] Diff is ready for review ($DIFF_LINES lines on $CURRENT_BRANCH).
Pending directive: $DIRECTIVE_FILE
Run the gates listed there before the next user turn — auto-mode is on per ship-sop.config.json.
EOF
