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

echo "-----------------------------------------"
echo "bump-plugin-version.sh self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
