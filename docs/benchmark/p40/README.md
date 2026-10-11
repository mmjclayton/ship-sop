# P40 sample: blocking findings from edward's ship gate

- `frame.tsv`: every reviewer-run that blocked at least once in edward's schema-2 receipts (receipt, reviewed HEAD, reviewer, block rounds). 231 rows from 124 receipts (25 Sep to 11 Oct 2026), built from `edward/docs/reviews/*-ship-auto.json` on 11 Oct 2026.
- `sample.tsv`: 30 reviewer-runs, stratified by reviewer in proportion to blocks (silent-failure-hunter 14, code-reviewer 11, security-reviewer 5), drawn with Python `random.Random(40)` over each reviewer's sorted rows.
- Next: one blocking finding per sampled run, extracted as a claim only (no fix or disposition), selected with the same seed, committed before grading.
- `extract/batch{1,2,3}.json`: per sampled run, the reviewer's blocking findings restated as claims (three fresh extraction agents, read-only over edward, told to strip fixes and dispositions). Notes on how each round's commit was identified are in `commit_note`, kept out of the grading packet because some name later fix commits.
- `selected.json`: one finding per run, picked with `random.Random(40)` among findings at blocking severity (HIGH or CRITICAL, including ones marked implied or inferred). S14 is excluded: its report lists nine round-one items without saying which were the silent-failure reviewer's blocking ones. 29 findings remain.
- `grading-packet.json`: what the graders see: id, reviewed commit, severity, file, line, claim. Committed before grading.

## Reproducing the draws

```python
import csv, json, random
rows = list(csv.reader(open('frame.tsv'), delimiter='\t'))
rng = random.Random(40)  # one shared instance, reviewers drawn in this order
sample = []
for reviewer, k in (('silent-failure-hunter', 14), ('code-reviewer', 11), ('security-reviewer', 5)):
    sample += rng.sample(sorted(r for r in rows if r[2] == reviewer), k)
sample.sort()  # ids S01..S30 follow this order

# Finding selection: a fresh Random(40), rows in id order, one choice per row
# among findings whose severity starts with HIGH or CRITICAL; rows with none are excluded.
rng = random.Random(40)
for row in sorted(extracted_rows, key=lambda r: r['id']):
    eligible = [f for f in row['findings'] if f['severity'].split()[0] in ('HIGH', 'CRITICAL')]
    if eligible:
        pick = rng.choice(eligible)
```

S04's pick came from its round-two commit, which the claim text named. Its `reviewed_commit` was corrected to fbdd9d2 before grading (16f82ad).
