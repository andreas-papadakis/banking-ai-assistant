#!/usr/bin/env bash
# Finds the pull requests that belong to a ticket, across every repo with the configured prefix.
#
# Read-only: it lists PRs and writes nothing. The ticket number is the project-wide number
# (the "13" in "13 - Title"), not a per-repo issue number. A PR belongs to it when its title is
# "<Label>: <n> - <Title>" (primary) or its branch is "<label>/<n>" (fallback).
#
# Reads owner, repo_prefix and token_env_file from config.local.yaml in the workspace root
# (override the path with PR_REVIEW_CONFIG). Local use only; in CI the PR is already known.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: find-pr.sh TICKET_NUMBER [--state open|closed|merged|all]

  TICKET_NUMBER  project-wide ticket number, e.g. 13
  --state        which PRs to search, default open

Prints one line per match, tab separated:
  <repo>#<pr>  <matched by: title|branch>  <branch>  <title>  <url>
Exits 0 with matches, 1 when none are found or on error.
EOF
}

die() { echo "error: $*" >&2; exit 1; }

NUMBER="" STATE="open"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --state) STATE="${2:?--state needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; die "unknown argument: $1" ;;
    *) [[ -z $NUMBER ]] || die "only one ticket number is allowed"; NUMBER="$1"; shift ;;
  esac
done
[[ $NUMBER =~ ^[0-9]+$ ]] || { usage >&2; die "TICKET_NUMBER must be a number"; }
[[ ${GITHUB_ACTIONS:-} != true ]] || die "find-pr.sh is for local use; in CI the PR is already known from the event"
case "$STATE" in open|closed|merged|all) ;; *) die "--state must be open, closed, merged or all" ;; esac

# ---- config -----------------------------------------------------------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONFIG="${PR_REVIEW_CONFIG:-$ROOT/config.local.yaml}"
[[ -f $CONFIG ]] || die "config not found: $CONFIG (copy config.example.yaml to config.local.yaml)"

# Top-level "key: value" lines only; strips surrounding quotes.
cfg() {
  awk -v k="$1" '
    index($0, k ":") == 1 {
      v = substr($0, length(k) + 2); sub(/^ +/, "", v); sub(/ +#.*$/, "", v)
      gsub(/^"|"$/, "", v); print v; exit
    }' "$CONFIG"
}

OWNER="$(cfg owner)"; PREFIX="$(cfg repo_prefix)"; TOKEN_FILE="$(cfg token_env_file)"
[[ -n $OWNER && -n $PREFIX ]] || die "config must set owner and repo_prefix"

if [[ -n $TOKEN_FILE ]]; then
  TOKEN_FILE="${TOKEN_FILE/#\~/$HOME}"
  [[ -f $TOKEN_FILE ]] || die "token_env_file not found: $TOKEN_FILE"
  # shellcheck disable=SC1090
  source "$TOKEN_FILE"
fi

command -v gh >/dev/null || die "gh (GitHub CLI) is not installed"
command -v jq >/dev/null || die "jq is not installed"

# ---- search -----------------------------------------------------------------------------
FOUND=0
while IFS= read -r repo; do
  [[ -n $repo ]] || continue
  PRS="$(gh pr list -R "$OWNER/$repo" --state "$STATE" --limit 200 \
    --json number,title,headRefName,url)" || die "could not list PRs of $OWNER/$repo"
  # Title "<Label>: <n> - <Title>" wins over the branch "<label>/<n>".
  MATCHES="$(jq -r --arg repo "$repo" --arg n "$NUMBER" '
    .[]
    | (if (.title | test("^[^:]+: " + $n + " - ")) then "title"
       elif (.headRefName | test("^[^/]+/" + $n + "$")) then "branch"
       else empty end) as $by
    | [$repo + "#" + (.number | tostring), $by, .headRefName, .title, .url] | @tsv' <<<"$PRS")"
  if [[ -n $MATCHES ]]; then echo "$MATCHES"; FOUND=1; fi
done < <(gh repo list "$OWNER" --limit 200 --json name --jq '.[].name' | awk -v p="$PREFIX" 'index($0, p) == 1')

[[ $FOUND -eq 1 ]] || { echo "no PR found for ticket $NUMBER (state: $STATE)" >&2; exit 1; }
