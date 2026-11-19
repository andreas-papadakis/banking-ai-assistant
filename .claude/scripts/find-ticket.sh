#!/usr/bin/env bash
# Finds tickets (GitHub issues) in every repo_prefix repo, open and closed, and prints one line per hit:
#   <issue url> | <title> | <state> | <board Status>
# Shared by all ticket skills (create-ticket, work-on-ticket, update-ticket), so it lives in
# .claude/scripts/ and not in a skill's folder.
#
# The board Status is read from the issue's own project item (projectItems on the issue), not from
# the project item listing, which has been seen to omit items.
#
# Reads owner, project_number, repo_prefix and token_env_file from config.local.yaml
# in the workspace root (override the path with TICKET_CONFIG). The shared helpers come from lib.sh.
#
# Exit codes: 0 = at least one hit, 1 = error, 2 = nothing matched (not necessarily a failure;
# for a duplicate check it is the expected result).
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  find-ticket.sh --id N
  find-ticket.sh --search KEYWORDS

Options:
  --id      find the ticket whose title starts with "N - " (N is the project-wide ticket number,
            not the per-repo issue number)
  --search  keyword search in titles and bodies, GitHub search syntax (quote phrases, e.g.
            --search '"find ticket" script'); repo:, org: and user: are not allowed

Searches every repo whose name starts with the configured repo_prefix, in all states.
Prints one line per hit:
  <issue url> | <title> | <state> | <board Status>
The Status is "not on board" when the issue is not on the project, "no Status" when it is but has none.

Exit codes:
  0  at least one hit
  1  error
  2  nothing matched (message on stderr, nothing on stdout); whether that is a failure depends on
     the caller: for a duplicate check it is the expected result
EOF
}

ID="" SEARCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) ID="${2:?--id needs a value}"; shift 2 ;;
    --search) SEARCH="${2:?--search needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

if [[ -n $ID && -n $SEARCH ]] || [[ -z $ID && -z $SEARCH ]]; then
  usage >&2; die "use exactly one of --id or --search"
fi
if [[ -n $ID ]]; then
  [[ $ID =~ ^[0-9]+$ ]] || die "--id must be a number (the N in \"N - Title\")"
  ID=$((10#$ID))
fi
if [[ -n $SEARCH ]] && grep -Eqi '(^|[[:space:]])-?(repo|org|user):' <<<"$SEARCH"; then
  die "--search must not contain repo:, org: or user: qualifiers; the script searches every repo_prefix repo itself"
fi

# ---- config -----------------------------------------------------------------------------
load_config
OWNER="$(cfg owner)"; PROJECT_NUMBER="$(cfg project_number)"; PREFIX="$(cfg repo_prefix)"
[[ -n $OWNER && -n $PROJECT_NUMBER && -n $PREFIX ]] || die "config must set owner, project_number and repo_prefix"
[[ $PROJECT_NUMBER =~ ^[0-9]+$ ]] || die "project_number must be a number"
source_token_file

command -v gh >/dev/null || die "gh (GitHub CLI) is not installed"
command -v jq >/dev/null || die "jq is not installed"

REPOS="$(prefixed_repos "$OWNER" "$PREFIX")" || exit 1

# ---- queries ----------------------------------------------------------------------------
ISSUE_FIELDS='url title state projectItems(first:20){nodes{project{number} fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}'
LIST_QUERY='query($o:String!,$r:String!,$endCursor:String){repository(owner:$o,name:$r){issues(first:100,after:$endCursor,states:[OPEN,CLOSED],orderBy:{field:CREATED_AT,direction:ASC}){pageInfo{hasNextPage endCursor} nodes{'"$ISSUE_FIELDS"'}}}}'
SEARCH_QUERY='query($q:String!,$endCursor:String){search(type:ISSUE,query:$q,first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{... on Issue{'"$ISSUE_FIELDS"'}}}}'

# One output line per issue; Status comes from the issue's own item on the configured project.
JQ_LINE='def line:
  ([.projectItems.nodes[] | select(.project.number == $pn)] | first) as $it
  | "\(.url) | \(.title) | \(.state) | \(if $it == null then "not on board" else ($it.fieldValueByName.name // "no Status") end)";'

HITS=""
while IFS= read -r repo; do
  [[ -n $repo ]] || continue
  if [[ -n $ID ]]; then
    # Exact title prefix: list every issue (no search index, so no fuzzy matches and no indexing delay).
    out="$(gh api graphql --paginate -f query="$LIST_QUERY" -f o="$OWNER" -f r="$repo" \
      | jq -r --argjson pn "$PROJECT_NUMBER" --arg p "$ID - " \
          "$JQ_LINE"' .data.repository.issues.nodes[] | select(.title | startswith($p)) | line')" \
      || die "could not list the issues of $OWNER/$repo"
  else
    out="$(gh api graphql --paginate -f query="$SEARCH_QUERY" \
        -f q="repo:$OWNER/$repo is:issue in:title,body sort:created-asc $SEARCH" \
      | jq -r --argjson pn "$PROJECT_NUMBER" \
          "$JQ_LINE"' .data.search.nodes[] | select(.url != null) | line')" \
      || die "could not search the issues of $OWNER/$repo"
  fi
  if [[ -n $out ]]; then HITS+="$out"$'\n'; fi
done <<<"$REPOS"

if [[ -z $HITS ]]; then
  if [[ -n $ID ]]; then
    echo "no ticket found with id $ID (title starting with \"$ID - \") in the $PREFIX* repos of $OWNER, open or closed" >&2
  else
    echo "no ticket found matching \"$SEARCH\" in the $PREFIX* repos of $OWNER, open or closed" >&2
  fi
  exit 2
fi

printf '%s' "$HITS"
if [[ -n $ID ]]; then
  COUNT="$(printf '%s' "$HITS" | grep -c .)"
  if (( COUNT > 1 )); then
    echo "warning: $COUNT tickets have the number $ID; ticket numbers should be unique" >&2
  fi
fi
exit 0
