#!/usr/bin/env bash
# Hermetic contract for github-mcp-headers.sh: a stub `gh` stands in for the GitHub CLI, so no
# network and no real credential is used.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
helper="$here/github-mcp-headers.sh"
bash_bin=$(command -v bash)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/empty"

fail() { echo "FAIL: $*" >&2; exit 1; }

# A gh stub that prints the token in $STUB_TOKEN, or fails when STUB_FAIL is set, and records
# each call so a test can prove gh was or was not consulted.
cat > "$work/bin/gh" <<STUB
#!$bash_bin
printf '%s\n' "\$*" >> "$work/gh-calls"
[ -z "\${STUB_FAIL:-}" ] || exit 4
[ "\$*" = "auth token" ] || exit 2
printf '%s\n' "\$STUB_TOKEN"
STUB
chmod +x "$work/bin/gh"

run() { # expected-exit env-assignments...
  local expected=$1 status=0
  shift
  env -i HOME="$work" "$@" "$bash_bin" "$helper" > "$work/out" 2> "$work/err" || status=$?
  [ "$status" -eq "$expected" ] || fail "exit $status, expected $expected: $(cat "$work/err")"
}

# 1. The GitHub CLI login supplies the token; the output is exactly one Authorization header.
run 0 PATH="$work/bin" STUB_TOKEN=gho_cliToken123
jq -e '. == {"Authorization": "Bearer gho_cliToken123"}' "$work/out" > /dev/null || fail "gh token header: $(cat "$work/out")"

# 2. GITHUB_SECURITY_MCP_TOKEN wins, and gh is never consulted.
rm -f "$work/gh-calls"
run 0 PATH="$work/bin" STUB_TOKEN=gho_cliToken123 GITHUB_SECURITY_MCP_TOKEN=github_pat_Narrow_42
jq -e '. == {"Authorization": "Bearer github_pat_Narrow_42"}' "$work/out" > /dev/null || fail "override header: $(cat "$work/out")"
[ ! -e "$work/gh-calls" ] || fail "gh was called although GITHUB_SECURITY_MCP_TOKEN was set"

# 3. A failing GitHub CLI login yields no output and exit 1, never an empty bearer.
run 1 PATH="$work/bin" STUB_FAIL=1
[ ! -s "$work/out" ] || fail "printed output for a failed gh login"
grep -q 'gh auth login' "$work/err" || fail "failed login message does not name the fix"

# 4. No GitHub CLI on PATH and no override: no output, exit 1.
run 1 PATH="$work/empty"
[ ! -s "$work/out" ] || fail "printed output without any token source"

# 5. An empty token from gh is refused.
run 1 PATH="$work/bin" STUB_TOKEN=
[ ! -s "$work/out" ] || fail "printed output for an empty token"

# 6. A value that could break out of the JSON string is refused, from either source.
run 1 PATH="$work/bin" STUB_TOKEN='abc","X-Evil":"1'
[ ! -s "$work/out" ] || fail "printed output for a malformed gh token"
run 1 PATH="$work/empty" GITHUB_SECURITY_MCP_TOKEN='abc def'
[ ! -s "$work/out" ] || fail "printed output for a malformed override token"

printf 'github-mcp-headers: PASS\n'
