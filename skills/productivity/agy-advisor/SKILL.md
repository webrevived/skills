---
name: agy-advisor
description: Get an adversarial second opinion on a plan, design, or decision from the agy CLI (Gemini 4 Neon). Use only when the user explicitly asks for agy-advisor — never on your own initiative.
argument-hint: '[what to review, e.g. "the plan we discussed"]'
disable-model-invocation: true
---

Use the `agy` CLI as an adversarial advisor on whatever the user points at — usually a
plan from this conversation.

## 1. Brief agy

agy has none of this conversation. Write a self-contained brief to a temp file:

- The plan or decision in full, not a summary of it.
- The goal, constraints, and decisions the user has already made.
- Relevant files and paths in the repo.
- Anything the user asked agy to focus on.

Leave out your own doubts about the plan; let agy find problems independently.

Ask agy to attack it: find what's wrong, missing, risky, overcomplicated, or built on a
false assumption, and propose a better alternative where one exists. Tell it to rank its
concerns by impact and not to edit any files.

Also tell it to verify the plan's core claims and assumptions — about this codebase,
libraries, APIs, and platform behavior — against the actual code and docs, not the brief,
and to call out any that are false and what would break.

## 2. Run agy

From the repo root:

```bash
agy -p "$(cat "$BRIEF_FILE")" --model gemini-4-neon-high --output-format json
```

- Read `response` and `conversation_id` from the JSON.
- Don't pass `--mode`; `plan` and `accept-edits` block the shell commands agy needs to
  read the repo in headless mode.
- A run takes minutes. Give it a long timeout or run it in the background and wait.
- Use a different model only if the user names one.

## 3. Report

Weigh each point yourself — don't relay agy uncritically. Tell the user what you agree
with and would change in the plan, what you disagree with and why, and anything that
needs their decision. Don't change the plan until the user agrees.

For follow-up questions to agy, resume the same conversation with `-r <conversation_id>`.
