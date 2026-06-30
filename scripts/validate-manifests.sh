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
#   5. The README plugin table and on-disk plugins/skills are in lockstep (every plugin
#      has a row and vice versa; each row's Skills column matches the plugin's skills/).
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

# Skill directory names (sorted, space-separated) bundled under plugins/<name>/skills/.
# Count EVERY skill directory, not only those that already carry a SKILL.md, so a
# stray/half-added skill folder (the exact drift this parity check guards against)
# is surfaced rather than silently hidden.
plugin_disk_skills() {
  local name="$1" d
  for d in "plugins/$name/skills"/*/; do
    [ -d "$d" ] || continue
    basename "$d"
  done | sort | tr '\n' ' '
}

# 5. The README plugin table and on-disk plugins/skills are in lockstep.
#    Table rows look like:
#      | [`<name>`](plugins/<name>/) | `skill-a`, `skill-b` | <editorial description> |
#    The Description column stays free prose (plugin.json↔manifest already guards it).
# The backticks below are literal table-cell markers in regex/sed patterns, not command
# substitution — SC2016 (won't-expand) is a false positive here.
# shellcheck disable=SC2016
validate_readme_parity() {
  local failed=0
  local line name readme_skills disk_skills
  local readme_names=()
  # Each README plugin row: parse the plugin name (col 1) and its Skills column (col 3).
  while IFS= read -r line; do
    name=$(printf '%s' "$line" | sed -nE 's/^\| \[`([a-z0-9-]+)`\].*/\1/p')
    [ -z "$name" ] && continue
    readme_names+=("$name")
    readme_skills=$(printf '%s' "$line" | awk -F'|' '{print $3}' \
      | grep -oE '`[a-z0-9-]+`' | tr -d '`' | sort | tr '\n' ' ')
    # Require the manifest, not just the directory: a stray plugins/<name>/ without a
    # plugin.json would otherwise pass here yet stay invisible to the orphan scan below
    # (which only iterates plugins/*/plugin.json).
    if [ ! -f "plugins/$name/plugin.json" ]; then
      echo "::error::$README lists plugin '$name' with no plugins/$name/plugin.json on disk"
      failed=1
      continue
    fi
    disk_skills=$(plugin_disk_skills "$name")
    if [ "$readme_skills" != "$disk_skills" ]; then
      echo "::error::$README Skills for '$name' (${readme_skills% }) differ from plugins/$name/skills/ (${disk_skills% })"
      failed=1
    else
      echo "✓ $README ↔ plugins/$name (skills: ${disk_skills% })"
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
#    skill MUST carry that provenance. We assert a non-empty `github-repo:` inside the
#    YAML frontmatter (the block between the first two `---` lines), staying jq/grep-only
#    like the rest of this guard (no yq dependency). A skill with no frontmatter, or with
#    an empty/absent `github-repo`, is rejected — it can only have come from a hand edit.
validate_skill_provenance() {
  local failed=0
  local skill fm
  while IFS= read -r skill; do
    # Slice the YAML frontmatter: the lines strictly between the first '---' and the
    # next '---'. A file that does not open with '---' yields an empty slice (→ fail).
    fm=$(awk 'NR==1 && $0 !~ /^---[[:space:]]*$/ {exit}
              /^---[[:space:]]*$/ {c++; next}
              c==1 {print}
              c>=2 {exit}' "$skill")
    if printf '%s\n' "$fm" | grep -qE '^[[:space:]]*github-repo:[[:space:]]*[^[:space:]]'; then
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
