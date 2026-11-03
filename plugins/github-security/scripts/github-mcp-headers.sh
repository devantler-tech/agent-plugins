#!/usr/bin/env bash
# Print the Authorization header Claude Code sends to the bundled GitHub security MCP server.
#
# Claude Code runs this as the `headersHelper` of `github-ghas-tools` in ../.mcp.json on every
# connection and merges its output into the request headers. GitHub's remote MCP server points
# OAuth at github.com/login/oauth, which offers no dynamic client registration, so Claude Code
# cannot sign in to it on its own. GitHub Copilot and VS Code authenticate the server themselves
# and do not run this helper.
#
# The token is GITHUB_SECURITY_MCP_TOKEN when that is set, which lets you supply a narrowly
# scoped token; otherwise it is the GitHub CLI login (`gh auth token`). Every tool the bundled
# toolsets expose is read-only. The script prints one JSON object and nothing else. When no usable
# token exists it prints nothing and exits 1, so Claude Code reports a failed helper instead of
# sending an empty credential.
#
# Usage: github-mcp-headers.sh   (no arguments)
# Exit codes: 0 header printed, 1 no usable token.
set -euo pipefail

token=${GITHUB_SECURITY_MCP_TOKEN:-}
if [ -z "$token" ]; then
  if ! command -v gh > /dev/null 2>&1; then
    echo 'github-mcp-headers: set GITHUB_SECURITY_MCP_TOKEN, or install the GitHub CLI and run: gh auth login' >&2
    exit 1
  fi
  if ! token=$(gh auth token 2> /dev/null); then
    echo 'github-mcp-headers: the GitHub CLI has no token; run: gh auth login' >&2
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
