#!/usr/bin/env bash
# Observe release artifacts in real independent repositories without network access.
# shellcheck disable=SC2016 # Inner bash snippets expand their own positional arguments.
set -euo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_PREFIX GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
passed=0 failed=0
# Accumulate assertions so every boundary has independent RED/GREEN evidence.
check() { if "$@"; then passed=$((passed+1)); else printf 'FAIL %s\n' "$label"; failed=$((failed+1)); fi; }
# Create a complete two-plugin baseline and one committed skill update.
fresh() {
  d=$(mktemp -d "$work/repo.XXXXXX")
  git -C "$d" init -q -b main
  git -C "$d" config user.name Fixture
  git -C "$d" config user.email fixture@example.invalid
  git -C "$d" config commit.gpgsign false
  mkdir -p "$d/.claude-plugin" "$d/.github/plugin"
  for n in alpha beta; do
    mkdir -p "$d/plugins/$n/.claude-plugin" "$d/plugins/$n/skills/example"
    printf '{"name":"%s","version":"1.2.3"}\n' "$n" > "$d/plugins/$n/plugin.json"
    cp "$d/plugins/$n/plugin.json" "$d/plugins/$n/.claude-plugin/plugin.json"
    printf '%s\n' '---' 'name: example' 'metadata:' '  github-repo: https://github.com/devantler-tech/agent-skills' '  github-ref: refs/tags/v1.0.0' '---' 'Example.' > "$d/plugins/$n/skills/example/SKILL.md"
    printf '## 1.2.3 — 2026-01-01\n\nOriginal history.\n' > "$d/plugins/$n/CHANGELOG.md"
  done
  printf '%s\n' '{"name":"fixture","plugins":[{"name":"alpha","version":"1.2.3","source":"./plugins/alpha"},{"name":"beta","version":"1.2.3","source":"./plugins/beta"}]}' > "$d/.claude-plugin/marketplace.json"
  cp "$d/.claude-plugin/marketplace.json" "$d/.github/plugin/marketplace.json"
  git -C "$d" add -- plugins .claude-plugin .github
  git -C "$d" commit -qm base
  base=$(git -C "$d" rev-parse HEAD)
  sed 's/v1.0.0/v2.0.0/' "$d/plugins/alpha/skills/example/SKILL.md" > "$d/next"
  mv "$d/next" "$d/plugins/alpha/skills/example/SKILL.md"
  git -C "$d" add -- plugins/alpha/skills/example/SKILL.md
  git -C "$d" commit -qm sync
  printf '%s\n' '{"name":"alpha","version":"1.2.4"}' > "$d/plugins/alpha/plugin.json"
}
# Capture only the actual helper's status and bytes, preserving later assertions.
run() { rc=0; (cd "$d" && "$@") > "$work/out" 2> "$work/err" || rc=$?; }
# Commit only the fixture-owned plugin paths.
commit() { git -C "$d" add -- plugins; git -C "$d" commit -qm change; }
# Snapshot all publication files independently of the index.
snapshot() { find "$d/plugins" "$d/.claude-plugin" "$d/.github" -type f -exec shasum {} + | LC_ALL=C sort; }
for mode in check write; do
  for selector in repository worktree index config; do
    fresh
    foreign=$(mktemp -d "$work/foreign.XXXXXX")
    git clone -q "$d" "$foreign"
    git -C "$foreign" checkout -q "$base"
    if [[ $mode == check ]]; then commit; arg=HEAD; else arg=2026-10-04; fi
    case $selector in
      repository) run env GIT_DIR="$foreign/.git" GIT_WORK_TREE="$foreign" bash "$here/plugin-changelog.sh" "$mode" "$base" "$arg" ;;
      worktree) run env GIT_WORK_TREE="$foreign" bash "$here/plugin-changelog.sh" "$mode" "$base" "$arg" ;;
      index) run env GIT_INDEX_FILE="$foreign/.git/index" bash "$here/plugin-changelog.sh" "$mode" "$base" "$arg" ;;
      config) run env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0="$foreign" bash "$here/plugin-changelog.sh" "$mode" "$base" "$arg" ;;
    esac
    label="$mode binds caller under $selector selector"
    if [[ $mode == check ]]; then check test "$rc" -ne 0
    else check bash -c '[[ $1 == 0 ]] && grep -Fq refs/tags/v2.0.0 "$2"' _ "$rc" "$d/plugins/alpha/CHANGELOG.md"; fi
  done
done
for kind in root plugin destination; do
  fresh
  outside=$(mktemp -d "$work/external.XXXXXX")
  case $kind in
    root) mv "$d/plugins" "$outside/plugins"; ln -s "$outside/plugins" "$d/plugins"; target="$outside/plugins/alpha/CHANGELOG.md" ;;
    plugin) mv "$d/plugins/alpha" "$outside/alpha"; ln -s "$outside/alpha" "$d/plugins/alpha"; target="$outside/alpha/CHANGELOG.md" ;;
    destination) mv "$d/plugins/alpha/CHANGELOG.md" "$outside/log"; ln -s "$outside/log" "$d/plugins/alpha/CHANGELOG.md"; target="$outside/log" ;;
  esac
  cp "$target" "$work/before"; cp "$d/plugins/beta/CHANGELOG.md" "$work/beta"
  run bash "$here/plugin-changelog.sh" write "$base" 2026-10-04
  label="linked $kind refuses whole write"; check test "$rc" -ne 0
  label="linked $kind preserves external and other plugin bytes"; check bash -c 'cmp "$1" "$2" && cmp "$3" "$4"' _ "$work/before" "$target" "$work/beta" "$d/plugins/beta/CHANGELOG.md"
done
for kind in altered missing linked; do
  fresh
  metadata="$d/plugins/alpha/skills/example/SKILL.md"
  case $kind in
    altered) sed 's/v2.0.0/v99.0.0/' "$metadata" > "$d/next"; mv "$d/next" "$metadata" ;;
    missing) rm "$metadata" ;;
    linked) printf 'wrong uncommitted provenance\n' > "$d/wrong"; rm "$metadata"; ln -s "$d/wrong" "$metadata" ;;
  esac
  run bash "$here/plugin-changelog.sh" write "$base" 2026-10-04
  label="committed provenance survives $kind working copy"; check bash -c '[[ $1 == 0 ]] && grep -Fq refs/tags/v2.0.0 "$2" && ! grep -Fq v99.0.0 "$2"' _ "$rc" "$d/plugins/alpha/CHANGELOG.md"
done
fresh
rm "$d/plugins/alpha/skills/example/SKILL.md"
ln -s other "$d/plugins/alpha/skills/example/SKILL.md"
commit; snapshot > "$work/before"
run bash "$here/plugin-changelog.sh" write "$base" 2026-10-04
label='nonregular committed provenance refuses'; check test "$rc" -ne 0
snapshot > "$work/after"; label='nonregular committed provenance preserves batch'; check cmp "$work/before" "$work/after"
for target in marketplace portable; do
  for kind in scalar container escaped; do
    fresh
    if [[ $target == marketplace ]]; then
      file="$d/.claude-plugin/marketplace.json"
      case $kind in
        scalar) printf '%s\n' '{"name":"fixture","name":"fixture","plugins":[{"name":"alpha","version":"1.2.3","source":"./plugins/alpha"}]}' > "$file" ;;
        container) printf '%s\n' '{"plugins":[{"name":"beta","version":"1.2.3"}],"plugins":[{"name":"alpha","version":"1.2.3","source":"./plugins/alpha"}]}' > "$file" ;;
        escaped) printf '%s\n' '{"plugins":[],"\u0070lugins":[{"name":"alpha","version":"1.2.3","source":"./plugins/alpha"}]}' > "$file" ;;
      esac
      cp "$d/plugins/alpha/.claude-plugin/plugin.json" "$d/plugins/alpha/plugin.json"
      snapshot > "$work/before"
      run bash "$here/bump-plugin-version.sh" alpha patch
    else
      file="$d/plugins/alpha/plugin.json"
      case $kind in
        scalar) printf '%s\n' '{"version":"1.2.4","version":"1.2.3"}' > "$file" ;;
        container) printf '%s\n' '{"version":"1.2.3","extra":{},"extra":{}}' > "$file" ;;
        escaped) printf '%s\n' '{"version":"1.2.4","\u0076ersion":"1.2.3"}' > "$file" ;;
      esac
      commit; snapshot > "$work/before"
      run bash "$here/plugin-changelog.sh" check "$base" HEAD
    fi
    label="$target repeated $kind refuses"; check test "$rc" -ne 0
    snapshot > "$work/after"; label="$target repeated $kind preserves all bytes"; check cmp "$work/before" "$work/after"
  done
done
for mode in check write; do
  fresh
  tree=$(git -C "$d" rev-parse "$base^{tree}")
  git -C "$d" add -- plugins/alpha/plugin.json
  changed_tree=$(git -C "$d" write-tree)
  a=$(printf 'First base\n' | git -C "$d" commit-tree "$changed_tree" -p "$base")
  b=$(printf 'Other base\n' | git -C "$d" commit-tree "$tree" -p "$base")
  head=$(printf 'Head\n' | git -C "$d" commit-tree "$changed_tree" -p "$a" -p "$b")
  comparison=$(printf 'Comparison\n' | git -C "$d" commit-tree "$tree" -p "$b" -p "$a")
  git -C "$d" checkout -q "$head"
  snapshot > "$work/before"
  if [[ $mode == check ]]; then arg="$head"; else arg=2026-10-04; fi
  run bash "$here/plugin-changelog.sh" "$mode" "$comparison" "$arg"
  label="$mode ambiguous merge bases refuse"; check test "$rc" -ne 0
  snapshot > "$work/after"; label="$mode ambiguous history preserves bytes"; check cmp "$work/before" "$work/after"
  fresh
  clone=$(mktemp -d "$work/shallow.XXXXXX")
  git clone -q --depth=1 "file://$d" "$clone"
  d=$clone
  run bash "$here/plugin-changelog.sh" "$mode" HEAD "$([[ $mode == check ]] && printf HEAD || printf 2026-10-04)"
  label="$mode shallow history refuses"; check test "$rc" -ne 0
done
printf 'release artifact boundaries: %s passes, %s failures\n' "$passed" "$failed"
[[ $failed == 0 ]]
