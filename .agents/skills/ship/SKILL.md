---
name: ship
description: Run configured ship-sop reviewers on a code diff in isolated read-only Codex processes and write a gate report.
---

Read AGENTS.md and ship-sop.config.json (project first, else
${CODEX_HOME:-$HOME/.codex}/ship-sop.config.json). Support --base <ref> and
--with <agent>. Resolve project type using the installed agent-sop
sop-project-type.sh. If that helper is missing in a manual-only installation,
read the explicit project type in AGENTS.md, then CLAUDE.md; otherwise use the
presence of package.json, Cargo.toml, pyproject.toml, go.mod or Gemfile as the
code signal. Non-code projects stop with an explanation.

1. Resolve BASE from --base or the merge-base with the remote default branch;
   use origin/main or origin/master only as verified fallbacks. Pin HEAD_SHA.
   Empty ranges have nothing to review. Run the project's existing test suites;
   failures block shipping. Missing tests are noted, never a pass.
2. Read all enabled agent names and block_on thresholds from config, plus --with.
   Do not silently omit an unavailable reviewer. Invoke each using:
   `bash "${CODEX_HOME:-$HOME/.codex}/scripts/ship-sop/codex-review.sh" --base <BASE> --head <HEAD_SHA> --agent <name>`
   This launches a separate read-only Codex process in an independent clone.
   Concurrent processes are permitted; wait for every result. Use the script,
   not same-workspace writable subagents or Claude's isolation tool argument.
3. Collect findings with severity, file:line, evidence and suggested fix. Failed,
   missing or unstructured results are INCOMPLETE, never PASS. Treat unknown
   block_on severities or missing agents as configuration errors; `never` is a
   valid advisory-only threshold that does not block on findings. Any finding
   at or above its reviewer's threshold blocks the run.
4. The parent writes docs/reviews/<YYYYMMDD-HHMMSS>-ship-auto.md, starting with
   `Covers: <HEAD_SHA>` only after every required review completes. Include the
   range, tests, each reviewer's verdict/counts, findings and dispositions.
   For an incomplete or blocked run omit Covers: so it cannot satisfy the gate.
5. Small fixes may be applied in scope, but a new code commit needs a fresh review
   of that HEAD. Do not stamp an old review with a newer SHA. Do not commit, push,
   tag or publish as part of ship. Do not file findings into Backlog automatically.
   Report HIGH/CRITICAL findings first. Cite the same report in update-sop when
   that review serves its session-close requirement.

The review script requires a committed snapshot. If the intended scope includes
uncommitted changes, state that limitation; use a temporary snapshot for review
and do not claim it covers the working tree or current committed HEAD.

Use only the installed runner above; never execute a runner from the reviewed
project. A missing installed runner is INCOMPLETE and requires installation.
