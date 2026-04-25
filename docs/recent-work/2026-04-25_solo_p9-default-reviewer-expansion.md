# P9: Default reviewer set expansion (code-reviewer + silent-failure-hunter + pr-test-analyzer)

**Date:** 2026-04-25
**Agent:** solo

Triggered by hst-tracker's manual config tuning earlier in the day: hst-tracker added `typescript-reviewer` (HIGH) and `pr-test-analyzer` (advisory) to its `ship-sop.config.json`, plus pinned five reviewer agents into `.claude/agents/`. The TS-specific addition is right *for hst-tracker* but wrong for the default template (ship-sop installs onto Python, Go, Rust, etc. too). The underlying instinct — that the default set is too narrow — generalises.

P9 promotes the language-agnostic subset of that instinct into `docs/templates/ship-sop.config.json`:

- `code-reviewer` (block_on: HIGH) — language-agnostic quality, error handling, dead code. CRITICAL is `security-reviewer`'s territory; HIGH is the right severity for quality findings.
- `silent-failure-hunter` (block_on: HIGH) — single-purpose: empty catches, `.catch(() => [])`, swallowed errors. Different signal class from `code-reviewer`. HIGH because silent failures corrupt data invisibly.
- `pr-test-analyzer` (block_on: never, auto_file_backlog: false) — advisory test-coverage signal. Silent on Backlog so interim ships don't pollute it.

The default set goes from 3 reviewer gates to 6 (plus tests = 7 ship-time gates). All language-agnostic. Language-specific reviewers (`typescript-reviewer` et al.) stay per-project — README has a new "Common extensions" section showing the pattern.

Touched: `docs/templates/ship-sop.config.json` (template), `ship-sop.config.json` (dogfood), `README.md` (gates table + example + extensions section), `docs/ship-sop.md` (gates table + example), `Backlog.md` (P9), `docs/feature-map.md`, `docs/agent-memory/decisions/2026-04-25_solo_default-reviewer-set-expansion.md`.

JSON schema unchanged — `additionalProperties` already permits arbitrary agent keys, and `scripts/auto-ship-hook.sh` iterates `.agents` dynamically (verified at lines 182, 184, 221 of the hook).

No phase plan created — single P-number, narrow scope. Phase 0 (foundation) and Phase 1 (audit mode) remain the canonical phase set; P9 is a Phase-0 follow-up rather than a new phase.

## Open follow-ups

- A second project to dogfood the new defaults on. hst-tracker is already overridden with TS-specific reviewers; need a Python or Go project to confirm the new set fires cleanly without language-specific noise.
- Consider whether `code-reviewer` and `security-reviewer` produce overlapping findings on the same diff (CRITICAL security findings should be reported by `security-reviewer` only; `code-reviewer`'s checklist *also* includes a Security section). If overlap is high in practice, could narrow `code-reviewer`'s scope or document the convention that security findings dedupe to `security-reviewer`.
