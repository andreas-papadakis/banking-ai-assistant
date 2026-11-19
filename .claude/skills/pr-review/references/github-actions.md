# GitHub Actions workflows

Workflows run with repo secrets, so every finding below is blocking unless marked otherwise.

- **Secrets** only through `${{ secrets.* }}`, never echoed, never in the `env` of steps that do not need them, never interpolated into `run:`.
- **Untrusted input in `run:`.** PR title, body, branch name, comment and issue text must never be interpolated into shell (`${{ github.event.* }}`). Pass them through `env:` and quote them.
- **Minimal `permissions:`** per job; no `write-all`; the default token is read-only unless a job needs more.
- **Dangerous triggers.** `pull_request_target`, `workflow_run` and `issue_comment` must not check out and run PR code while secrets are available, unless the change explains the isolation.
- **Fork PRs.** Secrets are unavailable there: no secret is exposed, and the job must report clearly that nothing ran instead of failing obscurely.
- **Pinned actions.** Third-party actions pinned to a full commit SHA (a version tag at minimum, with a reason); no `@main` or `@latest`.
- **Model-driven jobs** set turn and concurrency limits, so a loop or a comment flood cannot drain the subscription.
- **Self-modification.** A PR that edits the workflow that reviews it: flag it, because the changed workflow must not be the one that approves the change.
- Non-blocking: caching, job and step naming, duplicated steps, timeouts.
