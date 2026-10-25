#!/usr/bin/env bash
# agent-plugins#603: publish generated metadata with an App-signed, head-fenced commit.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/marketplace-git-context.lib.sh
. "$here/marketplace-git-context.lib.sh"
marketplace_git_context
# shellcheck source=scripts/json-object.lib.sh
. "$here/json-object.lib.sh"

# Refuse an incomplete observation without claiming publication or retrying an uncertain write.
fail() {
  printf 'skill metadata: %s\n' "$*" >&2
  exit 1
}
repo_dir='' skill='' branch=''
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] && [ -n "$2" ] || fail 'each option requires one value'
  case "$1" in
  --repo-dir)
    [ -z "$repo_dir" ] || fail 'duplicate repository directory'
    repo_dir=$2
    ;;
  --skill-path)
    [ -z "$skill" ] || fail 'duplicate skill path'
    skill=$2
    ;;
  --branch)
    [ -z "$branch" ] || fail 'duplicate branch'
    branch=$2
    ;;
  *) fail 'usage: --repo-dir <checkout> --skill-path <plugins/name/skills/name> --branch <canonical-updater-branch>' ;;
  esac
  shift 2
done
[[ "$skill" =~ ^plugins/([a-z0-9][a-z0-9-]*)/skills/([a-z0-9][a-z0-9-]*)$ ]] || fail 'invalid skill scope'
plugin=${BASH_REMATCH[1]}
slug=${skill#plugins/}
slug=${slug//\//-}
[ "$branch" = "deps/agent-skills-update-$slug" ] || fail 'branch and skill scope disagree'
[ -n "$repo_dir" ] && [ -d "$repo_dir" ] || fail 'repository directory is required'
repo_dir=$(cd "$repo_dir" && pwd -P)
top=$(git -C "$repo_dir" rev-parse --show-toplevel) || fail 'repository root is unreadable'
[ "$top" -ef "$repo_dir" ] || fail 'repository directory must be the physical checkout root'
origin=$(git -C "$repo_dir" remote get-url origin) || fail 'origin is unreadable'
case "$origin" in
https://github.com/devantler-tech/agent-plugins | https://github.com/devantler-tech/agent-plugins.git | git@github.com:devantler-tech/agent-plugins.git) ;;
*) fail 'origin is not the expected github.com repository' ;;
esac
base=$(git -C "$repo_dir" rev-parse --verify HEAD) || fail 'HEAD is unreadable'
tree=$(git -C "$repo_dir" write-tree) || fail 'index tree is unreadable'
[[ "$base" =~ ^[0-9a-f]{40}$ && "$tree" =~ ^[0-9a-f]{40}$ ]] || fail 'invalid Git identity'
base_tree=$(git -C "$repo_dir" rev-parse "$base^{tree}") || fail 'base tree is unreadable'
if [ "$tree" = "$base_tree" ]; then
  printf 'NOOP: no staged metadata; no publication attempted\n'
  exit 0
fi

temp=$(mktemp -d "${TMPDIR:-/tmp}/signed-skill-metadata.XXXXXX")
finished=0 attempted=0 commit=''
# Preserve aborts on Bash 3.2 and never undo or retry a remote write with uncertain readback.
cleanup() {
  local rc=$?
  if [ "$finished" != 1 ] && [ "$rc" -eq 0 ]; then rc=1; fi
  if [ "$rc" -ne 0 ] && [ "$attempted" = 1 ]; then
    printf 'Inspect agent-plugins branch %s (expected parent %s, candidate %s); no automatic retry or rollback.\n' "$branch" "$base" "${commit:-unknown}" >&2
  fi
  rm -rf "$temp"
  exit "$rc"
}
trap cleanup EXIT
git -C "$repo_dir" diff --cached --no-renames --name-status "$base" >"$temp/index-diff" || fail 'staged change read failed'
git -C "$repo_dir" diff-tree --no-commit-id -r --no-renames --name-status "$base" "$tree" >"$temp/tree-diff" || fail 'tree change read failed'
if [ ! -s "$temp/index-diff" ] || ! cmp -s "$temp/index-diff" "$temp/tree-diff"; then
  fail 'staged and immutable tree inventories disagree'
fi
printf '[]\n' >"$temp/additions"
count=0
while IFS=$'\t' read -r status path extra || [ -n "${status}${path}${extra}" ]; do
  [[ "$status" = A || "$status" = M ]] && [ -n "$path" ] && [ -z "$extra" ] || fail 'metadata changes must be regular-file additions or modifications'
  case "$path" in
  .claude-plugin/marketplace.json | .github/plugin/marketplace.json | "plugins/$plugin/plugin.json" | "plugins/$plugin/.claude-plugin/plugin.json" | "plugins/$plugin/CHANGELOG.md") ;;
  "plugins/$plugin/resources/"*)
    resource=${path#"plugins/$plugin/resources/"}
    [[ "$resource" =~ ^[A-Za-z0-9_-][A-Za-z0-9_.-]*\.desired-state\.json$ ]] || fail 'unexpected resource path'
    git -C "$repo_dir" cat-file -e "$base:$path" || fail 'metadata publication cannot create a new desired-state profile'
    ;;
  *) fail 'staged path is outside the selected plugin metadata' ;;
  esac
  entry=$(git -C "$repo_dir" ls-files --stage -- "$path") || fail 'staged entry is unreadable'
  [[ "$entry" =~ ^100644\ ([0-9a-f]{40})\ 0$'\t' ]] || fail 'metadata must have one regular non-executable index entry'
  blob=${BASH_REMATCH[1]}
  git -C "$repo_dir" cat-file blob "$blob" >"$temp/content" || fail 'metadata blob read failed'
  [ "$(git -C "$repo_dir" hash-object --stdin <"$temp/content")" = "$blob" ] || fail 'metadata blob read was incomplete'
  if [ ! -f "$repo_dir/$path" ] || [ -L "$repo_dir/$path" ] || ! cmp -s "$temp/content" "$repo_dir/$path"; then
    fail 'working metadata differs from its staged bytes'
  fi
  case "$path" in
  *.json) json_object_unique "$temp/content" || fail 'generated JSON metadata is incomplete or ambiguous' ;;
  *.md)
    iconv -f UTF-8 -t UTF-16BE <"$temp/content" >"$temp/utf16" || fail 'generated changelog is not UTF-8'
    iconv -f UTF-16BE -t UTF-8 <"$temp/utf16" >"$temp/utf8" || fail 'generated changelog round-trip failed'
    cmp -s "$temp/content" "$temp/utf8" || fail 'generated changelog bytes changed during validation'
    tr -d '\000' <"$temp/content" >"$temp/no-nul"
    cmp -s "$temp/content" "$temp/no-nul" || fail 'generated changelog contains a raw NUL'
    ;;
  esac
  encoded=$(base64 <"$temp/content" | tr -d '\r\n') || fail 'metadata encoding failed'
  jq --arg path "$path" --arg contents "$encoded" '. + [{path:$path,contents:$contents}]' "$temp/additions" >"$temp/next"
  mv "$temp/next" "$temp/additions"
  count=$((count + 1))
done <"$temp/index-diff"
[ "$count" -gt 0 ] || fail 'nonempty staged tree has no observed metadata'

repo=devantler-tech/agent-plugins
message='chore(deps): refresh plugin metadata for synced content'
# shellcheck disable=SC2016 # GraphQL variables are data, never shell substitutions.
query='query($branch:String!){viewer{login} repository(owner:"devantler-tech",name:"agent-plugins"){nameWithOwner isArchived ref(qualifiedName:$branch){name target{__typename oid}}}}'
gh api graphql --hostname github.com -f "query=$query" -f "branch=refs/heads/$branch" >"$temp/before" || fail 'native branch observation failed'
json_object_unique "$temp/before" || fail 'ambiguous native branch observation'
jq -es -L "$here" --arg branch "$branch" --arg base "$base" 'include "graphql-observation";
  length==1 and (.[0]|graphql_complete and .data.viewer.login=="botantler-1[bot]" and
    (.data.repository|.nameWithOwner=="devantler-tech/agent-plugins" and .isArchived==false and
      .ref.name==$branch and .ref.target.__typename=="Commit" and .ref.target.oid==$base))' "$temp/before" >/dev/null || fail 'writer, repository or expected branch head is unproven'
[ "$(git -C "$repo_dir" rev-parse HEAD)" = "$base" ] && [ "$(git -C "$repo_dir" write-tree)" = "$tree" ] || fail 'local checkout moved before publication'
# shellcheck disable=SC2016 # GraphQL variables remain literal in the request.
mutation='mutation($input:CreateCommitOnBranchInput!){createCommitOnBranch(input:$input){commit{oid signature{isValid state}}}}'
jq -n --arg query "$mutation" --arg repo "$repo" --arg branch "$branch" --arg base "$base" --arg message "$message" --slurpfile additions "$temp/additions" \
  '{query:$query,variables:{input:{branch:{repositoryNameWithOwner:$repo,branchName:$branch},expectedHeadOid:$base,message:{headline:$message},fileChanges:{additions:$additions[0]}}}}' >"$temp/request"
attempted=1
gh api graphql --hostname github.com --method POST --input "$temp/request" >"$temp/created" || fail 'signed publication failed; inspect branch before recovery'
json_object_unique "$temp/created" || fail 'ambiguous signed publication response'
commit=$(jq -esr -L "$here" 'include "graphql-observation";
  if length==1 and (.[0]|graphql_complete and (.data.createCommitOnBranch.commit|
    (.oid|type=="string" and test("^[0-9a-f]{40}$")) and .signature.isValid==true and .signature.state=="VALID"))
  then .[0].data.createCommitOnBranch.commit.oid else error("signed publication response incomplete") end' "$temp/created") || fail 'signature response is unproven'
gh api --hostname github.com "repos/$repo/commits/$commit" >"$temp/commit" || fail 'independent commit readback failed'
json_object_unique "$temp/commit" || fail 'ambiguous independent commit readback'
jq -es --arg commit "$commit" --arg base "$base" --arg tree "$tree" --arg message "$message" '
  length==1 and (.[0]|.sha==$commit and .commit.verification.verified==true and .commit.verification.reason=="valid" and
    .commit.tree.sha==$tree and (.parents|length)==1 and .parents[0].sha==$base and .commit.message==$message and
    .author.login=="botantler-1[bot]" and .committer.login=="web-flow")' "$temp/commit" >/dev/null || fail 'signature, actor, parent or complete tree readback mismatch'
qualified=$(jq -rn --arg branch "$branch" '$branch|@uri')
gh api --hostname github.com "repos/$repo/git/ref/heads/$qualified" >"$temp/ref" || fail 'final branch readback failed'
json_object_unique "$temp/ref" || fail 'ambiguous final branch readback'
jq -es --arg branch "$branch" --arg commit "$commit" 'length==1 and (.[0]|.ref==("refs/heads/"+$branch) and .object.type=="commit" and .object.sha==$commit)' "$temp/ref" >/dev/null || fail 'branch no longer names the verified commit'
printf '%s\n' "$commit"
finished=1
