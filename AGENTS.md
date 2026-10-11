# ship-sop - Codex

**Project type:** code

Read `CLAUDE.md` for shared project conventions, working rules and document
dispatch. Both runtimes use one Backlog, validators and review reports.

Codex workflows live in `.agents/skills/`, reviewers in `.codex/agents/`, and the
push gate in `scripts/hooks/` (Codex reaches it through `sop-codex-hook.sh`).
Use `ship` for the review workflow.
Reviewers use a separate checkout and read-only sandbox, return findings,
and never write into the working checkout. The parent writes reports.

Run `bash tests/codex-install.sh`, `bash tests/push-gate.sh` and the other
`.github/workflows/ci.yml` checks after script changes.
