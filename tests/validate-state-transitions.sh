#!/usr/bin/env bash
# scripts/validate-state-transitions.sh: the Backlog state graph, the review
# citation on a shipped Feature/Refactor, trigger (b) for executable instruction
# paths, and the --assert-review substance check /ship relies on.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
V="$SOURCE/scripts/validate-state-transitions.sh"
WORK=$(mktemp -d)
SUITE_DONE=0
suite_trap() { local rc=$?; [ "$SUITE_DONE" = 1 ] || { echo "FAIL: suite stopped before its last check" >&2; rc=1; }; rm -rf "$WORK"; exit "$rc"; }
trap suite_trap EXIT
cd "$WORK"
mkdir -p docs/reviews
: > "$WORK/none-changed"

entry() { # <status> <type> [extra-line]
    printf '# Backlog\n\n### P7 - Thing\n`%s %s`\n%s\n\nbody\n\n---\n' "$1" "$2" "${3:-}"
}
validate() { # <before> <after> [changed-file]
    bash "$V" --before-file "$1" --after-file "$2" --self-mod-changed-file "${3:-$WORK/none-changed}" > "$WORK/out" 2>&1
}

entry '[OPEN]' '[Feature]' > before.md
entry '[IN PROGRESS]' '[Feature]' > after.md
validate before.md after.md
printf 'PASS: [OPEN] -> [IN PROGRESS] is legal\n'

entry '[VERIFIED - 2026-10-01]' '[Feature]' > before.md
entry '[OPEN]' '[Feature]' > after.md
if validate before.md after.md; then echo 'FAIL: revived a terminal item'; exit 1; fi
grep -q 'illegal' "$WORK/out"
printf 'PASS: a terminal state cannot be revived\n'

entry '[IN PROGRESS]' '[Refactor]' > before.md
entry '[SHIPPED - 2026-10-11]' '[Refactor]' > after.md
if validate before.md after.md; then echo 'FAIL: shipped a Refactor with no review'; exit 1; fi
entry '[SHIPPED - 2026-10-11]' '[Refactor]' 'review: docs/reviews/missing.md' > after.md
if validate before.md after.md; then echo 'FAIL: accepted a review citation that does not resolve'; exit 1; fi
grep -q 'does not exist' "$WORK/out"
printf '# review\n' > docs/reviews/real.md
entry '[SHIPPED - 2026-10-11]' '[Refactor]' 'review: docs/reviews/real.md' > after.md
validate before.md after.md
entry '[SHIPPED - 2026-10-11]' '[Refactor]' 'review skipped (P7): docs-only' > after.md
validate before.md after.md
printf 'PASS: a shipped Refactor cites a real review or an enumerated skip\n'

# Trigger (b): a branch touching the push gate needs a real review whatever the tag.
printf 'scripts/hooks/sop-push-gate.sh\n' > "$WORK/gate-changed"
entry '[IN PROGRESS]' '[Bug]' > before.md
entry '[SHIPPED - 2026-10-11]' '[Bug]' 'review skipped (P7): docs-only' > after.md
if validate before.md after.md "$WORK/gate-changed"; then echo 'FAIL: docs-only skip accepted for a push-gate change'; exit 1; fi
grep -q 'executable instruction surface' "$WORK/out"
entry '[SHIPPED - 2026-10-11]' '[Bug]' 'review: docs/reviews/real.md' > after.md
validate before.md after.md "$WORK/gate-changed"
printf 'PASS: changes to the push gate need a cited review regardless of tag\n'

cat > review-ok.md <<'EOF'
## Summary
Moves the push gate.
Severity: LOW
## Findings
- `scripts/install-hooks.sh:12` names the old path in a comment.
EOF
bash "$V" --assert-review review-ok.md > "$WORK/out" 2>&1
printf '## Summary\nLooks good.\nSeverity: NONE\n## Findings\nAll fine.\n' > review-vague.md
if bash "$V" --assert-review review-vague.md > "$WORK/out" 2>&1; then echo 'FAIL: review with no concrete anchor accepted'; exit 1; fi
printf 'PASS: --assert-review requires sections and a concrete anchor\n'
SUITE_DONE=1
