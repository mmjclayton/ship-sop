# Plan: measure the review gate's cost and net value on live work

**Status:** approved 12 Oct 2026; the recording it needs ships in P44. **Replaces this README sentence when done:** "The sample covers one project; review cost and net benefit against no gate have not been measured."

## The questions

1. **What does a review cost?** Tokens, reviewer minutes and fix rounds per change.
2. **What does the gate catch that the tests would not?** Each project still runs its tests and CI without the gate, so the gate's net benefit is the real defects it blocks that the tests missed, set against its cost.
3. **Did P43 cut minor blocks?** P40 found 8 to 10 of 29 blocks were correct but minor. P43 (12 Oct) made reviewers block only on user or data impact.

## Where and for how long

- **Live work, no separate experiments.** The measurement uses the reviews that run anyway: Edward's work, plus any RepCanvas work in the same window.
- **Window:** about 4 weeks or 40 gated pushes, whichever comes first, counted from the day P44 is merged and setup is re-run in those projects so the installed `/ship` records usage and block tests.
- **One-project limit.** Nearly all the data will come from Edward, a single small, single-operator project with agent-written code. The results describe that project. RepCanvas adds a few changes at most, which is not enough to show the results hold elsewhere, and the report will say so.

## What is recorded, and from where

### Cost: from the receipts

- Each reviewer's `usage` in the receipt: Claude records the tokens and duration that each task-completion notification reports (tokens are a running total per agent, so each agent's last figure counts once); Codex records its runner telemetry. A missing figure is null, never estimated.
- `scripts/receipt-totals.sh --json` over the window's receipts gives, per change: tokens, reviewer minutes and block rounds; and per project: totals, medians and ranges. A change with any unknown usage is left out of the cost figures and counted separately.
- Reviewer minutes add each reviewer's own run time. Reviewers run in parallel, so this is not wall-clock time.
- Claude and Codex count tokens differently, so their figures are reported separately.
- Any dollar figure is labelled API-equivalent. On a subscription, the real cost is usage quota and waiting time.

### Test-catch: from `block_tests`

- When a review round blocks, `/ship` runs the project's test suite at the blocked commit before any fix and records the result in the receipt's `block_tests` (PASS, FAIL or NOT_AVAILABLE, with the commit).
- **FAIL:** the tests already caught something at that commit; the gate added nothing for this block. **PASS:** the tests missed what the reviewer blocked. **NOT_AVAILABLE:** counted and reported, never read as either.
- A blocked round with no `block_tests` entry is reported as missing.

### Grading: one blind pass at the end

- **Sample:** up to 30 post-P43 blocks from the window, all of them if there are fewer, otherwise a seeded random sample.
- **Method:** P40's (`docs/benchmark/p40/`): two blind graders, the same three grades (real defect, correct but minor, false positive), the same packet format and the same impact labels.
- **P43 check:** compare the share graded minor with P40's 8 to 10 of 29. The sample is small, so the report gives the counts and does not claim a significant difference.

## Net value

For each reviewer and in total:

| Measure | From |
|---|---|
| Blocks graded real by both graders | grading pass |
| Of those, the tests missed (block_tests PASS) | block_tests |
| Of those, security, privacy or data loss | P40 impact labels |
| Tokens and reviewer minutes per change | receipts |
| Fix rounds spent on minor findings or false positives | grading pass and receipts |
| Cost per real defect the tests missed | the rows above |

This plan does not put a dollar value on a defect; that is a judgement for the operator. The report gives the cost per defect caught and the severity mix, so the call can be made on numbers.

## Decision rule, set before the data

- A reviewer that catches no real defect the tests missed, across all sampled changes, is path-scoped or turned off.
- A reviewer whose blocks are more than half minor or false positive is flagged for a severity-rule change.
- Otherwise the gate stays as configured.

## Order

1. Merge P44 and re-run setup in Edward and RepCanvas. The window starts that day.
2. Check the first few receipts: usage is filled or null with a reason, and every blocked round has a `block_tests` entry.
3. At the end of the window, run `receipt-totals.sh`, then the grading pass.
4. Write the report and update the README sentence with the measured figures and their limits.

The grading cost is not known yet; P40 is the only comparison, and it graded 29 blocks.

## What this will not show

- Defects neither the gate nor the tests caught.
- Whether a missed defect would ever have been noticed by a user.
- Results for projects unlike Edward.
- Whether a defect the tests missed at the blocked commit would have been caught by a test written later without the gate.
