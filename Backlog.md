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

### P12 — Background-subagent semantics for gate execution
`[SHIPPED - 2026-07-27] [Bug]`

Claude Code 2.1.198 (1 July 2026) made subagents run in the background by default. ship-sop's gates fire via `@agent` invocations — auto-mode on the next user turn (from the `.ship/.pending-auto-fire.md` directive), manual mode inside `/ship`. Two documented behaviours now silently break:

1. **Auto-mode:** README states "Findings land in `docs/reviews/` and surface in the model's reply." With background subagents, the model can finish its reply before the gate agents complete — findings land late or surface in a later turn, and the "watch the reply for the auto-review summary" guidance misleads.
2. **Manual `/ship`:** "halts on hard-block failures" assumes the invoking turn waits for gate results. The command must explicitly collect every gate agent's result before evaluating `block_on` thresholds and reporting.

**Acceptance criteria:**
- `/ship` command doc requires collecting all gate-agent results before threshold evaluation and the readiness report — no reply until every enabled gate returns
- README "How auto-mode actually executes" section notes background-by-default and that findings may surface a turn later than the directive pickup
- Companion note: agent-sop P62 shipped the upstream `/update-sop` Step 0 pre-check (collect/terminate before session-end); ship-sop's SessionStop hook captures the diff at stop — outstanding subagent work at stop is invisible to the captured diff range and gets gated on the following stop instead

**Source:** Claude Code changelog 2.1.198 (verified); agent-sop 2026-07-06 digest review; agent-sop P62.

---

### P13 — Directive file `.ship/.pending-auto-fire.md` as an injection surface
`[SHIPPED - 2026-07-27] [Iteration]`

The auto-mode IPC pattern (hook writes a directive file; next-turn model reads it and invokes agents against the stated diff range) makes the directive file persistent agent state that the model acts on — exactly the persistence-vector class Anthropic's containment post (25 May 2026) flags, and the same class agent-sop P61 now covers for CLAUDE.md/Backlog/agent-memory. A poisoned directive (crafted commit, compromised dependency script, or any process with repo write access) could redirect the next turn's gate invocations or embed instructions the model treats as operator intent.

Constrain what the model trusts from the directive:

1. **Schema-bound consumption.** The next-turn reader treats the directive as data, not instructions: only the documented fields (gates list, diff range, report destination) are honoured; any prose outside the schema is ignored and flagged to the user.
2. **Provenance check.** `auto-ship-hook.sh` writes a content hash (same `shasum`/`sha256sum` fallback pattern the hook already uses) alongside the directive; the reader verifies it before acting. Mismatch = stale or tampered directive — report, do not execute.
3. **README note** in the "How auto-mode actually executes" section naming the directive as the audit trail *and* an input to treat with rule-1 scepticism (agent-sop `security.md`).

**Acceptance criteria:**
- Directive schema documented (fields the reader may honour; everything else ignored)
- Hash write + verify implemented in `auto-ship-hook.sh` and the reader-side instructions; `SHIP_SOP_DEBUG=1` prints the verification result
- Tampered-directive dogfood: hand-edit `.ship/.pending-auto-fire.md` after the hook writes it, confirm the next turn reports rather than executes
- README updated; no change to gate behaviour on clean directives

**Source:** anthropic.com/engineering/how-we-contain-claude; agent-sop P61 (2026-07-06); ship-sop composition review 2026-07-06.

**Reviewer turn returned 5 HIGH — all defects in this session's own work, all fixed before ship** (`docs/reviews/2026-07-27_solo_P12-P13.md`):

1. **The directive tripped its own tripwire.** P13's schema table listed five honoured fields but omitted the hook's own `## Auto-mode rules` block, which matches three of the stated tamper indicators (writes to `Backlog.md`, says don't halt, contains the P12 instruction). A compliant reader would have refused every directive the hook produces — P13 as first written was net-negative. Restructured: the hash is now the primary gate, and the fallback section check enumerates every section the hook emits, verified by regression.
2. **`README.md:55` still carried the exact sentence P12 was filed against** ("runs the gates before responding to your prompt"). The bullet three lines below had been caveated and the paragraph had not.
3. **The collect-before-evaluate instruction was stranded** after gates that already halt inline. Moved ahead of `## Pipeline gates`; Gates 2/3 now record verdicts rather than acting on them, and Gate 1 is called out as genuinely synchronous.
4. **The emitted verification command hardcoded `shasum`**, defeating the `sha256sum` fallback beside it. On a Linux host the hook wrote a correct sidecar then handed the reader a command exiting 127 — which the reader was told to read as tampering. Silent gate suppression on most containers. Both paths now tested.
5. **The staleness claim was false.** Nothing deletes the directive, so a stale one still matches its own sidecar. Claim removed; staleness is now a separate documented check comparing `Diff range` against `HEAD`.

Also from the review: the `UNAVAILABLE` sentinel is now a documented third state ("unverifiable", explicitly not "tampered") rather than a hash-shaped string; `CLAUDE.md:42/:94/:143` gained sidecar references, since verification had lived only in ephemeral hook stdout.

**Known, not fixed:** `setup.sh:145` has a third hash helper (`file_hash`) alongside `diff_sha256` and `file_sha256`. Consolidation is a separate `[Refactor]`, not folded into a `[Bug]` diff.


---

## Phase 3 — Automation and correctness

Filed 2026-08-03 from the full-project review (`docs/reviews/2026-08-03_solo_full-project-review.md`): 7 reviewer dimensions, adversarially verified, 48 surviving findings. Plan and batch detail in `docs/build-plans/phase-3-automation-and-correctness.md`.

### P14 — SessionStop hook entry is written in a shape Claude Code discards
`[SHIPPED - 2026-08-03] [Bug]`

`setup.sh` wrote `{"hooks":{"Stop":[{"command":"scripts/auto-ship-hook.sh"}]}}`. Claude Code requires each entry to nest its command: `{"matcher":"*","hooks":[{"type":"command","command":"..."}]}`. The flat form parses as JSON and is then discarded by the harness, so the hook never ran and nothing reported an error. Auto-mode has therefore never fired in any project since P1 — confirmed by `.ship/.last-auto-fire` frozen at install time in both live installs, and by the contrast with correctly-shaped hooks sitting in the same `Stop` array in `hst-tracker/.claude/settings.json`.

This is the root cause of the pipeline being invoked by hand: the automation was never wired.

**Acceptance criteria:**
- Nested shape emitted at all four write sites (fresh-file heredoc, jq merge, jq-missing warning, this repo's own `.claude/settings.json`)
- The three selectors that assumed the flat shape updated, or install/uninstall silently no-op: idempotency probe, uninstall probe, uninstall delete
- Selectors live in one place (`HOOK_NESTED_PROBE`, `HOOK_LEGACY_PROBE`, `HOOK_ENTRY_EXAMPLE`) so install and uninstall cannot drift apart again
- Pre-P14 flat entries migrated in place, not duplicated
- Uninstall removes both shapes and leaves other hooks in the same array intact
- Post-install assertion hard-fails if the entry is not reachable via the nested probe
- README manual-fallback removal command updated to match

**Verified:** fresh install, re-run idempotency, legacy migration alongside a user hook, uninstall of both shapes, assertion rejects the flat shape and accepts the nested one.

**Source:** `docs/reviews/2026-08-03_solo_full-project-review.md` P1-1.

---

### P15 — Installer damage: `.gitignore` over-delete, symlink self-delete, `/ship-on` hook clobber
`[SHIPPED - 2026-08-03] [Bug]`

Three independent installer defects, all reproduced. (a) The uninstall `.gitignore` awk sets `skip = 2` after `next` has already consumed the marker line, so it eats one user line past the ship-sop block while printing "other entries kept" — a `.env.local` sitting after `.ship/` becomes un-ignored. (b) `setup.sh:32` and `:92` use logical `pwd`, so a symlinked invocation defeats the self-install check and `--uninstall` deletes ship-sop's own source. (c) `ship-on.md:20` replaces `.hooks.Stop` wholesale and writes a 0-byte `settings.json` when the file is absent, while `:44` claims it does not modify settings.json.

Also adds the repo's first CI: shellcheck on `setup.sh` and `scripts/*.sh`, `jq empty` on both configs.

**Acceptance criteria:** `skip = 1` in `setup.sh` and the `README.md` copy; `pwd -P` plus an `-ef` guard in `remove_if_unmodified`; `/ship-on` snippet deleted in favour of `setup.sh`; sentinel-line regression check; CI workflow green.

**Verified:** (a) install → append sentinel immediately after the block → uninstall → sentinel survives, ship-sop block gone, pre-existing entries intact. (b) A/B through a real symlinked clone: the pre-P15 installer deleted `scripts/auto-ship-hook.sh`, the schema template and the config; the fixed one reports "Self-install detected" and everything survives. (c) Reproduced both `/ship-on` snippet defects before removing it — wholesale `.hooks.Stop` replacement destroyed a co-located user hook, and a missing `settings.json` produced a 0-byte file. CI: shellcheck `-S warning` and `bash -n` clean on both ship-sop scripts, five JSON files valid, workflow YAML parses.

Also fixed while in the file: `/ship-on` line 6 still advertised the three-gate set and the pre-rename `doc-builder`.

**Reviewer turn:** `docs/reviews/2026-08-03_solo_P14-P15.md` — APPROVE (0 CRITICAL / 0 HIGH / 1 MEDIUM / 2 LOW), covering P14 and P15 together. Fired by Step 1b trigger (b) on the `.claude/commands/**` change, not by tag. All three findings fixed in-session: the hook script's header comment still documented the dead flat shape (the exact reference an operator would hand-wire from); the uninstall jq dropped a pre-existing `"hooks": []` entry that was not ours; the README fallback lacked the existence guard `setup.sh` has. Round-trip verified — a settings.json with a user hook plus an empty-hooks entry survives install → uninstall byte-equivalent.

---

### P24 — `--uninstall` on one project silently disarms ship-sop in every other project
`[OPEN] [Bug]`

Discovered during P15 regression testing, by being bitten by it. `remove_user_scope_files()` deletes `~/.claude/agents/{compliance-reviewer,diagram-builder,release-notes-writer}.md` and `~/.claude/commands/{ship,release,ship-on,ship-off,audit}.md` whenever `--uninstall` runs against *any* target. Those paths are global. Uninstalling ship-sop from a project you no longer want gated therefore removes the agents and commands every other installed project depends on, with no warning and no reference counting. The remaining projects keep their config, their hook and their `ship-sop.config.json`, so auto-mode still fires — and every gate then resolves to a missing agent.

That last part is what makes it more than an inconvenience: it converts a clean uninstall in project A into silent gate loss in projects B and C. Under the P17 rule this must surface as MISSING, but P17 does not exist yet and the hook does not check agent presence today.

**Acceptance criteria:**
- Uninstall detects other installed projects before removing user-scope files, and either skips them or requires explicit confirmation naming the projects that would lose their gates
- A `--user-scope-only` / `--project-only` split so "stop gating this project" and "remove ship-sop from this machine" are separate operations
- Reinstall is the documented recovery, and the uninstall summary says so
- Consider an install manifest at `~/.claude/.ship-sop-installs` as the reference-count source; ties into the P23 manifest work

**Source:** P15 session, 2026-08-03. Recovery used was `./setup.sh <project>` answering `n` to the hook prompt, which restored all eight user-scope files without touching the wiring.

---

### P16 — Close the automation loop: SessionStart pickup so no command is typed
`[WON'T - Reason: superseded 2026-09-04 by agent-sop P97, which delivers the intent in one step instead of two] [Feature]`

**Superseded (2026-09-04).** The two-step design (Stop writes a directive, SessionStart injects a pointer, the model dispatches) rested on a premise that turned out false: project-scope hooks never load for a session launched outside the project, and Stop stdout never reaches the model. agent-sop P97 ships a user-scope Stop hook (`sop-stop-drift.sh`) that reads this repo's `ship-sop.config.json` and exits 2 with the gate demand in the same turn, plus a push gate (`sop-push-gate.sh`). No directive file, no pickup, no `/restart-sop` backstop needed. See `docs/agent-memory/decisions/2026-09-04_solo_auto-mode-trigger-moves-to-agent-sop.md`.

Depends on P14. The Stop hook writes a directive; nothing deterministically picks it up. Add a SessionStart hook that verifies the sidecar and freshness and injects the directive pointer into the opening context, so gates dispatch with nothing typed. `/restart-sop` becomes a backstop sharing one idempotent pickup routine keyed on a consumed marker, so a session that starts and is then given `/restart-sop` cannot dispatch twice.

The `/restart-sop` step ships in the **agent-sop repo** guarded on `ship-sop.config.json` existing, and arrives here via `/update-agent-sop` — a downstream edit to a pristine replica would be reverted by the next sync (`CLAUDE.md` rule 8).

**Acceptance criteria:** directive deleted on consumption and stale pairs cleared at the top of every hook run; `--no-session-start` opt-out; end a session, start a new one, gates dispatch untyped; `/restart-sop` in that session does not re-dispatch.

---

### P17 — `/ship` dispatches 4 of the 7 gates it advertises
`[SHIPPED - 2026-09-05] [Bug]`

`ship.md` hardcodes Gate 1 tests, Gate 2 security, Gate 3 compliance, Gate 4 diagrams. `code-reviewer`, `silent-failure-hunter` and `pr-test-analyzer` appear zero times in the file; two are configured `block_on: HIGH`. `ship.md:8` claims "the gates and outputs are identical" to auto-mode, which reads them from config. So the path documented as stricter is the weaker one. Flagged by the P9 reviewer on 2026-04-25 and never filed.

Includes the gate-completion contract: `block_on` is quoted at `:64`/`:68` but hardcoded to CRITICAL at `:108`/`:117`/`:119`/`:128`; `<stamp>` is referenced six times and generated nowhere; four of six gate agents are read-only so they cannot write the artifact `:67` uses as its completion test; two emit no severity enum at all.

**Acceptance criteria:** config-driven dispatch reusing the hook's enumeration; per-agent `block_on` honoured; one `<stamp>` per run; `Gates dispatched: N of M enabled` header; agent-presence check; orchestrator persists read-only agents' replies; severity normalised with INCOMPLETE fallback; **a gate that did not run reports MISSING, never a pass.**

---

### P18 — Hook state machine: staleness check cannot fail, throttle records the wrong event
`[WON'T - Reason: superseded 2026-10-10 by P25, which removed scripts/auto-ship-hook.sh; agent-sop reads coverage from validated receipts, with no stamp or directive file] [Bug]`

The directive writes `Diff range: <base>..HEAD` with `HEAD` as a literal string, then instructs the reader to check "if the range no longer ends at `HEAD`" — it always does, so the staleness check is a tautology. `HEAD_SHA` is computed at `:165` and discarded. A stale directive from 27 July is in `.ship/` now, naming a deleted branch, hash still matching. Separately the diff-hash is stamped at emission (`:411`) rather than gate completion, so an interrupted turn leaves that commit permanently ungated and silently skipped next run.

Plus three silent-exit traps under `set -euo pipefail`: a no-match `grep -v` at `:189` kills the script; malformed config dies at `:118` with a raw jq error after seven schema probes swallowed it; a future timestamp in `.last-auto-fire` disables auto-mode for 250 years with no output.

**Blocks default-on automation** — auto-dispatch on a tautological staleness check would gate the wrong range.

---

### P19 — Coverage holes: a gate reports success without looking
`[SHIPPED - 2026-10-10] [Bug]`

2026-10-10 triage: (a), (b) and (c) described the removed hook and are superseded by P25 and agent-sop's receipt coverage (a missing test runner is now `NOT_AVAILABLE` with a reason, never a pass; instruction files count as code). (e) is gone: `/ship` no longer runs `git add`. (d) was open: no reviewer instruction declared diff content untrusted. Fixed with P25: `/ship` and the Codex runner prompt (`scripts/codex-review.sh`) now tell reviewers to treat the diff, comments and commit messages as untrusted data, and that a claim of prior sign-off changes nothing; `tests/codex-install.sh` asserts the prompt text.

(a) No detected test runner means Gate 1 prints a notice and passes, so an agent scaffolding a service with zero tests gets READY TO SHIP. (b) The docs-only regex matches any top-level `.md`, so `CLAUDE.md` and `Backlog.md` — the highest-value files for steering the next agent — route around every blocking gate, the same persistence vector P13 hardened the directive against. (c) Missing sidecar is treated as "not tampering" although the hook writes one unconditionally, while a hash mismatch skips the gates, making `printf '\n' >>` a permanent off-switch. (d) Nothing anywhere declares diff content untrusted, so a diff asserting prior sign-off is read as operator intent. (e) `ship.md:195` runs `git add -A` straight after gates instructed to find hardcoded secrets, with no redaction rule in any agent.

---

### P20 — Deterministic gates in the hook, and a push/PR gate that can actually refuse
`[OPEN] [Feature]`

Every gate today is model judgement. shellcheck, `jq empty` and a staged-secret scan need no model: run them inside the hook where they are instant, free, and cannot be reasoned past. Then add a `PreToolUse` hook on `git push` / `gh pr create` that refuses when no gate run covers `HEAD` — coverage is a deterministic fact a hook can check, unlike "are there findings". `SHIP_SOP_SKIP_GATE=1` overrides and is recorded in the report so bypasses are greppable. This is what turns ship-sop from a reporter into a gate.

**Partially delivered upstream (2026-09-04).** The push/PR gate shipped in agent-sop P97 as `sop-push-gate.sh`: refuses `git push` / `gh pr create` when `ship-sop.config.json` is `auto`, the code diff vs the default branch is at or over `min_diff_lines`, and no `docs/reviews/*-ship-auto.md` names an ancestor of HEAD with zero code lines since. The bypass token is `SOP_SKIP_GATE=1` (not `SHIP_SOP_SKIP_GATE`), logged to `.ship/bypass.log` with the HEAD it skipped. Still open here: the deterministic checks inside the hook (shellcheck, `jq empty`, staged-secret scan).

---

### P21 — Fixture harness and CI for the hook
`[OPEN] [Feature]`

ship-sop enforces test gates on others and has none. `CLAUDE.md:78` claims a CI candidate is "filed in `Backlog.md` if needed" — no such item existed and there is no `.github/`. agent-sop's `docs/benchmark/drift-fixtures/run-tests.sh` pattern ports directly. Cases: below-min-diff, cooldown, same-hash, docs-only, agent-instruction-file, no-agents, malformed config, future timestamp, stale directive, happy path. Assert on the directive body, not just the exit code.

---

### P22 — Command and agent defects
`[OPEN] [Bug]`

`/audit`'s documented `--scope`/`--regulation`/`--no-shadow-controls` flags are inert against a bare invocation, and `--scope` is prescribed as the fix for the timeout most likely to hit. `/release` says "halt" without defining confirmation or ending the turn, then tags/pushes/publishes unguarded, and `--no-publish` commits `chore(release):` before the flag is checked. `compliance-reviewer` scores health data CRITICAL at `:78` and MEDIUM at `:104` while saying twice it does not enforce HIPAA. Backlog auto-file has no dedup and no cross-branch P-number reservation. `diagram-builder`'s hand-edit guard tests for a marker its own templates never write. `release-notes-writer` can publish an abandoned branch's feature. Split if it grows.

---

### P23 — Replica drift, tracker backfill, and naming inconsistency
`[OPEN] [Refactor]`

Six of 28 SHA-tracked agent-sop replicas are stale; `validate-state-transitions.sh` is 602 lines here against 783 upstream and runs a pre-fix copy of a silent-failure bug in `resolve_before()`. `.claude/agent-sop.config.json` has `update_reminder: "weekly"` and nothing reads it — add a warn-only drift check. Replicating a 600-line executable without upstream's fixtures is the worst option; decide vendor-with-fixtures or invoke via `.local_path`. Backfill P12/P13 into `docs/feature-map.md` (still "Last updated: 2026-04-26 (P10)") and the Phase 2 Batch Log. Artifact naming disagrees three ways between the hook, `ship.md` and README. README understates the install footprint by three items and misdescribes `--force` scope. Root config missing the `artifacts` block its own template has, which also makes `--uninstall` refuse to remove it as "locally modified".

---

### P27 — Three default gates, one review run, a minimal `/ship`
`[SHIPPED - 2026-09-05] [Iteration]`

From the 2026-09-05 five-agent token review of agent-sop and ship-sop (recorded in the operator's memory note `project_sop_token_review_2026-09-05`). Measured on two agent-sop gate runs: 417k and 561k tokens per ship, ~64k fixed per agent launched regardless of diff size; compliance-reviewer and diagram-builder 23% of the total for zero findings; both CRITICALs from silent-failure-hunter.

- Template and this repo's config enable `security-reviewer`, `silent-failure-hunter`, `code-reviewer`; `pr-test-analyzer`, `compliance-reviewer`, `diagram-builder` ship disabled, added per run with `/ship --with <agent>`.
- `/ship` rewritten to ~40 lines: project-type gate, range, tests, dispatch **every enabled agent** with `isolation: "worktree"` (closes P17: the old text dispatched only three of six and omitted the agent that found both CRITICALs), collect all, one report with `Covers:`, no Backlog filing, no `--skip` override.
- One review run serves agent-sop's Step 1b and the gate; README section rewritten.
- Dead keys removed from the template and this config (`skip_docs_only`, `cooldown_seconds`, `auto_file_backlog`, `release.*`, `artifacts.*`); schema keeps them as deprecated so old configs validate.
- `/ship-on` Step 4 probes `~/.claude/settings.json` for `sop-stop-drift.sh` (P25 item 5).

**Acceptance criteria:**
- Template parses; this config parses; schema parses - DONE
- `/ship` names the config's enabled set, not a hard-coded three - DONE
- README "What runs", "Relationship", "Per-agent toggles", "Throttle", "Outputs" agree with the trigger in agent-sop `sop-lib.sh` - DONE

**Source:** operator instruction "fix all of this", 2026-09-05.

---

### P26 — Gates fire only on code projects and code lines
`[SHIPPED - 2026-09-04] [Iteration]`

Operator rule, 2026-09-04: ship-sop fires for coding and for nothing else. The trigger lives in agent-sop (P97), and agent-sop P102 makes it read one project-type rule (`sop-project-type.sh`: an explicit `**Project type:**` line in CLAUDE.md, else the compliance-checklist heuristics) and count code lines only. This item is ship-sop's side of it, docs-only:

- `/ship` opens with a project-type gate and stops on a non-code project; `/ship-on` refuses to enable auto-mode there.
- README states the rule; `skip_docs_only` is documented as accepted-but-unread (documentation is always excluded now — and was already, by accident: agent-sop's hook read it with a jq `// true` default, which swallows an explicit `false`). Template default flips to `true` so the file says what happens; schema description updated.
- This repo declares `**Project type:** code` in CLAUDE.md (bash under CI, no manifest — the heuristics alone would say non-code).

**Acceptance criteria:**
- A non-code repository with an auto config gets no gate demand, no refused push, and `/ship` stops in one line — enforced and fixture-tested in agent-sop P102
- Template and schema agree with the trigger
- User-scope replicas of `/ship`, `/ship-on`, `/ship-off` refreshed

**Source:** operator instruction, agent-sop session 2026-09-04.

---

### P25 — Retire the project-scope `auto-ship-hook.sh` wiring now that agent-sop carries the trigger
`[SHIPPED - 2026-10-10] [Refactor]`

Merged via PR #25 (f62d1bc), CI green. Consumer repos (step 4) drop the entry when setup is next run there.
review: docs/reviews/20261010-143321-ship-auto.md

2026-10-10: script deleted outright (not kept as reference); setup retires leftover copies by blob hash and both entry shapes, `tests/legacy-hook.sh`; CI asserts no entry remains. This repo's settings already had none; `/ship-on` already probes `sop-stop-drift.sh`. Folded in from the P37 review: actions pinned by SHA with Dependabot and auto-merge, a cleanup trap and distinct jq messages in `create_default_config`, self-install and Codex default-config tests. Consumer repos (step 4) are checked separately.

agent-sop P97 (2026-09-04) supersedes the project-scope Stop hook: its user-scope `sop-stop-drift.sh` reads `ship-sop.config.json` and emits the gate demand via exit 2, and `sop-push-gate.sh` refuses an uncovered push. The old entry is inert for home-launched sessions and a harmless duplicate otherwise, but it still gets copied and wired by `setup.sh`, asserted by CI, and sits in four consumer repos.

**Scope:**
1. `setup.sh` — stop copying `scripts/auto-ship-hook.sh` and stop writing the `.hooks.Stop` entry; keep `--uninstall` able to remove legacy entries (both shapes). Keep the config bootstrap and the `.gitignore` block.
2. `.github/workflows/ci.yml` — replace the P14 "nested shape" assertion (which now asserts the presence of a superseded hook) with an assertion that no `auto-ship-hook.sh` entry remains in this repo's `.claude/settings.json`; keep shellcheck on the script while it stays in the repo.
3. This repo's `.claude/settings.json` — remove the entry.
4. Consumer repos — remove the entry on each project's next session: `hst-tracker`, `opportunity-scan`, `os-carry`. The agent-sop context hook flags a leftover `.ship/.pending-auto-fire.md`; delete the `.ship/` legacy files with it.
5. `/ship-on` Step 4 — probe `~/.claude/settings.json` for `sop-stop-drift.sh` instead of the project file for `auto-ship-hook.sh`.
6. `docs/ship-sop.md` and `docs/feature-map.md` rows P1/P2/P11/P14 — mark the "next-turn pattern" superseded in place.

**Acceptance criteria:**
- A fresh `setup.sh` run wires no Stop hook and CI passes
- `setup.sh --uninstall` on a repo with the legacy entry still removes it
- `grep -rl auto-ship-hook.sh ~/Projects/*/.claude/settings.json` returns nothing
- P18 and P19's hook-state-machine bugs are closed as superseded rather than fixed, with a note pointing at agent-sop's coverage-by-fact rule

**Source:** agent-sop P97 close-out, 2026-09-04.

---

### P33 — Path-scoped reviewer enablement
`[SHIPPED - 2026-09-24] [Feature]`

Merged via PR #16 (1ace2d8) with agent-sop P111 (PR #30, 2d4cf7d). Template scopes security-reviewer; opportunity-scan scoped the same day (3b2d23a): on its twelve receipt ranges the reviewer stays in scope for eight.

A reviewer's yield depends on what the diff touches. Over eleven Opportunity Scan gates (8 to 24 September 2026) security-reviewer produced zero CRITICAL and zero HIGH; the same agent found a CRITICAL in agent-sop's shell on 5 September. The only control today is `enabled` per repository, so a reviewer either runs on every diff or never. Decision record: opportunity-scan `docs/agent-memory/decisions/2026-09-24_client_two-reviewers-carry-the-gate.md`.

Add an optional `paths` array per agent in `ship-sop.config.json`. Patterns are regular expressions rather than globs: the config already uses regular expressions for `skip_branch_patterns`, and jq matches them inside the receipt validator without a second matcher. An agent with `paths` joins the gate plan only when `git diff --name-only BASE..HEAD` matches at least one glob; an agent without `paths` behaves as today. The template ships security-reviewer scoped to shell, server routes, auth, HTML rendering and env/config files, and leaves the other agents unscoped.

**Acceptance criteria:**
- `auto-ship-hook.sh` gate plan and `/ship` (Claude and Codex) select the same set for the same diff and config
- Schema accepts `paths` (array of strings) and rejects a non-array
- Fixtures: scoped agent skipped on a non-matching diff, selected on a matching diff, unscoped agent unaffected; a config with no `paths` anywhere produces today's plan byte for byte
- README "Per-agent toggles" documents `paths` and the template default

**Source:** operator decision, opportunity-scan session 2026-09-24.

---

### P34 — Reviewer run and round counts in Claude receipts
`[SHIPPED - 2026-09-24] [Iteration]`

Merged via PR #17 with agent-sop P112 (PR #31). Not included: filling `usage` from the Codex runner telemetry; the field is null on both runtimes until that is wired.

The Codex path records `usage` per review (`codex-review.sh`, P32). The Claude path cannot see subagent token usage, so a Claude receipt's `model` reads `runtime-default-unresolved` and carries no cost field. The one measured cost figure on file is the 5 September gate (about 64k tokens fixed per reviewer launched); the 24 September B43 estimate of 1.4M was not measured. Gate-cost decisions need a recorded proxy.

Add to each reviewer entry in the receipt: `launches` (fresh agents started), `rechecks` (re-reviews by an agent with context intact) and `block_rounds`, plus an optional `usage` object when the runtime exposes it. Both write paths produce the fields; the validator requires the three counts.

**Acceptance criteria:**
- Schema and validator require `launches`, `rechecks`, `block_rounds` on every reviewer entry; `usage` optional
- Codex path fills `usage` from the existing telemetry; Claude path leaves it null and does not claim a figure
- Existing receipts without the fields still validate under `schema_version: 1`; new fields land under `schema_version: 2`
- `/ship` report table shows launches and rechecks per reviewer

**Source:** operator decision, opportunity-scan session 2026-09-24.

---

### P35 — Codex usage in receipts
`[SHIPPED - 2026-09-24] [Iteration]`

Merged via PR #19 (826b850); installed Codex assets refreshed the same evening.

P34 left `usage` null on both runtimes. The Codex runner already records per-turn usage and a telemetry status in each run's `metadata.json` (P32); nothing turned that into the receipt's one object per reviewer. `scripts/codex-usage.sh [--agent NAME] EVIDENCE_DIR...` sums a reviewer's runs (launches and re-checks) into `{source, runs, turns, elapsed_seconds, tokens{...}, evidence[]}`, prints null when any run lacked telemetry so a partial sum never reads as a total, and refuses evidence from another reviewer or from before telemetry existed. Installed beside the runner; `$ship` step 4 names it. Claude stays null.

**Acceptance criteria:**
- `tests/codex-usage.sh`: two runs sum; a run without telemetry yields null with the run named on stderr; mixed, mismatched, non-evidence and pre-telemetry inputs exit 2
- Installer places and removes the helper with the runner; `tests/codex-install.sh` checks both
- CI runs the helper test

**Source:** operator instruction, 2026-09-24 evening.

---

### P36 - Replicate agent-sop P113 and P114 documents

`[SHIPPED - 2026-09-30] [Iteration]`
review: docs/reviews/20260930-112230-ship-auto.md

Two pristine-replica documents updated from agent-sop main (6d89a77, PR #33) with `sync-sop-files.sh --apply`: `docs/sop/claude-agent-sop.md` carries the rule that SOP project state stays out of harness memory (agent-sop P114), and `docs/sop/harness-configuration.md` documents the memory index size check hook (agent-sop P113). No ship-sop code changed. The hook itself is installed from agent-sop. Their content was reviewed upstream (agent-sop `docs/reviews/20260930-111521-ship-auto.json`, PR #33).

The sync also advanced the baseline SHAs for five installed files that this repository does not hold: `update-sop.md`, `update-agent-sop.md`, `sop-doctor.sh`, `sop-lib.sh` and the new `sop-memory-index.sh`.

Merged via PR #21 (f6679f6) on 2026-09-30, CI green.

**Acceptance criteria:**
- `sync-sop-files.sh --root` on this repository reports no older or missing rows
- CI green

**Source:** operator instruction, 2026-09-30.

---

### P37 - Act on the 2026-10-10 independent review

`[SHIPPED - 2026-10-10] [Iteration]`
review: docs/reviews/20261010-125845-ship-auto.md

Merged via PR #23 (c77f836) on 2026-10-10. CI green on ubuntu-latest, including `tests/claude-install.sh` and the cross-package `tests/receipt-integration.sh`. Stale remote branches deleted.

An independent review of main (80a2b04) found that a receipt certifies recorded results, not that reviews ran: `ship-receipt.sh` takes verdicts and test status from files the session writes, and agent-sop's `sop_receipt_valid` checks `.verdict == "PASS"` without comparing it to reviewer evidence. README line 16 ("Rejects blocked, incomplete or stale review evidence") read stronger than that.

- README states the limit in a "What a receipt proves" section and rewords the two summary bullets (Option A).
- CI runs `tests/receipt-integration.sh` against a checkout of agent-sop main, the only suite covering both repositories.
- `setup.sh` disables `silent-failure-hunter` in a new Claude-only config when no profile exists at user or project scope, and says so. The config is built beside the target and renamed once (mode 644); a failed edit leaves no config and names jq. Fixture: `tests/claude-install.sh`.
- CI: agent-sop checkout without persisted credentials, its SHA logged, all test scripts under shellcheck and `bash -n`.
- Housekeeping: merged and squash-merged branches deleted, including `docs/p26-code-projects-only` (tree identical to 9eadcc7, PR #11); stray `.claude/agent-sop.config.json.bak` removed.

The stale agent-sop `scripts/codex-review.sh` copy stays with P23 and is fixed in agent-sop.

**Acceptance criteria:**
- `tests/claude-install.sh` fails before the setup change and passes after
- CI runs all five suites, including the cross-package one
- README makes no claim that a receipt proves a review ran

**Source:** operator instruction, 2026-10-10, on the independent review.

---

### P38 - Check Codex receipt entries against runner evidence

`[SHIPPED - 2026-10-10] [Feature]`

Merged via PR #27 (dac81d4), CI green.

2026-10-10 review v2: the README overstated the scope. The check runs only in `ship-receipt.sh`; agent-sop's gates validate the receipt alone, so a receipt written straight into `docs/reviews/` bypasses it (confirmed in `sop_shipsop_covered`, which calls only `sop_receipt_valid`). README reworded. Moving the check into the gate was declined: it needs a runtime field in the receipt, works for Codex only, and the session can still write `.ship/`.
review: docs/reviews/20261010-145222-ship-auto.md

2026-10-10: `ship-receipt.sh` refuses a Codex receipt when any reviewer entry lacks a run record in `.ship/reviews/` with the same reviewer, commit, base, verdict, exit 0 and no timeout; reviewer names are validated before use. Fixtures in `tests/receipt-integration.sh` (no evidence, verdict mismatch, other commit, timeout, bad name; Claude unchanged). README states the check per runtime. Also carries the six P39 review LOWs: settings links followed only to a Claude settings file inside the project or home, including a linked `.claude` directory; guarded `$HOME`; named `readlink -f` failure; library load reason includes stdout; differing-copy check includes schema version.

Option B from the 2026-10-10 independent review. Before `ship-receipt.sh` writes a receipt under Codex, check each reviewer entry against the runner's evidence in `.ship/reviews/`: the run exists, it was for the same commit and base, and its recorded verdict matches. Refuse the receipt on any mismatch.

Limits: Codex only, since Claude subagents leave no evidence to check. It raises the cost of forging a receipt but does not prevent it, because the evidence directory is writable by the same session. The README limits section would then describe the Codex check.

**Acceptance criteria:**
- A fixture with a hand-written `PASS` result and no matching evidence is refused under Codex
- A genuine run still produces a receipt
- Claude behaviour unchanged and documented

**Source:** 2026-10-10 independent review, logged at operator instruction.

---

### P39 - agent-sop compatibility check and receipt totals

`[SHIPPED - 2026-10-10] [Feature]`

Merged via PR #26 (daf1dfd), CI green at both agent-sop commits.
review: docs/reviews/20261010-144318-ship-auto.md

From the 2026-10-10 independent review (two repositories that must move together; no evidence of value).

- `ship-receipt.sh --check-lib` checks the installed agent-sop library for every function ship-sop calls and names any missing one with the minimum agent-sop (`0a1e5ee`, P112, 2026-09-24, the first with receipt schema version 2; its parent fails the cross-package test, verified locally 2026-10-10). Claude setup warns; Codex auto-mode setup refuses. CI runs the cross-package test at that commit and at agent-sop `main`. Fixture: `tests/agent-sop-compat.sh`.
- `scripts/receipt-totals.sh` totals receipts across projects (deduped across clones). Fixture: `tests/receipt-totals.sh`.
- README: minimum agent-sop, the totals tool and what it cannot show, a one-maintainer statement.
- P25 review LOWs: legacy entries removed under any hook event; settings mode and symlinks preserved; incomplete uninstall reported; Dependabot comment corrected; stale-registration path tested.

A version constant exported by agent-sop's library would replace the function list; that belongs in agent-sop.

**Acceptance criteria:**
- `tests/agent-sop-compat.sh` fails on the previous `ship-receipt.sh`
- CI green against agent-sop `main` and `0a1e5ee`

**Source:** operator instruction, 2026-10-10.

---

### P40 - Measure reviewer precision on a blind sample of blocking findings

`[SHIPPED - 2026-10-11] [Feature]`
review: docs/reviews/20261011-p40-ship-auto.md (merged as PR #36, 41fb083)

**Result (11 Oct 2026, run at Matt's request: "run it if it gives us actual data that ship sop adds value or not"; report `docs/benchmark/p40/report.md`):** of 29 blind-graded blocking findings from edward, both graders rated 14 (48%) real defects and 2 (7%) false positives. Grader A rated 17 real and 3 false; grader B, told to be sceptical, rated 14 real and 5 false. The graders agreed on 24 of 29. The confirmed defects include 3 security or privacy exposures and 2 data-loss defects. The result holds with uncertain rows removed (46-50% real, 5-8% false). Whether edward's existing tests would also have caught them is unknown, because receipts record test status only at the final commit. Measured cost: 1,460 reviewer runs over 174 receipts, 8.4 per receipt. Tokens are not measured for edward; about 93M at P27's 64k per launch is an estimate. Not measured: what the defects would have cost if caught later, so this shows precision, not net value. S14 was excluded (its blocking findings could not be attributed).

From review v2 (2026-10-10). The gates' block rate (edward: 98 of 142 schema-2 receipts blocked at least once) shows how often they stopped work, not whether the blocks were worth it. This item measures precision from existing records, with no new review runs, and puts a cost estimate for a full with-and-without benchmark beside the result.

**Design:**
- **Sample.** 30 blocking findings from edward's `docs/reviews/*-ship-auto.md` tables (rounds that blocked), stratified across reviewers and severities so no single reviewer dominates. Record the sampling frame and seed.
- **Blind input.** Each grader sees only the finding (severity, file, line, message) and the code at the reviewed commit. The disposition column is stripped before grading.
- **Grades.** Validity on its own merits: real defect, valid but minor, or false positive, each with a one-line reason. Outcome recorded separately from the reports: fixed or not fixed. A real defect left unfixed is reported.
- **Two graders.** The session agent and a fresh agent with no edward context grade all 30 independently. Report percentage agreement and a 3x3 disagreement table (real/minor/false positive).
- **Benchmark estimate.** Scope a with-and-without benchmark (repos, change set, runs) and estimate its API cost from receipt run counts and Codex usage records where available; label anything not measured as an estimate.

**Acceptance criteria:**
- Sample frame, seed and the 30 extracted findings committed (without dispositions) before grading
- Both graders' grades, agreement figure and disagreement table in one report
- Precision per reviewer and overall, with the unfixed-real-defect count
- Benchmark scope and cost estimate beside the result, with measured and estimated figures separated

**Source:** operator approval 2026-10-10, on the review v2 recommendation.

---

### P41 - Fold agent-sop's push gate and reviewer agents into ship-sop

`[SHIPPED - 2026-10-11] [Refactor]`

Since agent-sop P124 (11 Oct 2026), the only parts of agent-sop that do anything are the push gate (`sop-push-gate.sh`, `sop-lib.sh`, `sop-project-type.sh`, the Codex dispatcher `sop-codex-hook.sh`, registered by `install-hooks.sh`), the library `ship-receipt.sh` loads to validate receipts, and the `security-reviewer` and `code-reviewer` agents the gate runs. All of them serve ship-sop. Keeping them in a second repository meant two installs, a sync layer (`/update-agent-sop`, `sync-sop-files.sh`, `.claude/agent-sop.config.json`), CI checkouts of agent-sop at `main` and at a minimum commit, and a compatibility check between the two. Operator decision 11 Oct 2026: fold them into ship-sop; agent-sop then becomes private and archived, and ship-sop must stand on its own.

**Design:**
- **Code.** The four hook scripts move to `scripts/hooks/`, the installer to `scripts/install-hooks.sh`. The installed location becomes `~/.claude/scripts/hooks/ship-sop/` (Codex: `$CODEX_HOME/scripts/hooks/ship-sop/`). `sop-lib.sh` keeps only what the gate, the project-type check and receipt validation use. Function names (`sop_*`) and the `SOP_SKIP_GATE` bypass are unchanged, and the gate still fails closed.
- **Migration.** The installer removes every registration that points at `.../scripts/hooks/agent-sop/sop-*.sh` (Codex also at the Claude copies), then deletes the old copies whose git blob is a shipped agent-sop version (`scripts/legacy-agent-sop-hooks.txt`, built from agent-sop's full history). Edited copies are kept and named, and deletion happens after the settings write. The retired-hook registration cleanup is kept.
- **Setup.** `setup.sh` and `setup-codex.sh` install and register the gate and the two reviewer agents themselves; the "install agent-sop first" preconditions go. Agents are installed where absent or byte-identical to a shipped version (`scripts/shipped-user-files.txt` (then `shipped-agents.txt`)) and kept when edited. `--no-hook` installs the scripts without registering the gate; `--uninstall` removes the registration and the scripts. `install-codex.sh` knows only the ship-sop package.
- **Sync layer retired.** `.claude/agent-sop.config.json`, `scripts/detect-trackers.sh` and the archived agent-sop guide are deleted; `validate-state-transitions.sh` loses its drift and replication modes and stays as ship-sop's own file, with `archive-backlog.sh`.
- **Tests and CI.** The agent-sop push-gate, project-type, dispatcher, library and installer fixtures are ported to `tests/push-gate.sh` and `tests/install-hooks.sh`, with the `SUITE_DONE` early-stop guard; retired-hook cases are left out. `tests/receipt-integration.sh` uses the shipped library and `tests/receipt-lib-check.sh` replaces the agent-sop compatibility test (no minimum agent-sop). CI runs every suite with no agent-sop checkout, shellchecks the hooks as first-party code, and fails if a script or test names an external checkout.
- **Docs.** The README describes only what ship-sop does, with an optional working-rules snippet; CLAUDE.md, AGENTS.md, the docs index, the feature map and the commands and skills point at the new paths.

**Acceptance criteria:**
- Every `tests/*.sh` passes with no `AGENT_SOP_SOURCE` set and no agent-sop checkout readable
- `shellcheck -S warning` passes on `setup.sh`, `scripts/`, `scripts/hooks/` and `tests/`
- `git grep agent-sop` outside history lists only the migration code, its data and its tests, and the CI guard
- A fresh install registers exactly one push gate at the new path, installs both reviewer agents, refuses an uncovered push in an auto-mode project, and `--uninstall` removes the registration
- An existing agent-sop-style install ends with exactly one registration, at the new path, and its pristine old copies removed

**Review round 1 (11 Oct 2026):** silent-failure-hunter BLOCK, security and code PASS with MEDIUMs. Fixed on the branch, each with a fixture: the gate refuses when a library function is missing, the gate check fails, `cwd` is absent or unusable, `HEAD` is unreadable or the review range cannot be computed; `--check-lib` covers the gate's functions and Claude setup exits non-zero on failure; the installer touches only entries holding a matching command, names a non-array event, refuses (and keeps old copies) when another gate registration remains, never treats an unhashable copy as unedited, and writes settings beside the target with its mode kept; the bypass applies only when every push carries it, and a failed bypass-log write warns; the installed gate is exercised end to end for Claude and Codex; setup reports the Codex `hooks` feature; `AGENT_SOP_*` environment variables are renamed `SHIP_SOP_*`.

**Source:** operator decision 11 Oct 2026 (fold agent-sop into ship-sop; archive agent-sop afterwards).

**Outcome:** ship-sop installs and registers the push gate and the two gate reviewers itself; CI and every suite run without agent-sop. Review took one blocking round (silent-failure: a missing library function let a push through) and three fix commits; the gate now refuses on any check it cannot complete.

review: docs/reviews/20261011-230251-ship-auto.md


---

### P42 - Setup updates unedited installed commands and the receipt tool

`[SHIPPED - 2026-10-11] [Bug]`

Found switching a real machine over after P41: setup copied the Claude slash commands and `scripts/ship-receipt.sh` only when missing, so a machine set up earlier kept copies that point at the old `hooks/agent-sop/` path. `/ship`, `/ship-on`, `/ship-off`, `/release` and the receipt tool would then fail. Agents already used shipped-version matching; commands and the receipt tool now do the same.

**Acceptance criteria:**
- `scripts/shipped-user-files.txt` (renamed from `shipped-agents.txt`) lists every shipped version of each agent, command and the receipt tool; `tests/install-agents.sh` fails when a current one is missing
- Install updates an unedited earlier command or receipt tool and keeps an edited one; uninstall removes only unedited ones
- The upgrade test fails against the previous `setup.sh`

review: docs/reviews/20261011-231347-ship-auto.md


---

### P43 - Block only on findings with user or data impact

`[SHIPPED - 2026-10-12] [Iteration]`

Matt chose option 2 from P40 (11 Oct 2026): cut the gate's cost without dropping the blocks that matter. P40 found 8 to 10 of 29 sampled blocks were correct but minor, each costing a fix round and a re-review, and three security blocks fired on HIGH below edward's CRITICAL threshold because `/ship` told the session to fix every HIGH and never told reviewers their threshold. Reviewers now get their `block_on` and one shared rule: CRITICAL or HIGH only for user or data impact. Only findings at or above the threshold block, count as a block round or get fixed; the rest are report notes. On review, a security HIGH under the new rule means a real weakness, so Matt set security-reviewer's default `block_on` to HIGH (12 Oct 2026); code and silent-failure stay at HIGH. The saving is an estimate from the P40 sample, not a measurement.

**Acceptance criteria:**
- `/ship` (Claude) and `codex-review.sh` (Codex) carry the same severity rule; a test fails if they differ
- Each reviewer is told its threshold (Codex: `--block-on`, validated); an invalid threshold is refused
- `/ship` and the Codex skill fix and count only at-or-above-threshold findings

review: docs/reviews/20261012-064609-ship-auto.md

### P44 - Bypass hygiene, live cost and test-catch recording, archive old history

`[SHIPPED - 2026-10-12] [Iteration]`

Matt approved three changes on 12 Oct 2026. First, an independent review found that the push gate's refusal, which Claude Code shows to the model, gave the agent the exact bypass command. The refusal now says nothing about a bypass; the mechanism and its log are unchanged and documented for people in the README; `/ship` and the Codex skill carry the rule never to use the gate's user-only override unless the user explicitly instructs it in that session; and each ship report lists every bypass since the previous receipt. Second, the gate's value is to be measured on live work (`docs/build-plans/2026-10-12-gate-value.md`), so receipts now record Claude reviewer usage from the task-completion notifications and, for each blocked round, the project's test result at the blocked commit (`block_tests`); `receipt-totals.sh` summarises both. Third, records from before ship-sop became self-contained move to `archive/`.

**Acceptance criteria:**
- No push-gate refusal, library demand or agent-loaded instruction names the override variable; a fixture checks every refusal in the suite. The bypass still works and is logged, one line per bypass
- `sop_bypasses_since_receipt` resolves the git toplevel and lists bypass-log entries at or after the newest valid receipt committed at HEAD (the earlier of its `written_at` and its commit time, ignoring future times), masked and stripped of control bytes, or `none`; any failure prints `unreadable:`. Both workflows put it in the report as a `Bypasses:` line
- The validator accepts the Claude and Codex usage shapes and null, and rejects malformed ones; Claude tokens count each agent instance's last cumulative figure once
- `block_tests` entries are validated; a receipt with `written_at` and a blocked round must carry the field; older receipts stay valid
- `receipt-totals.sh` reports tokens, reviewer minutes (n/a when nothing is costed), block rounds per change, block-test results and blocked changes with no record

**Review round 1 (12 Oct 2026, on `efd29ea`):** security, code and silent-failure PASS with MEDIUMs on the bypass listing (subdirectory root, forgeable cutoff, credential masking, control characters), the workflow order and block_tests completeness. All fixed on the branch, each with a fixture.
- The gate-value plan describes the approved live-measurement design
- `docs/recent-work/`, `docs/agent-memory/`, `docs/agent-memory.md`, `docs/RECENT-WORK.md` and the historical build plans are in `archive/` with history kept; no live document points at a moved path

review: docs/reviews/20261012-110353-ship-auto.md

### P45 - Receipt tool enforces the live-measurement record

`[SHIPPED - 2026-10-12] [Bug]`

P44 added live measurement, but the first 6 real receipts from Edward on 12 Oct 2026 all lack it: every reviewer's usage is null, no companion report has a `Bypasses:` line, and blocked rounds have `block_tests` recorded as NOT_AVAILABLE after the fact ("logs overwritten") rather than a test run at the blocked commit before fixing. Edward's sessions do not run `/ship`; they answer the push gate's refusal, which gave reviewers their threshold and severity rule but said nothing about usage, bypasses or block tests, and the receipt tool enforced only that `block_tests` was present. Instructions alone are not reliable, so the tool now enforces what the measurement needs.

Decisions: the Claude demand reads "Run /ship (it covers reviewers, usage and block tests)" without "and the bypass listing", because P44's fixtures forbid any mention of a bypass in a refusal. An `unreadable:` bypass listing is stored in the receipt as that string (the listing ran and says the log cannot be read); only a missing function, a non-zero exit or empty output is refused. `--usage-unavailable` with every usage present is refused, so a `usage_note` always explains a real gap. Codex keeps optional usage because `codex-usage.sh` prints null when a run lacked telemetry.

**Acceptance criteria:**
- The push gate's demand points at the full workflow (Claude: "Run /ship"; Codex: "Use the ship skill"), keeps the reviewer list, thresholds and existing rules, and names the two steps sessions skip: record each reviewer's token and duration figures as they arrive, and run the tests at a blocked commit before fixing it. It names no bypass
- Under Claude, `ship-receipt.sh` refuses a receipt in which any reviewer's usage is null or absent unless `--usage-unavailable "<reason>"` is given, and stores the reason as `usage_note`; Codex behaviour is unchanged
- `ship-receipt.sh` runs `sop_bypasses_since_receipt` from the repository toplevel and stores the result as `bypasses` (`none` becomes `[]`); a missing function, failure or empty output is INCOMPLETE. `/ship` and the Codex skill copy the receipt's `bypasses` into the `Bypasses:` line
- The validator accepts receipts without `usage_note` or `bypasses`, and rejects a `usage_note` that is not a non-empty string and a `bypasses` that is not an array of strings
- `/ship`, the skill and the demand say NOT_AVAILABLE is only for a project with no runnable suite
- `receipt-totals.sh` counts receipts carrying `usage_note`, recorded bypass entries and unreadable listings
- The gate-value plan says the measurement window restarts when P45 is installed

**Review round 1 (12 Oct 2026, on `afc0166`):** security, code and silent-failure PASS with MEDIUM and LOW notes, fixed on the branch, each with a fixture. Bypass entries now land in a committed receipt, so the listing also masks header-style secrets, `--flag value` secrets, JSON `"token":"..."` pairs and well-known token prefixes, strips bidi overrides and U+2028/2029, and cuts each entry to 300 characters. `usage_note` is stripped of control characters and must be 10 to 500 characters; the tool records `usage_unavailable` (reviewers with null usage) itself; a Claude run with 0 tokens or 0 duration is rejected. An unreadable bypass log prints a warning and the workflows say so in the report. `receipt-totals.sh` separates bypass records, entries and unreadable listings (n/a without the field) and shows usage notes against receipts. The plan's window starts at P45 and its limits name Codex null usage and self-reported block tests.

review: docs/reviews/20261012-154630-ship-auto.md

### P46 - Tidy linked worktrees at the end of each ship

`[SHIPPED - 2026-10-22] [Feature]`

Matt asked on 22 Oct 2026 that ship-sop keep worktrees well managed, since much work is not merged to main from a worktree. ship-sop had no worktree lifecycle; agent-sop's claim hook was not carried over. On 22 Oct 2026 Edward had 170 linked worktrees (159 detached, 34 with uncommitted changes, 6.6 GB under `.claude/worktrees`). Matt chose automatic removal of safe worktrees with a report of the rest.

Decisions: "safe" is clean (untracked files count; ignored files count unless the ignored path's last component is in a short regenerable list such as `node_modules`, `dist`, `.venv`, because `git worktree remove` deletes ignored files and a `.env` or local database may be the only copy), no paused rebase, merge, cherry-pick, revert or bisect, HEAD contained in a branch, remote branch or tag (a branch worktree: its tip is an ancestor of the remote-tracking default branch; without one, branch worktrees are review), not locked, not a worktree containing the caller's directory, and idle for at least 24 hours by the worktree's HEAD and reflog. An age that cannot be read is review. The index is excluded from the age because `git status` rewrites it; the tool's own status call uses `--no-optional-locks`. A clean worktree a session has held open for over 24 hours without committing is not detected; this is documented. The worktree list is read NUL-delimited. The tidy runs before the reply on every ship, whatever the verdict, and its failure never changes the verdict. A branch merged by squash is not an ancestor and stays in review, with a hint when its remote branch is gone; checking GitHub PR state was left out to keep the tool offline. Removal uses `git worktree remove` without `--force`, so git refuses a worktree that changed after classification. Remote branches are not deleted. No session-start warning: `/ship` runs on every code push and covers it.

**Acceptance criteria:**
- `scripts/worktree-tidy.sh [--apply] [--min-age-hours N] [repo]` prints one line per linked worktree (safe, review, gone, keep) and a `Worktrees:` summary; without `--apply` it changes nothing
- `--apply` removes safe worktrees, deletes a removed worktree's branch only after re-checking it is on the default branch, and prunes deleted folders; review and keep entries are untouched
- setup installs it for Claude and Codex and uninstall removes it; `scripts/shipped-user-files.txt` lists its blob
- `/ship` and the Codex skill run it with `--apply` after the reply's findings and copy the summary and every review line into the reply
- `tests/worktree-tidy.sh` covers each category, ignored `.env` versus `node_modules`, a paused bisect, the caller's worktree from a subfolder, an unreadable age, no remote default branch, a fresh index on an idle worktree, apply, a repeat run and usage errors; the install tests check both runtimes install and remove it

**Review round 1 (22 Oct 2026, on `4e6e19a`):** security, code and silent-failure each BLOCK on the same class: ignored files (`.env`, local databases) were deleted with a "clean" worktree, and an unreadable age defaulted to 0 and read as idle. Tests passed at the blocked commit. Fixed with the ignored-file check and age-unreadable review above; the MEDIUM findings (paused operations, local default fallback, caller guard, unguarded git calls, locked-and-gone, branch-delete reporting, step order, failure wording) were fixed in the same pass.

**Review round 2 (22 Oct 2026, on `4f5a170`):** all three PASS. Notes left open: a status over about 64KB can label a dirty worktree safe (git still refuses the removal), regenerable names match at any depth, and a long-held clean worktree is not detected.

review: docs/reviews/20261022-160537-ship-auto.md

---

## Shipped Archive

*Items below are shipped or verified. Never removed. Move items here when Backlog.md exceeds ~2,000 lines and items are older than 90 days.*

(Empty — all P-numbered items above are still in the recent block.)

### P28 — Native Codex support alongside Claude

`[SHIPPED - 2026-09-08] [Feature]`

Provide runtime-aware installation and updates, native Codex skills and reviewers,
and one shared automatic review path. Preserve Claude support and project-owned files.

Acceptance criteria:
- `--runtime claude|codex|both` installs the selected integration without cross-runtime writes.
- Codex hooks load context, continue on missing records and block uncovered pushes.
- Native workflows have valid paths and enforce reviewer isolation.
- Installation/update/uninstall fixtures and existing regression checks pass.

Implementation complete locally (2026-09-08). Existing and new fixtures pass.
review: docs/reviews/20260908-153509-ship-auto.md
Merged to main in PR #13 (`451ec44`) on 2026-09-08.

### P29 — Preserve shared instruction symlinks during priority refresh

`[OPEN] [Iteration]`

The shared `scripts/refresh-priorities.sh` can replace an AGENTS.md symlink rather
than updating its target. Fix upstream under agent-sop P108 and sync the replica.
Source: P28 configured review, 2026-09-08. This is below the configured HIGH gate threshold.

### P30 — Port shared enforcement surfaces to Codex

`[SHIPPED - 2026-09-08] [Refactor]`

Declared enforcement scope accompanying the Codex runtime feature: runtime-aware
validator configuration and replication paths, AGENTS/native-skill review triggers,
and the hook adapters. In ship-sop, also replace the obsolete positive project-hook
CI assertion with unified-hook installation fixtures. Policy thresholds remain unchanged.

This is an explicit enforcement work item under security rule 11, separated from
the feature declaration for auditability. Independent configured reviewers assess
these changes; passing output from a changed validator is not the sole evidence.
The pre-port validator is also run against the final Backlog transitions.

review: docs/reviews/20260908-153509-ship-auto.md
Merged to main in PR #13 (`451ec44`) on 2026-09-08.

### P31 — Clear empty Codex installation ownership records

`[OPEN] [Iteration]`

After removing Codex assets, the empty `ship-sop.install.json` can still make a
later Claude uninstall preserve shared config/artifacts. Check remaining owned
assets rather than file existence, with a Codex-then-Claude removal fixture.
Source: P28 independent review, 2026-09-08; MEDIUM, below the configured threshold.

---

## Archived items

Closed more than 90 days ago; full entries in `docs/backlog-archive.md`, moved verbatim by `scripts/archive-backlog.sh`.

- P1 — archived: Initial scaffold (3 reviewer agents, 4 slash commands, hook, config, setup) (see docs/backlog-archive.md)
- P2 — archived: Dogfood self-install + post-install rough-edge fixes (see docs/backlog-archive.md)
- P3 — archived: End-to-end dogfood of the auto-mode pipeline + leftover-rename fix (see docs/backlog-archive.md)
- P4 — archived: Docs-only detection in the SessionStop hook (see docs/backlog-archive.md)
- P5 — archived: Install agent-sop on ship-sop for retrospective record (see docs/backlog-archive.md)
- P6 — archived: Multi-tenant isolation section in compliance-reviewer + lawful-basis severity bump (see docs/backlog-archive.md)
- P7 — archived: /audit command + whole-codebase mode in compliance-reviewer (see docs/backlog-archive.md)
- P9 — archived: Default reviewer set expansion (code-reviewer + silent-failure-hunter + pr-test-analyzer) (see docs/backlog-archive.md)
- P10 — archived: `setup.sh --uninstall` for clean removal (see docs/backlog-archive.md)
- P11 — archived: Phase 2: Hardening pass (diagnostics, schema warn, retention, drift, declutter) (see docs/backlog-archive.md)


### P32 - Verified receipts, reviewer telemetry and concise workflow

`[SHIPPED - 2026-09-24] [Refactor]`

Merged to main via PR #15 (5fe6e61) on 2026-09-24 with agent-sop P110 (PR #29, ac93962); CI green on main in both repositories.

review: docs/reviews/20260908-hardening-ship-auto.md

Generate validated structured review receipts; align Claude and Codex review decisions; retain bounded reviewer usage evidence; remove duplicated session instructions and document the shared gate contract.

Authorised by the user following the 2026-09-08 full review. This explicitly changes enforcement policy. Acceptance: discriminating regression fixtures, complete existing suites, independent isolated review, preserved consumer customisations and documented migration.

Implemented and verified locally on `fix/review-continuity-hardening`. Installation, timeout, receipt contract and real cross-package tests pass. Full-range findings were corrected and all three configured reviewers passed the pinned correction range. Validated receipt recorded. Both runtime integrations updated with customisations preserved. Remains IN PROGRESS until merge; publication and the comparison-pilot budget are separate decisions.
