# Path-scoped reviewer enablement

Shipped P33 after the user authorised the P32 merge (PR #15) and then the
mechanism. Optional `paths` (regular expressions) per agent in
`ship-sop.config.json`; a reviewer with `paths` joins the gate only when a path
changed in the review range matches. Schema, template (security-reviewer scoped
to shell, server/auth/route code, HTML templates, env and container files,
workflows, SQL), `/ship` and `$ship` (both read the in-scope set from the
installed agent-sop library, P111), the legacy hook, README and the integration
and contract tests. CI green; user-scope `/ship` and the Codex ship skill
refreshed from main.

Source: the 2026-09-24 gate-yield review of eleven Opportunity Scan receipts
(P27's cost work continued): the two reviewers with the blocking yield stay
unscoped; the reviewer whose yield follows the diff gets a scope. P34 (run and
round counts in Claude receipts, since receipts carry no cost field) is filed
and waits for authorisation.
