#!/usr/bin/env bash
# Bump a plugin's version across all four manifests that must agree.
#
# A plugin's version lives in four places — the portable manifest, the strict Claude manifest,
# and one entry in each of the two marketplace manifests — and validate-manifests.sh fails if
# they disagree. Doing that by hand is four edits and an easy way to ship a half-bumped plugin,
# so this is the one supported way to move a version.
#
# Consumers cache plugins by version, so a content change that leaves the version untouched
# never reaches them; check-plugin-version-bump.sh is the gate that catches it, and this is the
# fix that gate points at.
#
# Usage:
#   ./scripts/bump-plugin-version.sh <plugin> [patch|minor|major]   # bump one plugin
#   ./scripts/bump-plugin-version.sh --changed-since <ref> [level]  # bump every plugin whose
#                                                                   # content changed since <ref>
#
# The --changed-since mode is what the automated skill sync uses: it bumps exactly the plugins
# whose shipped content moved, so the daily update PR satisfies the gate without a human edit.
set -euo pipefail

CLAUDE_MANIFEST=".claude-plugin/marketplace.json"
COPILOT_MANIFEST=".github/plugin/marketplace.json"

next_version() {
  local current="$1" level="$2" major minor patch
  IFS=. read -r major minor patch <<< "$current"
  if [ -z "${patch:-}" ] || [ -n "${major//[0-9]/}${minor//[0-9]/}${patch//[0-9]/}" ]; then
    echo "::error::Version '$current' is not a bare MAJOR.MINOR.PATCH triple; bump it by hand." >&2
    return 1
  fi
  case "$level" in
    major) printf '%d.0.0' "$((major + 1))" ;;
    minor) printf '%d.%d.0' "$major" "$((minor + 1))" ;;
    patch) printf '%d.%d.%d' "$major" "$minor" "$((patch + 1))" ;;
    *) echo "::error::Unknown bump level '$level' (expected patch, minor, or major)." >&2; return 1 ;;
  esac
}

write_json() {
  local file="$1"
  shift
  local tmp="$file.tmp.$$"
  jq "$@" "$file" > "$tmp" && mv "$tmp" "$file"
}

bump_one() {
  local name="$1" level="$2" dir="plugins/$1" current new
  if [ ! -f "$dir/.claude-plugin/plugin.json" ]; then
    echo "::error::No such plugin: $dir" >&2
    return 1
  fi
  current=$(jq -r '.version // empty' "$dir/.claude-plugin/plugin.json")
  if [ -z "$current" ]; then
    echo "::error::$dir/.claude-plugin/plugin.json has no 'version'." >&2
    return 1
  fi
  new=$(next_version "$current" "$level")

  # jq programs, not shell expansions — the $v/$n are bound with --arg.
  # shellcheck disable=SC2016
  {
    write_json "$dir/plugin.json" --arg v "$new" '.version = $v'
    write_json "$dir/.claude-plugin/plugin.json" --arg v "$new" '.version = $v'
    local manifest
    for manifest in "$CLAUDE_MANIFEST" "$COPILOT_MANIFEST"; do
      write_json "$manifest" --arg n "$name" --arg v "$new" \
        '.plugins |= map(if .name == $n then .version = $v else . end)'
    done
  }

  echo "✓ $name $current → $new"
}

main() {
  local level plugins

  if [ "${1:-}" = "--changed-since" ]; then
    local base="${2:?--changed-since needs a base ref}"
    level="${3:-patch}"
    local base_sha
    if ! base_sha=$(git merge-base "$base" HEAD 2>/dev/null); then
      echo "::error::Cannot resolve a merge base for '$base'...HEAD." >&2
      exit 1
    fi
    plugins=""
    while IFS= read -r plugin_dir; do
      [ -n "$plugin_dir" ] || continue
      [ -n "$(git diff --name-only "$base_sha" HEAD -- "$plugin_dir/")" ] || continue

      # The goal is "this plugin's version moved", not "add one every run". If a previous
      # pass (or a human) already bumped it relative to the base, re-running must be a
      # no-op — otherwise a re-run of the sync workflow inflates the version each time.
      local manifest_rel=".claude-plugin/plugin.json"
      local base_v head_v
      base_v=$(git show "$base_sha:$plugin_dir/$manifest_rel" 2>/dev/null | jq -r '.version // empty')
      head_v=$(jq -r '.version // empty' "$plugin_dir/$manifest_rel" 2>/dev/null)
      if [ -n "$base_v" ] && [ "$base_v" != "$head_v" ]; then
        echo "✓ ${plugin_dir#plugins/} already moved $base_v → $head_v — leaving it"
        continue
      fi
      plugins="$plugins ${plugin_dir#plugins/}"
    done < <(git ls-tree -d --name-only HEAD plugins/)
    if [ -z "${plugins// /}" ]; then
      echo "✓ No plugin content changed since $base — nothing to bump"
      return 0
    fi
  else
    plugins="${1:?usage: bump-plugin-version.sh <plugin> [patch|minor|major]}"
    level="${2:-patch}"
  fi

  local p
  for p in $plugins; do
    bump_one "$p" "$level"
  done
}

main "$@"
