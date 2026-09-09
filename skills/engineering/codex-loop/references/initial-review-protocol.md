# Review task: staged changes

Review the staged diff using the strategy named under `## Review level`. The staged diff is the
complete review boundary. The host saved a copy at the path under `## Diff file`; `git diff
--cached` in the repository is the same content. Read surrounding code and repository instructions
when they materially affect a candidate, but do not turn this into a repository-wide audit.

## Root reviewer procedure

1. Read the full diff yourself before spawning anything. Write a neutral three-to-five line
   description of what the change does and list the changed files. Do not speculate about the
   author's intent beyond what the diff and its doc changes state.
2. Give each finder a brief containing: the repository path, the diff file path, your neutral
   description, its single assigned perspective, and two to four diff-specific pointers for that
   perspective (which hunks, symbols, deleted blocks, or comments deserve its attention). Briefs
   must differ by perspective; do not send the same brief with the perspective name swapped.
3. Launch finders, collect candidates, deduplicate, verify, run the gap sweep, then report.

## Shared finder contract

Every finder is read-only and recall-biased. Give each finder this scope and one perspective:

- Read the full diff from the diff file, then read the enclosing function or block for every hunk
  in the repository. Bugs in unchanged lines of a touched function are in scope.
- Read the governing `AGENTS.md`, `CLAUDE.md`, or equivalent repository instructions for the files
  being assessed.
- Consider changed tests as evidence, not proof that the implementation is correct. An assertion
  the diff weakened until it no longer tests the behavior is a candidate.
- A comment, doc line, or docstring the diff made false is a candidate; cite the line.
- Report a pre-existing condition when the staged change newly relies on it, makes it newly
  reachable, or materially worsens it, and state that causal link. Do not report unrelated
  pre-existing issues or work outside the staged files.
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
limit and run verifiers in waves of at most 12. A spawn failure reporting a thread limit means a
wave is still open, not that delegation is unavailable: close finished children, then relaunch
the failed spawns. Never downgrade the review because of a thread-limit failure.

Use a fresh context without inherited reviewer conclusions when the delegation tool supports it.
Do not override a child agent's model or reasoning effort; the host configures them. Close
completed children after collecting their results so later waves can reuse the available agent
slots. Retain concise candidate evidence, not transcripts or repeated copies of the diff.

If subagent delegation is unavailable, explicitly downgrade the initial review to `low` semantics
regardless of the requested level. Perform one single-context pass, do not claim independent finder
or verifier coverage, return at most 4 findings with `validation: unverified`, and state the
degraded coverage in the result summary.

## Finder perspectives

1. **Line-by-line correctness:** inspect every hunk and its enclosing function. Ask which input,
   state, timing, or platform makes the new behavior fail: inverted conditions, off-by-one,
   null/undefined dereference, missing `await`, falsy-zero checks, wrong-variable copy-paste,
   swallowed errors, derived state that can diverge from its source.
2. **Removed-behavior audit:** identify the invariant previously enforced by each deleted or
   replaced path and prove where it is re-established. A removed guard, dropped error path,
   narrowed validation, or deleted assertion with no replacement is a candidate.
3. **Cross-file contract tracing:** follow callers and callees affected by changed preconditions,
   return shapes, errors, side effects, ordering, or timing. Include server-side checks, DTOs,
   schemas, and entities whose stated justification depended on behavior the diff removed.
4. **Reuse:** find staged code that duplicates an existing abstraction or creates parallel logic
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
9. **Language-specific edge cases:** concentrate on the actual languages and frameworks in the
   diff, including coercion, falsy values, nullability, capture semantics, mutable defaults,
   iteration behavior, precision, timezone/DST behavior, async cancellation, and framework
   component or hook contracts (for example a UI library prop whose absence changes rendering).
10. **Delegation and wrapper correctness:** inspect adapters, proxies, registries, caches,
    clients, decorators, and wrappers for incorrect routing, re-entry, incomplete forwarding,
    inconsistent lifecycle, or bypassed policy.

## Levels

The level selects breadth: finder count, candidate caps, and the final finding cap. Reasoning
depth is fixed by the host and does not change with the level.

### low

Use no subagents. Perform one focused pass over every staged hunk and the immediately enclosing
code. Look for concrete correctness, security, performance, and integration failures. Avoid broad
history or repository exploration. Do not run independent candidate verification. Return at most
4 findings and set their `validation` to `unverified`.

### medium

Run finders 1 through 8, each returning at most 6 candidates. Deduplicate, verify every
shortlisted candidate, run the gap sweep, and return at most 8 findings.

### high

Run finders 1 through 10, each returning at most 6 candidates. Deduplicate, verify every
shortlisted candidate, run the gap sweep, and return at most 10 findings.

### xhigh

Run finders 1 through 10, each returning at most 8 candidates. Deduplicate, verify every
shortlisted candidate, run the gap sweep with its larger allowance, and return at most 15 findings.

## Deduplication

Merge candidates that describe the same file, line, and failure mechanism. Preserve the clearest
failure scenario and strongest evidence. Do not merge distinct failure modes merely because they
anchor to the same line.

Before verification, drop only candidates that fall outside the staged-change boundary or that
carry no failure or cost scenario at all. Do not drop a candidate for being uncertain, minor, or
weakly evidenced; that judgment belongs to the verifier.

Rank the remaining candidates by severity, strength of repository evidence, concreteness of the
failure scenario, and likely affected surface. Shortlist at most 20 candidates for `medium`, 24
for `high`, or 30 for `xhigh`. The shortlist is a ceiling, not a target.

## Independent verification

For `medium`, `high`, and `xhigh`, launch one fresh skeptic verifier per shortlisted candidate, in
parallel waves when necessary. Give the verifier the candidate, the diff file path, and the
repository location, but not a preferred verdict or finder identity. The verifier must inspect
the actual diff and surrounding code and return exactly one verdict with a short reason:

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

Drop `REFUTED` candidates. Set `validation` to `confirmed` or `plausible` for the others.

## Gap sweep

After verification, launch one fresh finder with the deduplicated verified list. It must re-read
the diff and enclosing code looking only for defects not already listed, especially: dropped
guards in moved code, default-value changes, nondeterminism, narrowed locking, side-effecting
predicates, asymmetric test setup and teardown, configuration-default flips, and stale comments,
docs, or assertions the first pass missed. It returns up to 6 additional candidates at `medium`
and `high`, or up to 8 at `xhigh`, or an empty sweep. Pass each through the same deduplication
and independent verification before reporting.

## Final ranking

Rank confirmed before plausible, then by severity and concreteness. Apply the selected level's
final finding cap only after verification. Never invent extra findings to fill the cap.
