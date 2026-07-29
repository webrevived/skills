@AGENTS.md

## Claude Code specifics

- Installs land in `.claude/skills/` (project) or `~/.claude/skills/` (global):
  `npx skills add webrevived/skills -a claude-code`.
- Skills in this repo must not assume Claude Code. They run under Codex, Cursor, and
  OpenCode too — no `.claude/` paths, no Claude-only tool names, no slash commands in the
  instructions unless the skill is explicitly Claude-scoped and says so in its description.
- When a skill needs to be Claude-only, say so in the `description` so other agents skip it.
