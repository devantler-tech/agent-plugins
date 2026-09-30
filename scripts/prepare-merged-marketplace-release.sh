#!/usr/bin/env bash
# Reconstruct a merged version proposal only with exact successful main CI evidence.
set -euo pipefail
export GIT_NO_REPLACE_OBJECTS=1
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Never emit a ready record for incomplete or conflicting evidence.
fail() { printf 'merged marketplace preparation: %s\n' "$*" >&2; exit 1; }
repo='' release='' ci='' output=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo|--release|--ci-run|--output)
      [ "$#" -ge 2 ] && [ -n "$2" ] || fail 'each option requires a value'
      case "$1" in
        --repo) [ -z "$repo" ] || fail 'duplicate repo'; repo=$2 ;;
        --release) [ -z "$release" ] || fail 'duplicate release'; release=$2 ;;
        --ci-run) [ -z "$ci" ] || fail 'duplicate CI run'; ci=$2 ;;
        --output) [ -z "$output" ] || fail 'duplicate output'; output=$2 ;;
      esac
      shift 2 ;;
    *) fail 'usage: prepare-merged-marketplace-release.sh --repo <owner/name> --release <full-commit> --ci-run <id> --output <new-directory>' ;;
  esac
done
[[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || fail 'repo must be an explicit github.com owner/name'
[[ "$release" =~ ^[0-9a-f]{40}$ ]] || fail 'release must be a full 40-character commit'
[[ "$ci" =~ ^[1-9][0-9]{0,14}$ ]] || fail 'CI run must be a positive integer'
[ -n "$output" ] && [ ! -e "$output" ] && [ ! -L "$output" ] || fail 'output must be a new directory'
[ "$(git cat-file -t "$release")" = commit ] || fail 'release must identify a commit'
[ "$(git rev-parse HEAD)" = "$release" ] || fail 'checkout must be the selected current main commit'
source=$(git show -s --no-show-signature --format=%P "$release")
[[ "$source" =~ ^[0-9a-f]{40}$ ]] || fail 'merged proposal must have exactly one parent'
temp=$(mktemp -d "${TMPDIR:-/tmp}/marketplace-merged.XXXXXX")
created=false
# Remove only this invocation's fresh candidate on a refusal; preserve existing paths.
cleanup() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$created" = true ]; then rm -rf "$output"; fi
  rm -rf "$temp"
}
trap cleanup EXIT
# Read native repository, ref and workflow-run identities, never caller artifacts or checkout URLs.
snapshot() {
  gh api --hostname github.com "repos/$repo" > "$temp/repo"
  jq -es --arg repo "$repo" 'length==1 and (.[0] | .full_name==$repo and .archived==false and .default_branch=="main")' "$temp/repo" >/dev/null || fail 'repository identity, archive state or default branch is invalid'
  gh api --hostname github.com "repos/$repo/git/ref/heads/main" > "$temp/ref"
  jq -es --arg release "$release" 'length==1 and (.[0] | .ref=="refs/heads/main" and .object.type=="commit" and .object.sha==$release)' "$temp/ref" >/dev/null || fail 'remote main is not the selected release commit'
  gh api --hostname github.com "repos/$repo/actions/runs/$ci" > "$temp/run"
  jq -es --arg repo "$repo" --arg release "$release" --argjson ci "$ci" '
    length==1 and (.[0] | .id==$ci and .path==".github/workflows/ci.yaml" and .event=="push"
      and .status=="completed" and .conclusion=="success" and .head_branch=="main" and .head_sha==$release
      and .repository.full_name==$repo and .head_repository.full_name==$repo)' "$temp/run" >/dev/null || fail 'CI must be the exact successful main push run of the repository CI workflow'
}
snapshot
bash "$here/check-marketplace-version.sh" "$source" "$release" > "$temp/gate"
status=$(jq -er '.status' "$temp/gate")
if [ "$status" = VERIFIED ]; then
  base=$(jq -er '.baseline.tag' "$temp/gate")
  bash "$here/prepare-marketplace-release.sh" --base-tag "$base" --head "$source" --output "$output" > "$temp/preparation.log"
  created=true
  bash "$here/verify-marketplace-release.sh" --candidate "$output" --source "$source" --release "$release" > "$temp/verified"
  cmp -s "$temp/gate" "$temp/verified" || fail 'regenerated candidate differs from the verified merged proposal'
elif [ "$status" != NO_VERSION_CHANGE ]; then
  fail 'unexpected marketplace version result'
fi
snapshot
if [ "$status" = VERIFIED ]; then
  jq --argjson ci "$ci" '.+{ciRunId:$ci,scope:"merged-marketplace-proposal-with-ci",publication:"NOT_AUTHORIZED"}' "$temp/verified"
else
  jq -n --arg release "$release" --argjson ci "$ci" '{status:"NO_VERSION_CHANGE",releaseCommit:$release,ciRunId:$ci,publication:"NOT_AUTHORIZED"}'
fi
