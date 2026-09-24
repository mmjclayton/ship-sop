#!/usr/bin/env bash
# codex-usage.sh sums a reviewer's run telemetry, or refuses to guess.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
meta() { # meta DIR AGENT STATUS ELAPSED [USAGE_JSON]
    mkdir -p "$WORK/$1"
    jq -n --arg a "$2" --arg s "$3" --argjson e "$4" --argjson u "${5:-null}" \
      '{agent:$a,head:"h",base:"b",model_requested:"m",runtime:"codex fixture",elapsed_seconds:$e,exit_code:0,usage:$u,telemetry_status:$s,timed_out:false}' > "$WORK/$1/metadata.json"
}
meta launch code-reviewer available 40 '[{"input_tokens":100,"cached_input_tokens":20,"cache_write_input_tokens":5,"output_tokens":30,"reasoning_output_tokens":7}]'
meta recheck code-reviewer available 15 '[{"input_tokens":50,"cached_input_tokens":40,"cache_write_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":2},{"input_tokens":1,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}]'
meta blind code-reviewer unavailable 9
meta other security-reviewer available 3 '[{"input_tokens":1,"output_tokens":1}]'
OUT=$(bash "$SOURCE/scripts/codex-usage.sh" --agent code-reviewer "$WORK/launch" "$WORK/recheck")
echo "$OUT" | jq -e '.source == "codex-review" and .runs == 2 and .turns == 3 and .elapsed_seconds == 55
  and .tokens.input_tokens == 151 and .tokens.cached_input_tokens == 60 and .tokens.cache_write_input_tokens == 5
  and .tokens.output_tokens == 41 and .tokens.reasoning_output_tokens == 9 and .evidence == ["launch","recheck"]' >/dev/null
echo 'PASS: two runs sum to one usage object'
OUT=$(bash "$SOURCE/scripts/codex-usage.sh" "$WORK/launch" "$WORK/blind" 2> "$WORK/err")
[ "$OUT" = null ]; grep -q 'usage unknown: code-reviewer run with telemetry unavailable' "$WORK/err"
echo 'PASS: a run without telemetry makes the total null, never a partial sum'
if bash "$SOURCE/scripts/codex-usage.sh" "$WORK/launch" "$WORK/other" 2>/dev/null; then echo 'FAIL: mixed reviewers accepted'; exit 1; fi
if bash "$SOURCE/scripts/codex-usage.sh" --agent security-reviewer "$WORK/launch" 2>/dev/null; then echo 'FAIL: wrong reviewer accepted'; exit 1; fi
if bash "$SOURCE/scripts/codex-usage.sh" "$WORK" 2>/dev/null; then echo 'FAIL: non-evidence directory accepted'; exit 1; fi
mkdir -p "$WORK/old"; printf '{"agent":"code-reviewer"}\n' > "$WORK/old/metadata.json"
if bash "$SOURCE/scripts/codex-usage.sh" "$WORK/old" 2>/dev/null; then echo 'FAIL: pre-telemetry metadata accepted'; exit 1; fi
echo 'PASS: mixed, mismatched, non-evidence and pre-telemetry inputs are refused'
