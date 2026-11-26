---
name: council
description: Convene a council of two adversarial reviewers — Codex (GPT-6 Astra, high) and agy (Gemini 4 Neon, xhigh) — on a plan, approach, or decision, then verify their points and report what to change. Use only when the user explicitly asks for council — never on your own initiative.
argument-hint: '[what to review, e.g. "the plan"]'
disable-model-invocation: true
---

Run two independent adversarial reviews in parallel — Codex and agy — on whatever the
user points at, then act as the judge: verify every point and tell the user what to
change. With no argument, review the plan or approach most recently discussed in this
conversation. If it's unclear what that is, ask.

## 1. Brief

Neither reviewer has this conversation. Make a temp dir `$OUT` and write one
self-contained brief to `$BRIEF_FILE` inside it. Both get the same brief, so their
agreement means something:

- The plan or decision in full, not a summary of it.
- The goal, constraints, and decisions the user has already made.
- Relevant files and paths in the repo.
- Anything the user asked the council to focus on.

Leave out your own doubts; let the reviewers find problems independently.

Ask each to attack it: find what's wrong, missing, risky, overcomplicated, or built on a
false assumption, and propose a better alternative where one exists. Tell it to check
claims against the codebase rather than trust the brief, to rank its concerns by impact,
and not to edit any files.

## 2. Run both at once

From the repo root, run both concurrently as one command:

```bash
codex exec -m gpt-6-astra -c model_reasoning_effort="high" -s read-only \
  -o "$OUT/codex.md" - < "$BRIEF_FILE" > "$OUT/codex.log" 2>&1 &
agy -p "$(cat "$BRIEF_FILE")" --model gemini-4-neon-xhigh --output-format json \
  > "$OUT/agy.json" 2> "$OUT/agy.log" &
wait
```

- Codex's review is `$OUT/codex.md`; agy's is `response` in `$OUT/agy.json`.
- Don't add flags. In particular, don't pass `--mode` to agy: `plan` and `accept-edits`
  block the shell commands it needs to read the repo headless.
- Each run takes minutes. Use a long timeout, or run the whole command in the background
  and wait for it; don't end your turn while it runs.
- If one fails, report that and continue with the other. Don't retry with extra flags.
- Use different models only if the user names them.

## 3. Judge

You're the judge, not a relay. For each point:

- Verify it against the code and the plan. Drop anything that's wrong, already handled,
  or contradicts a decision the user made.
- Note when both reviewers raised it independently — that's the strongest signal.
- Keep what changes the outcome; drop nitpicks.

## 4. Report

In plain language, short:

1. **Verdict** — one line: sound, sound with changes, or rethink.
2. **Change** — what to change in the plan, most important first, each with a one-line
   why and which reviewer(s) raised it.
3. **Rejected** — notable points you dismissed, one line each with the reason.
4. **Your call** — anything that needs the user's decision.

Don't change the plan until the user agrees. For follow-ups, resume agy with
`-r <conversation_id>` from `agy.json`, and Codex with
`codex exec resume <session id from codex.log> -m gpt-6-astra -c model_reasoning_effort="high" "<question>"`.
