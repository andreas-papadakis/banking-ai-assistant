# banking-ai-assistant

AI-assistant setup (instructions and skills for Claude Code) for the banking system repositories. It is meant to be used from the parent folder that contains the repos, e.g.:

```
banking/                  <- this repository; start Claude Code here
├── banking-backoffice/   <- separate repo, git-ignored here
└── banking-core-library/ <- separate repo, git-ignored here
```

## Setup

- Install the GitHub CLI (`gh`) and expose a token to it via the `GH_TOKEN` environment variable. The token is never stored in this repository.
- Copy `config.example.yaml` to `config.local.yaml` (git-ignored) and fill in your own values, once it exists.

## Status

Work in progress. Planned: ticket creation in a GitHub Project, later PR review.
