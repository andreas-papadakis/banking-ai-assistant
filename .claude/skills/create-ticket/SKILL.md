---
name: create-ticket
description: Create GitHub issues (features, bugs, chores, docs) for the banking repos and put them on the GitHub Project board with the right Status and Priority. Use whenever the user asks to create, file, open or split a ticket/issue, including parent and sub-issues across repos.
---

# create-ticket

Creates tickets as GitHub issues, adds them to the GitHub Project and sets board fields. All user-specific values come from `config.local.yaml` in the workspace root (the folder containing the sibling repos). If it is missing, stop and tell the user to copy `config.example.yaml` to `config.local.yaml` and fill it in.

Config keys used below: `owner`, `project_number`, `repo_prefix`, `token_env_file` (optional).

## Running `gh`

The shell is non-interactive, so shell profiles are not loaded. If `token_env_file` is set, run `source <token_env_file>` at the start of every Bash call that uses `gh`. Never print, echo or inspect the token. Otherwise rely on `GH_TOKEN` being set.

The `gh project ...` subcommands need extra token scopes. Use `gh issue ...` for issues and `gh api graphql` for project operations.

## Autonomy

Create tickets without asking for review. Ask the user first only when:
- the parent repo or ticket type is ambiguous after reading the code,
- an Estimate is needed,
- something would change or remove an existing ticket (never close, delete, retitle or edit existing tickets without being asked).

Never put secrets or internal-only details in a ticket. Some repos are public (check `visibility` with `gh repo view`). After creating, report every ticket with its link, number, Status, Priority and the reason for the Priority.

## Steps

1. **Understand the request.** Decide the type: feature, bug, or chore/tech-debt/docs. Read the relevant code in the sibling repos (all cloned next to each other in the workspace root); use `gh` for a repo that is not cloned.
2. **Choose the repo and parent.** The ticket goes in the repo where the problem is noticed or the feature is requested. That ticket is the **parent**. Root-cause work found in another repo, and dependency bumps in consuming apps, become **sub-issues** of it. When the root cause is discovered later, create the sub-issue then and link it. A bug found directly in a library has its parent in the library.
3. **Compute the number.** Titles are `<n> - <Title>`. `n` is a project-wide counter, independent of per-repo issue numbers. List repos with `gh repo list <owner> --limit 100 --json name`, keep those starting with `repo_prefix`, list their issues in all states (`gh issue list -R <owner>/<repo> --state all --limit 200 --json title`), parse the leading integer of each title, and use max + 1. Recompute immediately before creating. Pull requests do not count. Each sub-issue gets its own number.
4. **Write the title.** Imperative, short, no emoji.
5. **Write the body** (English):

   ```
   > [!WARNING]
   > **❓ Unanswered topics**
   > - [ ] <open question>

   ## 🎯 Context
   <why this is needed, 1-3 lines>
   <bugs only> **Steps to reproduce:** <steps, or "Unknown - part of the investigation">

   ## 🛠️ What to do
   <the work, concrete; for a bug with unknown cause: trace from the symptom to the root cause>

   ## ✅ Acceptance criteria
   <see below>
   ```

   - Include the `❓ Unanswered topics` block only when something is genuinely unanswered, and put it first. Each open question is a checkbox so the user can tick answers off. Never invent answers.
   - Acceptance criteria for **features and bugs**: Given/When/Then scenarios, one per case, with **Given**, **When**, **Then** in bold (a single scenario is fine for small tickets). For **chores, tech debt, docs**: a plain `- [ ]` checklist.
   - No Notes section. Emojis only on the headings and the warning block.
   - Write the body to a file in the scratchpad directory and pass it with `--body-file`.
6. **Labels.** The standard labels (name, color, description) are defined in the `labels` list of the config and must be identical in every `repo_prefix` repo. Before labelling, check the target repo with `gh label list -R <owner>/<repo> --json name,color,description`:
   - Create any missing standard label (`gh label create <name> --color <color> --description "<description>"`).
   - If one exists with a different color or description, align it (`gh label edit`) and tell the user.
   - If the repo still has GitHub's default `enhancement` label, it is replaced by `feature`: if no issue uses it (`gh issue list --label enhancement --state all`), delete it; if issues use it and `feature` is missing, rename it (`gh label edit enhancement --name feature`); otherwise ask the user.
   - Pick the label by ticket type: `feature` for new behavior, `techdebt` for chores, tooling, docs and cleanup, `spike` for investigations, plus the default `bug` and `documentation` where they fit. Do not create labels outside the config list without asking.
7. **Create the issue:** `gh issue create -R <owner>/<repo> --title "<n> - <Title>" --body-file <file> [--label ...]`.
8. **Link sub-issues.** For a sub-issue, get its database id (`gh api repos/<owner>/<repo>/issues/<number> --jq .id`) and attach it to the parent (`gh api repos/<owner>/<parent-repo>/issues/<parent-number>/sub_issues -X POST -F sub_issue_id=<id>`). Verify this on first use and fix this step if the call differs.
9. **Add to the project and set fields** with `gh api graphql`:
   - Look up the project id: `viewer { projectV2(number: <project_number>) { id } }` (for an org owner use `organization(login:)`).
   - Look up field ids and option ids at runtime (`fields(first: 30)` with single-select options). The Status options change over time, so never hard-code ids.
   - Get the issue node id (`repository(...) { issue(number: n) { id } }`), call `addProjectV2ItemById` (it is idempotent and returns the item id; sub-issues are also auto-added by a project workflow), then `updateProjectV2ItemFieldValue` for Status and Priority.
10. **Board field rules:**
    - **Status:** `Backlog` if the ticket has unanswered topics, `Ready` if nothing is open. Never set In progress, In review, Done or PRs; those come from the user and the project workflows.
    - **Priority:** choose it and explain why. `P0` = pick up immediately, `P1` = in between, `P2` = least important.
    - **Size:** leave empty.
    - **Estimate:** a number field; ask the user when one is needed. The user votes with planning-poker numbers from 0 to 21 (0, 1, 2, 3, 5, 8, 13, 21).
11. **Verify with the board and the issue, not the project item list.** The GraphQL `items` listing has been seen to omit items that were just added. Check with `gh issue view` and a node lookup of the item (`node(id: ...)`), or ask the user to look at the board.

## Resolving unanswered topics later

When the user says the open questions are answered, or when asked to check a ticket: read it with `gh issue view`; if every box is ticked, fold the answers into the description, remove the warning block and move the ticket to `Ready`. Do not do this unprompted.
