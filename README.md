# WebRevived Skills

Agent skills we use at [WebRevived](https://webrevived.com) — building web apps, mobile
apps, design, and infrastructure for startups and SMEs. Open to anyone.

A skill is a portable set of instructions that a coding agent loads on demand. These are
the conventions and workflows we'd otherwise re-explain to an agent on every project.
They work with Claude Code, Codex, Cursor, OpenCode, and ~70 other agents via the
[`skills` CLI](https://github.com/vercel-labs/skills).

## Install

```bash
# Pick from a list
npx skills add webrevived/skills

# A specific skill, globally, for Claude Code
npx skills add webrevived/skills --skill <name> -g -a claude-code

# Everything
npx skills add webrevived/skills --all
```

Project installs go to `./.claude/skills/` (or your agent's equivalent); `-g` installs to
your home directory instead. `npx skills update` pulls the latest versions.

## Skills

| Skill | Category | What it does | Invoke |
| ----- | -------- | ------------ | ------ |
| [build-plan](./skills/engineering/build-plan/SKILL.md) | Engineering | Claude Code only. Builds every remaining phase of a `write-plan` plan unattended: one fresh subagent per phase builds, verifies, and runs `codex-loop --auto`; the orchestrator checks the result and commits each phase, never pushes. | Claude Code: `/build-plan <plan-path>` |
| [codex-loop](./skills/engineering/codex-loop/SKILL.md) | Engineering | Reviews an immutable snapshot of uncommitted changes (or `--base <ref>` → working tree) with Codex, fixes valid findings, and verifies them in bounded rounds; `--auto` for unattended runs, `--model sol` for Sol. | Claude Code/Cursor: `/codex-loop`; Codex: `$codex-loop` |
| [figma-build](./skills/design/figma-build/SKILL.md) | Design | Implements a component or page from Figma with judgement: maps raw values to tokens, fills missing states, and asks about unbuilt features or unclear design issues instead of copying them. | Claude Code/Cursor: `/figma-build`; Codex: `$figma-build` |
| [grill-me](./skills/productivity/grill-me/SKILL.md) | Productivity | Stress-tests a plan or design through relentless, one-at-a-time questioning. | Claude Code/Cursor: `/grill-me`; Codex: `$grill-me` |
| [write-plan](./skills/productivity/write-plan/SKILL.md) | Productivity | Writes phased implementation plans sized to one AI coding-agent session per phase, with per-phase Verify steps and upfront "Needs from user" items; hands off to `build-plan`. | Claude Code/Cursor: `/write-plan`; Codex: `$write-plan` |

## Contributing

Skills live at `skills/<category>/<skill-name>/SKILL.md`. Scaffold one with
`npx skills init <name>`, write the instructions, and open a PR. See
[AGENTS.md](./AGENTS.md) for the `engineering`, `design`, and `productivity` category
definitions, layout, and authoring conventions.

Test locally before opening a PR:

```bash
npx skills add /path/to/this/repo --skill <name>
```

Issues and PRs welcome, including from outside WebRevived.
