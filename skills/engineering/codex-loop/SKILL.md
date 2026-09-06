---
name: codex-loop
description: Use when explicitly invoked via /codex-loop or $codex-loop to review staged changes with Codex, fix valid findings, and run bounded verification.
disable-model-invocation: true
argument-hint: '[low|medium|high|xhigh] [--model astra|sol] [--rounds N] [review focus]'
---

Run one independent staged review, triage and fix its findings, then verify only those fixes
and rebuttals. Keep this session lean: pass artifact paths to fresh reviewers and fixers;
read headlines and dispositions here, not full findings, diffs, or child transcripts.

## Arguments

Resolve arguments afresh on every invocation:

- Recognize `low`, `medium`, `high`, or `xhigh` only as the very first argument, before parsing
  flags; default `high`. This selects initial review depth and reasoning effort. Later level
  words are review focus.
- `--model astra|sol`: default `astra`. Map `astra` to `gpt-6-astra` and `sol` to `gpt-5.6-sol`.
  Also accept those exact model IDs. Pin the selected model and effort for every review round;
  reviewer children inherit them. This does not change the host session's model.
- `--rounds N`: positive integer; default `3`. This is an automatic budget, not a target.
- Remaining text: additional review focus supplied by the user.

Reject missing/invalid flag values, duplicate flags, and unsupported flags anywhere. Reject
`max` and `ultra` in the level slot: this skill defines only four review strategies. Reject
the removed `--here` flag; fix delegation is automatic when available. Never silently fall
back to another model if the selected one is unavailable.

Examples: `$codex-loop`, `$codex-loop --model sol`,
`$codex-loop xhigh --model astra --rounds 5 focus on authorization`.

## Preflight and invariants

1. Require `git`, `bash`, `jq`, and an authenticated `codex` CLI that supports the selected model.
   Record `codex --version`; if the service requires a newer client, stop and report the upgrade
   requirement. Follow repository data-handling rules; stop if they prohibit sending content to Codex.
2. Work from the repository root. Inspect `git status --porcelain`, `git diff --cached --stat`,
   `git diff --stat`, and `git ls-files --others --exclude-standard`.
3. Require staged changes and no pre-existing unstaged or untracked files. Otherwise show the
   blocking paths and ask the user to prepare the staged-only input. Do not stage, stash, delete,
   or repair their files. Stop on Git errors rather than treating them as an empty diff.
4. Resolve `SKILL_DIR` to the absolute directory containing this loaded `SKILL.md`; never assume
   an installation location. Verify its referenced files exist.

**Never stage, commit, or touch the index.** Reviewers are read-only; fixes land only in the
working tree. Do not run concurrent fixers or change branches during a run.

Create artifacts outside the repository and persist the resolved settings:

```bash
RUN="$(mktemp -d "${TMPDIR:-/tmp}/codex-loop.XXXXXX")"
REPO="$(git rev-parse --show-toplevel)"
MODEL=gpt-6-astra # Use gpt-5.6-sol when selected.
LEVEL=high       # Use the selected review level.
AUTOMATIC_BUDGET=3 # Use the validated --rounds value when supplied.
printf '%s\n' "$REPO" > "$RUN/repo"
printf '%s\n' "$MODEL" > "$RUN/model"
printf '%s\n' "$LEVEL" > "$RUN/review-level"
bash "$SKILL_DIR/scripts/baseline.sh" init "$RUN"
printf '{}\n' > "$RUN/ledger.json"
bash "$SKILL_DIR/scripts/round-budget.sh" init "$RUN" "$AUTOMATIC_BUDGET"
```

Use literal file writes for user focus and briefs; do not interpolate user text into shell code.
Report the run directory, selected model, level, and budget.

**Baseline check:** after each reviewer attempt (including failures), after the fixer, and before
returning to the user, run:

```bash
bash "$SKILL_DIR/scripts/baseline.sh" check "$RUN"
```

The helper compares HEAD and compact staged-diff metadata, ignoring index cache metadata and unstaged fixes.
Skip a duplicate check if no work or waiting occurred since the last successful check. On failure,
stop with its diagnostics; never repair or recreate the baseline. Do not load the helper source
into context unless diagnosing a failure.

## Each round

### 1. Review

Read [references/execution.md](references/execution.md) once for prompt assembly, background
execution, output validation, and retry rules. Reuse that procedure every round.

- Round 1: send the common review prompt and initial-review protocol directly to Codex.
- Later rounds: send the common prompt and verification protocol, plus paths to the previous
  findings and dispositions. Do not append the initial fan-out protocol or the full ledger.
- Start a fresh `codex exec` per round; do not resume a growing review transcript.

After successful output validation and the baseline check, read only the headline:

```bash
jq -r '.verdict, .summary, (.findings[] | "\(.id) [\(.severity)/\(.category)/\(.validation)] \(.file):\(.line) — \(.title)\(if .repeat_of != "" then " (repeat of \(.repeat_of))" else "" end)")' "$RUN/round-$N.json"
```

A clean verification closes the pending fixes from the previous round; it does not erase older
follow-ups or user deferrals. On any successful verification, close prior accepted/modified
findings that were not re-reported; link repeats to their prior ledger entries and resolve each
repeat chain using its latest disposition instead of leaving superseded entries pending. Record
this before handling new findings or stopping. A clean initial review needs no fixer.

### 2. Triage and fix

For nonempty findings, delegate to one fresh coding subagent without inherited conversation
history when supported. Its first instruction must be:

> Never `git add`, never `git commit`, never touch the index — fixes land in the working tree only.

Give it the repository path, round number, `$RUN/round-$N.json`, `$RUN/ledger.json`, the output
path `$RUN/dispositions-$N.json`, and [references/fixer.md](references/fixer.md). Include only
user-supplied intent and established constraints needed to judge the findings. The fixer reads
the full findings itself and returns a short disposition/test summary. It must read repository
instructions for affected files. If delegation is unavailable, read that reference and perform
the same work here; do not ask the user to choose the mechanism.

Check the baseline when it returns. Require exactly one disposition per reported finding, or
an explicit unresolved question for that ID, with no missing, duplicate, or invented IDs. Merge
findings and dispositions into `ledger.json` under `R<N>-F<n>` keys before honoring questions or
another stop condition. Preserve prior entries and `repeat_of` links; track applied fixes as
verification-pending until a later review closes them. Do not copy full finding bodies into
this session to maintain the ledger.

### 3. Continue or stop

- **Clean:** no findings in a valid review result. Stop after recording closures.
- **Resolved:** every finding has a disposition and no applied fix needs verification. Rejected
  and outside-review findings are closed; separate follow-ups and user deferrals stay open.
- **Question:** a fix needs user intent or the fixer returned questions. Preserve completed work
  and ask before another review.
- **Stalemate:** a repeated finding challenges a rejection with no new evidence, and the fixer
  still rejects it. Present both positions; do not argue it a third time.
- **Thrash:** the same invariant has been patched in three consecutive rounds and each patch
  caused the next finding. Stop further patching and surface the design decision.

Otherwise, when an accepted/modified fix was applied, advance exactly once and run targeted
verification regardless of severity:

```bash
bash "$SKILL_DIR/scripts/round-budget.sh" advance "$RUN"
```

A round with only rejected/outside-review findings can resolve without another call; do not
claim those decisions were independently verified. If review execution fails, stop with any
applied fixes still verification-pending.

## Budget gate

When the execution guard blocks a needed round, show the fixes awaiting verification and ask
for one additional round using the saved model and effort. Explain that this skill requires
explicit approval beyond the automatic budget. Use an observed verification duration if
available; do not invent an estimate. Only after approval:

```bash
bash "$SKILL_DIR/scripts/round-budget.sh" extend "$RUN" 1
```

Extend by exactly the approved count if the user explicitly grants more. Never reset/recreate
state or infer an extension from the desire to finish. Declining leaves verification pending.

## Final report

Report the model, requested level and any degraded coverage, completed rounds, and stop reason.
Give a compact table of findings, validation, disposition, and one-line reasons across rounds.
List still-open work only for separate follow-ups, explicit user deferrals, unresolved questions
or disagreements, and pending verification; give each an exact next action. Otherwise say
`No open review work.` Include tests/check limitations and the run directory.

State whether the baseline checks passed and that fixes remain unstaged. Never claim the index
was preserved or the review was clean after a failed check, invalid result, or incomplete run.
