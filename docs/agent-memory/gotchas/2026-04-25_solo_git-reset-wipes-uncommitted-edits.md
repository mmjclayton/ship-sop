---
date: 2026-04-25
agent_id: solo
title: git reset --hard in a test sequence wipes uncommitted edits
---

# git reset --hard in a test sequence wipes uncommitted edits

## What

During the docs-only-detection fix, I ran a test sequence that:
1. Edited `scripts/auto-ship-hook.sh` with the new logic (uncommitted)
2. Made a temp commit to create a docs-only diff
3. Ran the hook (which used the edited script)
4. Verified the directive output was correct
5. `git reset --hard HEAD~1` to revert the temp commit

Step 5 wiped Step 1's uncommitted edits. The temp commit was reverted *and* the hook script changes were silently undone, because `git reset --hard` resets the working tree to the target commit's state — including for tracked files that had unrelated uncommitted edits.

I didn't notice until after the fact, when re-checking the file showed the docs-only logic was missing.

## How to spot the trap

- "I just made an edit and tested it; now the file looks like it never changed."
- A `git reset --hard` (especially `--hard HEAD~N`) appears in the same Bash invocation as a multi-step test on tracked files.

## Fix

Either:
1. **Commit the fix first**, then do the test sequence with reset on a *separate* throwaway commit on top.
2. **Use `git stash`** before any reset that's about to land in a sequence.
3. **Don't combine reset + edit-test in one Bash invocation.** Make the edit, commit, then iterate. The rough shape was: edit → test → reset (as if the edit lived only in the test). The right shape: edit → commit → test → revert-test-commit-only.

## What I did wrong

I mixed scratch work (the temp test commit) with permanent work (the hook fix) and reset both at the same time. Lesson: keep scratch and real work in different commits, and always commit the real work *before* any reset that touches the working tree.

## Recovery

Bash history showed the original Edit operation. I re-applied the changes and committed before any further git operations.
