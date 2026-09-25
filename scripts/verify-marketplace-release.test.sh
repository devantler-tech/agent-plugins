#!/usr/bin/env bash
# Real histories catch candidate tampering and release commits that include unreviewed content.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tool="$root/scripts/verify-marketplace-release.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
passed=0
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
new_repo() {
  repo=$(mktemp -d "$work/repo.XXXXXX")
  git -C "$repo" init -q
  git -C "$repo" config user.name Test
  git -C "$repo" config user.email test@example.invalid
  mkdir -p "$repo/.github/plugin" "$repo/.claude-plugin"
  printf '%s\n' '{"name":"test","metadata":{"version":"1.2.3"},"plugins":[{"name":"example","version":"4.5.6","source":"./plugins/example"}]}' > "$repo/.github/plugin/marketplace.json"
  cp "$repo/.github/plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
  printf 'unchanged\n' > "$repo/content"
  git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json content
  git -C "$repo" commit -qm 'Initial import'
}
prepare() {
  candidate="$work/candidate-$passed"
  source=$(git -C "$repo" rev-parse HEAD)
  (cd "$repo" && bash "$root/scripts/prepare-marketplace-release.sh" --base-tag "$1" --head "$source" --output "$candidate") >/dev/null
  release=$source
}
incremental() {
  new_repo
  git -C "$repo" tag v1.2.3
  git -C "$repo" commit --allow-empty -qm 'feat: add capability'
  prepare v1.2.3
  cp "$candidate/.github/plugin/marketplace.json" "$repo/.github/plugin/marketplace.json"
  cp "$candidate/.claude-plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
  git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json
  git -C "$repo" commit -qm 'chore(release): prepare 1.3.0'
  release=$(git -C "$repo" rev-parse HEAD)
}
run() { (cd "$repo" && bash "$tool" --candidate "$candidate" --source "$source" --release "$release"); }
accept() {
  local name=$1 version=$2
  run > "$work/result" 2> "$work/error" || { cat "$work/error"; fail "$name rejected"; }
  jq -e --arg source "$source" --arg release "$release" --arg version "$version" \
    '.status=="VERIFIED" and .authority=="assessment-only" and .publication=="NOT_AUTHORIZED" and .sourceCommit==$source and .releaseCommit==$release and .version==$version' "$work/result" >/dev/null || fail "$name verdict"
  passed=$((passed+1))
}
reject() {
  local name=$1
  if run > "$work/result" 2> "$work/error"; then fail "$name accepted"; fi
  test ! -s "$work/result" || fail "$name emitted a success assessment"
  passed=$((passed+1))
}
new_repo; prepare initial; accept 'initial source already has release metadata' 1.2.3
incremental; accept 'single-parent manifest-only release' 1.3.0
cp "$work/result" "$work/first"
run > "$work/second"; cmp "$work/first" "$work/second" || fail 'nondeterministic verdict'
passed=$((passed+1))
# Worktree contents are not evidence; the verifier must read the nominated commits.
git -C "$repo" show-ref > "$work/refs-before"
printf 'dirty\n' > "$repo/content"
printf 'ignored\n' > "$repo/local"
git -C "$repo" status --porcelain > "$work/status-before"
accept 'dirty checkout is neither read nor changed' 1.3.0
git -C "$repo" status --porcelain > "$work/status-after"
git -C "$repo" show-ref > "$work/refs-after"
cmp "$work/status-before" "$work/status-after"; cmp "$work/refs-before" "$work/refs-after"
for file in release.json RELEASE_NOTES.md .github/plugin/marketplace.json .claude-plugin/marketplace.json; do
  incremental; printf '\nmodified\n' >> "$candidate/$file"; reject "tampered $file"
  incremental; rm "$candidate/$file"; reject "missing $file"
  incremental; mv "$candidate/$file" "$work/real-file"; ln -s "$work/real-file" "$candidate/$file"; reject "symlink $file"; rm "$work/real-file"
done
incremental; mkdir "$candidate/extra"; reject 'extra directory'
incremental; printf x > "$candidate/extra"; reject 'extra file'
incremental; ln -s "$candidate" "$work/linked-candidate"; candidate="$work/linked-candidate"; reject 'symlink candidate root'
incremental; mkfifo "$candidate/unexpected-pipe"; reject 'special artifact is not read'
incremental; source=$(git -C "$repo" rev-parse v1.2.3); reject 'candidate from another source'
incremental; source=HEAD; reject 'symbolic source'
incremental; release=HEAD; reject 'symbolic release'
incremental; release=$(git -C "$repo" rev-parse 'HEAD^{tree}'); reject 'tree object as release'
incremental; release=$source; reject 'incremental version has not been committed'
incremental; printf 'unrelated\n' > "$repo/content"; git -C "$repo" add content; git -C "$repo" commit --amend --no-edit -q; release=$(git -C "$repo" rev-parse HEAD); reject 'unrelated file update'
incremental; chmod +x "$repo/content"; git -C "$repo" add content; git -C "$repo" commit --amend --no-edit -q; release=$(git -C "$repo" rev-parse HEAD); reject 'unrelated file mode update'
incremental; chmod +x "$repo/.github/plugin/marketplace.json"; git -C "$repo" add .github/plugin/marketplace.json; git -C "$repo" commit --amend --no-edit -q; release=$(git -C "$repo" rev-parse HEAD); reject 'manifest mode update'
incremental; git -C "$repo" commit --allow-empty -qm 'fix: later work'; release=$(git -C "$repo" rev-parse HEAD); reject 'stale source parent'
incremental; release=$(printf 'merge\n' | git -C "$repo" commit-tree "HEAD^{tree}" -p "$source" -p "$(git -C "$repo" rev-parse v1.2.3)"); reject 'merge commit'
incremental; jq '.plugins[0].version="9.0.0"' "$repo/.github/plugin/marketplace.json" > "$work/change"; cp "$work/change" "$repo/.github/plugin/marketplace.json"; git -C "$repo" add .github/plugin/marketplace.json; git -C "$repo" commit --amend --no-edit -q; release=$(git -C "$repo" rev-parse HEAD); reject 'unapproved plugin change'
incremental; git -C "$repo" tag v1.3.0 "$release"; reject 'already reserved release tag'
incremental; git -C "$repo" config remote.origin.promisor true; reject 'partial clone'
incremental; git -C "$repo" rev-parse HEAD > "$repo/.git/shallow"; reject 'shallow history'
new_repo; git -C "$repo" tag v1.2.3; git -C "$repo" commit --allow-empty -qm 'docs: explain'; prepare v1.2.3; reject 'no-release candidate'
new_repo
gitlink=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" update-index --add --cacheinfo "160000,$gitlink,vendor/module"
git -C "$repo" commit -qm 'feat: add linked resource'
prepare initial
git -C "$repo" update-index --cacheinfo "160000,$source,vendor/module"
git -C "$repo" commit -qm 'chore(release): unapproved linked resource change'
release=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" config diff.ignoreSubmodules all
reject 'local diff configuration cannot hide a changed gitlink'
printf 'PASS %s release verification cases\n' "$passed"
