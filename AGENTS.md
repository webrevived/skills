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
        ├── agents/           # optional — host-specific metadata
        ├── references/       # optional — docs the skill tells the agent to read
        └── scripts/          # optional — executable helpers
```

Categories are added as skills land; don't invent one for a single skill. If a new skill
fits an existing category, use it. If it doesn't, propose the category in the PR.

## Categories

Use these broad capability categories:

- `engineering` — frontend, backend, mobile, infrastructure, testing, and architecture
- `design` — UI/UX, design systems, accessibility, and design-tool workflows
- `productivity` — research, writing, planning, communication, and general agent workflows

Create a category directory when its first skill lands; don't add empty directories.
Avoid narrower stack-based categories such as `frontend` or `backend`, and classify
personal workflows by what they help accomplish rather than under a `personal` category.

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

For implicitly invocable skills, the `description` is the primary information an agent
sees before deciding whether to load the skill. Write it as a trigger, not a summary:
lead with "Use when ..." and name the concrete signals (file types, library names, error
messages, phrases the user would say). A description that just restates the title gets
the skill ignored.

### Manual-only skills

Use manual-only invocation when a workflow should run only after the user explicitly
selects it. Support Claude Code and Codex as a pair:

1. Add `disable-model-invocation: true` to `SKILL.md` frontmatter. Claude Code and Cursor
   then expose the skill as `/<skill-name>` without loading it automatically.
2. Add `agents/openai.yaml` with:

   ```yaml
   policy:
     allow_implicit_invocation: false
   ```

   Codex then exposes the skill through `$<skill-name>` and `/skills` without invoking it
   implicitly.

Keep the base `name` and `description` valid for the Agent Skills specification so other
agents can still install the skill. Host-specific invocation controls may be ignored by
other agents. Don't set `user-invocable: false`; that hides the skill from user-facing
invocation instead.

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
