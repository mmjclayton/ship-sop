# P6-P7: Multi-tenant isolation scan + /audit command + whole-codebase mode

**Date:** 2026-04-25
**Agent:** solo
**Commits:** `3b679e0` (P6), plus this commit (P7)

First non-retrospective work for ship-sop, surfaced by hst-tracker's full code review (2026-04-25). The review caught 14 launch blockers; six were directly relevant to ship-sop's coverage gaps — three IDORs (cross-tenant data leakage) and three standing gaps (no privacy policy, no data-export endpoint, lawful-basis docs absent).

P6 added Section 7 (Multi-tenant isolation scan) to compliance-reviewer covering unscoped queries, missing-ownership mutations, IDOR shape (findUnique + update without scope on either call), foreign-key writes without parent-ownership checks, bulk operations without user-id `where`, admin routes without role checks, and repository helpers hiding missing scope. Severity calibrated: writes without scope → CRITICAL; reads without scope → HIGH. False-positive guards documented to skip public routes, aggregate counts, and parent-scoped includes. Also bumped lawful-basis severity from LOW to MEDIUM based on real-world launch-readiness calibration.

P7 added the `/audit` slash command and audit-mode workflow to compliance-reviewer. compliance-reviewer now runs in two modes — **diff** (default, per-ship, what `/ship` invokes) and **audit** (whole-codebase, what `/audit` invokes). Audit mode runs four passes: Pass A (missing documents — privacy policy, ToS, lawful-basis, sub-processors, retention, medical disclaimer, age gate), Pass B (missing endpoints — account deletion, data export, data access, consent withdrawal, Sentry scrubber), Pass C (shadow controls — middleware/guard/policy code defined but not wired to any route, the C6 false-confidence class), Pass D (standing config — Sentry without `beforeSend`, cookies without `secure`, hardcoded API-key fallbacks in client). Audit mode does not auto-file Backlog entries; reports typically surface 10-50 findings on existing codebases and operator triages in one pass.

Without audit mode, ship-sop was effectively useless on existing codebases — diff-bound gates can't see standing gaps. P7 closes that — ship-sop now catches accumulated debt as well as new bugs.

Phase 1 build plan and decision file written. App Store / store-policy gate considered as P8 candidate but deferred: one example (hst-tracker C12 medical disclaimer) is not enough evidence to justify a new agent.
