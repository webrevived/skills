# Review execution

Use these commands from the saved repository root. Read the saved settings and guard immediately
before every invocation, including retries. A nonzero guard means go to the skill's Budget gate;
never launch anyway.

```bash
REPO="$(cat "$RUN/repo")"
MODEL="$(cat "$RUN/model")"
LEVEL="$(cat "$RUN/review-level")"
case "$LEVEL" in
  low|medium|high|xhigh) EFFORT="$LEVEL" ;;
  *) printf 'Invalid saved review level: %s\n' "$LEVEL" >&2; exit 1 ;;
esac
N="$(bash "$SKILL_DIR/scripts/round-budget.sh" current "$RUN")"
bash "$SKILL_DIR/scripts/round-budget.sh" guard "$RUN"
```

## Prompt

Copy these files into the prompt without loading their bodies into the orchestrator's context.
Round 1 also saves the staged diff so every finder reads the same bytes without re-running Git:

```bash
cp "$SKILL_DIR/references/review-prompt.md" "$RUN/prompt-$N.md"
printf '\n## Review level\n\n%s\n' "$LEVEL" >> "$RUN/prompt-$N.md"
if [[ "$N" == "1" ]]; then
  git -C "$REPO" diff --cached --no-color --no-ext-diff > "$RUN/staged.diff"
  cat "$SKILL_DIR/references/initial-review-protocol.md" >> "$RUN/prompt-$N.md"
  printf '\n## Diff file\n\n%s\n' "$RUN/staged.diff" >> "$RUN/prompt-$N.md"
else
  cat "$SKILL_DIR/references/verification-prompt.md" >> "$RUN/prompt-$N.md"
  printf '\n## Prior round artifacts\n\nRead findings: %s\nRead dispositions: %s\n' \
    "$RUN/round-$((N - 1)).json" "$RUN/dispositions-$((N - 1)).json" >> "$RUN/prompt-$N.md"
fi
```

Append only user-supplied review focus under `## Additional focus`. Do not add an author's
summary or rationale; the root reviewer writes its own neutral description from the diff.

## Launch and wait

Launch with the host's background/asynchronous shell facility **on the first attempt**, or a
resumable exec/PTY that yields without killing the process. Retain its handle and launch time.
Announce the model, level/effort, and round. Do not use a foreground call whose timeout kills the job.

```bash
codex exec -C "$REPO" \
  -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" \
  -c "agents.default_subagent_reasoning_effort=\"$EFFORT\"" \
  -c agents.max_concurrent_threads_per_session=12 \
  -c memories.use_memories=false \
  -s read-only \
  --output-schema "$SKILL_DIR/references/findings.schema.json" \
  -o "$RUN/round-$N.json" \
  - < "$RUN/prompt-$N.md" > "$RUN/round-$N.log" 2>&1
```

Use the selected effort for both the root reviewer and every finder, verifier, and sweep child.
Set both flags explicitly rather than relying on inheritance. This applies to targeted rounds
as well as the initial review. Full-diff reads, surrounding-code checks, and a separate evidence
verdict for every candidate remain required at `medium` and above; a lower effort is not permission
to skim or silently omit verification. Do not automatically escalate effort on a retry.

The `agents.max_concurrent_threads_per_session` override is required. Codex defaults to only a
few concurrent child threads per session (3 under multi-agent v2, 6 under v1), which is below the
finder wave the protocols launch. Without it the reviewer's spawns fail with
`agent thread limit reached`, and the reviewer wrongly falls back to the degraded single-pass
result. The value counts child threads only; closing a child frees its slot, so 12 covers the
largest finder wave. Collect and close each phase before launching the next. Do not pass
`agents.max_threads`: it is a legacy alias of the same key, not a separate lifetime cap. The initial
protocol separately bounds total children; increasing concurrency must not expand that budget.

`memories.use_memories=false` is required. Codex memories are cross-project notes from the user's
other sessions; a reviewer that reads them inherits prior conclusions and other repositories'
context into an independent review. Do not use `features.memories=false`: on current clients it
leaves the memory instructions in place and the reviewer greps the memory index anyway.

Poll the same job non-destructively. A wait timeout means wait again, never start another job.
Keep the user informed during long runs without dumping logs. Bound each attempt by elapsed time
since launch: low 20, medium 45, high 60, xhigh 90 minutes. At that deadline, save the retained
job's status and log tail, interrupt that job gracefully, then terminate only it if necessary.
Do not retry until its exit is confirmed; never use broad process-name matching.

## Validate and retry

After every attempt exits, perform the baseline check from `SKILL.md` even on failure. Stop
immediately on baseline drift. Accept output only after exit zero, valid schema-shaped JSON,
and these semantic checks:

- `incomplete` iff `unchecked_candidates` is nonempty. Otherwise `clean` iff findings are empty,
  and `findings` iff nonempty. Unchecked candidate IDs must be unique `C1`, `C2`, etc., with valid
  locations and reasons. A legitimate incomplete result is not a process failure or retry trigger.
- IDs are unique `F1`, `F2`, etc.; lines are positive integers.
- Round 1: findings have empty `repeat_of`; enforce the initial protocol's level-specific
  finding caps and validation rules.
- Round 1 at `medium`, `high`, or `xhigh`: verify delegation and depth with the helper, never with
  the log. The exec log and its `--json` stream print only the root agent's commands, messages,
  and stderr errors; they never show `spawn_agent`, `wait_agent`, or child activity, so an
  absence of finder or verifier traces in the log is not evidence of anything. Run:

  ```bash
  bash "$SKILL_DIR/scripts/delegation-check.sh" "$RUN" "$N"
  ```

  It counts all descendant threads Codex recorded for the attempt's session and, per descendant,
  its tool calls, wall-clock seconds, read hints, and recorded efforts. Compare the role names in
  its output with the coverage counts in the result summary, using the initial protocol's limits:

  - Exactly 4 finders for `medium`, 8 for `high`, or 10 plus `gap_sweep` for `xhigh`. No sweep
    at lower levels. Require these roles individually; extra verifiers cannot replace finders.
  - Add the reported batch and dedicated verifier counts, not one child per candidate. Each
    batch covers 1–6 candidates, each dedicated verifier covers one, and at most two dedicated
    verifiers may run across the initial pass and sweep combined. Cross-check initial and sweep
    candidate counts against those capacities; require zero verifiers when no candidates exist.
    Check the per-role batch caps and total child ceilings in the initial protocol. For example,
    `high` with 24 assigned candidates and no dedicated verifiers needs 8 finders and 4 batch
    verifiers, for 12 children. A clean no-candidate `high` review needs only the 8 finders.
  - All children must be direct children (`children == depth1`); nested delegation bypasses the
    budget. A verifier count or aggregate child count alone does not prove every candidate got
    a verdict. If coverage counts are missing or inconsistent, inspect the relevant child
    rollouts for assignments and verdicts before accepting the result.
  - Every completed reviewer must read the full diff, but `diff=yes/no` is only a command-text
    heuristic. It can miss valid reads such as `git -C ... diff --cached`, and a command mentioning
    `staged.diff` may only count lines. Before accepting coverage, inspect each child's read commands
    and completion/truncation markers at the helper's `rollout` path. Read only those records,
    without loading diffs or whole transcripts. Resolve ambiguous reads from the actual outputs;
    do not accept, reject, or retry solely on the flag. A failed verifier's assigned
    candidates must be reported as unchecked rather than silently treated as reviewed.
  - The effort recorded across all turns of every child must match the saved `$EFFORT`
    (`medium`, `high`, or `xhigh`). A mismatch means the selected effort was not preserved;
    stop and report the observed efforts.

  Require `verdict: incomplete` when candidates remain unchecked because a cap was reached or a
  batch could not finish. Preserve the candidate list before triaging any verified findings. Do
  not retry solely to work around a cap or to hide an incomplete batch.

  Exit 2 means the sessions directory is unavailable: do not reject on delegation grounds, and
  state in the final report that delegation and depth were unverified.
  A count outside the protocol's requirements invalidates the result, unless the
  summary declares the downgrade and the log shows delegation is genuinely unavailable (the spawn
  tool missing or every spawn failing). A single `collab spawn failed` error line while the child
  count is satisfied is transient child-side noise, not a delegation failure.
- `grep -c 'agent thread limit reached' "$RUN/round-$N.log"` must be zero. A hit means the
  reviewer exceeded the configured concurrency: the result is invalid even if it validates,
  because its coverage is not what the level promised.
- Later rounds: nonempty `repeat_of` references identify an actual prior finding, and validation
  is `confirmed` or `plausible` regardless of level. Initial finding caps do not apply. Require
  `unchecked_candidates: []`; the saved initial list remains open regardless of this round's verdict.

The CLI schema constrains structure; still reject truncated, contradictory, or malformed output.
A failed review is never a clean result. For a definite process failure or invalid output,
inspect diagnostics. Stop on authentication, client-upgrade requirements, unavailable model, or
permission blockers; do not substitute models or weaken the sandbox. Otherwise retry **once within
the same round**, archiving the first attempt's log and any result to `round-$N-attempt-1.*`
before launch so stale output cannot pass as the retry's result. Use a fresh watchdog and retain
the new handle. Stop if it fails.
