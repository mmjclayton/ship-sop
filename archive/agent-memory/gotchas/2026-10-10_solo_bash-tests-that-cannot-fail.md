# Bash assertions that can never fail under set -e

**Date:** 2026-10-10
**Agent:** solo

**The surprise.** Three test assertions written this session passed whatever the code did, and reviewers found each one:
- `! grep -q pattern file` as a statement: `set -e` ignores a negated command, so it never stops the test (same in `tests/codex-install.sh` from earlier work).
- `while read ...; done < <(jq ...)`: a jq failure inside the process substitution does not trip `set -e`, so the loop runs fewer times or none and the check passes.
- `stat -f %Lp FILE || stat -c %a FILE`: GNU `stat -f` means filesystem status and prints to stdout, so the macOS-first fallback breaks on Linux CI.

**Expected.** `set -euo pipefail` makes any failing command fatal.

**Rule.** Write negative assertions as `if grep -q ...; then echo FAIL; exit 1; fi`; capture `jq` output into a variable with `|| exit 1` before looping; use `find FILE -perm 644 | grep -q .` for modes. After adding a check, remove it from the code under test and confirm the test fails.
