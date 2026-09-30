#!/usr/bin/env bash
# Reconstruct a current-main candidate; only explicit opt-in can create a signed draft proposal.
set -euo pipefail
export GIT_NO_REPLACE_OBJECTS=1
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Refuse incomplete or unsafe input without reporting a delivered proposal.
fail() { printf 'marketplace proposal: %s\n' "$*" >&2; exit 1; }
repo='' source='' ci='' output='' armed=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo|--source|--ci-run|--output)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then fail 'each option requires a value'; fi
      case "$1" in
        --repo) [ -z "$repo" ] || fail 'duplicate repo'; repo=$2;;
        --source) [ -z "$source" ] || fail 'duplicate source'; source=$2;;
        --ci-run) [ -z "$ci" ] || fail 'duplicate CI run'; ci=$2;;
        --output) [ -z "$output" ] || fail 'duplicate output'; output=$2;;
      esac
      shift 2;;
    --propose) [ "$armed" = false ] || fail 'duplicate opt-in'; armed=true; shift;;
    *) fail 'usage: propose-marketplace-release.sh --repo <owner/name> --source <full-main-commit> --ci-run <id|latest> --output <new-directory> [--propose]';;
  esac
done
[[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || fail 'explicit github.com repository is required'
[[ "$source" =~ ^[0-9a-f]{40}$ ]] || fail 'source must be a full commit'
[[ "$ci" = latest || "$ci" =~ ^[1-9][0-9]{0,14}$ ]] || fail 'CI run must be a positive integer or latest'
selection=$ci
if [ -z "$output" ] || [ -e "$output" ] || [ -L "$output" ]; then fail 'output must be new'; fi
temp=$(mktemp -d "${TMPDIR:-/tmp}/marketplace-proposal.XXXXXX")
attempted=false fetched_ref='' fetched_commit=''
# Never roll back a remote write: a failed response is not proof that nothing was created.
cleanup() {
  local code=$?
  if [ "$code" -ne 0 ] && [ "$attempted" = true ]; then
    printf 'Inspect proposal state in %s at refs/heads/%s; source=%s. No automatic retry or rollback.\n' "$repo" "$branch" "$source" >&2
  fi
  if [ -n "$fetched_ref" ] && [ -n "$fetched_commit" ]; then git update-ref -d "$fetched_ref" "$fetched_commit" || true; fi
  rm -rf "$temp"
}
trap cleanup EXIT
git for-each-ref --format='%(refname:strip=2) %(objectname)' refs/tags/ > "$temp/refs"
jq -Rn '[inputs|split(" ")|{name:.[0],oid:.[1]}]|sort_by(.name)' < "$temp/refs" > "$temp/tags"
base_tag=$(jq -er -L "$here" 'include "marketplace-release"; [.[]|.name|select(startswith("v"))|select(.[1:]|stable_version)]|sort_by(.[1:]|split(".")|map(tonumber))|last // error("published baseline required")' "$temp/tags")
bash "$here/prepare-marketplace-release.sh" --base-tag "$base_tag" --head "$source" --output "$output" > "$temp/preparation"
baseline=$(jq -c .baseline "$output/release.json")
tag=$(jq -r '.tag // .baseline.tag' "$output/release.json")
version=$(jq -r '.version // empty' "$output/release.json")
branch="automation/marketplace-$tag-$source"
git check-ref-format "refs/heads/$branch" || fail 'derived proposal branch is invalid'
# shellcheck disable=SC2016 # GraphQL variables are data supplied separately.
query='query($owner:String!,$name:String!,$baseline:String!,$tag:String!,$branch:String!,$endCursor:String) {
 viewer { login }
 repository(owner:$owner,name:$name) {
  id nameWithOwner isArchived viewerPermission defaultBranchRef { name target { __typename oid } }
  baseline:release(tagName:$baseline) { databaseId tagName isDraft isPrerelease publishedAt tagCommit { oid } }
  candidate:release(tagName:$tag) { databaseId }
  proposal:ref(qualifiedName:$branch) { name target { __typename oid } }
  refs(refPrefix:"refs/tags/",first:100,after:$endCursor,orderBy:{field:ALPHABETICAL,direction:ASC}) {
   totalCount nodes { name target { __typename oid } } pageInfo {hasNextPage endCursor}
  }
  pullRequests(states:OPEN,first:100) { totalCount nodes { number headRefName files(first:100) {totalCount nodes {path changeType}} } }
 }
}'
# Demand an exact successful main push run; the latest selector cannot search past a pending run.
ci_snapshot() {
  if [ "$selection" = latest ]; then
    gh api --hostname github.com "repos/$repo/actions/workflows/ci.yaml/runs?branch=main&event=push&head_sha=$source&per_page=1" > "$temp/latest"
    latest=$(jq -esr 'if length==1 and (.[0]|.total_count>0 and (.workflow_runs|length==1) and (.workflow_runs[0].id|type=="number" and .>0 and floor==.)) then .[0].workflow_runs[0].id else error("latest CI identity incomplete") end' "$temp/latest")
    if [ "$ci" = latest ]; then ci=$latest; else [ "$ci" = "$latest" ] || fail 'latest CI identity changed'; fi
  fi
  gh api --hostname github.com "repos/$repo/actions/runs/$ci" > "$temp/ci"
  jq -es --arg repo "$repo" --arg source "$source" --argjson ci "$ci" 'length==1 and (.[0]|.id==$ci and .path==".github/workflows/ci.yaml" and .event=="push" and .status=="completed" and .conclusion=="success" and .head_branch=="main" and .head_sha==$source and .repository.full_name==$repo and .head_repository.full_name==$repo)' "$temp/ci" >/dev/null || fail 'exact successful main CI is required'
}
# Refuse any local tag-object change since candidate preparation.
local_tags_unchanged() {
  git for-each-ref --format='%(refname:strip=2) %(objectname)' refs/tags/ > "$temp/current-refs"
  jq -Rn '[inputs|split(" ")|{name:.[0],oid:.[1]}]|sort_by(.name)' < "$temp/current-refs" > "$temp/current-tags"
  cmp -s "$temp/tags" "$temp/current-tags" || fail 'local tag objects changed during observation'
}
# Match the immutable candidate to fresh, complete local and remote tag inventories.
snapshot() {
  local owned=${1:-}
  local_tags_unchanged
  gh api --hostname github.com "repos/$repo" > "$temp/repo"
  gh api graphql --hostname github.com --paginate --slurp -f query="$query" -f owner="${repo%%/*}" -f name="${repo#*/}" -f baseline="$base_tag" -f tag="$(if [ -n "$version" ]; then printf '%s' "$tag"; else printf '%s' '__no_candidate__'; fi)" -f branch="refs/heads/$branch" > "$temp/pages"
  jq -es 'length==1 and (.[0]|type=="array")' "$temp/pages" >/dev/null || fail 'incomplete page stream'
  jq -e -L "$here" 'include "marketplace-proposal"; length>0 and all(.[]; .errors==null and (.data.repository.pullRequests|proposal_pr_inventory))' "$temp/pages" >/dev/null || fail 'complete PR file identities are required'
  jq -r '[.[].data.repository.pullRequests.nodes[]|select(any(.files.nodes[];.changeType=="RENAMED"))|.number]|unique|.[]' "$temp/pages" > "$temp/rename-requests"
  while IFS= read -r number; do
    gh api --hostname github.com --paginate --slurp "repos/$repo/pulls/$number/files?per_page=100" > "$temp/rename-files"
    jq -e -L "$here" --argjson number "$number" --slurpfile files "$temp/rename-files" 'include "marketplace-proposal"; proposal_rename_metadata($number;$files)' "$temp/pages" > "$temp/enriched-pages"
    mv "$temp/enriched-pages" "$temp/pages"
  done < "$temp/rename-requests"
  jq -e -L "$here" --arg repo "$repo" --arg source "$source" --argjson baseline "$baseline" --slurpfile tags "$temp/tags" --slurpfile permission "$temp/repo" --arg branch "$branch" --arg owned "$owned" 'include "marketplace-proposal"; proposal_snapshot($repo;$source;$baseline;$tags[0];$permission;$branch;$owned)' "$temp/pages"
  local_tags_unchanged
  ci_snapshot
}
snapshot > "$temp/before"
bash "$here/prepare-marketplace-release.sh" --base-tag "$base_tag" --head "$source" --output "$temp/reproduced" > "$temp/reproduction"
diff -r "$output" "$temp/reproduced" >/dev/null || fail 'candidate changed during reconstruction'
snapshot > "$temp/after"
cmp -s "$temp/before" "$temp/after" || fail 'remote state changed during preparation'
if [ -z "$version" ]; then
  jq -n --arg source "$source" --argjson ci "$ci" '{status:"NO_CHANGE",authority:"assessment-only",sourceCommit:$source,ciRunId:$ci,proposal:"NOT_AUTHORIZED",publication:"NOT_AUTHORIZED"}'
  exit 0
fi
if [ "$armed" = false ]; then
  jq -n --arg source "$source" --arg version "$version" --arg branch "$branch" --argjson ci "$ci" '{status:"PREPARED",authority:"assessment-only",candidateReleaseVisibility:"READER_PROJECTION",sourceCommit:$source,version:$version,branch:$branch,ciRunId:$ci,proposal:"NOT_AUTHORIZED",publication:"NOT_AUTHORIZED"}'
  exit 0
fi
# Repeat positive native capability and its identity bind at every remote write phase.
writer_proof() {
  jq -e 'all(.[]; .data.viewer.login=="github-actions[bot]")' "$temp/pages" >/dev/null || fail 'proposal writer must be the native Actions bot'
  jq -e -L "$here" 'include "marketplace-permissions"; all(.[]; .data.repository|compatible_user_role)' "$temp/pages" >/dev/null || fail 'writer role projection is missing or incompatible'
  jq -n --arg tag "$tag" --arg source "$source" '{tag_name:$tag,target_commitish:$source}' > "$temp/proof-request"
  gh api --hostname github.com --method POST "repos/$repo/releases/generate-notes" --input "$temp/proof-request" > "$temp/proof"
  jq -es -L "$here" --arg repo "$repo" --slurpfile permission "$temp/repo" --slurpfile observation "$temp/before" 'include "marketplace-permissions"; .[0] as $proof | length==1 and ($permission|length==1) and ($permission[0]|native_writer_repository($repo;"main";$observation[0].repositoryId;$proof))' "$temp/proof" >/dev/null || fail 'native contents-write capability is unproven'
}
snapshot > "$temp/prewrite"
cmp -s "$temp/before" "$temp/prewrite" || fail 'remote state changed before creation'
writer_proof
jq -n --arg branch "$branch" --arg source "$source" '{ref:("refs/heads/"+$branch),sha:$source}' > "$temp/ref-request"
attempted=true
gh api --hostname github.com --method POST "repos/$repo/git/refs" --input "$temp/ref-request" > "$temp/ref-response"
jq -es --arg branch "$branch" --arg source "$source" 'length==1 and (.[0]|.ref==("refs/heads/"+$branch) and .object.type=="commit" and .object.sha==$source)' "$temp/ref-response" >/dev/null || fail 'branch reservation readback failed'
snapshot "$source" > "$temp/reserved"
cmp -s "$temp/before" "$temp/reserved" || fail 'remote state changed after branch reservation'
writer_proof
title="chore(release): prepare marketplace $version"
# GitHub signs this mutation. Expected parent and the two fixed paths bound its authority.
# shellcheck disable=SC2016 # GraphQL variables remain literal and are supplied as JSON data.
mutation='mutation($input:CreateCommitOnBranchInput!) { createCommitOnBranch(input:$input) { commit { oid signature {isValid state} } } }'
jq -n --arg query "$mutation" --arg repo "$repo" --arg branch "$branch" --arg source "$source" --arg title "$title" --rawfile a "$temp/reproduced/.github/plugin/marketplace.json" --rawfile b "$temp/reproduced/.claude-plugin/marketplace.json" '{query:$query,variables:{input:{branch:{repositoryNameWithOwner:$repo,branchName:$branch},expectedHeadOid:$source,message:{headline:$title},fileChanges:{additions:[{path:".github/plugin/marketplace.json",contents:($a|@base64)},{path:".claude-plugin/marketplace.json",contents:($b|@base64)}]}}}}' > "$temp/commit-request"
gh api graphql --hostname github.com --method POST --input "$temp/commit-request" > "$temp/commit-response"
commit=$(jq -esr 'if length==1 and (.[0]|.errors==null and (.data.createCommitOnBranch.commit|(.oid|test("^[0-9a-f]{40}$")) and .signature.isValid==true and .signature.state=="VALID")) then .[0].data.createCommitOnBranch.commit.oid else error("signed commit response missing") end' "$temp/commit-response")
gh api --hostname github.com "repos/$repo/commits/$commit" > "$temp/commit-readback"
jq -es --arg commit "$commit" 'length==1 and (.[0]|.sha==$commit and .commit.verification.verified==true and .commit.verification.reason=="valid")' "$temp/commit-readback" >/dev/null || fail 'independent signature readback failed'
fetched_ref="refs/marketplace-proposal/$(basename "$temp")"
git -c credential.helper= -c 'credential.helper=!gh auth git-credential' fetch --no-write-fetch-head "https://github.com/$repo.git" "+refs/heads/$branch:$fetched_ref" >&2
fetched_commit=$(git rev-parse "$fetched_ref")
[ "$fetched_commit" = "$commit" ] || fail 'fetched branch differs from signed response'
bash "$here/verify-marketplace-release.sh" --candidate "$temp/reproduced" --source "$source" --release "$commit" > "$temp/verified"
snapshot "$commit" > "$temp/committed"
cmp -s "$temp/before" "$temp/committed" || fail 'remote state changed before draft creation'
writer_proof
printf '> 🤖 Generated by the Agentic Engineer\n\n## Why\n\nConsumers need a named marketplace version they can install and return to.\n\n## What\n\nPrepare the next marketplace release while keeping individual plugin versions independent. Review and publication remain separate steps.\n\nPart of #101\n' > "$temp/body"
jq -n --arg title "$title" --arg branch "$branch" --rawfile body "$temp/body" '{title:$title,head:$branch,base:"main",draft:true,body:$body}' > "$temp/pr-request"
gh api --hostname github.com --method POST "repos/$repo/pulls" --input "$temp/pr-request" > "$temp/pr-response"
number=$(jq -esr 'if length==1 and (.[0].number|type=="number" and .>0 and floor==.) then .[0].number else error("draft identity missing") end' "$temp/pr-response")
# shellcheck disable=SC2016 # GraphQL variables remain literal and are supplied separately.
readback='query($owner:String!,$name:String!,$branch:String!,$number:Int!) { repository(owner:$owner,name:$name) { id nameWithOwner isArchived defaultBranchRef {name target {oid}} ref(qualifiedName:$branch) {name target {oid}} pullRequest(number:$number) {number state isDraft author {login} headRefName headRefOid baseRefName baseRefOid headRepository {nameWithOwner} url title body} } }'
gh api graphql --hostname github.com -f query="$readback" -f owner="${repo%%/*}" -f name="${repo#*/}" -f branch="refs/heads/$branch" -F number="$number" > "$temp/pr-readback"
jq -es -L "$here" --arg repo "$repo" --arg node "$(jq -r .repositoryId "$temp/before")" --arg source "$source" --arg branch "$branch" --arg commit "$commit" --argjson number "$number" --arg title "$title" --rawfile body "$temp/body" 'include "marketplace-proposal"; length==1 and (.[0]|proposal_readback($repo;$node;$source;$branch;$commit;$number;$title;$body))' "$temp/pr-readback" >/dev/null || fail 'exact draft readback failed'
jq -n --arg repo "$repo" --arg source "$source" --arg commit "$commit" --arg branch "$branch" --arg version "$version" --argjson number "$number" --argjson ci "$ci" '{status:"CREATED",sourceCommit:$source,proposalCommit:$commit,branch:$branch,version:$version,proposalNumber:$number,url:("https://github.com/"+$repo+"/pull/"+($number|tostring)),ciRunId:$ci,proposal:"DRAFT_READBACK_VERIFIED",publication:"NOT_AUTHORIZED"}'
