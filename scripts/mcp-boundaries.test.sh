#!/usr/bin/env bash
# Exercise the package gate, including healthy MCP definitions, without launching a server.
set -euo pipefail
here=${MCP_SOURCE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0
fixture() {
  local root=$1 resource=$2
  mkdir -p "$root/.github/plugin" "$root/.claude-plugin" "$root/scripts" "$root/docs" "$root/plugins/alpha/.claude-plugin" "$root/plugins/alpha/skills/example"
  printf '%s\n' '{"name":"fixture","renames":{"old-alpha":"alpha"},"plugins":[{"name":"alpha","description":"Alpha","version":"1.0.0","source":"./plugins/alpha"}]}' > "$root/.claude-plugin/marketplace.json"
  cp "$root/.claude-plugin/marketplace.json" "$root/.github/plugin/marketplace.json"
  printf '%s\n' '{"old-alpha":"alpha"}' > "$root/scripts/marketplace-rename-history.json"
  printf '%s\n' '{"name":"alpha","description":"Alpha","version":"1.0.0"}' > "$root/plugins/alpha/plugin.json"
  cp "$root/plugins/alpha/plugin.json" "$root/plugins/alpha/.claude-plugin/plugin.json"
  printf '%s\n' '---' 'name: example' 'description: Example.' 'metadata:' '  github-repo: https://github.com/devantler-tech/agent-skills' '---' > "$root/plugins/alpha/skills/example/SKILL.md"
  # shellcheck disable=SC2016 # Backticks are literal Markdown, not shell substitutions.
  printf '| Plugin | Resources | Description |\n|---|---|---|\n| [`alpha`](plugins/alpha/) | `example`, `%s` | Alpha |\n' "$resource" > "$root/docs/plugins.md"
}
check() {
  local name=$1 expected=$2 payload=$3 resource=${4:-test-mcp} root rc=0
  root="$work/$name"; fixture "$root" "$resource"
  printf '%s\n' "$payload" > "$root/plugins/alpha/.mcp.json"
  (cd "$root" && bash "$here/validate-manifests.sh") > "$root/out" 2>&1 || rc=$?
  if { [ "$expected" = pass ] && [ "$rc" -eq 0 ]; } ||
     { [ "$expected" = reject ] && [ "$rc" -ne 0 ] && grep -q '.mcp.json' "$root/out"; }; then
    printf 'PASS %s\n' "$name"
  else printf 'FAIL %s (exit=%s)\n' "$name" "$rc"; cat "$root/out"; fail=$((fail+1)); fi
}
# shellcheck disable=SC2016 # The gate must retain literal client variable references.
check stdio pass '{"mcpServers":{"test-mcp":{"command":"tool","args":["serve", ""],"env":{"EMPTY":"","KEY":"${KEY}"}}}}'
# shellcheck disable=SC2016 # This is client configuration data, never shell expansion.
check http pass '{"mcpServers":{"test-mcp":{"type":"http","url":"https://example.invalid/mcp","headers":{"Authorization":"Bearer ${TOKEN}"}}}}'
check sse pass '{"mcpServers":{"test-mcp":{"type":"sse","url":"https://example.invalid/events"}}}'
check explicit-stdio pass '{"mcpServers":{"test-mcp":{"type":"stdio","command":"tool","args":[],"env":{}}}}'
check server-array reject '{"mcpServers":[{"command":"tool"}]}' 0
check server-scalar reject '{"mcpServers":"tool"}'
check server-entry-array reject '{"mcpServers":{"test-mcp":["tool"]}}'
check nonstring-command reject '{"mcpServers":{"test-mcp":{"command":7}}}'
check blank-command reject '{"mcpServers":{"test-mcp":{"command":"  "}}}'
check nonstring-url reject '{"mcpServers":{"test-mcp":{"type":"http","url":7}}}'
check blank-url reject '{"mcpServers":{"test-mcp":{"type":"http","url":" "}}}'
check remote-missing-type reject '{"mcpServers":{"test-mcp":{"url":"https://example.invalid/mcp"}}}'
check conflicting-transport reject '{"mcpServers":{"test-mcp":{"type":"http","command":"tool"}}}'
check two-transports reject '{"mcpServers":{"test-mcp":{"command":"tool","url":"https://example.invalid/mcp"}}}'
check args-object reject '{"mcpServers":{"test-mcp":{"command":"tool","args":{"serve":true}}}}'
check args-nonstring reject '{"mcpServers":{"test-mcp":{"command":"tool","args":["serve",7]}}}'
check env-array reject '{"mcpServers":{"test-mcp":{"command":"tool","env":["KEY=value"]}}}'
check env-nonstring reject '{"mcpServers":{"test-mcp":{"command":"tool","env":{"KEY":true}}}}'
check headers-array reject '{"mcpServers":{"test-mcp":{"type":"http","url":"https://example.invalid/mcp","headers":["Authorization: value"]}}}'
check headers-nonstring reject '{"mcpServers":{"test-mcp":{"type":"http","url":"https://example.invalid/mcp","headers":{"Authorization":7}}}}'
check repeated-command reject '{"mcpServers":{"test-mcp":{"command":"other","command":"tool"}}}'
check repeated-server-container reject '{"mcpServers":{"test-mcp":{"command":"other"}},"mcpServers":{"test-mcp":{"command":"tool"}}}'
check repeated-empty-container reject '{"mcpServers":{"test-mcp":{"command":"tool","env":{},"env":{"KEY":"value"}}}}'
check escaped-repeated-key reject '{"mcpServers":{"test-mcp":{"command":"other","comm\u0061nd":"tool"}}}'
check multiple-documents reject '{"mcpServers":{"test-mcp":{"command":"tool"}}} {"mcpServers":{"test-mcp":{"command":"tool"}}}'
printf 'MCP boundaries: %s failure(s)\n' "$fail"
test "$fail" -eq 0
