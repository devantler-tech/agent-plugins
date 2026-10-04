#!/usr/bin/env bash
# Real Git histories and an offline forge: assessments must never perform writes.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tool="$root/scripts/check-marketplace-release-remote.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export REMOTE_FIXTURE="$work/remote" REMOTE_SECOND="$work/second" CALLS="$work/calls"
export PERMISSION_FIXTURE="$work/permission" PERMISSION_SECOND="$work/permission-second"
export WRITER_FIXTURE="$work/writer" WRITER_SECOND="$work/writer-second"
mkdir "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "$*" = 'api --hostname github.com repos/example/catalogue' ]; then
  printf 'repository\n' >> "$CALLS"
  [ "${FORGE_FAIL:-false}" != true ] || exit 92
  if [ "$(grep -c '^repository$' "$CALLS")" -gt 1 ] && [ -e "$PERMISSION_SECOND" ]; then cat "$PERMISSION_SECOND"; else cat "$PERMISSION_FIXTURE"; fi
  exit 0
fi
if [ "$#" -eq 8 ] && [ "$1 $2 $3 $4 $5 $6 $7" = 'api --hostname github.com --method POST repos/example/catalogue/releases/generate-notes --input' ]; then
  printf 'writer\n' >> "$CALLS"
  [ "${WRITER_FAIL:-false}" != true ] || exit 93
  jq -e --arg tag "$FIXTURE_TAG" --arg head "$FIXTURE_HEAD" '.=={tag_name:$tag,target_commitish:$head}' "$8" >/dev/null || exit 94
  if [ "$(grep -c '^writer$' "$CALLS")" -gt 1 ] && [ -e "$WRITER_SECOND" ]; then cat "$WRITER_SECOND"; else cat "$WRITER_FIXTURE"; fi
  exit 0
fi
printf 'graphql\n' >> "$CALLS"
[[ "$*" == 'api graphql '* && "$*" == *'--hostname github.com'* && "$*" == *'--paginate --slurp'* ]] || exit 90
[[ "$*" != *mutation* && "$*" == *'owner=example'* && "$*" == *'name=catalogue'* ]] || exit 91
[[ ${FORGE_FAIL:-false} != true ]] || exit 92
if [ "$(grep -c '^graphql$' "$CALLS")" -gt 1 ] && [ -e "$REMOTE_SECOND" ]; then cat "$REMOTE_SECOND"; else cat "$REMOTE_FIXTURE"; fi
STUB
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"
passed=0
# Stop on the first behavior that violates the remote assessment contract.
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
# Build a complete candidate from real Git history and reset independent API fixtures.
setup() {
  repo=$(mktemp -d "$work/repo.XXXXXX")
  candidate="$repo-candidate"
  git -C "$repo" init -q
  git -C "$repo" config user.name Test
  git -C "$repo" config user.email test@example.invalid
  mkdir -p "$repo/.github/plugin" "$repo/.claude-plugin"
  printf '%s\n' '{"name":"example","metadata":{"version":"1.2.3"},"plugins":[{"name":"example","version":"4.5.6","source":"./plugins/example"}]}' > "$repo/.github/plugin/marketplace.json"
  cp "$repo/.github/plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
  git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json
  git -C "$repo" commit -qm 'Initial import'
  base=initial
  if [ "${1:-}" = incremental ]; then
    git -C "$repo" -c tag.gpgsign=false tag -a v1.2.3 -m baseline
    git -C "$repo" commit --allow-empty -qm 'feat: expand catalogue'
    base=v1.2.3
  fi
  source=$(git -C "$repo" rev-parse HEAD)
  (cd "$repo" && bash "$root/scripts/prepare-marketplace-release.sh" --base-tag "$base" --output "$candidate") >/dev/null
  if [ "$base" != initial ]; then
    cp "$candidate/.github/plugin/marketplace.json" "$repo/.github/plugin/marketplace.json"
    cp "$candidate/.claude-plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
    git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json
    git -C "$repo" commit -qm 'chore(release): prepare version'
  fi
  release=$(git -C "$repo" rev-parse HEAD)
  export FIXTURE_HEAD="$release" FIXTURE_TAG
  FIXTURE_TAG=$(jq -r .tag "$candidate/release.json")
  rm -f "$REMOTE_SECOND" "$PERMISSION_SECOND" "$WRITER_SECOND"
  unset FORGE_FAIL WRITER_FAIL
  snapshot
}
# Construct a complete remote inventory and successful nonpersistent capability response.
snapshot() {
  git -C "$repo" for-each-ref --format='%(refname:strip=2) %(objectname)' refs/tags/ > "$work/tags"
  jq -Rn --arg head "$release" '[inputs | split(" ") | {name:.[0],target:{__typename:"Tag",oid:.[1]}}] as $tags |
    [{data:{repository:{id:"R_catalogue",nameWithOwner:"example/catalogue",isArchived:false,viewerPermission:"WRITE",
      defaultBranchRef:{name:"main",target:{__typename:"Commit",oid:$head}},release:null,
      refs:{totalCount:($tags|length),nodes:$tags,pageInfo:{hasNextPage:false,endCursor:null}}}}}]' < "$work/tags" > "$REMOTE_FIXTURE"
  printf '%s\n' '{"id":123,"node_id":"R_catalogue","full_name":"example/catalogue","archived":false,"default_branch":"main","permissions":{"push":true,"pull":true}}' > "$PERMISSION_FIXTURE"
  printf '%s\n' '{"name":"Preview","body":"Nonpersistent generated notes"}' > "$WRITER_FIXTURE"
}
# Change only the selected remote observation for a refusal scenario.
mutate() { jq "$1" "$REMOTE_FIXTURE" > "$work/change"; mv "$work/change" "$REMOTE_FIXTURE"; }
# Exercise the production command with the independently selected candidate and commits.
run() {
  : > "$CALLS"
  (cd "$repo" && bash "$tool" --repo example/catalogue --candidate "$candidate" --source "$source" --release "$release" "$@")
}
# Require a successful, read-only assessment and repeated native capability observations.
accept() {
  run > "$work/result" 2> "$work/error" || { cat "$work/error"; fail "$1 rejected"; }
  jq -e --arg release "$release" '.status=="VERIFIED" and .releaseCommit==$release and .repository=="example/catalogue" and .scope=="remote-prepublication-snapshot" and .authority=="assessment-only" and .publication=="NOT_AUTHORIZED"' "$work/result" >/dev/null || fail "$1 verdict"
  [ "$(grep -c '^graphql$' "$CALLS")" -eq 2 ] || fail "$1 did not reobserve remote"
  [ "$(grep -c '^repository$' "$CALLS")" -eq 2 ] || fail "$1 did not reobserve native writer evidence"
  [ "$(grep -c '^writer$' "$CALLS")" -eq 2 ] || fail "$1 did not reobserve native writer capability"
  passed=$((passed+1))
}
# Require failure without any success assessment.
reject() {
  if run > "$work/result" 2> "$work/error"; then fail "$1 accepted"; fi
  [ ! -s "$work/result" ] || fail "$1 emitted assessment"
  passed=$((passed+1))
}
setup incremental; mutate '.[0].data.repository.viewerPermission=null'
jq '.permissions={pull:false,push:false}' "$PERMISSION_FIXTURE" > "$work/change"; mv "$work/change" "$PERMISSION_FIXTURE"
accept 'App null-role with provider-enforced writer capability'
setup; accept 'initial snapshot'
setup incremental; accept 'annotated baseline and manifest-only release'
for errors in false null '{}' '"unavailable"'; do
  setup incremental; mutate ".[0].errors=$errors"; reject "invalid GraphQL error envelope $errors"
done
setup incremental; mutate '.[0].errors=[]'; accept 'explicit empty GraphQL error envelope'
git -C "$repo" show-ref > "$work/refs-before"
printf 'local work\n' > "$repo/local"
git -C "$repo" status --porcelain > "$work/status-before"
accept 'dirty worktree is not changed'
git -C "$repo" show-ref > "$work/refs-after"
git -C "$repo" status --porcelain > "$work/status-after"
cmp "$work/refs-before" "$work/refs-after"; cmp "$work/status-before" "$work/status-after"
for change in \
  '.[0].data.repository.nameWithOwner="other/catalogue"' \
  '.[0].data.repository.isArchived=true' \
  '.[0].data.repository.viewerPermission="READ"' \
  '.[0].data.repository.viewerPermission="TRIAGE"' \
  'del(.[0].data.repository.viewerPermission)' \
  '.[0].data.repository.defaultBranchRef.target.oid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
  '.[0].data.repository.defaultBranchRef=null' \
  '.[0].data.repository.defaultBranchRef.target.__typename="Tag"' \
  '.[0].data.repository.release={tagName:"v1.3.0",isDraft:true}' \
  'del(.[0].data.repository.release)' \
  '.[0].data.repository.refs.nodes[0].target.oid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
  '.[0].data.repository.refs.nodes=[] | .[0].data.repository.refs.totalCount=0' \
  '.[0].data.repository.refs.totalCount=2' \
  '.[0].data.repository.refs.pageInfo.hasNextPage=true | .[0].data.repository.refs.pageInfo.endCursor="next"' \
  '.[0].data.repository.refs.nodes += .[0].data.repository.refs.nodes | .[0].data.repository.refs.totalCount=2' \
  '.[0].data.repository.refs.nodes[0].name="../unsafe"' \
  '.[0].data.repository.refs.nodes[0].target.oid="main"' \
  '.[0].data.repository.refs.nodes[0].target=null' \
  '.[0].errors=[{message:"partial failure"}]' \
  '.[0].data.repository=null' \
  '[]' \
  '{}'; do
  setup incremental; mutate "$change"; reject "$change"
done
for change in '.node_id="R_foreign"' '.id=null' \
  '.full_name="other/catalogue"' '.archived=true' '.default_branch="trunk"'; do
  setup incremental
  jq "$change" "$PERMISSION_FIXTURE" > "$work/change"; mv "$work/change" "$PERMISSION_FIXTURE"
  reject "native repository identity $change"
done
for change in '{}' '.name=""' '.name=true' 'del(.body)' '.body=null'; do
  setup incremental; jq "$change" "$WRITER_FIXTURE" > "$work/change"; mv "$work/change" "$WRITER_FIXTURE"
  reject "invalid writer capability $change"
done
setup incremental; mutate '.[0].data.repository.viewerPermission=null'; export WRITER_FAIL=true
reject 'read-only App cannot generate notes'
setup incremental; mutate '.[0].data.repository.viewerPermission=null'
printf '{}\n' > "$WRITER_SECOND"
reject 'App permission lost during assessment'
setup incremental; printf '{}\n{}\n' > "$WRITER_FIXTURE"; reject 'trailing native capability response'
setup incremental; printf '{}\n{}\n' > "$PERMISSION_FIXTURE"; reject 'trailing native permission response'
setup; printf 'not json\n' > "$REMOTE_FIXTURE"; reject 'malformed response'
setup; printf '\n[]\n' >> "$REMOTE_FIXTURE"; reject 'trailing JSON document'
setup; export FORGE_FAIL=true; reject 'forge failure'; unset FORGE_FAIL
setup incremental
# shellcheck disable=SC2016 # These are jq variables, not shell expansions.
mutate '.[0].data.repository.defaultBranchRef.target.oid as $head | .[0].data.repository.refs.nodes += [{name:"v1.3.0",target:{__typename:"Commit",oid:$head}}] | .[0].data.repository.refs.totalCount=2'
reject 'remotely occupied candidate tag'
setup incremental; jq '.[0].data.repository.defaultBranchRef.target.oid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$REMOTE_FIXTURE" > "$REMOTE_SECOND"; reject 'main moved during assessment'
setup incremental; jq '.[0].data.repository.defaultBranchRef.name="trunk"' "$REMOTE_FIXTURE" > "$REMOTE_SECOND"; reject 'default branch renamed during assessment'
setup incremental; jq '.[0].data.repository.release={tagName:"v1.3.0"}' "$REMOTE_FIXTURE" > "$REMOTE_SECOND"; reject 'release appeared during assessment'
setup incremental; printf 'changed\n' >> "$candidate/RELEASE_NOTES.md"; reject 'tampered local artifact'
[ ! -s "$CALLS" ] || fail 'tampered artifact reached forge'
setup
for number in $(seq 1 101); do git -C "$repo" tag "archive/$number"; done
snapshot
# shellcheck disable=SC2016 # These are jq variables, not shell expansions.
mutate '.[0] as $p | [($p | .data.repository.refs.nodes=$p.data.repository.refs.nodes[:100] | .data.repository.refs.pageInfo={hasNextPage:true,endCursor:"page1"}), ($p | .data.repository.refs.nodes=$p.data.repository.refs.nodes[100:] | .data.repository.refs.pageInfo={hasNextPage:false,endCursor:"page2"})]'
accept 'complete multi-page tag inventory'
mutate '.[1].data.repository.refs.totalCount=102'; reject 'inventory changed across pages'
setup; git -C "$repo" tag local-only; reject 'extra stale local tag'
setup; GH_HOST=other.invalid accept 'host remains github.com'
setup
: > "$CALLS"
bash "$tool" --help > "$work/help"
[ ! -s "$CALLS" ] || fail 'help reached forge'
if bash "$tool" > "$work/result" 2> "$work/error"; then fail 'no-argument invocation accepted'; fi
[ ! -s "$CALLS" ] || fail 'no-argument invocation reached forge'
passed=$((passed+1))
setup
if run --repo unexpected/repo > "$work/result" 2> "$work/error"; then fail 'duplicate repo accepted'; fi
[ ! -s "$CALLS" ] || fail 'invalid arguments reached forge'
passed=$((passed+1))
setup incremental
jq -c . "$PERMISSION_FIXTURE" | sed 's/^{/{"archived":true,/' > "$work/change"; mv "$work/change" "$PERMISSION_FIXTURE"
reject 'contradictory native repository identity'
setup incremental
jq -c . "$WRITER_FIXTURE" | sed 's/^{/{"body":false,/' > "$work/change"; mv "$work/change" "$WRITER_FIXTURE"
reject 'contradictory native writer capability'
setup incremental
jq -c . "$REMOTE_FIXTURE" | sed 's/"release":null/"release":{"tagName":"occupied"},"release":null/' > "$work/change"; mv "$work/change" "$REMOTE_FIXTURE"
reject 'contradictory candidate release absence'
printf 'PASS: %s remote release assessment cases\n' "$passed"
