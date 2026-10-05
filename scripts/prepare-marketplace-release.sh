#!/usr/bin/env bash
# Prepare immutable, offline review artifacts. No checkout, ref, or remote writes.
set -euo pipefail
export GIT_NO_REPLACE_OBJECTS=1 GIT_NO_LAZY_FETCH=1
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/marketplace-git-context.lib.sh
. "$here/marketplace-git-context.lib.sh"
marketplace_git_context
# shellcheck source=scripts/json-object.lib.sh
. "$here/json-object.lib.sh"
# Stop preparation without emitting a prepared candidate.
fail() { printf 'release preparation: %s\n' "$*" >&2; exit 1; }
directory_identity() {
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  case "$(uname -s)" in
    Darwin) stat -f '%d:%i' "$1" ;;
    Linux) stat -c '%d:%i' "$1" ;;
    *) return 1 ;;
  esac
}
# Describe offline preparation and the explicit Git head selector.
usage() { printf 'usage: prepare-marketplace-release.sh --base-tag <initial|vX.Y.Z> --output <new-directory> [--head <full-commit>]\n'; }
base_tag='' output='' head=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-tag)
      if [ "$#" -lt 2 ] || [ -n "$base_tag" ]; then fail 'one base tag is required'; fi
      base_tag=$2; shift 2 ;;
    --output)
      if [ "$#" -lt 2 ] || [ -n "$output" ]; then fail 'one output directory is required'; fi
      output=$2; shift 2 ;;
    --head)
      if [ "$#" -lt 2 ] || [ -n "$head" ]; then fail 'one full head commit is required'; fi
      head=$2; shift 2 ;;
    --help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
if [ -z "$base_tag" ] || [ -z "$output" ]; then fail 'base tag and output are required'; fi
if [ "$base_tag" != initial ]; then
  if [[ "$base_tag" != v* ]] || ! jq -en -L "$here" --arg v "${base_tag#v}" 'include "marketplace-release"; $v | stable_version' >/dev/null; then
    fail 'base must be initial or a stable vX.Y.Z tag'
  fi
fi
[ "$(git rev-parse --is-shallow-repository)" = false ] || fail 'complete Git history is required'
grafts=$(git rev-parse --git-path info/grafts)
[ ! -s "$grafts" ] || fail 'grafted history is unsupported'
# A partial clone fetches missing objects on demand, which would break the offline guarantee.
# shellcheck source=scripts/complete-clone.lib.sh
. "$here/complete-clone.lib.sh"
assert_complete_clone_config || fail 'incomplete Git configuration; offline history is required'
if [ -z "$head" ]; then head=$(git rev-parse --verify HEAD); fi
[[ "$head" =~ ^[0-9a-f]{40}$ ]] || fail 'head must be a full 40-character commit'
[ "$(git cat-file -t "$head")" = commit ] || fail 'head must identify a commit'
# A sentinel retains path newlines that command substitution would otherwise trim.
parent=$(dirname "$output" && printf '.') || fail 'output parent must exist'
parent=${parent%.}; parent=${parent%$'\n'}
parent=$(cd "$parent" && pwd -P && printf '.') || fail 'output parent must exist'
parent=${parent%.}; parent=${parent%$'\n'}
name=$(basename "$output" && printf '.') || fail 'output must name a new directory'
parent_identity=$(directory_identity "$parent") || fail 'cannot identify output parent'
[[ $parent_identity =~ ^[0-9]+:[0-9]+$ ]] || fail 'invalid output parent identity'
name=${name%.}; name=${name%$'\n'}
[[ "$name" != . && "$name" != .. && "$name" != / ]] || fail 'output must name a new directory'
output="$parent/$name"
caller=$(git rev-parse --show-toplevel && printf '.') || fail 'must run inside a Git worktree'
caller=${caller%.}; caller=${caller%$'\n'}
caller=$(cd "$caller" && pwd -P && printf '.') || fail 'cannot resolve caller worktree'
caller=${caller%.}; caller=${caller%$'\n'}
# Retain one complete NUL census and its producer status before consuming it.
# Keep this private scratch file separate from the not-yet-authorized output.
census=$(mktemp) || fail 'cannot retain Git worktrees'
trap 'rm -f "$census"' EXIT
git worktree list --porcelain -z > "$census" || fail 'cannot list Git worktrees'
record='' entry='' head_seen=false selector_seen=false bare_seen=false caller_seen=false
trees=()
while IFS= read -r -d '' record; do
  case "$record" in
    'worktree '*)
      [ -z "$entry" ] || fail 'worktree census has overlapping entries'
      entry=${record#worktree }
      [[ $entry == /* ]] || fail 'worktree census has an invalid path'
      for known in ${trees[@]+"${trees[@]}"}; do [ "$known" != "$entry" ] || fail 'worktree census repeats a path'; done
      trees+=("$entry")
      head_seen=false; selector_seen=false; bare_seen=false
      if tree=$(cd "$entry" 2>/dev/null && pwd -P && printf '.'); then
        tree=${tree%.}; tree=${tree%$'\n'}
      else tree=$entry; fi
      [ "$tree" != "$caller" ] || caller_seen=true
      case "$output/" in "$tree"/*) fail 'output must be outside every Git worktree' ;; esac ;;
    'HEAD '*)
      [[ -n $entry && $head_seen == false && $bare_seen == false && ${record#HEAD } =~ ^[0-9a-f]{40}$ ]] || fail 'invalid worktree HEAD observation'
      head_seen=true ;;
    'branch '*|detached)
      [[ -n $entry && $head_seen == true && $selector_seen == false && $bare_seen == false ]] || fail 'invalid worktree selector observation'
      if [[ $record == 'branch '* ]]; then [[ ${record#branch } == refs/heads/?* ]] || fail 'invalid worktree branch'; fi
      selector_seen=true ;;
    bare)
      [[ -n $entry && $head_seen == false && $selector_seen == false && $bare_seen == false ]] || fail 'invalid bare worktree observation'
      bare_seen=true ;;
    locked|'locked '*|prunable|'prunable '*)
      [[ -n $entry ]] || fail 'worktree metadata has no entry' ;;
    '')
      [[ -n $entry && ( $bare_seen == true || ( $head_seen == true && $selector_seen == true ) ) ]] || fail 'incomplete worktree entry'
      entry='' ;;
    *) fail 'unsupported worktree census record' ;;
  esac
done < "$census"
[[ -z $record ]] || fail 'unterminated record in Git worktree census'
[[ -z $entry && $caller_seen == true ]] || fail 'worktree census is incomplete or omits caller'
rm -f "$census"
trap - EXIT
if [ -e "$output" ] || [ -L "$output" ]; then fail 'output already exists'; fi
temp=$(mktemp -d /tmp/.marketplace-release.XXXXXX)
# Independent scratch may be deleted; an entered output is retained on failure
# for explicit recovery. Never recursively clean a mutable public pathname.
cleanup() {
  rm -rf "$temp"
}
trap cleanup EXIT
mkdir "$temp/data" "$temp/candidate"
# Read one unambiguous regular tracked manifest at the explicitly selected commit.
read_manifest() {
  local commit=$1 path=$2 destination=$3 mode
  mode=$(git ls-tree --full-tree "$commit" -- "$path")
  [[ "$mode" == '100644 blob '* || "$mode" == '100755 blob '* ]] || fail "manifest is not a regular tracked file: $path"
  git cat-file blob "$commit:$path" > "$destination"
  json_object_unique "$destination" || fail "ambiguous marketplace manifest: $path"
  jq -es -L "$here" 'include "marketplace-release"; length==1 and (.[0] | valid_marketplace)' "$destination" >/dev/null || fail "invalid marketplace manifest: $path"
}
# Require both marketplace adapter manifests at a commit to validate and agree.
read_pair() {
  local commit=$1 prefix=$2
  read_manifest "$commit" .github/plugin/marketplace.json "$temp/data/$prefix-copilot.json"
  read_manifest "$commit" .claude-plugin/marketplace.json "$temp/data/$prefix-claude.json"
  jq -n -e --slurpfile a "$temp/data/$prefix-copilot.json" --slurpfile b "$temp/data/$prefix-claude.json" '$a==$b' >/dev/null || fail 'marketplace manifests differ'
}
read_pair "$head" head
current=$(jq -r '.metadata.version' "$temp/data/head-copilot.json")
# One tag per line whatever column.tag says; the readers below expect exactly that.
git tag --list --no-column --format='%(refname:strip=2)' > "$temp/data/tags"
jq -Rn -L "$here" 'include "marketplace-release"; [inputs | select(startswith("v")) | select(.[1:] | stable_syntax)]' < "$temp/data/tags" > "$temp/data/stable-tags.json"
jq -e -L "$here" 'include "marketplace-release"; all(.[]; .[1:] | stable_version)' "$temp/data/stable-tags.json" >/dev/null || fail 'a stable tag exceeds the supported version range'
base=
if [ "$base_tag" = initial ]; then
  jq -e 'length==0' "$temp/data/stable-tags.json" >/dev/null || fail 'initial release requires no local stable marketplace tags'
  git rev-list --first-parent --reverse "$head" > "$temp/data/commits"
else
  base=$(git rev-parse --verify "refs/tags/$base_tag^{commit}") || fail 'base tag is missing'
  git rev-list --first-parent "$head" > "$temp/data/parents"
  grep -Fxq "$base" "$temp/data/parents" || fail 'base must be a first-parent ancestor of source'
  git tag --merged "$head" --no-column --format='%(refname:strip=2)' > "$temp/data/merged-tags"
  latest=$(jq -Rnr -L "$here" 'include "marketplace-release"; [inputs | select(startswith("v")) | select(.[1:] | stable_version)] | sort_by(.[1:] | split(".") | map(tonumber)) | last // ""' < "$temp/data/merged-tags")
  [ "$latest" = "$base_tag" ] || fail 'base is not the latest reachable stable marketplace tag'
  read_pair "$base" base
  [ "$(jq -r '.metadata.version' "$temp/data/base-copilot.json")" = "${base_tag#v}" ] || fail 'tag does not match baseline manifest version'
  [ "$current" = "${base_tag#v}" ] || fail 'source manifest version differs from baseline'
  git rev-list --first-parent --reverse "$base..$head" > "$temp/data/commits"
fi
: > "$temp/data/messages.jsonl"
while IFS= read -r sha; do
  git show -s --no-show-signature --encoding=UTF-8 --format=%B "$sha" > "$temp/data/message"
  jq -n --arg sha "$sha" --rawfile message "$temp/data/message" '{sha:$sha,message:$message}' >> "$temp/data/messages.jsonl"
done < "$temp/data/commits"
jq -e -L "$here" --arg source "$head" --arg base "$base" --arg baseTag "$base_tag" --arg current "$current" --slurpfile commits "$temp/data/messages.jsonl" \
  'include "marketplace-release"; prepare($source;$base;$baseTag;$current;$commits)' "$temp/data/head-copilot.json" > "$temp/candidate/release.json"
version=$(jq -r '.version // empty' "$temp/candidate/release.json")
if [ -n "$version" ]; then
  if git show-ref --verify --quiet "refs/tags/v$version"; then fail 'candidate tag already exists'; fi
  mkdir -p "$temp/candidate/.github/plugin" "$temp/candidate/.claude-plugin"
  jq --arg version "$version" '.metadata.version=$version' "$temp/data/head-copilot.json" > "$temp/candidate/.github/plugin/marketplace.json"
  cp "$temp/candidate/.github/plugin/marketplace.json" "$temp/candidate/.claude-plugin/marketplace.json"
fi
jq -r -L "$here" 'include "marketplace-release"; release_notes' "$temp/candidate/release.json" > "$temp/candidate/RELEASE_NOTES.md"
# Reserve the destination exclusively only after every source check and rendering step passed.
(
  cd "$parent" || fail 'cannot enter output parent; recovery retained'
  [[ $(directory_identity .) == "$parent_identity" && $(directory_identity "$parent") == "$parent_identity" ]] ||
    fail 'output parent moved before reservation; recovery retained'
  # Relative operands remain in the entered parent even if its public name moves.
  mkdir "./$name" || fail 'output was concurrently created'
  reserved=$(directory_identity "./$name") || fail 'cannot identify reserved output; recovery retained'
  [[ $reserved =~ ^[0-9]+:[0-9]+$ ]] || fail 'invalid reserved output identity; recovery retained'
  cd "./$name" || fail 'cannot enter reserved output; recovery retained'
  [[ $(directory_identity .) == "$reserved" && $(directory_identity "$output") == "$reserved" ]] ||
    fail 'reserved output moved before copy; recovery retained'
  # A replacement inserted before the first identity observation is not evidence
  # of an empty reservation. Retain a complete successful inventory before writing.
  find . -mindepth 1 -maxdepth 1 -print0 > "$temp/reservation-inventory" ||
    fail 'cannot inventory reserved output; recovery retained'
  [[ ! -s $temp/reservation-inventory ]] || fail 'reserved output contains unexpected data; recovery retained'
  cp -R "$temp/candidate/." . || fail 'copy failed; reserved output retained for recovery'
  # All readback stays relative to the entered directory even if its name moved.
  diff -r "$temp/candidate" . >/dev/null || fail 'candidate readback differs; recovery retained'
  status=$(jq -r .status ./release.json) || fail 'candidate status readback failed; recovery retained'
  [[ $status == CANDIDATE || $status == NO_RELEASE ]] || fail 'candidate status is invalid; recovery retained'
  [[ $(directory_identity "$parent") == "$parent_identity" && $(directory_identity "$output") == "$reserved" ]] ||
    fail 'reserved output or parent moved during copy; recovery retained'
  printf 'Prepared %s at %s\n' "$status" "$output"
)
