# P40 sample: blocking findings from edward's ship gate

- `frame.tsv`: every reviewer-run that blocked at least once in edward's schema-2 receipts (receipt, reviewed HEAD, reviewer, block rounds). 231 rows from 124 receipts, built from `edward/docs/reviews/*-ship-auto.json` on 11 Oct 2026.
- `sample.tsv`: 30 reviewer-runs, stratified by reviewer in proportion to blocks (silent-failure-hunter 14, code-reviewer 11, security-reviewer 5), drawn with Python `random.Random(40)` over each reviewer's sorted rows.
- Next: one blocking finding per sampled run, extracted as a claim only (no fix or disposition), selected with the same seed, committed before grading.
