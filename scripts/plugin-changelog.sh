#!/usr/bin/env bash
# Write skill-sync release notes, or check newly published plugin versions.
# Usage: bash scripts/plugin-changelog.sh write <base-ref> [YYYY-MM-DD]
#        bash scripts/plugin-changelog.sh check <base-ref> <head-ref>
# The writer reads working-tree versions after bump-plugin-version.sh. The gate reads commits.
set -euo pipefail
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
  # Match the version helper when main advances while the sync branch is being prepared.
  base=$(git merge-base "$base" "$head") || fail 'no merge base'
  release_date=${3:-$(date -u +%F)}
  [[ "$release_date" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[0-1])$ ]] || fail 'invalid date'
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
plugins=$(git ls-tree -d --name-only "$head" plugins/)
[ -n "$plugins" ] || fail 'no plugins found'

# Shared Markdown state for the gate and insertion point: fences close with the same character
# and at least the opener's length. Four-space indented examples are not release headings either.
# HTML comments retain their state across lines, but comment tokens inside code are literal.
# shellcheck disable=SC2016 # Static awk program; $0 and code fences are literal.
markdown='
  # Return the last position of a matching inline backtick run, or zero for literal unmatched ticks.
  function code_end(line, size,    offset, tail) {
    offset=size+1; tail=substr(line,offset)
    while (match(tail,/`+/)) {
      if (RLENGTH==size) return offset+RSTART+RLENGTH-2
      offset+=RSTART+RLENGTH-1; tail=substr(line,offset)
    }
    return 0
  }
  # Update comment state without interpreting escaped openers or inline code as HTML.
  function comments(line,    stop, size) {
    while (length(line)) {
      if (comment) {
        stop=index(line,"-->")
        if (!stop) return
        comment=0; line=substr(line,stop+3)
      } else if (substr(line,1,1)=="\\") line=substr(line,3)
      else if (substr(line,1,4)=="<!--") { comment=1; line=substr(line,5) }
      else if (match(line,/^`+/)) {
        size=RLENGTH; stop=code_end(line,size)
        line=substr(line,(stop ? stop : size)+1)
      } else line=substr(line,2)
    }
  }
  function release_heading(    line, run, mark, size, rest) {
    line=$0
    # A comment continuation cannot contain a heading, including the line that closes it.
    if (comment) { comments(line); return 0 }
    if (line ~ /^    / || line ~ /^\t/) return 0
    sub(/^ */, "", line)
    if (line ~ /^```/ || line ~ /^~~~/) {
      mark=substr(line,1,1); run=line
      if (mark=="`") sub(/[^`].*$/, "", run); else sub(/[^~].*$/, "", run)
      size=length(run); rest=substr(line,size+1)
      if (fence=="") {
        # CommonMark 4.5: backticks in the info string make this an ordinary content line.
        if (mark=="`" && rest ~ /`/) { comments(line); return 0 }
        fence=mark; width=size
      }
      else if (mark==fence && size>=width && rest ~ /^[[:space:]]*$/) fence=""
      return 0
    }
    if (fence!="") return 0
    comments(line)
    return line ~ /^##[[:space:]]/
  }
'
# Count exact version headings outside code examples. Prefix matches and duplicates fail the gate.
headings() {
  LC_ALL=C awk -v version="$2" "$markdown"'
    release_heading() && $2==version { count++ }
    END { print count+0 }
  ' "$1"
}

# Read the scalar provenance emitted by gh skill, scoped to frontmatter metadata.
# Unsupported or duplicate values are refused instead of rendered as misleading release notes.
provenance() {
  awk -v key="$2" '
    NR==1 { if ($0 !~ /^---\r?$/) exit 1; next }
    /^---\r?$/ { closed=1; exit }
    /^metadata:[[:space:]]*$/ { metadata=1; next }
    /^[^[:space:]]/ { metadata=0 }
    metadata && $1==key ":" {
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, ""); sub(/\r$/, "")
      if (($0 ~ /^".*"$/) || ($0 ~ /^\047.*\047$/)) $0=substr($0,2,length($0)-2)
      value=$0; count++
    }
    END { if (!closed || count!=1 || value=="") exit 1; print value }
  ' "$1"
}

changed=0
while IFS= read -r dir; do
  [[ "$dir" =~ ^plugins/[a-z0-9-]+$ ]] || fail "unsupported plugin path: $dir"
  name=${dir#plugins/}
  manifest="$dir/plugin.json"
  old=''
  if git cat-file -e "$base:$manifest" 2>/dev/null; then
    old=$(git show "$base:$manifest" | jq -er '.version | strings')
  fi
  if [ "$mode" = check ]; then
    version=$(git show "$head:$manifest" | jq -er '.version | strings')
  else
    version=$(jq -er '.version | strings' "$manifest")
  fi
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid version for $name"
  [ "$version" != "$old" ] || continue
  changed=$((changed + 1))
  log="$dir/CHANGELOG.md"
  snapshot="$work/$name.old"
  if [ "$mode" = check ]; then
    git show "$head:$log" > "$snapshot" 2>/dev/null || fail "$name $version has no changelog"
    [ "$(headings "$snapshot" "$version")" -eq 1 ] || fail "$name $version needs exactly one changelog heading"
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
  paths=$(git diff --name-only --no-renames "$base" "$head" -- "$dir/skills/")
  skills=$(printf '%s\n' "$paths" | sed -nE 's|^(plugins/[^/]+/skills/[^/]+)/.*|\1|p' | LC_ALL=C sort -u)
  [ -n "$skills" ] || fail "$name has no synced skills; write its changelog manually"
  entry="$work/$name.entry"
  printf '## %s — %s\n\n' "$version" "$release_date" > "$entry"
  while IFS= read -r skill; do
    [[ "$skill" =~ ^plugins/[a-z0-9-]+/skills/[a-z0-9-]+$ ]] || fail "unsupported skill path: $skill"
    source=$(provenance "$skill/SKILL.md" github-repo) || fail "missing source for $skill"
    ref=$(provenance "$skill/SKILL.md" github-ref) || fail "missing upstream ref for $skill"
    [[ "$source" =~ ^https://github.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "unsupported source for $skill"
    [[ "$ref" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:+-]*$ ]] || fail "unsupported upstream ref for $skill"
    # shellcheck disable=SC2016 # Literal Markdown code spans, not shell expansion.
    printf '**Changed** — sync `%s` from `%s` at `%s`.\n\n' "${skill##*/}" "$source" "$ref" >> "$entry"
  done <<< "$skills"
  # Preserve the introduction and old entries, inserting immediately before the first release.
  LC_ALL=C awk -v entry="$entry" "$markdown"'
    release_heading() && !inserted { while ((getline line < entry)>0) print line; close(entry); inserted=1 }
    { print }
    END { if (!inserted) { while ((getline line < entry)>0) print line; close(entry) } }
  ' "$snapshot" > "$work/$name.new"
  [ "$(headings "$work/$name.new" "$version")" -eq 1 ] || fail "$name generated no visible release heading"
done <<< "$plugins"
# Validate every planned entry before changing any file.
if [ "$mode" = write ]; then
  for planned in "$work/"*.new; do
    [ -f "$planned" ] || continue
    name=${planned##*/}; name=${name%.new}
    mv "$planned" "plugins/$name/CHANGELOG.md"
    printf 'Wrote %s changelog\n' "$name"
  done
fi
printf 'plugin changelog: %s checked %s changed version(s)\n' "$mode" "$changed"
