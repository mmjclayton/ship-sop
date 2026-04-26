# ship-sop — Backlog

Single source of truth for all work items. Never delete without a trace — update in place, mark superseded, or archive.

## Tag Taxonomy

- Status (first): `[OPEN]`, `[IN PROGRESS]`, `[BLOCKED]`, `[DEFERRED]`, `[SHIPPED - YYYY-MM-DD]`, `[VERIFIED - YYYY-MM-DD]`, `[WON'T]`
- Type (second): `[Feature]`, `[Iteration]`, `[Bug]`, `[Refactor]`
- Optional: `[has-open-questions]`, `[ok-for-automation]`, `[needs-triage]`

**Tag rules:**
- Status first, type second. Never reverse.
- `[BLOCKED]` = waiting on an external action.
- `[DEFERRED]` = intentionally postponed with no external blocker.
- `[WON'T]` requires inline reason.
- `[VERIFIED]` means tested in production.
- `[needs-triage]` is the auto-file marker from `compliance-reviewer`.
- P-numbers are assigned sequentially, never reused, and do not imply priority.

## Item Sizing

Each item should be small enough to ship in a single PR with a single clear outcome. If the title or description needs "and" or multiple top-level bullets, split it into separate P-numbered items.

---

## P-Numbered Items

### P1 — Initial scaffold (3 reviewer agents, 4 slash commands, hook, config, setup)
`[SHIPPED - 2026-04-25] [Feature]`

Scaffold ship-sop as a companion library to agent-sop. Pre-merge quality pipeline runnable from a Claude Code session.

**Shipped contents:**
- `compliance-reviewer` — PII / GDPR / HIPAA-applicability scan; auto-files Backlog entries
- `diagram-builder` — Mermaid state + sequence diagrams, API endpoint catalog, ARCHITECTURE Δ log
- `release-notes-writer` — CHANGELOG entries + GitHub Release body from Backlog/BatchLog/commits
- `/ship` slash command — manual entrypoint to the four-gate pipeline
- `/release` slash command — always-manual tagged release
- `/ship-on`, `/ship-off` — config-mode toggles
- `scripts/auto-ship-hook.sh` — SessionStop hook with throttle (min diff, cooldown, branch patterns) and config-driven per-agent toggles
- `setup.sh` — installs into a target project with consent prompt for hook wiring
- `docs/templates/ship-sop.config.json` + `.schema.json` — config template + JSON schema
- `README.md`, `docs/ship-sop.md`, `LICENSE` (MIT)

**Commit:** `bd05f40`

---

### P2 — Dogfood self-install + post-install rough-edge fixes
`[SHIPPED - 2026-04-25] [Iteration]`

Run `setup.sh` against ship-sop's own repo as the dogfood test. Fix three rough edges surfaced by the install.

**Shipped contents:**
- Self-install detection: `setup.sh` now compares `SCRIPT_DIR == TARGET` and skips duplicate copies of project-side files (cleaner output for dogfood)
- Next-steps output: explicit instruction to commit `ship-sop.config.json` + `.claude/settings.json` + `.gitignore` after install
- Hook flow documented: `docs/ship-sop.md` "How the hook actually executes" subsection explaining the SessionStop → directive file → next-turn pattern

**Acceptance criteria met:**
- Three reviewer agents installed at `~/.claude/agents/`
- Four slash commands installed at `~/.claude/commands/`
- `.claude/settings.json` wired with the SessionStop hook (consent-prompted)
- `ship-sop.config.json` at the project root
- `.gitignore` excludes `.ship/`

**Commit:** `e82ccd5`

---

### P3 — End-to-end dogfood of the auto-mode pipeline + leftover-rename fix
`[SHIPPED - 2026-04-25] [Iteration]`

Manually fire the SessionStop hook against a real diff (Uninstall section added to README) and execute the gates inline. Validates the full flow end-to-end.

**What was tested:**
1. Hook detected 38-line diff (above 10-line throttle) ✓
2. Hook resolved diff range correctly ✓
3. Hook wrote `.ship/.pending-auto-fire.md` directive listing the three enabled gates ✓
4. Hook stamped `.last-auto-fire` and `.last-diff-hash` for cooldown/dedup ✓
5. Hook emitted next-turn context message ✓
6. Acted as next-turn model: ran security, compliance, diagram-builder gates inline against the diff ✓
7. All three gates returned APPROVE; tests skipped (no runner) ✓
8. Per-gate review files + consolidated `ship-auto.md` written to `docs/reviews/` ✓

**Bug fix:** the directive header still said "Ship-pipeline auto-mode" — leftover string from the pre-rename codebase. Now reads "ship-sop auto-mode".

**Commits:** `7db908e` (Uninstall README section), `31f984e` (test artifacts + leftover-rename fix)

---

### P4 — Docs-only detection in the SessionStop hook
`[SHIPPED - 2026-04-25] [Bug]`

Mirror `/ship`'s docs-only behaviour in `scripts/auto-ship-hook.sh`. Previously the hook ran every enabled agent regardless of diff content — security and compliance gates fired on README-only changes and reliably returned APPROVE, producing noise.

**What changed:**
- Docs-only detection added: scans every changed file against `^docs/`, `\.(md|mdx)$`, `^README`. If all files match, sets `DOCS_ONLY=true`.
- Agent filter: when `DOCS_ONLY=true`, the directive includes only advisory gates (`block_on: "never"`). Hard-blocking gates skip cleanly. Config-driven, no hardcoded names.
- Directive annotation: `Mode: docs-only (hard-blocking gates skipped — only advisory gates listed below)` line appears at the top when docs-only mode is active.

**Acceptance criteria met:**
- 10-line README-only commit triggers the hook
- Directive correctly lists only `@diagram-builder`
- Docs-only banner appears at the top of the directive
- Mixed-file diffs continue to list all enabled agents

**Commit:** `bc2e9d7`

---

### P5 — Install agent-sop on ship-sop for retrospective record
`[SHIPPED - 2026-04-25] [Feature]`

Install agent-sop into ship-sop with the base template. Backfill CLAUDE.md, Backlog.md, feature-map.md, decisions, gotchas, build plan, and recent-work entry to capture what already shipped (P1-P4). Not for driving new work — for recording the history that surfaced during the initial scaffold + dogfood session.

**Shipped contents:**
- agent-sop file set: `CLAUDE.md`, `Backlog.md`, `docs/agent-memory.md`, `docs/feature-map.md`, `docs/build-plans/phase-0-foundation.md`, `docs/sop/*`, `docs/guides/*`, `docs/templates/review-template.md`
- Backfilled this Backlog with P1-P5 retroactive items (this entry being P5)
- Decisions captured under `docs/agent-memory/decisions/`
- Gotchas captured under `docs/agent-memory/gotchas/`
- Phase 0 build plan with retrospective Batch Log
- Recent-work entry summarising 2026-04-25 session

**Why retrospective:** ship-sop is at "released, working, no immediate roadmap." agent-sop's primary value is across sessions on active work, but its secondary value is durable record of what was decided and why — that record is worth capturing now, while the context is fresh.

---

### P6 — Multi-tenant isolation section in compliance-reviewer + lawful-basis severity bump
`[SHIPPED - 2026-04-25] [Feature]`

Surfaced by hst-tracker's full code review (2026-04-25). The review caught three IDORs (cross-tenant data leakage) that fell into a gap between security-reviewer (generic auth bypass only) and compliance-reviewer (PII-in-logs only). Plus, lawful-basis was graded LOW in the checklist but the review treats it as launch-blocking — calibration data says it should be MEDIUM.

**Acceptance criteria:**
- compliance-reviewer has a "Multi-tenant isolation scan" section with concrete patterns:
  - User-scoped routes that don't filter `findMany`/`findFirst`/`update`/`delete` by `session.user_id` or equivalent
  - Mutations that take a resource ID from `req.params` or `req.body` without verifying ownership
  - `prisma.<model>.update({ where: { id } })` without a user-scoped `where` clause
- Severity calibrated: missing ownership checks on user-scoped writes → CRITICAL; missing on reads → HIGH
- Lawful-basis check bumped from LOW to MEDIUM
- Self-test: read the new section against a synthetic IDOR pattern and confirm it would flag

**Out of scope:**
- Whole-codebase isolation audit (covered by P7's audit mode)
- Modifications to security-reviewer (not ship-sop's agent)

---

### P7 — /audit command + whole-codebase mode in compliance-reviewer
`[SHIPPED - 2026-04-25] [Feature]`

Surfaced by hst-tracker's full code review (2026-04-25). Three of the launch blockers (no privacy policy doc anywhere, no data-export endpoint anywhere, no lawful-basis doc) are *standing gaps* — the absence of files or routes that diff-bound compliance-reviewer can't detect because they predate the gate's installation.

Without `/audit`, ship-sop is effectively useless on existing codebases — it only protects forward-going changes from new gaps, never catches accumulated debt.

**Acceptance criteria:**
- New `/audit` slash command that invokes compliance-reviewer in whole-codebase mode (not diff-bound)
- compliance-reviewer's prompt has explicit "audit mode" instructions: scan the whole repo, not the diff; check for *absence* of expected files/routes; report standing gaps
- Audit mode includes a shadow-controls check: middleware/guard/policy code defined but not wired into any route (the C6 finding from hst-tracker)
- Output: `docs/reviews/<stamp>-audit.md` with sections for missing-documents, missing-endpoints, shadow-controls, standing-gaps
- Audit report doesn't auto-file Backlog entries — operator triages findings in one pass (audit findings are typically large in number; auto-filing would flood the Backlog)
- README and docs/ship-sop.md mention the new command and when to use it (launch-readiness milestones, monthly compliance reviews, post-acquisition due-diligence pass)

**Out of scope:**
- Audit mode for security-reviewer or diagram-builder (compliance is the canonical use case for whole-codebase audits)
- App Store / store-policy compliance (separate scope; punt until a second example surfaces)

---

### P8 — App Store / store-policy compliance gate (`store-policy-reviewer` agent)
`[DEFERRED] [Feature]`

A `store-policy-reviewer` agent that flags App Store Review Guidelines / Google Play Policy concerns: medical disclaimer absence (App Review Guideline 1.4.1), Sign in with Apple required when third-party login present, privacy nutrition manifest, age rating accuracy, missing in-app purchase / subscription disclosure for billing flows, etc.

**Why deferred:** one example (hst-tracker C12 medical disclaimer) is not enough evidence to justify a new agent. Compliance regulations (GDPR, HIPAA, CCPA) are universal across most products; App Store / Play Store policies are mobile-specific and vary by app category. Building a generic store-policy reviewer requires more samples to know which checks generalise vs. which are app-specific noise.

**Trigger condition:** revive when a *second* example surfaces — either:
- A second project in flight that needs App Store review, OR
- A user explicitly requests this gate, OR
- A clear pattern emerges across reviewed projects (e.g., 3+ shipped products that hit the same store-policy gap)

**What it would look like (if revived):**
- New agent at `.claude/agents/store-policy-reviewer.md`
- New entry in `ship-sop.config.json` agents block, `block_on: "never"` (advisory only — store policies change frequently and false positives are common)
- Detection patterns: scan `app.json` / `Info.plist` / `AndroidManifest.xml` for missing privacy keys; grep for unhandled medical/financial/legal language without disclaimer; check for Sign in with Apple when other social login providers are present; verify privacy nutrition manifest matches actual data collection
- Likely runs in a separate gate from the diff-bound four-gate pipeline, since most store-policy issues are standing gaps (audit-mode candidate)

**Out of scope when revived:**
- App-specific UX critique (that's `pm-reviewer`'s lane if/when it's built)
- Marketing-claim review (over-promise, FDA disclaimer language for health apps) — separate scope

---

### P9 — Default reviewer set expansion (code-reviewer + silent-failure-hunter + pr-test-analyzer)
`[SHIPPED - 2026-04-25] [Feature]`

The Phase 0 default config (`security-reviewer`, `compliance-reviewer`, `diagram-builder`) covers vulnerabilities, privacy/compliance, and ship-time docs but leaves three signal gaps that any project benefits from: general code quality, silent-failure detection, and test-coverage analysis. All three reviewers are language-agnostic, so they're appropriate for the *default* template (every fresh install gets them) — language-specific reviewers (`typescript-reviewer`, `python-reviewer`, etc.) stay per-project.

**Shipped contents:**
- `code-reviewer` added to default config — `block_on: HIGH`. Catches function/file size, missing error handling, dead code, missing tests. CRITICAL-class is already covered by `security-reviewer`; HIGH is the right severity here.
- `silent-failure-hunter` added — `block_on: HIGH`. Single-purpose: empty catches, `.catch(() => [])`, swallowed errors, lost stack traces. Different signal class from `code-reviewer`'s broader sweep.
- `pr-test-analyzer` added — `block_on: never`, `auto_file_backlog: false`. Advisory test-coverage quality signal; runs cheaply and silently to avoid Backlog churn on small interim diffs.
- README's "Common extensions" section documents the per-project pattern (language reviewers, database-reviewer, performance-optimizer).
- Both `docs/templates/ship-sop.config.json` (template) and `ship-sop.config.json` (dogfood) updated.
- `docs/ship-sop.md` gates table and example config updated to match.

**Decision file:** `docs/agent-memory/decisions/2026-04-25_solo_default-reviewer-set-expansion.md`

**Why HIGH for code-reviewer and silent-failure-hunter:** CRITICAL territory in the Claude Code agent ecosystem is mostly security-class (auth bypass, secret exposure, SQL injection) — `security-reviewer` owns that. Code-quality and silent-failure findings are typically HIGH-class (real bugs, but bounded blast radius). Setting `block_on: HIGH` makes both gates loud without forcing them to compete with `security-reviewer` for the CRITICAL bar.

**Why advisory for pr-test-analyzer:** test-coverage gaps are legitimate (refactors, doc-only changes, interim WIP commits). Hard-blocking on coverage drift would create false-positive friction without catching real bugs. Running it `block_on: never` + `auto_file_backlog: false` keeps the signal in the readiness summary without polluting the Backlog.

---

### P10 — `setup.sh --uninstall` for clean removal
`[SHIPPED - 2026-04-26] [Feature]`

`setup.sh` could install ship-sop but couldn't reverse it. The README documented the manual `rm` procedure across three scopes, but it was easy to leave fragments behind — particularly the `.gitignore` block, the SessionStop hook entry in `.claude/settings.json`, and the `audit.md` command (which the manual list didn't include after P7).

Lowers the barrier to trying ship-sop on a project: you can install with confidence that one command reverses every install step.

**Shipped contents:**
- `setup.sh` parses `--uninstall`, `--keep-config`, `--keep-artifacts`. Existing `--force` flag is reused for "remove locally-modified files".
- New `uninstall_mode()` function: removes user-scope agents and commands, project-scope hook script, schema template, config file, `.ship/` directory; updates `.gitignore` (removes the two-line block) and `.claude/settings.json` (removes the Stop hook entry via jq).
- Hash-based safety: by default, user-scope agents and commands whose content differs from source are skipped with a "locally modified" notice. `--force` removes them regardless. Mirrors the existing install-time behaviour where modifications are respected unless `--force` is passed.
- Self-install detection (`SCRIPT_DIR == TARGET`) skips project-side file removal — same logic the install path uses.
- `docs/reviews/`, `docs/agent-memory/`, `docs/diagrams/`, `docs/api/`, `docs/ARCHITECTURE.md` are never auto-removed (audit trail / generated docs the operator may want to keep).
- Install Next-Steps text and README Uninstall section both updated. README now leads with `--uninstall` as the canonical path; manual `rm` procedure preserved as a fallback.
- Drive-by fix: install Next-Steps and manual-uninstall list both included `audit.md` (the P7 command) which they'd been missing.

**Acceptance criteria met:**
- Running `./setup.sh /path --uninstall` removes every file `./setup.sh /path` adds, by default
- Locally-modified user-scope agents are skipped without `--force`
- `--keep-config` preserves `ship-sop.config.json` for reinstall
- `--keep-artifacts` preserves `.ship/`
- Self-install (`SCRIPT_DIR == TARGET`) skips project-side removal
- Manual dogfood: install + uninstall against a throwaway directory leaves zero ship-sop files behind, plus `.gitignore` and `.claude/settings.json` are restored to their pre-install state
- README documents the new flag set; manual fallback retained

**Why this earned a P-number now:** it was a "Likely-soon" candidate in `feature-map.md` for adoption ergonomics. Building it before ship-sop has many adopters keeps the install/uninstall round-trip clean from the first user.

**Out of scope:**
- A dry-run mode (`--uninstall --dry-run`). Could be added if false-positive removal becomes a real concern; not built speculatively.
- Logging the removed-file list to `docs/reviews/`. Uninstall is a teardown event, not a review event.

---

## Shipped Archive

*Items below are shipped or verified. Never removed. Move items here when Backlog.md exceeds ~2,000 lines and items are older than 90 days.*

(Empty — all P-numbered items above are still in the recent block.)
