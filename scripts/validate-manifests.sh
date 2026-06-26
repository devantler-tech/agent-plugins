#!/usr/bin/env bash
# Validate the plugin marketplace manifests and every plugins/<name>/plugin.json.
#
# Single source of truth for the checks the 🧪 CI "Validate manifests" job runs:
#   1. Both marketplace manifests (Copilot + Claude) are well-formed (.name + .plugins).
#   2. The two manifests are byte-for-byte equivalent (key-sorted) — no drift.
#   3. Every plugins/<name>/plugin.json is complete and well-shaped.
#   4. Manifest entries and on-disk plugins are in lockstep (no missing/orphan plugin,
#      no name/description/version/source divergence).
#
# Operates on the current working directory (run from the repo root, exactly as CI
# does). Documented in AGENTS.md for local runs and self-tested by
# validate-manifests.test.sh, so the gate stays a single source of truth with no
# inline/doc drift. Stops at the first failing check, mirroring the job's
# stop-on-first-failing-step behaviour.
set -euo pipefail

COPILOT_MANIFEST=".github/plugin/marketplace.json"
CLAUDE_MANIFEST=".claude-plugin/marketplace.json"

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

# 3. Every plugins/<name>/plugin.json is complete and well-shaped.
validate_plugin_json() {
  local failed=0
  local pj plugin_dir ok plugin_name
  for pj in plugins/*/plugin.json; do
    plugin_dir=$(dirname "$pj")
    ok=1
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
    if [ "$(jq -r '.skills // ""' "$pj")" != "skills/" ]; then
      echo "::error::$pj: 'skills' must be \"skills/\""
      ok=0
    fi
    if ! find "$plugin_dir/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -print -quit 2>/dev/null | grep -q .; then
      echo "::error::$plugin_dir: 'skills/' must contain at least one <skill>/SKILL.md"
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

main() {
  validate_marketplace_json "$COPILOT_MANIFEST"
  validate_marketplace_json "$CLAUDE_MANIFEST"
  validate_marketplace_parity
  validate_plugin_json
  validate_marketplace_plugins_parity
}

main "$@"
