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

# ── Diagnostics ───────────────────────────────────────────────────────────────
#
# Set SHIP_SOP_DEBUG=1 to print one-line stderr diagnostics for every silent
# exit path. Default behaviour stays silent so production hook output is not
# polluted; this is a troubleshooting toggle for "why didn't auto-mode fire?"

skip_log() {
    if [ "${SHIP_SOP_DEBUG:-0}" = "1" ]; then
        echo "[ship-sop] skip: $*" >&2
    fi
}

# ── Locate project root ───────────────────────────────────────────────────────

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [ -z "$ROOT" ]; then
    skip_log "not a git repo"
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
    skip_log "no config (auto-mode disabled by default)"
    exit 0
fi

# ── jq is required for config parsing ─────────────────────────────────────────

if ! command -v jq >/dev/null 2>&1; then
    echo "[ship-sop] jq not installed — auto-mode requires jq. Install via brew/apt and re-run." >&2
    exit 0
fi

# ── Schema sanity check (warn on unknown keys) ────────────────────────────────
#
# Catch typos like `enabld: true` that would silently treat a gate as disabled.
# Warn-only — never block. Whitelist of known top-level / throttle / per-agent
# keys; anything else gets a single stderr advisory line.

KNOWN_TOP_LEVEL='trigger agents release artifacts $schema'
KNOWN_TRIGGER='mode throttle'
KNOWN_THROTTLE='min_diff_lines skip_docs_only cooldown_seconds skip_branch_patterns'
KNOWN_AGENT='enabled block_on auto_file_backlog'
KNOWN_RELEASE='auto_publish default_branch version_source'
KNOWN_ARTIFACTS='retain_ship_artifact_days'

warn_unknown_keys() {
    local context="$1" actual_keys="$2" known_keys="$3"
    local k
    for k in $actual_keys; do
        case " $known_keys " in
            *" $k "*) ;;
            *) echo "[ship-sop] config warning: unknown key '$k' in $context" >&2 ;;
        esac
    done
}

ACTUAL_TOP=$(jq -r 'keys[]' "$CONFIG" 2>/dev/null || true)
warn_unknown_keys "top-level" "$ACTUAL_TOP" "$KNOWN_TOP_LEVEL"

ACTUAL_TRIGGER=$(jq -r '.trigger | keys[]?' "$CONFIG" 2>/dev/null || true)
warn_unknown_keys ".trigger" "$ACTUAL_TRIGGER" "$KNOWN_TRIGGER"

ACTUAL_THROTTLE=$(jq -r '.trigger.throttle | keys[]?' "$CONFIG" 2>/dev/null || true)
warn_unknown_keys ".trigger.throttle" "$ACTUAL_THROTTLE" "$KNOWN_THROTTLE"

ACTUAL_RELEASE=$(jq -r '.release | keys[]?' "$CONFIG" 2>/dev/null || true)
warn_unknown_keys ".release" "$ACTUAL_RELEASE" "$KNOWN_RELEASE"

ACTUAL_ARTIFACTS=$(jq -r '.artifacts | keys[]?' "$CONFIG" 2>/dev/null || true)
warn_unknown_keys ".artifacts" "$ACTUAL_ARTIFACTS" "$KNOWN_ARTIFACTS"

while IFS= read -r agent_name; do
    [ -z "$agent_name" ] && continue
    actual_agent_keys=$(jq -r --arg a "$agent_name" '.agents[$a] | keys[]?' "$CONFIG" 2>/dev/null || true)
    warn_unknown_keys ".agents.$agent_name" "$actual_agent_keys" "$KNOWN_AGENT"
done < <(jq -r '.agents | keys[]?' "$CONFIG" 2>/dev/null || true)

# ── Read trigger mode ─────────────────────────────────────────────────────────

MODE=$(jq -r '.trigger.mode // "off"' "$CONFIG")

case "$MODE" in
    auto)
        ;;
    manual|off)
        skip_log "trigger.mode=$MODE (not auto)"
        exit 0
        ;;
    *)
        echo "[ship-sop] unknown trigger.mode: $MODE — expected auto|manual|off" >&2
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
            skip_log "branch '$CURRENT_BRANCH' matches skip pattern '$pattern'"
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
    skip_log "cannot resolve default branch (no origin/HEAD; no origin/{main,master,develop})"
    exit 0
fi

BASE=$(git merge-base "origin/$DEFAULT_BRANCH" HEAD 2>/dev/null || echo "")
HEAD_SHA=$(git rev-parse HEAD)

if [ -z "$BASE" ] || [ "$BASE" = "$HEAD_SHA" ]; then
    skip_log "no diff vs origin/$DEFAULT_BRANCH"
    exit 0
fi

# Cache the diff once — reused for line count and hash below to avoid double work.
DIFF_OUT=$(git diff "$BASE..HEAD")

# ── Throttle: minimum diff size ───────────────────────────────────────────────

MIN_LINES=$(jq -r '.trigger.throttle.min_diff_lines // 10' "$CONFIG")
DIFF_LINES=$(printf '%s\n' "$DIFF_OUT" | wc -l | tr -d '[:space:]')

if [ "$DIFF_LINES" -lt "$MIN_LINES" ]; then
    skip_log "diff $DIFF_LINES lines < threshold $MIN_LINES"
    exit 0
fi

# ── Throttle: docs-only skip (if configured) ──────────────────────────────────

SKIP_DOCS_ONLY=$(jq -r '.trigger.throttle.skip_docs_only // false' "$CONFIG")
if [ "$SKIP_DOCS_ONLY" = "true" ]; then
    NON_DOCS=$(git diff --name-only "$BASE..HEAD" | grep -vE '\.(md|mdx)$|^docs/' | wc -l | tr -d '[:space:]')
    if [ "$NON_DOCS" -eq 0 ]; then
        skip_log "skip_docs_only=true and diff is docs-only"
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
        skip_log "cooldown elapsed=${ELAPSED}s < ${COOLDOWN}s"
        exit 0
    fi
fi

# Same-diff guard: if HEAD hasn't moved since last fire, skip.
# Use shasum (BSD/macOS) with sha256sum (GNU/Linux) fallback for portability.
diff_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        printf '%s\n' "$DIFF_OUT" | shasum -a 256 | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        printf '%s\n' "$DIFF_OUT" | sha256sum | awk '{print $1}'
    else
        echo ""
    fi
}
DIFF_HASH_FILE="$ROOT/.ship/.last-diff-hash"
CURRENT_HASH=$(diff_sha256)
if [ -n "$CURRENT_HASH" ] && [ -f "$DIFF_HASH_FILE" ]; then
    LAST_HASH=$(cat "$DIFF_HASH_FILE" 2>/dev/null || echo "")
    if [ "$CURRENT_HASH" = "$LAST_HASH" ]; then
        skip_log "diff unchanged since last fire (hash match)"
        exit 0
    fi
fi

# ── Detect docs-only diff ─────────────────────────────────────────────────────
#
# When every changed file is documentation (^docs/, *.md, *.mdx, ^README),
# hard-blocking gates (security, compliance) have no real surface to evaluate.
# Mirror /ship's behaviour: filter to advisory gates (block_on: "never") only.
# This keeps diagram-builder running so generated docs stay in sync, while
# avoiding noise from gates that would always APPROVE on a docs-only diff.

DOCS_ONLY=true
while IFS= read -r f; do
    [ -z "$f" ] && continue
    # Match: docs/*.md|*.mdx, top-level *.md|*.mdx, or README / README.md exactly.
    # Avoids false positives like docs/img.png and READMENOT.md.
    if ! echo "$f" | grep -qE '^docs/.*\.(md|mdx)$|^[^/]+\.(md|mdx)$|^README(\.md)?$'; then
        DOCS_ONLY=false
        break
    fi
done < <(git diff --name-only "$BASE..HEAD")

# ── Build the gate plan from config ───────────────────────────────────────────

if [ "$DOCS_ONLY" = true ]; then
    # On docs-only diffs, run only advisory gates. A gate is advisory iff its
    # block_on is "never" — hard-blocking gates (CRITICAL/HIGH/MEDIUM) are skipped.
    ENABLED_AGENTS=$(jq -r '.agents | to_entries[] | select(.value.enabled == true and .value.block_on == "never") | .key' "$CONFIG")
else
    ENABLED_AGENTS=$(jq -r '.agents | to_entries[] | select(.value.enabled == true) | .key' "$CONFIG")
fi

if [ -z "$ENABLED_AGENTS" ]; then
    skip_log "no agents enabled (or all hard-blocking on docs-only diff)"
    exit 0
fi

# ── Optional retention prune (ship-sop artifacts only) ────────────────────────
#
# Pre-fire cleanup of stale ship-sop gate artifacts under docs/reviews/.
# Scoped strictly to ship-sop's filename pattern (YYYYMMDD-HHMMSS-*.md) so we
# never touch agent-sop's permanent /update-sop reviews (YYYY-MM-DD_*.md).
# Off by default; opt in via `artifacts.retain_ship_artifact_days` in config.

RETAIN_DAYS=$(jq -r '.artifacts.retain_ship_artifact_days // 0' "$CONFIG")
if [ "$RETAIN_DAYS" -gt 0 ] 2>/dev/null && [ -d "$ROOT/docs/reviews" ]; then
    # Strictly match ship-sop's `date +%Y%m%d-%H%M%S` stamp format:
    # 8 digits, hyphen, 6 digits, hyphen, anything, .md
    # This avoids matching agent-sop's YYYY-MM-DD_<agent-id>_P<n>.md (which
    # has hyphens *inside* the date prefix and underscores between segments).
    find "$ROOT/docs/reviews" -maxdepth 1 -type f \
        -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-*.md' \
        -mtime +"$RETAIN_DAYS" -delete 2>/dev/null || true
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
    if [ "$DOCS_ONLY" = true ]; then
        echo "Mode: docs-only (hard-blocking gates skipped — only advisory gates listed below)"
    fi
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
