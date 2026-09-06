# Review task: staged changes

Review `git diff --cached` using the strategy named under `## Review level`. The staged diff is the
complete review boundary. Read surrounding code and repository instructions when they materially
affect a candidate, but do not turn this into a repository-wide audit.

## Shared finder contract

Every finder is read-only. Give each finder this scope and one assigned perspective:

- Inspect the staged diff and enough surrounding code to prove concrete issues introduced or
  materially worsened by it.
- Read the governing `AGENTS.md`, `CLAUDE.md`, or equivalent repository instructions for the files
  being assessed.
- Consider changed tests as evidence, not proof that the implementation is correct.
- Do not report unrelated pre-existing issues, cosmetic preferences, speculative future features,
  or cleanup that is unrelated to the staged changes. Do report a pre-existing condition when the
  staged change newly relies on it, makes it newly reachable, or materially worsens it, and state
  that causal link explicitly.
- Anchor every candidate to a changed line, or to the nearest changed line that introduces the
  mechanism when the failure manifests elsewhere.
- For every candidate return: file, line, category, severity, concise summary, concrete failure or
  cost scenario, and supporting evidence. Return no candidate when the perspective finds nothing.
- Do not edit, stage, commit, stash, or delete files.

Launch independent finders concurrently when the host permits. When concurrency is smaller than
the finder count, use waves. Give each finder a fresh role-specific brief; do not ask one finder to
simulate several independent reviewers unless the selected level explicitly combines perspectives.
Use a fresh context without inherited reviewer conclusions when the delegation tool supports it.
Do not override a child agent's model or reasoning effort; inherit them from this reviewer.
Close completed children after collecting their results so later waves can reuse the available
agent slots. Retain concise candidate evidence, not transcripts or repeated copies of the diff.

If subagent delegation is unavailable, explicitly downgrade the initial review to `low` semantics
regardless of the requested level. Perform one single-context pass, do not claim independent finder
or verifier coverage, return at most 4 findings with `validation: unverified`, and state the
degraded coverage in the result summary.

## Levels

### low

Use no subagents. Perform one focused pass over every staged hunk and the immediately enclosing
code. Look for concrete correctness, security, performance, and integration failures. Avoid broad
history or repository exploration. Do not run independent candidate verification. Return at most
4 findings and set their `validation` to `unverified`.

### medium

Run four independent finders, each returning at most 6 candidates:

1. Line-by-line correctness, edge cases, error handling, and changed tests.
2. Removed behavior, lost invariants, and cross-file caller/callee contracts.
3. Reuse, duplication, simplification, cyclomatic complexity, and avoidable work.
4. Architectural altitude, repository conventions, boundaries, and maintainability.

Deduplicate, apply the pre-verification shortlist, and independently verify every shortlisted
candidate. Return at most 8 findings.

### high

Run eight independent finders, each returning at most 6 candidates:

1. **Line-by-line correctness:** inspect every hunk and its enclosing function. Ask which input,
   state, timing, or platform makes the new behavior fail.
2. **Removed-behavior audit:** identify the invariant previously enforced by each deleted or
   replaced path and prove where it is re-established.
3. **Cross-file contract tracing:** follow callers and callees affected by changed preconditions,
   return shapes, errors, side effects, ordering, or timing.
4. **Runtime and safety pitfalls:** inspect language/framework hazards, state and concurrency,
   security boundaries, validation, serialization, timezones, numeric behavior, and resource
   lifecycle where relevant to the change.
5. **Reuse:** find staged code that duplicates an existing abstraction or creates parallel logic
   likely to diverge. Name the existing implementation and the concrete divergence risk.
6. **Simplification:** find redundant or derivable state, copy-paste variants, deep branching,
   unnecessary indirection, and complexity that obscures an invariant. Name the materially simpler
   form and why it reduces defect risk.
7. **Efficiency:** find redundant computation or I/O, accidental serialization, blocking work in
   startup or hot paths, unbounded work, and resource retention introduced by the change.
8. **Architectural altitude and conventions:** determine whether the change belongs at the chosen
   layer, bypasses an owning boundary, or violates an exact repository rule. Quote the governing
   rule when reporting a convention violation.

Deduplicate, apply the pre-verification shortlist, and independently verify every shortlisted
candidate. Return at most 10 findings.

### xhigh

Run all eight `high` finders with a limit of 8 candidates each, plus two independent finders:

9. **Language-specific edge cases:** concentrate on the actual languages and frameworks in the
   diff, including coercion, falsy values, nullability, capture semantics, mutable defaults,
   iteration behavior, precision, timezone/DST behavior, and async cancellation when applicable.
10. **Delegation and wrapper correctness:** inspect adapters, proxies, registries, caches, clients,
    decorators, and wrappers for incorrect routing, re-entry, incomplete forwarding, inconsistent
    lifecycle, or bypassed policy.

After ordinary verification, launch one fresh gap-sweep finder with the deduplicated verified list.
It must look only for missed staged-change defects, especially dropped guards in moved code,
default-value changes, nondeterminism, narrowed locking, side-effecting predicates, asymmetric test
setup/teardown, and configuration-default flips. Reserve 8 of the global 30 xhigh verifier slots for
this sweep. Accept at most 8 gap candidates and pass each through the same deduplication and
independent verification before reporting. Ordinary and gap candidates combined must never exceed
30 verifier launches. Return at most 15 findings overall.

## Deduplication

Merge candidates that describe the same file, line, and failure mechanism. Preserve the clearest
failure scenario and strongest evidence. Do not merge distinct failure modes merely because they
anchor to the same line.

Before verification, drop candidates that lack a concrete failure or material cost, fall outside
the staged-change boundary, or amount only to optional cleanup.

Rank the remaining candidates by severity, strength of repository evidence, concreteness of the
failure scenario, and likely affected surface. Before launching verifiers, shortlist at most 16
candidates for `medium`, 20 for `high`, or 22 ordinary candidates for `xhigh`; xhigh reserves its
remaining 8 slots for the later gap sweep. Preserve distinct failure mechanisms and supported
perspectives when candidates are otherwise comparable. The shortlist is a ceiling, not a target;
do not retain weak candidates to fill it.

## Independent verification

For `medium`, `high`, and `xhigh`, launch one fresh skeptic verifier per shortlisted candidate, in
parallel waves when necessary. Give the verifier the candidate, staged-diff scope, and repository
location, but not a preferred verdict or finder identity. Use a fresh context without inherited
reviewer conclusions. The verifier must inspect the actual diff and surrounding code and return
exactly one verdict with a short reason:

- `CONFIRMED` — the stated mechanism and scenario are supported by the code.
- `PLAUSIBLE` — material risk remains, but repository evidence cannot completely prove the runtime
  or product assumption.
- `REFUTED` — the mechanism is impossible, pre-existing and unaffected, explicitly handled, or only
  a preference.

Drop `REFUTED` candidates. Set `validation` to `confirmed` or `plausible` for the others. Rank
confirmed before plausible, then by severity and concreteness. Apply the selected level's final
finding cap only after verification. Never invent extra findings to fill the cap.
