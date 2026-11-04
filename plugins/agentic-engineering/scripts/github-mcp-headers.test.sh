#!/usr/bin/env bash
# Hermetic contract for github-mcp-headers.sh: a stub `gh` stands in for the GitHub CLI, so no
# network and no real credential is used.
#
# The stub tokens are deliberately not shaped like GitHub tokens (no `gho_`, `ghp_` or
# `github_pat_` prefix). The helper accepts any token of letters, digits and underscores, so the
# shape proves nothing here, while a realistic one makes secret scanners, the Claude plugin
# directory's among them, report this shipped file as holding a secret.
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
run 0 -- PATH="$work/bin" STUB_TOKEN=stubCliLoginToken
expect_header stubCliLoginToken "gh token header"
[ "$(cat "$work/gh-calls")" = "auth token --hostname github.com" ] ||
  fail "gh was not asked for exactly the github.com token: $(cat "$work/gh-calls")"

# 2. A github-token file in the data directory wins, and gh is never consulted.
printf 'stubNarrowFileToken\n' > "$work/data/github-token"
run 0 "$work/data" -- PATH="$work/bin" STUB_TOKEN=stubCliLoginToken
expect_header stubNarrowFileToken "token file header"
[ ! -e "$work/gh-calls" ] || fail "gh was called although the token file exists"

# 3. A data directory without the file falls back to the github.com login.
run 0 "$work/nodata" -- PATH="$work/bin" STUB_TOKEN=stubCliLoginToken
expect_header stubCliLoginToken "fallback header"

# 4. A credential-named variable is never read: Claude Code strips those from a plugin helper, so
#    relying on one would silently send the broader login instead.
run 0 -- PATH="$work/bin" STUB_TOKEN=stubCliLoginToken GITHUB_SECURITY_MCP_TOKEN=stubIgnoredEnvToken
expect_header stubCliLoginToken "credential variable ignored"

# 5. A failing GitHub CLI login yields no output and exit 1, never an empty bearer.
run 1 -- PATH="$work/bin" STUB_FAIL=1
[ ! -s "$work/out" ] || fail "printed output for a failed gh login"
grep -q 'gh auth login --hostname github.com' "$work/err" || fail "failed login message does not name the fix"

# 6. No GitHub CLI on PATH and no token file: no output, exit 1.
run 1 "$work/nodata" -- PATH="$work/empty"
[ ! -s "$work/out" ] || fail "printed output without any token source"

# A configured token file that cannot be used must fail without consulting gh, so a working gh is
# on PATH for these cases: a helper that fell back to it would exit 0 and be caught.
refused_without_fallback() { # description helper-arg
  run 1 "$2" -- PATH="$work/bin" STUB_TOKEN=stubCliLoginToken
  [ ! -s "$work/out" ] || fail "printed output for $1"
  [ ! -e "$work/gh-calls" ] || fail "fell back to gh for $1"
}

# 7. An empty token, from gh or from the file, is refused.
run 1 -- PATH="$work/bin" STUB_TOKEN=
[ ! -s "$work/out" ] || fail "printed output for an empty gh token"
: > "$work/data/github-token"
refused_without_fallback "an empty token file" "$work/data"

# 8. A value that could break out of the JSON string is refused, from either source.
run 1 -- PATH="$work/bin" STUB_TOKEN='abc","X-Evil":"1'
[ ! -s "$work/out" ] || fail "printed output for a malformed gh token"
printf 'abc def\n' > "$work/data/github-token"
refused_without_fallback "a malformed token file" "$work/data"

# 8a. A token file that is a dangling symlink, as for a secret on an unmounted volume, is a
#     configured token that cannot be read, never a reason to fall back.
rm -f "$work/data/github-token"
ln -s "$work/missing/github-token" "$work/data/github-token"
refused_without_fallback "a dangling token-file symlink" "$work/data"
rm -f "$work/data/github-token"

# 8b. A data-directory argument that is not a directory fails closed.
printf 'not a directory\n' > "$work/notadir"
refused_without_fallback "a data path that is not a directory" "$work/notadir"

# 9. An unreadable token file is a failure, not a silent fallback to the broader login.
if [ "$(id -u)" -ne 0 ]; then
  printf 'stubNarrowFileToken\n' > "$work/data/github-token"
  chmod 000 "$work/data/github-token"
  run 1 "$work/data" -- PATH="$work/bin" STUB_TOKEN=stubCliLoginToken
  [ ! -s "$work/out" ] || fail "printed output for an unreadable token file"
  [ ! -e "$work/gh-calls" ] || fail "fell back to gh for an unreadable token file"
  chmod 600 "$work/data/github-token"
  # 9a. A data directory that cannot be searched hides the token file, so it fails closed.
  mkdir -p "$work/locked"
  printf 'stubNarrowFileToken\n' > "$work/locked/github-token"
  chmod 600 "$work/locked"
  refused_without_fallback "an unsearchable data directory" "$work/locked"
  chmod 700 "$work/locked"
fi

# 10. More than one argument is a usage error.
run 2 "$work/data" extra -- PATH="$work/bin" STUB_TOKEN=stubCliLoginToken
[ ! -s "$work/out" ] || fail "printed output for a usage error"

# 11. The two servers this helper signs in keep their limits. github's exclusions remove the
#     tools that bypass a consumer's command-line rules; GitHub offers some of them only to some
#     clients (delete_repository needs MCP 2026-07-28 with elicitation), so a probe cannot stand in
#     for this list. github-ghas-tools stays read-only on its own URL, which Claude Code needs to
#     load both servers.
servers_keep_limits() { # mcp-json
  jq -e '
    def excluded: (.mcpServers.github.headers["X-MCP-Exclude-Tools"] // "") | split(",");
    ["merge_pull_request", "update_pull_request", "pull_request_review_write",
     "add_comment_to_pending_review", "update_pull_request_branch", "create_repository",
     "fork_repository", "delete_repository", "push_files", "create_or_update_file",
     "delete_file", "actions_run_trigger"] - excluded == [] and
    .mcpServers.github.url == "https://api.githubcopilot.com/mcp/" and
    .mcpServers["github-ghas-tools"].url == "https://api.githubcopilot.com/mcp/readonly" and
    .mcpServers["github-ghas-tools"].headers["X-MCP-Readonly"] == "true" and
    .mcpServers["github-ghas-tools"].headers["X-MCP-Toolsets"] ==
      "code_security,secret_protection,security_advisories,dependabot" and
    ([.mcpServers.github.headersHelper, .mcpServers["github-ghas-tools"].headersHelper] |
      all(. == "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/github-mcp-headers.sh\" \"${CLAUDE_PLUGIN_DATA}\""))
  ' "$1" > /dev/null
}
mcp_json="$here/../.mcp.json"
servers_keep_limits "$mcp_json" || fail "the bundled GitHub servers lost a limit in .mcp.json"
jq '.mcpServers.github.headers["X-MCP-Exclude-Tools"] |= (split(",") - ["delete_repository"] | join(","))' \
  "$mcp_json" > "$work/fewer-exclusions.json"
if servers_keep_limits "$work/fewer-exclusions.json"; then fail "accepted github without delete_repository excluded"; fi
jq '.mcpServers["github-ghas-tools"].url = "https://api.githubcopilot.com/mcp/"' \
  "$mcp_json" > "$work/shared-url.json"
if servers_keep_limits "$work/shared-url.json"; then fail "accepted github-ghas-tools on github's URL"; fi

printf 'github-mcp-headers: PASS\n'
