---
name: agy-loop
description: Review code changes with the agy CLI (Gemini 4 Neon), fix valid findings, and re-review the fixes until clean. Use only when the user explicitly asks for agy-loop — never on your own initiative.
argument-hint: '[review focus, base ref, or model]'
disable-model-invocation: true
---

Use the `agy` CLI as an independent reviewer. You fix; agy reviews. Loop until agy
reports nothing new.

## Run agy

From the repo root, write the prompt to a temp file and run:

```bash
agy -p "$(cat "$PROMPT_FILE")" --model gemini-4-neon-high --output-format json
```

- Read `response` and `conversation_id` from the JSON.
- Don't pass `--mode`. `plan` and `accept-edits` silently deny shell commands in headless
  mode, so agy can't run `git diff`. The default mode works; the prompt keeps it read-only.
- A run takes minutes. Give it a long timeout or run it in the background and wait.
- Use a different model only if the user names one (`agy models` lists them).

## 1. Full review

Scope is the uncommitted changes (staged, unstaged, and untracked) unless the user names a
base ref or other scope. Don't paste the diff; agy runs git itself. Prompt agy to:

- Review the scope for bugs, security issues, performance problems, and unnecessary
  complexity, plus anything in the user's focus.
- Read surrounding code as needed to judge the changes.
- Not edit any files — this is a review only.
- Report each finding with `file:line`, severity, the problem, and a suggested fix, or say
  plainly that it found nothing.

## 2. Fix

Judge each finding yourself — agy can be wrong. Fix the valid ones. For each rejected
finding, note why. Issues that predate the change are out of scope: list them as
follow-ups instead of fixing them. Run the relevant tests or checks before re-reviewing.

## 3. Focused re-review

Run the same command plus `-r <conversation_id>` so agy keeps its earlier findings.
Tell it which findings you fixed and how, which you rejected and why, and ask it to
review only those fixes: confirm each is resolved, flag anything the fixes broke, and
push back on rejections it still disagrees with. Review only, no edits.

Repeat steps 2–3 until agy reports no new issues. Stop after 5 rounds and tell the user
what is still open.

## Report

Rounds run, each finding → fixed / rejected / follow-up (one-line reason), and anything
still open. Leave fixes uncommitted.
