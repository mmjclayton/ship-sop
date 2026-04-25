---
description: Run the ship-sop gates (tests, security, compliance, docs) against the current diff. Manual entrypoint for the same pipeline that auto-mode fires on SessionStop. Produces a single readiness report. Does not push, tag, or publish.
ship_sop_version: "2026-04-25"
---

Run the ship pipeline against the current branch's diff vs. its merge base. Each gate produces an artifact under `docs/reviews/`. Hard-blocking gates halt on failure; advisory gates surface findings and continue.

This command is the **manual entrypoint** to the same pipeline that runs automatically on SessionStop when auto-mode is enabled (`ship-sop.config.json` → `trigger.mode: "auto"`). The gates and outputs are identical; the only difference is who pulls the trigger.

## Arguments

- `--skip <gate>` — skip a single gate. Logged in the readiness report. Use only for emergencies.
- `--base <ref>` — override the diff base (default: `git merge-base origin/main HEAD`).
- `--preview-release` — also run `release-notes-writer` to preview what release notes would look like with this ship included. Off by default.

## Resolve diff range

```bash
BASE="${BASE_OVERRIDE:-$(git merge-base origin/main HEAD 2>/dev/null || git merge-base origin/master HEAD 2>/dev/null)}"
HEAD_SHA=$(git rev-parse HEAD)

if [ -z "$BASE" ] || [ "$BASE" = "$HEAD_SHA" ]; then
    echo "No diff to ship — branch matches default. Aborting."
    exit 1
fi

echo "Diff range: $BASE..HEAD"
git diff --stat "$BASE..HEAD"
```

## Detect docs-only diff

If every changed file matches `^docs/`, `\.md$`, or `^README`, declare a docs-only ship:

- Skip Gate 2 (security)
- Skip Gate 3 (compliance)
- Run Gate 4 (docs) — keeps generated docs in sync with hand-edited content
- Run Gate 1 (tests) only if a docs-aware test runner is configured (rare)

State the docs-only mode in the readiness report.

## Read config

```bash
CONFIG="${PROJECT_ROOT:-.}/ship-sop.config.json"
if [ ! -f "$CONFIG" ]; then
    CONFIG="$HOME/.claude/ship-sop.config.json"
fi
```

The config controls per-agent toggles. A gate whose agent is disabled in config is skipped with a notice. `--skip` overrides on a per-run basis.

## Pipeline gates

Run gates in order. Hard-blocking gates that fail halt the pipeline; advisory gates always continue.

### Gate 1 — Tests (hard block)

```bash
# Detect test runner
if [ -f package.json ] && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    TEST_CMD="npm test"
elif [ -f pyproject.toml ] || [ -f pytest.ini ]; then
    TEST_CMD="pytest"
elif [ -f Cargo.toml ]; then
    TEST_CMD="cargo test"
elif [ -f go.mod ]; then
    TEST_CMD="go test ./..."
else
    TEST_CMD=""
fi

if [ -n "$TEST_CMD" ]; then
    echo "Running: $TEST_CMD"
    if ! $TEST_CMD; then
        echo "Gate 1 (tests): FAIL — halting."
        exit 1
    fi
    echo "Gate 1 (tests): PASS"
else
    echo "Gate 1 (tests): no runner detected — skipped."
fi
```

If no test runner is detected, skip with a notice — don't fail. Use `--skip tests` to bypass an existing runner.

### Gate 2 — Security (hard block on CRITICAL)

Invoke `@security-reviewer` (from agent-sop, or the user's own install) on the diff.

If `security-reviewer` is unavailable, surface a notice and continue with Gate 3. ship-sop doesn't bundle a security reviewer — it composes with agent-sop's or any other.

Verdict consumed:
- `APPROVE` — proceed
- `WARNING` — proceed, surface findings
- `BLOCK` — halt (CRITICAL findings)

### Gate 3 — Compliance (hard block on CRITICAL)

Invoke `@compliance-reviewer` on the diff.

The agent writes to `docs/reviews/<stamp>-compliance.md` and auto-files HIGH/MEDIUM as `[OPEN][Bug][needs-triage]` Backlog entries (if `Backlog.md` exists).

Verdict consumed:
- `APPROVE` — proceed
- `WARNING` — proceed, surface findings
- `BLOCK` — halt (CRITICAL findings)

### Gate 4 — Diagrams + API catalog + Δ log (advisory; never blocks)

Invoke `@diagram-builder`. Always returns `APPROVE`.

Updates `docs/ARCHITECTURE.md` (Δ log), `docs/diagrams/<feature>.md` (Mermaid state + sequence diagrams), `docs/api/<service>.md` (endpoint catalog with schemas). Hand-edited docs are written alongside as `<path>.generated.md` and surfaced in the report.

Codemaps, README refresh, and broader doc maintenance are **not** in this gate — invoke `@doc-updater` separately when you need them. The split: diagram-builder runs every ship and stays narrow; doc-updater runs on-demand for bigger refreshes.

Diagram-builder writes are intended to commit alongside the code change in the same commit, not separately.

### Optional — Release notes preview

Only when `--preview-release` is passed.

Invoke `@release-notes-writer` in dry-run mode. Writes to `.ship/release-notes-preview.md`. Does not write `CHANGELOG.md` — that's `/release`'s job.

## Auto-mode vs. manual mode

When this command is invoked manually:
- Hard-blocking gate failures **halt** with non-zero exit. Operator fixes and re-runs.
- Output goes to terminal and `docs/reviews/<stamp>-ship-report.md`.

When the same pipeline runs automatically via the SessionStop hook:
- Hard-blocking gate failures **inject a strong warning into the operator's context** but do not halt the session.
- Output goes to `docs/reviews/<stamp>-ship-report.md` and a one-line summary in the model's reply.
- The operator can run `/ship` manually afterwards if they want the halt-on-fail behaviour.

This duality is deliberate: auto-mode prioritises non-disruption (you're mid-flow), manual mode prioritises strict gates (you're explicitly checking ship-readiness).

## Readiness report

```markdown
# Ship readiness

Date: YYYY-MM-DD
Branch: <current-branch>
Diff range: <BASE>..<HEAD>
Mode: manual | auto
Trigger: /ship | SessionStop hook

## Gate results

| # | Gate | Verdict | Artifact |
|---|------|---------|----------|
| 1 | Tests | PASS | (test runner output) |
| 2 | Security | APPROVE | docs/reviews/<stamp>-security.md |
| 3 | Compliance | WARNING | docs/reviews/<stamp>-compliance.md (2 Backlog entries filed) |
| 4 | Diagrams + API + Δ | APPROVE | 3 files updated |

Skipped: <list with reasons>

## Verdict: READY TO SHIP | BLOCKED | READY-WITH-OVERRIDE

## Findings summary

<Top 5 most important findings, with file:line — operator's at-a-glance view>
```

The report is also written to `docs/reviews/<stamp>-ship-report.md` for the durable audit trail.

## After /ship passes

The operator's next steps (not run by `/ship`):

```bash
# Stage and commit (including doc-builder writes)
git add -A
git commit -m "feat: <description>"

# Push and open PR
git push -u origin HEAD
gh pr create --fill
```

`/ship` deliberately does not push, commit, or open PRs. For tagged releases, run `/release` after the PR merges to main.

## Skip flag policy

`--skip <gate>` is permitted but always logged. The readiness report records:
- Which gate was skipped
- The reason (prompted; required)
- Resulting verdict: READY-WITH-OVERRIDE

PR reviewers can grep ship reports for `READY-WITH-OVERRIDE` to spot bypassed gates.

## Failure modes handled gracefully

- **No test runner detected** — Gate 1 skipped with notice.
- **No `Backlog.md`** — compliance reviewer writes review file only; doesn't auto-file Backlog entries.
- **`security-reviewer` not installed** — Gate 2 skipped with install hint pointing at agent-sop.
- **Diff is empty** — abort early before invoking any agent.
- **Config missing** — fall back to "all configured agents on, throttle defaults".
