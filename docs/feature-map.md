# ship-sop — Feature Map & Roadmap

Last updated: 2026-08-03 (P15)

---

## Shipped Features

| P# | Feature | Path/PR | Shipped |
|----|---------|---------|---------|
| P1 | `compliance-reviewer` agent (PII / GDPR / HIPAA-applicability) | `.claude/agents/compliance-reviewer.md` | 2026-04-25 (`bd05f40`) |
| P1 | `diagram-builder` agent (Mermaid + API catalog + ARCHITECTURE Δ) | `.claude/agents/diagram-builder.md` | 2026-04-25 (`bd05f40`) |
| P1 | `release-notes-writer` agent | `.claude/agents/release-notes-writer.md` | 2026-04-25 (`bd05f40`) |
| P1 | `/ship` slash command | `.claude/commands/ship.md` | 2026-04-25 (`bd05f40`) |
| P1 | `/release` slash command | `.claude/commands/release.md` | 2026-04-25 (`bd05f40`) |
| P1 | `/ship-on` and `/ship-off` toggles | `.claude/commands/ship-{on,off}.md` | 2026-04-25 (`bd05f40`) |
| P1 | SessionStop hook script | `scripts/auto-ship-hook.sh` | 2026-04-25 (`bd05f40`) |
| P1 | Setup installer with consent prompt | `setup.sh` | 2026-04-25 (`bd05f40`) |
| P1 | Default config + JSON schema | `docs/templates/ship-sop.{config,schema}.json` | 2026-04-25 (`bd05f40`) |
| P1 | Public README + spec doc + LICENSE | `README.md`, `docs/ship-sop.md`, `LICENSE` | 2026-04-25 (`bd05f40`) |
| P2 | Self-install detection + commit-the-artifacts next-step | `setup.sh` | 2026-04-25 (`e82ccd5`) |
| P2 | Hook flow documented (next-turn pattern) | `docs/ship-sop.md` | 2026-04-25 (`e82ccd5`) |
| P3 | README Uninstall section | `README.md` | 2026-04-25 (`7db908e`) |
| P3 | End-to-end dogfood of auto-mode | `docs/reviews/20260425-154239-*.md` | 2026-04-25 (`31f984e`) |
| P3 | Leftover-rename fix in directive header | `scripts/auto-ship-hook.sh` | 2026-04-25 (`31f984e`) |
| P4 | Docs-only detection in hook | `scripts/auto-ship-hook.sh` | 2026-04-25 (`bc2e9d7`) |
| P5 | agent-sop install (retrospective record) | `CLAUDE.md`, `Backlog.md`, `docs/agent-memory*` | 2026-04-25 |
| P6 | Multi-tenant isolation scan in compliance-reviewer | `.claude/agents/compliance-reviewer.md` (Section 7) | 2026-04-25 (`3b679e0`) |
| P6 | Lawful-basis severity bump LOW → MEDIUM | `.claude/agents/compliance-reviewer.md` (GDPR rights scan) | 2026-04-25 (`3b679e0`) |
| P7 | `/audit` slash command (whole-codebase compliance audit) | `.claude/commands/audit.md` | 2026-04-25 |
| P7 | Audit-mode workflow in compliance-reviewer (Pass A-D) | `.claude/agents/compliance-reviewer.md` (Audit Mode Workflow) | 2026-04-25 |
| P7 | Phase 1 build plan | `docs/build-plans/phase-1-audit-mode.md` | 2026-04-25 |
| P9 | `code-reviewer` added to default reviewer set | `docs/templates/ship-sop.config.json` (+ dogfood `ship-sop.config.json`) | 2026-04-25 |
| P9 | `silent-failure-hunter` added to default reviewer set | `docs/templates/ship-sop.config.json` (+ dogfood `ship-sop.config.json`) | 2026-04-25 |
| P9 | `pr-test-analyzer` added to default reviewer set (advisory) | `docs/templates/ship-sop.config.json` (+ dogfood `ship-sop.config.json`) | 2026-04-25 |
| P9 | "Common extensions" section (language reviewers + stack-specific table) | `README.md` | 2026-04-25 |
| P9 | Code-review artifact + 3 LOW findings addressed inline | `docs/reviews/2026-04-25_solo_P9.md` | 2026-04-25 |
| P10 | `setup.sh --uninstall` (with `--keep-config`, `--keep-artifacts`, hash-based modification check) | `setup.sh` | 2026-04-26 |
| P10 | README Uninstall section rewritten — `--uninstall` is canonical, manual `rm` fallback retained | `README.md` | 2026-04-26 |
| P10 | Drive-by fix: install Next-Steps + manual-uninstall lists now include `audit.md` | `setup.sh`, `README.md` | 2026-04-26 |
| P11 | `SHIP_SOP_DEBUG=1` env var: stderr diagnostics on every silent-exit path in the SessionStop hook | `scripts/auto-ship-hook.sh` | 2026-05-02 |
| P11 | Config schema sanity check: warn on unknown keys at hook load (catches `enabld`-style typos) | `scripts/auto-ship-hook.sh` | 2026-05-02 |
| P11 | Opt-in artifact retention: `artifacts.retain_ship_artifact_days` (precise digit-count glob preserves agent-sop's `YYYY-MM-DD_*.md` reviews) | `scripts/auto-ship-hook.sh`, `docs/templates/ship-sop.{config,schema}.json` | 2026-05-02 |
| P11 | Hook edge fixes: `sha256sum` fallback, tightened docs-only regex, cached `git diff` | `scripts/auto-ship-hook.sh` | 2026-05-02 |
| P11 | CLAUDE.md drift fixed: rollup refreshed (now includes P10), stale "future candidates" list removed | `CLAUDE.md` | 2026-05-02 |
| P11 | `docs/ship-sop.md` folded into README; original file replaced with redirect stub | `README.md`, `docs/ship-sop.md` | 2026-05-02 |
| P11 | README uninstall fallback wrapped in `<details>`; `/audit` added to quick start; new troubleshooting section | `README.md` | 2026-05-02 |
| P11 | `setup.sh prompt_yn()` non-interactive timeout (`read -t 30` with default fallthrough) | `setup.sh` | 2026-05-02 |
| P11 | `docs/README.md` orientation note (ship-sop surface vs agent-sop pristine replicas vs SOP-generated history) | `docs/README.md` | 2026-05-02 |
| P11 | P10 retroactive `docs/recent-work/` entry filed; rollup re-runs cleanly | `docs/recent-work/2026-04-26_solo_p10-uninstall.md` | 2026-05-02 |
| P14 | SessionStop hook wired in the nested shape Claude Code actually executes — auto-mode fires for the first time since P1 | `setup.sh`, `.claude/settings.json` | 2026-08-03 |
| P14 | Shared hook selectors (`HOOK_NESTED_PROBE`, `HOOK_LEGACY_PROBE`, `HOOK_ENTRY_EXAMPLE`) so install and uninstall cannot drift apart | `setup.sh` | 2026-08-03 |
| P14 | In-place migration of pre-P14 flat hook entries; uninstall removes both shapes and preserves other hooks | `setup.sh`, `README.md` | 2026-08-03 |
| P14 | Post-install assertion hard-fails on an unparseable hook entry instead of reporting success | `setup.sh` | 2026-08-03 |
| P15 | Uninstall no longer eats the first user `.gitignore` line after the ship-sop block | `setup.sh`, `README.md` | 2026-08-03 |
| P15 | `pwd -P` + `-ef` source guard: a symlinked clone can no longer delete ship-sop's own files | `setup.sh` | 2026-08-03 |
| P15 | `/ship-on` hook check is read-only; the destructive wiring snippet removed | `.claude/commands/ship-on.md` | 2026-08-03 |
| P15 | First CI: shellcheck + `bash -n` + JSON validation + P14 nested-shape regression guard | `.github/workflows/ci.yml` | 2026-08-03 |

> P12 and P13 are absent from this table — tracker drift filed as P23, not backfilled here to keep this batch's diff to its own item.

---

## Awaiting merge

P28 adds Codex installation, native skills, isolated reviewers and shared automatic
hook policy on `feat/codex-support`. See `Backlog.md` for review and merge status.

## Roadmap

ship-sop is at "released, working, no immediate roadmap." Items below are likely-soon candidates that haven't been filed as P-numbers yet.

### Likely-soon

| Candidate | Notes |
|-----------|-------|
| `/release` end-to-end dogfood | Cut a real GitHub Release on ship-sop using the agent. Validates `release-notes-writer` against actual Backlog + commits. |
| CI workflow for the gates | Run security + compliance + diagrams without a Claude Code session. Useful for PRs from contributors who don't run Claude. |
| Composition test with agent-sop | Verify that with both installed, `compliance-reviewer` auto-files Backlog entries with proper P-numbers (documented, not tested). |

### Not on the table

| Item | Why not |
|------|---------|
| `intent-reviewer` agent | Dropped from initial scope (2026-04-25). Revisit if clearly missing in practice. |
| `pm-reviewer` agent | Dropped from initial scope (2026-04-25). |
| Auto-publish on `/release` | Releases stay deliberate. For pre-push automation, use GitHub Actions on tag push. |
| `doc-builder` (codemaps + INDEX) | Renamed to `diagram-builder` and trimmed to avoid overlap with `doc-updater`. |
| `auto-ship-hook.sh` as the auto-mode trigger (P1, P2, P11, P14 rows above) | Superseded 2026-09-04 by agent-sop P97: project-scope hooks never load for a home-launched session and Stop stdout never reaches the model, so the next-turn directive pattern could not fire live. Trigger is now agent-sop's user-scope `sop-stop-drift.sh` + `sop-push-gate.sh`. Retirement of the wiring is P25. |
