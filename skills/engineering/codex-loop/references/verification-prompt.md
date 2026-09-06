# Review task: fix verification

Read the prior findings and dispositions at the appended paths. Inspect the cumulative unstaged
fixes (`git diff`) and new untracked files; use staged changes only as context. Do not run general
finder fan-out or discover unrelated staged-change issues.

- Accepted/modified: report only an incorrect or incomplete fix.
- Rejected: re-report only with evidence that defeats the rebuttal, including a direct
  counter-argument. A correct rebuttal closes the finding.
- Outside-review/separate-follow-up/user-deferred: do not re-report.
- New findings: only regressions introduced by the fixes.

Set `repeat_of` to `R<prior-round>-F<n>` for a repeated finding. Set `validation` to `confirmed`
when repository evidence proves it or `plausible` when a material runtime/product assumption
remains. No new independent verifier fan-out is required in these targeted rounds.

Return `clean` with no findings when fixes and rebuttals need no further action. State any
checks you could not perform in the summary; do not imply tests ran when they did not.
Reuse recorded check results when they still apply to the current code. Re-run checks only to
resolve a concrete evidence gap or suspected regression; always inspect the fix independently.
