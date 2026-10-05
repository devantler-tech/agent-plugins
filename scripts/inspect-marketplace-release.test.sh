#!/usr/bin/env bash
# Exercise historical inspection through the public verifier with real Git histories.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tool="$root/scripts/verify-marketplace-release.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
passed=0
# Stop the suite at the first contract mismatch.
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
# Build a real baseline, feature source, four-file candidate and version-only release.
fixture() {
  repo=$(mktemp -d "$work/repo.XXXXXX")
  repo=$(cd "$repo" && pwd -P)
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE GIT_CONFIG_PARAMETERS \
    GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM
  git -C "$repo" init -q
  git -C "$repo" config user.name Test
  git -C "$repo" config user.email test@example.invalid
  mkdir -p "$repo/.github/plugin" "$repo/.claude-plugin"
  printf '%s\n' '{"name":"test","metadata":{"version":"1.2.3"},"plugins":[{"name":"example","version":"4.5.6","source":"./plugins/example"}]}' > "$repo/.github/plugin/marketplace.json"
  cp "$repo/.github/plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
  printf 'original\n' > "$repo/content"
  git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json content
  git -C "$repo" commit -qm 'Initial import'
  git -C "$repo" tag v1.2.3
  git -C "$repo" commit --allow-empty -qm 'feat: add capability'
  source=$(git -C "$repo" rev-parse HEAD)
  candidate=$(mktemp -d "$work/artifact.XXXXXX"); rmdir "$candidate"
  (cd "$repo" && bash "$root/scripts/prepare-marketplace-release.sh" --base-tag v1.2.3 --head "$source" --output "$candidate") >/dev/null
  cp "$candidate/.github/plugin/marketplace.json" "$repo/.github/plugin/marketplace.json"
  cp "$candidate/.claude-plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
  git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json
  git -C "$repo" commit -qm 'chore(release): prepare 1.3.0'
  release=$(git -C "$repo" rev-parse HEAD)
}
# Exercise the public entrypoint against the selected fixture and explicit options.
run() { (cd "$repo" && bash "$tool" --candidate "$candidate" --source "$source" --release "$release" "$@"); }
# Require a non-authoritative historical verdict and the expected local tag observation.
accept() {
  local name=$1 state=$2 matches=$3
  run --inspect-existing > "$work/result" 2> "$work/error" || { cat "$work/error"; fail "$name rejected"; }
  jq -e --arg source "$source" --arg release "$release" --arg state "$state" --argjson matches "$matches" '
    .schemaVersion==1 and .status=="INSPECTED" and .scope=="local-historical-content"
    and .sourceCommit==$source and .releaseCommit==$release and .tag=="v1.3.0"
    and .authority=="assessment-only" and .publication=="NOT_AUTHORIZED"
    and .proposal=="NOT_AUTHORIZED" and .readiness=="NOT_ASSESSED" and .remoteState=="UNKNOWN"
    and .localTag.state==$state and .localTag.targetsRelease==$matches
  ' "$work/result" >/dev/null || fail "$name verdict"
  passed=$((passed+1))
}
# Require nonzero refusal with no leaked successful result.
reject() {
  local name=$1; shift
  if run --inspect-existing "$@" > "$work/result" 2> "$work/error"; then fail "$name accepted"; fi
  [ ! -s "$work/result" ] || fail "$name emitted success"
  passed=$((passed+1))
}
# Capture caller refs, dirty/untracked files and index checksum for before/after comparison.
snapshot() {
  git -C "$repo" for-each-ref --sort=refname --format='%(refname) %(objectname)' > "$1.refs"
  git -C "$repo" status --porcelain > "$1.status"
  cksum "$repo/.git/index" > "$1.index"
}
# A subprocess exercises the real fixture setup under a foreign inherited Git layout.
if [ "${1:-}" = --fixture-isolation-check ]; then
  [ "$#" -eq 1 ] || fail 'one fixture isolation option is supported'
  fixture; run --inspect-existing > "$work/result"
  jq -e '.status=="INSPECTED" and .localTag.state=="ABSENT"' "$work/result" >/dev/null
  exit 0
fi
[ "$#" -eq 0 ] || fail 'unknown suite option'
fixture
run > "$work/default"
jq -e '.status=="VERIFIED" and .scope=="local-prepublication"' "$work/default" >/dev/null
passed=$((passed+1))
accept 'absent tag is an inspection, never prepublication clearance' ABSENT null
fixture
newline_repo="$repo"$'\n'
mv "$repo" "$newline_repo"; repo=$newline_repo
snapshot "$work/newline-before"
accept 'exact trailing-newline checkout identity' ABSENT null
snapshot "$work/newline-after"
for field in refs status index; do
  cmp "$work/newline-before.$field" "$work/newline-after.$field" || fail "newline checkout $field changed"
done
passed=$((passed+1))
git -C "$repo" tag v1.3.0 "$release"
if run > "$work/default" 2> "$work/error"; then fail 'default mode accepted occupied tag'; fi
[ ! -s "$work/default" ] || fail 'default emitted clearance'
passed=$((passed+1))
printf 'dirty\n' > "$repo/content"
printf 'untracked\n' > "$repo/local"
snapshot "$work/before"
accept 'published lightweight tag' PRESENT true
for field in refs status index; do snapshot "$work/after"; cmp "$work/before.$field" "$work/after.$field" || fail "caller $field changed"; done
passed=$((passed+1))
run --inspect-existing > "$work/repeat"
cmp "$work/result" "$work/repeat" || fail 'nondeterministic inspection'
passed=$((passed+1))
if run > "$work/default" 2> "$work/error"; then fail 'inspection removed the caller tag'; fi
passed=$((passed+1))

fixture; git -C "$repo" tag -a -m 'release' v1.3.0 "$release"; accept 'annotated commit tag' PRESENT true
tag_object=$(git -C "$repo" rev-parse refs/tags/v1.3.0)
jq -e --arg oid "$tag_object" --arg commit "$release" '.localTag.objectOid==$oid and .localTag.commitOid==$commit' "$work/result" >/dev/null
passed=$((passed+1))
fixture; git -C "$repo" tag v1.3.0 "$source"; accept 'retained proposal differs from the occupied tag' PRESENT false
fixture; git -C "$repo" tag v1.3.0 'HEAD^{tree}'; reject 'non-commit candidate tag'

for file in release.json RELEASE_NOTES.md .github/plugin/marketplace.json .claude-plugin/marketplace.json; do
  fixture; git -C "$repo" tag v1.3.0 "$release"; printf '\nmodified\n' >> "$candidate/$file"; reject "tampered $file"
  fixture; rm "$candidate/$file"; reject "missing $file"
  fixture; mv "$candidate/$file" "$work/saved"; ln -s "$work/saved" "$candidate/$file"; reject "symlink $file"; rm "$work/saved"
done
fixture; ln -s "$candidate" "$work/link"; candidate="$work/link"; reject 'symlink candidate root'
fixture; mkfifo "$candidate/extra-pipe"; reject 'special artifact'
fixture; printf x > "$candidate/extra"; reject 'unexpected artifact'
fixture; source=HEAD; reject 'symbolic source'
fixture; release=HEAD; reject 'symbolic release'
fixture; reject 'duplicate inspection flag' --inspect-existing
fixture; git -C "$repo" config remote.origin.promisor true; reject 'partial source clone'
fixture; git -C "$repo" rev-parse HEAD > "$repo/.git/shallow"; reject 'shallow source history'
fixture; mkdir -p "$repo/.git/info"; printf 'grafted\n' > "$repo/.git/info/grafts"; reject 'grafted source history'
fixture; mkdir -p "$repo/sub" "$repo/.git/info"; printf '%s\n' "$source" > "$repo/.git/info/grafts"
if (cd "$repo/sub" && bash "$tool" --candidate "$candidate" --source "$source" --release "$release" --inspect-existing) > "$work/result" 2> "$work/error"; then
  fail 'grafted source inspected from a subdirectory was accepted'
fi
[ ! -s "$work/result" ] || fail 'subdirectory graft refusal emitted success'
grep -q 'grafted history is unsupported' "$work/error" || fail 'subdirectory graft was refused for another reason'
passed=$((passed+1))
fixture; git -C "$repo" tag v1.3.0 "$release"; printf changed > "$repo/content"; git -C "$repo" add content; git -C "$repo" commit --amend --no-edit -q; release=$(git -C "$repo" rev-parse HEAD); reject 'unrelated release content'
fixture; chmod +x "$repo/.github/plugin/marketplace.json"; git -C "$repo" add .github/plugin/marketplace.json; git -C "$repo" commit --amend --no-edit -q; release=$(git -C "$repo" rev-parse HEAD); reject 'changed manifest mode'
fixture; git -C "$repo" commit --allow-empty -qm 'fix: later work'; release=$(git -C "$repo" rev-parse HEAD); reject 'wrong source parent'

# Inherited Git layout overrides must never redirect the private tag deletion.
fixture; git -C "$repo" tag v1.3.0 "$release"
foreign=$(mktemp -d "$work/foreign.XXXXXX")
git clone --shared --no-checkout -q "$repo" "$foreign"
foreign_tag=$(git -C "$foreign" rev-parse refs/tags/v1.3.0)
cp "$foreign/.git/config" "$work/foreign-config-before"
git -C "$foreign" for-each-ref --sort=refname --format='%(refname) %(objectname)' > "$work/foreign-refs-before"
GIT_DIR="$foreign/.git" GIT_WORK_TREE="$foreign" bash "${BASH_SOURCE[0]}" --fixture-isolation-check || fail 'inherited fixture layout was not isolated'
cmp "$work/foreign-config-before" "$foreign/.git/config" || fail 'fixture changed foreign configuration'
git -C "$foreign" for-each-ref --sort=refname --format='%(refname) %(objectname)' > "$work/foreign-refs-after"
cmp "$work/foreign-refs-before" "$work/foreign-refs-after" || fail 'fixture changed foreign refs'
passed=$((passed+1))
GIT_DIR="$foreign/.git" GIT_WORK_TREE="$foreign" accept 'inherited foreign Git layout is neutralized' PRESENT true
[ "$(git -C "$foreign" rev-parse refs/tags/v1.3.0)" = "$foreign_tag" ] || fail 'foreign tag changed'
passed=$((passed+1))
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0="$foreign" accept 'inherited worktree configuration is neutralized' PRESENT true
[ "$(git -C "$foreign" rev-parse refs/tags/v1.3.0)" = "$foreign_tag" ] || fail 'configured foreign tag changed'
passed=$((passed+1))

# Initial inspection preserves the no-other-stable-tags history requirement.
fixture
source=$(git -C "$repo" rev-parse v1.2.3); release=$source
git -C "$repo" tag -d v1.2.3 >/dev/null
candidate=$(mktemp -d "$work/initial.XXXXXX"); rmdir "$candidate"
(cd "$repo" && bash "$root/scripts/prepare-marketplace-release.sh" --base-tag initial --head "$source" --output "$candidate") >/dev/null
git -C "$repo" tag v1.2.3 "$release"
run --inspect-existing > "$work/result"
jq -e '.status=="INSPECTED" and .tag=="v1.2.3" and .localTag.targetsRelease==true' "$work/result" >/dev/null
passed=$((passed+1))
git -C "$repo" tag v9.0.0 "$release"; reject 'initial history with another stable tag'

# A concurrent ref writer at the final observation must invalidate the result.
real_git=$(command -v git)
mkdir "$work/bin"
cat > "$work/bin/git" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = -C ] && [ "${2:-}" = "$MOVE_REPO" ] && [ "${3:-}" = for-each-ref ]; then
  count=$(cat "$MOVE_COUNT"); count=$((count+1)); printf '%s' "$count" > "$MOVE_COUNT"
  if [ "$count" -eq 2 ]; then "$REAL_GIT" -C "$MOVE_REPO" update-ref refs/tags/v1.3.0 "$MOVE_TARGET"; fi
fi
exec "$REAL_GIT" "$@"
STUB
chmod +x "$work/bin/git"
fixture; git -C "$repo" tag v1.3.0 "$release"; printf 0 > "$work/move-count"
REAL_GIT="$real_git" MOVE_REPO="$repo" MOVE_TARGET="$source" MOVE_COUNT="$work/move-count" PATH="$work/bin:$PATH" reject 'moving tag inventory'
grep -q 'tag inventory changed' "$work/error" || fail 'movement was rejected for another reason'
printf 'PASS %s historical inspection cases\n' "$passed"
