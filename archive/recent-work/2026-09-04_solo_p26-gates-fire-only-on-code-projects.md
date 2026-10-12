# P26 — gates fire only on code projects and code lines

**Date:** 2026-09-04
**Agent:** solo
**Commits:** `b1a22c2` (docs), housekeeping commit follows

Operator rule from the agent-sop session the same day: ship-sop fires for coding and for nothing else. The trigger is agent-sop's (P97), and agent-sop P102 makes it read one project-type rule and count code lines only. This is ship-sop's side, docs-only: `/ship` and `/ship-on` stop on a non-code project by the shared rule, the README states it, `skip_docs_only` is documented as accepted-but-unread (agent-sop's hook read it through a jq `// true` default that already swallowed an explicit `false`), the template default flips to `true`, and this repo declares `**Project type:** code` because bash under CI with no manifest would otherwise read as non-code.

Nothing here executes; the enforcement and the fixtures live in agent-sop P102.
