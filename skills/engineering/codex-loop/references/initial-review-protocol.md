# Review task: changes

The diff file under `## Review input` (base commit to reviewed tree) is the review boundary. Read
surrounding code and repository instructions when they bear on a candidate; this is not a
repository-wide audit. Use the strategy for the level under `## Review level`.

The review has two stages with opposite biases. Keep them separate:

- **Finding is recall-biased.** Finders return every candidate with a nameable failure or cost
  scenario, including half-believed ones. Do not apply the report rules at this stage.
- **Verification is precision-biased.** Verifiers decide from the code whether each candidate is
  confirmed, plausible, or refuted. Only confirmed and plausible candidates are reported.

A clean result is legitimate only when finders looked hard and verifiers refuted what they found.

## Procedure

1. Read the full diff yourself. Write a neutral three-to-five line description of what it does and
   list the changed files. Do not speculate about intent beyond what the diff and its docs state.
2. Brief each finder with the repository path, diff file path, your description, its
   perspective(s), and two to four diff-specific pointers (hunks, symbols, deleted blocks,
   comments) for that perspective. Briefs must differ in substance, not just in perspective name.
3. Launch the finders concurrently, collect and close them, deduplicate, verify, then report.

## Finders

Every finder:

- reads the full diff, then the enclosing function or block of every hunk at the reviewed tree
  (bugs in unchanged lines of a touched function are in scope), and the governing repository
  instructions;
- treats changed tests as evidence, not proof;
- reports a pre-existing condition only when the change relies on it, newly reaches it, or worsens
  it, stating that link;
- anchors each candidate to the changed line that introduces the mechanism;
- returns at most 6 candidates, each with file, line, category, severity, summary, concrete failure
  or cost scenario, and evidence;
- when returning none, states that it read the full diff and enclosing code and what it checked.

Perspectives:

1. **Correctness:** inputs, state, timing, or platform that make the new behavior fail, including
   the language and framework edge cases actually in the diff.
2. **Removed behavior:** the invariant each deleted or replaced path enforced, and where it is
   re-established. A removed guard or check with no replacement is a candidate.
3. **Cross-file contracts:** callers, callees, schemas, adapters, caches, and wrappers affected by
   changed preconditions, return shapes, errors, side effects, ordering, or timing.
4. **Reuse:** changed code that duplicates an existing abstraction or creates parallel logic likely
   to diverge. Name the existing implementation.
5. **Simplification:** redundant or derivable state, copy-paste variants, needless indirection, or
   dead code the diff leaves behind. Name the simpler form.
6. **Efficiency:** redundant computation or I/O, accidental serialization, blocking work in startup
   or hot paths, unbounded work, or resource retention.
7. **Architectural altitude:** a symptom patched at the wrong depth or layer, or a special case on
   shared code that shared infrastructure should own. Name the deeper change.
8. **Conventions, docs, and tests:** violations of a repository rule (quote it), comments or docs
   the change made false (cite the line), and test assertions that no longer exercise what they name.

## Levels

The host sets root and child reasoning effort to the level. `medium` reduces breadth, never the
evidence standard.

| Level | Finders | Candidate cap | Batch verifiers, up to 6 candidates each |
| --- | --- | ---: | ---: |
| medium | 4, grouped by perspective: 1+2, 3+7, 4+5, 6+8 | 18 | up to 3 |
| high | 8, one per perspective | 24 | up to 4 |

Allow at most two additional dedicated verifiers. These are ceilings, not targets.

## Delegation

- At most 12 children may be open at once. A spawn failure reporting a thread limit means a wave
  is still open, not that delegation is unavailable: close finished children and relaunch. Never
  downgrade the review because of it.
- Use fresh children without inherited reviewer conclusions. Do not override a child's model or
  reasoning effort. Children must not delegate.
- Name children `finder_1`, `finder_2`, …, `verify_batch_1`, …, `verify_dedicated_1`, and
  `verify_dedicated_2`.
- If delegation is unavailable, do not fall back to a single-context pass: return no findings and
  all-zero `coverage`, and say so in the summary. The host treats that as a failed review.

## Deduplication

Merge candidates with the same file, line, and failure mechanism, keeping the clearest scenario
and strongest evidence; keep distinct failure modes on the same line separate. Drop only
candidates outside the boundary or with no scenario at all. Uncertainty, low severity, and weak
evidence are the verifier's call.

Assign stable IDs `C1`, `C2`, …, rank by severity, evidence, concreteness, and affected surface,
and apply the candidate cap. Candidates beyond the cap go to `unchecked_candidates` with reason
`candidate_cap`.

## Verification

Partition the shortlist into the fewest disjoint batches of at most six, grouped by related code,
within the level's limit. Launch one fresh skeptic per batch; it must not have been a finder. Give
it the candidate IDs and evidence, the diff file path, and the repository location, but no
preferred verdict, finder identity, or other verdicts. A candidate that needs extensive tracing
(a race, an authorization boundary) may go alone to a dedicated verifier; record why.

Each verifier reads the full diff, inspects the surrounding code for every candidate itself (an
unchanged guard or caller can make a failure unreachable), judges every candidate separately, and
returns exactly one verdict with evidence per ID:

- `CONFIRMED`: names the triggering input or state and the wrong output, cost, or contradiction,
  quoting the line.
- `PLAUSIBLE`: the mechanism is real and the trigger realistic but uncertain; states what would
  confirm it. Default here when the state is realistic.
- `REFUTED`: the code does not say that, a type, constant, or invariant makes it impossible, the
  diff already handles it, it is pre-existing and unaffected, or it is style with no observable
  effect. Quotes the proving line. Never refute a candidate merely for being speculative.

Check each verifier's result for missing, duplicate, or invented IDs before closing it, and ask
the same verifier to finish an incomplete batch rather than spawning a replacement. A candidate
still without a verdict goes to `unchecked_candidates` with reason `verification_incomplete`.
Drop refuted candidates; set `validation` to `confirmed` or `plausible` for the rest.

## Result

Report every confirmed or plausible finding, confirmed first, then by severity and concreteness.
Never drop a verified finding or invent one. `verdict` is `incomplete` whenever
`unchecked_candidates` is nonempty, otherwise `findings` or `clean`. Fill `coverage` with what
actually happened: finders run, verifier batches, dedicated verifiers, candidates assigned to
verifiers, and candidates that received a verdict. The host checks these against Codex's child
telemetry.
