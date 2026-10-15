#!/usr/bin/env bash
# Creates a ticket (GitHub issue) on the GitHub Project board, or finishes one that is still in Backlog.
#
# This script only does the mechanical steps. Deciding what a ticket says (type, parent repo,
# duplicates, priority, text, how answers fold into the description) is the skill's job (see SKILL.md).
#
# Reads owner, project_number, repo_prefix, assignee and token_env_file from config.local.yaml
# in the workspace root (override the path with CREATE_TICKET_CONFIG).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  Create a ticket:
    create-ticket.sh --repo REPO --title TITLE --body-file FILE --model MODEL \
                     --status STATUS --priority PRIORITY [--label NAME]... [--estimate N] \
                     [--parent OWNER/REPO#N] [--dry-run]

  Update a ticket that is still in Backlog (e.g. to fold in answers to its open questions):
    create-ticket.sh --update OWNER/REPO#N --body-file FILE [--ready] [--model MODEL] [--dry-run]

Create options:
  --repo       repo name without the owner, e.g. banking-ai-assistant
  --title      title WITHOUT the number; the script prepends "<n> - "
  --body-file  markdown body; a footer naming Claude Code and the model is appended
  --model      name of the model that wrote the ticket, used in the footer
  --label      label to apply, repeatable; must already exist in the repo
  --status     board Status option name, e.g. Backlog or Ready
  --priority   board Priority option name, e.g. P0, P1 or P2
  --estimate   optional number for the Estimate field
  --parent     create the ticket as a sub-issue of this open parent ticket (any repo of the same
               owner and prefix); the parent must already exist

Update options:
  --update     the ticket to update; refused unless it is open and its board Status is Backlog
  --body-file  the complete new body; replaces the old one (the title never changes)
  --ready      also move the ticket to Ready; refused while the body still has an
               "Unanswered topics" block
  --model      if given and the body has no footer yet, append the Claude Code footer

Common:
  --dry-run    validate everything and print what would happen, without writing anything
EOF
}

die() { echo "error: $*" >&2; exit 1; }

REPO="" TITLE="" BODY_FILE="" MODEL="" STATUS="" PRIORITY="" ESTIMATE="" PARENT="" UPDATE="" READY=0 DRY_RUN=0
LABELS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:?--repo needs a value}"; shift 2 ;;
    --title) TITLE="${2:?--title needs a value}"; shift 2 ;;
    --body-file) BODY_FILE="${2:?--body-file needs a value}"; shift 2 ;;
    --model) MODEL="${2:?--model needs a value}"; shift 2 ;;
    --label) LABELS+=("${2:?--label needs a value}"); shift 2 ;;
    --status) STATUS="${2:?--status needs a value}"; shift 2 ;;
    --priority) PRIORITY="${2:?--priority needs a value}"; shift 2 ;;
    --estimate) ESTIMATE="${2:?--estimate needs a value}"; shift 2 ;;
    --parent) PARENT="${2:?--parent needs a value}"; shift 2 ;;
    --update) UPDATE="${2:?--update needs a value}"; shift 2 ;;
    --ready) READY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

if [[ -n $UPDATE ]]; then
  [[ -z $REPO && -z $TITLE && -z $STATUS && -z $PRIORITY && -z $ESTIMATE && -z $PARENT && ${#LABELS[@]} -eq 0 ]] \
    || die "--update only accepts --body-file, --ready, --model and --dry-run"
  [[ $UPDATE =~ ^([^/]+)/([^#]+)#([0-9]+)$ ]] || die "--update must look like OWNER/REPO#N"
  [[ -n $BODY_FILE ]] || { usage >&2; die "--update needs --body-file"; }
  [[ -f $BODY_FILE ]] || die "body file not found: $BODY_FILE"
else
  [[ $READY -eq 0 ]] || die "--ready only works together with --update"
  [[ -n $STATUS && -n $PRIORITY ]] || { usage >&2; die "--status and --priority are required"; }
  [[ -n $REPO && -n $TITLE && -n $BODY_FILE && -n $MODEL ]] \
    || { usage >&2; die "--repo, --title, --body-file and --model are required"; }
  [[ -f $BODY_FILE ]] || die "body file not found: $BODY_FILE"
  if [[ $TITLE =~ ^[0-9]+\ -\  ]]; then die "title must not start with a number; the script adds it"; fi
  if [[ -n $ESTIMATE && ! $ESTIMATE =~ ^[0-9]+(\.[0-9]+)?$ ]]; then die "--estimate must be a number"; fi
  if [[ -n $PARENT && ! $PARENT =~ ^([^/]+)/([^#]+)#([0-9]+)$ ]]; then die "--parent must look like OWNER/REPO#N"; fi
fi

# ---- config -----------------------------------------------------------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONFIG="${CREATE_TICKET_CONFIG:-$ROOT/config.local.yaml}"
[[ -f $CONFIG ]] || die "config not found: $CONFIG (copy config.example.yaml to config.local.yaml)"

# Top-level "key: value" lines only; strips surrounding quotes.
cfg() {
  awk -v k="$1" '
    index($0, k ":") == 1 {
      v = substr($0, length(k) + 2); sub(/^ +/, "", v); sub(/ +#.*$/, "", v)
      gsub(/^"|"$/, "", v); print v; exit
    }' "$CONFIG"
}

OWNER="$(cfg owner)"; PROJECT_NUMBER="$(cfg project_number)"; PREFIX="$(cfg repo_prefix)"
ASSIGNEE="$(cfg assignee)"; TOKEN_FILE="$(cfg token_env_file)"
[[ -n $OWNER && -n $PROJECT_NUMBER && -n $PREFIX && -n $ASSIGNEE ]] \
  || die "config must set owner, project_number, repo_prefix and assignee"
[[ $PROJECT_NUMBER =~ ^[0-9]+$ ]] || die "project_number must be a number"

if [[ -n $TOKEN_FILE ]]; then
  TOKEN_FILE="${TOKEN_FILE/#\~/$HOME}"
  [[ -f $TOKEN_FILE ]] || die "token_env_file not found: $TOKEN_FILE"
  # shellcheck disable=SC1090
  source "$TOKEN_FILE"
fi

command -v gh >/dev/null || die "gh (GitHub CLI) is not installed"
command -v jq >/dev/null || die "jq is not installed"

# ---- project lookup and validation (read-only, so we fail before writing anything) -------
PROJECT_QUERY='query($owner:String!,$num:Int!){repositoryOwner(login:$owner){... on ProjectV2Owner{projectV2(number:$num){id fields(first:50){nodes{... on ProjectV2Field{id name dataType} ... on ProjectV2SingleSelectField{id name options{id name}}}}}}}}'
PROJECT_JSON="$(gh api graphql -f query="$PROJECT_QUERY" -f owner="$OWNER" -F num="$PROJECT_NUMBER")"
PROJECT_ID="$(jq -r '.data.repositoryOwner.projectV2.id // empty' <<<"$PROJECT_JSON")"
[[ -n $PROJECT_ID ]] || die "project $PROJECT_NUMBER not found for $OWNER (or the token cannot see it)"

field_id() {
  jq -r --arg n "$1" '.data.repositoryOwner.projectV2.fields.nodes[] | select(.name == $n) | .id' <<<"$PROJECT_JSON" | head -n 1
}
option_id() { # field name, option name
  jq -r --arg f "$1" --arg o "$2" \
    '.data.repositoryOwner.projectV2.fields.nodes[] | select(.name == $f) | .options[]? | select(.name == $o) | .id' \
    <<<"$PROJECT_JSON" | head -n 1
}
options_of() {
  jq -r --arg f "$1" '.data.repositoryOwner.projectV2.fields.nodes[] | select(.name == $f) | [.options[]?.name] | join(", ")' \
    <<<"$PROJECT_JSON"
}
set_select() { # item id, field id, option id
  gh api graphql \
    -f query='mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}}){projectV2Item{id}}}' \
    -f p="$PROJECT_ID" -f i="$1" -f f="$2" -f o="$3" >/dev/null
}
append_footer() { # file; appends the Claude Code footer unless one is already there
  if ! grep -q 'Authored by' "$1"; then
    local body
    body="$(cat "$1")" # command substitution drops trailing newlines, so the footer is spaced evenly
    printf '%s\n\n---\n🤖 Authored by [Claude Code](https://claude.com/claude-code) (%s)\n' "$body" "$MODEL" >"$1"
  fi
}

STATUS_FIELD="$(field_id Status)"
[[ -n $STATUS_FIELD ]] || die "the project has no Status field"

# ============================================================================================
# Update mode: only for tickets that are open and still in Backlog
# ============================================================================================
if [[ -n $UPDATE ]]; then
  [[ $UPDATE =~ ^([^/]+)/([^#]+)#([0-9]+)$ ]]
  U_OWNER="${BASH_REMATCH[1]}"; U_REPO="${BASH_REMATCH[2]}"; U_NUMBER="${BASH_REMATCH[3]}"
  [[ $U_OWNER == "$OWNER" ]] || die "ticket owner \"$U_OWNER\" does not match the configured owner \"$OWNER\""
  case "$U_REPO" in "$PREFIX"*) ;; *) die "repo \"$U_REPO\" does not start with the configured prefix \"$PREFIX\"" ;; esac

  READY_OPTION=""
  if [[ $READY -eq 1 ]]; then
    READY_OPTION="$(option_id Status Ready)"
    [[ -n $READY_OPTION ]] || die "Status \"Ready\" not found; options: $(options_of Status)"
    if grep -q 'Unanswered topics' "$BODY_FILE"; then
      die "the new body still has an \"Unanswered topics\" block; answer or remove it before using --ready"
    fi
  fi

  INFO="$(gh api graphql \
    -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){state projectItems(first:20){nodes{id project{number} fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}' \
    -f o="$U_OWNER" -f r="$U_REPO" -F n="$U_NUMBER")"
  ISSUE_STATE="$(jq -r '.data.repository.issue.state // empty' <<<"$INFO")"
  [[ -n $ISSUE_STATE ]] || die "issue not found: $UPDATE"
  [[ $ISSUE_STATE == OPEN ]] || die "$UPDATE is $ISSUE_STATE; only open tickets can be updated"
  ITEM_ID="$(jq -r --argjson p "$PROJECT_NUMBER" \
    '.data.repository.issue.projectItems.nodes[] | select(.project.number == $p) | .id' <<<"$INFO" | head -n 1)"
  CUR_STATUS="$(jq -r --argjson p "$PROJECT_NUMBER" \
    '.data.repository.issue.projectItems.nodes[] | select(.project.number == $p) | .fieldValueByName.name // empty' <<<"$INFO" | head -n 1)"
  [[ -n $ITEM_ID ]] || die "$UPDATE is not on project $PROJECT_NUMBER"
  [[ $CUR_STATUS == Backlog ]] \
    || die "$UPDATE has Status \"$CUR_STATUS\"; only tickets in Backlog can be updated here (tickets in progress are out of scope)"

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "dry run, nothing written"
    if [[ $READY -eq 1 ]]; then
      echo "would replace the body of $UPDATE and move it from Backlog to Ready"
    else
      echo "would replace the body of $UPDATE and keep it in Backlog"
    fi
    exit 0
  fi

  BODY_TMP="$(mktemp)"; trap 'rm -f "$BODY_TMP"' EXIT
  cp "$BODY_FILE" "$BODY_TMP"
  if [[ -n $MODEL ]]; then append_footer "$BODY_TMP"; fi
  gh issue edit "$U_NUMBER" -R "$U_OWNER/$U_REPO" --body-file "$BODY_TMP" >/dev/null
  echo "updated body: https://github.com/$U_OWNER/$U_REPO/issues/$U_NUMBER"

  if [[ $READY -eq 1 ]]; then
    set_select "$ITEM_ID" "$STATUS_FIELD" "$READY_OPTION"
    GOT="$(gh api graphql \
      -f query='query($i:ID!){node(id:$i){... on ProjectV2Item{fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}' \
      -f i="$ITEM_ID" --jq '.data.node.fieldValueByName.name')"
    [[ $GOT == Ready ]] || die "verification failed: Status is \"$GOT\", expected Ready"
    echo "board: Status=Ready"
  else
    echo "board: Status stays Backlog"
  fi
  exit 0
fi

# ============================================================================================
# Create mode
# ============================================================================================
PRIORITY_FIELD="$(field_id Priority)"
STATUS_OPTION="$(option_id Status "$STATUS")"; PRIORITY_OPTION="$(option_id Priority "$PRIORITY")"
[[ -n $STATUS_OPTION ]] || die "Status \"$STATUS\" not found; options: $(options_of Status)"
[[ -n $PRIORITY_FIELD && -n $PRIORITY_OPTION ]] || die "Priority \"$PRIORITY\" not found; options: $(options_of Priority)"
ESTIMATE_FIELD=""
if [[ -n $ESTIMATE ]]; then
  ESTIMATE_FIELD="$(field_id Estimate)"
  [[ -n $ESTIMATE_FIELD ]] || die "the project has no Estimate field"
fi

next_number() {
  local max=0 repo titles t n
  while IFS= read -r repo; do
    [[ -n $repo ]] || continue
    titles="$(gh issue list -R "$OWNER/$repo" --state all --limit 1000 --json title --jq '.[].title')"
    while IFS= read -r t; do
      if [[ $t =~ ^([0-9]+)\ -\  ]]; then
        n=$((10#${BASH_REMATCH[1]}))
        if (( n > max )); then max=$n; fi
      fi
    done <<<"$titles"
  done < <(gh repo list "$OWNER" --limit 200 --json name --jq '.[].name' | grep "^${PREFIX}" || true)
  echo $((max + 1))
}

case "$REPO" in "$PREFIX"*) ;; *) die "repo \"$REPO\" does not start with the configured prefix \"$PREFIX\"" ;; esac
gh repo view "$OWNER/$REPO" --json name >/dev/null 2>&1 || die "repo not found: $OWNER/$REPO"
if [[ ${#LABELS[@]} -gt 0 ]]; then
  REPO_LABELS="$(gh label list -R "$OWNER/$REPO" --limit 200 --json name --jq '.[].name')"
  for l in "${LABELS[@]}"; do
    grep -qxF -- "$l" <<<"$REPO_LABELS" || die "label \"$l\" does not exist in $OWNER/$REPO"
  done
fi
if [[ -n $PARENT ]]; then
  [[ $PARENT =~ ^([^/]+)/([^#]+)#([0-9]+)$ ]]
  P_OWNER="${BASH_REMATCH[1]}"; P_REPO="${BASH_REMATCH[2]}"; P_NUM="${BASH_REMATCH[3]}"
  [[ $P_OWNER == "$OWNER" ]] || die "parent owner \"$P_OWNER\" does not match the configured owner \"$OWNER\""
  case "$P_REPO" in "$PREFIX"*) ;; *) die "parent repo \"$P_REPO\" does not start with the configured prefix \"$PREFIX\"" ;; esac
  P_STATE="$(gh api "repos/$P_OWNER/$P_REPO/issues/$P_NUM" --jq .state 2>/dev/null)" || die "parent not found: $PARENT"
  [[ $P_STATE == open ]] || die "parent $PARENT is $P_STATE; sub-issues can only be added to an open ticket"
fi
NUMBER="$(next_number)"
FULL_TITLE="$NUMBER - $TITLE"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "dry run, nothing written"
  echo "would create in $OWNER/$REPO: \"$FULL_TITLE\" (assignee $ASSIGNEE, labels: ${LABELS[*]:-none})"
  echo "would set Status=$STATUS Priority=$PRIORITY${ESTIMATE:+ Estimate=$ESTIMATE}"
  if [[ -n $PARENT ]]; then echo "would link it as a sub-issue of $PARENT"; fi
  exit 0
fi

# ---- create the issue --------------------------------------------------------------------
BODY_TMP="$(mktemp)"; trap 'rm -f "$BODY_TMP"' EXIT
cp "$BODY_FILE" "$BODY_TMP"
append_footer "$BODY_TMP"
ARGS=(issue create -R "$OWNER/$REPO" --title "$FULL_TITLE" --body-file "$BODY_TMP" --assignee "$ASSIGNEE")
for l in ${LABELS[@]+"${LABELS[@]}"}; do ARGS+=(--label "$l"); done
ISSUE_URL="$(gh "${ARGS[@]}")"
[[ $ISSUE_URL =~ ^https://github.com/([^/]+)/([^/]+)/issues/([0-9]+)$ ]] || die "unexpected output from gh issue create: $ISSUE_URL"
ISSUE_OWNER="${BASH_REMATCH[1]}"; ISSUE_REPO="${BASH_REMATCH[2]}"; ISSUE_NUMBER="${BASH_REMATCH[3]}"
echo "created: $ISSUE_URL"

# ---- add to the project and set the fields -----------------------------------------------
ISSUE_NODE="$(gh api graphql \
  -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){id}}}' \
  -f o="$ISSUE_OWNER" -f r="$ISSUE_REPO" -F n="$ISSUE_NUMBER" --jq '.data.repository.issue.id')"
[[ -n $ISSUE_NODE && $ISSUE_NODE != null ]] || die "issue not found: $ISSUE_OWNER/$ISSUE_REPO#$ISSUE_NUMBER"

ITEM_ID="$(gh api graphql \
  -f query='mutation($p:ID!,$c:ID!){addProjectV2ItemById(input:{projectId:$p,contentId:$c}){item{id}}}' \
  -f p="$PROJECT_ID" -f c="$ISSUE_NODE" --jq '.data.addProjectV2ItemById.item.id')"
[[ -n $ITEM_ID && $ITEM_ID != null ]] || die "could not add the issue to the project"

set_select "$ITEM_ID" "$STATUS_FIELD" "$STATUS_OPTION"
set_select "$ITEM_ID" "$PRIORITY_FIELD" "$PRIORITY_OPTION"
if [[ -n $ESTIMATE_FIELD ]]; then
  gh api graphql \
    -f query='mutation($p:ID!,$i:ID!,$f:ID!,$v:Float!){updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{number:$v}}){projectV2Item{id}}}' \
    -f p="$PROJECT_ID" -f i="$ITEM_ID" -f f="$ESTIMATE_FIELD" -F v="$ESTIMATE" >/dev/null
fi

# ---- verify from the issue's own project item (the project item listing can omit new items) -
VERIFY="$(gh api graphql \
  -f query='query($i:ID!){node(id:$i){... on ProjectV2Item{project{number} fieldValues(first:30){nodes{... on ProjectV2ItemFieldSingleSelectValue{name field{... on ProjectV2FieldCommon{name}}} ... on ProjectV2ItemFieldNumberValue{number field{... on ProjectV2FieldCommon{name}}}}}}}}' \
  -f i="$ITEM_ID")"
GOT_PROJECT="$(jq -r '.data.node.project.number' <<<"$VERIFY")"
GOT_STATUS="$(jq -r '.data.node.fieldValues.nodes[] | select(.field.name? == "Status") | .name' <<<"$VERIFY")"
GOT_PRIORITY="$(jq -r '.data.node.fieldValues.nodes[] | select(.field.name? == "Priority") | .name' <<<"$VERIFY")"
[[ $GOT_PROJECT == "$PROJECT_NUMBER" && $GOT_STATUS == "$STATUS" && $GOT_PRIORITY == "$PRIORITY" ]] \
  || die "verification failed: project=$GOT_PROJECT Status=$GOT_STATUS Priority=$GOT_PRIORITY"
if [[ -n $ESTIMATE ]]; then
  # Compare as numbers: GitHub returns 3.0 for an estimate of 3.
  jq -e --argjson e "$ESTIMATE" \
    '[.data.node.fieldValues.nodes[] | select(.field.name? == "Estimate") | .number == $e] | any' \
    <<<"$VERIFY" >/dev/null || die "verification failed: Estimate is not $ESTIMATE"
fi

# ---- link as a sub-issue (sub_issue_id is the issue's database id, not its number) ------------
if [[ -n $PARENT ]]; then
  CHILD_ID="$(gh api "repos/$ISSUE_OWNER/$ISSUE_REPO/issues/$ISSUE_NUMBER" --jq .id)"
  gh api -X POST "repos/$P_OWNER/$P_REPO/issues/$P_NUM/sub_issues" -F sub_issue_id="$CHILD_ID" >/dev/null \
    || die "created $ISSUE_URL but could not link it to $PARENT"
  gh api --paginate "repos/$P_OWNER/$P_REPO/issues/$P_NUM/sub_issues" \
    --jq '.[] | "\(.repository_url | split("/") | .[-1])#\(.number)"' | grep -qxF "$ISSUE_REPO#$ISSUE_NUMBER" \
    || die "created $ISSUE_URL but linking to $PARENT could not be verified"
fi

echo "number: $NUMBER"
echo "url: $ISSUE_URL"
echo "board: project $GOT_PROJECT, Status=$GOT_STATUS, Priority=$GOT_PRIORITY${ESTIMATE:+, Estimate=$ESTIMATE}"
if [[ -n $PARENT ]]; then echo "parent: $PARENT"; fi
