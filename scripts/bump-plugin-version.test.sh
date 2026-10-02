#!/usr/bin/env bash
# Self-test for bump-plugin-version.sh.
#
# Proves the helper moves the version in ALL FOUR manifests that must agree (a partial bump
# would fail validate-manifests.sh downstream), that each bump level is arithmetically right,
# that --changed-since bumps exactly the plugins whose content moved and is idempotent on a
# re-run, and that it fails closed on a bad plugin, a bad level, and a non-semver version.
#
# Self-contained: throwaway git repos, the REAL helper, no network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUMP="$SCRIPT_DIR/bump-plugin-version.sh"

pass=0
fail=0

ok() { echo "  ✓ $1"; pass=$((pass + 1)); }
ko() { echo "  ✗ $1"; fail=$((fail + 1)); }

make_plugin() {
  local root="$1" name="$2" version="$3" body="${4:-original}"
  mkdir -p "$root/plugins/$name/.claude-plugin" "$root/plugins/$name/skills/example-skill"
  local pj
  pj=$(printf '{"name":"%s","description":"%s plugin","version":"%s"}' "$name" "$name" "$version")
  printf '%s\n' "$pj" > "$root/plugins/$name/plugin.json"
  printf '%s\n' "$pj" > "$root/plugins/$name/.claude-plugin/plugin.json"
  printf -- '---\nname: example-skill\n---\n%s\n' "$body" \
    > "$root/plugins/$name/skills/example-skill/SKILL.md"
}

make_repo() {
  local root="$1"
  mkdir -p "$root/.claude-plugin" "$root/.github/plugin"
  local manifest='{
  "name": "devantler-plugins",
  "plugins": [
    { "name": "alpha", "description": "alpha plugin", "version": "1.2.3", "source": "./plugins/alpha" },
    { "name": "beta", "description": "beta plugin", "version": "1.2.3", "source": "./plugins/beta" }
  ]
}'
  printf '%s\n' "$manifest" > "$root/.claude-plugin/marketplace.json"
  printf '%s\n' "$manifest" > "$root/.github/plugin/marketplace.json"
  make_plugin "$root" alpha "1.2.3"
  make_plugin "$root" beta "1.2.3"
  git -C "$root" init --quiet --initial-branch=main
  git -C "$root" config user.email test@example.com
  git -C "$root" config user.name Test
  # Hermetic: never inherit the caller's signing setup — a contributor with
  # commit.gpgsign enabled would otherwise fail every fixture commit.
  git -C "$root" config commit.gpgsign false
  git -C "$root" add -A
  git -C "$root" commit --quiet -m base
}

# Every place a version must agree.
versions_of() {
  local root="$1" name="$2"
  jq -r '.version' "$root/plugins/$name/plugin.json"
  jq -r '.version' "$root/plugins/$name/.claude-plugin/plugin.json"
  jq -r --arg n "$name" '.plugins[]|select(.name==$n)|.version' "$root/.claude-plugin/marketplace.json"
  jq -r --arg n "$name" '.plugins[]|select(.name==$n)|.version' "$root/.github/plugin/marketplace.json"
}

expect_all() {
  local desc="$1" root="$2" name="$3" want="$4" got uniq
  got=$(versions_of "$root" "$name")
  uniq=$(printf '%s\n' "$got" | sort -u | tr '\n' ' ')
  if [ "$uniq" = "$want " ]; then ok "$desc"; else
    ko "$desc — expected all four at '$want', got: $uniq"; fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fresh() { local d; d=$(mktemp -d "$WORK/case-XXXXXX"); make_repo "$d"; printf '%s' "$d"; }

echo "bump-plugin-version.sh self-test"

# --- all four manifests move together ---
d=$(fresh); (cd "$d" && "$BUMP" alpha patch >/dev/null)
expect_all "patch bumps all four manifests" "$d" alpha "1.2.4"

d=$(fresh); (cd "$d" && "$BUMP" alpha minor >/dev/null)
expect_all "minor resets patch" "$d" alpha "1.3.0"

d=$(fresh); (cd "$d" && "$BUMP" alpha major >/dev/null)
expect_all "major resets minor and patch" "$d" alpha "2.0.0"

d=$(fresh); (cd "$d" && "$BUMP" alpha >/dev/null)
expect_all "level defaults to patch" "$d" alpha "1.2.4"

# A sibling plugin must not be dragged along.
d=$(fresh); (cd "$d" && "$BUMP" alpha patch >/dev/null)
expect_all "an untouched sibling keeps its version" "$d" beta "1.2.3"

# --- --changed-since bumps exactly what moved ---
d=$(fresh)
git -C "$d" checkout --quiet -b feature
make_plugin "$d" alpha "1.2.3" "edited"
git -C "$d" add -A && git -C "$d" commit --quiet -m "content"
(cd "$d" && "$BUMP" --changed-since main >/dev/null)
expect_all "--changed-since bumps the changed plugin" "$d" alpha "1.2.4"
expect_all "--changed-since leaves the unchanged plugin" "$d" beta "1.2.3"

# Re-running must not double-bump: only the manifests changed on the second pass.
d=$(fresh)
git -C "$d" checkout --quiet -b feature
make_plugin "$d" alpha "1.2.3" "edited"
git -C "$d" add -A && git -C "$d" commit --quiet -m "content"
(cd "$d" && "$BUMP" --changed-since main >/dev/null)
git -C "$d" add -A && git -C "$d" commit --quiet -m "bump"
(cd "$d" && "$BUMP" --changed-since main >/dev/null)
expect_all "--changed-since is idempotent (no double bump)" "$d" alpha "1.2.4"

d=$(fresh)
git -C "$d" checkout --quiet -b feature
printf 'unrelated\n' > "$d/README.md"
git -C "$d" add -A && git -C "$d" commit --quiet -m "docs"
out=$( (cd "$d" && "$BUMP" --changed-since main) 2>&1 )
if [[ $out == *"No plugin content changed"* ]]; then
  ok "--changed-since is a no-op when no plugin moved"
else
  ko "--changed-since should no-op on an unrelated change; got: $out"
fi

# --- fails closed ---
d=$(fresh)
if (cd "$d" && "$BUMP" no-such-plugin patch) >/dev/null 2>&1; then
  ko "unknown plugin should fail"; else ok "unknown plugin fails closed"; fi

d=$(fresh)
if (cd "$d" && "$BUMP" alpha sideways) >/dev/null 2>&1; then
  ko "unknown bump level should fail"; else ok "unknown bump level fails closed"; fi

d=$(fresh)
jq '.version = "1.2.3-beta"' "$d/plugins/alpha/.claude-plugin/plugin.json" > "$d/t" \
  && mv "$d/t" "$d/plugins/alpha/.claude-plugin/plugin.json"
if (cd "$d" && "$BUMP" alpha patch) >/dev/null 2>&1; then
  ko "non-semver version should fail"; else ok "non-semver version fails closed"; fi

d=$(fresh)
if (cd "$d" && "$BUMP" --changed-since origin/nope) >/dev/null 2>&1; then
  ko "unresolvable base should fail"; else ok "unresolvable base fails closed"; fi

# Exercise the real updater with failed Git observations. Enumeration and all
# change queries must finish before any of the four manifests are written.
REAL_GIT=$(command -v git)
export REAL_GIT
mkdir -p "$WORK/git-fault"
cat > "$WORK/git-fault/git" <<'STUB'
#!/usr/bin/env bash
case $VERSION_GIT_FAULT in
  tree-empty|tree-partial)
    if [[ $1 == ls-tree && $2 == -d && $3 == --name-only ]]; then
      [[ $VERSION_GIT_FAULT != tree-partial ]] || printf 'plugins/alpha\n'
      printf 'injected plugin listing failure\n' >&2
      exit 71
    fi ;;
  diff-empty|diff-partial)
    if [[ $1 == diff && ${!#} == plugins/beta/ ]]; then
      [[ $VERSION_GIT_FAULT != diff-partial ]] || printf 'plugins/beta/plugin.json\n'
      printf 'injected plugin change query failure\n' >&2
      exit 72
    fi ;;
esac
exec "$REAL_GIT" "$@"
STUB
chmod +x "$WORK/git-fault/git"
for fault in tree-empty tree-partial diff-empty diff-partial; do
  d=$(fresh)
  git -C "$d" checkout --quiet -b feature
  make_plugin "$d" alpha "1.2.3" "edited alpha"
  make_plugin "$d" beta "1.2.3" "edited beta"
  git -C "$d" add plugins/alpha plugins/beta
  git -C "$d" commit --quiet -m content
  out=$( (cd "$d" && PATH="$WORK/git-fault:$PATH" VERSION_GIT_FAULT="$fault" \
    "$BUMP" --changed-since main) 2>&1 ); rc=$?
  case $fault in
    tree-*) diagnostic='Cannot enumerate plugins' ;;
    diff-*) diagnostic='Cannot inspect changed content' ;;
  esac
  if [[ $rc -ne 0 && $out == *"$diagnostic"* ]]; then
    ok "$fault observation refuses the update"
  else
    ko "$fault observation should fail with '$diagnostic'; got exit $rc: $out"
  fi
  expect_all "$fault leaves all alpha manifests untouched" "$d" alpha "1.2.3"
  expect_all "$fault leaves all beta manifests untouched" "$d" beta "1.2.3"
  if [[ -z $(git -C "$d" status --porcelain --untracked-files=all) ]]; then
    ok "$fault leaves no temporary files or changes"
  else
    ko "$fault observation wrote into the repository"
  fi
done

# Malformed late inputs must not leave an earlier manifest (or plugin) bumped.
for corruption in missing duplicate identity parity malformed; do
  d=$(fresh)
  f="$d/.github/plugin/marketplace.json"
  case "$corruption" in
    missing) jq '.plugins |= map(select(.name != "alpha"))' "$f" > "$d/t"; mv "$d/t" "$f" ;;
    duplicate) jq '.plugins += [.plugins[0]]' "$f" > "$d/t"; mv "$d/t" "$f" ;;
    identity) jq '.name="beta"' "$d/plugins/alpha/plugin.json" > "$d/t"; mv "$d/t" "$d/plugins/alpha/plugin.json" ;;
    parity) jq '.plugins[0].version="1.2.2"' "$f" > "$d/t"; mv "$d/t" "$f" ;;
    malformed) printf '{invalid\n' > "$f" ;;
  esac
  git -C "$d" diff > "$WORK/before"
  (cd "$d" && "$BUMP" alpha patch > "$WORK/out" 2>&1); rc=$?
  git -C "$d" diff > "$WORK/after"
  if [ "$rc" -ne 0 ] && cmp -s "$WORK/before" "$WORK/after" && [ -z "$(git -C "$d" ls-files --others --exclude-standard)" ]; then
    ok "$corruption input leaves all four manifests unchanged"
  else ko "$corruption input leaves all four manifests unchanged (rc=$rc)"; fi
done
d=$(fresh)
make_plugin "$d" alpha 1.2.3 "edited alpha"
make_plugin "$d" beta 1.2.3 "edited beta"
printf '{invalid\n' > "$d/plugins/beta/plugin.json"
git -C "$d" add plugins/alpha plugins/beta
git -C "$d" commit --quiet -m content
(cd "$d" && "$BUMP" --changed-since HEAD^ > "$WORK/out" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && [ -z "$(git -C "$d" status --porcelain --untracked-files=all)" ]; then
  ok "a bad later plugin prevents every manifest write"
else ko "a bad later plugin prevents every manifest write (rc=$rc)"; fi

echo "-----------------------------------------"
echo "bump-plugin-version.sh self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
