# P11: Phase 2 hardening pass (diagnostics, schema warn, retention, drift, declutter)

**Date:** 2026-05-02
**Agent:** solo
**Commits:** (pending — will be filled in at commit time)

User asked for an objective whole-repo review against ship-sop's stated purpose: optimise, declutter, improve performance, harden usefulness. The work split into four batches plus the SOP wrap-up.

The interesting story here is the plan itself rather than the code: the first draft proposed a 25-file archive move into `docs/internal/`, framed as decluttering "dogfooding noise". A re-read of `.claude/agent-sop.config.json` revealed those 25 files are SHA-tracked pristine replicas of upstream agent-sop, and agent-sop's slash commands (`/update-sop`, `/restart-sop`, `/migrate-to-multi-agent`) hardcode every one of those paths. Moving them would break ship-sop, hst-tracker, and every future agent-sop consumer. The plan was scrapped and replaced with a single `docs/README.md` orientation note plus targeted hardening of ship-sop's own surface.

Earlier "perf" claims were also inflated. Caching `git diff` saves ~50-100ms on a typical diff, not "30-50%". The skip-pattern grep loop is 3 iterations in default config; refactoring saves microseconds. Real wins are usefulness hardening, not perf.

**What shipped (four batches):**

Batch 1 — usefulness hardening in `scripts/auto-ship-hook.sh`:
- `SHIP_SOP_DEBUG=1` env var prints `[ship-sop] skip: <reason>` on every silent-exit path (13 paths). Default silent.
- Schema sanity check: warn-only stderr advisory on unknown keys at top-level / `.trigger.throttle` / `.agents.<name>` / `.release` / `.artifacts` (catches `enabld: true` typos).
- Optional retention: `artifacts.retain_ship_artifact_days` field. Prunes ship-sop's `YYYYMMDD-HHMMSS-*.md` artifacts older than the threshold using `find -name '[0-9]{8}-[0-9]{6}-*.md'` (precise digit-count glob; agent-sop's `YYYY-MM-DD_<agent-id>_*.md` reviews are not matched).

Batch 2 — drift + slim:
- P10 retroactive `docs/recent-work/` entry filed. `bash scripts/refresh-rollup.sh` regenerated the CLAUDE.md rollup (P10 was missing despite shipping six days prior).
- CLAUDE.md "Likely future candidates" list (which still listed `--uninstall` as a future) replaced with a Backlog pointer.
- `docs/ship-sop.md` folded into README. Unique content: "How auto-mode actually executes" (the SessionStop → directive → next-turn IPC pattern, ~25 lines) and extended Compliance scope. Original `docs/ship-sop.md` replaced with a one-paragraph redirect stub so historical references continue to resolve.
- README uninstall: manual-fallback bash block wrapped in `<details>`.
- Hook edge fixes: `sha256sum` fallback alongside `shasum`; tightened docs-only regex (`^docs/.*\.(md|mdx)$|^[^/]+\.(md|mdx)$|^README(\.md)?$`) so `docs/img.png` and `READMENOT.md` no longer false-positive; cached `git diff "$BASE..HEAD"` once and reused for line count + hash.

Batch 3 — orientation:
- `docs/README.md` (new). Distinguishes ship-sop's own surface, agent-sop pristine replicas (do-not-edit list), SOP-generated history, and runtime artifacts (with the dual filename convention spelled out). Cancelled the larger archive move; this single file gives readers context without breaking integrations.

Batch 4 — setup robustness + small README fixes:
- `setup.sh prompt_yn()` `read -t 30 -r` with default fallthrough. CI runners and scripted installs no longer hang.
- README quick-start: "Four slash commands" → "Five"; `/audit` added to the example block with a launch-readiness gloss.
- README troubleshooting section added (documents `SHIP_SOP_DEBUG`, schema warnings, retention).
- Schema URL verified: 200 from `https://raw.githubusercontent.com/mmjclayton/ship-sop/main/docs/templates/ship-sop.schema.json`. No change needed.

Touched: `scripts/auto-ship-hook.sh`, `setup.sh`, `README.md`, `CLAUDE.md`, `docs/ship-sop.md`, `docs/agent-memory.md`, `docs/templates/ship-sop.schema.json`, `docs/templates/ship-sop.config.json`, `docs/README.md` (new), `docs/recent-work/2026-04-26_solo_p10-uninstall.md` (new), `docs/recent-work/2026-05-02_solo_p11-hardening-pass.md` (this file), `Backlog.md` (P11), `docs/feature-map.md` (10 P11 rows), `docs/build-plans/phase-2-hardening.md` (new).

No agent-sop pristine replicas were modified — verified via `git status -s` cross-checked against `.claude/agent-sop.config.json` `baseline_shas`.

## Open follow-ups

- Dogfood the new `SHIP_SOP_DEBUG` and schema-warn behaviour against hst-tracker on the next session-end fire to confirm the messages are useful in practice.
- Decide whether to recommend a default `retain_ship_artifact_days` value (current default is `0` = disabled). 90 days is a candidate but arbitrary — wait for adopter feedback.
- Consider promoting `SHIP_SOP_DRY_RUN=1` (would-fire echo without writing the directive) as a follow-up. Diagnostic mode covers "why didn't it fire"; dry-run would cover "what will it do."
