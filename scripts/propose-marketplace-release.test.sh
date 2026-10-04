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
  case "$mode" in
    latest-text-count) printf '{"total_count":"unknown","workflow_runs":[{"id":42}]}\n'; exit 0 ;;
    latest-fractional-count) printf '{"total_count":1.5,"workflow_runs":[{"id":42}]}\n'; exit 0 ;;
  esac
  if [ "$mode" = duplicate-latest ]; then
    printf '{"total_count":1,"workflow_runs":[{"id":99}],"workflow_runs":[{"id":42}]}\n'; exit 0
  fi
  if [ "$mode" = latest-ci-changed ] && [ "$(cat "$FORGE_STATE/reads")" -gt 1 ]; then
    printf '%s\n' '{"total_count":2,"workflow_runs":[{"id":43}]}'
  else
    printf '%s\n' '{"total_count":1,"workflow_runs":[{"id":42}]}'
  fi
elif [ "$endpoint" = repos/example/catalogue/actions/runs/42 ]; then
  jq -n --arg source "$SOURCE" '{id:42,path:".github/workflows/ci.yaml",event:"push",status:"completed",conclusion:"success",head_branch:"main",head_sha:$source,repository:{full_name:"example/catalogue"},head_repository:{full_name:"example/catalogue"}}' > "$FORGE_STATE/ci"
  if [ "$mode" = duplicate-ci ]; then
    jq -c . "$FORGE_STATE/ci" | sed 's/^{/{"conclusion":"failure",/'; exit 0
  fi
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
    pr-conflict) change='.[0].data.repository.pullRequests={totalCount:1,nodes:[{number:9,headRefName:"other",files:{totalCount:1,nodes:[{path:".github/plugin/marketplace.json",changeType:"MODIFIED"}]}}]}';;
    unrelated-pr) change='.[0].data.repository.pullRequests={totalCount:1,nodes:[{number:9,headRefName:"other",files:{totalCount:1,nodes:[{path:"README.md",changeType:"MODIFIED"}]}}]}';;
    pr-rename-*|unrelated-rename|rename-*|duplicate-rename) change='.[0].data.repository.pullRequests={totalCount:1,nodes:[{number:9,headRefName:"other",files:{totalCount:1,nodes:[{path:"docs/new.json",changeType:"RENAMED"}]}}]}';;
    pr-change-type-missing) change='.[0].data.repository.pullRequests={totalCount:1,nodes:[{number:9,headRefName:"other",files:{totalCount:1,nodes:[{path:"README.md"}]}}]}';;
    pr-change-type-malformed) change='.[0].data.repository.pullRequests={totalCount:1,nodes:[{number:9,headRefName:"other",files:{totalCount:1,nodes:[{path:"README.md",changeType:"UNKNOWN"}]}}]}';;
    branch-occupied) change='.[0].data.repository.proposal={name:"occupied"}';;
    writer-other-user) change='.[0].data.viewer.login="devantler"';;
    writer-role-missing) change='del(.[0].data.repository.viewerPermission)';;
    writer-read-role) change='.[0].data.repository.viewerPermission="READ"';;
    null-errors) change='.[0].errors=null';;
    empty-errors) change='.[0].errors=[]';;
    malformed) change='{}';;
  esac
  if [ "$mode" = duplicate-occupancy ]; then
    jq -c . "$FORGE_STATE/snapshot" | sed 's/"candidate":null/"candidate":{"databaseId":99},"candidate":null/'; exit 0
  fi
  jq "$change" "$FORGE_STATE/snapshot"
  [ "$mode" != trailing ] || printf '{}\n'
elif [ "$endpoint" = 'repos/example/catalogue/pulls/9/files?per_page=100' ]; then
  [ "$mode" != rename-api-denied ] || exit 111
  previous=docs/old.json
  case "$mode" in
    pr-rename-github) previous=.github/plugin/marketplace.json;;
    pr-rename-claude) previous=.claude-plugin/marketplace.json;;
    rename-fresh-drift) if [ "$(cat "$FORGE_STATE/reads")" -gt 1 ]; then previous=.github/plugin/marketplace.json; fi;;
  esac
  jq -n --arg previous "$previous" '[[{filename:"docs/new.json",status:"renamed",previous_filename:$previous}]]' > "$FORGE_STATE/files"
  case "$mode" in
    rename-prev-missing) jq '.[0][0]|=del(.previous_filename)' "$FORGE_STATE/files";;
    rename-rest-path) jq '.[0][0].filename="other.json"' "$FORGE_STATE/files";;
    rename-rest-status) jq '.[0][0].status="modified"' "$FORGE_STATE/files";;
    rename-rest-truncated) printf '[[]]\n';;
    duplicate-rename) jq -c . "$FORGE_STATE/files" | sed 's/"previous_filename":/"previous_filename":".github\/plugin\/marketplace.json","previous_filename":/';;
    *) cat "$FORGE_STATE/files";;
  esac
elif [ "$endpoint" = repos/example/catalogue/releases/generate-notes ]; then
  [ "$mode" != writer-denied ] || exit 105
  if [ "$mode" = writer-after-ref ] && [ -f "$FORGE_STATE/branch" ]; then exit 105; fi
  if [ "$mode" = writer-after-commit ] && [ -f "$FORGE_STATE/commit" ]; then exit 105; fi
  jq -e --arg source "$SOURCE" '.tag_name=="v1.1.0" and .target_commitish==$source' "$input" >/dev/null
  if [ "$mode" = duplicate-writer ]; then printf '{"name":false,"name":"preview","body":"discarded"}\n'
  else printf '%s\n' '{"name":"preview","body":"discarded"}'; fi
elif [ "$endpoint" = repos/example/catalogue/git/refs ] && [ "$method" = POST ]; then
  [ "$mode" != ref-race ] || exit 106
  branch=$(jq -er '.ref' "$input")
  jq -e --arg source "$SOURCE" '.sha==$source and (.ref|startswith("refs/heads/automation/marketplace-v1.1.0-"))' "$input" >/dev/null
  "$REAL_GIT" -C "$FIXTURE_REPO" update-ref "$branch" "$SOURCE" ''
  printf '%s\n' "$branch" > "$FORGE_STATE/branch"
  jq -n --arg ref "$branch" --arg source "$SOURCE" '{ref:$ref,object:{type:"commit",sha:$source}}' > "$FORGE_STATE/ref-response"
  if [ "$mode" = ref-duplicate ]; then jq -c . "$FORGE_STATE/ref-response" | sed 's/^{/{"object":{"type":"tag"},/'
  else cat "$FORGE_STATE/ref-response"; fi
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
  jq -n --arg commit "$commit" --argjson valid "$valid" '{data:{createCommitOnBranch:{commit:{oid:$commit,signature:{isValid:$valid,state:"VALID"}}}}}' > "$FORGE_STATE/commit-response"
  if [ "$mode" = commit-duplicate ]; then jq -c . "$FORGE_STATE/commit-response" | sed 's/"isValid":true/"isValid":false,"isValid":true/'
  elif [ "$mode" = commit-null-errors ]; then jq '.errors=null' "$FORGE_STATE/commit-response"
  else cat "$FORGE_STATE/commit-response"; fi
elif [[ "$endpoint" == repos/example/catalogue/commits/* ]]; then
  commit=$(cat "$FORGE_STATE/commit")
  valid=true; [ "$mode" != signature-readback ] || valid=false
  jq -n --arg commit "$commit" --argjson valid "$valid" '{sha:$commit,commit:{verification:{verified:$valid,reason:"valid"}}}' > "$FORGE_STATE/verification"
  if [ "$mode" = signature-duplicate ]; then jq -c . "$FORGE_STATE/verification" | sed 's/"verified":true/"verified":false,"verified":true/'
  else cat "$FORGE_STATE/verification"; fi
elif [ "$endpoint" = repos/example/catalogue/pulls ] && [ "$method" = POST ]; then
  [ "$mode" != pr-fails ] || exit 108
  jq -e '.draft==true and .base=="main" and (.body|startswith("> 🤖 Generated by the Agentic Engineer")) and (.body|test("(?m)^Part of #101$"))' "$input" >/dev/null
  cp "$input" "$FORGE_STATE/pr-input"
  if [ "$mode" = pr-duplicate ]; then printf '{"number":99,"number":17}\n'
  else printf '%s\n' '{"number":17}'; fi
elif [ "$endpoint" = repos/example/catalogue/pulls/17 ]; then
  [ "$mode" != readback-rest-denied ] || exit 112
  jq -n --arg source "$SOURCE" --arg commit "$(cat "$FORGE_STATE/commit")" --slurpfile pr "$FORGE_STATE/pr-input" '{node_id:"PR_fixture",number:17,state:"open",draft:true,user:{login:"github-actions[bot]",type:"Bot",node_id:"Bot_fixture"},head:{ref:$pr[0].head,sha:$commit,repo:{full_name:"example/catalogue"}},base:{ref:"main",sha:$source,repo:{full_name:"example/catalogue"}},html_url:"https://github.com/example/catalogue/pull/17",title:$pr[0].title,body:$pr[0].body}' > "$FORGE_STATE/native-pr"
  case "$mode" in
    readback-rest-user) jq '.user.login="devantler"' "$FORGE_STATE/native-pr";;
    readback-rest-type) jq '.user.type="User"' "$FORGE_STATE/native-pr";;
    readback-rest-node-missing) jq 'del(.user.node_id)' "$FORGE_STATE/native-pr";;
    readback-pr-node-missing) jq 'del(.node_id)' "$FORGE_STATE/native-pr";;
    readback-rest-head) jq '.head.sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$FORGE_STATE/native-pr";;
    readback-rest-repo) jq '.head.repo.full_name="other/catalogue"' "$FORGE_STATE/native-pr";;
    readback-rest-trailing) cat "$FORGE_STATE/native-pr"; printf '{}\n';;
    readback-rest-duplicate) jq -c . "$FORGE_STATE/native-pr" | sed 's/^{/{"draft":false,/';;
    *) cat "$FORGE_STATE/native-pr";;
  esac
elif [ "$endpoint" = graphql ]; then
  [ "$mode" != readback-fails ] || exit 109
  # Native GitHub represents this author as Bot github-actions in GraphQL, with the REST bot node ID.
  jq -n --arg source "$SOURCE" --arg commit "$(cat "$FORGE_STATE/commit")" --slurpfile pr "$FORGE_STATE/pr-input" '{data:{repository:{id:"R_fixture",nameWithOwner:"example/catalogue",isArchived:false,defaultBranchRef:{name:"main",target:{oid:$source}},ref:{name:$pr[0].head,target:{oid:$commit}},pullRequest:{id:"PR_fixture",number:17,state:"OPEN",isDraft:true,author:{login:"github-actions",__typename:"Bot",id:"Bot_fixture"},headRefName:$pr[0].head,headRefOid:$commit,baseRefName:"main",baseRefOid:$source,headRepository:{nameWithOwner:"example/catalogue"},url:"https://github.com/example/catalogue/pull/17",title:$pr[0].title,body:$pr[0].body}}}}' > "$FORGE_STATE/readback"
  case "$mode" in
    readback-null-errors) jq '.errors=null' "$FORGE_STATE/readback";;
    readback-not-draft) jq '.data.repository.pullRequest.isDraft=false' "$FORGE_STATE/readback";;
    readback-wrong-head) jq '.data.repository.pullRequest.headRefOid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$FORGE_STATE/readback";;
    readback-gql-login) jq '.data.repository.pullRequest.author.login="github-actions[bot]"' "$FORGE_STATE/readback";;
    readback-gql-type) jq '.data.repository.pullRequest.author.__typename="User"' "$FORGE_STATE/readback";;
    readback-gql-node) jq '.data.repository.pullRequest.author.id="Bot_other"' "$FORGE_STATE/readback";;
    readback-pr-node) jq '.data.repository.pullRequest.id="PR_other"' "$FORGE_STATE/readback";;
    readback-gql-duplicate) jq -c . "$FORGE_STATE/readback" | sed 's/"isDraft":true/"isDraft":false,"isDraft":true/';;
    *) cat "$FORGE_STATE/readback";;
  esac
else
  printf 'unexpected %s %s\n' "$method" "$endpoint" >&2; exit 110
fi
STUB
chmod +x "$work/bin/gh" "$work/bin/git"
export PATH="$work/bin:$PATH"
passed=0
# Report a failed proposal invariant without continuing to later fixture cases.
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
# Run the production CLI against a fresh real-Git and offline-forge fixture.
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
    if [[ "$fault" == commit-null-errors || "$fault" == readback-null-errors ]]; then
      [ -e "$FORGE_STATE/branch" ] && [ -e "$FORGE_STATE/commit" ] || fail "$name lost created objects"
      grep -q "No automatic retry or rollback" "$work/error" || fail "$name omitted recovery warning"
      ! grep -Eq "^(PATCH|DELETE) " "$CALLS" || fail "$name altered created objects"
      [ "$(grep -c '^POST graphql' "$CALLS" || true)" -eq 1 ] || fail "$name retried commit creation"
    fi
    if [[ "$fault" != unsigned && "$fault" != ref-race && "$fault" != ref-duplicate && "$fault" != commit-* && "$fault" != signature-readback && "$fault" != signature-duplicate && "$fault" != main-after-ref && "$fault" != writer-after-* && "$fault" != pr-fails && "$fault" != pr-duplicate && "$fault" != readback-* ]]; then
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
run_case 'explicit empty GraphQL errors remain valid' empty-errors true CREATED
for fault in null-errors commit-null-errors readback-null-errors; do run_case "$fault is refused" "$fault" true REFUSED; done
for fault in readback-rest-denied readback-rest-user readback-rest-type readback-rest-node-missing readback-pr-node-missing readback-rest-head readback-rest-repo readback-rest-trailing readback-gql-login readback-gql-type readback-gql-node readback-pr-node; do
  run_case "$fault is refused" "$fault" true REFUSED
done
run_case 'unrelated PR does not fence these manifests' unrelated-pr false PREPARED
run_case 'GitHub manifest renamed away is a conflict' pr-rename-github false REFUSED
run_case 'Claude manifest renamed away is a conflict' pr-rename-claude true REFUSED
run_case 'unrelated rename remains actionable' unrelated-rename false PREPARED
run_case 'unrelated rename permits an armed proposal' unrelated-rename true CREATED
for fault in rename-prev-missing rename-rest-path rename-rest-status rename-rest-truncated rename-api-denied rename-fresh-drift pr-change-type-missing pr-change-type-malformed; do
  run_case "$fault is refused" "$fault" true REFUSED
done
run_case 'local tags changing during assessment is refused' local-tags-changed false REFUSED
for fault in duplicate-ci duplicate-latest duplicate-occupancy duplicate-rename latest-text-count latest-fractional-count; do
  run_case "$fault is refused" "$fault" false REFUSED
done
for fault in duplicate-writer ref-duplicate commit-duplicate signature-duplicate pr-duplicate readback-rest-duplicate readback-gql-duplicate; do
  run_case "$fault is refused" "$fault" true REFUSED
done
for fault in repo-foreign repo-node repo-missing ci-pending ci-foreign ci-stale ci-event ci-workflow latest-ci-changed main-stale main-moved main-after-ref baseline-draft baseline-missing baseline-wrong baseline-changed candidate-occupied candidate-field-missing proposal-field-missing tag-missing tag-unknown page-incomplete pr-incomplete pr-files-incomplete pr-conflict branch-occupied malformed trailing writer-other-user writer-role-missing writer-read-role writer-denied writer-after-ref writer-after-commit ref-race commit-fails commit-extra commit-wrong-parent unsigned signature-readback pr-fails readback-fails readback-not-draft readback-wrong-head; do
  run_case "$fault is refused" "$fault" true REFUSED
done
SOURCE=$BASE
run_case 'quiet baseline remains read-only when armed' none true NO_CHANGE
printf 'PASS marketplace proposal (%s cases)\n' "$passed"
