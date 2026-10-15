# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repository holds the AI-assistant setup (instructions and skills) shared by the banking repos. Claude Code is meant to be started from this folder, which also contains the other `banking-*` repos as sibling folders (separate git repos, git-ignored here). Each sibling has its own `CLAUDE.md`.

- Never commit tokens or personal configuration. Keep real values in `config.local.yaml` (git-ignored); commit only `config.example.yaml` with placeholders.
- Keep this file up to date when instructions or skills in this repository change.

## Tickets

Tickets are GitHub issues on the project board configured in `config.local.yaml`. Use the `create-ticket` skill (`.claude/skills/create-ticket/SKILL.md`) for creating them; it holds the template, numbering, parent/sub-issue rule and board field rules. `config.example.yaml` shows the config shape for anyone forking this setup.
