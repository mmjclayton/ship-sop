---
date: 2026-04-25
agent_id: solo
title: diagram-builder is narrow; doc-updater stays in its lane
---

# diagram-builder is narrow; doc-updater stays in its lane

## Decision

The initial design called the docs gate `doc-builder` and had it generate codemaps + INDEX.md + Mermaid diagrams + API catalog + ARCHITECTURE Δ log. After audit, this overlapped significantly with the existing user-installed `doc-updater` agent (`~/.claude/agents/doc-updater.md`) which generates codemaps, refreshes README, builds module import/export graphs, and uses TypeScript AST analysis.

Resolution: rename to `diagram-builder` and trim its scope to:
- Mermaid state + sequence diagrams from enums and multi-collaborator flows
- API endpoint catalog with request/response schemas + side effects
- Per-ship ARCHITECTURE Δ log (append-only architectural history)

Codemaps, INDEX.md, README refresh: out of scope. Operators invoke `@doc-updater` directly when they want those.

## Why

Two reasons against expanding ship-sop's docs scope:

1. **Don't duplicate existing tools.** `doc-updater` is mature, in the user's actual install, and well-suited for codemap work. Reinventing it inside ship-sop dilutes both agents.
2. **Stay narrow.** A gate that does five different things is harder to debug than a gate that does three closely-related things. Diagrams + API + Δ log are all "ship-time documentation derived from the diff." Codemaps are broader and on-demand.

## Consequences

- `diagram-builder` is the only docs-related agent ship-sop ships. Users who want broader doc maintenance run `@doc-updater` separately.
- README explicitly documents the split: doc-updater is on-demand and broad, diagram-builder is per-ship and narrow.
- If a project doesn't have `doc-updater`, ship-sop's docs gate produces less than it could. That's the right trade — expanding ship-sop's scope to compensate would push it back into duplication.

## Naming

`doc-builder` was generic and invited scope creep. `diagram-builder` is concrete, names what it actually does, and signals what it doesn't.
