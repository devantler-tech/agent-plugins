#!/usr/bin/env bash
set -Eeuo pipefail
plugins=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
digest="$plugins/scripts/refresh-desired-state-digests.sh"
bump="$plugins/scripts/bump-plugin-version.sh"
fail=0
# Evaluate one labeled behavior and retain failures so all boundaries are exercised.
check() { if "$@"; then printf 'PASS %s\n' "$label"; else printf 'FAIL %s\n' "$label"; fail=$((fail+1)); fi; }
# Create a fresh minimal plugin whose resource and definition are real files.
fixture() {
  root=$(mktemp -d "$work/case.XXXXXX")
  mkdir -p "$root/plugins/alpha/resources" "$root/plugins/alpha/agents"
  printf 'definition\n' > "$root/plugins/alpha/agents/alpha.agent.md"
  printf '{"spec":{"source":{"entrypoint":"alpha","entrypointSha256":"stale"}}}\n' > "$root/plugins/alpha/resources/a.desired-state.json"
  resource="$root/plugins/alpha/resources/a.desired-state.json"
}
# Invoke the installed generator and capture its status and diagnostics for assertions.
run_digest() { rc=0; (cd "$root" && bash "$digest" "$@") > "$work/out" 2>&1 || rc=$?; }
fixture
printf '{}\n' >> "$resource"
run_digest --check
label='multiple JSON documents are rejected'; check test "$rc" -ne 0
fixture
printf 'outside\n' > "$root/outside.agent.md"
jq '.spec.source.entrypoint="../../../outside"' "$resource" > "$work/new"; cp "$work/new" "$resource"
run_digest
label='digest target cannot escape its plugin'; check test "$rc" -ne 0
fixture
mv "$root/plugins/alpha/agents/alpha.agent.md" "$root/outside.agent.md"
ln -s "$root/outside.agent.md" "$root/plugins/alpha/agents/alpha.agent.md"
run_digest
label='digest target cannot follow a linked file'; check test "$rc" -ne 0
fixture
run_digest
cp "$resource" "$root/external.json"
ln -s "$root/external.json" "$root/plugins/alpha/resources/b.desired-state.json"
run_digest --check
label='symlink resources are rejected rather than omitted'; check test "$rc" -ne 0
fixture
run_digest
real_cat=$(command -v cat)
mkdir "$root/bin"
cat > "$root/bin/cat" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "$BAD_READ" ]]; then "$REAL_CAT" "$@"; exit 1; fi
exec "$REAL_CAT" "$@"
EOF
chmod +x "$root/bin/cat"
rc=0
(cd "$root" && PATH="$root/bin:$PATH" BAD_READ=plugins/alpha/resources/a.desired-state.json REAL_CAT="$real_cat" bash "$digest" --check) > "$work/out" 2>&1 || rc=$?
label='failed original-byte read cannot report CURRENT'; check test "$rc" -ne 0

# Inject a one-shot second-commit failure at the filesystem boundary only.
faults() {
  mkdir -p "$root/bin"
  real_cat=$(command -v cat); real_mv=$(command -v mv)
  cat > "$root/bin/cat" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  */update-*|*/plugin-*)
    count=0; [[ ! -f "$FAULT_COUNT" ]] || read -r count < "$FAULT_COUNT"
    count=$((count+1)); printf '%s\n' "$count" > "$FAULT_COUNT"
    [[ $count != 2 ]] || exit 1 ;;
esac
exec "$REAL_CAT" "$@"
EOF
  cat > "$root/bin/mv" <<'EOF'
#!/usr/bin/env bash
last=${!#}
case "$last" in
  "$FAULT_ROOT"/*.json|plugins/*.json|.claude-plugin/marketplace.json|.github/plugin/marketplace.json)
    count=0; [[ ! -f "$FAULT_COUNT" ]] || read -r count < "$FAULT_COUNT"
    count=$((count+1)); printf '%s\n' "$count" > "$FAULT_COUNT"
    [[ $count != 2 ]] || exit 1 ;;
esac
exec "$REAL_MV" "$@"
EOF
  chmod +x "$root/bin/cat" "$root/bin/mv"
  export REAL_CAT="$real_cat" REAL_MV="$real_mv" FAULT_ROOT="$root" FAULT_COUNT="$work/count"
  rm -f "$FAULT_COUNT"
}
fixture
cp "$resource" "$root/plugins/alpha/resources/b.desired-state.json"
cp -R "$root/plugins" "$work/before-digests"
faults
rc=0; (cd "$root" && PATH="$root/bin:$PATH" bash "$digest") > "$work/out" 2>&1 || rc=$?
label='failed resource commit reports failure'; check test "$rc" -ne 0
label='failed resource commit restores the whole batch'; check diff -rq "$work/before-digests" "$root/plugins"

# Prepare a plugin with all four version manifests in parity, without a Git history.
version_fixture() {
  root=$(mktemp -d "$work/version.XXXXXX")
  mkdir -p "$root/plugins/alpha/.claude-plugin" "$root/.github/plugin" "$root/.claude-plugin"
  printf '{"name":"alpha","version":"1.2.3"}\n' > "$root/plugins/alpha/plugin.json"
  cp "$root/plugins/alpha/plugin.json" "$root/plugins/alpha/.claude-plugin/plugin.json"
  printf '{"plugins":[{"name":"alpha","version":"1.2.3","source":"./plugins/alpha"}]}\n' > "$root/.github/plugin/marketplace.json"
  cp "$root/.github/plugin/marketplace.json" "$root/.claude-plugin/marketplace.json"
}
version_fixture
cp -R "$root" "$work/before-versions"
faults
rc=0; (cd "$root" && PATH="$root/bin:$PATH" bash "$bump" alpha patch) > "$work/out" 2>&1 || rc=$?
label='failed version commit reports failure'; check test "$rc" -ne 0
label='failed version commit restores every manifest'; check diff -rq "$work/before-versions/plugins" "$root/plugins"
label='failed version commit restores both catalogues'; check diff -rq "$work/before-versions/.github" "$root/.github"
label='failed version commit restores strict catalogue'; check diff -rq "$work/before-versions/.claude-plugin" "$root/.claude-plugin"
label='failed version commit removes private staging files'; check test "$(find "$root" -name '*.next.*' -o -name '*.original.*' | wc -l | tr -d ' ')" = 0

version_fixture
git -C "$root" init -q
git -C "$root" config user.name Test; git -C "$root" config user.email test@example.invalid
git -C "$root" -c commit.gpgsign=false add plugins .github/plugin/marketplace.json .claude-plugin/marketplace.json
git -C "$root" -c commit.gpgsign=false commit -qm base
base=$(git -C "$root" rev-parse HEAD)
mkdir -p "$root/plugins/beta/.claude-plugin"
printf '{"name":"beta","version":"1.0.0"}\n' > "$root/plugins/beta/plugin.json"
cp "$root/plugins/beta/plugin.json" "$root/plugins/beta/.claude-plugin/plugin.json"
for f in .github/plugin/marketplace.json .claude-plugin/marketplace.json; do
  jq '.plugins += [{name:"beta",version:"1.0.0",source:"./plugins/beta"}]' "$root/$f" > "$work/new"; cp "$work/new" "$root/$f"
done
git -C "$root" add plugins/beta .github/plugin/marketplace.json .claude-plugin/marketplace.json
git -C "$root" -c commit.gpgsign=false commit -qm 'feat: new plugin'
rc=0; (cd "$root" && bash "$bump" --changed-since "$base") > "$work/out" 2>&1 || rc=$?
label='changed-since accepts a newly introduced plugin'; check test "$rc" -eq 0
printf '%s discovery regression(s) failing\n' "$fail"
test "$fail" -eq 0
