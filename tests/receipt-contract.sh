#!/usr/bin/env bash
# Test assembly and IPC with a policy stub; semantic policy fixtures live in Agent SOP.
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/companion/scripts/hooks"
cat > "$WORK/companion/scripts/hooks/sop-lib.sh" <<'STUB'
sop_effective_config() {
    if [ -f "$1/ship-sop.config.json" ]; then printf '%s/ship-sop.config.json' "$1"
    else printf '%s/ship-sop.config.json' "$CODEX_HOME"; fi
}
sop_policy_digest() { test -f "$1" && printf fixture-policy; }
sop_receipt_valid() {
    jq -e '.schema_version == 1 and .policy_sha256 == "fixture-policy" and
      (.base | length == 40) and (.head | length == 40) and (.tree | length == 40) and
      .tests.status == "PASS" and all(.reviewers[]; .verdict == "PASS")' "$2" >/dev/null
}
sop_shipsop_covered() { sop_receipt_valid "$1" "$1/docs/reviews/valid-ship-auto.json"; }
STUB
AGENT_SOP_SOURCE="$WORK/companion" bash "$SOURCE/tests/receipt-integration.sh"
