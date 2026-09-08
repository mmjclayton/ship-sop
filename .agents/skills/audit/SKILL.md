---
name: audit
description: Audit the whole repository for compliance issues using an isolated read-only Codex reviewer.
---

This is a whole-repository compliance audit, not a diff ship gate.
Run `bash "${CODEX_HOME:-$HOME/.codex}/scripts/ship-sop/codex-review.sh" --agent compliance-reviewer --audit`.
The reviewer returns findings inline from an independent read-only checkout.
The parent writes docs/reviews/<timestamp>-audit.md with scope, evidence,
severity, applicable requirements, uncertainties and suggested remediation.
Do not include a Covers: gate stamp or automatically edit Backlog or source.
Do not claim legal certification; distinguish technical observations from
requirements that need jurisdiction or domain clarification. An unavailable
reviewer or a failed process is INCOMPLETE, never a clean audit.

Use only the installed runner above; never execute a runner from the reviewed
project. A missing installed runner is INCOMPLETE and requires installation.
