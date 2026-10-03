#!/usr/bin/env bash
# Exercise exact Git identity, complete inventory and safe version writes offline.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
real_git=$(command -v git)
export REAL_GIT="$real_git"
fail=0
check() { if "$@"; then printf 'PASS %s\n' "$label"; else printf 'FAIL %s\n' "$label"; fail=$((fail+1)); fi; }
fresh() {
  d=$(mktemp -d "$work/repo.XXXXXX")
  git -C "$d" init -q --initial-branch=main
  git -C "$d" config user.name Fixture
  git -C "$d" config user.email fixture@example.test
  git -C "$d" config commit.gpgsign false
  mkdir -p "$d/.claude-plugin" "$d/.github/plugin" "$d/plugins/alpha/.claude-plugin" "$d/plugins/beta/.claude-plugin"
  for name in alpha beta; do
    printf '{"name":"%s","version":"1.2.3"}\n' "$name" > "$d/plugins/$name/plugin.json"
    cp "$d/plugins/$name/plugin.json" "$d/plugins/$name/.claude-plugin/plugin.json"
    printf 'original\n' > "$d/plugins/$name/body.md"
  done
  printf '%s\n' '{"name":"fixture","plugins":[{"name":"alpha","version":"1.2.3","source":"./plugins/alpha"},{"name":"beta","version":"1.2.3","source":"./plugins/beta"}]}' > "$d/.claude-plugin/marketplace.json"
  cp "$d/.claude-plugin/marketplace.json" "$d/.github/plugin/marketplace.json"
  git -C "$d" add plugins .claude-plugin .github
  git -C "$d" commit -qm base
  git -C "$d" checkout -qb feature
}
commit() { git -C "$d" add plugins .claude-plugin .github; git -C "$d" commit -qm change; }
run_gate() { rc=0; (cd "$d" && bash "$here/check-plugin-version-bump.sh" main HEAD) > "$work/out" 2> "$work/err" || rc=$?; }
run_writer() { rc=0; (cd "$d" && bash "$here/bump-plugin-version.sh" --changed-since main) > "$work/out" 2> "$work/err" || rc=$?; }
for tool in gate writer; do
  fresh; printf 'changed\n' > "$d/plugins/alpha/body.md"; commit
  replacement=$(printf 'replacement\n' | git -C "$d" commit-tree "$(git -C "$d" rev-parse 'main^{tree}')" -p main)
  git -C "$d" replace HEAD "$replacement"
  "run_$tool"
  if [[ $tool == gate ]]; then label='replacement objects cannot hide an unbumped change'; check test "$rc" -ne 0
  else label='writer bumps original committed content despite replacement objects'; check test "$(jq -r .version "$d/plugins/alpha/plugin.json")" = 1.2.4; fi

  fresh; printf 'changed\n' > "$d/plugins/alpha/body.md"; commit
  changed_head=$(git -C "$d" rev-parse HEAD)
  git -C "$d" checkout -q main; printf 'base advanced\n' > "$d/root.md"; git -C "$d" add root.md; git -C "$d" commit -qm advance
  base=$(git -C "$d" rev-parse HEAD); git -C "$d" checkout -q feature
  printf '%s %s\n' "$base" "$changed_head" > "$d/.git/info/grafts"
  "run_$tool"; label="$tool refuses grafted ancestry"; check test "$rc" -ne 0

  fresh; target=$d; foreign=$(mktemp -d "$work/foreign.XXXXXX")
  git clone -q "$target" "$foreign"; git -C "$foreign" branch -f main HEAD
  printf 'changed\n' > "$d/plugins/alpha/body.md"; commit
  GIT_DIR="$foreign/.git" GIT_WORK_TREE="$foreign" "run_$tool"
  if [[ $tool == gate ]]; then label='caller Git context cannot clear the current checkout'; check test "$rc" -ne 0
  else label='writer reads the current checkout despite caller Git context'; check test "$(jq -r .version "$d/plugins/alpha/plugin.json")" = 1.2.4; fi

  fresh
  printf '%s\n' '{"name":"alpha","version":"1.2.3","version":"1.2.2"}' > "$d/plugins/alpha/.claude-plugin/plugin.json"
  commit; git -C "$d" branch -f main HEAD
  printf '%s\n' '{"name":"alpha","version":"1.2.3"}' > "$d/plugins/alpha/.claude-plugin/plugin.json"
  printf 'changed\n' > "$d/plugins/alpha/body.md"; commit
  "run_$tool"; label="$tool refuses repeated base version keys"; check test "$rc" -ne 0

  fresh
  printf '%s\n' '{"name":"alpha"}' > "$d/plugins/alpha/.claude-plugin/plugin.json"
  commit; git -C "$d" branch -f main HEAD
  printf '%s\n' '{"name":"alpha","version":"1.2.3"}' > "$d/plugins/alpha/.claude-plugin/plugin.json"
  printf 'changed\n' > "$d/plugins/alpha/body.md"; commit
  "run_$tool"; label="$tool keeps an existing missing version UNKNOWN"; check test "$rc" -ne 0

  fresh; mv "$d/plugins/alpha" "$d/plugins/"$'al\npha'; commit
  "run_$tool"; label="$tool refuses unsupported plugin identities"; check test "$rc" -ne 0

  fresh
  for name in alpha beta; do
    printf 'changed\n' > "$d/plugins/$name/body.md"
    printf '{"name":"%s","version":"1.2.4"}\n' "$name" > "$d/plugins/$name/.claude-plugin/plugin.json"
    cp "$d/plugins/$name/.claude-plugin/plugin.json" "$d/plugins/$name/plugin.json"
  done
  jq '.plugins[].version="1.2.4"' "$d/.claude-plugin/marketplace.json" > "$d/next"; mv "$d/next" "$d/.claude-plugin/marketplace.json"
  cp "$d/.claude-plugin/marketplace.json" "$d/.github/plugin/marketplace.json"; commit
  mkdir -p "$work/bin"
  cat > "$work/bin/git" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *' ls-tree -d --name-only '* ]]; then
  if [[ " $* " == *' -z '* ]]; then printf 'plugins/alpha\0plugins/beta'; else printf 'plugins/alpha\nplugins/beta'; fi
  exit 0
fi
exec "$REAL_GIT" "$@"
EOF
  chmod +x "$work/bin/git"
  PATH="$work/bin:$PATH" "run_$tool"; label="$tool refuses a successful unterminated inventory"; check test "$rc" -ne 0
done
fresh
outside=$(mktemp -d "$work/outside.XXXXXX")
mv "$d/plugins/alpha/.claude-plugin" "$outside/header"
ln -s "$outside/header" "$d/plugins/alpha/.claude-plugin"
cp "$outside/header/plugin.json" "$work/before"
rc=0; (cd "$d" && bash "$here/bump-plugin-version.sh" alpha patch) > "$work/out" 2> "$work/err" || rc=$?
label='writer refuses symlinked manifest parent'; check test "$rc" -ne 0
label='writer preserves files outside the checkout'; check cmp -s "$work/before" "$outside/header/plugin.json"
fresh; run_gate
label='complete unchanged plugin census succeeds'; check test "$rc" -eq 0
fresh; printf 'changed\n' > "$d/plugins/alpha/body.md"; commit
run_writer; label='ordinary changed-since writer succeeds'; check test "$rc" -eq 0
label='ordinary writer updates the selected plugin'; check test "$(jq -r .version "$d/plugins/alpha/plugin.json")" = 1.2.4
label='ordinary writer preserves its sibling'; check test "$(jq -r .version "$d/plugins/beta/plugin.json")" = 1.2.3
commit; run_gate; label='committed generated bump satisfies the gate'; check test "$rc" -eq 0
run_writer; label='repeated changed-since remains idempotent'; check test "$rc" -eq 0
label='repeated writer retains the cache version'; check test "$(jq -r .version "$d/plugins/alpha/plugin.json")" = 1.2.4
for mode in repeated-head multi-head symlink-head shallow promisor; do
  fresh
  printf 'changed\n' > "$d/plugins/alpha/body.md"
  case $mode in
    repeated-head) printf '%s\n' '{"name":"alpha","version":"1.2.3","version":"1.2.4"}' > "$d/plugins/alpha/.claude-plugin/plugin.json" ;;
    multi-head) printf '%s\n' '{"name":"alpha","version":"1.2.4"}' '{"name":"alpha","version":"1.2.4"}' > "$d/plugins/alpha/.claude-plugin/plugin.json" ;;
    symlink-head) mv "$d/plugins/alpha/.claude-plugin/plugin.json" "$d/alternate.json"; ln -s ../../../alternate.json "$d/plugins/alpha/.claude-plugin/plugin.json" ;;
  esac
  commit
  case $mode in
    shallow) git -C "$d" rev-parse main > "$d/.git/shallow" ;;
    promisor) git -C "$d" config remote.origin.promisor true ;;
  esac
  run_gate; label="$mode evidence refuses gate clearance"; check test "$rc" -ne 0
  # Capture actual files independently of Git's ancestry and index interpretation.
  before=$(find "$d/plugins" "$d/.claude-plugin" "$d/.github" -type f -exec shasum {} + | LC_ALL=C sort)
  run_writer; label="$mode evidence refuses the writer"; check test "$rc" -ne 0
  after=$(find "$d/plugins" "$d/.claude-plugin" "$d/.github" -type f -exec shasum {} + | LC_ALL=C sort)
  label="$mode refusal preserves every manifest"; check test "$before" = "$after"
done
printf 'plugin version boundary regressions: %s failure(s)\n' "$fail"
test "$fail" -eq 0
