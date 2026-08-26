# Code review

Follow the `## Review task` appended to this prompt. Read the surrounding code, `AGENTS.md`, and
relevant repository documentation as needed to verify each finding.

Report only concrete issues introduced or materially worsened by the reviewed changes that should
be addressed before committing this phase. A pre-existing condition is in scope only when the
changes rely on it, worsen it, or make it newly reachable. Omit cosmetic nitpicks, optional
improvements, unrelated follow-ups, and separate feature ideas.

Assess architecture, structure, conventions, and code quality. Report an architectural concern
only when the current change creates a material maintainability or scalability risk; categorize it
as `architecture` and explain the tradeoff rather than presenting taste as a defect. Return a clean
verdict with an empty findings array when no action is required before commit.

Do not modify files. State each failure concretely and respond only with the JSON object required
by the output schema.
