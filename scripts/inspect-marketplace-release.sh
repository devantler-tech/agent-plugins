#!/usr/bin/env bash
# Read-only historical content assessment, invoked by verify-marketplace-release.sh.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Stop inspection without exposing the private verifier's success result.
fail() { printf 'release inspection: %s\n' "$*" >&2; exit 1; }
[ "$#" -eq 3 ] || fail 'candidate, source and release are required'
candidate=$1 source=$2 release=$3
[[ "$source" =~ ^[0-9a-f]{40}$ && "$release" =~ ^[0-9a-f]{40}$ ]] || fail 'full source and release commits are required'
if [ ! -d "$candidate" ] || [ -L "$candidate" ]; then fail 'candidate must be a real directory'; fi
candidate=$(cd "$candidate" && pwd -P && printf '.')
candidate=${candidate%$'\n.'}
if [ ! -f "$candidate/release.json" ] || [ -L "$candidate/release.json" ]; then fail 'candidate plan must be a regular file'; fi
# No inherited layout or command-scoped configuration may redirect private ref writes.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
unset GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM
export GIT_NO_REPLACE_OBJECTS=1 GIT_NO_LAZY_FETCH=1
original=$(git rev-parse --show-toplevel && printf '.') || fail 'a Git working tree is required'
original=${original%$'\n.'}
original=$(cd "$original" && pwd -P && printf '.') || fail 'physical working tree is unavailable'
original=${original%$'\n.'}
temp=$(mktemp -d "${TMPDIR:-/tmp}/marketplace-inspect.XXXXXX")
trap 'rm -rf "$temp"' EXIT
# Check the original before cloning; a local clone need not retain these restrictions.
[ "$(git -C "$original" rev-parse --is-shallow-repository)" = false ] || fail 'complete Git history is required'
grafts=$(git -C "$original" rev-parse --path-format=absolute --git-path info/grafts)
[ ! -s "$grafts" ] || fail 'grafted history is unsupported'
# Observe the original configuration; the private clone does not retain it.
# shellcheck source=scripts/complete-clone.lib.sh
. "$here/complete-clone.lib.sh"
(cd "$original" && assert_complete_clone_config) || fail 'incomplete Git configuration; offline history is required'
for commit in "$source" "$release"; do
  [ "$(git -C "$original" cat-file -t "$commit")" = commit ] || fail 'selected commits must be available locally'
done
jq -es -L "$here" --arg source "$source" '
  include "marketplace-release";
  length == 1 and (.[0] | .schemaVersion==1 and .status=="CANDIDATE"
    and .sourceCommit==$source and .publication=="NOT_AUTHORIZED"
    and (.version | stable_version) and .tag==("v" + .version))
' "$candidate/release.json" >/dev/null || fail 'candidate plan does not match the selected source'
tag=$(jq -r .tag "$candidate/release.json")
git -C "$original" for-each-ref --sort=refname --format='%(refname) %(objectname)' refs/tags > "$temp/tags-before"
tag_oid=$(awk -v ref="refs/tags/$tag" '$1 == ref { print $2 }' "$temp/tags-before")
if [ -n "$tag_oid" ]; then
  [[ "$tag_oid" =~ ^[0-9a-f]{40}$ ]] || fail 'candidate tag inventory is invalid'
  tag_commit=$(git -C "$original" rev-parse --verify "$tag_oid^{commit}") || fail 'candidate tag does not resolve to a commit'
  jq -n --arg object "$tag_oid" --arg commit "$tag_commit" --arg release "$release" \
    '{state:"PRESENT",objectOid:$object,commitOid:$commit,targetsRelease:($commit==$release)}' > "$temp/local-tag.json"
else
  printf '%s\n' '{"state":"ABSENT","objectOid":null,"commitOid":null,"targetsRelease":null}' > "$temp/local-tag.json"
fi
# A separate local repository copies immutable objects, never the caller's refs or index.
# No checkout, network call or nominated source code is executed.
# Shared-clone alternates use line records and cannot retain every physical pathname.
git clone --no-hardlinks --no-checkout --quiet "$original" "$temp/repository"
private=$(cd "$temp/repository" && pwd -P)
[ "$(git -C "$private" rev-parse --show-toplevel)" = "$private" ] || fail 'private worktree layout is invalid'
[ "$(git -C "$private" rev-parse --path-format=absolute --git-common-dir)" = "$private/.git" ] || fail 'private Git directory is invalid'
if [ -n "$tag_oid" ]; then
  git -C "$private" update-ref -d "refs/tags/$tag" "$tag_oid" || fail 'candidate tag changed while cloning'
fi
# Reuse every strict byte, history, parent, tree and mode check. Capture its verdict
# privately: prepublication clearance from this disposable repository is never exposed.
(cd "$private" && bash "$here/verify-marketplace-release.sh" \
  --candidate "$candidate" --source "$source" --release "$release") > "$temp/verified.json"
git -C "$original" for-each-ref --sort=refname --format='%(refname) %(objectname)' refs/tags > "$temp/tags-after"
cmp -s "$temp/tags-before" "$temp/tags-after" || fail 'tag inventory changed during inspection'
jq -es --arg source "$source" --arg release "$release" --arg tag "$tag" '
  length==1 and (.[0] | .status=="VERIFIED" and .scope=="local-prepublication"
    and .sourceCommit==$source and .releaseCommit==$release and .tag==$tag)
' "$temp/verified.json" >/dev/null || fail 'strict verification result is invalid'
jq --slurpfile localTag "$temp/local-tag.json" '
  .status="INSPECTED" | .scope="local-historical-content" | .localTag=$localTag[0]
  | .proposal="NOT_AUTHORIZED" | .readiness="NOT_ASSESSED" | .remoteState="UNKNOWN"
' "$temp/verified.json"
