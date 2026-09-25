#!/usr/bin/env bash
# Prepare immutable, offline review artifacts. No checkout, ref, or remote writes.
set -euo pipefail
export GIT_NO_REPLACE_OBJECTS=1
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail() { printf 'release preparation: %s\n' "$*" >&2; exit 1; }
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
[ -z "$(git config --get extensions.partialClone || true)" ] || fail 'partial clones are unsupported: every object must be local'
while IFS= read -r promisor; do
  [ "${promisor##* }" != true ] || fail 'partial clones are unsupported: every object must be local'
done < <(git config --type=bool --get-regexp '^remote\..*\.promisor$' || true)
if [ -z "$head" ]; then head=$(git rev-parse --verify HEAD); fi
[[ "$head" =~ ^[0-9a-f]{40}$ ]] || fail 'head must be a full 40-character commit'
[ "$(git cat-file -t "$head")" = commit ] || fail 'head must identify a commit'
parent=$(cd "$(dirname "$output")" && pwd -P) || fail 'output parent must exist'
name=$(basename "$output")
[[ "$name" != . && "$name" != .. && "$name" != / ]] || fail 'output must name a new directory'
output="$parent/$name"
git rev-parse --show-toplevel >/dev/null || fail 'must run inside a Git worktree'
# Every worktree of the repository is a checkout, linked ones included.
git worktree list --porcelain -z >/dev/null || fail 'cannot list Git worktrees'
while IFS= read -r -d '' record; do
  [[ "$record" == 'worktree '* ]] || continue
  tree=$(cd "${record#worktree }" 2>/dev/null && pwd -P) || tree=${record#worktree }
  case "$output/" in "$tree"/*) fail 'output must be outside every Git worktree' ;; esac
done < <(git worktree list --porcelain -z)
if [ -e "$output" ] || [ -L "$output" ]; then fail 'output already exists'; fi
temp=$(mktemp -d "$parent/.marketplace-release.XXXXXX")
owned_output=false
cleanup() {
  rm -rf "$temp"
  if [ "$owned_output" = true ]; then rm -rf "$output"; fi
}
trap cleanup EXIT
mkdir "$temp/data" "$temp/candidate"
read_manifest() {
  local commit=$1 path=$2 destination=$3 mode
  mode=$(git ls-tree "$commit" -- "$path")
  [[ "$mode" == '100644 blob '* || "$mode" == '100755 blob '* ]] || fail "manifest is not a regular tracked file: $path"
  git cat-file blob "$commit:$path" > "$destination"
  jq -es -L "$here" 'include "marketplace-release"; length==1 and (.[0] | valid_marketplace)' "$destination" >/dev/null || fail "invalid marketplace manifest: $path"
}
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
mkdir "$output" || fail 'output was concurrently created'
owned_output=true
cp -R "$temp/candidate/." "$output/"
owned_output=false
printf 'Prepared %s at %s\n' "$(jq -r .status "$output/release.json")" "$output"
