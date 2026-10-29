# Shared helpers for the ticket scripts (.claude/scripts/*.sh and .claude/skills/*/*.sh).
# Source this file; do not run it. Sourcing only defines functions and sets TICKET_ROOT, so a
# script can source it first and still validate its arguments before loading the config.
# Must stay compatible with bash 3.2 (macOS /bin/bash).

# Repo root (where config.local.yaml lives), from this file's own location: .claude/scripts/ -> ../..
TICKET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "error: $*" >&2; exit 1; }

# Sets CONFIG to $TICKET_CONFIG, or config.local.yaml in the repo root, and fails if it is missing.
load_config() {
  CONFIG="${TICKET_CONFIG:-$TICKET_ROOT/config.local.yaml}"
  [[ -f $CONFIG ]] || die "config not found: $CONFIG (copy config.example.yaml to config.local.yaml)"
}

# Top-level "key: value" lines only; strips surrounding quotes. Needs load_config first.
cfg() {
  awk -v k="$1" '
    index($0, k ":") == 1 {
      v = substr($0, length(k) + 2); sub(/^ +/, "", v); sub(/ +#.*$/, "", v)
      gsub(/^"|"$/, "", v); print v; exit
    }' "$CONFIG"
}

# Sources the config's token_env_file, if set (it exports GH_TOKEN). Never prints the token.
source_token_file() {
  local token_file
  token_file="$(cfg token_env_file)"
  if [[ -n $token_file ]]; then
    token_file="${token_file/#\~/$HOME}"
    [[ -f $token_file ]] || die "token_env_file not found: $token_file"
    # shellcheck disable=SC1090
    source "$token_file"
  fi
}

# Prints the names of OWNER's repos that start with PREFIX, sorted, one per line.
# Fails if gh fails or no repo matches. Call as: REPOS="$(prefixed_repos "$OWNER" "$PREFIX")" || exit 1
prefixed_repos() { # owner, prefix
  local all repos
  all="$(gh repo list "$1" --limit 200 --json name --jq '.[].name')" || die "could not list the repos of $1"
  repos="$(awk -v p="$2" 'index($0, p) == 1' <<<"$all" | sort)"
  [[ -n $repos ]] || die "no repos starting with \"$2\" found for $1"
  printf '%s\n' "$repos"
}
