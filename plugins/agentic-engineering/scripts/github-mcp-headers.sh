#!/usr/bin/env bash
# Print the Authorization header Claude Code sends to the bundled GitHub MCP servers.
#
# Claude Code runs this as the `headersHelper` of both `github` and `github-ghas-tools` in
# ../.mcp.json on every connection and merges its output into the request headers, so one token
# signs in to both. GitHub's remote MCP server points
# OAuth at github.com/login/oauth, which offers no dynamic client registration, so Claude Code
# cannot sign in to it on its own. GitHub Copilot and VS Code authenticate the server themselves
# and do not run this helper.
#
# Claude Code runs a plugin's helper without any environment variable whose name looks like a
# credential (TOKEN, SECRET, KEY, AUTH, ...), so the token never comes from the environment. It is
# the contents of `github-token` in the plugin data directory, passed as the first argument, when
# that file exists; that is where you put a narrowly scoped token, which then serves both servers.
# Otherwise it is the GitHub CLI's github.com login (`gh auth token --hostname github.com`), never
# another host's token. `github-ghas-tools` uses GitHub's read-only endpoint and also sends
# `X-MCP-Readonly`. `github` can write, except for the tools its `X-MCP-Exclude-Tools` header
# removes; what a token allows bounds both.
#
# The script prints one JSON object and nothing else, and never writes the token to stderr. When
# no usable token exists it prints nothing and exits 1, so Claude Code reports a failed helper
# instead of sending an empty credential.
#
# Usage: github-mcp-headers.sh [plugin-data-dir]
# Exit codes: 0 header printed, 1 no usable token, 2 usage error.
set -euo pipefail

if [ $# -gt 1 ]; then
  echo 'usage: github-mcp-headers.sh [plugin-data-dir]' >&2
  exit 2
fi

token_file=
if [ -n "${1:-}" ]; then
  # A data directory that exists but cannot be searched hides whether a token file is there, so
  # it fails closed rather than falling back to the broader login.
  if { [ -e "$1" ] || [ -L "$1" ]; } && ! { [ -d "$1" ] && [ -x "$1" ]; }; then
    echo 'github-mcp-headers: cannot search the plugin data directory' >&2
    exit 1
  fi
  token_file="$1/github-token"
fi

# A dangling symlink counts as a configured token file: it is a narrow token the user set up but
# cannot be read now, never a reason to send the broader login.
if [ -n "$token_file" ] && { [ -e "$token_file" ] || [ -L "$token_file" ]; }; then
  # Bash's own file read, so the helper needs nothing on PATH to read its token.
  if ! [ -f "$token_file" ] || ! [ -r "$token_file" ] || ! token=$(< "$token_file"); then
    echo 'github-mcp-headers: cannot read github-token in the plugin data directory' >&2
    exit 1
  fi
else
  if ! command -v gh > /dev/null 2>&1; then
    echo 'github-mcp-headers: install the GitHub CLI and run: gh auth login --hostname github.com' >&2
    exit 1
  fi
  if ! token=$(gh auth token --hostname github.com 2> /dev/null); then
    echo 'github-mcp-headers: the GitHub CLI has no github.com token; run: gh auth login --hostname github.com' >&2
    exit 1
  fi
fi

# GitHub tokens are letters, digits and underscores. Refuse anything else rather than build
# JSON from it.
if ! [[ $token =~ ^[A-Za-z0-9_]+$ ]]; then
  echo 'github-mcp-headers: the token is empty or is not a GitHub token' >&2
  exit 1
fi
printf '{"Authorization":"Bearer %s"}\n' "$token"
