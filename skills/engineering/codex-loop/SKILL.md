---
name: codex-loop
description: Bounded Codex review loop — a pinned Codex reviewer checks staged changes, then performs focused verification of unstaged fixes with user-gated extensions. Only run when explicitly invoked via /codex-loop or $codex-loop.
disable-model-invocation: true
argument-hint: '[--here] [--rounds N] [optional review focus]'
---

Codex (`gpt-5.6-sol`, `xhigh`) reviews the staged changes, you triage and fix, the
dispositions go back to Codex for bounded verification. This replaces the manual
paste-between-tools loop without turning every round into another full review.

**Arguments** (all optional; free text after the flags is additional review context):

- `--here` — do the triage-and-fix in this session instead of delegating to a subagent
- `--rounds N` — automatic round budget, default `3`; this is not a target or an absolute ceiling

## Ground rules

- **Never `git add`, never commit.** The user reviews via the stage-vs-working-tree diff. Fixes
  land in the working tree only.
- **Codex runs read-only** (`-s read-only`). It reviews; it does not edit.
- Pin every review to `gpt-5.6-sol` at `xhigh` reasoning effort. Do not substitute another model or
  inherit those two settings from local configuration.
- Run at most three rounds automatically unless the user explicitly supplied `--rounds N`.
  Additional rounds remain available, but require explicit user approval before each extension.
- Follow the repository's data-handling rules. If they prohibit sending changed content to Codex,
  stop and tell the user.

## Preflight

```bash
git status --porcelain
command -v codex
git diff --cached --stat
git diff --stat
git ls-files --others --exclude-standard
```

Require a staged-only starting state:

- If `codex` is unavailable, stop and report the missing prerequisite.
- If `git diff --cached --quiet` succeeds, stop — there are no staged changes to review.
- If `git diff --quiet` fails, stop and show the pre-existing unstaged changes.
- If `git ls-files --others --exclude-standard` returns any paths, stop and show the pre-existing
  untracked files.

Do not stage, stash, delete, or otherwise resolve those files. Ask the user to prepare the intended
staged changes and invoke the skill again. This clean boundary means every later working-tree
change belongs to the fixer while the index remains the immutable review baseline.

Resolve the absolute directory containing this loaded `SKILL.md` and store it in `SKILL_DIR`.
Hosts install skills in different locations, so never hard-code `.claude/skills`,
`.agents/skills`, or a user-level skill directory. Verify the references before starting:

```bash
test -f "$SKILL_DIR/references/review-prompt.md"
test -f "$SKILL_DIR/references/findings.schema.json"
test -f "$SKILL_DIR/scripts/round-budget.sh"
```

Create the run directory outside the repository so artifacts cannot be committed and the workflow
does not require write access to `.git`:

```bash
BRANCH="$(git branch --show-current | tr '/:' '--')"
RUN="$(mktemp -d "${TMPDIR:-/tmp}/codex-loop-${BRANCH:-detached}-$(date +%Y%m%d-%H%M%S).XXXXXX")"
git diff --cached | git hash-object --stdin > "$RUN/staged.sha"
```

Initialize the automatic budget from `--rounds N`, or `3` when the flag was omitted. Reject
non-positive or non-integer values:

```bash
AUTOMATIC_BUDGET=3 # Replace 3 with the validated N when --rounds N was supplied.
bash "$SKILL_DIR/scripts/round-budget.sh" init "$RUN" "$AUTOMATIC_BUDGET"
```

The `staged.sha` snapshot is the index guard — after every round you assert the staged diff is
byte-identical, because a subagent has mutated the index before despite instructions.

Report the run directory to the user so they can inspect artifacts afterwards.

## Round procedure

### 1. Enforce the budget

Read the round number from state and run the guard immediately before every Codex invocation:

```bash
N="$(bash "$SKILL_DIR/scripts/round-budget.sh" current "$RUN")"
bash "$SKILL_DIR/scripts/round-budget.sh" guard "$RUN"
```

If the guard exits non-zero, do not launch Codex. Go to **Budget gate**. Never reset or recreate
the state files to bypass the guard.

### 2. Compose the prompt

```bash
cp "$SKILL_DIR/references/review-prompt.md" "$RUN/prompt-$N.md"
```

Append any review focus the user passed as arguments under a `## Additional focus` heading.
Do not generate an author's summary, rationale, or other context the user did not supply.

For round 1, append:

```markdown
## Review task: staged changes

Review the staged changes (`git diff --cached`). Look for logical bugs and other concrete issues
that should be fixed before commit. Assess the implementation's conventions and overall direction.
You may also call out architectural decisions you disagree with, but categorize those as
`architecture` rather than presenting preferences as defects.
```

For round 2 and later, append a `## Review task: fix verification` section followed by a
`## Prior round` section built from the previous round's ledger entries:

```markdown
## Review task: fix verification

Focus on the unstaged fixes (`git diff`) and any new untracked files. Use the staged changes only
as context. Check that the previous round's findings were addressed correctly.

Report only an incorrect or incomplete fix, an incorrect rebuttal, or a regression introduced by
the fixes. Do not conduct another general review of the staged changes.

## Prior round

The diff already contains the accepted fixes. Here is what happened to each finding:

### R<N-1>-F1 — <title> (<file>:<line>) — ACCEPTED

<what was actually changed>

### R<N-1>-F2 — <title> (<file>:<line>) — REJECTED

<the rebuttal>

Now:

- For each **rejected** finding: if the rebuttal is wrong, re-report it with `repeat_of` set to the
  prior id and a direct counter-argument. If the rebuttal is right, drop it — do not re-report it.
- For each **accepted** or **modified** finding: re-report only if the fix is wrong or incomplete.
- For each **out-of-scope** or **deferred** finding: do not re-report it.
- Report a new finding only when the prior round's fix introduced it.
```

### 3. Run Codex

Reviews at `xhigh` effort run **~10–15 minutes per round**. Set the Bash timeout to `600000` and
tell the user when a round starts. Do not silently start an unapproved extension.

```bash
codex exec \
  -m gpt-5.6-sol \
  -c 'model_reasoning_effort="xhigh"' \
  -s read-only \
  --output-schema "$SKILL_DIR/references/findings.schema.json" \
  -o "$RUN/round-$N.json" \
  - < "$RUN/prompt-$N.md" > "$RUN/round-$N.log" 2>&1
```

Non-zero exit or a missing/unparseable `round-$N.json`: check the tail of the log, retry once, then
stop and report.

### 4. Read only the headline into this session

Keep the full finding bodies out of your context — the fixer reads the file directly.

```bash
jq -r '.verdict, .summary, (.findings[] | "\(.id) [\(.severity)/\(.category)] \(.file):\(.line) — \(.title)\(if .repeat_of != "" then "  (repeat of \(.repeat_of))" else "" end)")' "$RUN/round-$N.json"
```

`verdict: "clean"` with no findings → the loop is done. Go to **Final report**.

### 5. Triage and fix

Every finding gets verified against the real code before anything is applied — Codex is wrong a
meaningful fraction of the time. Each one ends as **accepted** (applied as described), **modified**
(real problem, different fix), **rejected** (not a problem, or wrong), or **out-of-scope** (real,
but pre-existing or belongs to work in flight that isn't this changeset's to fix), or **deferred**
(real and in scope, but deliberately not fixed in this loop). Record out-of-scope and deferred
findings in the ledger and final report.

A **blocking finding** is `critical` or `major` and categorized as `correctness` or `security`.
Only an accepted or modified blocking finding can trigger another verification round after round 2.

**Default — delegate to a subagent.** This is the point of the skill: the fix work burns context in
a process that then exits, so this session stays flat across rounds. Spawn a `general-purpose` agent
with:

- the path to `$RUN/round-$N.json` and `$RUN/ledger.json` (it reads them itself)
- a short intent brief containing only the additional context the user supplied and any concrete
  constraints already established in the session that are necessary to triage the findings
- instructions to: verify each finding against the actual code first; apply accepted and modified
  fixes; never fix an issue Codex did not report; write `$RUN/dispositions-$N.json` as
  `{"round": N, "dispositions": [{"id","disposition","note"}], "follow_ups": [], "questions": []}`
  where `disposition` is `accepted`/`modified`/`rejected`/`out-of-scope`/`deferred` and `note` is
  one line; put other issues it notices in `follow_ups` without editing them; and return a short
  report, not a narration.

**The first line of the brief, verbatim: "Never `git add`, never `git commit`, never touch the
index — fixes land in the working tree only."** Not buried mid-brief as context; a subagent has
unstaged paths before when the rule lived in prose.

**With `--here` — do it in this session.** Same verification-first standard. Use this when the
findings turn on design intent that lives in this conversation, and accept that context grows.

If `questions` is non-empty, stop before another review. Ask the user and wait.

Then merge the round's findings and dispositions into `$RUN/ledger.json`, keyed `R<N>-F<n>`, and
assert the index survived the round:

```bash
test "$(git diff --cached | git hash-object --stdin)" = "$(cat "$RUN/staged.sha")" || echo "INDEX MUTATED"
```

If it differs, stop the loop immediately and show the user `git status --porcelain` next to what
the snapshot expected — do not attempt to repair the index yourself.

### 6. Continue or stop

After round 1, continue to one verification round when at least one accepted or modified fix was
applied.

After round 2 or later, continue only when the round produced at least one accepted or modified
**blocking finding**, its fix was applied, and no stop condition below fired. Minor findings and
findings categorized as performance, test-coverage, maintainability, docs, architecture, or style
never trigger another round; record them in the final report.

When continuing, advance state exactly once:

```bash
bash "$SKILL_DIR/scripts/round-budget.sh" advance "$RUN"
```

Return to **Enforce the budget**. A budget is permission to run up to that many rounds, not a target:
stop as soon as the continuation criteria fail.

**Stop and hand to the user** when any of these fire:

- **Clean** — `verdict: "clean"`. Done.
- **Non-blocking** — after a verification round, no accepted or modified blocking finding remains.
- **Taste** — every remaining finding is `architecture` or `style`. The disagreement is no longer
  about defects; it's the reviewer and fixer expressing different preferences, and that's the
  user's call.
- **Stalemate** — a finding is re-reported (`repeat_of` set) against a rejection you still believe
  is correct, and Codex's counter-argument raises nothing new. Present both positions and let the
  user settle it. Do not fold just because Codex repeated itself, and do not re-argue it a third
  time.
- **Thrash** — the same file or invariant has been patched in three consecutive rounds, each fix
  spawning the next round's finding. Stop patching: the defect is in the design, at a level
  point-fixes can't reach. Name the pattern and put the underlying design question to the user.
- **Open question** — the subagent returned `questions`, or a fix needs a decision only the user can
  make. Ask before continuing; a wrong assumption compounds across rounds.

## Budget gate

The automatic budget is not an absolute cap. When the guard blocks a justified next round:

1. Stop before launching Codex.
2. Show the accepted or modified blocking findings that require verification.
3. State that another `gpt-5.6-sol`/`xhigh` round is expected to take roughly 10–15 minutes.
4. Ask the user to approve one additional round.

Only after explicit approval, extend the budget and return to **Enforce the budget**:

```bash
bash "$SKILL_DIR/scripts/round-budget.sh" extend "$RUN" 1
```

If the user explicitly approves more than one additional round, extend by exactly that number.
Never infer approval from the desire to finish, never reset the state, and never restart full-review
mode. If the user declines, go to **Final report** with verification pending.

## Final report

Short. In this order:

1. Why the loop ended (clean / non-blocking / taste / stalemate / thrash / budget declined /
   question) and how many rounds ran.
2. A table across all rounds: finding, category, disposition, one-line reason.
3. Anything still open — unresolved disagreements stated as both positions, out-of-scope findings
   and deferred follow-ups, unverified fixes, and any question.
4. The run directory path.

State plainly that the loop did not alter the index and its fixes are sitting in the working tree.
