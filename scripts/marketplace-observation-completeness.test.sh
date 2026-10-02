#!/usr/bin/env bash
# Real release histories with incomplete observations at external command boundaries.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
real_git=$(command -v git)
real_find=$(command -v find)
export REAL_GIT="$real_git" REAL_FIND="$real_find"
passed=0 failed=0
fixture() {
  repo=$(mktemp -d "$work/repo.XXXXXX")
  repo=$(cd "$repo" && pwd -P)
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
  git -C "$repo" commit --allow-empty -qm 'feat: capability'
  source=$(git -C "$repo" rev-parse HEAD)
  candidate=$(mktemp -d "$work/holder.XXXXXX")/candidate
  (cd "$repo" && bash "$root/scripts/prepare-marketplace-release.sh" --base-tag v1.2.3 --head "$source" --output "$candidate") >/dev/null
  candidate=$(cd "$candidate" && pwd -P)
  cp "$candidate/.github/plugin/marketplace.json" "$repo/.github/plugin/marketplace.json"
  cp "$candidate/.claude-plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
  git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json
  git -C "$repo" commit -qm 'chore(release): proposal'
  release=$(git -C "$repo" rev-parse HEAD)
}
run() {
  case "$mode" in
    inspect) (cd "$repo" && bash "$root/scripts/verify-marketplace-release.sh" --candidate "$candidate" --source "$source" --release "$release" --inspect-existing) ;;
    verify) (cd "$repo" && bash "$root/scripts/verify-marketplace-release.sh" --candidate "$candidate" --source "$source" --release "$release") ;;
    version) (cd "$repo" && bash "$root/scripts/check-marketplace-version.sh" "$source" "$source") ;;
    prepare) (cd "$repo" && bash "$root/scripts/prepare-marketplace-release.sh" --base-tag v1.2.3 --head "$source" --output "$destination") ;;
  esac
}
refuse() {
  local name=$1
  if run > "$work/result" 2> "$work/error"; then
    printf 'FAIL %s was accepted\n' "$name" >&2; failed=$((failed+1))
  elif [ -s "$work/result" ]; then
    printf 'FAIL %s emitted a success record\n' "$name" >&2; failed=$((failed+1))
  elif [ -n "${2:-}" ] && ! grep -Fq "$2" "$work/error"; then
    printf 'FAIL %s refused for another reason: %s\n' "$name" "$(cat "$work/error")" >&2; failed=$((failed+1))
  else
    passed=$((passed+1))
  fi
}
mkdir "$work/bin"
cat > "$work/bin/git" <<'STUB'
#!/usr/bin/env bash
if { [ "${1:-}" = -C ] && [ "${2:-}" = "$OBS_REPO" ] && [ "${3:-}" = config ]; } ||
   { [ "${1:-}" = config ] && [ "$PWD" = "$OBS_REPO" ]; }; then
  case "$OBS_FAULT:$*" in
    extension:*extensions.partialClone*) printf 'origin\n'; exit 1 ;;
    promisor:*promisor*) printf 'remote.origin.promisor false\n'; exit 1 ;;
    extension-newline:*extensions.partialClone*) printf '\n'; exit 1 ;;
    promisor-newline:*promisor*) printf '\n'; exit 1 ;;
  esac
fi
if [ "$OBS_FAULT" = graft ] && [ "${1:-}" = rev-parse ] && [ "${2:-}" = --git-path ]; then exit 1; fi
if [ "$OBS_FAULT" = changes ] && [ "${1:-}" = diff-tree ]; then
  printf '.claude-plugin/marketplace.json\0.github/plugin/marketplace.json\0content'
  exit 0
fi
if [ "$OBS_FAULT" = worktrees ] && [ "${1:-}" = worktree ] && [ "${2:-}" = list ]; then
  printf 'worktree %s\0HEAD %s\0branch refs/heads/main\0\0worktree %s' "$OBS_REPO" "$OBS_SOURCE" "$OBS_OTHER"
  exit 0
fi
exec "$REAL_GIT" "$@"
STUB
cat > "$work/bin/find" <<'STUB'
#!/usr/bin/env bash
if [ "$OBS_FAULT" = artifacts ] && [ "${1:-}" = "$OBS_CANDIDATE" ]; then
  "$REAL_FIND" "$1" -mindepth 1 ! -name extra -print0
  printf '%s/extra' "$1"
  exit 0
fi
exec "$REAL_FIND" "$@"
STUB
chmod +x "$work/bin/git" "$work/bin/find"
fixture; mode=inspect
run > "$work/result"
jq -e '.status=="INSPECTED" and .publication=="NOT_AUTHORIZED"' "$work/result" >/dev/null
passed=$((passed+1))
git -C "$repo" config extensions.partialClone ''
refuse 'defined empty partial-clone extension remains refused'
for fault in extension promisor extension-newline promisor-newline; do
  fixture; mode=inspect
  PATH="$work/bin:$PATH" REAL_GIT="$real_git" OBS_REPO="$repo" OBS_FAULT="$fault" refuse "partial failed $fault configuration" 'unreadable partial-clone configuration'
done
fixture; mode=version
PATH="$work/bin:$PATH" REAL_GIT="$real_git" OBS_FAULT=graft refuse 'failed graft-path observation' 'graft path is unreadable'
fixture; mode=verify; printf extra > "$candidate/extra"
refuse 'complete inventory catches extra artifact'
PATH="$work/bin:$PATH" REAL_GIT="$real_git" REAL_FIND="$real_find" OBS_FAULT=artifacts OBS_CANDIDATE="$candidate" refuse 'unterminated extra artifact' 'unterminated record'
fixture; mode=verify
printf changed > "$repo/content"; git -C "$repo" add content; git -C "$repo" commit --amend --no-edit -q
release=$(git -C "$repo" rev-parse HEAD)
refuse 'complete inventory catches unrelated content'
PATH="$work/bin:$PATH" REAL_GIT="$real_git" OBS_FAULT=changes refuse 'unterminated release change' 'unterminated record'
fixture; mode=prepare
other=$(mktemp -d "$work/other.XXXXXX"); rmdir "$other"
git -C "$repo" worktree add --detach -q "$other" "$source"
destination="$other/candidate"
refuse 'complete census catches a destination inside another worktree'
PATH="$work/bin:$PATH" REAL_GIT="$real_git" OBS_FAULT=worktrees OBS_REPO="$repo" OBS_SOURCE="$source" OBS_OTHER="$other" refuse 'unterminated final worktree' 'unterminated record'
if [ -e "$destination" ]; then printf 'FAIL refused worktree census created output\n' >&2; failed=$((failed+1)); fi
printf 'PASS %s marketplace observation cases; FAIL %s\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
