#!/usr/bin/env bash
# Real branch histories: removing exact candidate verification admits the wrong-version case.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tool="$root/scripts/check-marketplace-version.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
passed=0
# Stop at the first violated observable contract.
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
# Build an independent tagged history; fixture commits are never pushed.
fixture() {
  repo=$(mktemp -d "$work/repo.XXXXXX")
  git -C "$repo" init -q
  git -C "$repo" config user.name Test
  git -C "$repo" config user.email test@example.invalid
  mkdir -p "$repo/.github/plugin" "$repo/.claude-plugin"
  printf '%s\n' '{"name":"test","metadata":{"version":"1.2.3"},"plugins":[{"name":"example","version":"4.5.6","source":"./plugins/example"}]}' > "$repo/.github/plugin/marketplace.json"
  cp "$repo/.github/plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
  git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json
  git -C "$repo" commit -qm 'Initial import'
  git -C "$repo" tag v1.2.3
  git -C "$repo" commit --allow-empty -qm "${1:-feat: capability}"
  base=$(git -C "$repo" rev-parse HEAD)
  head=$base
}
# Commit exactly the proposed manifests on the independently selected base.
proposal() {
  candidate=$(mktemp -d "$work/holder.XXXXXX")/candidate
  (cd "$repo" && bash "$root/scripts/prepare-marketplace-release.sh" --base-tag v1.2.3 --head "$base" --output "$candidate") >/dev/null
  cp "$candidate/.github/plugin/marketplace.json" "$repo/.github/plugin/marketplace.json"
  cp "$candidate/.claude-plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
  commit_pair
}
# Record deliberate fixture changes and refresh the tested head identity.
commit_pair() {
  git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json
  git -C "$repo" commit -qm 'chore(release): update marketplace'
  head=$(git -C "$repo" rev-parse HEAD)
}
# Change the fixture's version without using the generator.
set_version() {
  jq --arg version "$1" '.metadata.version=$version' "$repo/.github/plugin/marketplace.json" > "$work/changed"
  cp "$work/changed" "$repo/.github/plugin/marketplace.json"
  cp "$work/changed" "$repo/.claude-plugin/marketplace.json"
  commit_pair
}
# Invoke the real gate, never code from the fixture history.
run() { (cd "$repo" && bash "$tool" "$base" "$head"); }
# Assert a structured verdict bound to the selected commits.
accept() {
  local name=$1 status=$2
  run > "$work/result" 2> "$work/error" || { cat "$work/error"; fail "$name rejected"; }
  jq -e --arg status "$status" '.status==$status and .publication=="NOT_AUTHORIZED"' "$work/result" >/dev/null || fail "$name verdict"
  if [ "$status" = VERIFIED ]; then
    jq -e --arg base "$base" --arg head "$head" '.sourceCommit==$base and .releaseCommit==$head' "$work/result" >/dev/null || fail "$name identities"
  fi
  passed=$((passed+1))
}
# A refusal must not leave a success record on stdout.
reject() {
  local name=$1
  if run > "$work/result" 2> "$work/error"; then fail "$name accepted"; fi
  [ ! -s "$work/result" ] || fail "$name emitted success output"
  passed=$((passed+1))
}
fixture; set_version 9.0.0; reject 'arbitrary version'
fixture; proposal; accept 'generated minor proposal' VERIFIED
fixture 'fix: repair'; proposal; accept 'generated patch proposal' VERIFIED
fixture 'feat!: break'; proposal; accept 'generated major proposal' VERIFIED
fixture; accept 'unchanged version' NO_VERSION_CHANGE
fixture; git -C "$repo" tag -d v1.2.3 >/dev/null; accept 'ordinary work before first release' NO_VERSION_CHANGE
fixture; proposal
cp "$work/result" "$work/old-result"
printf 'dirty\n' > "$repo/.github/plugin/marketplace.json"
git -C "$repo" status --porcelain > "$work/status-before"
git -C "$repo" show-ref > "$work/refs-before"
accept 'dirty checkout is not evidence' VERIFIED
git -C "$repo" status --porcelain > "$work/status-after"
git -C "$repo" show-ref > "$work/refs-after"
cmp "$work/status-before" "$work/status-after"; cmp "$work/refs-before" "$work/refs-after"
run > "$work/repeated"; cmp "$work/result" "$work/repeated"; passed=$((passed+1))
fixture 'docs: explain'; set_version 1.2.4; reject 'no releasable changes'
fixture; proposal; git -C "$repo" tag -d v1.2.3 >/dev/null; reject 'missing baseline'
fixture; proposal; git -C "$repo" tag v1.3.0 "$head"; reject 'occupied release tag'
fixture; proposal; base=$(git -C "$repo" rev-parse v1.2.3); reject 'wrong source parent'
fixture; proposal; git -C "$repo" commit --allow-empty -qm 'docs: extra commit'; head=$(git -C "$repo" rev-parse HEAD); reject 'extra proposal commit'
fixture; proposal; base=$(printf 'docs: concurrent main change\n' | git -C "$repo" commit-tree "$base^{tree}" -p "$base"); reject 'main moved'
# An old ordinary PR must not be blamed for a release that landed on its base.
fixture; old_base=$base; proposal; base=$head
head=$(printf 'docs: ordinary branch\n' | git -C "$repo" commit-tree "$old_base^{tree}" -p "$old_base")
accept 'ordinary branch behind marketplace release' NO_VERSION_CHANGE
fixture; proposal; head=$(printf 'merge\n' | git -C "$repo" commit-tree "$head^{tree}" -p "$base" -p "$(git -C "$repo" rev-parse v1.2.3)"); reject 'merge commit instead of proposal'
fixture; proposal; printf 'unrelated\n' > "$repo/unrelated"; git -C "$repo" add unrelated; git -C "$repo" commit --amend --no-edit -q; head=$(git -C "$repo" rev-parse HEAD); reject 'unrelated content'
fixture; proposal; chmod +x "$repo/.github/plugin/marketplace.json"; git -C "$repo" add .github/plugin/marketplace.json; git -C "$repo" commit --amend --no-edit -q; head=$(git -C "$repo" rev-parse HEAD); reject 'manifest mode change'
fixture; proposal; jq '.plugins[0].version="9.0.0"' "$repo/.github/plugin/marketplace.json" > "$work/changed"; cp "$work/changed" "$repo/.github/plugin/marketplace.json"; cp "$work/changed" "$repo/.claude-plugin/marketplace.json"; git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json; git -C "$repo" commit --amend --no-edit -q; head=$(git -C "$repo" rev-parse HEAD); reject 'plugin version changed with marketplace'
fixture; printf '{broken\n' > "$repo/.github/plugin/marketplace.json"; commit_pair; reject 'malformed manifest'
fixture; jq '.metadata.version="1.3.0"' "$repo/.github/plugin/marketplace.json" > "$work/changed"; cp "$work/changed" "$repo/.github/plugin/marketplace.json"; commit_pair; reject 'manifest disagreement'
fixture; rm "$repo/.github/plugin/marketplace.json"; commit_pair; reject 'missing manifest'
fixture; rm "$repo/.github/plugin/marketplace.json"; ln -s ../../.claude-plugin/marketplace.json "$repo/.github/plugin/marketplace.json"; commit_pair; reject 'symlink manifest'
fixture; printf '%s\n%s\n' '{"metadata":{"version":"1.2.3"}}' '{}' > "$repo/.github/plugin/marketplace.json"; commit_pair; reject 'multiple JSON documents'
fixture; sed 's/"version":"1.2.3"/"version":"9.0.0","version":"1.2.3"/' "$repo/.github/plugin/marketplace.json" > "$work/changed"; cp "$work/changed" "$repo/.github/plugin/marketplace.json"; cp "$work/changed" "$repo/.claude-plugin/marketplace.json"; commit_pair; reject 'duplicate version hidden behind unchanged value'
fixture; base=HEAD; reject 'symbolic base'
fixture; head=HEAD; reject 'symbolic head'
fixture; head=$(git -C "$repo" rev-parse 'HEAD^{tree}'); reject 'noncommit head'
fixture; head=0000000000000000000000000000000000000000; reject 'missing commit'
fixture; head=$(printf 'orphan\n' | git -C "$repo" commit-tree "$base^{tree}"); reject 'unrelated histories'
fixture; git -C "$repo" rev-parse HEAD > "$repo/.git/shallow"; reject 'shallow unchanged history'
fixture; git -C "$repo" config remote.origin.promisor true; reject 'partial unchanged history'
printf 'PASS %s marketplace version gate cases\n' "$passed"
