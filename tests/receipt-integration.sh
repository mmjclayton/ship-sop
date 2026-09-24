#!/usr/bin/env bash
# Cross-package smoke test; point AGENT_SOP_SOURCE at the companion checkout.
set -euo pipefail
SOURCE=$(cd "$(dirname "$0")/.." && pwd)
: "${AGENT_SOP_SOURCE:?Set AGENT_SOP_SOURCE to the current agent-sop checkout}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export CODEX_HOME="$WORK/codex"
mkdir -p "$CODEX_HOME/scripts/hooks/agent-sop"
cp "$AGENT_SOP_SOURCE/scripts/hooks/sop-lib.sh" "$CODEX_HOME/scripts/hooks/agent-sop/"
git init -q -b main "$WORK/repo"
cd "$WORK/repo"
git config user.name Test
git config user.email test@example.invalid
printf '**Project type:** code\n' > AGENTS.md
cp "$SOURCE/docs/templates/ship-sop.config.json" ship-sop.config.json
printf 'base\n' > code.sh
git add .; git commit -qm base
BASE=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$BASE"
printf 'change\n' >> code.sh
git commit -qam change
jq '[.agents | to_entries[] | select(.value.enabled) |
  {name:.key,version:"fixture-v1",model:"fixture",verdict:"PASS",findings:[]}]' ship-sop.config.json > "$WORK/results.json"
printf '{"status":"PASS","evidence":"integration fixture"}\n' > "$WORK/tests.json"
run_receipt() {
    bash "$SOURCE/scripts/ship-receipt.sh" --base "$BASE" --results "$WORK/results.json" \
      --tests "$WORK/tests.json" --output "$1"
}
run_receipt docs/reviews/valid-ship-auto.json
. "$CODEX_HOME/scripts/hooks/agent-sop/sop-lib.sh"
sop_shipsop_covered "$PWD" "$(git rev-parse HEAD)"
if run_receipt docs/reviews/valid-ship-auto.json 2>/dev/null; then echo 'FAIL: overwrote evidence'; exit 1; fi
cp "$WORK/tests.json" "$WORK/tests-original.json"
printf '{"status":"FAIL","evidence":"later failure"}\n' >> "$WORK/tests.json"
if run_receipt docs/reviews/multidoc-ship-auto.json 2>/dev/null; then echo 'FAIL: discarded later test result'; exit 1; fi
cp "$WORK/tests-original.json" "$WORK/tests.json"
cp "$WORK/results.json" "$WORK/results-original.json"
cat "$WORK/results-original.json" >> "$WORK/results.json"
if run_receipt docs/reviews/multiresults-ship-auto.json 2>/dev/null; then echo 'FAIL: discarded later reviewer result'; exit 1; fi
cp "$WORK/results-original.json" "$WORK/results.json"
cp ship-sop.config.json "$CODEX_HOME/ship-sop.config.json"
mv ship-sop.config.json "$WORK/config.saved"
run_receipt docs/reviews/fallback-ship-auto.json
mv "$WORK/config.saved" ship-sop.config.json
jq '.[0].verdict="BLOCK"'  "$WORK/results.json" > "$WORK/blocked.json"
mv "$WORK/blocked.json" "$WORK/results.json"
if run_receipt docs/reviews/blocked-ship-auto.json 2>/dev/null; then echo 'FAIL: wrote blocked receipt'; exit 1; fi
test ! -e docs/reviews/blocked-ship-auto.json
echo 'PASS: real cross-package receipts qualify, reject BLOCK and preserve existing evidence'
