#!/usr/bin/env bash
# Check the authoring rules for first-party skills that no other check enforces (#678).
#
# A first-party skill is one whose SKILL.md records no install provenance: the same test
# validate-manifests.sh applies. An external skill is owned upstream, is never edited here
# and is not judged by this check.
#
# RULES (the skill-lifecycle skill's references/authoring.md states them)
#   1. Everything under a skill's references/ folder is a regular file directly inside it.
#   2. Every Markdown file in references/ is linked from SKILL.md. Any other file there (a
#      worked example, a data file) is linked from SKILL.md or from a Markdown file in
#      references/.
#   3. The description is no longer than the recorded limit, in characters.
# The entry file's own 500-line / 20000-byte budget is checked by validate-manifests.sh.
#
# EXCEPTIONS are recorded, with a reason each, in scripts/skill-authoring-exceptions.json
# (read from the working directory). They can only shrink: an exception whose rule now
# holds, whose file is gone, or whose recorded description ceiling no longer equals the
# measured length fails the check until the record is corrected.
#
# LINKS are read from Markdown outside fenced code blocks: inline `[text](target)` links
# and `[label]: target` definitions. A `#fragment` is ignored. A target in angle brackets
# or with spaces is not recognised and is reported as a missing link.
#
# Operates on the current working directory (run from the repository root, as CI does).
#
# USAGE  check-skill-authoring.sh
# EXIT   0 every first-party skill follows the rules
#        1 a rule is broken, an exception is stale, or a skill cannot be classified
#        2 usage error, a required tool is missing, or the exception record is unusable
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/frontmatter.lib.sh
. "$here/frontmatter.lib.sh"

unusable() {
  printf 'check-skill-authoring: %s\n' "$*" >&2
  exit 2
}

[ "$#" -eq 0 ] || unusable 'usage: check-skill-authoring.sh (no arguments; run from the repository root)'
for tool in jq yq awk find sort; do
  command -v "$tool" > /dev/null 2>&1 || unusable "$tool is required"
done
# The description is decoded by a YAML parser, never by pattern matching. Only the Go yq
# (mikefarah) reads Markdown front matter; another yq must not be trusted to mean the same.
case $(yq --version 2>&1) in
  *mikefarah*) ;;
  *) unusable 'the Go yq (github.com/mikefarah/yq) is required' ;;
esac
[ -d plugins ] || unusable 'no plugins directory here: run from the repository root'

exceptions=scripts/skill-authoring-exceptions.json
[ -f "$exceptions" ] || unusable "$exceptions is missing"
# One exact shape, so a typo cannot silently drop a rule or an exception.
jq -e '
  def text: type == "string" and (gsub("\\s"; "") | length) > 0;
  type == "object" and (keys == ["description", "references"]) and
  (.description | type == "object" and (keys == ["exceptions", "limit"]) and
    (.limit | type == "number" and . == floor and . >= 1 and . <= 1024)) and
  (.description.limit as $limit | .description.exceptions | type == "array" and all(.[];
    type == "object" and (keys == ["ceiling", "reason", "skill"]) and
    (.skill | text) and (.reason | text) and
    (.ceiling | type == "number" and . == floor and . > $limit and . <= 1024))) and
  ((.description.exceptions | map(.skill)) as $skills | ($skills | unique | length) == ($skills | length)) and
  (.references | type == "object" and (keys == ["exceptions"]) and
    (.exceptions | type == "array" and all(.[];
      type == "object" and (keys == ["file", "reason"]) and (.file | text) and (.reason | text)))) and
  ((.references.exceptions | map(.file)) as $files | ($files | unique | length) == ($files | length))
' "$exceptions" > /dev/null 2>&1 || unusable "$exceptions does not have the expected shape"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
limit=$(jq -r '.description.limit' "$exceptions")
jq -r '.description.exceptions[] | [.skill, (.ceiling | tostring)] | @tsv' "$exceptions" > "$work/description-exceptions"
jq -r '.references.exceptions[].file' "$exceptions" > "$work/reference-exceptions"
: > "$work/description-exceptions-used"
: > "$work/reference-exceptions-used"

failed=0
fail() { # file message
  echo "::error file=$1::$2"
  failed=1
}

# Print every link target in a Markdown file, one per line, without its #fragment.
link_targets() {
  awk '
    /^[ \t]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      if (match(line, /^ ? ? ?\[[^]]+\]:[ \t]*[^ \t]+/)) {
        target = substr(line, RSTART, RLENGTH)
        sub(/^ ? ? ?\[[^]]+\]:[ \t]*/, "", target)
        sub(/#.*$/, "", target)
        if (target != "") print target
      }
      while (match(line, /\]\([^) \t]+/)) {
        target = substr(line, RSTART + 2, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
        sub(/#.*$/, "", target)
        if (target != "") print target
      }
    }
  ' "$1"
}

# Count characters, not bytes: every UTF-8 character has exactly one non-continuation byte.
character_count() {
  printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d '[:space:]'
}

check_description() { # skill-dir
  local dir=$1 skill=$1/SKILL.md tag description length ceiling
  tag=$(yq --front-matter=extract '.description | tag' "$skill" 2> /dev/null) || tag=''
  if [ "$tag" != '!!str' ]; then
    fail "$skill" "the description could not be read as text, so its length is unknown"
    return 0
  fi
  description=$(yq --front-matter=extract '.description' "$skill")
  length=$(character_count "$description")
  printf '  %4s characters  %s\n' "$length" "$dir"
  ceiling=$(awk -F '\t' -v skill="$dir" '$1 == skill { print $2 }' "$work/description-exceptions")
  if [ -n "$ceiling" ]; then
    printf '%s\n' "$dir" >> "$work/description-exceptions-used"
    if [ "$length" -le "$limit" ]; then
      fail "$exceptions" "$dir: the description is now $length characters, within the limit of $limit; remove its exception"
    elif [ "$length" -gt "$ceiling" ]; then
      fail "$skill" "the description is $length characters; its recorded exception allows $ceiling. Shorten it"
    elif [ "$length" -lt "$ceiling" ]; then
      fail "$exceptions" "$dir: the description is now $length characters; lower its recorded ceiling from $ceiling to $length"
    fi
  elif [ "$length" -gt "$limit" ]; then
    fail "$skill" "the description is $length characters; the limit for a first-party skill is $limit. Shorten it, or record an exception with its reason in $exceptions"
  fi
}

check_references() { # skill-dir
  local dir=$1 refs=$1/references entry rel name document
  if [ ! -e "$refs" ] && [ ! -L "$refs" ]; then return 0; fi
  if [ -L "$refs" ] || [ ! -d "$refs" ]; then
    fail "$refs" 'references must be a real directory'
    return 0
  fi
  link_targets "$dir/SKILL.md" | sed 's|^\./||' > "$work/entry-links"
  : > "$work/reference-links"
  if ! find "$refs" -mindepth 1 -maxdepth 1 -type f -name '*.md' -print0 > "$work/documents" ||
     ! find "$refs" -mindepth 1 -print0 > "$work/entries-unsorted" ||
     ! LC_ALL=C sort -z "$work/entries-unsorted" > "$work/entries"; then
    fail "$refs" 'the references folder could not be read, so nothing in it was checked'
    return 0
  fi
  while IFS= read -r -d '' document; do
    link_targets "$document" | sed 's|^\./||' >> "$work/reference-links"
  done < "$work/documents"
  while IFS= read -r -d '' entry; do
    rel=${entry#"$dir"/}
    if [ -L "$entry" ]; then
      fail "$entry" 'a reference must be a regular file, not a link'
      continue
    fi
    [ ! -d "$entry" ] || continue
    if [ ! -f "$entry" ]; then
      fail "$entry" 'a reference must be a regular file'
      continue
    fi
    name=${rel#references/}
    case $name in
      */*)
        fail "$entry" "references sit one level deep: move this file directly into $refs"
        continue
        ;;
    esac
    if grep -Fxq -- "$rel" "$work/entry-links"; then
      if grep -Fxq -- "$entry" "$work/reference-exceptions"; then
        printf '%s\n' "$entry" >> "$work/reference-exceptions-used"
        fail "$exceptions" "$entry is now linked from SKILL.md; remove its exception"
      fi
      continue
    fi
    case $name in
      *.md) ;;
      *)
        # A worked example belongs to the document that explains it.
        if grep -Fxq -- "$name" "$work/reference-links"; then continue; fi
        fail "$entry" "this file is not linked from SKILL.md or from a Markdown file in $refs"
        continue
        ;;
    esac
    if grep -Fxq -- "$entry" "$work/reference-exceptions"; then
      printf '%s\n' "$entry" >> "$work/reference-exceptions-used"
      continue
    fi
    fail "$entry" "this reference is not linked from SKILL.md. Link it there, so a reader of the entry file can find it"
  done < "$work/entries"
}

if ! find plugins -type f -path '*/skills/*/SKILL.md' -print0 > "$work/skills-unsorted" ||
   ! LC_ALL=C sort -z "$work/skills-unsorted" > "$work/skills"; then
  unusable 'the skills under plugins could not be listed'
fi
[ -s "$work/skills" ] || unusable 'no skills found under plugins: run from the repository root'

echo "First-party skill descriptions (limit: $limit characters):"
first_party=0
while IFS= read -r -d '' skill; do
  if owner=$(frontmatter_repository < "$skill") && ! frontmatter_has_value "$skill" github-repo; then
    [ -z "$owner" ] || continue
  else
    fail "$skill" 'the skill cannot be classified as first-party or external (validate-manifests.sh reports why)'
    continue
  fi
  first_party=$((first_party + 1))
  dir=${skill%/SKILL.md}
  check_description "$dir"
  check_references "$dir"
done < "$work/skills"

# An exception that matched nothing protects nothing: it names a skill or file that is gone.
while IFS=$'\t' read -r skill _; do
  [ -n "$skill" ] || continue
  grep -Fxq -- "$skill" "$work/description-exceptions-used" ||
    fail "$exceptions" "$skill: the description exception names no first-party skill; remove it"
done < "$work/description-exceptions"
while IFS= read -r file; do
  [ -n "$file" ] || continue
  grep -Fxq -- "$file" "$work/reference-exceptions-used" ||
    fail "$exceptions" "$file: the reference exception names no reference of a first-party skill; remove it"
done < "$work/reference-exceptions"

if [ "$failed" -ne 0 ]; then
  echo "✗ first-party skill authoring rules: see the errors above" >&2
  exit 1
fi
echo "✓ $first_party first-party skills follow the authoring rules"
