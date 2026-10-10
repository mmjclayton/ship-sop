# Remaining independent-review items: P25, P19, P39, P38

**Date:** 2026-10-10
**Agent:** solo
**Commits:** f62d1bc (PR #25), daf1dfd (PR #26), 38cb15a, d351352

- **P25 (PR #25):** `scripts/auto-ship-hook.sh` deleted. Setup retires leftover entries (any hook event) before the script, matching copies against the seven shipped blob hashes; unfinished retirement exits non-zero. Actions pinned by SHA with Dependabot and gated auto-merge. P18 closed as superseded; P19 triaged, (d) fixed with an untrusted-diff rule in `/ship` and the Codex runner prompt.
- **P39 (PR #26):** `ship-receipt.sh --check-lib` names missing agent-sop functions and the minimum agent-sop (0a1e5ee); CI runs the cross-package test there and at main. `scripts/receipt-totals.sh` totals receipts across projects. README states the minimum, the totals tool's limits and one maintainer.
- **P38:** under Codex, every reviewer entry must match a run record in this repository's `.ship/reviews/` (reviewer, commit, base, clean exit, no timeout, one verdict line, same verdict). Claude unchanged; README table per runtime, including that the caller chooses `--runtime`.

Reviews: `docs/reviews/20261010-143321-ship-auto.md`, `20261010-144318-ship-auto.md`, `20261010-145222-ship-auto.md`; each three reviewers, two rounds, final PASS. Each PR's first round found one HIGH or several MEDIUMs, fixed before merge.

Not done: an agent-sop version constant (agent-sop held by another session); CI-run review enforcement (a cost decision for the operator).
