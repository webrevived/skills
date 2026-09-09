# Review execution

Use these commands from the saved repository root. Read the saved settings and guard immediately
before every invocation, including retries. A nonzero guard means go to the skill's Budget gate;
never launch anyway.

```bash
REPO="$(cat "$RUN/repo")"
MODEL="$(cat "$RUN/model")"
LEVEL="$(cat "$RUN/review-level")"
N="$(bash "$SKILL_DIR/scripts/round-budget.sh" current "$RUN")"
bash "$SKILL_DIR/scripts/round-budget.sh" guard "$RUN"
```

## Prompt

Copy these files into the prompt without loading their bodies into the orchestrator's context:

```bash
cp "$SKILL_DIR/references/review-prompt.md" "$RUN/prompt-$N.md"
printf '\n## Review level\n\n%s\n' "$LEVEL" >> "$RUN/prompt-$N.md"
if [[ "$N" == "1" ]]; then
  cat "$SKILL_DIR/references/initial-review-protocol.md" >> "$RUN/prompt-$N.md"
else
  cat "$SKILL_DIR/references/verification-prompt.md" >> "$RUN/prompt-$N.md"
  printf '\n## Prior round artifacts\n\nRead findings: %s\nRead dispositions: %s\n' \
    "$RUN/round-$((N - 1)).json" "$RUN/dispositions-$((N - 1)).json" >> "$RUN/prompt-$N.md"
fi
```

Append only user-supplied review focus under `## Additional focus`. Do not add an author's
summary or rationale. Reviewers read diffs from the repository; do not paste them into prompts.

## Launch and wait

Launch with the host's background/asynchronous shell facility **on the first attempt**, or a
resumable exec/PTY that yields without killing the process. Retain its handle and launch time.
Announce the model, level, and round. Do not use a foreground call whose timeout kills the job.

```bash
codex exec -C "$REPO" \
  -m "$MODEL" -c "model_reasoning_effort=\"$LEVEL\"" \
  -c agents.max_concurrent_threads_per_session=12 \
  -c features.memories=false \
  -s read-only \
  --output-schema "$SKILL_DIR/references/findings.schema.json" \
  -o "$RUN/round-$N.json" \
  - < "$RUN/prompt-$N.md" > "$RUN/round-$N.log" 2>&1
```

The `agents.max_concurrent_threads_per_session` override is required. Codex defaults to only a
few concurrent child threads per session (3 under multi-agent v2, 6 under v1), which is below the
finder wave the `high` and `xhigh` protocols launch. Without it the reviewer's spawns fail with
`agent thread limit reached`, and the reviewer wrongly falls back to the degraded single-pass
result. The value counts child threads only; closing a child frees its slot, so 12 covers the
largest finder wave and verifiers run in waves of 12. Do not pass `agents.max_threads`: it is a
legacy alias of the same key, not a separate lifetime cap.

The `features.memories=false` override is required. Codex memories are cross-project notes from
the user's other sessions; a reviewer that reads them inherits prior conclusions and other
repositories' context into an independent review, and the memory index alone costs tens of
thousands of tokens per attempt. The review must rest on the staged diff and the repository.

Poll the same job non-destructively. A wait timeout means wait again, never start another job.
Keep the user informed during long runs without dumping logs. Bound each attempt by elapsed time
since launch: low 20, medium 30, high 45, xhigh 60 minutes. At that deadline, save the retained
job's status and log tail, interrupt that job gracefully, then terminate only it if necessary.
Do not retry until its exit is confirmed; never use broad process-name matching.

## Validate and retry

After every attempt exits, perform the baseline check from `SKILL.md` even on failure. Stop
immediately on baseline drift. Accept output only after exit zero, valid schema-shaped JSON,
and these semantic checks:

- `clean` iff findings are empty; `findings` iff nonempty.
- IDs are unique `F1`, `F2`, etc.; lines are positive integers.
- Round 1: findings have empty `repeat_of`; enforce the initial protocol's level-specific
  finding caps and validation rules.
- Round 1 at `medium`, `high`, or `xhigh`: verify delegation with the helper, never with the log.
  The exec log and its `--json` stream print only the root agent's commands, messages, and stderr
  errors; they never show `spawn_agent`, `wait_agent`, or child activity, so an absence of finder
  or verifier traces in the log is not evidence of anything. Run:

  ```bash
  bash "$SKILL_DIR/scripts/delegation-check.sh" "$RUN" "$N"
  ```

  It counts the child threads Codex recorded for the attempt's session. Require `depth1` of at
  least 4 for `medium`, 8 for `high`, or 11 for `xhigh` (ten finders plus the gap sweep), plus
  one per reported finding for its verifier. Finders that return no candidates need no
  verifiers, so a `clean` result with exactly the finder count is valid. Exit 2 means the sessions directory is unavailable: do not
  reject on delegation grounds, and state in the final report that delegation was unverified.
  A count below the requirement is an undeclared downgrade and invalidates the result, unless the
  summary declares the downgrade and the log shows delegation is genuinely unavailable (the spawn
  tool missing or every spawn failing). A single `collab spawn failed` error line while the child
  count is satisfied is transient child-side noise, not a delegation failure.
- `grep -c 'agent thread limit reached' "$RUN/round-$N.log"` must be zero. A hit means the
  reviewer exceeded the configured concurrency: the result is invalid even if it validates,
  because its coverage is not what the level promised.
- Later rounds: nonempty `repeat_of` references identify an actual prior finding, and validation
  is `confirmed` or `plausible` regardless of level. Initial finding caps do not apply.

The CLI schema constrains structure; still reject truncated, contradictory, or malformed output.
A failed review is never a clean result. For a definite process failure or invalid output,
inspect diagnostics. Stop on authentication, client-upgrade requirements, unavailable model, or
permission blockers; do not substitute models or weaken the sandbox. Otherwise retry **once within the same round**, archiving
the first attempt's log and any result to `round-$N-attempt-1.*` before launch so stale output
cannot pass as the retry's result. Use a fresh watchdog and retain the new handle. Stop if it fails.
