#!/usr/bin/env bash
# Print the Authorization header Claude Code sends to the bundled Coroot MCP server.
#
# Claude Code runs this as the `headersHelper` of `coroot` in ../.mcp.json on every connection
# and merges its output into the request headers. Coroot's /mcp endpoint needs a bearer token on
# every request: for an agent that cannot complete Coroot's browser sign-in, that is the API key
# of a Coroot service account, ideally one with the Viewer role, which can investigate but cannot
# resolve alerts.
#
# The key is the contents of `coroot-api-key` in the plugin data directory, passed as the first
# argument. Claude Code runs a plugin's helper without any environment variable whose name looks
# like a credential, and this helper has no fallback: with no usable key file it prints nothing
# and exits 1, so Claude Code reports a failed helper instead of sending an empty credential. It
# prints one JSON object and nothing else, and never writes the key to stderr.
#
# Usage: coroot-mcp-headers.sh <plugin-data-dir>
# Exit codes: 0 header printed, 1 no usable key, 2 usage error.
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
key_file="$1/coroot-api-key"
if ! [ -f "$key_file" ] || ! [ -r "$key_file" ] || ! key=$(< "$key_file"); then
  echo 'coroot-mcp-headers: no readable coroot-api-key in the plugin data directory' >&2
  exit 1
fi
# One line of bearer-token characters (RFC 6750 b64token), so it can neither break the JSON nor
# smuggle a second header.
if ! [[ $key =~ ^[A-Za-z0-9._~+/-]+=*$ ]]; then
  echo 'coroot-mcp-headers: coroot-api-key is not a single API key' >&2
  exit 1
fi
printf '{"Authorization":"Bearer %s"}\n' "$key"
