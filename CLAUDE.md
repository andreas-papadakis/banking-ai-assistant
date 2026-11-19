# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repository holds the AI-assistant setup (instructions and skills) shared by the banking repos. Claude Code is meant to be started from this folder, which also contains the other `banking-*` repos as sibling folders (separate git repos, git-ignored here). Each sibling has its own `CLAUDE.md`.

- Never commit tokens or personal configuration. Keep real values in `config.local.yaml` (git-ignored); commit only `config.example.yaml` with placeholders.
- Keep this file up to date when instructions or skills in this repository change.

## Tickets

Tickets are GitHub issues on the project board configured in `config.local.yaml`. Use the `create-ticket` skill (`.claude/skills/create-ticket/SKILL.md`) for creating them; it holds the template, numbering, parent/sub-issue rule and board field rules. `config.example.yaml` shows the config shape for anyone forking this setup.

To look tickets up by number or keywords, use `.claude/scripts/find-ticket.sh` (`--id <n>` or `--search "<keywords>"`). It searches every `repo_prefix` repo in all states and prints the issue URL, title, state and board Status, one line per hit. Exit code 2 means nothing matched (whether that is a failure depends on the caller); 1 is an error. Scripts and helpers shared by more than one ticket skill live in `.claude/scripts/` (`lib.sh` holds the shared config, token and repo-listing helpers), not in a skill's folder. Set `TICKET_CONFIG` to use a config file other than `config.local.yaml`.
