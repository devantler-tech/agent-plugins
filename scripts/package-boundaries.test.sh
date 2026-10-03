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
for scenario in healthy unicode-description marketplace-name-number marketplace-name-blank duplicate-entries numeric-description blank-description numeric-version unstable-version leading-zero-version oversized-version component-number component-blank component-outside component-absolute component-missing component-wrong-kind component-valid-root component-valid-skill component-symlink component-root-symlink duplicate-marketplace duplicate-plugin duplicate-renames nested-duplicate escaped-duplicate multiple-objects plugin-parent-symlink; do
  root="$work/$scenario"; fixture "$root"
  m="$root/.claude-plugin/marketplace.json"; p="$root/plugins/alpha/plugin.json"
  case $scenario in
    marketplace-name-number) jq '.name=7' "$m" > "$root/new"; mv "$root/new" "$m" ;;
    marketplace-name-blank) jq '.name=" "' "$m" > "$root/new"; mv "$root/new" "$m" ;;
    duplicate-entries) jq '.plugins += [.plugins[0]]' "$m" > "$root/new"; mv "$root/new" "$m" ;;
    unicode-description|numeric-description|blank-description|numeric-version|unstable-version|leading-zero-version|oversized-version)
      case $scenario in unicode-description) expr='.description="Déploiement"' ;; numeric-description) expr='.description=7' ;; blank-description) expr='.description=" "' ;; numeric-version) expr='.version=7' ;; unstable-version) expr='.version="tomorrow"' ;; leading-zero-version) expr='.version="01.0.0"' ;; oversized-version) expr='.version="1000000000.0.0"' ;; esac
      jq "$expr" "$p" > "$root/new"; mv "$root/new" "$p"
      jq --slurpfile p "$p" '.plugins[0].description=$p[0].description | .plugins[0].version=$p[0].version' "$m" > "$root/new"; mv "$root/new" "$m" ;;
    component-*)
      case $scenario in component-number) value='[7]' ;; component-blank) value='[" "]' ;; component-outside) value='["../../outside"]' ;; component-absolute) value='["/tmp/outside"]' ;; component-missing) value='["./skills/absent"]' ;; component-wrong-kind) value='["./skills/example/SKILL.md"]' ;; component-valid-root) value='["./skills/"]' ;; component-valid-skill) value='["./skills/example/"]' ;; component-symlink|component-root-symlink) value='["./skills/link"]'; [ "$scenario" != component-root-symlink ] || value='["./skills/"]'; ln -s "$root/elsewhere" "$root/plugins/alpha/skills/link"; mkdir -p "$root/elsewhere"; cp "$root/plugins/alpha/skills/example/SKILL.md" "$root/elsewhere/SKILL.md" ;; esac
      jq --argjson v "$value" '.skills=$v' "$p" > "$root/new"; mv "$root/new" "$p" ;;
    duplicate-marketplace) jq -c . "$m" | sed 's/"name":"fixture"/"name":"other","name":"fixture"/' > "$root/new"; mv "$root/new" "$m" ;;
    duplicate-plugin) jq -c . "$p" | sed 's/"name":"alpha"/"name":"other","name":"alpha"/' > "$root/new"; mv "$root/new" "$p" ;;
    duplicate-renames) printf '%s\n' '{"old-alpha":null,"old-alpha":"alpha"}' > "$root/scripts/marketplace-rename-history.json" ;;
    nested-duplicate) jq -c . "$m" | sed 's/"old-alpha":"alpha"/"old-alpha":null,"old-alpha":"alpha"/' > "$root/new"; mv "$root/new" "$m" ;;
    escaped-duplicate) printf '%s\n' '{"name":"other","na\u006de":"alpha","description":"Alpha","version":"1.0.0"}' > "$p" ;;
    multiple-objects) cat "$m" "$m" > "$root/new"; mv "$root/new" "$m" ;;
  esac
  cp "$m" "$root/.github/plugin/marketplace.json"; cp "$p" "$root/plugins/alpha/.claude-plugin/plugin.json"
  if [ "$scenario" = plugin-parent-symlink ]; then
    mv "$root/plugins/alpha" "$root/elsewhere"; ln -s "$root/elsewhere" "$root/plugins/alpha"
  fi
  expected=reject
  case $scenario in healthy|unicode-description|component-valid-*) expected=pass ;; esac
  gate "$scenario" "$expected" "$root"
done
# Agent declarations select regular files from the canonical portable layout.
for scenario in valid number missing outside directory empty invalid-frontmatter; do
  root="$work/agent-$scenario"; fixture "$root"
  mkdir -p "$root/plugins/alpha/agents"
  printf '%s\n' '---' 'name: sample' 'description: Example agent.' '---' > "$root/plugins/alpha/agents/sample.agent.md"
  case $scenario in valid|invalid-frontmatter) value='["./agents/sample.agent.md"]' ;; number) value='[7]' ;; missing) value='["./agents/absent.agent.md"]' ;; outside) value='["../sample.agent.md"]' ;; directory) value='["./agents/"]' ;; empty) value='[]' ;; esac
  p="$root/plugins/alpha/plugin.json"
  jq --argjson v "$value" '.agents=$v' "$p" > "$root/new"; mv "$root/new" "$p"; cp "$p" "$root/plugins/alpha/.claude-plugin/plugin.json"
  if [ "$scenario" != empty ]; then
    # shellcheck disable=SC2016 # Backticks are literal catalogue markup.
    sed 's/`example` |/`example`, `sample` |/' "$root/docs/plugins.md" > "$root/new"; mv "$root/new" "$root/docs/plugins.md"
  fi
  [ "$scenario" != invalid-frontmatter ] || printf 'body only\n' > "$root/plugins/alpha/agents/sample.agent.md"
  expected=reject; case $scenario in valid|empty) expected=pass ;; esac
  gate "agent-$scenario" "$expected" "$root"
done
# The real desired-state fixture must be valid before ambiguity is introduced;
# otherwise another schema failure could mask the repeated protected declaration.
for scenario in healthy duplicate; do
  root="$work/desired-state-$scenario"; mkdir -p "$root"
  git -C "$here/.." archive HEAD > "$work/package.tar"
  tar -xf "$work/package.tar" -C "$root"
  resource="$root/plugins/agentic-engineering/resources/provider-neutral.desired-state.json"
  if [ "$scenario" = duplicate ]; then
    jq -c . "$resource" | sed 's/"spendStewardshipEnabled":false/"spendStewardshipEnabled":true,"spendStewardshipEnabled":false/' > "$root/new"
    mv "$root/new" "$resource"
  fi
  expected=pass; [ "$scenario" != duplicate ] || expected=reject
  gate "desired-state-$scenario" "$expected" "$root"
done
printf 'package boundaries: %s failure(s)\n' "$fail"
test "$fail" -eq 0
