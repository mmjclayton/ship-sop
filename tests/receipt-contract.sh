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
# Scope rule stubbed to the same shape as the library's (ship-sop P33): the
# integration test asserts the in-scope set and that a receipt lacking an
# in-scope reviewer is refused, so the stub must carry both.
sop_changed_files_json() { git -C "$1" diff --no-renames --name-only "$2..$3" 2>/dev/null | jq -R . | jq -sc .; }
sop_agents_in_scope() {
    jq -c --argjson files "$2" '[.agents | to_entries[] | select(.value.enabled == true) | . as $a |
      select(($a.value | has("paths") | not) or any($files[]; . as $f | any($a.value.paths[]; . as $p | $f | test($p)))) |
      {key: $a.key, block_on: ($a.value.block_on // "CRITICAL")}]' "$1"
}
sop_receipt_valid() {
    local scope
    scope=$(sop_agents_in_scope "$(sop_effective_config "$1")" "$(sop_changed_files_json "$1" "$(jq -r .base "$2")" "$(jq -r .head "$2")")")
    jq -e --argjson scope "$scope" '. as $r | .schema_version == 1 and .policy_sha256 == "fixture-policy" and
      (.base | length == 40) and (.head | length == 40) and (.tree | length == 40) and
      .tests.status == "PASS" and all(.reviewers[]; .verdict == "PASS") and
      all($scope[]; .key as $k | any($r.reviewers[]; .name == $k))' "$2" >/dev/null
}
sop_shipsop_covered() { sop_receipt_valid "$1" "$1/docs/reviews/valid-ship-auto.json"; }
STUB
AGENT_SOP_SOURCE="$WORK/companion" bash "$SOURCE/tests/receipt-integration.sh"
