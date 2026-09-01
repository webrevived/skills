---
name: codex-loop
description: Bounded multi-agent Codex review-and-fix loop — specialized reviewers inspect staged changes, then focused verification closes the fixes or surfaces genuinely separate work. Only run when explicitly invoked via /codex-loop or $codex-loop.
disable-model-invocation: true
argument-hint: '[low|medium|high|xhigh] [--rounds N] [optional review focus]'
---

Codex (`gpt-5.6-sol`) reviews the staged changes through level-appropriate independent review
paths, you triage and fix, and the dispositions go back to Codex for bounded verification. The
default `high` review uses broad multi-agent discovery without turning every later round into
another full review.

**Arguments** (all optional; the level, when supplied, must be the first argument; remaining free
text is additional review context):

- `low`, `medium`, `high`, or `xhigh` — review depth and reasoning effort; default `high`
- `--rounds N` — automatic round budget, default `3`; this is not a target or an absolute ceiling

Recognize a review level only in that first positional slot. Words such as `low` or `high` later in
the review focus are ordinary context, not additional levels. Do not support `max` or remember the
level from an earlier run. Reject unsupported flags wherever they appear. In particular, reject the
removed `--here` flag and explain that fix delegation is now automatic when available.

## Ground rules

- **Never `git add`, never commit.** The user reviews via the stage-vs-working-tree diff. Fixes
  land in the working tree only.
- **Codex runs read-only** (`-s read-only`). It reviews; it does not edit.
- Pin every review to `gpt-5.6-sol` and the selected reasoning effort. Do not substitute another
  model or inherit either setting from local configuration.
- Use the selected level's multi-agent protocol only for the initial staged review. Later rounds
  are targeted fix verification regardless of level.
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
test -f "$SKILL_DIR/references/initial-review-protocol.md"
test -f "$SKILL_DIR/references/findings.schema.json"
test -f "$SKILL_DIR/scripts/round-budget.sh"
```

Create the run directory outside the repository so artifacts cannot be committed and the workflow
does not require write access to `.git`:

```bash
BRANCH="$(git branch --show-current | tr '/:' '--')"
RUN="$(mktemp -d "${TMPDIR:-/tmp}/codex-loop-${BRANCH:-detached}-$(date +%Y%m%d-%H%M%S).XXXXXX")"
git diff --cached | git hash-object --stdin > "$RUN/staged.sha"
printf '{}\n' > "$RUN/ledger.json"
```

Resolve the level exclusively from the first argument before parsing flags. Consume it only when it
is exactly `low`, `medium`, `high`, or `xhigh`; reject `max` in that slot. Otherwise default to
`high` and preserve a non-flag first argument as review focus. Reject `--here` and any other
unsupported flag wherever it appears. Record the result so every round uses the same model effort:

```bash
LEVEL=high # Replace with low, medium, high, or xhigh when explicitly supplied.
printf '%s\n' "$LEVEL" > "$RUN/review-level"
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
LEVEL="$(cat "$RUN/review-level")"
printf '\n## Review level\n\n%s\n\n' "$LEVEL" >> "$RUN/prompt-$N.md"

if [[ "$N" == "1" ]]; then
  cat "$SKILL_DIR/references/initial-review-protocol.md" >> "$RUN/prompt-$N.md"
fi
```

Append any review focus the user passed as arguments under a `## Additional focus` heading. Do not
generate an author's summary, rationale, or other context the user did not supply.

For round 1, append:

```markdown
## Review task: staged changes

Review the staged changes (`git diff --cached`). Look for logical bugs and other concrete issues
introduced or materially worsened by this changeset that should be fixed before committing this
phase. Assess the implementation's conventions and overall direction. Report an architectural
issue only when the current decision creates a material maintainability or scalability risk;
categorize it as `architecture` and explain the tradeoff rather than presenting taste as a defect.
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
- For each **outside-review**, **separate-follow-up**, or **user-deferred** finding: do not re-report
  it.
- Report a new finding only when the prior round's fix introduced it.
```

### 3. Run Codex

Initial `high` and `xhigh` reviews fan out across multiple agents and can run for many minutes.
Launch every Codex invocation with the host's background or asynchronous shell mode **on the first
attempt**, retain its job/session handle, and tell the user the level and round when it starts. If
the host instead provides a resumable exec or PTY session, use that and yield while it runs. Do not
run Codex in a foreground tool call with a fixed long timeout: exceeding a wait limit must never
kill a healthy review or force it to restart. Do not silently start an unapproved extension.

```bash
# Launch this command with the host's background/async option immediately.
LEVEL="$(cat "$RUN/review-level")"
codex exec \
  -m gpt-5.6-sol \
  -c "model_reasoning_effort=\"$LEVEL\"" \
  -s read-only \
  --output-schema "$SKILL_DIR/references/findings.schema.json" \
  -o "$RUN/round-$N.json" \
  - < "$RUN/prompt-$N.md" > "$RUN/round-$N.log" 2>&1
```

Wait for the retained job/session to complete using notifications or non-terminating polls. A poll
or wait timing out means wait again; it is not a failed review. Never launch another invocation
while the original job/session may still be running.

Bound each attempt by elapsed wall-clock time from launch: `20` minutes for `low`, `30` for
`medium`, `45` for `high`, and `60` for `xhigh`. Individual poll timeouts do not reset that
watchdog. If the process is still alive at the overall deadline, capture its session/job status and
the tail of `round-$N.log`, then cancel only that retained job/session: request a graceful interrupt
first and terminate it only if it does not exit. Never identify the target by a broad process-name
match. Wait until the cancelled process has definitely exited before treating the attempt as
failed.

After a definite non-zero exit, watchdog cancellation, or missing/unparseable `round-$N.json`,
check the captured diagnostics and retry once as a new background job with a fresh watchdog. Stop
and report if that retry fails.

### 4. Read only the headline into this session

Keep the full finding bodies out of your context — the fixer reads the file directly.

```bash
jq -r '.verdict, .summary, (.findings[] | "\(.id) [\(.severity)/\(.category)/\(.validation)] \(.file):\(.line) — \(.title)\(if .repeat_of != "" then "  (repeat of \(.repeat_of))" else "" end)")' "$RUN/round-$N.json"
```

Assert the index survived the read-only review before following any exit path:

```bash
test "$(git diff --cached | git hash-object --stdin)" = "$(cat "$RUN/staged.sha")" || echo "INDEX MUTATED"
```

If it differs, stop the loop immediately and show the user `git status --porcelain` next to what
the snapshot expected — do not attempt to repair the index yourself.

`verdict: "clean"` with no findings → the loop is done. Go to **Final report**.

### 5. Triage and fix

Every finding gets verified against the real code before anything is applied — Codex is wrong a
meaningful fraction of the time. Each one ends as **accepted** (applied as described), **modified**
(real problem, different fix), **rejected** (not a problem, or wrong), **outside-review**
(pre-existing and neither worsened nor relied upon by the changeset), **separate-follow-up** (real
work that is not required to complete this staged phase and either was explicitly excluded by the
user/plan or requires a materially separate feature, phase, or external dependency), or
**user-deferred** (a verified in-scope finding the user explicitly chose not to fix in this run).

Default every real in-scope finding to **accepted** or **modified**. Do not use
**separate-follow-up** merely because a fix is non-blocking, inconvenient, slightly beyond the
originally edited lines, or larger than expected. Its note must say why the work cannot responsibly
be completed in this loop and name the exact next action. The agent cannot choose
**user-deferred** on the user's behalf. If scope or product intent is unclear, add a question and
stop instead of manufacturing a deferral. Record every disposition in the ledger, but only
separate follow-ups and explicit user deferrals count as still open.

**Delegate to a subagent.** This is the point of the skill: the fix work burns context in a process
that then exits, so this session stays flat across rounds. Spawn one capable coding subagent with:

- the path to `$RUN/round-$N.json` and `$RUN/ledger.json` (it reads them itself)
- a short intent brief containing only the additional context the user supplied and any concrete
  constraints already established in the session that are necessary to triage the findings
- instructions to: verify each finding against the actual code first; apply accepted and modified
  fixes; never fix an issue Codex did not report; write `$RUN/dispositions-$N.json` as
  `{"round": N, "dispositions": [{"id","disposition","note"}], "questions": []}` where
  `disposition` is `accepted`/`modified`/`rejected`/`outside-review`/`separate-follow-up`/
  `user-deferred` and `note` is one line; do not record incidental follow-ups Codex did not report;
  and return a short report, not a narration.

**The first line of the brief, verbatim: "Never `git add`, never `git commit`, never touch the
index — fixes land in the working tree only."** Not buried mid-brief as context; a subagent has
unstaged paths before when the rule lived in prose.

If subagent delegation is unavailable, perform the same verification-first triage in this session.
Do not ask the user to choose between those execution details.

Immediately after the fixer returns, assert the index survived its work:

```bash
test "$(git diff --cached | git hash-object --stdin)" = "$(cat "$RUN/staged.sha")" || echo "INDEX MUTATED"
```

If it differs, stop the loop immediately and show the user `git status --porcelain` next to what
the snapshot expected — do not attempt to repair the index yourself.

If `questions` is non-empty, stop before another review. Ask the user and wait.

Then merge the round's findings and dispositions into `$RUN/ledger.json`, keyed `R<N>-F<n>`.

### 6. Continue or stop

After any round, continue to a targeted verification round when at least one accepted or modified
fix was applied and no stop condition below fired. Severity and category do not waive verification:
a real fix should be closed, not left open merely because it is non-blocking. Later rounds remain
limited to prior findings and fix-induced regressions, so this does not authorize another general
review of the staged changes.

When continuing, advance state exactly once:

```bash
bash "$SKILL_DIR/scripts/round-budget.sh" advance "$RUN"
```

Return to **Enforce the budget**. A budget is permission to run up to that many rounds, not a target:
stop as soon as the continuation criteria fail.

**Stop and hand to the user** when any of these fire:

- **Clean** — `verdict: "clean"`. Done.
- **Resolved** — no accepted or modified fix needs verification and every reported finding has a
  disposition. Rejected and outside-review findings are closed, not still open.
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
2. Show the accepted or modified findings that require verification.
3. State that another `gpt-5.6-sol` round will use the selected effort but remain targeted rather
   than repeating initial fan-out. Use the most recent verification-round duration as the estimate
   when available; otherwise do not invent one.
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

1. The selected level, why the loop ended (clean / resolved / stalemate / thrash / budget declined
   / question), and how many rounds ran.
2. A table across all rounds: finding, category, validation, disposition, one-line reason.
3. **Still open**, only when there is at least one separate follow-up, explicit user deferral,
   unresolved disagreement, unverified fix after a declined extension, or unanswered question. For
   each item, state why it could not be completed in this loop and the exact next action. Do not
   include rejected or outside-review findings. If nothing qualifies, say `No open review work.`
4. The run directory path.

State plainly that the loop did not alter the index and its fixes are sitting in the working tree.
