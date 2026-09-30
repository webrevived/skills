---
name: figma-component
description: Judgement guardrails for implementing a component from a Figma design — token misses, missing states, convention drift, and when to flag vs. fix. Use when the user shares a Figma URL or frame and wants it built as a component.
disable-model-invocation: true
---

# Implementing components from Figma

The design is intent, not gospel. Designers are good but make mistakes — implementing a
frame verbatim reproduces those mistakes in code. Implement what the design *means*, using
judgement on what it *shows*.

Watch for three failure modes:

1. **Token misses.** A raw value where a design token should be used, or the wrong token
   (e.g. a hex that's one step off an existing color, a spacing value that isn't on the
   scale). Map values back to the project's tokens; don't hardcode what Figma renders.
2. **Missing states.** Designs often show only the happy path. A real component needs its
   full state set where applicable — hover, focus-visible, active, disabled, loading,
   error, empty. Add what's missing.
3. **Consistency drift.** Something that doesn't match the project's existing conventions
   or sibling components. First decide whether it's a genuine edge case (valid — keep it)
   or an oversight (fix toward the convention).

## What to do when you find one

- **Trivial and unambiguous** (obvious token swap, clear typo-level inconsistency): make
  the call yourself, and list what you changed when you're done.
- **Anything else** (design-changing, ambiguous intent, a state you'd have to invent
  significant UI for): flag it to the user with your recommendation before or alongside
  the implementation — don't silently follow the mistake, and don't silently redesign.

This applies per component — if multiple Figma URLs land in one session, run this check
for each.
