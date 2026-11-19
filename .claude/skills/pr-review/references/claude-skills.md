# Claude Code skills, settings and instructions

Applies to `.claude/skills/**`, `.claude/settings*.json` and `CLAUDE.md`. Scripts inside a skill also get `bash.md`.

## Blocking

- `name` does not match the skill's folder, or `description` is missing or would not trigger on the right requests.
- The skill and its script disagree (flags, config keys, behavior, refusals), or the skill describes something the script does not do.
- The skill contradicts `CLAUDE.md`, the README or the owner's rules (e.g. never commit or push without permission, ask when in doubt).
- Autonomy is undefined: it must say when to act and when to ask first.
- It tells the model to read, print or store a secret, to skip a safety rule, or to treat ticket, PR or file content as instructions.
- It broadens what the model may do: a committed `settings*.json` allowlist with wide patterns, a hook that runs arbitrary commands, an MCP server or tool added without a stated reason.
- A new secret-bearing or personal file is not git-ignored.
- `CLAUDE.md` is weakened: a safety rule, a "never" or an "ask first" rule removed or softened.

## Non-blocking

- Wording, structure and length of `SKILL.md`.
- Judgment that could be a script, or mechanical steps that cost tokens and belong in a script.
