# SOP sync after agent-sop P104/P105

**Date:** 2026-09-05
**Agent:** solo
**Commits:** `8c18bf5`

Pristine agent-sop replicas refreshed from upstream (trimmed core SOP, retargeted validator, `archive-backlog.sh`, checklist, review template); the project-scope ship-sop Stop hook retired. The replica scripts were reviewed and gated in agent-sop (P104 and P105 gate reports); no separate gate run here. Applied from the agent-sop session, not by this branch's own session, whose resume snapshot is untouched.
