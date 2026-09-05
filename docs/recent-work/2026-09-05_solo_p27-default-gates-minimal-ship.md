# P27 — three default gates, one review run, a minimal /ship

**Date:** 2026-09-05
**Agent:** solo
**Commits:** feature commit, housekeeping follows

Docs and config only, from the five-agent token review. Default gate set is three (security, silent-failure, code); the other three are opt-in per run. `/ship` is ~40 lines and dispatches every enabled agent in isolated worktrees (closes P17). One review run serves agent-sop's Step 1b and the gate. Dead config keys gone from the template; schema marks them deprecated. `/ship-on` probes the user-scope hook (P25 item 5).
