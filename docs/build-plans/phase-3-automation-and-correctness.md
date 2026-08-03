# Phase 3 — Automation and correctness

**Status:** Planned 2026-08-03
**Trigger:** Full-project review (`docs/reviews/2026-08-03_solo_full-project-review.md`) — 7 reviewer dimensions, adversarially verified, 48 findings. Plus an operator requirement: ship-sop must run automatically, without a slash command being typed each session.

---

## Scope

Two things, and they are the same thing.

The review found that the `.claude/settings.json` entry `setup.sh` writes does not match Claude Code's hook schema, so auto-mode has never fired in any project. That is why the pipeline has had to be invoked by hand. **The automation requirement and the correctness backlog are not competing priorities — the top correctness bug is the reason automation does not work.**

Phase 3 closes both:

1. Make the SessionStop hook actually fire, and close the loop so the gates it schedules get dispatched without anyone typing anything.
2. Fix the correctness defects that would otherwise make an automatic pipeline confidently wrong — a gate that did not run must never look like a gate that passed.

Out of scope: new gate types, new reviewer agents, the `store-policy-reviewer` in P8.

---

## The automation architecture

### The constraint

`docs/agent-memory/gotchas/2026-04-25_solo_stop-hooks-cant-invoke-agents.md` still holds: **hooks cannot invoke `@agent`**. They are plain shell. Every automation path is therefore two-step — a hook injects context, a model turn dispatches the gates. Any design that forgets this is unbuildable.

### Trigger surfaces

| Surface | Executed by | Fires with no typing | Can dispatch gates | Can block |
|---|---|---|---|---|
| SessionStop hook | harness | Yes | No — writes directive | No |
| SessionStart hook | harness | Yes | No — injects directive into opening context | No |
| PreToolUse hook on `git push` / `gh pr create` | harness | Yes | No | **Yes — `exit 1`** |
| `/restart-sop` | model | Only when typed | Yes | n/a |
| `/ship` | model | Only when typed | Yes | n/a |

### The design

**Primary path — no typing at all.** Session N stops, the Stop hook writes the directive. Session N+1 starts, a new SessionStart hook verifies the directive's integrity and freshness and injects "dispatch these gates now" into the opening context. The model dispatches. This closes the loop the current design leaves open, and it is strictly more reliable than any command because the harness runs it whether or not anyone remembers.

**Backstop path — `/restart-sop`.** The same pickup, for when the command is typed anyway. It must be idempotent with the primary path, or a session that starts and then runs `/restart-sop` dispatches six gate agents twice.

**Enforcement path — the push gate.** A `PreToolUse` hook on `git push` and `gh pr create` is the only surface that can actually *stop* something. This is the real pre-merge boundary. It cannot run the gates itself, but it can refuse the push when the last gate run does not cover `HEAD`, and say so. This is what turns ship-sop from a reporter into a gate.

**Deterministic gates move into the hook.** shellcheck, `jq empty`, and a staged-secret scan need no model. Running them inside the hook makes them instant, free, and genuinely blocking. The model gates stay on the directive path. This split is the single biggest improvement available to the pipeline's cost profile and its trustworthiness: a deterministic gate cannot be talked out of a finding.

### Where the `/restart-sop` step lives

`/restart-sop` belongs to agent-sop and is installed user-scope. Under `CLAUDE.md` rule 8 it is hands-off from this repo. The step therefore **ships in the agent-sop repo**, guarded by a `ship-sop.config.json` existence check, and reaches this project through `/update-agent-sop`. ship-sop must not patch it downstream — a downstream edit would be silently reverted by the next sync, which is exactly the class of bug this phase exists to remove.

This makes Batch 3.3 the one batch with a cross-repo dependency. agent-sop is under active development, so land the ship-sop side first and treat the agent-sop step as a follow-up PR there.

### State machine

The current throttle records "the hook fired". It must record "the gates ran".

```
        Stop hook                 SessionStart / restart-sop / ship
  none ──────────► pending ──────────────────────────────────► consumed
         writes            dispatches gates, then deletes the
      directive+sha        directive pair and stamps .last-gated-sha

  Every hook run clears a stale pair before writing a new one.
  The diff-hash stamp is written at gate completion, never at emission.
```

Consequence: an interrupted turn leaves the directive in place, so the next session picks it up instead of the commit going permanently ungated.

---

## Locked decisions

- **[LOCKED]** SessionStart hook is the primary automation path; `/restart-sop` is a backstop, not the mechanism. A command the operator has to remember is not automation. Both share one idempotent pickup routine keyed on the consumed marker.

- **[LOCKED]** The `/restart-sop` step ships in the agent-sop repo and arrives via `/update-agent-sop`. No downstream edit to a pristine replica, per `CLAUDE.md` rule 8.

- **[LOCKED]** Deterministic checks (shellcheck, `jq empty`, staged-secret scan) run inside the hook, not as model gates. Model gates are reserved for judgement. Deterministic checks may hard-block; they cost nothing and cannot be reasoned past.

- **[LOCKED]** A gate that did not run is reported as MISSING, never as a pass. This applies to an uninstalled agent, an agent that returns nothing, and an agent whose output carries no parseable severity. Silence is never success.

- **[LOCKED]** The nested settings shape is written everywhere, and existing flat entries are migrated in place rather than duplicated. Install is idempotent today and must stay so.

- **[LOCKED]** The push gate refuses on "no gate run covers `HEAD`", not on "findings exist". Findings are the model's call; coverage is a deterministic fact a hook can check. An override env var is provided and is recorded in the report, so bypasses are greppable.

- **[LOCKED]** Automatic dispatch fires only when a pending directive exists **and** its recorded range still ends at the current `HEAD`. No pending directive means no gate spend. This is the cost control, and it is why Batch 3.5's staleness fix blocks the automation being turned on by default.

---

## Batches

Ordered so nothing blocks on later work. Each is one PR.

### Batch 3.1 — Make the hook fire `[P14]`
The bug that makes everything else moot.

- Emit the nested `{"matcher": "", "hooks": [{"type": "command", "command": "..."}]}` shape at all four write sites in `setup.sh` (`:455-463`, `:472`, `:477`) and in this repo's `.claude/settings.json`.
- Fix the three selectors that assume the flat shape or they silently no-op: idempotency probe `setup.sh:468`, uninstall probe `:260`, uninstall delete `:263`.
- Migration branch: rewrite an existing flat entry in place, do not append a second one.
- Post-install assertion that hard-fails if `jq -e '[.hooks.Stop[]?.hooks[]?.command] | index("scripts/auto-ship-hook.sh")'` does not match.
- Repair this repo's own install so the dogfood is live.
- **Acceptance:** end a real session with a >10-line diff, confirm `.ship/.last-auto-fire` advances without anyone running the script by hand.

**`hst-tracker` repair deferred to after Batch 3.5.** Turning auto-mode back on there would start firing the *current* hook, which still writes a literal `HEAD` for its diff range and stamps the throttle at emission rather than completion. Repairing it now would replace a dead gate with a confidently-wrong one on the repo that matters most. The install is dead today and will keep being dead for a few more batches; that is the safer of the two states. Tracked in the phase Deploy Checklist, not here.

### Batch 3.2 — Stop the installer causing damage `[P15]`
Cheap, and every later batch is safer for it.

- `skip = 2` → `skip = 1` in the `.gitignore` awk at `setup.sh:280` and the copy-pasted fallback at `README.md:303`. Currently eats one user line past the block.
- `pwd -P` at `setup.sh:32` and `:92`, plus an `[ "$src" -ef "$dest" ]` guard in `remove_if_unmodified` so a symlinked invocation cannot delete ship-sop's own source.
- Delete the `/ship-on` wiring snippet at `ship-on.md:20` — it replaces `.hooks.Stop` wholesale and writes a 0-byte `settings.json` when the file is absent. Point at `setup.sh`, which already does this correctly.
- Minimal CI: shellcheck on `setup.sh` and `scripts/*.sh`, `jq empty` on both configs. Ten lines, and it is the first automated check this repo has ever had.
- **Acceptance:** install, append a sentinel line to `.gitignore`, uninstall, assert the sentinel survives.

### Batch 3.3 — Close the automation loop `[P16]`
The operator requirement. Depends on 3.1.

- New SessionStart hook, installed by `setup.sh` alongside the Stop hook: verify sidecar, verify freshness, inject the directive pointer into the opening context. Silent when there is nothing pending.
- One shared pickup routine with a consumed marker, so SessionStart and `/restart-sop` cannot double-dispatch.
- Directive lifecycle: delete the pair on consumption; clear a stale pair at the top of every hook run, immediately after `mkdir -p "$ROOT/.ship"` at `:200`.
- `--no-session-start` install flag for anyone who wants the Stop hook only.
- **Follow-up PR in agent-sop:** add a ship-sop pickup step to `restart-sop.md`, guarded on `ship-sop.config.json` existing. Then `/update-agent-sop` here.
- **Acceptance:** end a session with a real diff, start a new one, confirm gates dispatch with nothing typed. Then run `/restart-sop` in the same session and confirm it does not dispatch a second time.

### Batch 3.4 — Make `/ship` real `[P17]`
`/ship` currently runs 4 of 7 gates. After 3.3 it is the exception path, but it is still the path used before opening a PR.

- Replace the hardcoded Gate 2/3/4 sections with the config enumeration the hook already does correctly at `auto-ship-hook.sh:257-260`.
- Read `block_on` per agent. It is quoted at `ship.md:64` and `:68` and hardcoded to CRITICAL at `:108`, `:117`, `:119`, `:128`, so a configured `HIGH` is currently ignored.
- Generate `<stamp>` once per run — it is referenced six times and generated nowhere.
- Header line `Gates dispatched: N of M enabled`, so a short gate list is visible rather than silent.
- Gate-completion contract: presence-check each agent file before dispatch; the orchestrator persists each agent's reply itself, since four of six gate agents are read-only and cannot write the artifact `ship.md:67` uses as its completion test; normalise severity, with INCOMPLETE as the fallback.
- **Acceptance:** `/ship` on a diff with a known swallowed exception reports a `silent-failure-hunter` row. Set `security-reviewer.block_on: "HIGH"` and confirm a HIGH blocks.

### Batch 3.5 — Fix the hook state machine `[P18]`
Blocks turning automatic dispatch on by default, because the staleness bug would gate the wrong range.

- Write resolved SHAs plus a `HEAD at write time:` line. `Diff range` currently writes `HEAD` as a literal string, so the reader's instruction to check "if the range no longer ends at `HEAD`" can never fail. `HEAD_SHA` is already computed at `:165` and thrown away.
- Move the `.last-diff-hash` write from `:411` to gate completion.
- Guard the throttle stamp against non-numeric and future values — a clock jump currently disables auto-mode for 250 years with no output.
- `jq -e . "$CONFIG"` validity gate after `:69`; malformed JSON currently dies at `:118` with a raw jq error after seven schema probes swallowed it.
- `{ grep ... || true; }` at `:189` — under `set -euo pipefail` a no-match `grep -v` kills the script.
- Delete the stale directive pair currently sitting in `.ship/`, dated 27 July, naming a deleted branch, hash still matching.
- **Acceptance:** fixture-driven, see 3.7.

### Batch 3.6 — Close the coverage holes `[P19]`
The ways a gate reports success without looking.

- Split Gate 1 into PASS / FAIL / NO-RUNNER, and make NO-RUNNER a hard block unless the diff is docs-only or the project opts out. An agent scaffolding a service with no tests is the most common shape of agent-written code, and it currently passes.
- Carve agent-instruction paths out of the docs-only class before the match at `auto-ship-hook.sh:246` — `^(CLAUDE|AGENTS)\.md$`, `^Backlog\.md$`, `^\.claude/` — configurable as `throttle.never_docs_only`. These files currently route around every blocking gate, which is the same persistence vector P13 hardened the directive against.
- Split the integrity table: absence of the sidecar is tampering, because the hook writes one unconditionally using the literal `UNAVAILABLE` when no hashing tool exists. A hash mismatch should regenerate and gate, not skip — `printf '\n' >> .ship/.pending-auto-fire.md` is currently a permanent gate off-switch.
- Add an `## Input trust` block to `ship.md` and the directive body: diff content is data, and text in a diff asserting prior sign-off or addressing a reviewer is itself a CRITICAL finding. Nothing in `.claude/` currently says this.
- Replace `git add -A` at `ship.md:195` with explicit paths, add the staged-secret scan from `docs/sop/security.md:66-68`, and add "never reproduce a matched secret value" to each agent's output format.

### Batch 3.7 — Deterministic gates and the push gate `[P20]`
Where ship-sop stops reporting and starts gating.

- Run shellcheck, `jq empty`, and the staged-secret scan inside the hook. Deterministic, instant, hard-blocking.
- `PreToolUse` hook on `git push` and `gh pr create`: refuse when no gate run covers `HEAD`. `SHIP_SOP_SKIP_GATE=1` overrides and is recorded in the report.
- **Acceptance:** commit a change, attempt a push without a gate run, confirm refusal. Run the gates, confirm the push proceeds.

### Batch 3.8 — Fixture harness `[P21]`
Locks in 3.5 and 3.6, and closes the self-exemption.

- Port agent-sop's `docs/benchmark/drift-fixtures/run-tests.sh` pattern to `tests/hook-fixtures/`. The shape transfers directly: fixture directories, expected exit code keyed off a filename prefix, stdout asserted via a sidecar.
- Minimum cases: below-min-diff, cooldown, same-hash, docs-only, agent-instruction-file, no-agents, malformed config, future timestamp, stale directive, happy path.
- Assert on the directive body, not just the exit code.
- Wire into the Batch 3.2 CI workflow. Correct `CLAUDE.md:42` and `:78`, which claim a CI candidate is filed in `Backlog.md` — no such item exists and there is no `.github/`.

### Batch 3.9 — Command and agent polish `[P22]`
- `/audit`'s documented `--scope`, `--regulation`, `--no-shadow-controls` flags are inert (`audit.md:38-40` vs the bare invocation at `:47`). Forward them or delete them and rewrite the timeout guidance at `:101` around per-directory runs.
- `/release` has no turn boundary: `:75` says "halt" but never defines confirmation, and `:79-100` tags, pushes and publishes unguarded. Add an explicit stop, and fix `--no-publish` ordering — it commits `chore(release):` to main before the flag is checked.
- `compliance-reviewer` scores health data CRITICAL at `:78` and MEDIUM at `:104` while `:100` and `:350` say it does not enforce HIPAA. Score it once, and make BLOCK depend on a regulation the applicability scan marked applicable.
- Backlog auto-file needs dedup and cross-branch P-number reservation (`compliance-reviewer.md:271`); `diagram-builder`'s hand-edit guard tests for a marker its own templates never write (`:203` vs `:91`, `:147`); `release-notes-writer` can publish an abandoned branch's feature because nothing corroborates a `[SHIPPED]` item against a commit (`:68`).

### Batch 3.10 — Drift and boundary `[P23]`
- `scripts/check-agent-sop-drift.sh`, warn-only on stderr from the hook. `.claude/agent-sop.config.json:4-5` has `update_reminder: "weekly"` and `last_update_check: 2026-07-27`; nothing reads either.
- `/update-agent-sop` to refresh the six stale replicas. `validate-state-transitions.sh` is 602 lines here against 783 upstream and is running a pre-fix copy of a silent-failure bug in `resolve_before()`.
- Decide the validator question: vendor upstream's fixtures alongside it, or stop replicating it and invoke via `.local_path`. Replicating a 600-line executable without its tests is the worst of both.
- Backfill P12/P13 into `docs/feature-map.md` (still reads "Last updated: 2026-04-26 (P10)") and the Phase 2 Batch Log. Fix the `CLAUDE.md:34` pointer to a README section deleted in P11, and the `doc-builder` leftovers at `ship-on.md:6`, `ship.md:195`, `docs/templates/ship-sop.schema.json:30`. Sync the root config to its template — it is missing the `artifacts` block, which also makes `--uninstall` refuse to remove it as "locally modified".
- Artifact naming disagrees three ways: the hook writes `${STAMP}-ship-auto.md` (`:293`), `ship.md:188` says `<stamp>-ship-report.md`, `README.md:178-185` shows a seven-file per-gate tree. Pick one.
- README install footprint understates by three items (`:152-157` vs `:265`, which contradicts it), and `--force` is described as user-scope only when it also deletes project-scope files.
- **Then:** run the full gate set against a real code diff — the Phase 3 changes are the natural subject — and commit the artifact. If the gates find nothing on a diff that demonstrably contained defects, that is the signal to cut `code-reviewer` from the defaults as redundant with agent-sop's Step 1b.

---

## Batch Log

- **2026-08-03: Batch 3.1 shipped (P14).** SessionStop hook entry rewritten to the nested `{"matcher","hooks":[{"type","command"}]}` shape at all four write sites, plus this repo's own `.claude/settings.json`. The three flat-shape selectors replaced with three shared constants (`HOOK_NESTED_PROBE`, `HOOK_LEGACY_PROBE`, `HOOK_ENTRY_EXAMPLE`) so install and uninstall read the same definition. Pre-P14 flat entries migrate in place rather than gaining a duplicate; uninstall removes both shapes, strips only our command from a nested entry, drops entries left empty, and leaves other hooks in the same array untouched. Post-install assertion exits non-zero when the entry is not reachable via the nested probe. README manual-fallback jq updated to match. Verified against five cases on throwaway repos: fresh install, re-run idempotency, legacy migration alongside a user hook, uninstall of each shape, and the assertion rejecting the flat shape while accepting the nested one. `hst-tracker` repair deliberately deferred to after Batch 3.5 — see the note in Batch 3.1 above.

---

## Backlog mapping

| Batch | P | Type | Notes |
|---|---|---|---|
| 3.1 | P14 | `[Bug]` | Blocks every other batch |
| 3.2 | P15 | `[Bug]` | |
| 3.3 | P16 | `[Feature]` | Cross-repo follow-up in agent-sop |
| 3.4 | P17 | `[Bug]` | |
| 3.5 | P18 | `[Bug]` | Blocks default-on automation |
| 3.6 | P19 | `[Bug]` | |
| 3.7 | P20 | `[Feature]` | |
| 3.8 | P21 | `[Feature]` | |
| 3.9 | P22 | `[Bug]` | Splittable if it grows |
| 3.10 | P23 | `[Refactor]` | |

---

## Deploy Checklist

- [ ] `bash -n` clean on `setup.sh` and `scripts/*.sh`
- [ ] shellcheck clean, wired into CI
- [ ] `jq empty` passes on `ship-sop.config.json` and `docs/templates/ship-sop.config.json`
- [ ] Fixture suite green
- [ ] Auto-fire verified end to end with nothing typed: session ends, new session starts, gates dispatch
- [ ] Double-dispatch verified impossible: SessionStart pickup then `/restart-sop` in the same session
- [ ] Push gate verified: refuses an ungated `HEAD`, allows a gated one, records an override
- [ ] `/ship` dispatches every enabled agent and honours a non-default `block_on`
- [ ] A deliberately uninstalled agent reports MISSING, not pass
- [ ] `hst-tracker` install repaired and confirmed firing
- [ ] No agent-sop pristine replicas modified (`git status -s` before the 3.10 sync)
- [ ] `Backlog.md`, `docs/feature-map.md`, Batch Log, `docs/recent-work/` updated per batch

---

## Open Questions

- Should automatic dispatch be default-on for new installs, or opt-in for the first release after Phase 3? [UNRESOLVED — leaning opt-in until the fixture suite has run against real sessions for a fortnight. The failure mode of default-on is a surprise token bill, which is the kind of thing that gets a tool uninstalled.]
- Should the push gate be part of the default install or a separate `--with-push-gate` flag? [UNRESOLVED — it is the highest-value enforcement in the phase and the most likely to annoy. Suggest shipping it flag-gated and promoting it to default once it has been lived with.]
- Once deterministic gates run in the hook, is `code-reviewer` still worth its cost given agent-sop's Step 1b already runs one reviewer turn per session? [UNRESOLVED — deliberately deferred to the 3.10 dogfood, which is designed to answer it with evidence rather than argument.]
- Does the SessionStart pickup need a diff-size floor of its own, separate from the Stop hook's `min_diff_lines`? [UNRESOLVED — probably not, since the directive only exists if the Stop hook already cleared the floor. Revisit if pickups fire on trivial ranges.]
