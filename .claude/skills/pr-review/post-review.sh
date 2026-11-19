#!/usr/bin/env bash
# Posts a finished review to a pull request as ONE GitHub review: a summary, one inline thread per
# finding that points at a file and line, and a verdict derived from the findings.
#
# This script only does the mechanical part. Deciding what the findings are, and how severe, is the
# reviewer's job (see SKILL.md). The verdict is never taken from the review file; it is derived:
#   any blocking finding                          -> REQUEST_CHANGES
#   only non-blocking findings                    -> COMMENT
#   no findings, but open threads on the PR       -> COMMENT
#   no findings and no open threads               -> APPROVE
# So the bot approves only when nothing is left open, blocking or not. "Open" means unresolved, or
# started by this account and resolved by somebody else (the author cannot lift the block alone).
#
# Two modes, chosen by GitHub Actions' own GITHUB_ACTIONS variable:
#   local: reads owner, repo_prefix and token_env_file from config.local.yaml in the workspace root
#          (override the path with PR_REVIEW_CONFIG); the token file holds the reviewer's (bot's) token.
#   CI:    reads PR_REVIEW_OWNER (default GITHUB_REPOSITORY_OWNER), PR_REVIEW_PREFIX and GH_TOKEN
#          (the reviewer's token, passed by the workflow) from the environment; reads no files;
#          always posts, --dry-run is refused.
# The review is posted as whoever the token belongs to.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: post-review.sh --pr OWNER/REPO#N --review-file FILE --model MODEL [--dry-run]

  --pr           the pull request to review, e.g. andreas-papadakis/banking-ai-assistant#24
  --review-file  JSON file with the finished review (format below)
  --model        name of the model that wrote the review, used in the footer
  --dry-run      validate everything and print what would be posted, without posting

Review file:
  {
    "head_sha": "<40-char commit the review was made on>",
    "summary":  "markdown summary of the review",
    "findings": [
      {"severity": "blocking" | "non-blocking",
       "file": "path/in/repo", "line": 12,      <- both or neither
       "body": "what is wrong, why it matters, how to fix it"}
    ]
  }

A finding with file and line becomes an inline thread; one without goes into the review body.
Refused (nothing is posted) when: the file is invalid; the text looks like it contains a secret;
the PR is closed, has new commits since head_sha, or is authored by the account that would post;
or this commit was already reviewed by this account.
EOF
}

die() { echo "error: $*" >&2; exit 1; }

PR="" REVIEW_FILE="" MODEL="" DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:?--pr needs a value}"; shift 2 ;;
    --review-file) REVIEW_FILE="${2:?--review-file needs a value}"; shift 2 ;;
    --model) MODEL="${2:?--model needs a value}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done
[[ -n $PR && -n $REVIEW_FILE && -n $MODEL ]] || { usage >&2; die "--pr, --review-file and --model are required"; }
[[ $PR =~ ^([^/]+)/([^#]+)#([0-9]+)$ ]] || die "--pr must look like OWNER/REPO#N"
P_OWNER="${BASH_REMATCH[1]}"; P_REPO="${BASH_REMATCH[2]}"; P_NUM="${BASH_REMATCH[3]}"
[[ -f $REVIEW_FILE ]] || die "review file not found: $REVIEW_FILE"
# Two explicit modes, decided by GitHub Actions' own variable, never guessed from what files exist.
# In CI a review is always posted, so a workflow cannot end up with a checked-but-unsent review.
if [[ ${GITHUB_ACTIONS:-} == true && $DRY_RUN -eq 1 ]]; then die "--dry-run is not allowed in CI: a review there is always posted"; fi

command -v jq >/dev/null || die "jq is not installed"
command -v gh >/dev/null || die "gh (GitHub CLI) is not installed"

# ---- validate the review file (no network yet) -------------------------------------------
jq -e '
  type == "object" and
  (.head_sha | type == "string" and test("^[0-9a-f]{40}$")) and
  (.summary | type == "string" and length > 0 and length <= 8000) and
  (.findings | type == "array" and length <= 50) and
  (.findings | all(.[];
    type == "object" and
    (.severity == "blocking" or .severity == "non-blocking") and
    (.body | type == "string" and length > 0 and length <= 4000) and
    (has("file") == has("line")) and
    ((has("file") | not) or (.file | type == "string" and length > 0)) and
    ((has("line") | not) or (.line | type == "number" and . == floor and . >= 1))
  ))' "$REVIEW_FILE" >/dev/null 2>&1 \
  || die "invalid review file (see --help for the format; head_sha, summary, findings, severity, body, file+line)"

HEAD_SHA="$(jq -r '.head_sha' "$REVIEW_FILE")"

# ---- refuse text that looks like a secret; never print the match -------------------------
REVIEW_TEXT="$(jq -r '.summary, (.findings[].body)' "$REVIEW_FILE")"
scan() { # name, extended regex
  if grep -Eq -- "$2" <<<"$REVIEW_TEXT"; then
    die "the review text contains something that looks like a $1; remove the value (name the file and line only) and try again"
  fi
}
scan "GitHub token"      'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'
scan "API key"           'sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}'
scan "private key"       '-----BEGIN [A-Z ]*PRIVATE KEY-----'
scan "JWT"               'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.'

# ---- config and token --------------------------------------------------------------------
if [[ ${GITHUB_ACTIONS:-} == true ]]; then
  # CI mode: everything comes from the workflow's environment; no config or token file is read.
  OWNER="${PR_REVIEW_OWNER:-${GITHUB_REPOSITORY_OWNER:-}}"; PREFIX="${PR_REVIEW_PREFIX:-}"; TOKEN_FILE=""
  [[ -n $OWNER ]] || die "CI mode: set PR_REVIEW_OWNER (or run in a workflow that provides GITHUB_REPOSITORY_OWNER)"
  [[ -n $PREFIX ]] || die "CI mode: set PR_REVIEW_PREFIX (the repo name prefix, e.g. banking-)"
  [[ -n ${GH_TOKEN:-} ]] || die "CI mode: GH_TOKEN is not set; the workflow must pass the reviewer's token"
else
  # Local mode: config.local.yaml is required.
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
fi
[[ $P_OWNER == "$OWNER" ]] || die "PR owner \"$P_OWNER\" does not match the configured owner \"$OWNER\""
case "$P_REPO" in "$PREFIX"*) ;; *) die "repo \"$P_REPO\" does not start with the configured prefix \"$PREFIX\"" ;; esac

if [[ -n $TOKEN_FILE ]]; then
  TOKEN_FILE="${TOKEN_FILE/#\~/$HOME}"
  [[ -f $TOKEN_FILE ]] || die "token_env_file not found: $TOKEN_FILE"
  # shellcheck disable=SC1090
  source "$TOKEN_FILE"
fi

# The review text must not contain the token in use either.
if [[ -n ${GH_TOKEN:-} ]] && grep -qF -- "$GH_TOKEN" <<<"$REVIEW_TEXT"; then
  die "the review text contains the token in use; remove it and try again"
fi

# ---- checks against the PR (read-only) ---------------------------------------------------
ME="$(gh api user --jq .login)" || die "could not identify the account behind the token"
[[ $ME != *"[bot]" ]] || die "the token belongs to $ME; approvals from GitHub's built-in bot accounts do not count as required reviews, pass the reviewer's own token"
PR_JSON="$(gh api "repos/$P_OWNER/$P_REPO/pulls/$P_NUM")" || die "PR not found: $PR"
PR_STATE="$(jq -r '.state' <<<"$PR_JSON")"
PR_HEAD="$(jq -r '.head.sha' <<<"$PR_JSON")"
PR_AUTHOR="$(jq -r '.user.login' <<<"$PR_JSON")"

[[ $PR_STATE == open ]] || die "$PR is $PR_STATE; only open PRs can be reviewed"
[[ $PR_HEAD == "$HEAD_SHA" ]] || die "$PR has new commits since the review (reviewed ${HEAD_SHA:0:7}, now ${PR_HEAD:0:7}); review again"
[[ $PR_AUTHOR != "$ME" ]] || die "$ME authored $PR; GitHub does not allow reviewing your own PR (is the token file the reviewer's?)"

MARKER="<!-- pr-review:$HEAD_SHA -->"
ALREADY="$(gh api --paginate "repos/$P_OWNER/$P_REPO/pulls/$P_NUM/reviews" \
  | jq -r --arg me "$ME" --arg m "$MARKER" '.[] | select(.user.login == $me and (.body // "" | contains($m))) | .id' | head -n 1)"
[[ -z $ALREADY ]] || die "$ME already reviewed commit ${HEAD_SHA:0:7} of $PR (review $ALREADY); push a new commit or reply in the threads instead"

THREADS_QUERY='query($o:String!,$r:String!,$n:Int!,$endCursor:String){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{isResolved resolvedBy{login} comments(first:1){nodes{author{login}}}}}}}}'
# A thread is open when it is unresolved, or when this account started it and somebody else resolved it:
# a thread the PR author resolves alone does not lift the block; only the reviewer's own resolve does.
OPEN_THREADS="$(gh api graphql --paginate -f query="$THREADS_QUERY" -f o="$P_OWNER" -f r="$P_REPO" -F n="$P_NUM" \
  | jq -s --arg me "$ME" '[.[].data.repository.pullRequest.reviewThreads.nodes[]
      | select((.isResolved | not)
               or (((.comments.nodes[0].author.login // "") == $me) and ((.resolvedBy.login // "") != $me)))] | length')"
[[ $OPEN_THREADS =~ ^[0-9]+$ ]] || die "could not read the review threads of $PR"

# ---- derive the verdict ------------------------------------------------------------------
BLOCKING="$(jq '[.findings[] | select(.severity == "blocking")] | length' "$REVIEW_FILE")"
TOTAL="$(jq '.findings | length' "$REVIEW_FILE")"
if (( BLOCKING > 0 )); then EVENT=REQUEST_CHANGES; WANT_STATE=CHANGES_REQUESTED
elif (( TOTAL > 0 || OPEN_THREADS > 0 )); then EVENT=COMMENT; WANT_STATE=COMMENTED
else EVENT=APPROVE; WANT_STATE=APPROVED
fi

# ---- build the payload -------------------------------------------------------------------
GENERAL="$(jq -r '[.findings[] | select(has("file") | not)]
  | map("- **" + (if .severity == "blocking" then "Blocking" else "Non-blocking" end) + ":** " + .body) | join("\n")' "$REVIEW_FILE")"
case "$EVENT" in
  REQUEST_CHANGES) VERDICT_LINE="**Changes requested:** $BLOCKING blocking finding(s) must be fixed." ;;
  COMMENT) VERDICT_LINE="**Not approved yet:** $TOTAL new finding(s) and $OPEN_THREADS open thread(s) on this PR; every thread must be answered and resolved by the reviewer first." ;;
  APPROVE) VERDICT_LINE="**Approved:** no findings and no open threads." ;;
esac
BODY="$(jq -r '.summary' "$REVIEW_FILE")"
if [[ -n $GENERAL ]]; then BODY+=$'\n\n### Findings without a line\n'"$GENERAL"; fi
BODY+=$'\n\n'"$VERDICT_LINE"
BODY+=$'\n\n---\n🤖 Reviewed by [Claude Code](https://claude.com/claude-code) ('"$MODEL"$')\n'"$MARKER"

PAYLOAD="$(mktemp)"; trap 'rm -f "$PAYLOAD"' EXIT
jq --arg sha "$HEAD_SHA" --arg event "$EVENT" --arg body "$BODY" '{
    commit_id: $sha, event: $event, body: $body,
    comments: [.findings[] | select(has("file")) | {
      path: .file, line: .line, side: "RIGHT",
      body: ((if .severity == "blocking" then "**Blocking:** " else "**Non-blocking:** " end) + .body)
    }]
  }' "$REVIEW_FILE" >"$PAYLOAD"
THREADS="$(jq '.comments | length' "$PAYLOAD")"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "dry run, nothing posted"
  echo "would post to $PR as $ME: $EVENT ($BLOCKING blocking, $((TOTAL - BLOCKING)) non-blocking, $THREADS inline thread(s); $OPEN_THREADS open thread(s) already on the PR)"
  exit 0
fi

# ---- post (one atomic call: a bad file or line makes GitHub reject the whole review) -------
RESULT="$(gh api -X POST "repos/$P_OWNER/$P_REPO/pulls/$P_NUM/reviews" --input "$PAYLOAD")" \
  || die "GitHub rejected the review; nothing was posted (a finding's file or line is probably not part of the PR's diff)"
REVIEW_ID="$(jq -r '.id' <<<"$RESULT")"
REVIEW_URL="$(jq -r '.html_url' <<<"$RESULT")"
GOT_STATE="$(jq -r '.state' <<<"$RESULT")"
[[ $GOT_STATE == "$WANT_STATE" ]] || die "posted $REVIEW_URL but its state is $GOT_STATE, expected $WANT_STATE; check it by hand"

echo "posted: $REVIEW_URL"
echo "review: id $REVIEW_ID, state $GOT_STATE, $THREADS inline thread(s)"
