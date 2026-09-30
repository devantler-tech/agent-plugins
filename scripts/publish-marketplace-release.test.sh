#!/usr/bin/env bash
# Real Git candidates with a stateful offline GitHub boundary. No external writes.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tool="$root/scripts/publish-marketplace-release.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export FORGE_STATE="$work/state" CALLS="$work/calls" FIXTURE_HEAD='' FIXTURE_TAG=''
mkdir "$work/bin" "$FORGE_STATE"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = api ] || exit 90
shift
endpoint='' method=GET input='' host='' query='' paginated=false
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
if [ "$endpoint" = graphql ]; then
  if [ "$paginated" = true ]; then
    [ "$mode" != assessment-fails ] || exit 94
    if [ "$mode" = mutate-caller ]; then printf 'changed after verification\n' > "$CALLER_CANDIDATE/RELEASE_NOTES.md"; fi
    jq -n --arg head "$FIXTURE_HEAD" --slurpfile tags "$FORGE_STATE/tags" '
      [{data:{repository:{nameWithOwner:"example/catalogue",isArchived:false,viewerPermission:"WRITE",
      defaultBranchRef:{name:"main",target:{__typename:"Commit",oid:$head}},release:null,
      refs:{totalCount:($tags[0]|length),nodes:$tags[0],pageInfo:{hasNextPage:false,endCursor:null}}}}}]'
  else
    [ "$mode" != snapshot-fails ] || exit 95
    phase=absent
    [ ! -e "$FORGE_STATE/tag" ] || phase=reserved
    [ ! -e "$FORGE_STATE/release" ] || phase=published
    jq -n --arg head "$FIXTURE_HEAD" --arg tag "$FIXTURE_TAG" --arg phase "$phase" \
      --slurpfile body "$FORGE_STATE/release-body" '
      {data:{repository:{nameWithOwner:"example/catalogue",isArchived:false,viewerPermission:"WRITE",
      defaultBranchRef:{name:"main",target:{__typename:"Commit",oid:$head}},
      ref:(if $phase=="absent" then null else {prefix:"refs/tags/",name:$tag,target:{__typename:"Commit",oid:$head}} end),
      release:(if $phase!="published" then null else {databaseId:42,tagName:$tag,isDraft:false,isPrerelease:false,
        name:$tag,description:$body[0].body,publishedAt:"2026-09-30T00:00:00Z",
        url:("https://github.com/example/catalogue/releases/tag/"+$tag),tagCommit:{oid:$head}} end)}}}' > "$FORGE_STATE/readback"
    change=.
    case "$mode:$phase" in
      branch-moved:*|branch-after-tag:reserved|branch-after-release:published) change='.data.repository.defaultBranchRef.target.oid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' ;;
      branch-renamed:reserved) change='.data.repository.defaultBranchRef.name="trunk"' ;;
      tag-raced:absent) change='.data.repository.ref={name:"occupied"}' ;;
      release-raced:reserved) change='.data.repository.release={databaseId:99}' ;;
      tag-moved:reserved|tag-after-release:published) change='.data.repository.ref.target.oid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' ;;
      annotated-tag:reserved) change='.data.repository.ref.target.__typename="Tag"' ;;
      malformed-snapshot:*) change='{}' ;;
      graphql-errors:*) change='.errors=[{message:"partial"}]' ;;
      invalid-errors:*) change='.errors=false' ;;
      wrong-repo:*) change='.data.repository.nameWithOwner="other/catalogue"' ;;
      no-permission:*) change='.data.repository.viewerPermission="READ"' ;;
      archived:*) change='.data.repository.isArchived=true' ;;
      missing-ref:*) change='del(.data.repository.ref)' ;;
      missing-release:*) change='del(.data.repository.release)' ;;
      draft-readback:published) change='.data.repository.release.isDraft=true' ;;
      prerelease-readback:published) change='.data.repository.release.isPrerelease=true' ;;
      notes-readback:published) change='.data.repository.release.description="changed"' ;;
      id-readback:published) change='.data.repository.release.databaseId=43' ;;
      commit-readback:published) change='.data.repository.release.tagCommit.oid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' ;;
      unpublished-readback:published) change='.data.repository.release.publishedAt=null' ;;
      url-readback:published) change='.data.repository.release.url="https://other.invalid/release"' ;;
    esac
    jq "$change" "$FORGE_STATE/readback"
    [ "$mode" != trailing-json ] || printf '{}\n'
  fi
elif [ "$endpoint" = repos/example/catalogue/git/refs ] && [ "$method" = POST ]; then
  [ "$mode" != tag-write-fails ] || exit 96
  jq -e --arg head "$FIXTURE_HEAD" --arg tag "$FIXTURE_TAG" '.=={ref:("refs/tags/"+$tag),sha:$head}' "$input" >/dev/null || exit 97
  [ ! -e "$FORGE_STATE/tag" ] || exit 98
  cp "$input" "$FORGE_STATE/tag"
  [ "$mode" != lost-tag-response ] || exit 99
  jq '{ref,object:{type:"commit",sha:.sha}}' "$input" > "$FORGE_STATE/response"
  case "$mode" in
    bad-tag-response) jq '.object.sha="wrong"' "$FORGE_STATE/response" ;;
    malformed-tag-response) printf 'not json\n' ;;
    trailing-tag-response) cat "$FORGE_STATE/response"; printf '{}\n' ;;
    *) cat "$FORGE_STATE/response" ;;
  esac
elif [ "$endpoint" = repos/example/catalogue/releases ] && [ "$method" = POST ]; then
  [ "$mode" != release-write-fails ] || exit 100
  [ -e "$FORGE_STATE/tag" ] && [ ! -e "$FORGE_STATE/release" ] || exit 101
  jq -e --arg tag "$FIXTURE_TAG" --arg head "$FIXTURE_HEAD" '
    .tag_name==$tag and .target_commitish==$head and .name==$tag and .draft==false and .prerelease==false
    and .generate_release_notes==false and .make_latest=="legacy"
    and (.body|contains("## Plugin inventory")) and (.body|contains("not a published release")|not)' "$input" >/dev/null || exit 102
  cp "$input" "$FORGE_STATE/release-body"
  cp "$input" "$FORGE_STATE/release"
  [ "$mode" != lost-release-response ] || exit 103
  jq '.+{id:42,html_url:("https://github.com/example/catalogue/releases/tag/"+.tag_name),published_at:"2026-09-30T00:00:00Z"}' "$input" > "$FORGE_STATE/response"
  case "$mode" in
    bad-release-response) jq '.id=null' "$FORGE_STATE/response" ;;
    malformed-release-response) printf 'not json\n' ;;
    trailing-release-response) cat "$FORGE_STATE/response"; printf '{}\n' ;;
    *) cat "$FORGE_STATE/response" ;;
  esac
else
  printf 'unexpected forge operation: %s %s\n' "$method" "$endpoint" >&2
  exit 104
fi
STUB
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"
passed=0
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
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
  # shellcheck disable=SC2016 # Literal hostile-looking Markdown is test data.
  git -C "$repo" commit -qm 'Initial <unsafe> `text`'
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
  export CALLER_CANDIDATE="$candidate"
  FIXTURE_TAG=$(jq -r .tag "$candidate/release.json")
  git -C "$repo" for-each-ref --format='%(refname:strip=2) %(objectname)' refs/tags/ > "$work/tags"
  jq -Rn '[inputs|split(" ")|{name:.[0],target:{__typename:"Tag",oid:.[1]}}]' < "$work/tags" > "$FORGE_STATE/tags"
  rm -f "$FORGE_STATE/tag" "$FORGE_STATE/release"
  printf '{}\n' > "$FORGE_STATE/release-body"
  : > "$CALLS"
  unset FAULT
}
run() { (cd "$repo" && bash "$tool" --repo example/catalogue --candidate "$candidate" --source "$source" --release "$release" "$@"); }
accept() {
  label=$1; shift
  run "$@" > "$work/result" 2> "$work/error" || { cat "$work/error"; fail "$label rejected"; }
  passed=$((passed+1))
}
reject() {
  label=$1; shift
  if run "$@" > "$work/result" 2> "$work/error"; then fail "$label accepted"; fi
  [ ! -s "$work/result" ] || fail "$label emitted success"
  ! grep -Eq '^(PATCH|DELETE) ' "$CALLS" || fail "$label altered existing objects"
  [ "$(grep -c '^POST .*git/refs$' "$CALLS" || true)" -le 1 ] || fail "$label retried tag write"
  [ "$(grep -c '^POST .*releases$' "$CALLS" || true)" -le 1 ] || fail "$label retried release write"
  passed=$((passed+1))
}
setup; accept 'default is read-only'
jq -e '.status=="VERIFIED" and .publication=="NOT_AUTHORIZED"' "$work/result" >/dev/null
! grep -q '^POST ' "$CALLS" || fail 'default mode wrote'
for kind in initial incremental; do
  setup "$kind"; accept "$kind publication" --publish
  jq -e --arg head "$release" '.status=="PUBLISHED" and .releaseCommit==$head and .releaseId==42 and .publication=="PUBLISHED"' "$work/result" >/dev/null
  [ "$(grep -c '^POST ' "$CALLS")" -eq 2 ] || fail 'publication did not create exactly two objects'
  test -e "$FORGE_STATE/tag" && test -e "$FORGE_STATE/release"
  if [ "$kind" = initial ]; then
    jq -e '.body|contains("&lt;unsafe&gt;") and (contains("<unsafe>")|not)' "$FORGE_STATE/release" >/dev/null
  fi
done
for fault in assessment-fails snapshot-fails branch-moved tag-raced malformed-snapshot graphql-errors invalid-errors wrong-repo no-permission archived missing-ref missing-release trailing-json; do
  setup; export FAULT=$fault; reject "$fault" --publish
  ! grep -q '^POST ' "$CALLS" || fail "$fault wrote before readiness"
done
for fault in tag-write-fails lost-tag-response bad-tag-response malformed-tag-response trailing-tag-response branch-after-tag branch-renamed release-raced tag-moved annotated-tag; do
  setup; export FAULT=$fault; reject "$fault" --publish
  ! grep -q '^POST .*releases$' "$CALLS" || fail "$fault created a release"
done
for fault in release-write-fails lost-release-response bad-release-response malformed-release-response trailing-release-response branch-after-release tag-after-release draft-readback prerelease-readback notes-readback id-readback commit-readback unpublished-readback url-readback; do
  setup; export FAULT=$fault; reject "$fault" --publish
  [ -e "$FORGE_STATE/tag" ] || fail "$fault removed reserved tag"
  grep -q 'remote objects may exist' "$work/error" || fail "$fault omitted recovery warning"
done
setup; printf 'tampered\n' >> "$candidate/RELEASE_NOTES.md"; reject 'tampered candidate' --publish
[ ! -s "$CALLS" ] || fail 'tampered artifact reached forge'
setup; reject 'duplicate publish' --publish --publish
[ ! -s "$CALLS" ] || fail 'duplicate flag reached forge'
setup; GH_HOST=other.invalid accept 'fixed API host' --publish
setup; export FAULT=mutate-caller; accept 'caller mutation cannot change frozen publication' --publish
jq -e '.body|contains("changed after verification")|not' "$FORGE_STATE/release" >/dev/null
setup; source=abc; reject 'abbreviated source' --publish
[ ! -s "$CALLS" ] || fail 'invalid input reached forge'
setup; bash "$tool" --help > "$work/help"
[ ! -s "$CALLS" ] || fail 'help reached forge'
passed=$((passed+1))
printf 'publish-marketplace-release: %s passed\n' "$passed"
