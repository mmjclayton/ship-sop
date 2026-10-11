# P40 sample: blocking findings from edward's ship gate

- `frame.tsv`: every reviewer-run that blocked at least once in edward's schema-2 receipts (receipt, reviewed HEAD, reviewer, block rounds). 231 rows from 124 receipts, built from `edward/docs/reviews/*-ship-auto.json` on 11 Oct 2026.
- `sample.tsv`: 30 reviewer-runs, stratified by reviewer in proportion to blocks (silent-failure-hunter 14, code-reviewer 11, security-reviewer 5), drawn with Python `random.Random(40)` over each reviewer's sorted rows.
- Next: one blocking finding per sampled run, extracted as a claim only (no fix or disposition), selected with the same seed, committed before grading.
- `extract/batch{1,2,3}.json`: per sampled run, the reviewer's blocking findings restated as claims (three fresh extraction agents, read-only over edward, told to strip fixes and dispositions). Notes on how each round's commit was identified are in `commit_note`, kept out of the grading packet because some name later fix commits.
- `selected.json`: one finding per run, picked with `random.Random(40)` among findings at blocking severity (HIGH or CRITICAL, including ones marked implied or inferred). S14 is excluded: its report lists nine round-one items without saying which were the silent-failure reviewer's blocking ones. 29 findings remain.
- `grading-packet.json`: what the graders see: id, reviewed commit, severity, file, line, claim. Committed before grading.
