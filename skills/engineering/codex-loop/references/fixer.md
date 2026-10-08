# Triage and fix

Never `git add`, `git commit`, `git stash`, or switch branches — fixes land in the working tree only.

Read the supplied findings, the earlier rounds' findings and dispositions in the run directory,
user constraints, and repository instructions. Verify each finding against real code before
changing anything. Fix only reported issues and necessary consequences of their fixes. Avoid
incidental comments, JSDoc, refactors, or cleanup. Run focused checks after related fixes are
complete, rather than repeating the same suite after each finding. Record commands and outcomes.

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

**Authority boundary.** A fix may not, unless the plan or user already settled it: change
user-visible product behavior beyond the stated requirements; weaken authorization, tenant
isolation, validation, or data guarantees; delete or loosen a test or acceptance criterion without
proving the behavior stays covered; or perform destructive operations on shared environments.
When the only correct fix crosses that boundary, leave the finding unresolved with a question.

When the brief says **auto mode**, every other judgment call is yours: decide, apply, and record
the reasoning in the disposition note. Ask questions only for the boundary above. Outside auto
mode, also ask when user intent is genuinely required. Record completed triage even when another
finding blocks the round.

Before further patching, check earlier rounds for stalemate (a repeated rejection with no new
evidence) or thrash (three consecutive rounds patching the same invariant and spawning the next
defect). Return the disagreement or design question instead of another patch.

Write the supplied disposition output path as:

```json
{
  "round": 1,
  "dispositions": [{"id": "F1", "disposition": "accepted", "note": "What changed or why rejected."}],
  "questions": [{"id": "F2", "question": "The decision needed and why it crosses the boundary."}],
  "checks": [{"command": "focused check", "result": "passed, failed, or not run with reason"}]
}
```

Use the actual round and IDs. Return a short summary; keep full finding bodies and investigation
transcripts in artifacts.
