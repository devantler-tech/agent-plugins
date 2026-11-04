#!/usr/bin/env bash
# Hermetic contract for github-mcp-headers.sh: a stub `gh` stands in for the GitHub CLI, so no
# network and no real credential is used.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
helper="$here/github-mcp-headers.sh"
bash_bin=$(command -v bash)
work=$(mktemp -d)
trap 'chmod -R u+rwx "$work" 2> /dev/null || true; rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/empty" "$work/data" "$work/nodata"

fail() { echo "FAIL: $*" >&2; exit 1; }

# A gh stub that prints the token in $STUB_TOKEN, or fails when STUB_FAIL is set. It records each
# call so a test can prove gh was or was not consulted, and refuses any arguments except the one
# github.com token request.
cat > "$work/bin/gh" <<STUB
#!$bash_bin
printf '%s\n' "\$*" >> "$work/gh-calls"
[ -z "\${STUB_FAIL:-}" ] || exit 4
[ "\$*" = "auth token --hostname github.com" ] || exit 2
printf '%s\n' "\$STUB_TOKEN"
STUB
chmod +x "$work/bin/gh"

run() { # expected-exit helper-args... -- env-assignments...
  local expected=$1 status=0 args=()
  shift
  while [ $# -gt 0 ] && [ "$1" != -- ]; do args+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  rm -f "$work/gh-calls"
  env -i HOME="$work" "$@" "$bash_bin" "$helper" ${args[@]+"${args[@]}"} > "$work/out" 2> "$work/err" ||
    status=$?
  [ "$status" -eq "$expected" ] || fail "exit $status, expected $expected: $(cat "$work/err")"
}

# The output is exactly one JSON object, the Authorization header for the token, and the token is
# never written to stderr.
expect_header() { # token description
  jq -se --arg auth "Bearer $1" 'length == 1 and .[0] == {"Authorization": $auth}' "$work/out" \
    > /dev/null || fail "$2: $(cat "$work/out")"
  ! grep -qF "$1" "$work/err" || fail "$2: the token appeared on stderr"
}

# 1. The GitHub CLI's github.com login supplies the token when no data directory is given.
run 0 -- PATH="$work/bin" STUB_TOKEN=gho_cliToken123
expect_header gho_cliToken123 "gh token header"
[ "$(cat "$work/gh-calls")" = "auth token --hostname github.com" ] ||
  fail "gh was not asked for exactly the github.com token: $(cat "$work/gh-calls")"

# 2. A github-token file in the data directory wins, and gh is never consulted.
printf 'github_pat_Narrow_42\n' > "$work/data/github-token"
run 0 "$work/data" -- PATH="$work/bin" STUB_TOKEN=gho_cliToken123
expect_header github_pat_Narrow_42 "token file header"
[ ! -e "$work/gh-calls" ] || fail "gh was called although the token file exists"

# 3. A data directory without the file falls back to the github.com login.
run 0 "$work/nodata" -- PATH="$work/bin" STUB_TOKEN=gho_cliToken123
expect_header gho_cliToken123 "fallback header"

# 4. A credential-named variable is never read: Claude Code strips those from a plugin helper, so
#    relying on one would silently send the broader login instead.
run 0 -- PATH="$work/bin" STUB_TOKEN=gho_cliToken123 GITHUB_SECURITY_MCP_TOKEN=github_pat_Ignored_1
expect_header gho_cliToken123 "credential variable ignored"

# 5. A failing GitHub CLI login yields no output and exit 1, never an empty bearer.
run 1 -- PATH="$work/bin" STUB_FAIL=1
[ ! -s "$work/out" ] || fail "printed output for a failed gh login"
grep -q 'gh auth login --hostname github.com' "$work/err" || fail "failed login message does not name the fix"

# 6. No GitHub CLI on PATH and no token file: no output, exit 1.
run 1 "$work/nodata" -- PATH="$work/empty"
[ ! -s "$work/out" ] || fail "printed output without any token source"

# 7. An empty token, from gh or from the file, is refused.
run 1 -- PATH="$work/bin" STUB_TOKEN=
[ ! -s "$work/out" ] || fail "printed output for an empty gh token"
: > "$work/data/github-token"
run 1 "$work/data" -- PATH="$work/empty"
[ ! -s "$work/out" ] || fail "printed output for an empty token file"

# 8. A value that could break out of the JSON string is refused, from either source.
run 1 -- PATH="$work/bin" STUB_TOKEN='abc","X-Evil":"1'
[ ! -s "$work/out" ] || fail "printed output for a malformed gh token"
printf 'abc def\n' > "$work/data/github-token"
run 1 "$work/data" -- PATH="$work/empty"
[ ! -s "$work/out" ] || fail "printed output for a malformed token file"

# 9. An unreadable token file is a failure, not a silent fallback to the broader login.
if [ "$(id -u)" -ne 0 ]; then
  printf 'github_pat_Narrow_42\n' > "$work/data/github-token"
  chmod 000 "$work/data/github-token"
  run 1 "$work/data" -- PATH="$work/bin" STUB_TOKEN=gho_cliToken123
  [ ! -s "$work/out" ] || fail "printed output for an unreadable token file"
  [ ! -e "$work/gh-calls" ] || fail "fell back to gh for an unreadable token file"
  chmod 600 "$work/data/github-token"
fi

# 10. More than one argument is a usage error.
run 2 "$work/data" extra -- PATH="$work/bin" STUB_TOKEN=gho_cliToken123
[ ! -s "$work/out" ] || fail "printed output for a usage error"

printf 'github-mcp-headers: PASS\n'
