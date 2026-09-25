#!/usr/bin/env bash
# Offline assessment of a review artifact and its exact proposed release commit.
set -euo pipefail
export GIT_NO_REPLACE_OBJECTS=1
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail() { printf 'release verification: %s\n' "$*" >&2; exit 1; }
usage() { printf 'usage: verify-marketplace-release.sh --candidate <directory> --source <full-commit> --release <full-commit>\n'; }
candidate='' source='' release=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --candidate)
      if [ "$#" -lt 2 ] || [ -n "$candidate" ]; then fail 'one candidate directory is required'; fi
      candidate=$2; shift 2 ;;
    --source)
      if [ "$#" -lt 2 ] || [ -n "$source" ]; then fail 'one source commit is required'; fi
      source=$2; shift 2 ;;
    --release)
      if [ "$#" -lt 2 ] || [ -n "$release" ]; then fail 'one release commit is required'; fi
      release=$2; shift 2 ;;
    --help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[[ "$source" =~ ^[0-9a-f]{40}$ && "$release" =~ ^[0-9a-f]{40}$ ]] || fail 'source and release must be full 40-character commits'
if [ -z "$candidate" ] || [ ! -d "$candidate" ] || [ -L "$candidate" ]; then fail 'candidate must be a real directory'; fi
candidate=$(cd "$candidate" && pwd -P)
temp=$(mktemp -d "${TMPDIR:-/tmp}/marketplace-verify.XXXXXX")
trap 'rm -rf "$temp"' EXIT
# Inspect types before reading: do not follow artifact symlinks or block on a pipe.
find "$candidate" -mindepth 1 -print0 > "$temp/entries"
while IFS= read -r -d '' entry; do
  [ ! -L "$entry" ] || fail 'candidate contains a symlink'
  case "${entry#"$candidate/"}" in
    .github|.github/plugin|.claude-plugin) [ -d "$entry" ] || fail 'candidate directory has the wrong type' ;;
    release.json|RELEASE_NOTES.md|.github/plugin/marketplace.json|.claude-plugin/marketplace.json)
      [ -f "$entry" ] || fail 'candidate artifact is not a regular file' ;;
    *) fail 'candidate contains unexpected entries' ;;
  esac
done < "$temp/entries"
for path in release.json RELEASE_NOTES.md .github/plugin/marketplace.json .claude-plugin/marketplace.json; do
  [ -f "$candidate/$path" ] || fail "missing candidate artifact: $path"
done
jq -es --arg source "$source" 'length == 1 and (.[0] | .schemaVersion==1 and .status=="CANDIDATE" and .sourceCommit==$source and .publication=="NOT_AUTHORIZED")' "$candidate/release.json" >/dev/null || fail 'candidate plan does not match the selected source'
base_tag=$(jq -r 'if .baseline==null then "initial" else .baseline.tag end' "$candidate/release.json")
# Regeneration supplies the complete-history/offline checks and the executable plan contract.
# Never execute code from the candidate or from the nominated release commit.
bash "$here/prepare-marketplace-release.sh" --base-tag "$base_tag" --head "$source" --output "$temp/regenerated" > "$temp/preparation.log"
for path in release.json RELEASE_NOTES.md .github/plugin/marketplace.json .claude-plugin/marketplace.json; do
  cmp -s "$candidate/$path" "$temp/regenerated/$path" || fail "candidate does not reproduce: $path"
done
[ "$(git cat-file -t "$release")" = commit ] || fail 'release must identify a commit'
if [ "$release" = "$source" ]; then
  [ "$base_tag" = initial ] || fail 'incremental release requires a version-update commit'
else
  parents=$(git show -s --no-show-signature --format=%P "$release")
  [ "$parents" = "$source" ] || fail 'release must have exactly the selected source as its only parent'
fi
# Only the marketplace manifests may change. Include mode changes, deletions and renames.
git diff-tree --no-commit-id --name-only -r --no-renames --no-ext-diff -z "$source" "$release" > "$temp/changes"
while IFS= read -r -d '' path; do
  case "$path" in
    .github/plugin/marketplace.json|.claude-plugin/marketplace.json) ;;
    *) fail 'release contains changes outside the proposed marketplace manifests' ;;
  esac
done < "$temp/changes"
for path in .github/plugin/marketplace.json .claude-plugin/marketplace.json; do
  source_entry=$(git ls-tree "$source" -- "$path")
  release_entry=$(git ls-tree "$release" -- "$path")
  [ "${source_entry%% *}" = "${release_entry%% *}" ] || fail "manifest mode changed: $path"
  git cat-file blob "$release:$path" > "$temp/release-manifest.json"
  # Formatting is immaterial, but every JSON field and array order must agree.
  jq -en --slurpfile actual "$temp/release-manifest.json" --slurpfile expected "$temp/regenerated/$path" '$actual==$expected' >/dev/null || fail "release manifest differs from proposal: $path"
done
jq --arg release "$release" '{schemaVersion:1,status:"VERIFIED",authority:"assessment-only",publication:"NOT_AUTHORIZED",sourceCommit,releaseCommit:$release,baseline,version,tag,scope:"local-prepublication"}' "$temp/regenerated/release.json"
