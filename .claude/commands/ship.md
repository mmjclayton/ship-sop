---
description: Run the ship-sop gates against the current code diff — every agent enabled in ship-sop.config.json, read-only, in isolated worktrees; the session writes one report that covers HEAD. Manual entrypoint for the same run the agent-sop Stop hook demands in auto-mode. Does not push, tag, or publish.
ship_sop_version: "2026-09-05"
---

Run the ship gates on the code diff versus the default branch. Agents are read-only reviewers; the session writes the report.

Arguments: `--base <ref>` overrides the diff base. `--with <agent>` adds a disabled agent (for example `compliance-reviewer` when the diff touches a PII surface, `diagram-builder` when a route or state machine changed) for this run only.

1. **Project type.** `bash ~/.claude/scripts/hooks/agent-sop/sop-project-type.sh` — on `non-code`, stop with one line: ship-sop reviews code; declare `**Project type:** code` in CLAUDE.md to opt a scripts repository in. If the script is missing, apply the rule in agent-sop's `docs/sop/compliance-checklist.md` § Code vs Non-Code Detection by hand.
2. **Range.** `BASE=${BASE_OVERRIDE:-$(git merge-base origin/main HEAD 2>/dev/null || git merge-base origin/master HEAD)}`; `HEAD_SHA=$(git rev-parse HEAD)`. Empty or equal: nothing to ship, stop.
3. **Tests.** If the project has a runner (`package.json` test script, `pyproject.toml`, `Cargo.toml`, `go.mod`, or a fixture suite named in CLAUDE.md), run it. A failure halts the ship; a missing runner is noted, never treated as a pass.
4. **Agents.** `jq -r '.agents | to_entries[] | select(.value.enabled == true) | .key' ship-sop.config.json` (project file, else `~/.claude/ship-sop.config.json`), plus any `--with`. Launch each with the Agent tool using `isolation: "worktree"`, all at once, against `$BASE..$HEAD_SHA`, with these instructions: read-only; create nothing outside `mktemp -d`; run only existing suites; return findings inline as `[SEVERITY] file:line — issue — fix` and a one-line verdict. A prompt that names a worktree path is not isolation; the flag is.
5. **Collect.** Agents run in the background. Wait for every result. A missing result is INCOMPLETE, never a pass.
6. **Report.** Save a JSON reviewer array with name, version (definition SHA),
model (actual value or runtime-default-unresolved), verdict (PASS/BLOCK/INCOMPLETE)
and findings (severity, file, positive integer line, message). Save tests as
{"status":"PASS","evidence":"actual commands and results"}; NOT_AVAILABLE requires
a reason and FAIL cannot qualify. Run the installed tool:
`bash ~/.claude/scripts/ship-sop/ship-receipt.sh --runtime claude --base <BASE> --head <HEAD_SHA> --results <results.json> --tests <tests.json> --output docs/reviews/<stamp>-ship-auto.json`.
The validator derives threshold decisions and rejects incomplete evidence. Never
hand-edit a receipt. Write companion Markdown with the range, results, findings
and dispositions. A Covers: line is informational; only valid JSON qualifies.

7. **Reply.** CRITICAL and HIGH at the top with file:line. Fix in-diff where the fix is small; a fix commit requires a fresh review and receipt; never stamp a new HEAD with an old review. Do not file Backlog entries for findings. Do not commit or push here.

On a code project with `trigger.mode: "auto"`, this run also satisfies agent-sop's `/update-sop` Step 1b reviewer turn: cite the same report from the Backlog entry's `review:` line instead of running a second review.
