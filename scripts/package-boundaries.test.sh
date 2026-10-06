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
for scenario in healthy unicode-description marketplace-name-number marketplace-name-blank duplicate-entries numeric-description blank-description numeric-version unstable-version leading-zero-version oversized-version component-number component-blank component-outside component-absolute component-missing component-wrong-kind component-valid-root component-valid-skill component-symlink component-root-symlink component-nested-layout component-root-skill-layout duplicate-marketplace duplicate-plugin duplicate-renames nested-duplicate escaped-duplicate multiple-objects plugin-parent-symlink; do
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
    component-nested-layout)
      mkdir -p "$root/plugins/alpha/skills/container/nested"
      cp "$root/plugins/alpha/skills/example/SKILL.md" "$root/plugins/alpha/skills/container/nested/SKILL.md"
      jq '.skills=["./skills/container/"]' "$p" > "$root/new"; mv "$root/new" "$p"
      # shellcheck disable=SC2016 # Backticks are literal catalogue markup.
      sed 's/`example` |/`example`, `container` |/' "$root/docs/plugins.md" > "$root/new"; mv "$root/new" "$root/docs/plugins.md" ;;
    component-root-skill-layout)
      cp "$root/plugins/alpha/skills/example/SKILL.md" "$root/plugins/alpha/skills/SKILL.md"
      jq '.skills=["./skills/"]' "$p" > "$root/new"; mv "$root/new" "$p" ;;
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
# Identity text must be usable YAML, rather than merely a nonempty encoded value.
# Each case runs through the complete gate with both supported identity fields.
for field in name description; do
  for scenario in plain quoted-colon plain-colon leading-dash leading-question leading-colon \
    leading-percent leading-at leading-backtick leading-bracket leading-brace leading-comma \
    trailing-colon safe-colon safe-dash safe-question safe-leading-colon unicode-colon unicode-dash \
    unicode-question unicode-leading-indicator unicode-trailing-colon valid-strip valid-keep valid-strip-first valid-inferred valid-empty-lines \
    valid-leading-blank valid-explicit-tab-blank valid-explicit-tab-content valid-later-tab \
    valid-explicit-more-indent valid-large-indent block-double-plus block-double-minus block-zero \
    block-double-digit block-plus-minus block-minus-plus block-small-indent block-dedent \
    block-oversized-leading-blank block-leading-tab block-leading-tab-content block-small-tab-indent \
    block-continued-after-comment; do
    root="$work/yaml-$field-$scenario"; fixture "$root"
    cp "$root/plugins/alpha/plugin.json" "$root/plugins/alpha/.claude-plugin/plugin.json"
    mkdir -p "$root/plugins/alpha/agents"
    value='' body='' expected=reject
    case "$scenario" in
      plain) value=sample; expected=pass ;;
      quoted-colon) value='"alpha: beta"'; expected=pass ;;
      plain-colon) value='alpha: beta' ;;
      leading-dash) value='- alpha' ;;
      leading-question) value='? alpha' ;;
      leading-colon) value=': alpha' ;;
      leading-percent) value='%alpha' ;;
      leading-at) value='@alpha' ;;
      leading-backtick) value='`alpha' ;;
      leading-bracket) value=']alpha' ;;
      leading-brace) value='}alpha' ;;
      leading-comma) value=',alpha' ;;
      trailing-colon) value='alpha:' ;;
      safe-colon) value='alpha:beta'; expected=pass ;;
      safe-dash) value='-alpha'; expected=pass ;;
      safe-question) value='?alpha'; expected=pass ;;
      safe-leading-colon) value=':alpha'; expected=pass ;;
      unicode-colon) value=$'alpha:\302\240beta'; expected=pass ;;
      unicode-dash) value=$'-\302\240alpha'; expected=pass ;;
      unicode-question) value=$'?\302\240alpha'; expected=pass ;;
      unicode-leading-indicator) value=$'\302\240@alpha'; expected=pass ;;
      unicode-trailing-colon) value=$'alpha:\302\240'; expected=pass ;;
      valid-strip) value='|2-'; body='  alpha'; expected=pass ;;
      valid-keep) value='>+2'; body='  alpha'; expected=pass ;;
      valid-strip-first) value='|-2'; body='  alpha'; expected=pass ;;
      valid-inferred) value='>'; body=$'  alpha\n  beta'; expected=pass ;;
      valid-empty-lines) value='|'; body=$'\n\n  alpha\n\n  beta'; expected=pass ;;
      valid-leading-blank) value='|'; body=$' \n  alpha'; expected=pass ;;
      valid-explicit-tab-blank) value='|2'; body=$'  \t\n  alpha'; expected=pass ;;
      valid-explicit-tab-content) value='|2'; body=$'  \talpha'; expected=pass ;;
      valid-later-tab) value='|'; body=$'  alpha\n  \tbeta'; expected=pass ;;
      valid-explicit-more-indent) value='|1'; body=$'  alpha\n beta'; expected=pass ;;
      valid-large-indent) value='|9'; body='         alpha'; expected=pass ;;
      block-double-plus) value='|++'; body='  alpha' ;;
      block-double-minus) value='|--'; body='  alpha' ;;
      block-zero) value='|0'; body='  alpha' ;;
      block-double-digit) value='|99'; body='  alpha' ;;
      block-plus-minus) value='|+-'; body='  alpha' ;;
      block-minus-plus) value='|-+'; body='  alpha' ;;
      block-small-indent) value='|9'; body='  alpha' ;;
      block-dedent) value='|'; body=$'  alpha\n beta' ;;
      block-oversized-leading-blank) value='|'; body=$'    \n  alpha' ;;
      block-leading-tab) value='|'; body=$'\t\n  alpha' ;;
      block-leading-tab-content) value='|'; body=$'  \talpha' ;;
      block-small-tab-indent) value='|2'; body=$' \t\n  alpha' ;;
      block-continued-after-comment) value='|'; body=$'  alpha\n# comment\n  beta' ;;
    esac
    header="$root/plugins/alpha/agents/sample.agent.md"
    printf '%s\n' --- > "$header"
    if [ "$field" = description ]; then printf 'name: sample\n' >> "$header"; fi
    printf '%s: %s\n' "$field" "$value" >> "$header"
    if [ -n "$body" ]; then printf '%s\n' "$body" >> "$header"; fi
    if [ "$field" = name ]; then printf 'description: Example agent.\n' >> "$header"; fi
    printf '%s\n' --- >> "$header"
    # shellcheck disable=SC2016 # Backticks are literal catalogue markup.
    sed 's/`example` |/`example`, `sample` |/' "$root/docs/plugins.md" > "$root/new"
    mv "$root/new" "$root/docs/plugins.md"
    gate "yaml-$field-$scenario" "$expected" "$root"
    if [ "$expected" = reject ] && ! grep -Fq "must declare a non-empty '$field'" "$root/out"; then
      printf 'FAIL yaml-%s-%s did not identify the malformed identity\n' "$field" "$scenario"
      fail=$((fail+1))
    fi
  done
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
