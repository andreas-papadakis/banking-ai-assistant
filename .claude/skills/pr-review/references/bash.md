# Shell scripts

## Blocking

- Missing `set -euo pipefail`, or arguments and config values used without validation.
- A script that **writes** (creates, edits, links, moves, deletes) without a `--dry-run` or without verifying what it wrote.
- Silent failure paths, or a failure that leaves a half-done state without telling the user what was already done.
- Temp files without `mktemp` and a cleanup `trap`, or predictable temp paths.
- Unquoted variables, `eval`, `bash -c` / `sh -c` on external input, `curl | sh`, command lines built by string concatenation from user input.
- `set -x` / `bash -x` anywhere a token or secret is in the environment.
- A secret on a command line (visible in the process list) or in output.
- Reading files outside what the script declares.

## Non-blocking

- Missing `--dry-run` on a script that only reads.
- Portability: must run on Git Bash (Windows), macOS and Linux. Watch GNU-only flags (`sed -i`, `date -d`, `readlink -f`, `grep -P`), `/dev/null` vs `NUL`, and path separators.
- Readability, naming, duplicated logic, comments that say what instead of why.
- Run `shellcheck` if available and report what it finds.
