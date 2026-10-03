#!/usr/bin/env bash
# Exercise the actual package gate with complete portable fixtures and declared resource paths.
set -euo pipefail
here=${PACKAGE_SOURCE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0
# Build matching manifests, a sourced skill, and a complete catalogue.
fixture() {
  local root=$1
  mkdir -p "$root/.github/plugin" "$root/.claude-plugin" "$root/scripts" "$root/docs" "$root/plugins/alpha/.claude-plugin" "$root/plugins/alpha/skills/example"
  printf '%s\n' '{"name":"fixture","renames":{"old-alpha":"alpha"},"plugins":[{"name":"alpha","description":"Alpha","version":"1.0.0","source":"./plugins/alpha"}]}' > "$root/.claude-plugin/marketplace.json"
  cp "$root/.claude-plugin/marketplace.json" "$root/.github/plugin/marketplace.json"
  printf '%s\n' '{"old-alpha":"alpha"}' > "$root/scripts/marketplace-rename-history.json"
  printf '%s\n' '{"name":"alpha","description":"Alpha","version":"1.0.0"}' > "$root/plugins/alpha/plugin.json"
  printf '%s\n' '---' 'name: example' 'description: Example.' 'metadata:' '  github-repo: https://github.com/devantler-tech/agent-skills' '---' > "$root/plugins/alpha/skills/example/SKILL.md"
  # shellcheck disable=SC2016 # Literal catalogue markup.
  printf '| Plugin | Resources | Description |\n|---|---|---|\n| [`alpha`](plugins/alpha/) | `example` | Alpha |\n' > "$root/docs/plugins.md"
}
# Preserve the gate result and require its failure to identify the tested boundary.
gate() {
  local name=$1 expected=$2 root=$3 rc=0
  (cd "$root" && bash "$here/validate-manifests.sh") > "$root/out" 2>&1 || rc=$?
  if { [ "$expected" = pass ] && [ "$rc" -eq 0 ]; } ||
     { [ "$expected" = reject ] && [ "$rc" -ne 0 ] && grep -q '::error::' "$root/out"; }; then
    printf 'PASS %s\n' "$name"
  else printf 'FAIL %s exit=%s\n' "$name" "$rc"; cat "$root/out"; fail=$((fail+1)); fi
}
# Default discovery must apply the same packaged-resource fence as explicit paths.
for scenario in healthy linked-skill linked-agent linked-mcp linked-plugin linked-strict-plugin linked-marketplace linked-strict-parent incomplete-skill orphan-plugin description-backslash selected-agent selected-empty mcp-underscore mcp-dot mcp-unicode mcp-space mcp-backtick mcp-pipe; do
  root="$work/discovery-$scenario"; fixture "$root"
  p="$root/plugins/alpha/plugin.json"; m="$root/.claude-plugin/marketplace.json"
  case $scenario in
    linked-skill) mv "$root/plugins/alpha/skills/example/SKILL.md" "$root/outside.md"; printf 'body only\n' > "$root/outside.md"; ln -s "$root/outside.md" "$root/plugins/alpha/skills/example/SKILL.md" ;;
    linked-agent|selected-agent|selected-empty)
      mkdir "$root/plugins/alpha/agents"
      printf '%s\n' --- 'name: sample' 'description: Example.' --- > "$root/plugins/alpha/agents/sample.agent.md"
      if [ "$scenario" = linked-agent ]; then
        mv "$root/plugins/alpha/agents/sample.agent.md" "$root/outside.md"; ln -s "$root/outside.md" "$root/plugins/alpha/agents/sample.agent.md"
      else
        printf 'body only\n' > "$root/plugins/alpha/agents/unselected.md"
        value='["./agents/sample.agent.md"]'; [ "$scenario" != selected-empty ] || value='[]'
        jq --argjson v "$value" '.agents=$v' "$p" > "$root/new"; mv "$root/new" "$p"
      fi
      if [ "$scenario" != selected-empty ]; then
        # shellcheck disable=SC2016 # Literal catalogue markup.
        sed 's/`example` |/`example`, `sample` |/' "$root/docs/plugins.md" > "$root/new"; mv "$root/new" "$root/docs/plugins.md"
      fi ;;
    linked-mcp|mcp-*)
      case $scenario in mcp-underscore) key=test_mcp ;; mcp-dot) key=test.mcp ;; mcp-unicode) key=værktøj ;; mcp-space) key='test mcp' ;; mcp-backtick) key='test`mcp' ;; mcp-pipe) key='test|mcp' ;; *) key=test-mcp ;; esac
      jq -n --arg key "$key" '{mcpServers:{($key):{command:"tool"}}}' > "$root/plugins/alpha/.mcp.json"
      # shellcheck disable=SC2016 # Literal catalogue markup.
      printf '| Plugin | Resources | Description |\n|---|---|---|\n| [`alpha`](plugins/alpha/) | `example`, `%s` | Alpha |\n' "$key" > "$root/docs/plugins.md"
      if [ "$scenario" = linked-mcp ]; then mv "$root/plugins/alpha/.mcp.json" "$root/outside.json"; ln -s "$root/outside.json" "$root/plugins/alpha/.mcp.json"; fi ;;
    incomplete-skill)
      mkdir "$root/plugins/alpha/skills/incomplete"; printf 'not a skill\n' > "$root/plugins/alpha/skills/incomplete/README.md"
      # shellcheck disable=SC2016 # Literal catalogue markup.
      sed 's/`example` |/`example`, `incomplete` |/' "$root/docs/plugins.md" > "$root/new"; mv "$root/new" "$root/docs/plugins.md" ;;
    orphan-plugin) mkdir -p "$root/plugins/ghost/agents"; printf '%s\n' --- 'name: ghost' 'description: Example.' --- > "$root/plugins/ghost/agents/ghost.agent.md" ;;
    description-backslash)
      jq '.description="Use C:\\tools"' "$p" > "$root/new"; mv "$root/new" "$p"
      jq --slurpfile p "$p" '.plugins[0].description=$p[0].description' "$m" > "$root/new"; mv "$root/new" "$m" ;;
  esac
  cp "$p" "$root/plugins/alpha/.claude-plugin/plugin.json"; cp "$m" "$root/.github/plugin/marketplace.json"
  case $scenario in
    linked-plugin) mv "$p" "$root/outside.json"; ln -s "$root/outside.json" "$p" ;;
    linked-strict-plugin) path="$root/plugins/alpha/.claude-plugin/plugin.json"; mv "$path" "$root/outside.json"; ln -s "$root/outside.json" "$path" ;;
    linked-marketplace) mv "$m" "$root/outside.json"; ln -s "$root/outside.json" "$m" ;;
    linked-strict-parent) path="$root/plugins/alpha/.claude-plugin"; mv "$path" "$root/outside"; ln -s "$root/outside" "$path" ;;
  esac
  expected=reject
  case $scenario in healthy|description-backslash|selected-*|mcp-underscore|mcp-dot|mcp-unicode) expected=pass ;; esac
  gate "$scenario" "$expected" "$root"
done
# Ancillary non-agent files are not discovered or advertised as agent resources.
for scenario in listed ancillary; do
  root="$work/agent-token-$scenario"; fixture "$root"
  mkdir "$root/plugins/alpha/agents"
  printf '%s\n' --- 'name: sample' 'description: Example.' --- > "$root/plugins/alpha/agents/sample.agent.md"
  printf body > "$root/plugins/alpha/agents/invisible.txt"
  # shellcheck disable=SC2016 # Literal catalogue markup.
  extra=
  if [ "$scenario" = listed ]; then
    # shellcheck disable=SC2016 # Literal catalogue markup.
    extra=', `invisible.txt`'
  fi
  # shellcheck disable=SC2016 # Literal catalogue markup.
  printf '| Plugin | Resources | Description |\n|---|---|---|\n| [`alpha`](plugins/alpha/) | `example`, `sample`%s | Alpha |\n' "$extra" > "$root/docs/plugins.md"
  cp "$root/plugins/alpha/plugin.json" "$root/plugins/alpha/.claude-plugin/plugin.json"
  expected=pass; [ "$scenario" != listed ] || expected=reject
  gate "agent-token-$scenario" "$expected" "$root"
done
# Even exit-zero producers must supply complete NUL frames, never a hidden last member.
real_find=$(command -v find)
for kind in packages skills agents; do
  root="$work/unterminated-$kind"; fixture "$root"
  cp "$root/plugins/alpha/plugin.json" "$root/plugins/alpha/.claude-plugin/plugin.json"
  mkdir "$root/bin"
  cat > "$root/bin/find" <<'STUB'
#!/usr/bin/env bash
case "$FRAME_KIND:${1:-}:${2:-}" in
  packages:plugins:-mindepth) printf 'plugins/alpha\0plugins/ghost'; exit 0 ;;
  skills:plugins/alpha/skills:-mindepth) printf 'plugins/alpha/skills/example\0plugins/alpha/skills/incomplete'; exit 0 ;;
  agents:plugins/alpha/agents:-mindepth) printf 'plugins/alpha/agents/sample.agent.md\0plugins/alpha/agents/ghost.agent.md'; exit 0 ;;
esac
exec "$REAL_FIND" "$@"
STUB
  chmod +x "$root/bin/find"
  [ "$kind" != agents ] || mkdir "$root/plugins/alpha/agents"
  PATH="$root/bin:$PATH" REAL_FIND="$real_find" FRAME_KIND="$kind" gate "unterminated-$kind" reject "$root"
  grep -q 'Incomplete record' "$root/out" || { printf 'FAIL framing diagnostic %s\n' "$kind"; fail=$((fail+1)); }
done
printf 'package discovery: %s failures\n' "$fail"
test "$fail" -eq 0
