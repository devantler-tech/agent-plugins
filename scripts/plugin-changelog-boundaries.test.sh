#!/usr/bin/env bash
set -euo pipefail
script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plugin-changelog.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failed=0
# Make real committed plugin history; fake only one external observation per failure case.
fixture() {
  dir=$(mktemp -d "$work/case.XXXXXX")
  git -C "$dir" init -q -b main
  git -C "$dir" config user.name Test; git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config commit.gpgsign false
  for plugin in alpha beta; do
    mkdir -p "$dir/plugins/$plugin/skills/example"
    printf '{"version":"1.2.3"}\n' > "$dir/plugins/$plugin/plugin.json"
    printf '%s\n' '---' 'name: example' 'metadata:' '  github-repo: https://github.com/devantler-tech/agent-skills' '  github-ref: refs/tags/v1.0.0' '---' 'Example.' > "$dir/plugins/$plugin/skills/example/SKILL.md"
    printf '## 1.2.3 — 2026-01-01\n\nOriginal history.\n' > "$dir/plugins/$plugin/CHANGELOG.md"
  done
  git -C "$dir" add -- plugins; git -C "$dir" commit -qm base
  base=$(git -C "$dir" rev-parse HEAD)
  printf '\nChanged resource.\n' >> "$dir/plugins/alpha/skills/example/SKILL.md"
  git -C "$dir" add -- plugins; git -C "$dir" commit -qm sync
  printf '{"version":"1.2.4"}\n' > "$dir/plugins/alpha/plugin.json"
}
# Retain expected refusals as observable status assertions, so one gap cannot mask another.
expect_refusal() {
  if (cd "$dir" && bash "$script" "$@") > "$work/out" 2>&1; then
    printf 'FAIL %s\n' "$label"; failed=$((failed+1))
  else printf 'PASS %s\n' "$label"; fi
}
fixture; label='calendar-invalid release date'; expect_refusal write "$base" 2026-02-31
for invalid_date in 1900-02-29 2025-02-29 2026-04-31 0000-01-01; do
  fixture; label="invalid calendar date $invalid_date"; expect_refusal write "$base" "$invalid_date"
done
for valid_date in 2000-02-29 2024-02-29 2026-04-30; do
  fixture
  if (cd "$dir" && bash "$script" write "$base" "$valid_date") > "$work/out" 2>&1 &&
      grep -q "$valid_date" "$dir/plugins/alpha/CHANGELOG.md"; then printf 'PASS valid date %s\n' "$valid_date"
  else printf 'FAIL valid date %s\n' "$valid_date"; failed=$((failed+1)); fi
done
fixture
printf '{}\n' >> "$dir/plugins/alpha/plugin.json"
label='multiple working manifest documents'; expect_refusal write "$base" 2026-10-03
fixture
git -C "$dir" show "$base:plugins/alpha/plugin.json" > "$work/manifest"
printf '{"version":"1.2.3"}\n' >> "$work/manifest"
blob=$(git -C "$dir" hash-object -w "$work/manifest")
git -C "$dir" update-index --cacheinfo 100644 "$blob" plugins/alpha/plugin.json
git -C "$dir" commit -qm malformed-base
base=$(git -C "$dir" rev-parse HEAD)
label='multiple base manifest documents'; expect_refusal write "$base" 2026-10-03
fixture
printf '%s\n' '---' 'name: example' 'metadata:' '  nested:' '    github-repo: https://github.com/devantler-tech/agent-plugins' '    github-ref: refs/tags/v9.9.9' '---' > "$dir/plugins/alpha/skills/example/SKILL.md"
git -C "$dir" add -- plugins/alpha/skills/example/SKILL.md; git -C "$dir" commit -qm nested-provenance
label='nested keys cannot impersonate provenance'; expect_refusal write "$base" 2026-10-03
fixture
mkdir "$dir/bin"
printf '#!/usr/bin/env bash\nprintf '\''[{"version":"1.2.4","line":1}]\\n'\''\nexit 1\n' > "$dir/bin/node"
chmod +x "$dir/bin/node"
printf '## 1.2.4 — 2026-10-03\n' > "$dir/plugins/alpha/CHANGELOG.md"
git -C "$dir" add -- plugins; git -C "$dir" commit -qm notes
label='failed heading observation cannot pass check'
if (cd "$dir" && PATH="$dir/bin:$PATH" bash "$script" check "$base" HEAD) > "$work/out" 2>&1; then printf 'FAIL %s\n' "$label"; failed=$((failed+1)); else printf 'PASS %s\n' "$label"; fi
fixture
mkdir "$dir/bin"; real_git=$(command -v git)
cat > "$dir/bin/git" <<'SH'
#!/usr/bin/env bash
if [[ $1 == cat-file && $2 == blob ]]; then exit 128; fi
if [[ $1 == ls-tree && $2 == -r ]]; then exit 0; fi
exec "$REAL_GIT" "$@"
SH
chmod +x "$dir/bin/git"
label='failed committed provenance read cannot invent a removed skill'
if (cd "$dir" && PATH="$dir/bin:$PATH" REAL_GIT="$real_git" bash "$script" write "$base" 2026-10-03) > "$work/out" 2>&1; then printf 'FAIL %s\n' "$label"; failed=$((failed+1)); else printf 'PASS %s\n' "$label"; fi
fixture
printf 'resource\n' > "$dir/plugins/alpha/skills/example/café.txt"
git -C "$dir" checkout -- plugins/alpha/skills/example/SKILL.md
git -C "$dir" add -- plugins/alpha/skills/example/café.txt; git -C "$dir" commit -qm resource
# Compare against a base after the skill sync, so only the quoted resource path moved.
base=$(git -C "$dir" rev-parse HEAD~1)
label='non-ASCII resource filenames retain their owning skill'
if (cd "$dir" && bash "$script" write "$base" 2026-10-03) > "$work/out" 2>&1 && grep -q '\*\*Changed\*\*' "$dir/plugins/alpha/CHANGELOG.md"; then printf 'PASS %s\n' "$label"; else printf 'FAIL %s\n' "$label"; failed=$((failed+1)); fi
fixture
printf '{"version":"1.2.4"}\n' > "$dir/plugins/beta/plugin.json"
printf '\nChanged beta.\n' >> "$dir/plugins/beta/skills/example/SKILL.md"
git -C "$dir" add -- plugins/beta/skills/example/SKILL.md; git -C "$dir" commit -qm beta
cp "$dir/plugins/alpha/CHANGELOG.md" "$work/alpha-before"; cp "$dir/plugins/beta/CHANGELOG.md" "$work/beta-before"
mkdir "$dir/bin"; real_mv=$(command -v mv)
cat > "$dir/bin/mv" <<'SH'
#!/usr/bin/env bash
last=${!#}
if [[ $last == plugins/beta/CHANGELOG.md && ! -e $FAULT_ONCE ]]; then touch "$FAULT_ONCE"; exit 1; fi
exec "$REAL_MV" "$@"
SH
chmod +x "$dir/bin/mv"
rc=0
(cd "$dir" && PATH="$dir/bin:$PATH" REAL_MV="$real_mv" FAULT_ONCE="$dir/once" bash "$script" write "$base" 2026-10-03) > "$work/out" 2>&1 || rc=$?
label='failed second changelog write restores first history'
if [[ $rc -ne 0 ]] && cmp -s "$work/alpha-before" "$dir/plugins/alpha/CHANGELOG.md" && cmp -s "$work/beta-before" "$dir/plugins/beta/CHANGELOG.md"; then printf 'PASS %s\n' "$label"; else printf 'FAIL %s\n' "$label"; failed=$((failed+1)); fi
# A new changelog created before the same second-write failure must also be rolled back.
rm "$dir/once" "$dir/plugins/alpha/CHANGELOG.md"
rc=0
(cd "$dir" && PATH="$dir/bin:$PATH" REAL_MV="$real_mv" FAULT_ONCE="$dir/once" bash "$script" write "$base" 2026-10-03) > "$work/out" 2>&1 || rc=$?
label='failed second write removes its newly created first changelog'
if [[ $rc -ne 0 && ! -e "$dir/plugins/alpha/CHANGELOG.md" ]] && cmp -s "$work/beta-before" "$dir/plugins/beta/CHANGELOG.md"; then printf 'PASS %s\n' "$label"; else printf 'FAIL %s\n' "$label"; failed=$((failed+1)); fi
fixture
git -C "$dir" add -- plugins/alpha/plugin.json; git -C "$dir" commit -qm version
original=$(git -C "$dir" rev-parse HEAD)
printf '## 1.2.4 — 2026-10-03\n' > "$dir/plugins/alpha/CHANGELOG.md"
git -C "$dir" add -- plugins/alpha/CHANGELOG.md; git -C "$dir" commit -qm substitute-notes
replacement_tree=$(git -C "$dir" rev-parse 'HEAD^{tree}')
substitute=$(git -C "$dir" commit-tree "$replacement_tree" -p "$original^" -m substitute-notes)
git -C "$dir" replace "$original" "$substitute"
label='replacement objects cannot hide missing committed notes'
expect_refusal check "$base" "$original"
printf '%s discovery failures\n' "$failed"
test "$failed" -eq 0
