---
name: write-plan
description: Write a phased implementation plan (.md) for a large feature, where each phase is one AI coding-agent session.
disable-model-invocation: true
argument-hint: <feature or roadmap item to plan>
---

Write an implementation plan for the requested feature or roadmap item as a Markdown document.
The reader is **an AI coding agent in a fresh session** told "build phase N of this plan" — not
a human project manager. Every choice below follows from that.

## Before writing: align, then research

1. If the task has decisions that shape the whole approach — architecture, data model, library
   choice, scope boundaries — settle them with the user **before** drafting the plan. Ask one
   question at a time, leading with your recommended option. Skip this when the direction is
   already clear from the request, the docs, or prior decisions.
2. Research the entire change enough to establish every phase's boundaries, dependencies, and
   exit criteria. Research phase 1 deeply enough that you could implement it yourself. For later
   phases, specify exact contracts and files where they are already knowable; do not invent
   internals that depend on earlier implementation results. Delegate heavy or open-ended
   research when the host supports it.
3. Facts you can look up are never questions for the user; decisions are.

## Required skeleton

Only these four elements are mandatory. Adapt everything else — section names, extra sections,
depth, ordering — to what's being planned; a schema design plan and a migration plan should not
look alike.

1. **Title + goal** — one paragraph on what exists when the plan is done.
2. **Progress tracker**, directly under the goal: a phase/status table using only `not started`,
   `in progress`, `done`, or `blocked`, plus "current phase" and "recommended next phase" lines.
   End it with a literal instruction that the executing agent updates the tracker at the end of
   its run, noting any deviations in one line each.
3. **Decisions & context** — everything a fresh session needs that it can't get from the repo:
   load-bearing decisions made, rejected alternatives that would otherwise be relitigated,
   constraints, and pointers to the files and docs that matter. If rationale already has a
   durable home in architecture docs or an ADR, link it instead of duplicating it.
4. **Phases** — each with: goal, what to build (concrete — file paths, names, shapes), a coarse
   task checklist, and exit criteria another agent or the user can verify, including the exact
   commands to run. Every phase leaves the repo green (build, lint, test).

Include this standing execution rule in the plan: at the start of each phase, verify the plan
against the live repo and prior-phase deviations. Do not reopen settled decisions without new
evidence. If an assumption is invalidated, update the plan and surface the deviation rather
than silently changing direction.

## Sizing phases

A phase is **one agent session**, not a human workday. A capable model implements a multi-file
feature — schema, logic, tests, wiring — in a single run, managing its own todo list. Never
phase by kind of work (a scaffolding phase, a testing phase); phase only at real seams:

- The user should review output or make a decision before the next part starts.
- The output of one phase genuinely determines the design of the next.
- The work is too large for one session's context even executed efficiently.

Merge test: if an agent could execute two adjacent phases in one session with no ambiguity and
no lost checkpoint, they are one phase. Most large features land at 2–4 phases; more is fine
for genuinely large work, but each extra seam must be one of the three above.

Keep task checklists coarse — outcomes ("`ToolCallExecutor` with denial path + tests"), not
micro-steps. The implementing agent plans its own steps; the checklist exists so the user can
see the shape of the run and the agent can self-verify coverage.

## Saving

Follow the repo's existing conventions for plan location and retention. If it has no location
convention, default to `docs/plans/<feature>.md`, or `docs/plans/<area>/<feature>.md` when plans
are naturally grouped by area. If `docs/plans/` is unavailable or inappropriate, ask where
plans should live. Make the final phase move any lasting architecture, operational, or product
facts into their canonical docs; retire or archive the implementation plan only when the repo's
convention requires it.

## Handoff

End your final message with the kickoff prompt for phase 1, in a code block so it can be copied
into a fresh session. Keep it dead simple — the plan carries the context, the prompt just points
at it:

```
Read <plan-path> and build phase 1.
```

Add a trailing sentence of extra context only when something matters that the plan can't know
(e.g. "phase 1's migration is already half-applied locally"). Later phases reuse the same prompt
shape with the phase number changed, so only show phase 1's.
