#!/usr/bin/env bash
# Print the Authorization header Claude Code sends to the bundled Coroot MCP server.
#
# Claude Code runs this as the `headersHelper` of `coroot` in ../.mcp.json on every connection
# and merges its output into the request headers. Coroot's /mcp endpoint needs a bearer token on
# every request: for an agent that cannot complete Coroot's browser sign-in, that is the API key
# of a Coroot service account, ideally one with the Viewer role.
#
# Two files in the plugin data directory, passed as the first argument, hold the setup:
#   coroot-url      the Coroot address the key may go to, without /mcp: https://, or plain
#                   http:// only to localhost, 127.0.0.1 or [::1]
#   coroot-api-key  the API key
# The server's URL comes from COROOT_URL, which anything that sets Claude Code's environment can
# change. So the helper sends the key only when Claude Code reports, in CLAUDE_CODE_MCP_SERVER_URL,
# that it is connecting to exactly the pinned address followed by /mcp. That stops a changed
# COROOT_URL; it cannot stop someone who controls the whole environment, for example a proxy
# variable plus a trusted CA.
#
# Claude Code runs a plugin's helper without any environment variable whose name looks like a
# credential, and this helper has no fallback: when anything is missing or does not match, it
# prints nothing and exits 1, so Claude Code reports a failed helper instead of sending an empty
# credential. It prints one JSON object and nothing else, and never writes the key to stderr.
#
# Usage: coroot-mcp-headers.sh <plugin-data-dir>
# Exit codes: 0 header printed, 1 refused, 2 usage error.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo 'usage: coroot-mcp-headers.sh <plugin-data-dir>' >&2
  exit 2
fi
if [ -z "$1" ]; then
  echo 'coroot-mcp-headers: no plugin data directory was given' >&2
  exit 1
fi
if ! { [ -d "$1" ] && [ -x "$1" ]; }; then
  echo 'coroot-mcp-headers: cannot search the plugin data directory' >&2
  exit 1
fi

# read_exact <file> <pattern>: print the file's one line when the whole file is that line,
# optionally followed by one newline, and the line matches the pattern. The byte count catches
# what command substitution drops silently: a NUL byte or extra trailing newlines.
read_exact() {
  local file="$1" pattern="$2" value size
  [ -f "$file" ] && [ -r "$file" ] && value=$(< "$file") || return 1
  [[ $value =~ $pattern ]] || return 1
  size=$(wc -c < "$file") || return 1
  size=$((size))
  if [ "$size" -ne "${#value}" ]; then
    [ "$size" -eq $((${#value} + 1)) ] || return 1
    [ "$(tail -c 1 -- "$file" | od -An -tx1 | tr -d ' ')" = 0a ] || return 1
  fi
  printf '%s' "$value"
}

# An origin and an optional path, with no trailing slash, query, fragment or user info.
url_pattern='^(https://[A-Za-z0-9.-]+|http://(localhost|127\.0\.0\.1|\[::1\]))(:[0-9]{1,5})?(/[A-Za-z0-9._~%-]+)*$'
if ! pinned=$(read_exact "$1/coroot-url" "$url_pattern"); then
  echo 'coroot-mcp-headers: no single https:// (or loopback http://) address in coroot-url' >&2
  exit 1
fi
if [ "${CLAUDE_CODE_MCP_SERVER_URL:-}" != "$pinned/mcp" ]; then
  echo 'coroot-mcp-headers: the server URL is not the address pinned in coroot-url followed by /mcp' >&2
  exit 1
fi

# One line of bearer-token characters (RFC 6750 b64token), so it can neither break the JSON nor
# smuggle a second header.
if ! key=$(read_exact "$1/coroot-api-key" '^[A-Za-z0-9._~+/-]+=*$'); then
  echo 'coroot-mcp-headers: coroot-api-key is not a single readable API key' >&2
  exit 1
fi
printf '{"Authorization":"Bearer %s"}\n' "$key"
