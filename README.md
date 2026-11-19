# banking-ai-assistant

Instructions and skills for [Claude Code](https://claude.com/claude-code) that keep the banking system repositories consistent. Today it creates tickets on a GitHub Project; PR review is planned.

## 🤖 What it does

The **`create-ticket` skill** turns a request into a GitHub issue and puts it on the project board:

- a fixed ticket template (context, what to do, acceptance criteria)
- a project-wide ticket number in the title (`7 - Do the thing`), independent of per-repo issue numbers
- parent and sub-issues when work spans several repos
- Status, Priority and labels set on the board
- duplicate checks before creating anything

The judgment (what the ticket says, where it goes, how important it is) is the model's job. The mechanical steps (next number, create, board, fields, verification) are done by a plain script, [`create-ticket.sh`](.claude/skills/create-ticket/create-ticket.sh), so they are deterministic and cost no tokens.

Looking tickets up is shared by all ticket skills: [`find-ticket.sh`](.claude/scripts/find-ticket.sh) finds a ticket by its number (`--id 12`) or by keywords (`--search "board status"`) in every repo with the prefix, open and closed, and prints one line per hit with the issue URL, title, state and board Status. `create-ticket` uses it for its duplicate check. Helpers shared by the scripts live in [`.claude/scripts/lib.sh`](.claude/scripts/lib.sh).

The full procedure lives in [`.claude/skills/create-ticket/SKILL.md`](.claude/skills/create-ticket/SKILL.md), which is the single source of truth. This README only gives the overview.

## 📁 Layout

Start Claude Code from the folder that contains the repos:

```
banking/               <- this repository; start Claude Code here
├── banking-backoffice/ <- separate repo, git-ignored here
└── banking-*/          <- any other banking-* repo, git-ignored here
```

Every repo whose name starts with the configured prefix (`banking-`) counts as part of the project.

Skills are only discovered when Claude Code is started from this folder. A session started inside one of the repos does not see `create-ticket`, although it still loads this folder's `CLAUDE.md`.

## 🚀 Quick start

1. Install the [GitHub CLI](https://cli.github.com/) (`gh`) and [`jq`](https://jqlang.org/).
2. Create a **classic** personal access token with the `repo` and `project` scopes. Fine-grained tokens cannot reach user-level GitHub Projects.
3. Keep the token out of this repository. For example, put `export GH_TOKEN=...` in a file such as `~/.gh_token_env` (permissions `600`) and point `token_env_file` at it in the config.
4. Copy `config.example.yaml` to `config.local.yaml` (git-ignored) and fill in your own values.
5. Start Claude Code from the parent folder and ask it to create a ticket.

Optional: to stop `gh` commands from prompting each time, add an allowlist to `.claude/settings.local.json` (git-ignored, personal to your machine).

## ⚙️ Configuration

Personal values live in `config.local.yaml`; only the placeholder file `config.example.yaml` is committed. To use a different config file, set the `TICKET_CONFIG` environment variable to its path.

| Key | Meaning |
|---|---|
| `owner` | GitHub user or organization that owns the repos and the project |
| `project_number` | Number of the GitHub Project (the number in `.../projects/<number>`) |
| `repo_prefix` | Repos whose names start with this prefix are part of the project |
| `assignee` | Who every created ticket is assigned to (a username or `@me`) |
| `token_env_file` | Optional file that exports `GH_TOKEN`, sourced before each `gh` call |
| `labels` | Standard labels (name, color, description), kept identical in every repo |

## 📐 Conventions

- **Title:** `<n> - <imperative title>`, where `<n>` is the project-wide counter.
- **Body:** 🎯 Context, 🛠️ What to do, ✅ Acceptance criteria. Features and bugs use Given/When/Then scenarios; chores use a checklist. Open questions go in a warning box at the top as checkboxes. Every ticket ends with a footer naming Claude Code and the model that wrote it.
- **Branches:** `<label>/<n>`, for example `techdebt/7`.
- **Status:** `Backlog` while questions are open, `Ready` when nothing is. Priority runs from P0 (pick up now) to P2 (least important). Size is left empty and Estimate is asked for.
- **Labels:**

  | Label | Color | Use |
  |---|---|---|
  | `feature` | `#a2eeef` | New behavior or request |
  | `techdebt` | `#da4f0a` | Code maintenance, tooling, docs |
  | `spike` | `#f5d84d` | Needs investigation |

## 🔒 Safety

- The token never goes into the repository, and `config.local.yaml` and `.claude/settings.local.json` are git-ignored.
- Claude Code never commits or pushes without explicit permission, and never to the main branch without a confirmation.
- Tickets in public repositories are public. Keep secrets and internal-only details out of them.

## 🗺️ Roadmap

- [x] Ticket creation on a GitHub Project (`create-ticket`)
- [ ] Working on a ticket: branch handling and moving it through the board
- [ ] PR review
