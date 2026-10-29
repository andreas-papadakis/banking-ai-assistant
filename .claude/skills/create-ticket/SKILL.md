---
name: create-ticket
description: Create GitHub issues (features, bugs, chores, docs) for the banking repos and put them on the GitHub Project board with the right Status and Priority. Use whenever the user asks to create, file, open or split a ticket/issue, including parent and sub-issues across repos.
---

# create-ticket

Creates tickets as GitHub issues, adds them to the GitHub Project and sets board fields. The judgment (what the ticket says, where it goes, how important it is) is yours; the mechanical part is done by `create-ticket.sh` next to this file and by `find-ticket.sh` in `.claude/scripts/` (shared by all ticket skills, together with their helpers in `.claude/scripts/lib.sh`).

All user-specific values come from `config.local.yaml` in the workspace root (the folder containing the sibling repos). If it is missing, stop and tell the user to copy `config.example.yaml` to `config.local.yaml` and fill it in. To use a different config file, set `TICKET_CONFIG` to its path; both scripts honour it.

Config keys: `owner`, `project_number`, `repo_prefix`, `assignee`, `token_env_file` (optional), `labels`.

## Running `gh` and the scripts

Both scripts (`create-ticket.sh` and `.claude/scripts/find-ticket.sh`) read the config, source `token_env_file` themselves and call `gh`. For any other `gh` call, the shell is non-interactive, so shell profiles are not loaded: if `token_env_file` is set, run `source <token_env_file>` at the start of that Bash call. Never print, echo or inspect the token.

The `gh project ...` subcommands need extra token scopes. Use `gh issue ...` for issues and `gh api graphql` for project operations (the script already does).

## Autonomy

Create tickets without asking for review. Ask the user first only when:
- the parent repo or ticket type is ambiguous after reading the code,
- an Estimate is needed,
- something would change or remove an existing ticket (never close, delete, retitle or edit existing tickets without being asked).

Never put secrets or internal-only details in a ticket. Some repos are public (check `visibility` with `gh repo view`). After creating, report every ticket with its link, number, Status, Priority and the reason for the Priority.

## Steps

1. **Understand the request.** Decide the type: feature, bug, or chore/tech-debt/docs. Read the relevant code in the sibling repos (all cloned next to each other in the workspace root); use `gh` for a repo that is not cloned.
2. **Choose the repo and parent.** The ticket goes in the repo where the problem is noticed or the feature is requested. That ticket is the **parent**. Root-cause work found in another repo, and dependency bumps in consuming apps, become **sub-issues** of it. When the root cause is discovered later, create the sub-issue then and link it. A bug found directly in a library has its parent in the library.
3. **Check for duplicates** before creating. Run the shared lookup script with a few distinctive keywords from the request (repeat with other keywords if the first search is inconclusive):

   ```
   bash .claude/scripts/find-ticket.sh --search "<keywords>"
   ```

   It searches titles and bodies of the issues in every `repo_prefix` repo, open and closed, and prints one line per hit: `<issue url> | <title> | <state> | <board Status>`. Exit code 2 means nothing matched, which is the expected result here, not a failure; exit code 1 is an error. `--id <n>` finds a ticket by its number instead. If a hit covers the same work, tell the user instead of creating a ticket. Never edit, reopen or close the existing ticket without being asked.

   Titles are `<n> - <Title>` where `n` is a project-wide counter, independent of per-repo issue numbers; the script computes it (highest leading number in any `repo_prefix` repo, all states, plus 1). Pull requests do not count. Each sub-issue gets its own number.
4. **Write the title.** Imperative, short, no emoji, and **without the number**: the script prepends `<n> - `.
5. **Write the body** (English) to a file in the scratchpad directory:

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
   - Do not list obvious workflow steps as acceptance criteria, such as committing, pushing, opening or merging a pull request, or other things every ticket needs anyway. They are implicit. Criteria describe the finished outcome, not the process.
   - No Notes section. Emojis only on the headings, the warning block and the footer.
   - Do not write the footer. The script appends `🤖 Authored by [Claude Code](https://claude.com/claude-code) (<model>)` from `--model`, the issue counterpart of the `Co-Authored-By` trailer on commits.
6. **Labels.** The standard labels (name, color, description) are defined in the `labels` list of the config and must be identical in every `repo_prefix` repo. Before labelling, check the target repo with `gh label list -R <owner>/<repo> --json name,color,description`:
   - Create any missing standard label (`gh label create <name> --color <color> --description "<description>"`).
   - If one exists with a different color or description, align it (`gh label edit`) and tell the user.
   - If the repo still has GitHub's default `enhancement` label, it is replaced by `feature`: if no issue uses it (`gh issue list --label enhancement --state all`), delete it; if issues use it and `feature` is missing, rename it (`gh label edit enhancement --name feature`); otherwise ask the user.
   - Pick the label by ticket type: `feature` for new behavior, `techdebt` for chores, tooling, docs and cleanup, `spike` for investigations, plus the default `bug` and `documentation` where they fit. Do not create labels outside the config list without asking.
7. **Decide the board fields:**
   - **Status:** `Backlog` if the ticket has unanswered topics, `Ready` if nothing is open. Never set In progress, In review, Done or PRs; those come from the user and the project workflows.
   - **Priority:** choose it and explain why. `P0` = pick up immediately, `P1` = in between, `P2` = least important.
   - **Size:** leave empty.
   - **Estimate:** a number field; ask the user when one is needed. The user votes with planning-poker numbers from 0 to 21 (0, 1, 2, 3, 5, 8, 13, 21).
8. **Create the ticket with the script.** Run it from anywhere, with the model you are running as in `--model`. Do a `--dry-run` first when unsure; it validates the repo, labels, Status and Priority and prints the number it would use, without writing anything.

   ```
   bash .claude/skills/create-ticket/create-ticket.sh \
     --repo <repo-name> --title "<Title>" --body-file <file> --model "<model name>" \
     --label <label> --status <Backlog|Ready> --priority <P0|P1|P2> [--estimate <n>] \
     [--parent <owner>/<repo>#<n>] [--dry-run]
   ```

   It creates the issue (assigned to the config's `assignee`), adds it to the project, sets Status, Priority and Estimate, and verifies them from the issue's own project item (the project item listing has been seen to omit items that were just added). It prints the number, the URL and the board values, and exits non-zero on any failure. If it fails after creating the issue, it has already printed `created: <url>`; tell the user what failed.
9. **Sub-issues.** Create the parent ticket first, then create each child with `--parent <owner>/<repo>#<n>` pointing at it. The script links the child to the parent and checks that the parent now lists it. The parent may be in any repo of the same owner with the configured prefix, and must be open. Every child gets its own number, Status and Priority like any other ticket. The linking call needs the child's database id, not its issue number; the script does that, so never link by hand.

## Resolving unanswered topics (tickets still in Backlog)

A ticket created with open questions stays in `Backlog` until they are answered. This is part of finishing its creation, so it is done with this skill. When the user gives answers in chat, or says they ticked the boxes of a ticket:

1. Read the ticket (`gh issue view <n> -R <owner>/<repo> --json title,body,state,labels`).
2. Fold the answers into Context, What to do and Acceptance criteria. Never invent an answer: a ticked box with no answer given means ask the user.
3. Remove the answered items from the `❓ Unanswered topics` block. If every item is answered, remove the whole block; if some remain, keep the block with only the remaining unchecked items.
4. Write the complete new body to a file in the scratchpad directory and run:

   ```
   bash .claude/skills/create-ticket/create-ticket.sh --update <owner>/<repo>#<n> \
     --body-file <file> [--ready] [--model "<model name>"] [--dry-run]
   ```

   Use `--ready` only when no unanswered topics remain; it then moves the ticket from Backlog to Ready. Without `--ready`, the ticket stays in Backlog. The title, Priority and Estimate are never changed here unless the user asks.

The script refuses to update a ticket that is closed or whose board Status is anything but Backlog, and it refuses `--ready` while the body still has an `Unanswered topics` block. If it refuses because the ticket is in progress, tell the user: tickets in progress are out of scope for this skill.
