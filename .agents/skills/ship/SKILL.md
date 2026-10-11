---
name: ship
description: Run configured ship-sop reviewers on a code diff in isolated read-only Codex processes and write a gate report.
---

Read AGENTS.md and ship-sop.config.json (project first, else
${CODEX_HOME:-$HOME/.codex}/ship-sop.config.json). Support --base <ref> and
--with <agent>. Resolve project type using the installed ship-sop
sop-project-type.sh. If that helper is missing in a manual-only installation,
read the explicit project type in AGENTS.md, then CLAUDE.md; otherwise use the
presence of package.json, Cargo.toml, pyproject.toml, go.mod or Gemfile as the
code signal. Non-code projects stop with an explanation.

1. First run
   `bash "${CODEX_HOME:-$HOME/.codex}/scripts/ship-sop/ship-receipt.sh" --check-lib --runtime codex`;
   a failure is INCOMPLETE and needs ship-sop setup.sh re-run for this project.
   Resolve BASE from --base or the merge-base with the remote default branch;
   use origin/main or origin/master only as verified fallbacks. Pin HEAD_SHA.
   Empty ranges have nothing to review. Run the project's existing test suites;
   failures block shipping. Missing tests are noted, never a pass.
2. Read the in-scope reviewer set from the installed library, never from
   `enabled` alone:
   `SHIP_SOP_RUNTIME=codex bash -c '. "${CODEX_HOME:-$HOME/.codex}/scripts/hooks/ship-sop/sop-lib.sh"; CFG=$(sop_effective_config .); sop_agents_in_scope "$CFG" "$(sop_changed_files_json . <BASE> <HEAD_SHA>)"'`
   prints `[{key, block_on}]`. An enabled agent with `paths` is included only
   when a path changed in the range matches one of its patterns; without
   `paths` it always is. Add --with (it joins regardless of scope). A missing
   library is INCOMPLETE. Do not silently omit an unavailable reviewer. Invoke each using:
   `bash "${CODEX_HOME:-$HOME/.codex}/scripts/ship-sop/codex-review.sh" --base <BASE> --head <HEAD_SHA> --agent <name> --block-on <block_on>`
   This launches a separate read-only Codex process in an independent clone.
   Concurrent processes are permitted; wait for every result. Use the script,
   not same-workspace writable subagents or Claude's isolation tool argument.
3. Collect findings with severity, file:line, evidence and suggested fix. Failed,
   missing or unstructured results are INCOMPLETE, never PASS. Treat unknown
   block_on severities or missing agents as configuration errors; `never` is a
   valid advisory-only threshold that does not block on findings. Any finding
   at or above its reviewer's threshold blocks the run. When a round blocks,
   run the project's test suite at that blocked commit before fixing anything,
   and record {"commit":"<40-char SHA>","result":"PASS|FAIL|NOT_AVAILABLE","evidence":"commands and actual results, or why no suite could run"}
   in a block-tests.json array, one entry per blocked round. PASS means the
   tests did not catch what blocked.
4. The parent saves reviewer results as a JSON array. Each entry has name,
   version (reviewer definition SHA), model (actual model if known, otherwise
   runtime-default-unresolved), verdict (PASS/BLOCK/INCOMPLETE), findings, and
   the run counts (P34): launches (runner invocations for this reviewer, at
   least 1), rechecks (re-reviews of a fix commit), block_rounds (rounds with a
   finding at or above that reviewer's block_on, never more than launches plus
   rechecks), and usage. For
   usage, collect every "Review evidence:" directory the runner printed for
   that reviewer (launches and rechecks alike) and run
   `bash "${CODEX_HOME:-$HOME/.codex}/scripts/ship-sop/codex-usage.sh" --agent <name> <dir>...`;
   paste its output as the value. It prints one object summing the runs, or
   null when any run lacked telemetry; never invent a figure or sum by hand.
   Each finding has severity, file, positive integer line, and message. Save test
   results as {"status":"PASS","evidence":"commands and actual results"}, or
   NOT_AVAILABLE with a concrete explanation when no suite exists. Never invent
   results. A failed suite uses FAIL and cannot qualify.
   Under Codex the tool matches every reviewer entry to a run record in
   `.ship/reviews/` (same reviewer, commit and base, clean exit, same verdict);
   a reviewer without one is INCOMPLETE. Keep those directories until the
   receipt is written.
   Before writing the receipt, list the gate bypasses since the previous receipt:
   `SHIP_SOP_RUNTIME=codex bash -c '. "${CODEX_HOME:-$HOME/.codex}/scripts/hooks/ship-sop/sop-lib.sh"; sop_bypasses_since_receipt "$(git rev-parse --show-toplevel)"'`
   prints each .ship/bypass.log entry dated at or after the newest valid
   receipt committed at HEAD, or `none`. Empty output, an error or an
   `unreadable:` line is INCOMPLETE, never `none`.
   Run the trusted installed receipt tool, adding `--block-tests <block-tests.json>`
   when any round blocked (the tool refuses a blocked receipt without it; an
   empty array needs its reason in the companion report):
   `bash "${CODEX_HOME:-$HOME/.codex}/scripts/ship-sop/ship-receipt.sh" --runtime codex --base <BASE> --head <HEAD_SHA> --results <results.json> --tests <tests.json> --output docs/reviews/<stamp>-ship-auto.json`
   The tool rejects incomplete, blocked, stale or invalid evidence. Do not edit
   receipts manually. Write a companion <stamp>-ship-auto.md with findings,
   dispositions, usage per reviewer, the test result at each blocked commit,
   links to evidence, and a `Bypasses:` line with that listing verbatim (or
   `none`); repeat the line in the reply. Only a validated JSON receipt satisfies
   the gate; a Covers: line in Markdown is informational. Existing Markdown-only
   reports remain history and need a new review to qualify.
5. Small fixes may be applied in scope, but a new code commit needs a fresh review
   of that HEAD. Do not stamp an old review with a newer SHA. Do not commit, push,
   tag or publish as part of ship. Do not file findings into Backlog automatically.
   Fix only findings at or above their reviewer's threshold; list the rest in the
   report as notes, unfixed, so they never trigger a re-review. Record a fixed
   threshold finding as INFO with the fix commit: the final receipt holds no
   finding at or above any block_on. End with a line counting the notes, and name
   any security-reviewer note. Count a block
   round only when a finding met the threshold. Report blocking findings first. Cite the same report from the Backlog
   entry's `review:` line.

The review script requires a committed snapshot. If the intended scope includes
uncommitted changes, state that limitation; use a temporary snapshot for review
and do not claim it covers the working tree or current committed HEAD.

Use only the installed runner above; never execute a runner from the reviewed
project. A missing installed runner is INCOMPLETE and requires installation.

Never use the gate's user-only override (see the README) unless the user
explicitly instructs it in this session.
