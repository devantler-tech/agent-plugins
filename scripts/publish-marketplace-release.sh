#!/usr/bin/env bash
# Manual, create-only publication. Without --publish this only assesses the candidate.
set -euo pipefail
export GIT_NO_REPLACE_OBJECTS=1
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/json-object.lib.sh
. "$here/json-object.lib.sh"
# Report a validation failure on stderr and stop without a success assessment.
fail() { printf 'marketplace publication: %s\n' "$*" >&2; exit 1; }
# Describe the safe default and the explicit write operation.
usage() {
  printf 'usage: publish-marketplace-release.sh --repo <owner/name> --candidate <directory> --source <full-commit> --release <full-commit> [--publish]\n'
  printf 'Default: read-only assessment. --publish explicitly creates a tag and a published release. Establish CI and review readiness independently first.\n'
}
repo='' candidate='' source='' release='' publish=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo|--candidate|--source|--release)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then fail 'each option requires a value'; fi
      case "$1" in
        --repo) [ -z "$repo" ] || fail 'duplicate repo'; repo=$2 ;;
        --candidate) [ -z "$candidate" ] || fail 'duplicate candidate'; candidate=$2 ;;
        --source) [ -z "$source" ] || fail 'duplicate source'; source=$2 ;;
        --release) [ -z "$release" ] || fail 'duplicate release'; release=$2 ;;
      esac
      shift 2 ;;
    --publish) [ "$publish" = false ] || fail 'duplicate publish'; publish=true; shift ;;
    --help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || fail 'repo must be an explicit github.com owner/name'
temp=$(mktemp -d "${TMPDIR:-/tmp}/marketplace-publish.XXXXXX")
write_attempted=false
# Remove private artifacts; on a failed write, identify remote state needing inspection.
cleanup() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$write_attempted" = true ]; then
    printf 'marketplace publication: remote objects may exist for %s %s at %s; inspect them before recovery. No overwrite, rollback or write retry was attempted.\n' "$repo" "$tag" "$release" >&2
  fi
  rm -rf "$temp"
}
trap cleanup EXIT
# Validate the supplied artifact before the network, then freeze its content by regeneration.
# Never read the caller's mutable files again after this verification.
bash "$here/verify-marketplace-release.sh" --candidate "$candidate" --source "$source" --release "$release" > "$temp/local"
base=$(jq -r '.baseline.tag // "initial"' "$temp/local")
bash "$here/prepare-marketplace-release.sh" --base-tag "$base" --head "$source" --output "$temp/candidate" > "$temp/preparation.log"
bash "$here/verify-marketplace-release.sh" --candidate "$temp/candidate" --source "$source" --release "$release" > "$temp/frozen-local"
cmp -s "$temp/local" "$temp/frozen-local" || fail 'candidate changed while freezing verified Git objects'
bash "$here/check-marketplace-release-remote.sh" --repo "$repo" --candidate "$temp/candidate" --source "$source" --release "$release" > "$temp/assessment"
if [ "$publish" = false ]; then cat "$temp/assessment"; exit 0; fi
tag=$(jq -er '.tag' "$temp/assessment")
branch=$(jq -er '.defaultBranch' "$temp/assessment")
node=$(jq -er '.repositoryId' "$temp/assessment")
jq -n --arg tag "$tag" --arg release "$release" '{tag_name:$tag,target_commitish:$release}' > "$temp/writer-request"
jq -r -L "$here" --arg release "$release" 'include "marketplace-publication"; publication_notes($release)' "$temp/candidate/release.json" > "$temp/notes"
jq -n --arg tag "$tag" --arg release "$release" '{ref:("refs/tags/"+$tag),sha:$release}' > "$temp/tag-request"
jq -n --arg tag "$tag" --arg release "$release" --rawfile notes "$temp/notes" \
  '{tag_name:$tag,target_commitish:$release,name:$tag,body:$notes,draft:false,prerelease:false,generate_release_notes:false,make_latest:"legacy"}' > "$temp/release-request"
# shellcheck disable=SC2016 # GraphQL values are separate data, never interpolated query text.
query='query($owner:String!,$name:String!,$tag:String!,$qualifiedRef:String!) {
  repository(owner:$owner,name:$name) {
    id nameWithOwner isArchived viewerPermission defaultBranchRef { name target { __typename oid } }
    ref(qualifiedName:$qualifiedRef) { prefix name target { __typename oid } }
    release(tagName:$tag) { databaseId tagName isDraft isPrerelease name description publishedAt url tagCommit { oid } }
  }
}'
release_id=0
# Read and validate one publication phase against the frozen repository and release identities.
snapshot() {
  gh api --hostname github.com "repos/$repo" > "$temp/permission"
  json_object_unique "$temp/permission" || fail 'ambiguous repository observation'
  gh api --hostname github.com --method POST "repos/$repo/releases/generate-notes" \
    --input "$temp/writer-request" > "$temp/writer"
  json_object_unique "$temp/writer" || fail 'ambiguous writer capability observation'
  gh api graphql --hostname github.com -f query="$query" -f owner="${repo%%/*}" -f name="${repo#*/}" \
    -f tag="$tag" -f qualifiedRef="refs/tags/$tag" > "$temp/snapshot"
  json_object_unique "$temp/snapshot" || fail "ambiguous $1 publication observation"
  jq -es -L "$here" --arg phase "$1" --arg repo "$repo" --arg release "$release" --arg tag "$tag" \
    --arg node "$node" --arg branch "$branch" --argjson id "$release_id" --rawfile notes "$temp/notes" \
    --slurpfile permission "$temp/permission" \
    --slurpfile writer "$temp/writer" \
    'include "marketplace-publication"; length==1 and ($permission|length)==1 and ($writer|length)==1 and
      (.[0] | publication_snapshot($phase;$repo;$node;$branch;$tag;$release;$id;$notes;$permission[0];$writer[0]))' \
    "$temp/snapshot" >/dev/null || fail "invalid $1 readback; repository, branch, tag or release changed"
}
snapshot absent
# Each write is attempted once. A transport error can mean it succeeded remotely.
write_attempted=true
gh api --hostname github.com --method POST "repos/$repo/git/refs" --input "$temp/tag-request" > "$temp/created-tag"
json_object_unique "$temp/created-tag" || fail 'ambiguous tag creation response'
jq -es --arg tag "$tag" --arg release "$release" 'length==1 and (.[0] | .ref==("refs/tags/"+$tag) and .object.type=="commit" and .object.sha==$release)' \
  "$temp/created-tag" >/dev/null || fail 'invalid tag creation response'
snapshot reserved
gh api --hostname github.com --method POST "repos/$repo/releases" --input "$temp/release-request" > "$temp/created-release"
json_object_unique "$temp/created-release" || fail 'ambiguous release creation response'
jq -es --arg repo "$repo" --arg tag "$tag" --arg release "$release" --rawfile notes "$temp/notes" \
  'length==1 and (.[0] | (.id|type=="number" and .>0 and floor==.) and .tag_name==$tag and .target_commitish==$release
    and .name==$tag and .body==$notes and .draft==false and .prerelease==false
    and (.published_at|type=="string" and length>0) and .html_url==("https://github.com/"+$repo+"/releases/tag/"+$tag))' \
  "$temp/created-release" >/dev/null || fail 'invalid release creation response'
release_id=$(jq -er '.id' "$temp/created-release")
snapshot published
jq -n --arg repo "$repo" --arg tag "$tag" --arg source "$source" --arg release "$release" --argjson id "$release_id" \
  '{schemaVersion:1,status:"PUBLISHED",publication:"PUBLISHED",scope:"remote-publication-readback",repository:$repo,
    tag:$tag,sourceCommit:$source,releaseCommit:$release,releaseId:$id,url:("https://github.com/"+$repo+"/releases/tag/"+$tag)}'
