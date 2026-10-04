#!/usr/bin/env bash
# Verify marketplace version proposals before merge without changing any Git state.
set -euo pipefail
export GIT_NO_REPLACE_OBJECTS=1 GIT_NO_LAZY_FETCH=1
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/marketplace-git-context.lib.sh
. "$here/marketplace-git-context.lib.sh"
marketplace_git_context
# Refuse incomplete evidence without emitting a success record.
fail() { printf 'marketplace version gate: %s\n' "$*" >&2; exit 1; }
[ "$#" -eq 2 ] || fail 'usage: check-marketplace-version.sh <full-base-commit> <full-head-commit>'
base=$1 head=$2
[[ "$base" =~ ^[0-9a-f]{40}$ && "$head" =~ ^[0-9a-f]{40}$ ]] || fail 'base and head must be full 40-character commits'
[ "$(git rev-parse --is-shallow-repository)" = false ] || fail 'complete Git history is required'
grafts=$(git rev-parse --git-path info/grafts) || fail 'graft path is unreadable'
[ -n "$grafts" ] || fail 'graft path is empty'
[ ! -s "$grafts" ] || fail 'grafted history is unsupported'
# shellcheck source=scripts/complete-clone.lib.sh
. "$here/complete-clone.lib.sh"
assert_complete_clone_config || fail 'incomplete Git configuration; offline history is required'
for commit in "$base" "$head"; do
  [ "$(git cat-file -t "$commit")" = commit ] || fail 'base and head must identify commits'
done
fork=$(git merge-base --all "$base" "$head") || fail 'base and head have no common ancestor'
[[ "$fork" =~ ^[0-9a-f]{40}$ ]] || fail 'a unique merge base is required'
temp=$(mktemp -d "${TMPDIR:-/tmp}/marketplace-version.XXXXXX")
trap 'rm -rf "$temp"' EXIT
# Read both regular committed manifests and reject ambiguous version evidence.
version_at() {
  local commit=$1 path mode n=0
  for path in .github/plugin/marketplace.json .claude-plugin/marketplace.json; do
    n=$((n+1))
    mode=$(git ls-tree "$commit" -- "$path")
    [[ "$mode" == '100644 blob '* || "$mode" == '100755 blob '* ]] || fail "manifest is not a regular tracked file: $path"
    git cat-file blob "$commit:$path" > "$temp/manifest-$n.json"
    jq -es -L "$here" 'include "marketplace-release"; length==1 and (.[0] | valid_marketplace)' "$temp/manifest-$n.json" >/dev/null || fail "invalid marketplace manifest: $path"
    # Streaming retains repeated keys that ordinary JSON parsing collapses.
    jq --stream -s -e '[.[] | select(length==2 and .[0]==["metadata","version"])] | length==1' "$temp/manifest-$n.json" >/dev/null || fail 'marketplace version is ambiguous'
  done
  jq -ne --slurpfile a "$temp/manifest-1.json" --slurpfile b "$temp/manifest-2.json" '$a==$b' >/dev/null || fail 'marketplace manifests differ'
  jq -r '.metadata.version' "$temp/manifest-1.json"
}
fork_version=$(version_at "$fork")
head_version=$(version_at "$head")
# Compare branch intent, not changes that landed only on its base. An ordinary old
# PR must remain valid when another PR released the marketplace after it branched.
if [ "$fork_version" = "$head_version" ]; then
  jq -n --arg base "$base" --arg head "$head" --arg fork "$fork" \
    '{status:"NO_VERSION_CHANGE",scope:"branch-marketplace-version",baseCommit:$base,headCommit:$head,mergeBase:$fork,publication:"NOT_AUTHORIZED"}'
  exit 0
fi
[ "$(git show -s --no-show-signature --format=%P "$head")" = "$base" ] || fail 'version proposal must have exactly the current base as its only parent; regenerate from the current base'
base_version=$(version_at "$base")
# Preparation and verification are the shared release contract, not a second
# SemVer implementation. Keep their diagnostics off the structured result stream.
bash "$here/prepare-marketplace-release.sh" --base-tag "v$base_version" --head "$base" --output "$temp/candidate" > "$temp/preparation.log"
bash "$here/verify-marketplace-release.sh" --candidate "$temp/candidate" --source "$base" --release "$head"
