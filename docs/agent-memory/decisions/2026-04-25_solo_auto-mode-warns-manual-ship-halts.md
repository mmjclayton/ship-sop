---
date: 2026-04-25
agent_id: solo
title: Auto-mode warns; manual /ship halts. Same gates, different failure modes.
---

# Auto-mode warns; manual /ship halts. Same gates, different failure modes.

## Decision

The same four gates (tests, security, compliance, diagrams) produce identical artifacts whether triggered by the SessionStop hook or by `/ship`. What differs is what happens on a hard-block failure:

| Trigger | On hard-block failure |
|---------|----------------------|
| Auto (SessionStop hook → next-turn) | Strong warning injected into context. Session continues. |
| Manual (`/ship`) | Halts with non-zero exit. Operator fixes and re-runs. |

## Why

Two different intents.

**Auto-mode** is "run the gates on every code-touching session as a sanity check, without disrupting flow." If auto-mode could halt, every session-end on a CRITICAL finding would force the user out of whatever they're working on. The cost of that disruption outweighs the benefit of the strict gate, especially when most CRITICAL findings are addressable but not immediately urgent.

**Manual `/ship`** is the operator deliberately checking ship-readiness. If they invoked it, they want the strict answer — halt on CRITICAL means "fix this before opening a PR." Same gate, harder edge.

## Consequences

- Auto-mode is suitable for always-on use. Manual mode is suitable for pre-PR rigor.
- Operators don't have to choose one or the other; both can coexist. Auto runs in the background; manual is invoked when they want a halt-or-pass verdict.
- The CI story (gates without a Claude session) hasn't been built yet. When it is, it'll behave like manual mode — halt on hard-block — because CI failures are the canonical "halt the merge" surface.

## Alternatives considered

- **Auto halts too.** Rejected: too disruptive. The SOP equivalent would be `/update-sop` blocking on every session-end.
- **Manual warns too.** Rejected: defeats the purpose. If `/ship` doesn't halt, why run it instead of auto?
- **Configurable per-mode.** Rejected: two modes with two halt-policies = four code paths. Stick with two clear defaults.
