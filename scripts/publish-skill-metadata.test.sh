#!/usr/bin/env bash
# Exercise the real publisher against a hermetic forge that rebuilds trees from its request.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export REAL_GIT
REAL_GIT=$(command -v git)
export STATE="$work/state" FIXTURE="$work/repo"
mkdir -p "$STATE" "$work/bin" "$work/base"
branch=deps/agent-skills-update-agentic-engineering-skills-product-engineering
skill=plugins/agentic-engineering/skills/product-engineering
plugin=plugins/agentic-engineering
git -C "$work/base" init -q
git -C "$work/base" config user.name Fixture
git -C "$work/base" config user.email fixture@example.invalid
git -C "$work/base" remote add origin https://github.com/devantler-tech/agent-plugins.git
paths=(.claude-plugin/marketplace.json .github/plugin/marketplace.json
  "$plugin/plugin.json" "$plugin/.claude-plugin/plugin.json"
  "$plugin/resources/provider-neutral.desired-state.json" "$plugin/CHANGELOG.md")
for path in "${paths[@]}"; do
  mkdir -p "$work/base/$(dirname "$path")"
  case "$path" in
  *.json) printf '{"before":true}\n' >"$work/base/$path" ;;
  *) printf '# Existing notes\n' >"$work/base/$path" ;;
  esac
done
printf 'keep\n' >"$work/base/unrelated"
git -C "$work/base" add -- "${paths[@]}" unrelated
git -C "$work/base" -c commit.gpgsign=false commit -qm fixture

cat >"$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$STATE/calls"
mode=${MODE:-ok}
base=$("$REAL_GIT" -C "$FIXTURE" rev-parse HEAD)
branch=deps/agent-skills-update-agentic-engineering-skills-product-engineering
repo=devantler-tech/agent-plugins
message='chore(deps): refresh plugin metadata for synced content'
if [[ "$*" = *'--method POST'* ]]; then
  printf 'attempt\n' >> "$STATE/attempts"
  while [ "$1" != --input ]; do shift; done
  cp "$2" "$STATE/request"
  jq -e --arg base "$base" --arg branch "$branch" --arg repo "$repo" --arg message "$message" '
    .variables.input | .expectedHeadOid==$base and .branch=={branchName:$branch,repositoryNameWithOwner:$repo}
    and .message=={headline:$message} and (.fileChanges|keys)==["additions"]
  ' "$STATE/request" >/dev/null
  [ "$mode" != race ] || exit 1
  # Reconstruct the remote result solely from the transmitted paths and raw bytes.
  export GIT_INDEX_FILE="$STATE/server-index"
  "$REAL_GIT" -C "$FIXTURE" read-tree "$base"
  jq -c '.variables.input.fileChanges.additions[]' "$STATE/request" > "$STATE/entries"
  while IFS= read -r entry; do
    path=$(jq -r .path <<< "$entry")
    jq -r .contents <<< "$entry" | base64 --decode > "$STATE/blob"
    blob=$("$REAL_GIT" -C "$FIXTURE" hash-object -w --stdin < "$STATE/blob")
    "$REAL_GIT" -C "$FIXTURE" update-index --add --cacheinfo 100644 "$blob" "$path"
  done < "$STATE/entries"
  tree=$("$REAL_GIT" -C "$FIXTURE" write-tree)
  commit=$(printf '%s\n' "$message" | "$REAL_GIT" -C "$FIXTURE" -c commit.gpgsign=false commit-tree "$tree" -p "$base")
  printf '%s\n' "$commit" > "$STATE/commit"
  printf '%s\n' "$tree" > "$STATE/tree"
  if [ "$mode" = partial-write ]; then printf '{"data":'; exit; fi
  jq -n --arg oid "$commit" --arg mode "$mode" '{data:{createCommitOnBranch:{commit:{oid:$oid,signature:{isValid:($mode!="unsigned"),state:"VALID"}}}}}'
elif [[ "$*" = *'repos/'*'/commits/'* ]]; then
  commit=$(cat "$STATE/commit")
  tree=$(cat "$STATE/tree")
  [ "$mode" != wrong-tree ] || tree=$base
  [ "$mode" != wrong-parent ] || base=$commit
  jq -n --arg sha "$commit" --arg tree "$tree" --arg base "$base" --arg message "$message" --arg mode "$mode" '{sha:$sha,
    commit:{tree:{sha:$tree},message:$message,verification:{verified:($mode!="bad-readback-signature"),reason:"valid"}},
    parents:[{sha:$base}],author:{login:"botantler-1[bot]"},committer:{login:"web-flow"}}'
elif [[ "$*" = *'/git/ref/'* ]]; then
  commit=$(cat "$STATE/commit")
  [ "$mode" != moved-ref ] || commit=$base
  jq -n --arg branch "$branch" --arg sha "$commit" '{ref:("refs/heads/"+$branch),object:{type:"commit",sha:$sha}}'
else
  [ "$mode" != partial-observation ] || { printf '{"data":'; exit; }
  [ "$mode" != wrong-head ] || base=0000000000000000000000000000000000000000
  viewer='botantler-1[bot]'
  [ "$mode" != wrong-writer ] || viewer=devantler
  [ "$mode" != wrong-repo ] || repo=devantler-tech/other
  [ "$mode" != duplicate-observation ] || { printf '{"data":{},"data":{}}'; exit; }
  jq -n --arg branch "$branch" --arg base "$base" --arg viewer "$viewer" --arg repo "$repo" '{data:{viewer:{login:$viewer},repository:{nameWithOwner:$repo,isArchived:false,ref:{name:$branch,target:{__typename:"Commit",oid:$base}}}}}'
fi
STUB
cat >"$work/bin/git" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "${MODE:-}" = short-diff ] && [[ "$*" = *'diff --cached --no-renames --name-status'* ]]; then
  "$REAL_GIT" "$@" | sed -n '1p'
elif [ "${MODE:-}" = short-blob ] && [[ "$*" = *'cat-file blob '* ]]; then
  printf '{}\n'
else
  exec "$REAL_GIT" "$@"
fi
STUB
chmod +x "$work/bin/gh" "$work/bin/git"
export PATH="$work/bin:$PATH"

# Reset each isolated fixture and stage an exact metadata union; keep unrelated edits unstaged.
fixture() {
  local selected=("$plugin/plugin.json")
  if [ "${1:-}" = full ]; then selected=("${paths[@]}"); fi
  rm -rf "$FIXTURE" "$STATE"
  cp -R "$work/base" "$FIXTURE"
  mkdir "$STATE"
  for path in "${selected[@]}"; do
    case "$path" in
    *.json) printf '{"after":"æøå","nested":{"value":1}}\n' >"$FIXTURE/$path" ;;
    *) printf '# Notes\n\n## 1.2.3\n\nPublished æøå.\n' >"$FIXTURE/$path" ;;
    esac
  done
  git -C "$FIXTURE" add -- "${selected[@]}"
  printf 'unrelated editor\n' >"$FIXTURE/unrelated"
  export MODE=ok
}

# Invoke the production command without a real token or network-capable forge client.
publish() {
  bash "$here/publish-skill-metadata.sh" --repo-dir "$FIXTURE" --skill-path "$skill" --branch "$branch" >"$STATE/out" 2>"$STATE/err"
}

# Refusals must not print success; early faults must never reach a write attempt.
reject() {
  local name=$1 phase=$2
  if publish; then
    printf 'FAIL: accepted %s\n' "$name" >&2
    exit 1
  fi
  [ ! -s "$STATE/out" ]
  if [ "$phase" = before ]; then
    [ ! -e "$STATE/attempts" ]
  else
    [ "$(wc -l <"$STATE/attempts" | tr -d ' ')" = 1 ]
    grep -q 'no automatic retry or rollback' "$STATE/err"
  fi
  printf 'PASS: rejected %s (%s publication)\n' "$name" "$phase"
}

fixture full
before_head=$(git -C "$FIXTURE" rev-parse HEAD)
before_tree=$(git -C "$FIXTURE" write-tree)
git -C "$FIXTURE" diff >"$STATE/unstaged-before"
publish
[ "$(cat "$STATE/out")" = "$(cat "$STATE/commit")" ]
[ "$(cat "$STATE/tree")" = "$before_tree" ]
[ "$(git -C "$FIXTURE" rev-parse HEAD)" = "$before_head" ]
[ "$(git -C "$FIXTURE" write-tree)" = "$before_tree" ]
git -C "$FIXTURE" diff >"$STATE/unstaged-after"
cmp "$STATE/unstaged-before" "$STATE/unstaged-after"
jq -e '.variables.input.fileChanges.additions|length==6 and all(.[];.path!="unrelated")' "$STATE/request" >/dev/null
printf 'PASS: one signed request reproduces every staged byte and preserves the caller\n'

fixture
git -C "$FIXTURE" read-tree HEAD
publish
grep -q '^NOOP:' "$STATE/out"
[ ! -e "$STATE/calls" ]
printf 'PASS: no-op makes no forge call\n'

for mode in wrong-head wrong-writer wrong-repo partial-observation duplicate-observation short-diff short-blob; do
  fixture
  if [ "$mode" = short-diff ]; then fixture full; fi
  export MODE=$mode
  reject "$mode" before
done
for mode in race unsigned partial-write bad-readback-signature wrong-tree wrong-parent moved-ref; do
  fixture
  export MODE=$mode
  reject "$mode" after
done
fixture
printf '{"later":"editor"}\n' >"$FIXTURE/$plugin/plugin.json"
reject unstaged-metadata before
fixture
git -C "$FIXTURE" remote set-url origin https://github.com/other/agent-plugins.git
reject wrong-origin before
fixture
printf 'outside\n' >"$FIXTURE/forbidden"
git -C "$FIXTURE" add -- forbidden
reject forbidden-path before
fixture
rm "$FIXTURE/$plugin/CHANGELOG.md"
git -C "$FIXTURE" add -- "$plugin/CHANGELOG.md"
reject deletion before
fixture
rm "$FIXTURE/$plugin/CHANGELOG.md"
ln -s ../plugin.json "$FIXTURE/$plugin/CHANGELOG.md"
git -C "$FIXTURE" add -- "$plugin/CHANGELOG.md"
reject symlink before
fixture
printf '{"value":1,"value":2}\n' >"$FIXTURE/$plugin/plugin.json"
git -C "$FIXTURE" add -- "$plugin/plugin.json"
reject duplicate-json before
fixture
printf '{"value":' >"$FIXTURE/$plugin/plugin.json"
git -C "$FIXTURE" add -- "$plugin/plugin.json"
reject partial-json before
fixture
printf '{}\n' >"$FIXTURE/$plugin/resources/new.desired-state.json"
git -C "$FIXTURE" add -- "$plugin/resources/new.desired-state.json"
reject new-profile before
printf 'PASS: skill metadata publication boundaries\n'
