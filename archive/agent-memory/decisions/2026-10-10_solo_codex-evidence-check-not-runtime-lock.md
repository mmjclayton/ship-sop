# Codex receipts are checked against runner records; the runtime choice is not locked

**Date:** 2026-10-10
**Agent:** solo

We chose to check Codex receipt entries against the runner's records in `.ship/reviews/` (P38) and to state in the README that the calling session chooses `--runtime`, over refusing `--runtime claude` whenever Codex records or a Codex install exist, because projects installed with `--runtime both` legitimately write Claude receipts alongside Codex runs, and a lock would break them while still being bypassable (the session can delete `.ship/`).

The check raises the cost of a false receipt; it does not prevent one. Enforcement against a session that chooses to skip review needs reviewers that run outside it (CI), which is an API cost decision left to the operator.
