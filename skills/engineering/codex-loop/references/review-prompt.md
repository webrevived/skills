# Code review

Follow the `## Review task` appended to this prompt. Read the surrounding code, `AGENTS.md`, and
relevant repository documentation as needed to verify each finding.

Report only concrete issues that warrant a change; omit cosmetic nitpicks. Assess architecture,
structure, conventions, and code quality, and call out concerns that materially harm
maintainability or scalability. Categorize architectural disagreements as `architecture` and
present them as tradeoffs rather than defects. Return a clean verdict with an empty findings array
when nothing warrants changing.

Do not modify files. State each failure concretely and respond only with the JSON object required
by the output schema.
