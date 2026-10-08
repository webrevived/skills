---
name: build-plan
description: Claude Code only. Build every remaining phase of a write-plan plan unattended — one fresh subagent per phase builds, browser-verifies, and runs codex-loop --auto; this session verifies and commits each phase. Use only when the user invokes /build-plan.
disable-model-invocation: true
argument-hint: <plan-path>
---

You are the orchestrator. Stay thin: subagents read code, diffs, and logs; you check artifacts,
run gates, and commit. Invoking this skill authorizes one commit per phase on the current branch.
Never push.

**Escalate only for:** access or human-only actions (credentials, infra applies, accounts);
product or direction decisions beyond the plan; destructive operations on shared environments;
a codex-loop `escalate` outcome. Everything else gets decided, logged in the tracker, and the run
continues. To escalate: send a push notification with the question, report it here, and stop.

## Preflight

1. Read the plan. Refuse on the default branch or with merge conflicts. Require a clean tree,
   unless exactly one phase is `in progress` — then that phase resumes (see the brief).
2. Collect every open "Needs from user" item for the remaining phases (a plan without that
   section: derive them from its keys, accounts, external services, and live checks). Resolve
   what you can yourself; ask for the rest in one message and wait. Items that stay open block
   only the phases that need them.
3. Add `Base commit: <HEAD sha>` under the tracker if it isn't there.
4. Tell the user: the run is unattended, permission prompts in a background agent stall it, and
   the browser pane (when the run uses it) is in use until the run ends.

## Each remaining phase, in order

Spawn one background `general-purpose` subagent with this brief and no `model` override — every
agent in the run uses this session's model. Then end your turn; its completion notification
resumes you. Never run two phases at once.

```
Read <plan-path> and build phase <N>. You are unattended: never end your turn to wait for a
background job — block-poll it; ending your turn returns control to the orchestrator. Never
pass a `model` override to any subagent you spawn.
<If resuming: Partial work for this phase is already in the working tree; continue from it.>
1. Set phase <N> to `in progress` in the tracker. Verify the plan against the repo and prior
   deviations before building.
2. Build it, leaving types, lint, and tests green for what you touched.
3. Run the phase's Verify section (older plans: the live checks under its exit criteria). UI
   flows: use the project's browser-verification method when AGENTS.md or a project skill
   defines one; otherwise the built-in browser (mcp__Claude_Browser__*) — check preview_list
   first. With neither available, report those steps as not run; never claim them. Never kill a
   server you didn't start; when one won't pick up your changes, start your own instance on a
   free port. Fix what fails.
4. Invoke the codex-loop skill with `--auto`. If its fixes changed behavior, re-run the
   affected Verify steps.
5. Log deviations and judgment calls in the tracker, one line each. Do not mark the phase done
   and do not commit. If the phase says to delete the plan, leave it — the orchestrator does that
   last.
Human gates in the plan (migrations etc.): build and apply locally only, and list each in the
report with what to review — they don't stop the run.
Escalate — stop and report instead of guessing — only for: <the four classes above>.
Final message, at most 15 lines: STATUS ready|blocked|escalate; codex-loop run dir and outcome;
checks run; Verify scenarios with pass/fail/not run; files added; deviations; the question, if any.
```

## Accept — never trust the report

1. `STATUS escalate`: decide whether it truly is one of the four classes. If not, answer it via
   SendMessage to the same agent and wait again; if so, escalate.
2. `<run dir>/outcome.json` must say `"outcome": "clean"`.
3. `git ls-files --others --exclude-standard` must match the files the report says were added,
   with nothing secret-like (`.env*`, keys, credentials) or build output.
4. Run the phase's exit-criteria commands yourself with output redirected to a file (in the
   background if they can outlast the tool timeout); read only the tail on failure.

On any failure, send it to the same agent via SendMessage once and recheck. A second failure
marks the phase `blocked` — escalate.

Then set the phase `done` and update the current/next lines in the tracker, `git add -A`, and
commit `<type>(<scope>): <plan name> phase <N>` with the type the change warrants. Confirm the
commit exists and the tree is clean before moving on.

## Finish

After the last phase, spawn one more subagent: run codex-loop `high --auto --base <Base commit>`
with focus "cross-phase integration and contracts", then every phase's Verify flows end to end.
Accept and commit its fixes the same way (`fix(<scope>): <plan name> final review`). If a phase
said to delete the plan, delete it in that commit. Send a push notification, then report:
commits, every human gate with what to review before pushing, every Verify step not run, the
deviations and judgment calls from the tracker, follow-ups from each `outcome.json`, and anything
still open.
