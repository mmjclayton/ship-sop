# P40: are ship-sop's blocks real? Blind precision sample from edward

**Date:** 2026-10-11. **Data:** edward's schema-2 ship-gate receipts, 25 Sep to 11 Oct 2026. **Files:** this folder.

## Answer

About half of the gate's blocks were real defects by the stricter grader's standard; the more lenient grader's figure was about 60%. Few were false alarms: 7% by both graders' grading, 21% by at least one. These figures hold when the questionable rows are removed (see Sensitivity). This shows the gate catches real defects. Whether edward's existing tests would also have caught them is unknown: the receipts record test status only at their final commit, not at the blocked one. It does not show the gate is worth its cost: what those defects would have cost if caught later, or never, was not measured.

| Blind grade of 29 blocking findings | Grader A | Grader B | Both graders |
|---|---|---|---|
| Real defect | 17 (59%) | 14 (48%) | 14 (48%) |
| Correct but minor | 9 | 10 | 8 |
| False positive | 3 (10%) | 5 (17%) | 2 (7%) |

The graders agreed on 24 of 29 (83%). B was stricter in 4 of the 5 disagreements: A rated three findings real that B rated minor or false, and S18 minor where B rated it false. A was stricter on S21. Grader B's instructions included "be sceptical, automated reviewers often overstate"; A's did not. This difference was not planned, so read the two columns as a lenient and a sceptical framing of the same evidence.

| A (rows) by B (columns) | Real | Minor | False positive |
|---|---|---|---|
| Real | 14 | 1 | 2 |
| Minor | 0 | 8 | 1 |
| False positive | 0 | 1 | 2 |

## The 14 defects both graders confirmed

| Impact (grader A's label) | Count | Examples |
|---|---|---|
| Security or privacy exposure | 3 | S08: model calls bypassed the company's provider permission. S20: strategists' internal notes were shown to clients. S22: a rejected insight became client-visible |
| Data loss or corruption | 2 | S01: the model had to invent the scope's set date. S28: a failed brand read wiped the stored brand |
| User-visible wrong behaviour | 7 | S06, S13, S15, S17, S24, S25, S29 |
| Silent failure hidden from the user | 2 | S07, S16 |

Grader B labelled S01 user-visible rather than data loss; the counts above use A's labels.

## By reviewer

| Reviewer | Sampled | Real (A) | Real (B) | Not a false positive (both) |
|---|---|---|---|---|
| silent-failure-hunter | 13 | 6 | 5 | 12 |
| code-reviewer | 11 | 6 | 5 | 7 |
| security-reviewer | 5 | 5 | 4 | 4 |

The samples are small, so differences between reviewers are not significant.

## Would the tests have caught them?

Unknown. ship-sop's `/ship` procedure runs the project's test suite before the reviewers, and a failure halts the ship (`.claude/commands/ship.md`, step 3). Every sampled receipt records its tests as PASS, but at its final commit after the fixes; for example, S08's evidence reads "On 6727d88", while the blocked commit was e597a52. The test status at each blocked commit is not recorded, and neither is whether every edward round followed the procedure. Many receipts note a regression test "watched failing first" for each fix. That shows a test was added after the block; it says nothing about whether the existing suite was green at the blocked commit.

## Sensitivity

The rows below remove groups whose grades are less certain:
- **S22:** not blind. Its packet text said the finding was raised again in a later round.
- **Inferred rows:** the round commit, severity, files or reviewer were inferred by the extractors (S04, S07, S08, S09, S12, S25, S27, S29, S30). S12 and S29 also carried "inferred" or "implied" in the severity field the graders saw.
- **Below-threshold blocks:** security blocks recorded at HIGH, below edward's CRITICAL threshold (S08, S10, S20).

| Set | n | Real (both graders) | Real (A-B) | False positive (both) | False positive (either) |
|---|---|---|---|---|---|
| All | 29 | 14 (48%) | 17-14 | 2 (7%) | 6 |
| Without S22 | 28 | 13 (46%) | 16-13 | 2 (7%) | 6 |
| Without inferred rows | 20 | 10 (50%) | 13-10 | 1 (5%) | 5 |
| Without below-threshold security blocks | 26 | 12 (46%) | 14-12 | 2 (8%) | 5 |
| Without all of these | 17 | 8 (47%) | 10-8 | 1 (6%) | 4 |

The 17 rows left in the last slice: S01, S02, S03, S05, S06, S11, S13, S15, S16, S17, S18, S19, S21, S23, S24, S26, S28.

## Cost

Measured from edward's 174 schema-2 receipts (25 Sep to 11 Oct 2026):

| Measure | Count |
|---|---|
| Reviewer launches | 636 |
| Re-checks | 824 |
| Reviewer runs in total | 1,460 |
| Reviewer runs per receipt, on average | 8.4 |
| Block rounds | 277 |

Token cost per run is not measured for edward. Receipts record no usage, and edward's session transcripts no longer hold the per-agent token counts. ship-sop P27 measured about 64,000 tokens per agent launch on agent-sop. At that rate, 1,460 runs would be about 93 million tokens. That figure is an estimate built from another repo's measurement, not a measurement of edward.

Not measured either: the time a session spent fixing each block. That includes fix rounds triggered by false positives and by findings graded minor; 8 to 10 of the 29 sampled blocks were minor.

## Method

1. **Frame:** every reviewer-run that blocked at least once in edward's schema-2 receipts. 231 runs from 124 receipts.
2. **Sample:** 30 runs, stratified by reviewer in proportion to blocks (silent-failure 14, code 11, security 5), drawn with `random.Random(40)`.
3. **Extraction:** three fresh agents restated each run's blocking findings as claims, with fixes and dispositions stripped. One finding per run was then picked with the same seed. S14 was excluded because its report does not say which round-one items were the silent-failure reviewer's blocking ones. The frame, sample, extractions and blind packet were committed before grading (ed82ddc, 172a834, 16f82ad).
4. **Grading:** two independent fresh agents graded each claim against edward's code at the reviewed commit. They were not allowed to read review records, the backlog, session records or later commits.

## Limits

- **One project, 29 findings.** One finding per run was graded, so a run whose other findings were false or minor is not reflected.
- **Inferred attribution.** For S04, S07, S08, S09, S12, S25, S27, S29 and S30, the round commit, severity, files or reviewer were inferred by the extractors from the reports. For S07, S08 and S09 the round commit may be wrong, in which case the graders read slightly different code. S12's attribution to the silent-failure reviewer rests only on its two block rounds. These rows are flagged in `extract/` and isolated in Sensitivity.
- **One leak.** S22's packet text named a later round, so its grades are not blind.
- **Threshold mismatch.** The records show the security reviewer blocking on HIGH in at least three receipts (S08, S10, S20), although edward's config sets its block threshold at CRITICAL.
- **AI graders.** The graders are AI agents, not humans, and were not calibrated against human grades.
- **No counterfactual.** Whether these defects would have been found by a later review, by users or never, and at what cost, is not measured. This study measures the precision of blocks, not net value.
