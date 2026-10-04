#!/usr/bin/env bash
# Write skill-sync release notes, or check newly published plugin versions.
# Usage: bash scripts/plugin-changelog.sh write <base-ref> [YYYY-MM-DD]
#        bash scripts/plugin-changelog.sh check <base-ref> <head-ref>
# The writer reads working-tree versions after bump-plugin-version.sh. The gate reads commits.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/marketplace-git-context.lib.sh
source "$here/marketplace-git-context.lib.sh"
marketplace_git_context
# shellcheck source=scripts/plugin-version.lib.sh
source "$here/plugin-version.lib.sh"
# shellcheck source=scripts/json-object.lib.sh
source "$here/json-object.lib.sh"
# shellcheck source=scripts/atomic-write.lib.sh
source "$here/atomic-write.lib.sh"
mode=${1:-}
base_ref=${2:-}
fail() { printf 'plugin-changelog: %s\n' "$*" >&2; exit 1; }
[ "$mode" = write ] || [ "$mode" = check ] || fail 'expected write or check'
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then fail 'expected base and optional date/head'; fi
base=$(git rev-parse --verify --end-of-options "$base_ref^{commit}") || fail 'unreadable base'
if [ "$mode" = check ]; then
  head=$(git rev-parse --verify --end-of-options "${3:-HEAD}^{commit}") || fail 'unreadable head'
else
  head=$(git rev-parse --verify HEAD)
  release_date=${3:-$(date -u +%F)}
  [[ "$release_date" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[0-1])$ ]] || fail 'invalid date'
  year=$((10#${release_date:0:4})); month=$((10#${release_date:5:2})); day=$((10#${release_date:8:2}))
  days=31
  case "$month" in
    4|6|9|11) days=30 ;;
    2) days=28; if (( year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) )); then days=29; fi ;;
  esac
  (( year > 0 && day <= days )) || fail 'invalid calendar date'
fi
# Compare only this branch's changes, including when main advances during preparation.
plugin_version_history || fail 'incomplete comparison history'
bases=$(git merge-base --all "$base" "$head") || fail 'no merge base'
[[ "$bases" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || fail 'comparison requires one merge base'
base=$bases
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
plugins=$(git ls-tree -d --name-only "$head" plugins/)
[ -n "$plugins" ] || fail 'no plugins found'

# The gate and insertion point use the same CommonMark heading inventory.
headings() {
  node "$here/changelog-headings.cjs" "$1" | jq -r --arg version "$2" '[.[] | select(.version == $version)] | length'
}

# Read the scalar provenance emitted by gh skill, scoped to frontmatter metadata.
# Unsupported or duplicate values are refused instead of rendered as misleading release notes.
provenance() {
  awk -v key="$2" '
    NR==1 { if ($0 !~ /^---\r?$/) exit 1; next }
    /^---\r?$/ { closed=1; exit }
    /^metadata:[[:space:]]*$/ { metadata=1; child_indent=0; next }
    /^[^[:space:]]/ { metadata=0 }
    metadata && /^ +[^[:space:]#]/ {
      indent=match($0,/[^ ]/)-1
      if (!child_indent) child_indent=indent
      if (indent!=child_indent || $1!=key ":") next
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, ""); sub(/\r$/, "")
      if (($0 ~ /^".*"$/) || ($0 ~ /^\047.*\047$/)) $0=substr($0,2,length($0)-2)
      value=$0; count++
    }
    END { if (!closed || count!=1 || value=="") exit 1; print value }
  ' "$1"
}

# Require one complete manifest object before accepting its scalar version.
manifest_version() {
  cat "$@" > "$work/manifest.json" || return 1
  json_object_unique "$work/manifest.json" || return 1
  jq -er '.version | strings' "$work/manifest.json"
}

changed=0
while IFS= read -r dir; do
  [[ "$dir" =~ ^plugins/[a-z0-9-]+$ ]] || fail "unsupported plugin path: $dir"
  name=${dir#plugins/}
  if [ "$mode" = write ]; then
    for parent in plugins "$dir"; do
      if [ ! -d "$parent" ] || [ -L "$parent" ]; then
        fail 'changelog parent must be a real checkout directory'
      fi
    done
  fi
  manifest="$dir/plugin.json"
  old=''
  base_entry=$(git ls-tree "$base" -- "$manifest") || fail "unreadable base manifest tree: $name"
  if [ -n "$base_entry" ]; then
    base_manifest=$(git show "$base:$manifest") || fail "unreadable base manifest: $name"
    old=$(manifest_version <<< "$base_manifest") || fail "invalid base manifest: $name"
    [[ "$old" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid base version for $name"
  fi
  if [ "$mode" = check ]; then
    version=$(git show "$head:$manifest" | manifest_version) || fail "invalid head manifest: $name"
  else
    version=$(manifest_version "$manifest") || fail "invalid working manifest: $name"
  fi
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid version for $name"
  [ "$version" != "$old" ] || continue
  changed=$((changed + 1))
  log="$dir/CHANGELOG.md"
  snapshot="$work/$name.old"
  if [ "$mode" = check ]; then
    git show "$head:$log" > "$snapshot" 2>/dev/null || fail "$name $version has no changelog"
    count=$(headings "$snapshot" "$version") || fail "unreadable changelog headings: $name"
    [ "$count" -eq 1 ] || fail "$name $version needs exactly one changelog heading"
    continue
  fi
  [ ! -L "$log" ] || fail "refusing symlink: $log"
  if [ -f "$log" ]; then
    cp "$log" "$snapshot"
  else
    # shellcheck disable=SC2016 # Literal Markdown code spans, not shell expansion.
    printf '# Changelog — `%s`\n\n' "$name" > "$snapshot"
  fi
  count=$(headings "$snapshot" "$version")
  [ "$count" -le 1 ] || fail "$name $version has duplicate headings"
  [ "$count" -eq 0 ] || continue # Preserve the entire hand-written entry byte for byte.
  git diff --name-only -z --no-renames "$base" "$head" -- "$dir/skills/" > "$work/paths" || fail "unreadable changed paths: $name"
  : > "$work/skills"
  path=''
  while IFS= read -r -d '' path; do
    relative=${path#"$dir/skills/"}
    [[ "$relative" == */* ]] || fail "unsupported skill resource path: $path"
    printf '%s\n' "$dir/skills/${relative%%/*}" >> "$work/skills"
  done < "$work/paths"
  [ -z "$path" ] || fail "unterminated changed path inventory: $name"
  skills=$(LC_ALL=C sort -u "$work/skills") || fail "unreadable changed skills: $name"
  [ -n "$skills" ] || fail "$name has no synced skills; write its changelog manually"
  entry="$work/$name.entry"
  printf '## %s — %s\n\n' "$version" "$release_date" > "$entry"
  while IFS= read -r skill; do
    [[ "$skill" =~ ^plugins/[a-z0-9-]+/skills/[a-z0-9-]+$ ]] || fail "unsupported skill path: $skill"
    metadata="$skill/SKILL.md"
    removed=false
    tree=$(git ls-tree "$head" -- "$metadata") || fail "unreadable skill tree: $skill"
    if [ -z "$tree" ]; then
      remaining=$(git ls-tree -r --name-only "$head" -- "$skill/") || fail "unreadable removed skill tree: $skill"
      [ -z "$remaining" ] || fail "incomplete skill removal: $skill"
      removed=true
      metadata="$work/removed-skill.md"
      previous=$(git ls-tree "$base" -- "$skill/SKILL.md") || fail "unreadable previous skill tree: $skill"
      [[ "$previous" == '100644 blob '* || "$previous" == '100755 blob '* ]] || fail "previous skill provenance is not a regular committed file: $skill"
      git show "$base:$skill/SKILL.md" > "$metadata" 2>/dev/null || fail "missing previous skill: $skill"
    else
      [[ "$tree" == '100644 blob '* || "$tree" == '100755 blob '* ]] || fail "skill provenance is not a regular committed file: $skill"
      metadata="$work/committed-skill.md"
      git cat-file blob "$head:$skill/SKILL.md" > "$metadata" || fail "unreadable skill object: $skill"
    fi
    source=$(provenance "$metadata" github-repo) || fail "missing source for $skill"
    ref=$(provenance "$metadata" github-ref) || fail "missing upstream ref for $skill"
    [[ "$source" =~ ^https://github.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "unsupported source for $skill"
    [[ "$ref" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:+-]*$ ]] || fail "unsupported upstream ref for $skill"
    if [ "$removed" = true ]; then
      # shellcheck disable=SC2016 # Literal Markdown code spans, not shell expansion.
      printf '**Removed** — `%s`, previously from `%s` at `%s`.\n\n' "${skill##*/}" "$source" "$ref" >> "$entry"
    else
      # shellcheck disable=SC2016 # Literal Markdown code spans, not shell expansion.
      printf '**Changed** — sync `%s` from `%s` at `%s`.\n\n' "${skill##*/}" "$source" "$ref" >> "$entry"
    fi
  done <<< "$skills"
  # Preserve the introduction and old entries, inserting immediately before the first release.
  first=$(node "$here/changelog-headings.cjs" "$snapshot" | jq -r '.[0].line // 0')
  LC_ALL=C awk -v entry="$entry" -v first="$first" '
    NR==first { while ((getline line < entry)>0) print line; close(entry); inserted=1 }
    { print }
    END { if (!inserted) { while ((getline line < entry)>0) print line; close(entry) } }
  ' "$snapshot" > "$work/$name.new"
  count=$(headings "$work/$name.new" "$version") || fail "unreadable generated headings: $name"
  [ "$count" -eq 1 ] || fail "$name generated no visible release heading"
done <<< "$plugins"
# Validate every planned entry before changing any file.
if [ "$mode" = write ]; then
  : > "$work/plan"
  for planned in "$work/"*.new; do
    [ -f "$planned" ] || continue
    name=${planned##*/}; name=${name%.new}
    printf '%s\0%s\0' "plugins/$name/CHANGELOG.md" "$planned" >> "$work/plan"
  done
  atomic_write_batch "$work/plan" true || fail 'changelog batch replacement failed'
fi
printf 'plugin changelog: %s checked %s changed version(s)\n' "$mode" "$changed"
