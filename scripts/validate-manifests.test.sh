#!/usr/bin/env bash
# Self-test for validate-manifests.sh.
#
# Proves the guard PASSES a consistent fixture and FAILS each drift scenario it
# exists to catch — malformed manifests, manifest desync, every plugin.json
# completeness rule, and every manifest↔plugins lockstep rule — so a refactor
# that silently weakens a check is caught here, not by a broken plugin reaching
# consumers. Self-contained: builds throwaway fixtures, runs the REAL guard
# against them, asserts exit code + the specific error message. No network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/validate-manifests.sh"

pass=0
fail=0

# Build a complete, valid fixture repo (two plugins) at $1.
make_fixture() {
  local root="$1"
  mkdir -p "$root/.github/plugin" "$root/.claude-plugin"
  local manifest='{
  "name": "devantler-plugins",
  "plugins": [
    { "name": "alpha", "description": "Alpha plugin", "version": "1.0.0", "source": "./plugins/alpha" },
    { "name": "beta", "description": "Beta plugin", "version": "1.0.0", "source": "./plugins/beta" }
  ]
}'
  printf '%s\n' "$manifest" > "$root/.github/plugin/marketplace.json"
  printf '%s\n' "$manifest" > "$root/.claude-plugin/marketplace.json"
  make_plugin "$root" alpha "Alpha plugin" "1.0.0"
  make_plugin "$root" beta "Beta plugin" "1.0.0"
  # A README plugin table in lockstep with the two plugins + their example-skill.
  cat > "$root/README.md" <<'EOF'
# fixture

| Plugin | Skills | Description |
|--------|--------|-------------|
| [`alpha`](plugins/alpha/) | `example-skill` | Alpha plugin |
| [`beta`](plugins/beta/) | `example-skill` | Beta plugin |
EOF
}

# Write plugins/<name>/plugin.json + one skill with a SKILL.md.
make_plugin() {
  local root="$1" name="$2" desc="$3" version="$4"
  mkdir -p "$root/plugins/$name/skills/example-skill"
  printf 'Example skill.\n' > "$root/plugins/$name/skills/example-skill/SKILL.md"
  cat > "$root/plugins/$name/plugin.json" <<EOF
{
  "name": "$name",
  "description": "$desc",
  "version": "$version",
  "skills": "skills/"
}
EOF
}

run_guard() { ( cd "$1" && bash "$GUARD" 2>&1 ); }

# check_pass <description> <fixture-dir>
check_pass() {
  local desc="$1" dir="$2" out rc
  out=$(run_guard "$dir"); rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  ✓ $desc"; pass=$((pass + 1))
  else
    echo "  ✗ $desc — expected exit 0, got $rc"; printf '%s\n' "$out" | sed 's/^/      /'; fail=$((fail + 1))
  fi
}

# check_fail <description> <expected-substring> <fixture-dir>
check_fail() {
  local desc="$1" pat="$2" dir="$3" out rc
  out=$(run_guard "$dir"); rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qF "$pat"; then
    echo "  ✓ $desc"; pass=$((pass + 1))
  else
    echo "  ✗ $desc — expected non-zero exit + message containing '$pat'; got exit $rc"
    printf '%s\n' "$out" | sed 's/^/      /'; fail=$((fail + 1))
  fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A unique fixture per case (mktemp survives the command-substitution subshell).
fresh() { local d; d=$(mktemp -d "$WORK/case-XXXXXX"); make_fixture "$d"; printf '%s' "$d"; }

echo "validate-manifests.sh self-test"

# --- happy path ---
check_pass "valid fixture passes" "$(fresh)"

# --- check 1: malformed marketplace manifests ---
d=$(fresh); printf '%s\n' '{"name":"x"}' > "$d/.github/plugin/marketplace.json"
check_fail "Copilot manifest missing .plugins fails" "Invalid .github/plugin/marketplace.json" "$d"

d=$(fresh); printf '%s\n' '{"plugins":[]}' > "$d/.claude-plugin/marketplace.json"
check_fail "Claude manifest missing .name fails" "Invalid .claude-plugin/marketplace.json" "$d"

d=$(fresh); printf '%s\n' 'not json' > "$d/.github/plugin/marketplace.json"
check_fail "non-JSON manifest fails" "Invalid .github/plugin/marketplace.json" "$d"

# --- check 2: manifest desync ---
d=$(fresh)
jq '.plugins[0].version = "9.9.9"' "$d/.claude-plugin/marketplace.json" > "$d/tmp" && mv "$d/tmp" "$d/.claude-plugin/marketplace.json"
check_fail "out-of-sync manifests fail" "Marketplace manifests are out of sync" "$d"

# --- check 3: plugin.json completeness ---
d=$(fresh); jq '.name = "Bad_Name"' "$d/plugins/alpha/plugin.json" > "$d/tmp" && mv "$d/tmp" "$d/plugins/alpha/plugin.json"
# rename dir + manifest entry so only the kebab-case rule trips (keep lockstep intact)
mv "$d/plugins/alpha" "$d/plugins/Bad_Name"
for m in "$d/.github/plugin/marketplace.json" "$d/.claude-plugin/marketplace.json"; do
  jq '(.plugins[] | select(.name=="alpha")) |= (.name="Bad_Name" | .source="./plugins/Bad_Name")' "$m" > "$d/tmp" && mv "$d/tmp" "$m"
done
check_fail "non-kebab plugin name fails" "must be kebab-case" "$d"

d=$(fresh); jq 'del(.description)' "$d/plugins/alpha/plugin.json" > "$d/tmp" && mv "$d/tmp" "$d/plugins/alpha/plugin.json"
check_fail "missing plugin.json description fails" "missing or empty 'description'" "$d"

d=$(fresh); jq 'del(.version)' "$d/plugins/alpha/plugin.json" > "$d/tmp" && mv "$d/tmp" "$d/plugins/alpha/plugin.json"
check_fail "missing plugin.json version fails" "missing or empty 'version'" "$d"

d=$(fresh); jq '.skills = "wrong/"' "$d/plugins/alpha/plugin.json" > "$d/tmp" && mv "$d/tmp" "$d/plugins/alpha/plugin.json"
check_fail "wrong 'skills' value fails" "'skills' must be" "$d"

d=$(fresh); rm -rf "$d/plugins/alpha/skills"
check_fail "plugin with no SKILL.md fails" "must contain at least one <skill>/SKILL.md" "$d"

# --- check 4: manifest <-> plugins lockstep ---
d=$(fresh)
for m in "$d/.github/plugin/marketplace.json" "$d/.claude-plugin/marketplace.json"; do
  jq '(.plugins[] | select(.name=="alpha")).source = "./wrong/alpha"' "$m" > "$d/tmp" && mv "$d/tmp" "$m"
done
check_fail "wrong manifest source fails" "must be './plugins/alpha'" "$d"

d=$(fresh); rm -rf "$d/plugins/beta"
check_fail "manifest entry with no plugin dir fails" "has no plugins/beta/plugin.json on disk" "$d"

d=$(fresh); jq '.description = "Drifted"' "$d/plugins/alpha/plugin.json" > "$d/tmp" && mv "$d/tmp" "$d/plugins/alpha/plugin.json"
check_fail "plugin.json description drift vs manifest fails" "description differs from manifest entry 'alpha'" "$d"

d=$(fresh); jq '.version = "2.0.0"' "$d/plugins/alpha/plugin.json" > "$d/tmp" && mv "$d/tmp" "$d/plugins/alpha/plugin.json"
check_fail "plugin.json version drift vs manifest fails" "version differs from manifest entry 'alpha'" "$d"

d=$(fresh); jq '.name = "alpha2"' "$d/plugins/alpha/plugin.json" > "$d/tmp" && mv "$d/tmp" "$d/plugins/alpha/plugin.json"
check_fail "plugin.json name drift vs manifest fails" "name does not match manifest entry 'alpha'" "$d"

d=$(fresh); make_plugin "$d" gamma "Orphan plugin" "1.0.0"
check_fail "orphan plugin not in manifest fails" "plugins/gamma is not listed in" "$d"

# --- check 5: README plugin table <-> plugins/skills lockstep ---
# A README row for a plugin that does not exist on disk.
# (literal backticks in the table cell, not command substitution — SC2016 false positive)
d=$(fresh)
# shellcheck disable=SC2016
printf '| [`gamma`](plugins/gamma/) | `example-skill` | Ghost plugin |\n' >> "$d/README.md"
check_fail "README row for nonexistent plugin fails" "README.md lists plugin 'gamma' with no plugins/gamma/ on disk" "$d"

# A skill added on disk but not reflected in the README Skills column.
d=$(fresh)
mkdir -p "$d/plugins/alpha/skills/second-skill"
printf 'Second skill.\n' > "$d/plugins/alpha/skills/second-skill/SKILL.md"
check_fail "README skills drift vs disk fails" "README.md Skills for 'alpha'" "$d"

# A plugin on disk (and in the manifests) with no README table row.
d=$(fresh)
# shellcheck disable=SC2016
grep -v '`beta`' "$d/README.md" > "$d/tmp" && mv "$d/tmp" "$d/README.md"
check_fail "plugin missing from README table fails" "plugins/beta is not listed in the README.md plugin table" "$d"

echo "-----------------------------------------"
echo "validate-manifests.sh self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
