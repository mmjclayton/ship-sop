# Plan: measure the review gate's cost and net value

**Status:** proposed, 12 Oct 2026. **Replaces this README sentence when done:** "The sample covers one project; review cost and net benefit against no gate have not been measured."

## The three open questions

1. **Does P40's result hold beyond one project?** P40 graded 29 blocks, all from edward.
2. **What does a review cost?** Claude receipts record `usage: null`. Nothing records tokens or time per review.
3. **What does the gate catch that the project would otherwise miss?** "No gate" does not mean no checks: each project still runs its tests and CI. The gate's net benefit is the real defects it catches that those tests would not, set against what it costs.

## How each is measured

### A. Cost: record it from now on (cheap, ongoing)

- **Claude.** When the `/ship` session collects each reviewer's result, it records the token count and duration the runtime reports, and writes them into the receipt's `usage` field. Codex receipts already carry usage.
- **Per change.** Add up reviewer tokens, wall-clock minutes from the first review to a passing receipt, and the number of fix rounds.
- **Output after 4 weeks (or 40 changes, whichever comes first):** median and spread of tokens, minutes and fix rounds per change, split by reviewer and by repo.
- **Dollar figures.** Any figure in dollars is labelled API-equivalent. On a subscription, the real cost is usage quota and waiting time.

### B. Would the tests have caught it? (no new reviews, only test runs)

- **Sample.** Each defect both graders confirmed real: P40's 14, plus those from C.
- **Test.** Find the commit that fixed it; the review report names it. Check out the parent of that commit in a clean clone and run the project's full test suite as CI runs it.
  - **Caught by tests:** the suite fails at the parent. The gate added nothing for this defect.
  - **Missed by tests:** the suite passes at the parent. Only the gate caught it.
- **Extra signal.** Record whether the fix commit added a test.
- **Unresolved.** A defect whose fix commit cannot be identified is recorded as unresolved, not dropped.

### C. A second and third project

- **Sample.** Repeat P40's method (seeded sample, two blind graders, the same three grades) on blocks from RepCanvas and ship-sop. The records hold:
  - RepCanvas: 3 blocked receipts;
  - ship-sop: 4;
  - agent-sop: 13 (now archived, but its records are still there).
- **Use everything.** Every available block is used rather than sampled, because there are few.
- **Post-P43 blocks.** New blocks under the P43 rules (from 12 Oct) are graded separately, which shows whether P43 cut minor blocks.

### D. Net value

For each reviewer and in total, per 100 changes:

| Measure | From |
|---|---|
| Real defects caught that tests missed | B and C |
| Of those, security, privacy or data-loss | P40 impact labels |
| Tokens and minutes spent | A |
| Fix rounds spent on minor findings or false positives | A, C |
| Cost per real defect that tests missed | the two above |

This plan does not put a dollar value on a defect; that is a judgement for the operator. The report gives the cost per defect caught and the severity mix, so the call can be made on numbers.

## Decision rule, set before the data

- A reviewer that catches no real defect the tests missed, across all sampled changes, is path-scoped or turned off.
- A reviewer whose blocks are more than half minor or false positive is flagged for a severity-rule change.
- Otherwise the gate stays as configured.

## Order, effort and cost

1. **A** first. It is a small ship-sop change (receipt `usage` for Claude) and starts the 4-week clock.
2. **B** next. It costs only test-suite runs. It needs edward's suite to run from a clean clone; if it cannot, that is reported.
3. **C.** Pilot by grading 5 blocks first and measure the grading cost, then propose a cap for the rest before continuing.
4. **D.** Write the report after 4 weeks. Update the README sentence with the measured figures and their limits.

The cost of steps B and C is not known yet. The step 3 pilot measures it before any larger run.

## What this will not show

- Defects neither the gate nor the tests caught.
- Whether a missed defect would ever have been noticed by a user.
- Results for projects unlike these three (all small, single-operator, agent-written code).
