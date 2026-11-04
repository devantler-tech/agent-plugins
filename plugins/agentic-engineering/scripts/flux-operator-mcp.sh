#!/usr/bin/env bash
# Start the bundled `flux-operator-mcp` server read-only. ../.mcp.json runs this file as the
# server's command, so a plugin directory's validator can read exactly what the plugin starts
# instead of an inline `sh -c` program it cannot follow.
#
# flux-operator-mcp refuses to start unless the KUBECONFIG environment variable is set. This sets
# it to $HOME/.kube/config when the environment leaves it unset or empty, and passes any
# non-empty value through unchanged. `--read-only` keeps the server from applying, deleting,
# reconciling, suspending or resuming anything.
#
# The server speaks MCP over stdin and stdout, so this script writes nothing to stdout itself and
# replaces itself with the server.
#
# Usage: flux-operator-mcp.sh   (no arguments)
# Exit codes: the server's own; 1 neither KUBECONFIG nor HOME is set; 2 usage error; 127 the
# flux-operator-mcp binary is not on PATH.
set -euo pipefail

if [ $# -gt 0 ]; then
  echo 'usage: flux-operator-mcp.sh' >&2
  exit 2
fi

if [ -z "${KUBECONFIG:-}" ]; then
  if [ -z "${HOME:-}" ]; then
    echo 'flux-operator-mcp: set KUBECONFIG or HOME' >&2
    exit 1
  fi
  KUBECONFIG="$HOME/.kube/config"
fi
export KUBECONFIG

exec flux-operator-mcp serve --read-only
