#!/usr/bin/env bash
# Start the bundled `kubescape` MCP server (`kubescape mcpserver`). ../.mcp.json runs this file as
# the server's command, so a plugin directory's validator can read exactly what the plugin starts
# instead of an inline `sh -c` program it cannot follow.
#
# It resolves the kubeconfig the same way as ./flux-operator-mcp.sh, so both servers read the same
# clusters: KUBECONFIG is set to $HOME/.kube/config when the environment leaves it unset or empty,
# and any non-empty value passes through unchanged.
#
# The server speaks MCP over stdin and stdout, so this script writes nothing to stdout itself and
# replaces itself with the server.
#
# Usage: kubescape-mcp.sh   (no arguments)
# Exit codes: the server's own; 1 neither KUBECONFIG nor HOME is set; 2 usage error; 127 the
# kubescape binary is not on PATH.
set -euo pipefail

if [ $# -gt 0 ]; then
  echo 'usage: kubescape-mcp.sh' >&2
  exit 2
fi

if [ -z "${KUBECONFIG:-}" ]; then
  if [ -z "${HOME:-}" ]; then
    echo 'kubescape: set KUBECONFIG or HOME' >&2
    exit 1
  fi
  KUBECONFIG="$HOME/.kube/config"
fi
export KUBECONFIG

exec kubescape mcpserver
