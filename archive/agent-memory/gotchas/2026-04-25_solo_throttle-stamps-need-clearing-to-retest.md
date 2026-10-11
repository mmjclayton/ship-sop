---
date: 2026-04-25
agent_id: solo
title: Throttle stamps block re-firing on the same diff state
---

# Throttle stamps block re-firing on the same diff state

## What

`scripts/auto-ship-hook.sh` writes two stamp files after a successful run:
- `.ship/.last-auto-fire` — Unix timestamp; the cooldown check rejects fires within `cooldown_seconds` (default 300s)
- `.ship/.last-diff-hash` — SHA-256 of the diff; the same-diff guard rejects fires when the current diff is unchanged

These prevent rapid-fire firing on the same diff state, which is correct for production use — you don't want the hook firing 12 times an hour on a stale diff. But it makes iterating on the hook itself frustrating: every test run gets blocked by the previous one's stamps.

## How to spot the trap

- You edit the hook script, run it, get expected output.
- You run it again to verify a tweak — silent exit 0, no directive written.
- "Why did it fire the first time and not the second?"

## Fix

Clear the stamps between iterations:

```bash
rm -f .ship/.last-auto-fire .ship/.last-diff-hash
```

Or, if you want to also wipe the previous directive:

```bash
rm -rf .ship/
```

## Why I'm not "fixing" this

The stamps are doing their job — same-diff guard is the correct production behaviour. Adding a `--force` flag to the hook would expand its surface for a developer-only need. The clearer path is: developers know to clear `.ship/` when iterating; production runs leave the stamps alone.

If iteration becomes painful enough, a `--clear-stamps` or `--dev` flag could be added. Not worth it on initial release.
