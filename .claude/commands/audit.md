---
description: Run a whole-codebase compliance audit (compliance-reviewer in --audit mode). Catches standing gaps that diff-bound /ship can't see — missing privacy policy files, missing GDPR endpoints, shadow controls, lawful-basis docs absent. Use at launch-readiness milestones, monthly compliance reviews, or post-acquisition due-diligence. Always manual.
ship_sop_version: "2026-04-25"
---

Run a whole-codebase compliance audit. Different from `/ship` — `/ship` reviews a diff, `/audit` reviews the entire repository.

`/audit` is the answer to: *"My ship-pipeline gates have been clean for months. Why didn't they catch [missing privacy policy / no data-export endpoint / dead middleware that looks like a security control]?"*

The answer: those are *standing* gaps — the absence of files or routes that predate ship-sop's installation. Diff-bound gates can't see them. `/audit` does.

## When to run

- **Launch-readiness milestone.** Before inviting paid users, before App Store submission, before a public beta. Audit mode catches the GDPR/CCPA gaps that block launches.
- **Monthly compliance review.** Standing gaps accumulate. Cron a `/audit` reminder once a month.
- **Post-acquisition due diligence.** Inheriting a codebase? `/audit` is a fast first pass at "what compliance debt did we just buy?"
- **After installing ship-sop on an existing codebase.** Diff-mode gates only protect future changes. `/audit` is the catch-up pass.

## Pre-flight

```bash
# Must be in a git repo
git rev-parse --show-toplevel >/dev/null 2>&1 || {
    echo "Error: not a git repo. /audit requires a tracked codebase."
    exit 1
}

# Surface config status (not blocking — defaults are sensible)
if [ -f compliance.config.json ]; then
    echo "Using compliance.config.json"
else
    echo "No compliance.config.json — running with defaults (GDPR on, HIPAA advisory, CCPA off)"
fi
```

## Arguments

- `--scope <path>` — limit the audit to a subdirectory (e.g., `--scope app/api`). Default: whole repo.
- `--regulation <name>` — limit to one regulation (`gdpr` | `hipaa` | `ccpa`). Default: all applicable.
- `--no-shadow-controls` — skip Pass C (shadow-controls scan). Useful when iterating quickly; the shadow-controls check involves cross-file analysis and is the most expensive pass.

## Workflow

### Invoke compliance-reviewer in audit mode

```
@compliance-reviewer --audit
```

The agent runs four passes against the whole codebase:

1. **Pass A — Missing-document audit.** Privacy policy, ToS, cookie notice, lawful-basis doc, sub-processor list, retention policy, medical disclaimer, age gate.
2. **Pass B — Missing-endpoint audit.** Account deletion, data export, data access, consent withdrawal, Sentry/error-tracker PII scrubber.
3. **Pass C — Shadow-controls audit.** Middleware/guard/policy code defined but not wired into any route (the false-confidence class).
4. **Pass D — Standing-config audit.** Sentry without `beforeSend`, cookies without `secure: true, sameSite`, hardcoded API key fallbacks in client code.

### Output

The agent writes to `docs/reviews/<stamp>-audit.md`. Format:

```markdown
# Compliance Audit — <project-name>

Date: YYYY-MM-DD
Mode: audit (whole-codebase scan)
Applicable regulations: GDPR | HIPAA-advisory | CCPA | ...
Files scanned: N

## Summary

| Pass | Findings |
|------|----------|
| A — Missing documents | 4 |
| B — Missing endpoints | 2 |
| C — Shadow controls | 1 |
| D — Standing config | 2 |

Total: 9 findings (3 HIGH, 5 MEDIUM, 1 LOW)

## Findings

[Per-pass sections with file:line references where applicable, and "searched: <paths>; found: nothing" for missing-document/endpoint findings]

## Recommended triage

The operator should review and decide which to file as P-numbered Backlog items:
- HIGH on launch-blocking docs (privacy policy, ToS, deletion endpoint) → file immediately
- MEDIUM → batch into a "compliance debt" Backlog item
- LOW → file only if specifically called out as needed
```

## What `/audit` does NOT do

- **Auto-file Backlog entries.** Audit reports typically surface 10-50 findings on existing codebases. Auto-filing would flood `Backlog.md`. Operator triages in one pass and files only what they intend to fix.
- **Halt or block ship.** `/audit` is a separate command from `/ship`. It produces a report; the operator decides how to act on it.
- **Run `security-reviewer` or `diagram-builder`.** Audit mode is compliance-specific. For security audits of the whole codebase, invoke `@security-reviewer` directly with explicit instructions to scan all routes. For diagram regeneration, invoke `@diagram-builder` directly.

## Failure modes handled gracefully

- **No `compliance-reviewer` installed.** Surface the install command pointing at ship-sop's `setup.sh`. Don't proceed with an empty audit.
- **Whole-codebase scan timeout.** Large repos may exceed model context limits in one pass. Suggest `--scope` to narrow focus, or run separate `/audit --regulation gdpr` then `/audit --regulation hipaa` to split across regulations.
- **No applicable regulations.** If `compliance.config.json` has all regulations off, audit produces only Pass C (shadow controls) and Pass D (standing config) findings. Surface a notice that the audit was narrow.
