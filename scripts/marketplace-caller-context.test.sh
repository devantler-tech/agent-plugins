#!/usr/bin/env bash
# Real independent checkouts prove public helpers cannot inherit a different Git repository.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
fixture() {
  local repo=$1
  mkdir -p "$repo/.github/plugin" "$repo/.claude-plugin"
  git -C "$repo" init -q
  git -C "$repo" config user.name Fixture
  git -C "$repo" config user.email fixture@example.invalid
  git -C "$repo" config commit.gpgsign false
  printf '%s\n' '{"name":"test","metadata":{"version":"1.2.3"},"plugins":[{"name":"example","version":"1.0.0","source":"./plugins/example"}]}' > "$repo/.github/plugin/marketplace.json"
  cp "$repo/.github/plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
  git -C "$repo" add -- .github/plugin/marketplace.json .claude-plugin/marketplace.json
  git -C "$repo" commit -qm "chore: $repo"
}
fixture "$work/intended"; fixture "$work/redirected"
head=$(git -C "$work/intended" rev-parse HEAD)
export GIT_DIR="$work/redirected/.git" GIT_WORK_TREE="$work/redirected" GIT_COMMON_DIR="$work/redirected/.git" GIT_INDEX_FILE="$work/redirected/.git/index" GIT_OBJECT_DIRECTORY="$work/redirected/.git/objects"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0="$work/redirected"
failed=0
(cd "$work/intended" && bash "$root/scripts/prepare-marketplace-release.sh" --base-tag initial --output "$work/candidate") > "$work/prepared"
if ! jq -e --arg head "$head" '.sourceCommit==$head' "$work/candidate/release.json" >/dev/null; then printf 'FAIL redirected source\n';failed=$((failed+1));fi
if (cd "$work/intended" && bash "$root/scripts/prepare-marketplace-release.sh" --base-tag initial --output "$work/intended/forbidden") > "$work/result" 2> "$work/error"; then printf 'FAIL wrote inside caller\n';failed=$((failed+1));fi
if ! (cd "$work/intended" && bash "$root/scripts/verify-marketplace-release.sh" --candidate "$work/candidate" --source "$head" --release "$head") > "$work/result" 2> "$work/error"; then printf 'FAIL redirected verifier\n';failed=$((failed+1));fi
printf 'caller context: %s failures\n' "$failed"
[ "$failed" -eq 0 ]
