#!/usr/bin/env bash
# Offline assessment of a review artifact and its exact proposed release commit.
set -euo pipefail
export GIT_NO_REPLACE_OBJECTS=1
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/marketplace-git-context.lib.sh
. "$here/marketplace-git-context.lib.sh"
marketplace_git_context
# Refuse invalid input without emitting a successful assessment.
fail() { printf 'release verification: %s\n' "$*" >&2; exit 1; }
# Describe the public verifier and its explicit historical inspection option.
usage() { printf 'usage: verify-marketplace-release.sh --candidate <directory> --source <full-commit> --release <full-commit> [--inspect-existing]\n'; }
candidate='' source='' release='' inspect_existing=false
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
    --inspect-existing)
      [ "$inspect_existing" = false ] || fail 'inspection may be selected only once'
      inspect_existing=true; shift ;;
    --help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[[ "$source" =~ ^[0-9a-f]{40}$ && "$release" =~ ^[0-9a-f]{40}$ ]] || fail 'source and release must be full 40-character commits'
if [ -z "$candidate" ] || [ ! -d "$candidate" ] || [ -L "$candidate" ]; then fail 'candidate must be a real directory'; fi
candidate=$(cd "$candidate" && pwd -P && printf '.')
candidate=${candidate%$'\n.'}
# Dispatch before consulting Git: the inspector neutralizes inherited layout overrides.
# Its distinct result cannot satisfy the normal prepublication verifier's contract.
if [ "$inspect_existing" = true ]; then
  exec bash "$here/inspect-marketplace-release.sh" "$candidate" "$source" "$release"
fi
temp=$(mktemp -d "${TMPDIR:-/tmp}/marketplace-verify.XXXXXX")
trap 'rm -rf "$temp"' EXIT
# Inspect types before reading: do not follow artifact symlinks or block on a pipe.
find "$candidate" -mindepth 1 -print0 > "$temp/entries"
entry='' entries=0 observed='|'
while IFS= read -r -d '' entry; do
  relative=${entry#"$candidate/"}
  case "$observed" in *"|$relative|"*) fail 'candidate inventory repeats an entry' ;; esac
  observed="$observed$relative|"; entries=$((entries + 1))
  [ ! -L "$entry" ] || fail 'candidate contains a symlink'
  case "${entry#"$candidate/"}" in
    .github|.github/plugin|.claude-plugin) [ -d "$entry" ] || fail 'candidate directory has the wrong type' ;;
    release.json|RELEASE_NOTES.md|.github/plugin/marketplace.json|.claude-plugin/marketplace.json)
      [ -f "$entry" ] || fail 'candidate artifact is not a regular file' ;;
    *) fail 'candidate contains unexpected entries' ;;
  esac
done < "$temp/entries"
[ -z "$entry" ] || fail 'candidate inventory contains an unterminated record'
[ "$entries" -eq 7 ] || fail 'candidate inventory is incomplete'
# The closed layout has only seven entries. Independently observe each directory
# with shell expansion, including dotfiles, before trusting find's coverage.
shopt -s dotglob nullglob
for directory in '' .github .github/plugin .claude-plugin; do
  parent="$candidate${directory:+/$directory}"
  if [ ! -d "$parent" ] || [ -L "$parent" ]; then fail 'candidate parent is not a real directory'; fi
  children=("$parent"/*)
  case "$directory" in '') count=4 ;; .github) count=1 ;; *) count=1 ;; esac
  [ "${#children[@]}" -eq "$count" ] || fail 'candidate layout contains unexpected entries'
done
shopt -u dotglob nullglob
for path in release.json RELEASE_NOTES.md .github/plugin/marketplace.json .claude-plugin/marketplace.json; do
  if [ ! -f "$candidate/$path" ] || [ -L "$candidate/$path" ]; then fail "missing or linked candidate artifact: $path"; fi
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
git diff-tree --no-relative --no-commit-id --name-only -r --no-renames --no-ext-diff -z "$source" "$release" > "$temp/changes"
path=''
while IFS= read -r -d '' path; do
  case "$path" in
    .github/plugin/marketplace.json|.claude-plugin/marketplace.json) ;;
    *) fail 'release contains changes outside the proposed marketplace manifests' ;;
  esac
done < "$temp/changes"
[ -z "$path" ] || fail 'release change inventory contains an unterminated record'
for path in .github/plugin/marketplace.json .claude-plugin/marketplace.json; do
  source_entry=$(git ls-tree --full-tree "$source" -- "$path")
  release_entry=$(git ls-tree --full-tree "$release" -- "$path")
  [ "${source_entry%% *}" = "${release_entry%% *}" ] || fail "manifest mode changed: $path"
  git cat-file blob "$release:$path" > "$temp/release-manifest.json"
  # Byte comparison also catches duplicate keys hidden by JSON parsing. The first release
  # may retain its original manifest bytes because its version was already present.
  if ! cmp -s "$temp/release-manifest.json" "$temp/regenerated/$path"; then
    [ "$base_tag" = initial ] || fail "release manifest differs from proposal: $path"
    git cat-file blob "$source:$path" > "$temp/source-manifest.json"
    cmp -s "$temp/release-manifest.json" "$temp/source-manifest.json" || fail "release manifest differs from proposal: $path"
  fi
done
# Reconstruct the entire allowed tree in a private index/object store. An empty
# successful diff producer cannot prove that unrelated source entries survived.
mkdir "$temp/objects"
objects=$(git rev-parse --git-path objects) || fail 'cannot locate source objects'
objects=$(cd "$objects" && pwd -P) || fail 'cannot resolve source object directory'
# Git accepts C-quoted entries here, not JSON's unsupported \u escapes.
quote_git_alternate() (
  LC_ALL=C; export LC_ALL
  local value=$1 i byte code
  printf '"'
  for ((i=0;i<${#value};i++)); do
    byte=${value:i:1}
    case "$byte" in
      \\|'"') printf '\\%s' "$byte" ;;
      *)
        printf -v code '%d' "'$byte"
        if [ "$code" -lt 32 ] || [ "$code" -eq 127 ]; then printf '\\%03o' "$code"
        else printf '%s' "$byte"; fi ;;
    esac
  done
  printf '"'
)
alternates=$(quote_git_alternate "$objects") || fail 'cannot retain source object directory'
expected_git() {
  GIT_INDEX_FILE="$temp/index" GIT_OBJECT_DIRECTORY="$temp/objects" GIT_ALTERNATE_OBJECT_DIRECTORIES="$alternates" \
    git -c core.fsmonitor=false -c core.splitIndex=false -c index.sparse=false "$@"
}
expected_git read-tree --no-sparse-checkout "$source" || fail 'cannot load the expected source tree'
for path in .github/plugin/marketplace.json .claude-plugin/marketplace.json; do
  entry=$(git ls-tree --full-tree "$release" -- "$path") || fail 'cannot observe release manifest entry'
  mode=${entry%% *}
  [[ "$mode" == 100644 || "$mode" == 100755 ]] || fail 'unsupported release manifest mode'
  oid=$(git rev-parse --verify "$release:$path") || fail 'cannot observe release manifest object'
  expected_git update-index --cacheinfo "$mode,$oid,$path" || fail 'cannot update expected manifest entry'
done
expected_tree=$(expected_git write-tree) || fail 'cannot complete expected release tree'
release_tree=$(git rev-parse --verify "$release^{tree}") || fail 'cannot observe complete release tree'
[ "$expected_tree" = "$release_tree" ] || fail 'release tree differs outside the approved manifest replacements'
jq --arg release "$release" '{schemaVersion:1,status:"VERIFIED",authority:"assessment-only",publication:"NOT_AUTHORIZED",sourceCommit,releaseCommit:$release,baseline,version,tag,scope:"local-prepublication"}' "$temp/regenerated/release.json"
