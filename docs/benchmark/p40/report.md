# P40: are ship-sop's blocks real? Blind precision sample from edward

**Date:** 2026-10-11. **Data:** edward's ship-gate records, 8 Sep to 11 Oct 2026. **Files:** this folder.

## Answer

About half of the gate's blocks were real defects, and few were false alarms. All 29 sampled blocks were raised on commits whose test suite had already passed, so the tests had not caught any of them. This shows the gate catches real defects the tests miss. It does not show the gate is worth its cost: what those defects would have cost if caught later, or never, was not measured.

| Blind grade of 29 blocking findings | Grader A | Grader B | Both graders |
|---|---|---|---|
| Real defect | 17 (59%) | 14 (48%) | 14 (48%) |
| Correct but minor | 9 | 10 | 8 |
| False positive | 3 (10%) | 5 (17%) | 2 (7%) |

The graders agreed on 24 of 29 (83%). Where they disagreed, B was the stricter: three findings A rated real, B rated minor or false. Grader B's instructions included "be sceptical, automated reviewers often overstate"; A's did not. This difference was not planned, so read the two columns as a lenient and a sceptical framing of the same evidence.

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

No, on the record. ship-sop's `/ship` runs the project's test suite before the reviewers and halts on a failure. Every sampled receipt records its tests as PASS. Each blocking finding was raised on a commit whose existing suite passed, so none of the 14 confirmed defects was caught by edward's tests.

## Cost

Measured from edward's 174 schema-2 receipts (8 Sep to 11 Oct 2026):

| Measure | Count |
|---|---|
| Reviewer launches | 636 |
| Re-checks | 824 |
| Reviewer runs in total | 1,460 |
| Reviewer runs per shipped change, on average | 8.4 |
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
- **Inferred attribution.** For S12, S25, S29 and S30, the severity or files were inferred by the extractors from the reports; they are flagged in `extract/`.
- **Threshold mismatch.** The records show the security reviewer blocking on HIGH in at least three receipts (S08, S10, S20), although edward's config sets its block threshold at CRITICAL.
- **AI graders.** The graders are AI agents, not humans, and were not calibrated against human grades.
- **No counterfactual.** Whether these defects would have been found by a later review, by users or never, and at what cost, is not measured. This study measures the precision of blocks, not net value.
