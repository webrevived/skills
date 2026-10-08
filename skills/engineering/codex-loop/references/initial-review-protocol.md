# Review task: changes

Review the diff using the strategy named under `## Review level`. The diff file under
`## Review input` (base commit to reviewed tree) is the complete review boundary. Read surrounding
code and repository instructions when they materially affect a candidate, but do not turn this
into a repository-wide audit.

## Root reviewer procedure

1. Read the full diff yourself before spawning anything. Write a neutral three-to-five line
   description of what the change does and list the changed files. Do not speculate about the
   author's intent beyond what the diff and its doc changes state.
2. Give each finder a brief containing: the repository path, the diff file path, your neutral
   description, its assigned perspective or group, and two to four diff-specific pointers for that
   perspective (which hunks, symbols, deleted blocks, or comments deserve its attention). Briefs
   must differ by perspective; do not send the same brief with the perspective name swapped.
3. Launch finders, collect candidates, deduplicate, verify in batches, then report.

## Shared finder contract

Every finder is read-only and recall-biased. Give each finder this scope and its assigned perspective(s):

- Read the full diff from the diff file, then read the enclosing function or block for every hunk
  at the reviewed tree. Bugs in unchanged lines of a touched function are in scope.
- Read the governing `AGENTS.md`, `CLAUDE.md`, or equivalent repository instructions for the files
  being assessed.
- Consider changed tests as evidence, not proof that the implementation is correct. An assertion
  the diff weakened until it no longer tests the behavior is a candidate.
- A comment, doc line, or docstring the diff made false is a candidate; cite the line.
- Report a pre-existing condition when the change newly relies on it, makes it newly
  reachable, or materially worsens it, and state that causal link. Do not report unrelated
  pre-existing issues or work outside the changed files.
- Anchor every candidate to a changed line, or to the nearest changed line that introduces the
  mechanism when the failure manifests elsewhere.
- Return every candidate with a nameable failure or cost scenario. Do not drop half-believed
  candidates; verification is a separate stage. Do not pad with candidates that have no scenario.
- For every candidate return: file, line, category, severity, concise summary, concrete failure or
  cost scenario, and supporting evidence.
- When returning no candidates, state that the full diff and enclosing code were read and list
  what was checked for this perspective.
- Do not edit, stage, commit, stash, or delete files.

The host allows at most 12 open child agents at once. Launch finders concurrently within that
limit; collect and close them before launching verifiers. A spawn failure reporting a thread
limit means a wave is still open, not that delegation is unavailable: close finished children,
then relaunch the failed spawns. Never downgrade the review because of a thread-limit failure.

Use a fresh context without inherited reviewer conclusions when the delegation tool supports it.
Do not override a child agent's model or reasoning effort; the host configures them. Close
completed children after collecting their results so later waves can reuse the available agent
slots. Retain concise candidate evidence, not transcripts or repeated copies of the diff.
Name children by role: `finder_1`, `finder_2`, etc., `verify_batch_1`, etc., `verify_dedicated_1`,
and `verify_dedicated_2`. Children must not delegate.

If subagent delegation is unavailable, do not degrade to a single-context pass: return no findings,
all-zero `coverage`, and say so in the summary. The host treats that as a failed review.

## Finder perspectives

1. **Line-by-line correctness:** inspect every hunk and its enclosing function. Ask which input,
   state, timing, or platform makes the new behavior fail: inverted conditions, off-by-one,
   null/undefined dereference, missing `await`, falsy-zero checks, wrong-variable copy-paste,
   swallowed errors, derived state that can diverge from its source. Include the language and
   framework edge cases actually in the diff: coercion, nullability, capture semantics, iteration,
   precision, timezone/DST, async cancellation, and component or hook contracts.
2. **Removed-behavior audit:** identify the invariant previously enforced by each deleted or
   replaced path and prove where it is re-established. A removed guard, dropped error path,
   narrowed validation, or deleted assertion with no replacement is a candidate.
3. **Cross-file contract tracing:** follow callers and callees affected by changed preconditions,
   return shapes, errors, side effects, ordering, or timing. Include server-side checks, DTOs,
   schemas, and entities whose stated justification depended on behavior the diff removed, and
   adapters, proxies, registries, caches, and wrappers that misroute, re-enter, forward
   incompletely, or bypass policy.
4. **Reuse:** find changed code that duplicates an existing abstraction or creates parallel logic
   likely to diverge, including two definitions that now render or compute the same thing. Name
   the existing implementation and the concrete divergence risk.
5. **Simplification:** find redundant or derivable state, copy-paste variants, deep branching,
   unnecessary indirection, dead code the diff leaves behind, and complexity that obscures an
   invariant. Name the materially simpler form.
6. **Efficiency:** find redundant computation or I/O, accidental serialization, blocking work in
   startup or hot paths, unbounded work, and resource retention introduced by the change.
7. **Architectural altitude:** determine whether the change fixes the root cause at the right
   depth and layer, or patches a symptom that shared infrastructure should own. Name the deeper
   change when a special case is layered on shared code.
8. **Conventions, docs, and tests:** quote the exact repository rule for any convention violation.
   Check every comment, doc file, and docstring the diff touches or contradicts for statements the
   change made false. Check every changed test for assertions that no longer exercise the
   behavior they name.

## Levels

The host sets the root and child reasoning effort to the selected level. Keep the same evidence
standard at both levels; `medium` reduces breadth, never verification.

| Level | Finders | Initial candidate cap | Batch verifiers, up to 6 candidates each |
| --- | ---: | ---: | ---: |
| medium | 4 grouped | 18 | Up to 3 |
| high | 8 | 24 | Up to 4 |

Allow at most two additional dedicated verifiers for complex candidates, as described below.
Child ceilings are therefore 9 for `medium` and 14 for `high`. These are ceilings, not targets.

### medium

Run four finders, each returning at most 6 candidates across its assigned group:

1. Correctness and removed behavior: perspectives 1 and 2.
2. Contracts and architecture: perspectives 3 and 7.
3. Reuse and simplification: perspectives 4 and 5.
4. Efficiency, conventions, docs, and tests: perspectives 6 and 8.

### high

Run finders 1 through 8, each returning at most 6 candidates.

## Deduplication

Merge candidates that describe the same file, line, and failure mechanism. Preserve the clearest
failure scenario and strongest evidence. Do not merge distinct failure modes merely because they
anchor to the same line.

Before verification, drop only candidates that fall outside the review boundary or that
carry no failure or cost scenario at all. Do not drop a candidate for being uncertain, minor, or
weakly evidenced; that judgment belongs to the verifier.

Rank the remaining candidates by severity, strength of repository evidence, concreteness of the
failure scenario, and likely affected surface. Apply the table's initial candidate cap. Assign stable
`C1`, `C2`, etc. IDs before shortlisting; retain them through batching. Put candidates
excluded by the cap in `unchecked_candidates` with their location, failure scenario, and reason
`candidate_cap`. Remove an entry only if that candidate subsequently receives a verifier verdict.

## Independent verification

Partition the shortlist into disjoint batches of at most six
candidates. Group by related code to share necessary context, while judging every candidate
separately. Use the fewest batches that fit, within the table's limit; do not pad empty batches.
Launch one fresh skeptic verifier per batch. It must not have participated in discovery.

Give each verifier candidate IDs and evidence, the diff file path, and the repository location,
but not a preferred verdict, finder identity, or other verifiers' conclusions. Require it to
read the full diff once, inspect the relevant surrounding code, and return exactly one verdict
with evidence per assigned ID. One refutation must not dispose of a different candidate.

When a candidate needs unusually extensive tracing or reproduction (for example a concurrency
race or an authorization boundary), assign it alone to a dedicated verifier and remove it from
the batches. Allow at most two dedicated verifiers total. Record the reason for isolation. Use the
selected effort; do not raise it.

Use these verdicts for both batch and dedicated verification:

- `CONFIRMED` — can name the inputs or state that trigger it and the wrong output, cost, or
  contradiction. Quote the line.
- `PLAUSIBLE` — the mechanism is real and the trigger is realistic but uncertain (timing,
  environment, configuration, concurrent state, a rare but reachable path). State what would
  confirm it.
- `REFUTED` — factually wrong (the code does not say that), provably impossible from a type,
  constant, or invariant, already handled in this diff, pre-existing and unaffected, or pure
  style with no observable effect. Quote the line that proves it.

Default to `PLAUSIBLE` when the state is realistic. Do not refute a candidate for being
speculative when the code does not exclude the trigger. Refute only with evidence constructible
from the code.

Require a verdict and evidence for every assigned ID, with no missing, duplicate, or invented
IDs. Check completeness before closing the verifier. Ask the same verifier to finish an incomplete
batch; do not spawn replacement agents to bypass the budget. Put any candidate still missing a
verdict in `unchecked_candidates` with reason `verification_incomplete`; do not silently drop it or
infer a refutation. Drop `REFUTED` candidates. Set `validation` to `confirmed` or `plausible` for
the others.

## Final ranking

Rank confirmed before plausible, then by severity and concreteness. Report every confirmed or
plausible finding; never drop a verified finding to shorten the report, and never invent findings.
Set `verdict: incomplete` whenever `unchecked_candidates` is nonempty, even when every checked
candidate was refuted. Otherwise use `findings` or `clean` according to whether findings remain.

Fill `coverage` with the actual counts: finders run, verifier batches, dedicated verifiers,
candidates assigned to verifiers, and candidates that received a verdict. The host checks these
against Codex's child telemetry, so report what happened, not what the level planned.
