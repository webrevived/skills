# WebRevived Skills

Public catalog of [Agent Skills](https://github.com/vercel-labs/skills) maintained by
WebRevived. Skills are portable instruction sets that any coding agent (Claude Code,
Codex, Cursor, OpenCode, and ~70 others) can install with the `skills` CLI.

This repo is **content, not code**. There is no build step, no dependencies, and nothing
to compile. A skill is a directory containing a `SKILL.md`.

Everything here is public and non-proprietary. Never commit client names, credentials,
internal URLs, or anything under NDA — assume every file is read by strangers.

## Layout

Catalog layout — the CLI walks two levels deep under `skills/`:

```
skills/
└── <category>/
    └── <skill-name>/
        ├── SKILL.md          # required — the skill itself
        ├── references/       # optional — docs the skill tells the agent to read
        └── scripts/          # optional — executable helpers
```

Categories are added as skills land; don't invent one for a single skill. If a new skill
fits an existing category, use it. If it doesn't, propose the category in the PR.

## Authoring a skill

Scaffold with `npx skills init <name>`, then move it under the right category.

`SKILL.md` frontmatter:

```yaml
---
name: my-skill              # required — lowercase, hyphens, matches the directory name
description: >              # required — what it does AND when to use it
  Use when ...
metadata:
  internal: true            # optional — hides the skill from discovery
---
```

The `description` is the only thing an agent sees before deciding whether to load the
skill. Write it as a trigger, not a summary: lead with "Use when ..." and name the
concrete signals (file types, library names, error messages, phrases the user would say).
A description that just restates the title gets the skill ignored.

Body conventions:

- Write instructions to the agent in the imperative. No marketing, no "this skill will".
- Be prescriptive. A skill exists to encode a decision we've already made — state the
  decision and the reason, don't survey the options.
- Keep the body short enough to stay useful in context. Push long reference material
  into `references/` and tell the agent when to read it.
- Prefer one skill that does one thing well over a kitchen-sink skill.

## Working on this repo

- Test a skill before committing: `npx skills add . --skill <name>` from a scratch
  project, then drive the agent through the workflow the skill claims to handle.
- Renaming a skill directory breaks everyone's install. Treat names as an API.
- Keep the skill table in `README.md` in sync when adding or removing a skill.
