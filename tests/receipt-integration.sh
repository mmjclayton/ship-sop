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
  {name:.key,version:"fixture-v1",model:"fixture",verdict:"PASS",findings:[],launches:1,rechecks:0,block_rounds:0,usage:null}]' ship-sop.config.json > "$WORK/results.json"
printf '{"status":"PASS","evidence":"integration fixture"}\n' > "$WORK/tests.json"
run_receipt() {
    bash "$SOURCE/scripts/ship-receipt.sh" --base "$BASE" --results "$WORK/results.json" \
      --tests "$WORK/tests.json" --output "$1"
}
# Runner evidence as scripts/codex-review.sh leaves it (P38).
evidence() { # agent verdict head [exit_code] [timed_out]
    local dir
    mkdir -p .ship/reviews
    dir=$(mktemp -d ".ship/reviews/20261010T000000Z-$1.XXXXXX")
    jq -n --arg a "$1" --arg h "$3" --arg b "$BASE" --argjson e "${4:-0}" --argjson t "${5:-false}" \
        '{agent:$a,head:$h,base:$b,exit_code:$e,timed_out:$t}' > "$dir/metadata.json"
    printf 'Findings: none\n\nVerdict: %s\n' "$2" > "$dir/result.md"
}
refused() { # output reason-pattern
    if run_receipt "$1" 2> "$WORK/refusal"; then echo "FAIL: $1 written without matching evidence"; exit 1; fi
    grep -q "$2" "$WORK/refusal" || { echo "FAIL: $1 refused for the wrong reason:"; cat "$WORK/refusal"; exit 1; }
    test ! -e "$1"
}
HEAD_SHA=$(git rev-parse HEAD)
refused docs/reviews/no-evidence-ship-auto.json 'no Codex runner evidence'
evidence code-reviewer PASS "$HEAD_SHA"
evidence silent-failure-hunter PASS "$HEAD_SHA"
evidence security-reviewer BLOCK "$HEAD_SHA"
refused docs/reviews/verdict-mismatch-ship-auto.json 'security-reviewer'
evidence security-reviewer PASS "$BASE"
refused docs/reviews/other-head-ship-auto.json 'security-reviewer'
evidence security-reviewer PASS "$HEAD_SHA" 124 true
refused docs/reviews/timed-out-ship-auto.json 'security-reviewer'
jq '.[0].name = "../x"' "$WORK/results.json" > "$WORK/bad-name.json"
cp "$WORK/results.json" "$WORK/results-kept.json"; cp "$WORK/bad-name.json" "$WORK/results.json"
refused docs/reviews/bad-name-ship-auto.json 'invalid reviewer name'
cp "$WORK/results-kept.json" "$WORK/results.json"
evidence security-reviewer PASS "$HEAD_SHA"
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
jq 'map(del(.launches))' "$WORK/results-original.json" > "$WORK/results.json"
if run_receipt docs/reviews/uncounted-ship-auto.json 2>/dev/null; then echo 'FAIL: wrote a version-2 receipt without run counts'; exit 1; fi
cp "$WORK/results-original.json" "$WORK/results.json"
jq '.[0].verdict="BLOCK"'  "$WORK/results.json" > "$WORK/blocked.json"
mv "$WORK/blocked.json" "$WORK/results.json"
if run_receipt docs/reviews/blocked-ship-auto.json 2>/dev/null; then echo 'FAIL: wrote blocked receipt'; exit 1; fi
test ! -e docs/reviews/blocked-ship-auto.json
# Reviewer scope by path (P33): the template scopes security-reviewer, so a
# TypeScript-only range needs no security result, while the shell range above
# (code.sh) did. A receipt lacking an in-scope reviewer is still refused.
git checkout -q -b scoped "$BASE"
printf 'export const x = 1\n' > lib.ts
git add lib.ts; git commit -qm 'feat: ts only'
evidence code-reviewer PASS "$(git rev-parse HEAD)"
evidence silent-failure-hunter PASS "$(git rev-parse HEAD)"
sop_agents_in_scope ship-sop.config.json "$(sop_changed_files_json . "$BASE" HEAD)" | jq -e 'map(.key) | index("security-reviewer") == null and index("code-reviewer") != null' >/dev/null || { echo 'FAIL: scope rule did not exclude the scoped reviewer on a ts-only range'; exit 1; }
sop_agents_in_scope ship-sop.config.json "$(sop_changed_files_json . "$BASE" "$(git rev-parse main)")" | jq -e 'map(.key) | index("security-reviewer") != null' >/dev/null || { echo 'FAIL: scope rule did not include the scoped reviewer on the shell range'; exit 1; }
jq 'map(select(.name != "security-reviewer"))' "$WORK/results-original.json" > "$WORK/results.json"
run_receipt docs/reviews/scoped-ship-auto.json
jq 'map(select(.name != "code-reviewer"))' "$WORK/results-original.json" > "$WORK/results.json"
if run_receipt docs/reviews/scoped-missing-ship-auto.json 2>/dev/null; then echo 'FAIL: accepted a receipt missing an in-scope reviewer'; exit 1; fi
test ! -e docs/reviews/scoped-missing-ship-auto.json
# Claude subagents leave no runner evidence; that runtime is unchanged.
mkdir -p "$WORK/user/.claude/scripts/hooks/agent-sop"
cp "$AGENT_SOP_SOURCE/scripts/hooks/sop-lib.sh" "$WORK/user/.claude/scripts/hooks/agent-sop/"
rm -rf .ship/reviews
jq 'map(select(.name != "security-reviewer"))' "$WORK/results-original.json" > "$WORK/results.json"
AGENT_SOP_USER_HOME="$WORK/user" bash "$SOURCE/scripts/ship-receipt.sh" --runtime claude --base "$BASE" \
    --results "$WORK/results.json" --tests "$WORK/tests.json" --output docs/reviews/claude-ship-auto.json
echo 'PASS: real cross-package receipts qualify, reject BLOCK, preserve existing evidence, honour reviewer scope and require run counts'
echo 'PASS: Codex receipts need matching runner evidence (commit, base, clean exit, verdict); Claude unchanged'

