#!/usr/bin/env bash
# Read-only prepublication snapshot. This does not reserve a tag or authorize publication.
set -euo pipefail
export GIT_NO_REPLACE_OBJECTS=1
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/json-object.lib.sh
. "$here/json-object.lib.sh"
# Stop without emitting a successful remote assessment.
fail() { printf 'remote release assessment: %s\n' "$*" >&2; exit 1; }
# Describe the candidate and exact source/release commit selectors.
usage() { printf 'usage: check-marketplace-release-remote.sh --repo <owner/name> --candidate <directory> --source <full-commit> --release <full-commit>\n'; }
repo='' candidate='' source='' release=''
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
    --help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || fail 'repo must be an explicit github.com owner/name'
[[ "$source" =~ ^[0-9a-f]{40}$ && "$release" =~ ^[0-9a-f]{40}$ ]] || fail 'source and release must be full commits'
[ -n "$candidate" ] || fail 'candidate is required'
temp=$(mktemp -d "${TMPDIR:-/tmp}/marketplace-remote.XXXXXX")
trap 'rm -rf "$temp"' EXIT
# Regenerate and validate the complete local candidate against exact Git objects.
verify() {
  bash "$here/verify-marketplace-release.sh" --candidate "$candidate" --source "$source" --release "$release"
}
# Validate before contacting the forge, including artifact types and all candidate bytes.
verify > "$temp/assessment"
tag=$(jq -er '.tag' "$temp/assessment")
jq -n --arg tag "$tag" --arg release "$release" '{tag_name:$tag,target_commitish:$release}' > "$temp/writer-request"
# shellcheck disable=SC2016 # GraphQL variables are passed separately as data.
query='query($owner:String!,$name:String!,$tag:String!,$endCursor:String) {
  repository(owner:$owner,name:$name) {
    id nameWithOwner isArchived viewerPermission defaultBranchRef { name target { __typename oid } }
    release(tagName:$tag) { tagName isDraft isPrerelease }
    refs(refPrefix:"refs/tags/",first:100,after:$endCursor,orderBy:{field:ALPHABETICAL,direction:ASC}) {
      totalCount pageInfo { hasNextPage endCursor } nodes { name target { __typename oid } }
    }
  }
}'
# Capture every local tag object so missing or stale refs cannot establish absence.
local_tags() {
  git for-each-ref --format='%(refname:strip=2) %(objectname)' refs/tags/ > "$temp/local-refs"
  jq -Rn '[inputs | split(" ") | {name:.[0],oid:.[1]}] | sort_by(.name)' < "$temp/local-refs"
}
# Read positive writer capability and complete remote state without creating objects.
remote_snapshot() {
  # Bind repository identity and positively exercise contents-write without saving notes.
  gh api --hostname github.com "repos/$repo" > "$temp/permission"
  json_object_unique "$temp/permission" || fail 'ambiguous repository observation'
  gh api --hostname github.com --method POST "repos/$repo/releases/generate-notes" \
    --input "$temp/writer-request" > "$temp/writer"
  json_object_unique "$temp/writer" || fail 'ambiguous writer capability observation'
  # Variables remain data; neither candidate content nor configured Git transports choose the host.
  gh api graphql --hostname github.com --paginate --slurp -f query="$query" \
    -f owner="${repo%%/*}" -f name="${repo#*/}" -f tag="$tag" > "$temp/pages"
  json_value_unique "$temp/pages" || fail 'ambiguous remote page observation'
  # --slurp must return exactly one array. Do not accept trailing JSON or a partial API result.
  jq -es 'length == 1 and (.[0] | type == "array")' "$temp/pages" >/dev/null || fail 'invalid page stream'
  jq -e -L "$here" --arg repo "$repo" --arg release "$release" --slurpfile permission "$temp/permission" \
    --slurpfile writer "$temp/writer" \
    -f "$here/marketplace-remote-state.jq" "$temp/pages" > "$temp/remote"
  jq -r '.tags[].name' "$temp/remote" > "$temp/tag-names"
  while IFS= read -r name; do
    git check-ref-format "refs/tags/$name" || fail 'invalid remote tag name'
    [ "$name" != "$tag" ] || fail 'candidate tag is already reserved remotely'
  done < "$temp/tag-names"
  jq '.tags' "$temp/remote" > "$temp/remote-tags"
  cmp -s "$temp/local-tags" "$temp/remote-tags" || fail 'local and remote tags differ; refresh in an isolated clone'
  cat "$temp/remote"
}
local_tags > "$temp/local-tags"
remote_snapshot > "$temp/before"
verify > "$temp/reassessment"
cmp -s "$temp/assessment" "$temp/reassessment" || fail 'local assessment changed'
remote_snapshot > "$temp/after"
cmp -s "$temp/before" "$temp/after" || fail 'remote state changed during assessment'
local_tags > "$temp/final-local-tags"
cmp -s "$temp/local-tags" "$temp/final-local-tags" || fail 'local tags changed during assessment'
jq --slurpfile remote "$temp/after" '. + {repository:$remote[0].repository,
  repositoryId:$remote[0].repositoryId,defaultBranch:$remote[0].defaultBranch,remoteTags:$remote[0].tags,candidateRelease:"ABSENT",
  scope:"remote-prepublication-snapshot"}' "$temp/reassessment"
