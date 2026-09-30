#!/usr/bin/env bash
# Exercise real Git proposals against a stateful offline forge, without external writes.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tool="$root/scripts/propose-marketplace-release.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export REAL_GIT
REAL_GIT=$(command -v git)
export FIXTURE_REPO="$work/repo" FORGE_STATE="$work/state" CALLS="$work/calls"
mkdir "$work/bin" "$FORGE_STATE" "$FIXTURE_REPO"
"$REAL_GIT" -C "$FIXTURE_REPO" init -q
"$REAL_GIT" -C "$FIXTURE_REPO" config user.name Fixture
"$REAL_GIT" -C "$FIXTURE_REPO" config user.email fixture@example.invalid
mkdir -p "$FIXTURE_REPO/.github/plugin" "$FIXTURE_REPO/.claude-plugin"
printf '%s\n' '{"name":"fixture","metadata":{"version":"1.0.0"},"plugins":[{"name":"fixture","source":"./plugins/fixture","version":"1.0.0"}]}' > "$FIXTURE_REPO/.github/plugin/marketplace.json"
cp "$FIXTURE_REPO/.github/plugin/marketplace.json" "$FIXTURE_REPO/.claude-plugin/marketplace.json"
"$REAL_GIT" -C "$FIXTURE_REPO" add -- .github/plugin/marketplace.json .claude-plugin/marketplace.json
"$REAL_GIT" -C "$FIXTURE_REPO" commit -qm 'chore: initial marketplace'
export BASE SOURCE
BASE=$("$REAL_GIT" -C "$FIXTURE_REPO" rev-parse HEAD)
"$REAL_GIT" -C "$FIXTURE_REPO" tag v1.0.0
printf 'feature\n' > "$FIXTURE_REPO/feature"
"$REAL_GIT" -C "$FIXTURE_REPO" add -- feature
"$REAL_GIT" -C "$FIXTURE_REPO" commit -qm 'feat: add a feature'
SOURCE=$("$REAL_GIT" -C "$FIXTURE_REPO" rev-parse HEAD)
cat > "$work/bin/git" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
args=()
for arg in "$@"; do
  if [ "$arg" = https://github.com/example/catalogue.git ]; then arg=$FIXTURE_REPO; fi
  args+=("$arg")
done
exec "$REAL_GIT" "${args[@]}"
STUB
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = api ] || exit 90
shift
endpoint='' method=GET input='' query='' host='' paginated=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --hostname) host=$2; shift 2 ;;
    --method) method=$2; shift 2 ;;
    --input) input=$2; shift 2 ;;
    --paginate) paginated=true; shift ;;
    --slurp) shift ;;
    -f|-F) case "$2" in query=*) query=${2#query=} ;; esac; shift 2 ;;
    *) [ -z "$endpoint" ] || exit 91; endpoint=$1; shift ;;
  esac
done
[ "$host" = github.com ] || exit 92
printf '%s %s\n' "$method" "$endpoint" >> "$CALLS"
[ "$method" != PATCH ] && [ "$method" != DELETE ] || exit 93
mode=${FAULT:-none}
if [ "$endpoint" = repos/example/catalogue ]; then
  jq -n '{id:123,node_id:"R_fixture",full_name:"example/catalogue",archived:false,default_branch:"main"}' > "$FORGE_STATE/repo"
  case "$mode" in repo-foreign) jq '.full_name="other/catalogue"' "$FORGE_STATE/repo";; repo-node) jq '.node_id="R_other"' "$FORGE_STATE/repo";; repo-missing) printf '{}\n';; *) cat "$FORGE_STATE/repo";; esac
elif [[ "$endpoint" == repos/example/catalogue/actions/workflows/ci.yaml/runs\?* ]]; then
  if [ "$mode" = latest-ci-changed ] && [ "$(cat "$FORGE_STATE/reads")" -gt 1 ]; then
    printf '%s\n' '{"total_count":2,"workflow_runs":[{"id":43}]}'
  else
    printf '%s\n' '{"total_count":1,"workflow_runs":[{"id":42}]}'
  fi
elif [ "$endpoint" = repos/example/catalogue/actions/runs/42 ]; then
  jq -n --arg source "$SOURCE" '{id:42,path:".github/workflows/ci.yaml",event:"push",status:"completed",conclusion:"success",head_branch:"main",head_sha:$source,repository:{full_name:"example/catalogue"},head_repository:{full_name:"example/catalogue"}}' > "$FORGE_STATE/ci"
  case "$mode" in ci-pending) jq '.status="in_progress"|.conclusion=null' "$FORGE_STATE/ci";; ci-foreign) jq '.head_repository.full_name="other/catalogue"' "$FORGE_STATE/ci";; ci-stale) jq '.head_sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$FORGE_STATE/ci";; ci-event) jq '.event="workflow_dispatch"' "$FORGE_STATE/ci";; ci-workflow) jq '.path=".github/workflows/other.yaml"' "$FORGE_STATE/ci";; *) cat "$FORGE_STATE/ci";; esac
elif [ "$endpoint" = graphql ] && [ "$paginated" = true ]; then
  count=$(cat "$FORGE_STATE/reads" 2>/dev/null || printf 0)
  count=$((count+1)); printf '%s\n' "$count" > "$FORGE_STATE/reads"
  if [ "$mode" = local-tags-changed ] && [ "$count" = 2 ]; then
    "$REAL_GIT" -C "$FIXTURE_REPO" tag unexpected-local "$BASE"
  fi
  jq -n --arg source "$SOURCE" --arg base "$BASE" '[{data:{viewer:{login:"github-actions[bot]"},repository:{id:"R_fixture",nameWithOwner:"example/catalogue",isArchived:false,viewerPermission:null,defaultBranchRef:{name:"main",target:{__typename:"Commit",oid:$source}},baseline:{databaseId:10,tagName:"v1.0.0",isDraft:false,isPrerelease:false,publishedAt:"2026-09-30T00:00:00Z",tagCommit:{oid:$base}},candidate:null,proposal:null,refs:{totalCount:1,nodes:[{name:"v1.0.0",target:{__typename:"Commit",oid:$base}}],pageInfo:{hasNextPage:false,endCursor:null}},pullRequests:{totalCount:0,nodes:[]}}}}]' > "$FORGE_STATE/snapshot"
  if [ -f "$FORGE_STATE/branch" ]; then
    owned=$(cat "$FORGE_STATE/commit" 2>/dev/null || printf '%s' "$SOURCE")
    branch=$(cat "$FORGE_STATE/branch")
    jq --arg branch "${branch#refs/heads/}" --arg owned "$owned" '.[0].data.repository.proposal={name:$branch,target:{__typename:"Commit",oid:$owned}}' "$FORGE_STATE/snapshot" > "$FORGE_STATE/owned"
    mv "$FORGE_STATE/owned" "$FORGE_STATE/snapshot"
  fi
  change=.
  case "$mode" in
    main-stale) change='.[0].data.repository.defaultBranchRef.target.oid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"';;
    main-moved) if [ "$count" -gt 1 ]; then change='.[0].data.repository.defaultBranchRef.target.oid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'; fi;;
    main-after-ref) if [ -f "$FORGE_STATE/branch" ]; then change='.[0].data.repository.defaultBranchRef.target.oid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'; fi;;
    baseline-changed) if [ "$count" -gt 1 ]; then change='.[0].data.repository.baseline.databaseId=11'; fi;;
    baseline-draft) change='.[0].data.repository.baseline.isDraft=true';;
    baseline-missing) change='.[0].data.repository.baseline=null';;
    baseline-wrong) change='.[0].data.repository.baseline.tagCommit.oid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"';;
    candidate-occupied) change='.[0].data.repository.candidate={databaseId:11}';;
    candidate-field-missing) change='del(.[0].data.repository.candidate)';;
    proposal-field-missing) change='del(.[0].data.repository.proposal)';;
    tag-missing) change='.[0].data.repository.refs.nodes=[]|.[0].data.repository.refs.totalCount=0';;
    tag-unknown) change='.[0].data.repository.refs.nodes[0].target.__typename="Tree"';;
    page-incomplete) change='.[0].data.repository.refs.pageInfo.hasNextPage=true';;
    pr-incomplete) change='.[0].data.repository.pullRequests.totalCount=101';;
    pr-files-incomplete) change='.[0].data.repository.pullRequests={totalCount:1,nodes:[{number:9,headRefName:"other",files:{totalCount:101,nodes:[]}}]}';;
    pr-conflict) change='.[0].data.repository.pullRequests={totalCount:1,nodes:[{number:9,headRefName:"other",files:{totalCount:1,nodes:[{path:".github/plugin/marketplace.json"}]}}]}';;
    unrelated-pr) change='.[0].data.repository.pullRequests={totalCount:1,nodes:[{number:9,headRefName:"other",files:{totalCount:1,nodes:[{path:"README.md"}]}}]}';;
    branch-occupied) change='.[0].data.repository.proposal={name:"occupied"}';;
    writer-other-user) change='.[0].data.viewer.login="devantler"';;
    writer-role-missing) change='del(.[0].data.repository.viewerPermission)';;
    writer-read-role) change='.[0].data.repository.viewerPermission="READ"';;
    malformed) change='{}';;
  esac
  jq "$change" "$FORGE_STATE/snapshot"
  [ "$mode" != trailing ] || printf '{}\n'
elif [ "$endpoint" = repos/example/catalogue/releases/generate-notes ]; then
  [ "$mode" != writer-denied ] || exit 105
  if [ "$mode" = writer-after-ref ] && [ -f "$FORGE_STATE/branch" ]; then exit 105; fi
  if [ "$mode" = writer-after-commit ] && [ -f "$FORGE_STATE/commit" ]; then exit 105; fi
  jq -e --arg source "$SOURCE" '.tag_name=="v1.1.0" and .target_commitish==$source' "$input" >/dev/null
  printf '%s\n' '{"name":"preview","body":"discarded"}'
elif [ "$endpoint" = repos/example/catalogue/git/refs ] && [ "$method" = POST ]; then
  [ "$mode" != ref-race ] || exit 106
  branch=$(jq -er '.ref' "$input")
  jq -e --arg source "$SOURCE" '.sha==$source and (.ref|startswith("refs/heads/automation/marketplace-v1.1.0-"))' "$input" >/dev/null
  "$REAL_GIT" -C "$FIXTURE_REPO" update-ref "$branch" "$SOURCE" ''
  printf '%s\n' "$branch" > "$FORGE_STATE/branch"
  jq -n --arg ref "$branch" --arg source "$SOURCE" '{ref:$ref,object:{type:"commit",sha:$source}}'
elif [ "$endpoint" = graphql ] && [ "$method" = POST ]; then
  [ "$mode" != commit-fails ] || exit 107
  jq -e --arg source "$SOURCE" '.variables.input.expectedHeadOid==$source and (.variables.input.fileChanges.additions|length==2)' "$input" >/dev/null
  index="$FORGE_STATE/index"
  GIT_INDEX_FILE="$index" "$REAL_GIT" -C "$FIXTURE_REPO" read-tree "$SOURCE"
  while IFS= read -r addition; do
    path=$(printf '%s' "$addition" | jq -er .path)
    blob=$(printf '%s' "$addition" | jq -rj '.contents|@base64d' | "$REAL_GIT" -C "$FIXTURE_REPO" hash-object -w --stdin)
    GIT_INDEX_FILE="$index" "$REAL_GIT" -C "$FIXTURE_REPO" update-index --add --cacheinfo "100644,$blob,$path"
  done < <(jq -c '.variables.input.fileChanges.additions[]' "$input")
  if [ "$mode" = commit-extra ]; then
    extra=$(printf 'unexpected\n' | "$REAL_GIT" -C "$FIXTURE_REPO" hash-object -w --stdin)
    GIT_INDEX_FILE="$index" "$REAL_GIT" -C "$FIXTURE_REPO" update-index --add --cacheinfo "100644,$extra,unexpected"
  fi
  tree=$(GIT_INDEX_FILE="$index" "$REAL_GIT" -C "$FIXTURE_REPO" write-tree)
  parent=$SOURCE; [ "$mode" != commit-wrong-parent ] || parent=$BASE
  commit=$("$REAL_GIT" -C "$FIXTURE_REPO" commit-tree "$tree" -p "$parent" -m 'chore(release): prepare marketplace 1.1.0')
  "$REAL_GIT" -C "$FIXTURE_REPO" update-ref "$(cat "$FORGE_STATE/branch")" "$commit" "$SOURCE"
  printf '%s\n' "$commit" > "$FORGE_STATE/commit"
  valid=true; [ "$mode" != unsigned ] || valid=false
  jq -n --arg commit "$commit" --argjson valid "$valid" '{data:{createCommitOnBranch:{commit:{oid:$commit,signature:{isValid:$valid,state:"VALID"}}}}}'
elif [[ "$endpoint" == repos/example/catalogue/commits/* ]]; then
  commit=$(cat "$FORGE_STATE/commit")
  valid=true; [ "$mode" != signature-readback ] || valid=false
  jq -n --arg commit "$commit" --argjson valid "$valid" '{sha:$commit,commit:{verification:{verified:$valid,reason:"valid"}}}'
elif [ "$endpoint" = repos/example/catalogue/pulls ] && [ "$method" = POST ]; then
  [ "$mode" != pr-fails ] || exit 108
  jq -e '.draft==true and .base=="main" and (.body|startswith("> 🤖 Generated by the Agentic Engineer")) and (.body|test("(?m)^Part of #101$"))' "$input" >/dev/null
  cp "$input" "$FORGE_STATE/pr-input"
  printf '%s\n' '{"number":17}'
elif [ "$endpoint" = graphql ]; then
  [ "$mode" != readback-fails ] || exit 109
  jq -n --arg source "$SOURCE" --arg commit "$(cat "$FORGE_STATE/commit")" --slurpfile pr "$FORGE_STATE/pr-input" '{data:{repository:{id:"R_fixture",nameWithOwner:"example/catalogue",isArchived:false,defaultBranchRef:{name:"main",target:{oid:$source}},ref:{name:$pr[0].head,target:{oid:$commit}},pullRequest:{number:17,state:"OPEN",isDraft:true,author:{login:"github-actions[bot]"},headRefName:$pr[0].head,headRefOid:$commit,baseRefName:"main",baseRefOid:$source,headRepository:{nameWithOwner:"example/catalogue"},url:"https://github.com/example/catalogue/pull/17",title:$pr[0].title,body:$pr[0].body}}}}' > "$FORGE_STATE/readback"
  case "$mode" in readback-not-draft) jq '.data.repository.pullRequest.isDraft=false' "$FORGE_STATE/readback";; readback-wrong-head) jq '.data.repository.pullRequest.headRefOid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$FORGE_STATE/readback";; *) cat "$FORGE_STATE/readback";; esac
else
  printf 'unexpected %s %s\n' "$method" "$endpoint" >&2; exit 110
fi
STUB
chmod +x "$work/bin/gh" "$work/bin/git"
export PATH="$work/bin:$PATH"
passed=0
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
run_case() {
  local name=$1 fault=$2 armed=$3 expected=$4 output code=0
  if [ -n "${CASE_ONLY:-}" ] && [ "$fault" != "$CASE_ONLY" ]; then return; fi
  output="$work/candidate-$passed"
  rm -f "$FORGE_STATE/reads" "$FORGE_STATE/branch" "$FORGE_STATE/commit" "$FORGE_STATE/pr-input"
  : > "$CALLS"
  "$REAL_GIT" -C "$FIXTURE_REPO" update-ref -d refs/tags/unexpected-local
  "$REAL_GIT" -C "$FIXTURE_REPO" for-each-ref --format='%(refname)' refs/heads/automation/ | while IFS= read -r ref; do "$REAL_GIT" -C "$FIXTURE_REPO" update-ref -d "$ref"; done
  args=(--repo example/catalogue --source "$SOURCE" --ci-run latest --output "$output")
  [ "$armed" = false ] || args+=(--propose)
  if [ ! -f "$tool" ]; then fail "$name: proposal preparation is not implemented"; fi
  (cd "$FIXTURE_REPO" && FAULT="$fault" bash "$tool" "${args[@]}") > "$work/result" 2> "$work/error" || code=$?
  if [ "$expected" = REFUSED ]; then
    [ "$code" -ne 0 ] || fail "$name unexpectedly succeeded"
    ! grep -Eq '"status": "(CREATED|PREPARED)"' "$work/result" || fail "$name emitted success"
    if [[ "$fault" != unsigned && "$fault" != ref-race && "$fault" != commit-* && "$fault" != signature-readback && "$fault" != main-after-ref && "$fault" != writer-after-* && "$fault" != pr-fails && "$fault" != readback-* ]]; then
      ! grep -Eq 'POST (repos/example/catalogue/git/refs|graphql|repos/example/catalogue/pulls)' "$CALLS" || fail "$name wrote before refusal"
    fi
  else
    [ "$code" -eq 0 ] || { cat "$work/error" >&2; fail "$name exit $code"; }
    jq -e --arg expected "$expected" '.status==$expected' "$work/result" >/dev/null || fail "$name result"
    if [ "$expected" = CREATED ]; then
      jq -e '.proposalNumber==17 and .publication=="NOT_AUTHORIZED"' "$work/result" >/dev/null
      [ "$(grep -Ec 'POST (repos/example/catalogue/git/refs|graphql|repos/example/catalogue/pulls)' "$CALLS")" -eq 3 ] || fail "$name mutation count"
    else
      ! grep -q '^POST ' "$CALLS" || fail "$name performed a write"
    fi
  fi
  passed=$((passed+1))
}
run_case 'read-only preparation' none false PREPARED
run_case 'explicit signed draft creation' none true CREATED
run_case 'unrelated PR does not fence these manifests' unrelated-pr false PREPARED
run_case 'local tags changing during assessment is refused' local-tags-changed false REFUSED
for fault in repo-foreign repo-node repo-missing ci-pending ci-foreign ci-stale ci-event ci-workflow latest-ci-changed main-stale main-moved main-after-ref baseline-draft baseline-missing baseline-wrong baseline-changed candidate-occupied candidate-field-missing proposal-field-missing tag-missing tag-unknown page-incomplete pr-incomplete pr-files-incomplete pr-conflict branch-occupied malformed trailing writer-other-user writer-role-missing writer-read-role writer-denied writer-after-ref writer-after-commit ref-race commit-fails commit-extra commit-wrong-parent unsigned signature-readback pr-fails readback-fails readback-not-draft readback-wrong-head; do
  run_case "$fault is refused" "$fault" true REFUSED
done
SOURCE=$BASE
run_case 'quiet baseline remains read-only when armed' none true NO_CHANGE
printf 'PASS marketplace proposal (%s cases)\n' "$passed"
