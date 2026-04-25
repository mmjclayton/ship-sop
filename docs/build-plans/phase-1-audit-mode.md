# Phase 1 — Audit Mode + Isolation Checks

Status: Shipped 2026-04-25

---

## Problem

ship-sop's pipeline (Phase 0) is diff-bound by design — every gate reviews `BASE..HEAD`, not the whole codebase. That's the right shape for per-ship gates, but it has a blind spot: ship-sop installed on an *existing* codebase only protects forward-going changes. It can't see *standing* gaps that predate the install:

- Privacy policy file doesn't exist anywhere in the repo
- No `/users/me/export` endpoint anywhere (GDPR Art. 20 right-to-portability)
- No account-deletion endpoint anywhere (GDPR Art. 17 right-to-erasure)
- Lawful-basis documentation absent
- Middleware named like a security control (e.g., `attachDataIsolation`) defined but not wired to any route — a "shadow control" that creates false confidence

Plus: cross-tenant data leakage (IDORs) sits in a gap between `security-reviewer` (generic auth bypass only) and `compliance-reviewer` (PII-in-logs only).

Real-world evidence: hst-tracker's full code review (2026-04-25) surfaced 14 launch blockers. Three of them (C8 missing privacy policy, C10 lawful-basis, C11 data export) are standing-gap class. Three more (C1-C3 IDORs in routes/logger.js) are isolation-class. ship-sop's Phase 0 gates would have caught none of these.

Phase 1 closes both gaps.

---

## Scope

| Batch | What | Priority |
|-------|------|----------|
| 1.1 | P6: Multi-tenant isolation section in compliance-reviewer + lawful-basis severity bump | P0 |
| 1.2 | P7: `/audit` command + whole-codebase mode + shadow-controls check | P0 |

---

## Architecture

**compliance-reviewer takes a mode flag.**

| Mode | Trigger | Scope | Output |
|------|---------|-------|--------|
| Diff (default) | `/ship` or SessionStop hook | `BASE..HEAD` | `docs/reviews/<stamp>-compliance.md` + Backlog auto-file |
| Audit | `/audit` | Whole codebase | `docs/reviews/<stamp>-audit.md`, no auto-file |

**Audit mode is four passes.** Each addresses a distinct kind of standing gap:

- **Pass A — Missing-document audit.** Walks expected paths (`docs/privacy/`, `PRIVACY.md`, `app/(legal)/`) and flags absences. Severities adapt to applicability — GDPR-on raises privacy-policy and lawful-basis to HIGH/MEDIUM; HIPAA-applicability triggers escalate medical-disclaimer to HIGH.
- **Pass B — Missing-endpoint audit.** Greps route definitions for account-delete, data-export, data-access, consent-withdrawal, Sentry-scrubber. Reports absences.
- **Pass C — Shadow-controls audit.** Find files matching `*middleware*|*guard*|*policy*|*auth*|*protect*`, identify exports, grep the codebase for usage, flag exports with zero usages as HIGH-severity false-confidence.
- **Pass D — Standing-config audit.** Sentry init without `beforeSend`, cookie middleware without `secure: true, sameSite`, hardcoded API-key fallbacks in client-side files.

**Isolation scan in compliance-reviewer (P6).** A new section (7) detecting unscoped queries, missing-ownership mutations, IDOR shape (findUnique + update without scope), foreign-key writes without parent-ownership checks, bulk operations without user-id `where`, admin routes without role checks, repository helpers hiding missing scope. Severity calibrated: writes without scope → CRITICAL; reads without scope → HIGH. False-positive guards exclude public routes, aggregate counts, and parent-scoped includes.

---

## Key Decisions Locked In

- **[LOCKED]** Audit mode does not auto-file Backlog entries. Reports typically surface 10-50 findings on existing codebases; auto-filing would flood the Backlog. Operator triages.
- **[LOCKED]** `/audit` is a separate command from `/ship`, not a flag on `/ship`. Different cadence (monthly / launch-readiness vs. every-session), different audience (compliance reviewer vs. shipper), different output format (audit report vs. ship readiness).
- **[LOCKED]** Audit mode runs only `compliance-reviewer`, not `security-reviewer` or `diagram-builder`. Whole-codebase compliance audits are the canonical use case for audit mode; security and diagrams have other invocation paths.
- **[LOCKED]** Shadow-controls check is in compliance-reviewer's Pass C, not a standalone agent. The detection is privacy/compliance-class (false security confidence is a privacy-class harm).
- **[LOCKED]** App Store / store-policy gate (the natural P8 candidate) is deferred. One example (hst-tracker C12 medical disclaimer) is not enough evidence. Revisit if a second example surfaces.
- **[LOCKED]** Multi-tenant isolation lives in compliance-reviewer, not as a standalone `isolation-reviewer` agent. Cross-tenant data leakage is privacy-class; routing it through compliance-reviewer keeps the agent count down without sacrificing detection.

---

## Batch Log

- **2026-04-25: Batch 1.1 shipped — `3b679e0 feat(P6): multi-tenant isolation scan + lawful-basis severity bump`.** Section 7 added to compliance-reviewer (~50 lines) covering unscoped queries, IDOR patterns, admin-route checks, repository-helper traps, and admin-typo class (MRV-ceiling style). Lawful-basis check bumped LOW → MEDIUM. False-positive guards documented.
- **2026-04-25: Batch 1.2 shipped — this commit.** `/audit` slash command (~110 lines), audit-mode workflow added to compliance-reviewer (~150 lines covering Pass A through Pass D + output format). Phase-1 build plan, decision file, recent-work entry, feature-map updated.

---

## Deploy Checklist

- [x] compliance-reviewer.md has Section 7 (Multi-tenant isolation scan)
- [x] compliance-reviewer.md has audit-mode workflow (Pass A-D + output format)
- [x] `/audit` slash command exists at `.claude/commands/audit.md`
- [x] Backlog updated (P6 SHIPPED, P7 SHIPPED with commit refs)
- [x] feature-map.md has rows for P6 and P7
- [x] Decision file at `docs/agent-memory/decisions/2026-04-25_solo_audit-mode-not-diff-bound.md`
- [x] Recent-work entry at `docs/recent-work/2026-04-25_solo_p6-p7-audit-mode-and-isolation.md`
- [x] CLAUDE.md rollup refreshed via `bash scripts/refresh-rollup.sh`
- [x] Pushed to origin

---

## Open Questions

- Should `/audit` be added as a fifth gate to `/ship` (auto-runnable), or stay manual-only? [RESOLVED - 2026-04-25: stay manual-only. Auto-running an audit on every session-end would re-find the same standing gaps repeatedly until they're fixed. Cadence is monthly / at-launch, not per-session.]
- Should audit mode ever auto-file Backlog entries? [UNRESOLVED — possibly worth a `/audit --file-as P-prefix` flag in the future for operators who do want one-shot Backlog seeding from a fresh audit. Defer until requested.]
- Should there be a project-specific config for audit mode (e.g., paths to ignore, custom missing-document checks)? [UNRESOLVED — current `compliance.config.json` covers regulation toggles. Audit-mode-specific config can be added if patterns emerge from real use.]
