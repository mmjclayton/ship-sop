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
2. Read the in-scope reviewer set from the installed library, never from
   `enabled` alone:
   `AGENT_SOP_RUNTIME=codex bash -c '. "${CODEX_HOME:-$HOME/.codex}/scripts/hooks/agent-sop/sop-lib.sh"; CFG=$(sop_effective_config .); sop_agents_in_scope "$CFG" "$(sop_changed_files_json . <BASE> <HEAD_SHA>)"'`
   prints `[{key, block_on}]`. An enabled agent with `paths` is included only
   when a path changed in the range matches one of its patterns; without
   `paths` it always is. Add --with (it joins regardless of scope). A missing
   library is INCOMPLETE. Do not silently omit an unavailable reviewer. Invoke each using:
   `bash "${CODEX_HOME:-$HOME/.codex}/scripts/ship-sop/codex-review.sh" --base <BASE> --head <HEAD_SHA> --agent <name>`
   This launches a separate read-only Codex process in an independent clone.
   Concurrent processes are permitted; wait for every result. Use the script,
   not same-workspace writable subagents or Claude's isolation tool argument.
3. Collect findings with severity, file:line, evidence and suggested fix. Failed,
   missing or unstructured results are INCOMPLETE, never PASS. Treat unknown
   block_on severities or missing agents as configuration errors; `never` is a
   valid advisory-only threshold that does not block on findings. Any finding
   at or above its reviewer's threshold blocks the run.
4. The parent saves reviewer results as a JSON array. Each entry has name,
   version (reviewer definition SHA), model (actual model if known, otherwise
   runtime-default-unresolved), verdict (PASS/BLOCK/INCOMPLETE), and findings.
   Each finding has severity, file, positive integer line, and message. Save test
   results as {"status":"PASS","evidence":"commands and actual results"}, or
   NOT_AVAILABLE with a concrete explanation when no suite exists. Never invent
   results. A failed suite uses FAIL and cannot qualify.
   Run the trusted installed receipt tool:
   `bash "${CODEX_HOME:-$HOME/.codex}/scripts/ship-sop/ship-receipt.sh" --runtime codex --base <BASE> --head <HEAD_SHA> --results <results.json> --tests <tests.json> --output docs/reviews/<stamp>-ship-auto.json`
   The tool rejects incomplete, blocked, stale or invalid evidence. Do not edit
   receipts manually. Write a companion <stamp>-ship-auto.md with findings,
   dispositions and links to evidence. Only a validated JSON receipt satisfies
   the gate; a Covers: line in Markdown is informational. Existing Markdown-only
   reports remain history and need a new review to qualify.
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
