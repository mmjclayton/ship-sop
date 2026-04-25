---
date: 2026-04-25
agent_id: solo
title: /release stays manual; never fires from a hook
---

# /release stays manual; never fires from a hook

## Decision

`/release` is invoked by the operator only. No SessionStop hook triggers it. No git pre-push hook calls it. No GitHub Action template ships with ship-sop that auto-tags releases.

## Why

Releases are public commitments. Once a Git tag and GitHub Release are pushed, they're seen by users and dependent projects. Auto-firing `/release` on every push to main risks:
- Releasing half-finished states
- Releasing during an open refactor
- Releasing without anyone reviewing what's in the release notes
- Recovery means deleting tags, force-pushing, and embarrassed messages

The cost of "I forgot to cut a release" is low (a few clicks later). The cost of "we accidentally released v0.4.0 with a half-baked feature" is high.

Manual is the right default.

## Consequences

- `/release` has a confirmation prompt before tagging. Operator types `y` or stops.
- Pre-flight checks halt early: dirty tree, not on default branch, behind origin, not gh-authenticated.
- If users want some release automation, they do it via GitHub Actions on tag push (e.g., publish to npm/crates/PyPI when a tag matching `v*` lands). That's a downstream concern, not ship-sop's.

## Alternatives considered

- **`auto_publish: true` in config.** Rejected. The schema permits it for completeness but the description says *"Strongly discouraged."* Documenting the existence of an option is not the same as recommending it.
- **Auto-fire `/release` after merge to main.** Rejected for the same reason — auto-merge plus auto-release means a single PR review can ship a tagged release, which is too much trust in a single review.

## Note

This is a hard line, not a configurable trade-off. Auto-publish behaviour is the kind of feature that should require deliberate friction (manual command + confirmation prompt) on every invocation.
