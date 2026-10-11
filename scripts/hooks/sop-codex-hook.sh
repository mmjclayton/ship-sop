#!/usr/bin/env bash
# Codex transport adapter for the push gate. sop-push-gate.sh owns every decision.
set -u
export AGENT_SOP_RUNTIME=codex
export AGENT_SOP_CONFIG_HOME="${CODEX_HOME:-${AGENT_SOP_USER_HOME:-$HOME}/.codex}"
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
    # Older hooks.json files may still route these events here. They are no-ops, so a
    # stale registration never errors or blocks a session.
    SessionStart|UserPromptSubmit|Stop) cat > /dev/null; exit 0 ;;
    PreToolUse) exec bash "$HOOK_DIR/sop-push-gate.sh" ;;
    *) echo 'sop-codex-hook: expected PreToolUse (or a retired SessionStart, UserPromptSubmit or Stop)' >&2; exit 1 ;;
esac
