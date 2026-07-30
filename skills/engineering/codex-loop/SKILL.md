---
name: codex-loop
description: Adversarial Codex review loop — a pinned Codex reviewer inspects the uncommitted diff, the invoking agent verifies and fixes, and the cycle repeats until clean or stalemate. Only run when explicitly invoked via /codex-loop or $codex-loop.
disable-model-invocation: true
argument-hint: '[--here] [--rounds N] [optional review focus]'
---

Codex (`gpt-5.6-sol`, `xhigh`) reviews the uncommitted changeset, you triage and fix, the
dispositions go back to Codex, repeat. This replaces the manual paste-between-tools loop — you
drive both sides.

**Arguments** (all optional; free text after the flags is the build summary, review focus, or both):

- `--here` — do the triage-and-fix in this session instead of delegating to a subagent
- `--rounds N` — round cap, default `3`
- `--no-notes` — send Codex nothing about the author's intent, for a fully cold read

## Ground rules

- **Never `git add`, never commit.** The user reviews via the stage-vs-working-tree diff. Fixes
  land in the working tree only.
- **Codex runs read-only** (`-s read-only`). It reviews; it does not edit.
- Pin every review to `gpt-5.6-sol` at `xhigh` reasoning effort. Do not substitute another model or
  inherit those two settings from local configuration.
- Follow the repository's data-handling rules. If they prohibit sending changed content to Codex,
  stop and tell the user.

## Preflight

```bash
git status --porcelain
command -v codex
```

If clean, stop — there is nothing to review. If `codex` is unavailable, stop and report the missing
prerequisite.

Resolve the absolute directory containing this loaded `SKILL.md` and store it in `SKILL_DIR`.
Hosts install skills in different locations, so never hard-code `.claude/skills`,
`.agents/skills`, or a user-level skill directory. Verify the references before starting:

```bash
test -f "$SKILL_DIR/references/review-prompt.md"
test -f "$SKILL_DIR/references/findings.schema.json"
```

Create the run directory outside the repository so artifacts cannot be committed and the workflow
does not require write access to `.git`:

```bash
BRANCH="$(git branch --show-current | tr '/:' '--')"
RUN="$(mktemp -d "${TMPDIR:-/tmp}/codex-loop-${BRANCH:-detached}-$(date +%Y%m%d-%H%M%S).XXXXXX")"
git diff --cached | git hash-object --stdin > "$RUN/staged.sha"
```

The `staged.sha` snapshot is the index guard — after every round you assert the staged diff is
byte-identical, because a subagent has mutated the index before despite instructions.

Report the run directory to the user so they can inspect artifacts afterwards.

## Round procedure

### 1. Compose the prompt

```bash
cp "$SKILL_DIR/references/review-prompt.md" "$RUN/prompt-$N.md"
```

Append any review focus the user passed as arguments under a `## Additional focus` heading.

Then append `## Author's notes` — the build summary for this changeset. When this skill runs in the
session that built the feature, write it from what you actually did. In a fresh session, the user
supplies it as the argument. Include:

- what the changeset is for, in a paragraph
- what is deliberately out of scope, deferred, or stubbed
- **deviations from the plan, and why** — these are where a reviewer should look hardest, so name
  them explicitly rather than burying them
- anything you could not verify, or verified empirically rather than against a spec

**Leave out the justifications** — "this is safe because…", "identity failures split cleanly",
"nothing can orphan here". Those anchor the reviewer into confirming your claims instead of testing
them, and that independent cold read is the whole reason Codex is in the loop. They are not wasted:
they belong in the round-2 rebuttal, where they answer a finding Codex reached on its own. The test
for each line is whether it states a _fact about scope_ or an _opinion about correctness_ — facts go
in, opinions wait.

`--no-notes` skips this section entirely.

For round 2 and later, append a `## Prior round` section built from the ledger — every finding from
the previous round, its disposition, and the one-line reason:

```markdown
## Prior round

You already reviewed this changeset. The diff you are about to read **already contains** the
accepted fixes. Here is what happened to each finding:

### R<N-1>-F1 — <title> (<file>:<line>) — ACCEPTED

<what was actually changed>

### R<N-1>-F2 — <title> (<file>:<line>) — REJECTED

<the rebuttal>

Now:

- For each **rejected** finding: if the rebuttal is wrong, re-report it with `repeat_of` set to the
  prior id and a direct counter-argument. If the rebuttal is right, drop it — do not re-report it.
- For each **accepted** or **modified** finding: re-report only if the fix is wrong or incomplete.
- For each **out-of-scope** finding: it is real but not this changeset's to fix. Do not re-report it.
- Report genuinely new findings as normal.
```

Also maintain `$RUN/do-not-report.txt` — one `path — reason` line per entry. Add a path when a
finding about it is disposed out-of-scope, or when a rejected finding survives its one
re-argument. From round 2 on, append the list to the prompt as a `## Do not report` section.
This is mechanical suppression, separate from the narrative rebuttals — Codex re-reports
rebutted paths often enough that prose alone doesn't stop it.

### 2. Run Codex

Reviews at `xhigh` effort run **~10–15 minutes per round** — a full loop is an hour-plus of wall
clock. **Set the Bash timeout to 600000**, and run it in the background when there is unrelated
work (docs, the next feature) to do in the meantime; the latency is mostly free if you use it.

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

### 3. Read only the headline into this session

Keep the full finding bodies out of your context — the fixer reads the file directly.

```bash
jq -r '.verdict, .summary, (.findings[] | "\(.id) [\(.severity)/\(.category)] \(.file):\(.line) — \(.title)\(if .repeat_of != "" then "  (repeat of \(.repeat_of))" else "" end)")' "$RUN/round-$N.json"
```

`verdict: "clean"` with no findings → the loop is done. Go to **Final report**.

### 4. Triage and fix

Every finding gets verified against the real code before anything is applied — Codex is wrong a
meaningful fraction of the time. Each one ends as **accepted** (applied as described), **modified**
(real problem, different fix), **rejected** (not a problem, or wrong), or **out-of-scope** (real,
but pre-existing or belongs to work in flight that isn't this changeset's to fix — recorded in the
ledger and surfaced in the final report, not fixed).

**Default — delegate to a subagent.** This is the point of the skill: the fix work burns context in
a process that then exits, so this session stays flat across rounds. Spawn a `general-purpose` agent
with:

- the path to `$RUN/round-$N.json` and `$RUN/ledger.json` (it reads them itself)
- **an intent brief you write** — the `## Author's notes` material **plus the justifications you
  withheld from Codex**, since the anchoring concern runs the other way here: the fixer is the
  author's side of the argument and needs to know why each decision was made. Design reasoning,
  rejected alternatives, constraints that don't show up in the diff. This is the one thing the
  subagent cannot recover on its own and it decides whether triage is good or bad — don't skip it,
  and don't pad it with what the code already says.
- instructions to: verify each finding against the actual code first; apply accepted and modified
  fixes; write `$RUN/dispositions-$N.json` as
  `{"round": N, "dispositions": [{"id","disposition","note"}], "also_fixed": [], "questions": []}`
  where `disposition` is `accepted`/`modified`/`rejected`/`out-of-scope` and `note` is one line;
  and return a short report, not a narration.

**The first line of the brief, verbatim: "Never `git add`, never `git commit`, never touch the
index — fixes land in the working tree only."** Not buried mid-brief as context; a subagent has
unstaged paths before when the rule lived in prose.

**With `--here` — do it in this session.** Same verification-first standard. Use this when the
findings turn on design intent that lives in this conversation, and accept that context grows.

Then merge the round's findings and dispositions into `$RUN/ledger.json`, keyed `R<N>-F<n>`, and
assert the index survived the round:

```bash
test "$(git diff --cached | git hash-object --stdin)" = "$(cat "$RUN/staged.sha")" || echo "INDEX MUTATED"
```

If it differs, stop the loop immediately and show the user `git status --porcelain` next to what
the snapshot expected — do not attempt to repair the index yourself.

### 5. Continue or stop

Automatic — **continue** to the next round when the round produced at least one accepted or
modified fix, no stop condition below has fired, and `N < rounds`.

**Stop and hand to the user** when any of these fire:

- **Clean** — `verdict: "clean"`. Done.
- **Taste** — every new finding is `architecture` or `style`. The disagreement is no longer about
  defects; it's the reviewer and fixer expressing different preferences, and that's the user's
  call.
- **Stalemate** — a finding is re-reported (`repeat_of` set) against a rejection you still believe
  is correct, and Codex's counter-argument raises nothing new. Present both positions and let the
  user settle it. Do not fold just because Codex repeated itself, and do not re-argue it a third
  time.
- **Rebuttal round exhausted** — a round where you rejected everything gets exactly one more round,
  so Codex sees the rebuttals. If that round produces no new substantive findings, stop.
- **Thrash** — the same file or invariant has been patched in three consecutive rounds, each fix
  spawning the next round's finding. Stop patching: the defect is in the design, at a level
  point-fixes can't reach. Name the pattern and put the underlying design question to the user.
- **Cap reached** — `N == rounds`. The cap is a budget, not a verdict: if this final round still
  produced a new accepted or modified `critical`/`major` `correctness` or `security` finding, the
  loop did **not** converge — say so plainly and recommend re-invoking with more rounds instead of
  reporting the cap as if it were clean.
- **Open question** — the subagent returned `questions`, or a fix needs a decision only the user can
  make. Ask before continuing; a wrong assumption compounds across rounds.

## Final report

Short. In this order:

1. Why the loop ended (clean / taste / stalemate / thrash / cap / question) and how many rounds
   ran — and, on a cap, whether the loop actually converged.
2. A table across all rounds: finding, category, disposition, one-line reason.
3. Anything still open — unresolved disagreements stated as both positions, out-of-scope findings
   that deserve their own follow-up, and any question.
4. The run directory path.

State plainly that nothing was staged and the fixes are sitting in the working tree.
