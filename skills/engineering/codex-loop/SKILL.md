---
name: codex-loop
description: Review uncommitted changes (or a committed range) with Codex, fix valid findings, and verify the fixes in bounded rounds. Use only when the user explicitly asks for codex-loop, or when a plan or orchestrating skill (e.g. build-plan) instructs it — never on your own initiative.
argument-hint: '[medium|high] [--auto] [--base <ref>] [--model astra|sol] [--rounds N] [review focus]'
---

**Run this only when the user or an orchestrating skill/plan explicitly asks for it.**

Codex reviews an immutable snapshot of the changes, a fresh fixer applies fixes to the working
tree, and Codex verifies those fixes. Scripts own the mechanics; keep this session lean — read
headlines and dispositions, never full findings, diffs, logs, or child transcripts.

## Arguments

- First argument `medium` or `high`. When omitted, choose: **default `high`**; pick `medium` only
  for clearly low-risk changes — UI/styling-only, docs/tests-only, or a small internal refactor
  that touches no contract, auth, data, or concurrency. Ignore generated code and lockfiles when
  judging size. When in doubt, `high`. State the level and a one-line reason.
- `--auto`: unattended. The fixer decides judgment calls itself; only authority-boundary
  questions stop the run (see `references/fixer.md`).
- `--base <ref>`: review `<ref>` → working tree (e.g. a whole branch) instead of HEAD → working tree.
- `--model astra|sol`: default `astra` = `gpt-6-astra`; `sol` = `gpt-5.6-sol`. Never substitute.
- `--rounds N`: automatic round budget, default 3.
- Remaining text: review focus. Reject `low`, `xhigh`, and unknown or duplicate flags.

## Setup

Require `git`, `jq`, and an authenticated `codex` CLI. Resolve `SKILL_DIR` to the directory of
this file. After the block below, write any review focus to `$RUN/focus.md` with a file-write
tool, never by interpolating it into shell.

```bash
RUN="$(mktemp -d "${TMPDIR:-/tmp}/codex-loop.XXXXXX")"
git rev-parse --show-toplevel > "$RUN/repo"
printf '%s\n' "$MODEL" > "$RUN/model"
printf '%s\n' "$LEVEL" > "$RUN/review-level"
bash "$SKILL_DIR/scripts/round-budget.sh" init "$RUN" "$ROUNDS"
bash "$SKILL_DIR/scripts/snapshot.sh" init "$RUN" "$BASE"   # omit $BASE for HEAD; exit 4 = nothing to review
```

The snapshot is what `git add -A` would commit: staged or not, plus untracked non-ignored files.
Report the run directory, model, level, budget, and every path in `$RUN/untracked.txt` — they are
reviewed and will be committed with the change, so flag anything that looks like a secret or artifact.

## Each round

1. **Review.** Run `bash "$SKILL_DIR/scripts/review.sh" "$RUN"` in the foreground — it returns
   once a detached Codex runner is up (exit 3 = budget gate, 1 = nothing launched). Then block on
   `bash "$SKILL_DIR/scripts/wait.sh" "$RUN"` (exit 75 = call it again). **Never end your turn to
   wait** — in a subagent that hands control back to your parent. Never start a second review
   while one runs.
2. **Validate.** `bash "$SKILL_DIR/scripts/validate.sh" "$RUN"`. Exit 1: relaunch `review.sh` once
   (it archives the failed attempt), unless the log tail shows an auth, upgrade, model, or
   permission error — then stop `review-failed`. A second failure stops `review-failed`; exit 2
   stops `telemetry-unknown`. Then `bash "$SKILL_DIR/scripts/snapshot.sh" check "$RUN"`; failure
   stops `baseline-drift`.
3. **Read the headline only.**

   ```bash
   N="$(bash "$SKILL_DIR/scripts/round-budget.sh" current "$RUN")"
   jq -r '.verdict, .summary, (.findings[] | "\(.id) [\(.severity)/\(.category)/\(.validation)] \(.file):\(.line) — \(.title)\(if .repeat_of != "" then " (repeat of \(.repeat_of))" else "" end)")' "$RUN/round-$N.json"
   ```

   No findings: go to Finish.
4. **Fix.** Delegate to one fresh subagent without inherited history: repo path, round `N`,
   `$RUN/round-$N.json`, the run directory, output `$RUN/dispositions-$N.json`,
   `$SKILL_DIR/references/fixer.md`, "auto mode" when `--auto`, and only established user
   constraints. Without delegation, do it yourself per `fixer.md`. Require exactly one disposition
   or question per finding ID. Questions without `--auto`: ask the user, then send the answers to
   the same fixer to apply; each answered question moves from `questions` to `dispositions`
   (`user-deferred` when the user declines the fix). Then run `snapshot.sh check "$RUN"` and
   `snapshot.sh take "$RUN" "$N"`.
5. **Continue or stop.**
   - Questions remain (`--auto`): go to Finish — they escalate.
   - Stalemate or thrash (defined in `fixer.md`): Finish with `--stop stalemate|thrash`.
   - Any `accepted`/`modified` fix: `round-budget.sh advance "$RUN"` and review again — the next
     round verifies only those fixes and rebuttals.
   - Otherwise (only rejected, outside-review, or follow-up): Finish.

## Budget gate

Fixes await verification but `review.sh` exits 3. With `--auto`, extend once per run
(`[[ -e "$RUN/auto-extended" ]] || { bash "$SKILL_DIR/scripts/round-budget.sh" extend "$RUN" 1; touch "$RUN/auto-extended"; }`),
otherwise Finish with `--stop budget`. Interactively, ask the user for more rounds and extend only
by what they approve.

## Finish

Run `bash "$SKILL_DIR/scripts/outcome.sh" "$RUN" [--stop <reason>]`; it writes
`$RUN/outcome.json` with `outcome: clean | open | escalate`. Report: model, level and reason,
rounds, the outcome line, a compact table of every finding → disposition → one-line reason, each
open item from `outcome.json` with its exact next action, checks run and their limits, and the
run directory. Fixes stay uncommitted. Never call the review clean unless the outcome is `clean`.
