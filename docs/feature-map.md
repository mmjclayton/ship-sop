# ship-sop — Feature Map & Roadmap

Last updated: 2026-04-25

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

---

## Roadmap

ship-sop is at "released, working, no immediate roadmap." Items below are likely-soon candidates that haven't been filed as P-numbers yet.

### Likely-soon

| Candidate | Notes |
|-----------|-------|
| `/release` end-to-end dogfood | Cut a real GitHub Release on ship-sop using the agent. Validates `release-notes-writer` against actual Backlog + commits. |
| CI workflow for the gates | Run security + compliance + diagrams without a Claude Code session. Useful for PRs from contributors who don't run Claude. |
| `setup.sh --uninstall` | The README documents manual uninstall. An automated path would be friendlier. |
| Composition test with agent-sop | Verify that with both installed, `compliance-reviewer` auto-files Backlog entries with proper P-numbers (documented, not tested). |

### Not on the table

| Item | Why not |
|------|---------|
| `intent-reviewer` agent | Dropped from initial scope (2026-04-25). Revisit if clearly missing in practice. |
| `pm-reviewer` agent | Dropped from initial scope (2026-04-25). |
| Auto-publish on `/release` | Releases stay deliberate. For pre-push automation, use GitHub Actions on tag push. |
| `doc-builder` (codemaps + INDEX) | Renamed to `diagram-builder` and trimmed to avoid overlap with `doc-updater`. |
