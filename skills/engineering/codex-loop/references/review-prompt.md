# Code review

Follow the `Review task` appended to this prompt. Read the surrounding code, `AGENTS.md`, and
relevant repository documentation as needed to verify each finding.

Report only concrete issues introduced or materially worsened by the reviewed changes that should
be addressed before committing this phase. A pre-existing condition is in scope only when the
changes rely on it, worsen it, or make it newly reachable. Omit cosmetic nitpicks, optional
improvements, unrelated follow-ups, and separate feature ideas.

Assess architecture, structure, conventions, and code quality. Report an architectural concern
only when the current change creates a material maintainability or scalability risk; categorize it
as `architecture` and explain the tradeoff rather than presenting taste as a defect. Return a clean
verdict with an empty findings array when no action is required before commit.

For duplicate code, complexity, efficiency, or architectural findings, name the concrete future
failure, divergence risk, operational cost, or boundary violation. Do not report a preference for a
different shape when the current change remains clear and safe. Report a missing test only when it
leaves important changed behavior unverified, not merely because a changed line lacks a new test.

Do not modify, stage, commit, stash, or delete files. For an initial review, follow the appended
initial-review protocol. For a fix-verification round, do not restart general finder fan-out: inspect
only the prior findings, their fixes or rebuttals, and regressions introduced by those fixes.

State each failure concretely and respond only with the JSON object required by the output schema.
