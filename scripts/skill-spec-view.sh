#!/usr/bin/env bash
# Print the path of a copy of one skill that the Agent Skills spec validator can judge.
#
# Why this exists: Claude Code and VS Code read two skill frontmatter fields the agentskills.io
# spec does not define, `argument-hint` and `user-invocable`, and Anthropic's own skills use them. The
# spec validator rejects any field it does not define, so those skills could not be bundled
# unmodified, and bundled skills are never rewritten. The maintainer decided (2026-11-04) to
# accept exactly those two fields. This view drops them, and only them, from a copy, so the
# validator still checks everything else, and any other unknown field still fails.
#
# Only a top-level `key: value` line with a non-empty single-line value is dropped. A block
# scalar, an empty value, a continuation line or a repeated field is refused rather than
# half-stripped, because removing one line of a multi-line value would hand the validator
# frontmatter the skill does not have.
#
# USAGE
#   skill-spec-view.sh <skill-dir> <out-root>
#
# Copies <skill-dir> to <out-root>/<basename of skill-dir> (which must not exist yet), drops
# the two fields from the copy's SKILL.md frontmatter and prints the copy's path.
#
# EXIT  0 printed the view; 1 the frontmatter cannot be reduced safely; 2 usage or I/O error.
set -euo pipefail

if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  echo 'usage: skill-spec-view.sh <skill-dir> <out-root>' >&2
  exit 2
fi
src=${1%/}
out_root=$2
if [ ! -f "$src/SKILL.md" ]; then
  echo "skill-spec-view: $src has no SKILL.md" >&2
  exit 2
fi
dest=$out_root/$(basename "$src")
if [ -e "$dest" ] || [ -L "$dest" ]; then
  echo "skill-spec-view: $dest already exists" >&2
  exit 2
fi
mkdir -p "$out_root"
cp -R "$src" "$dest"

status=0
awk '
  function refuse(why) { printf "skill-spec-view: %s: %s\n", FILENAME, why > "/dev/stderr"; bad=1; exit 1 }
  NR == 1 {
    if ($0 !~ /^---[ \t]*\r?$/) refuse("SKILL.md does not open with frontmatter")
    print; next
  }
  !closed && /^---[ \t]*\r?$/ { closed=1; print; next }
  closed { print; next }
  {
    # A continuation of a dropped field would be left behind on its own.
    if (dropping && /^[ \t]/) refuse("a dropped field continues onto another line")
    dropping=0
    if (match($0, /^(argument-hint|user-invocable):/)) {
      key=substr($0, 1, RLENGTH - 1)
      if (seen[key]++) refuse(key " appears more than once")
      value=substr($0, RLENGTH + 1)
      sub(/^[ \t]+/, "", value); sub(/[ \t]+(#.*)?\r?$/, "", value); sub(/\r$/, "", value)
      if (value == "" || value ~ /^[|>]/) refuse(key " has no single-line value")
      dropping=1
      next
    }
    print
  }
  END { if (!bad && !closed) refuse("SKILL.md frontmatter is not closed") }
' "$src/SKILL.md" > "$dest/SKILL.md.view" || status=$?

if [ "$status" -ne 0 ]; then
  rm -rf "$dest"
  exit 1
fi
mv "$dest/SKILL.md.view" "$dest/SKILL.md"
printf '%s\n' "$dest"
