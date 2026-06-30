#!/usr/bin/env bash
# Validate the plugin marketplace manifests, every plugins/<name>/plugin.json, and the
# README plugin table.
#
# Single source of truth for the checks the 🧪 CI "Validate manifests" job runs:
#   1. Both marketplace manifests (Copilot + Claude) are well-formed (.name + .plugins).
#   2. The two manifests are byte-for-byte equivalent (key-sorted) — no drift.
#   3. Every plugins/<name>/plugin.json is complete and well-shaped.
#   4. Manifest entries and on-disk plugins are in lockstep (no missing/orphan plugin,
#      no name/description/version/source divergence).
#   5. The README plugin table and on-disk plugin resources are in lockstep (every plugin
#      has a row and vice versa; each row's Resources column matches the plugin's bundled
#      skills + MCP servers).
#
# Operates on the current working directory (run from the repo root, exactly as CI
# does). Documented in AGENTS.md for local runs and self-tested by
# validate-manifests.test.sh, so the gate stays a single source of truth with no
# inline/doc drift. Stops at the first failing check, mirroring the job's
# stop-on-first-failing-step behaviour.
set -euo pipefail

COPILOT_MANIFEST=".github/plugin/marketplace.json"
CLAUDE_MANIFEST=".claude-plugin/marketplace.json"
README="README.md"

# 1. A marketplace manifest must parse and carry both required top-level keys.
validate_marketplace_json() {
  local manifest="$1"
  if ! jq -e '.name and .plugins' "$manifest" > /dev/null 2>&1; then
    echo "::error::Invalid $manifest"
    return 1
  fi
  echo "✓ $manifest is valid"
}

# 2. The Copilot and Claude manifests must be identical once key-sorted.
validate_marketplace_parity() {
  if ! diff <(jq -S . "$COPILOT_MANIFEST") <(jq -S . "$CLAUDE_MANIFEST") > /dev/null 2>&1; then
    echo "::error::Marketplace manifests are out of sync"
    diff <(jq -S . "$COPILOT_MANIFEST") <(jq -S . "$CLAUDE_MANIFEST") || true
    return 1
  fi
  echo "✓ Marketplace manifests are in sync"
}

# A bundled MCP server (ADR 0001 §D3): an .mcp.json must be valid JSON with a
# non-empty '.mcpServers' object, each server carrying a 'command' (stdio transport)
# or a 'url' (remote transport).
validate_mcp_json() {
  local mcp="$1" bad
  if ! jq -e . "$mcp" > /dev/null 2>&1; then
    echo "::error::$mcp: not valid JSON"
    return 1
  fi
  if [ "$(jq -r '(.mcpServers // {}) | length' "$mcp")" -eq 0 ]; then
    echo "::error::$mcp: '.mcpServers' must be a non-empty object"
    return 1
  fi
  bad=$(jq -r '.mcpServers | to_entries[]
    | select((.value.command // "") == "" and (.value.url // "") == "") | .key' "$mcp")
  if [ -n "$bad" ]; then
    echo "::error::$mcp: server(s) missing a 'command' (stdio) or 'url' (remote): ${bad//$'\n'/ }"
    return 1
  fi
  return 0
}

# 3. Every plugins/<name>/plugin.json is complete and well-shaped, declaring at least
#    one recognized resource (skills/, a bundled .mcp.json, or agents/) — ADR 0001 §D3.
validate_plugin_json() {
  local failed=0
  local pj plugin_dir ok plugin_name resource_count
  for pj in plugins/*/plugin.json; do
    plugin_dir=$(dirname "$pj")
    ok=1
    resource_count=0
    plugin_name=$(jq -r '.name // ""' "$pj")
    if ! echo "$plugin_name" | grep -qE '^[a-z0-9-]+$'; then
      echo "::error::$pj: name '$plugin_name' must be kebab-case (a-z, 0-9, hyphens)"
      ok=0
    fi
    if [ "$(jq -r '.description // "" | length' "$pj")" -eq 0 ]; then
      echo "::error::$pj: missing or empty 'description' field"
      ok=0
    fi
    if [ "$(jq -r '.version // "" | length' "$pj")" -eq 0 ]; then
      echo "::error::$pj: missing or empty 'version' field"
      ok=0
    fi
    # Skills resource: when '.skills' is declared it must be "skills/" and contain at
    # least one <skill>/SKILL.md. (Existing check — unchanged, only made conditional.)
    if [ "$(jq -e 'has("skills")' "$pj")" = "true" ]; then
      if [ "$(jq -r '.skills // ""' "$pj")" != "skills/" ]; then
        echo "::error::$pj: 'skills' must be \"skills/\""
        ok=0
      elif ! find "$plugin_dir/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -print -quit 2>/dev/null | grep -q .; then
        echo "::error::$plugin_dir: 'skills/' must contain at least one <skill>/SKILL.md"
        ok=0
      else
        resource_count=$((resource_count + 1))
      fi
    fi
    # MCP resource: a bundled .mcp.json at the plugin root must validate.
    if [ -f "$plugin_dir/.mcp.json" ]; then
      if validate_mcp_json "$plugin_dir/.mcp.json"; then
        resource_count=$((resource_count + 1))
      else
        ok=0
      fi
    fi
    # Custom-agents resource: an agents/ directory holding at least one entry.
    if find "$plugin_dir/agents" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
      resource_count=$((resource_count + 1))
    fi
    if [ "$resource_count" -eq 0 ]; then
      echo "::error::$plugin_dir: must declare at least one resource (skills/, .mcp.json, or agents/)"
      ok=0
    fi
    if [ "$ok" -eq 1 ]; then
      echo "✓ $pj ($plugin_name)"
    else
      failed=1
    fi
  done
  return "$failed"
}

# 4. Manifest entries and on-disk plugins are in lockstep.
validate_marketplace_plugins_parity() {
  local failed=0
  local manifest="$CLAUDE_MANIFEST"
  local name description version source ok pj
  # Every plugin entry in the manifest resolves to a matching plugins/<name>/ on disk.
  while IFS=$'\t' read -r name description version source; do
    ok=1
    if [ "$source" != "./plugins/$name" ]; then
      echo "::error::$manifest: plugin '$name' source '$source' must be './plugins/$name'"
      ok=0
    fi
    pj="plugins/$name/plugin.json"
    if [ ! -f "$pj" ]; then
      echo "::error::$manifest: plugin '$name' has no $pj on disk"
      failed=1
      continue
    fi
    if [ "$(jq -r '.name' "$pj")" != "$name" ]; then
      echo "::error::$pj: name does not match manifest entry '$name'"
      ok=0
    fi
    if [ "$(jq -r '.description' "$pj")" != "$description" ]; then
      echo "::error::$pj: description differs from manifest entry '$name'"
      ok=0
    fi
    if [ "$(jq -r '.version' "$pj")" != "$version" ]; then
      echo "::error::$pj: version differs from manifest entry '$name'"
      ok=0
    fi
    if [ "$ok" -eq 1 ]; then
      echo "✓ $name ↔ $pj"
    else
      failed=1
    fi
  done < <(jq -r '.plugins[] | [.name, .description, .version, .source] | @tsv' "$manifest")
  # Every plugins/<name>/ on disk appears in the manifest (no orphan plugin).
  for pj in plugins/*/plugin.json; do
    name=$(jq -r '.name' "$pj")
    if ! jq -e --arg n "$name" '.plugins[] | select(.name == $n)' "$manifest" > /dev/null; then
      echo "::error::plugins/$name is not listed in $manifest"
      failed=1
    fi
  done
  return "$failed"
}

# Resource token names (sorted, space-separated) a plugin bundles: every skill
# directory under plugins/<name>/skills/ PLUS every MCP server key in an optional
# plugins/<name>/.mcp.json. These are the tokens the README "Resources" column must
# list (ADR 0001 §D3). Count EVERY skill directory, not only those that already carry a
# SKILL.md, so a stray/half-added skill folder (the exact drift this parity check guards
# against) is surfaced rather than silently hidden.
plugin_disk_resources() {
  local name="$1" d mcp="plugins/$1/.mcp.json"
  {
    for d in "plugins/$name/skills"/*/; do
      [ -d "$d" ] || continue
      basename "$d"
    done
    if [ -f "$mcp" ]; then
      jq -r '.mcpServers // {} | keys[]' "$mcp"
    fi
  } | sort | tr '\n' ' '
}

# 5. The README plugin table and on-disk plugin resources are in lockstep.
#    Table rows look like:
#      | [`<name>`](plugins/<name>/) | `skill-a`, `mcp-server-b` | <editorial description> |
#    The Resources column lists every bundled skill AND MCP server; the Description
#    column stays free prose (plugin.json↔manifest already guards it).
# The backticks below are literal table-cell markers in regex/sed patterns, not command
# substitution — SC2016 (won't-expand) is a false positive here.
# shellcheck disable=SC2016
validate_readme_parity() {
  local failed=0
  local line name readme_resources disk_resources
  local readme_names=()
  # Each README plugin row: parse the plugin name (col 1) and its Resources column (col 3).
  while IFS= read -r line; do
    name=$(printf '%s' "$line" | sed -nE 's/^\| \[`([a-z0-9-]+)`\].*/\1/p')
    [ -z "$name" ] && continue
    readme_names+=("$name")
    readme_resources=$(printf '%s' "$line" | awk -F'|' '{print $3}' \
      | grep -oE '`[a-z0-9-]+`' | tr -d '`' | sort | tr '\n' ' ')
    # Require the manifest, not just the directory: a stray plugins/<name>/ without a
    # plugin.json would otherwise pass here yet stay invisible to the orphan scan below
    # (which only iterates plugins/*/plugin.json).
    if [ ! -f "plugins/$name/plugin.json" ]; then
      echo "::error::$README lists plugin '$name' with no plugins/$name/plugin.json on disk"
      failed=1
      continue
    fi
    disk_resources=$(plugin_disk_resources "$name")
    if [ "$readme_resources" != "$disk_resources" ]; then
      echo "::error::$README Resources for '$name' (${readme_resources% }) differ from on-disk resources (${disk_resources% })"
      failed=1
    else
      echo "✓ $README ↔ plugins/$name (resources: ${disk_resources% })"
    fi
  done < <(grep -E '^\| \[`[a-z0-9-]+`\]' "$README")
  # Every plugins/<name>/ on disk appears as a README row (no plugin missing from the table).
  local pj listed rn
  for pj in plugins/*/plugin.json; do
    name=$(jq -r '.name' "$pj")
    listed=0
    for rn in "${readme_names[@]}"; do
      [ "$rn" = "$name" ] && listed=1 && break
    done
    if [ "$listed" -eq 0 ]; then
      echo "::error::plugins/$name is not listed in the $README plugin table"
      failed=1
    fi
  done
  return "$failed"
}

# 6. Every bundled SKILL.md carries its upstream provenance frontmatter.
#    `gh skill install` records the true upstream in each skill's `metadata.github-*`
#    frontmatter, and AGENTS.md forbids hand-authored/divergent skills — so a bundled
#    skill MUST carry a real `github-repo` value *inside the `metadata:` block* of the
#    YAML frontmatter (the lines between the first two `---`). Staying jq/grep-only (no
#    yq dependency), one awk pass both slices the frontmatter and scopes the lookup to
#    `metadata:` so a TOP-LEVEL `github-repo:` cannot satisfy it, and rejects an empty,
#    quoted-empty (`""`/`''`) or comment-only (`# …`) value — each of which can only
#    come from a hand edit. A skill with no frontmatter yields no match → reject.
validate_skill_provenance() {
  local failed=0
  local skill
  while IFS= read -r skill; do
    if awk '
      # Walk only the frontmatter (lines between the first two --- ); END decides via found.
      NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
      /^---[[:space:]]*$/ { fm++; next }
      fm!=1 { next }
      # A non-indented key (column 0) is a top-level mapping key. metadata: opens the
      # block we care about; any other top-level key closes it (so a TOP-LEVEL
      # github-repo: can never satisfy the guard).
      /^metadata:[[:space:]]*$/ { in_meta=1; next }
      /^[^[:space:]]/ { in_meta=0; next }
      # Inside metadata:, an indented github-repo: with a real value is provenance.
      in_meta && /^[[:space:]]+github-repo:/ {
        v=$0
        sub(/^[[:space:]]+github-repo:[[:space:]]*/, "", v)  # drop the key
        sub(/[[:space:]]+#.*$/, "", v)                        # drop trailing " # comment"
        if (v ~ /^#/) v=""                                    # whole value is a comment ⇒ null
        gsub(/^[[:space:]"'"'"']+|[[:space:]"'"'"']+$/, "", v) # trim spaces and surrounding quotes
        if (v != "") found=1
      }
      END { exit(found ? 0 : 1) }
    ' "$skill"; then
      echo "✓ provenance $skill"
    else
      echo "::error::$skill: missing upstream provenance (metadata.github-repo) — bundled skills must come from 'gh skill install', never hand-authored"
      failed=1
    fi
  done < <(find plugins -type f -path '*/skills/*/SKILL.md' | sort)
  return "$failed"
}

main() {
  validate_marketplace_json "$COPILOT_MANIFEST"
  validate_marketplace_json "$CLAUDE_MANIFEST"
  validate_marketplace_parity
  validate_plugin_json
  validate_marketplace_plugins_parity
  validate_readme_parity
  validate_skill_provenance
}

main "$@"
