# Phase 2 — Hardening pass

**Status:** Shipped 2026-05-02 (P11)
**Trigger:** Whole-repo review against ship-sop's stated purpose. User requested an objective audit that would optimise, declutter, improve performance, and harden usefulness.

---

## Scope

A maintenance pass on ship-sop's own surface. Phase 0 was the initial scaffold, Phase 1 was audit-mode + isolation. Phase 2 closes UX gaps that emerged from a fresh re-read against purpose:

- Hook silent-exit paths give users no signal when auto-mode "doesn't seem to fire."
- Config typos (e.g. `enabld: true`) silently disable gates with no warning.
- `docs/reviews/` accumulates ship-sop gate artifacts forever; no retention.
- `CLAUDE.md` rollup drift (P9 last-shown despite P10 shipped).
- `docs/ship-sop.md` and README duplicated the spec; drift inevitable across two docs.
- `setup.sh` `read -r` blocks non-interactive shells indefinitely.

---

## Locked decisions

- **[LOCKED]** Source-tree "clutter" (the dated `docs/recent-work`, `docs/agent-memory/{decisions,gotchas}/`, `docs/build-plans/`, `docs/reviews/` files) stays where it is. These directories are normative in upstream agent-sop's slash commands (`/update-sop`, `/restart-sop`, `/migrate-to-multi-agent`) and SHA-tracked in `.claude/agent-sop.config.json`. Moving them would break every consumer (ship-sop, hst-tracker, future projects). The "clutter" is the SOP working as designed.

- **[LOCKED]** Retention prune scope is strictly ship-sop's `YYYYMMDD-HHMMSS-*.md` filename format. Agent-sop's permanent `YYYY-MM-DD_<agent-id>_P<n>.md` review artifacts are protected by a precise digit-count glob — `[0-9]{8}-[0-9]{6}-*.md` instead of the loose `[0-9]*-[0-9]*-*.md` (which would also match agent-sop's format because `*` in shell globs spans hyphens). Verified empirically against synthetic fixtures.

- **[LOCKED]** `docs/ship-sop.md` is replaced with a one-paragraph redirect stub instead of being deleted. SOP rule "never delete without a trace" applies; the file is referenced from shipped `Backlog.md`, `feature-map.md`, recent-work and review artifacts. Redirecting preserves all historical references without rewriting audit history.

- **[LOCKED]** Diagnostic mode is opt-in via `SHIP_SOP_DEBUG=1` env var, not always-on. Default behaviour stays silent so production hook output is not polluted.

- **[LOCKED]** Schema validation is warn-only, never blocking. The hook should never refuse to fire because of a config oddity — diagnostics surface the issue without making things worse.

- **[LOCKED]** Retention is opt-in (default `0` = disabled). Existing installs keep all their review history until the operator explicitly chooses a retention window.

---

## Batch Log

- **2026-05-02: Batch 2.1 shipped.** Usefulness hardening in `scripts/auto-ship-hook.sh`: `skip_log` helper + 13 silent-exit paths converted to `SHIP_SOP_DEBUG`-aware diagnostics; jq-based unknown-key warning across top-level / `.trigger.throttle` / `.agents.<name>` / `.release` / `.artifacts`; opt-in `artifacts.retain_ship_artifact_days` retention prune with the precise glob. Schema and config template updated to expose the new `artifacts` section. README troubleshooting section added.

- **2026-05-02: Batch 2.2 shipped.** Drift + slim. P10 retroactive entry filed under `docs/recent-work/`; `bash scripts/refresh-rollup.sh` regenerated CLAUDE.md rollup. CLAUDE.md "Current Priority Items" + "Likely future candidates" replaced with a Backlog pointer. `docs/ship-sop.md` unique content (the IPC explainer + extended Compliance scope) folded into README under a new "How auto-mode actually executes" section; original file replaced with a redirect stub. README uninstall manual-fallback wrapped in `<details>`. Hook edge fixes: `sha256sum` fallback, tightened docs-only regex, cached `git diff` once.

- **2026-05-02: Batch 2.3 shipped.** `docs/README.md` (new) — one-page orientation distinguishing ship-sop's surface from agent-sop pristine replicas from SOP-generated history. (Originally a 25-file `docs/internal/` archive move; cancelled after re-reading agent-sop's hardcoded paths.)

- **2026-05-02: Batch 2.4 shipped.** `setup.sh prompt_yn()` non-interactive timeout (`read -t 30` with default fallthrough). README quick-start: "Four" → "Five" command count, `/audit` added to example block. Schema URL verified via `gh repo view` and `curl` (200, no change needed).

---

## Deploy Checklist

- [x] `scripts/auto-ship-hook.sh` `bash -n` clean
- [x] `setup.sh` `bash -n` clean
- [x] `SHIP_SOP_DEBUG=1` smoke test prints stderr diagnostics
- [x] Schema-warn smoke test (`enabld: true`, `oops_typo: 99`) prints warnings
- [x] Retention safety test: agent-sop format files preserved, ship-sop format files pruned
- [x] `docs/templates/ship-sop.schema.json` documents new `artifacts` field
- [x] `docs/templates/ship-sop.config.json` includes new `artifacts` field example
- [x] README troubleshooting section + Quick start updates rendered cleanly
- [x] `bash scripts/refresh-rollup.sh` regenerates CLAUDE.md rollup
- [x] `Backlog.md` P11 entry under SHIPPED
- [x] `docs/feature-map.md` rows for P11
- [x] `docs/recent-work/2026-05-02_solo_p11-hardening.md` entry exists
- [x] `docs/recent-work/2026-04-26_solo_p10-uninstall.md` retroactive entry filed
- [x] No agent-sop pristine replicas modified (verified via `git status -s`)

---

## Open Questions

- Should the schema warning eventually escalate to a blocking error if a known-bad key is detected (vs warn-only)? [UNRESOLVED — current warn-only behaviour matches the rest of the hook's "never break the user's session" stance. Revisit if config-typo bugs continue to bite users in practice.]
- Should `artifacts.retain_ship_artifact_days` have a recommended default in the README other than 0? [UNRESOLVED — 90 is a reasonable starting point but feels arbitrary. Defer until real adopters report disk-bloat.]
- Should `SHIP_SOP_DEBUG` also surface what would have run on a successful fire (i.e. dry-run mode)? [UNRESOLVED — could be a separate `SHIP_SOP_DRY_RUN=1` env var. Defer; current diagnostic mode covers the "why didn't it fire" case which is the more common ask.]

### 2026-09-08 — P28 Codex integration

Implemented native Codex skills, isolated review runner and installer support.
Shared agent-sop runtime files synced from the companion checkout. Installation
and isolation fixtures pass. Implementation and review fixes are committed on
`feat/codex-support`; P28 and the explicit enforcement item P30 remain IN PROGRESS pending merge.
