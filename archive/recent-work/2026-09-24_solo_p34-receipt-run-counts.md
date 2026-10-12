# Receipt schema version 2 with run counts

Shipped P34 with agent-sop P112 on the user's go, the third item of the day
after P32 (merge) and P33 (path-scoped reviewers). `ship-receipt.sh` writes
`schema_version` 2; each reviewer entry carries launches, rechecks, block_rounds
and usage (null unless the runtime reports one). `/ship` and `$ship` name the
fields and ask for launches and re-checks in the report table; the integration
test refuses an uncounted receipt; the contract stub carries the same rule.
Version-1 receipts stay valid. CI green; user-scope `/ship`, the Codex ship
skill and both `ship-receipt.sh` copies refreshed from main.

Left out: filling `usage` from the Codex runner telemetry. The read of
`codex-review.sh` needed for that wiring was refused by the session's tool
classifier, so the field stays null on both runtimes. P25 remains OPEN.
