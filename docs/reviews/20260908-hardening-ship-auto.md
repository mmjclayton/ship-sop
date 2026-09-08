# Review and continuity hardening

Date: 2026-09-08

## Diff summary

Reviewed `e8630e1ab48d3a6ae21ae72a727e07399de191ba..71dab0b3ff171f2cb0284bf53bca9fb70ee53c4a` on `fix/review-continuity-hardening`. Implements structured review evidence, stable context recovery, local session coordination and observable reviewer execution. Both packages were upgraded together.

Coverage combines complete full-range source analysis from every configured reviewer with a fresh review of the correction diff at the final HEAD. The ranges are contiguous and pinned in `review_chain` for each reviewer. The later review covers the corrections; the earlier review covers the preceding range. Earlier findings were corrected in the new range; both original and correction outputs appear below. Reviewer definitions and policy were unchanged between these two stages.

Severity: NONE

## Findings

No unresolved issues remain after the three configured correction reviews. The parent executed tests. Concrete anchors include `scripts/resolve-resume-path.sh`, the receipt contract and its regression fixtures. Full-range findings and correction output are reproduced below.

Verdict: PASS

## Verification

PASS: tests/codex-install.sh, tests/receipt-contract.sh, tests/receipt-integration.sh with actual AGENT_SOP_SOURCE; blocking CI ShellCheck and JSON checks; state transitions and Claude/Codex replication checks. Upstream resolver and validator changes also passed all nine Agent SOP fixture suites.

## Earlier findings and dispositions

| Finding | Disposition |
|---|---|
| Markdown BLOCK stamps, malformed policy and executable instruction changes accepted as coverage | Structured validation and instruction rename regressions added. |
| Claims split by subdirectory, ambiguous paths and unreadable registry records | Common-directory ownership, path validation and explicit errors verified. |
| Target-controlled resolver or handoff symlinks read outside intended boundaries | Trusted installed resolver and symlink rejection verified. |
| Hash failures, conflicting main snapshots, next-close conflicts and external Git directories | Stable identity, explicit reconciliation, archived legacy generations and atomic migration verified. |
| Resolver errors became successful drift skips | Caller now propagates unsafe resolution failures. |
| Expired presence accumulated; identity/schema errors became successful fallbacks | Locked pruning, batch parsing and explicit error handling verified. |
| Multi-document results lost failures; timeout descendants survived; telemetry failures were hidden | Strict single-document input, process-group termination and explicit telemetry status verified. |
| Claude close-out retained obsolete Markdown-only review instructions | Installed close-out routes through the receipt-producing ship workflow. |
| Symlinked legacy directories or invalid enumerated snapshots were skipped; doctor omitted dependencies | Starting-directory symlinks are followed, every enumerated snapshot is validated, and doctor checks all installed runtime dependencies. |

Earlier BLOCK results and model-capacity failures were not counted as passes. Fixes were committed and new independent reviews were run. Raw local execution evidence remains under `.ship/reviews`; historical review replies remain in `/tmp/sop-hardening-reviews`.

## Final reviewer telemetry

| Reviewer | Elapsed seconds | Input tokens | Cached input tokens | Output tokens |
|---|---:|---:|---:|---:|
| code-reviewer | 35 | 119328 | 94208 | 595 |
| security-reviewer | 45 | 139524 | 116736 | 684 |
| silent-failure-hunter | 37 | 110057 | 80512 | 577 |

CLI-reported usage, not billed cost. Cached input is reported separately; do not add it to input totals. Model remains runtime-default-unresolved. This table covers final correction reviews only and excludes full-range and earlier fix/review iterations.

## Limits and remaining decisions

Claims are cooperative and local to linked worktrees. Use one writer per worktree; they do not coordinate separate clones or machines. Installation diagnostics do not prove execution in every fresh runtime session. Local receipts are not an adversarial boundary against their author. No fresh native-model benchmark or total-cost advantage is claimed. Publication and the budgeted comparison pilot remain separate next steps.

## code-reviewer full-range output

Review evidence: /Users/matt_clayton/Projects/ship-sop/.ship/reviews/20260908T074608Z-code-reviewer.cuxtOE
## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 1 | info |
| LOW | 0 | pass |

Source analysis completed. No files modified or write-producing suites run.

## Findings

[MEDIUM] Migration silently skips symlinked legacy memory directories  
File: `scripts/resolve-resume-path.sh:190`  
Issue: The preceding directory checks accept symlinks, but `find "$LEGACY_DIR"` does not follow a symlink supplied as its starting path. For a symlinked legacy memory directory containing snapshots, enumeration succeeds with no matches. Migration then reports success without copying anything; subsequent reads still demand migration.  
Evidence: Lines 187-190 accept the directory and enumerate without `-H`; lines 234-235 report success without checking whether snapshots were found.  
Fix: Use `find -H "$LEGACY_DIR" -maxdepth 1 ...` to follow the starting directory symlink. Add a fixture verifying that migration copies snapshots from a symlinked legacy memory directory.

Verdict: PASS

## code-reviewer correction output

Review evidence: /Users/matt_clayton/Projects/ship-sop/.ship/reviews/20260908T075437Z-code-reviewer.CZMNtM
| Severity | Count |
|---|---:|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |

No issues found in the specified range.

- `scripts/resolve-resume-path.sh:190` follows a symlinked legacy directory during enumeration.
- `scripts/resolve-resume-path.sh:208` and `:213` reject invalid or unreadable snapshots before copying.
- `.claude/agent-sop.config.json:40` matches the resolver’s SHA-256.

Source analysis completed. Test execution remains with the parent; no artifacts written.

Verdict: PASS

## security-reviewer full-range output

Review evidence: /Users/matt_clayton/Projects/ship-sop/.ship/reviews/20260908T074802Z-security-reviewer.mt4VTF
Source analysis completed for `e8630e1..e386087`. No actionable security findings identified.

Reviewed shell input handling, reviewer isolation, telemetry storage, receipt assembly, migration paths and installation changes. Secret scans found no matches. No Node dependency manifest was present, so `npm audit` was not applicable.

Tests remain the parent’s responsibility. External Agent SOP validator semantics were outside this diff.

Verdict: PASS

## security-reviewer correction output

Review evidence: /Users/matt_clayton/Projects/ship-sop/.ship/reviews/20260908T075512Z-security-reviewer.9ZdiYL
No security findings in the scoped diff.

Reviewed symlink handling, snapshot validation, shell quoting, migration publication and baseline hash changes. The changes preserve explicit migration and strengthen rejection of invalid or unreadable snapshots. No secrets or dependency changes were introduced.

Source analysis is complete. Test execution remains with the parent. The external `sop-doctor.sh` baseline could not be independently matched because that script is absent from this checkout.

Verdict: PASS

## silent-failure-hunter full-range output

Review evidence: /Users/matt_clayton/Projects/ship-sop/.ship/reviews/20260908T074858Z-silent-failure-hunter.ZijS1t
- **MEDIUM | scripts/resolve-resume-path.sh:190** - Migration silently succeeds without copying snapshots when `LEGACY_DIR` is a symlink to a directory. The preceding `-d`, `-r` and `-x` checks accept it, but `find` does not follow the command-line symlink by default. Enumeration returns empty, and migration exits successfully at line 235. Existing history remains unmigrated. **Fix:** use `find -H "$LEGACY_DIR" ...`, or explicitly reject symlinked storage with a diagnostic.

Source analysis completed. Tests remain with the parent. This finding is below the configured HIGH blocking threshold.

Verdict: PASS

## silent-failure-hunter correction output

Review evidence: /Users/matt_clayton/Projects/ship-sop/.ship/reviews/20260908T075557Z-silent-failure-hunter.SvhJHw
No findings in the scoped diff. Migration enumeration errors propagate, and invalid or unreadable snapshots now produce explicit diagnostics and exit code 2 instead of being silently skipped.

Source analysis completed. Test execution remains with the parent.

Verdict: PASS

