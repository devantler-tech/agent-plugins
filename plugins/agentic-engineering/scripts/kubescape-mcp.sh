#!/bin/sh
# Start the bundled `kubescape` MCP server (`kubescape mcpserver`). ../.mcp.json runs this file with
# `sh` as the server's command, and ../.codex-plugin/mcp.json runs it by its plugin-relative path,
# so a plugin directory's validator can read exactly what the plugin starts instead of an inline
# `sh -c` program it cannot follow.
#
# It resolves the kubeconfig the same way as ./flux-operator-mcp.sh, so both servers read the same
# clusters: KUBECONFIG is set to $HOME/.kube/config when the environment leaves it unset or empty,
# and any non-empty value passes through unchanged.
#
# Kubescape's scans otherwise send a version check to Kubescape's update service carrying a cluster
# ID, the node count, the frameworks scanned and the client version. This sets
# KS_SKIP_UPDATE_CHECK=true when the environment leaves it unset or empty, so the agents' scans send
# none; set it yourself to choose otherwise.
#
# The server speaks MCP over stdin and stdout, so this script writes nothing to stdout itself and
# replaces itself with the server. It is POSIX sh, run by `sh`, which reads no BASH_ENV file that
# could print onto that stream first.
#
# Usage: kubescape-mcp.sh   (no arguments)
# Exit codes: the server's own; 1 neither KUBECONFIG nor HOME is set; 2 usage error; 127 the
# kubescape binary is not on PATH.
set -eu

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

if [ -z "${KS_SKIP_UPDATE_CHECK:-}" ]; then
  KS_SKIP_UPDATE_CHECK=true
fi
export KS_SKIP_UPDATE_CHECK

exec kubescape mcpserver
