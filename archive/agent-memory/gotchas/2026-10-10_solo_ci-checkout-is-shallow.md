# actions/checkout is depth 1, so tests that read git history fail in CI

**Date:** 2026-10-10
**Agent:** solo

**The surprise.** `tests/legacy-hook.sh` reads the deleted `auto-ship-hook.sh` blobs from history. It passed locally and would have failed in CI: `actions/checkout` fetches one commit by default, so the blobs are absent.

**Expected.** CI has the same history as a local clone.

**Rule.** A test that needs history says so in its header and fails with a clear message without it; the CI checkout for it sets `fetch-depth: 0`. Reviewers caught this before merge (P25 round 1).
