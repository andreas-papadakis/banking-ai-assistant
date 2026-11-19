# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repository holds the AI-assistant setup (instructions and skills) shared by the banking repos. Claude Code is meant to be started from this folder, which also contains the other `banking-*` repos as sibling folders (separate git repos, git-ignored here). Each sibling has its own `CLAUDE.md`.

- Never commit tokens or personal configuration. Keep real values in `config.local.yaml` (git-ignored); commit only `config.example.yaml` with placeholders.
- Keep this file up to date when instructions or skills in this repository change.

## Tickets

Tickets are GitHub issues on the project board configured in `config.local.yaml`. Use the `create-ticket` skill (`.claude/skills/create-ticket/SKILL.md`) for creating them; it holds the template, numbering, parent/sub-issue rule and board field rules. `config.example.yaml` shows the config shape for anyone forking this setup.

## Review rules for this repo

PRs here are reviewed with the generic `pr-review` skill (`.claude/skills/pr-review/SKILL.md`), which holds the universal safety checks and the language and technology references (bash, GitHub Actions, Claude skills). On top of those, these rules are specific to this repo:

- Skills, scripts, `config.example.yaml`, README and this file must agree: config keys, flags, behavior, the skill list and the roadmap. A change that makes one stale is blocking.
- `config.example.yaml` holds placeholders only. A new file with real values or personal data must be added to `.gitignore` in the same change.
- Skills never commit, push, delete or close anything without the owner's explicit permission, and never touch `master`.
- The repo is public: no tickets, paths, emails or internal details of private repos in any committed file.
