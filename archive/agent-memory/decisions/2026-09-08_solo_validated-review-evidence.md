# Review receipts replace Markdown coverage stamps

**Date:** 2026-09-08
**Agent:** solo (Codex)
**Work item:** P32

Only a complete validated JSON receipt qualifies for automatic coverage. The
trusted installed ship-receipt tool calls Agent SOP's shared policy validator.
It binds the actual reviewed commit/tree, base, policy, configured reviewers and
test evidence, and rejects BLOCK, INCOMPLETE and malformed inputs. The parent
writes the human report from actual isolated reviewer output. A fix commit needs
fresh review; earlier results cannot be relabelled with a later SHA.

Review processes retain usage, runtime, elapsed time, exit and timeout information
under .ship/reviews. Missing usage differs from failed parsing. The default model
and reviewer set remain unchanged pending a controlled cost/quality comparison.
Independent clones and read-only execution remain the reviewer boundary.

Upgrade Agent SOP and ship-sop together. The shared verifier is hosted in Agent
SOP for compatibility in this release; extracting a standalone versioned verifier
is future packaging work. Receipts guard against accidental invalid evidence,
not a deliberately dishonest author controlling local files.
