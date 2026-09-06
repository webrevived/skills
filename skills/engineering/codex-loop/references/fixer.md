# Triage and fix

Never `git add`, never `git commit`, never touch the index — fixes land in the working tree only.

Read the supplied findings, relevant ledger entries, user constraints, and repository instructions.
Verify each finding against real code before changing anything. Fix only reported issues and
necessary consequences of their fixes. Avoid incidental comments, JSDoc, refactors, or cleanup.
Run appropriate focused checks after related fixes are complete, rather than repeating the same
suite after each finding. Record the commands and outcomes for the verification reviewer.

Assign exactly one disposition to every finding, except an unresolved question:

| Disposition | Meaning |
| --- | --- |
| `accepted` | Real in-scope issue; applied the proposed fix. |
| `modified` | Real in-scope issue; applied a different fix. |
| `rejected` | Incorrect finding; give the concrete rebuttal. |
| `outside-review` | Pre-existing, neither worsened nor newly relied upon by the changes. |
| `separate-follow-up` | Real work explicitly excluded from this phase or requiring a materially separate feature, phase, or external dependency. Explain why it cannot be completed here and the exact next action. |
| `user-deferred` | Verified in-scope issue the user explicitly chose not to fix. Cite that decision. |

Default real in-scope issues to accepted/modified. Inconvenience, low severity, fix size, or code
outside originally edited lines does not justify a follow-up. Never choose user-deferred yourself.
If user intent is required, leave that finding unresolved with a question; do not invent a
disposition. Record completed triage even when another finding blocks the round.

Before further patching, check prior ledger history for stalemate (a repeated rejection with no
new evidence) or thrash (three consecutive rounds patching the same invariant and spawning the
next defect). Return the disagreement/design question instead of another patch.

Write the supplied disposition output path as:

```json
{
  "round": 1,
  "dispositions": [{"id": "F1", "disposition": "accepted", "note": "What changed or why rejected."}],
  "questions": [],
  "checks": [{"command": "focused check", "result": "passed, failed, or not run with reason"}]
}
```

Use the actual round and IDs. Each question must identify its finding and needed decision.
Return a short summary; keep full finding bodies and investigation transcripts in artifacts.
