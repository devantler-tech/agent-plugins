#!/usr/bin/env bash
# Exercise changelog generation and the publication gate in real temporary repositories.
set -euo pipefail
script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plugin-changelog.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
passed=0
# Build two plugins with tracked provenance; no network or global configuration is used.
fixture() {
  dir=$(mktemp -d "$work/case.XXXXXX")
  git -C "$dir" init -q -b main
  git -C "$dir" config user.name Test
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config commit.gpgsign false
  for plugin in alpha beta; do
    mkdir -p "$dir/plugins/$plugin/skills/example"
    printf '{"version":"1.2.3"}\n' > "$dir/plugins/$plugin/plugin.json"
    cat > "$dir/plugins/$plugin/skills/example/SKILL.md" <<'MD'
---
name: example
metadata:
  github-repo: https://github.com/example/skills
  github-ref: refs/tags/v1.0.0
---
Example skill.
MD
  done
  printf '# Alpha history\n\nKeep this introduction.\n\n## 1.2.3 — 2026-01-01\n\nHuman history.\n' > "$dir/plugins/alpha/CHANGELOG.md"
  git -C "$dir" add -- plugins
  git -C "$dir" commit -qm base
  base=$(git -C "$dir" rev-parse HEAD)
  sed 's/v1.0.0/v2.0.0/' "$dir/plugins/alpha/skills/example/SKILL.md" > "$dir/new"
  mv "$dir/new" "$dir/plugins/alpha/skills/example/SKILL.md"
  git -C "$dir" add -- plugins/alpha/skills/example/SKILL.md
  git -C "$dir" commit -qm sync
}
# Simulate the four-manifest helper's resulting portable version, which this tool reads.
bump() { printf '{"version":"1.2.4"}\n' > "$dir/plugins/alpha/plugin.json"; }
# The check reads committed output, matching its CI boundary.
commit() { git -C "$dir" add -- plugins; git -C "$dir" commit -qm change; }
# Run the real tool in the fixture and assert failure is never mistaken for a pass.
refuse() { if (cd "$dir" && bash "$script" "$@") > "$work/out" 2>&1; then cat "$work/out"; exit 1; fi; passed=$((passed + 1)); }
fixture; bump; commit
refuse check "$base" HEAD
(cd "$dir" && bash "$script" write "$base" 2026-09-24)
grep -Fq '## 1.2.4 — 2026-09-24' "$dir/plugins/alpha/CHANGELOG.md"
grep -Fq 'example' "$dir/plugins/alpha/CHANGELOG.md"
grep -Fq 'refs/tags/v2.0.0' "$dir/plugins/alpha/CHANGELOG.md"
grep -Fq 'https://github.com/example/skills' "$dir/plugins/alpha/CHANGELOG.md"
git -C "$dir" show "$base:plugins/alpha/CHANGELOG.md" > "$work/old"
sed '/^## 1.2.4/,/^## 1.2.3/{ /^## 1.2.3/!d; }' "$dir/plugins/alpha/CHANGELOG.md" > "$work/preserved"
cmp "$work/old" "$work/preserved"
[ ! -e "$dir/plugins/beta/CHANGELOG.md" ]
passed=$((passed + 1))
cp "$dir/plugins/alpha/CHANGELOG.md" "$work/once"
(cd "$dir" && bash "$script" write "$base" 2026-09-25)
cmp "$work/once" "$dir/plugins/alpha/CHANGELOG.md"
commit
(cd "$dir" && bash "$script" check "$base" HEAD)
(cd "$dir" && bash "$script" write "$base" 2026-09-26)
cmp "$work/once" "$dir/plugins/alpha/CHANGELOG.md"
passed=$((passed + 2))

fixture; bump
printf '# Human notes\n\n## 1.2.4 — 2026-09-20\n\nA carefully written release.\n' > "$dir/plugins/alpha/CHANGELOG.md"
cp "$dir/plugins/alpha/CHANGELOG.md" "$work/manual"
(cd "$dir" && bash "$script" write "$base" 2026-09-24)
cmp "$work/manual" "$dir/plugins/alpha/CHANGELOG.md"
passed=$((passed + 1))

fixture
(cd "$dir" && bash "$script" write "$base" 2026-09-24)
[ -z "$(git -C "$dir" status --porcelain)" ]
(cd "$dir" && bash "$script" check "$base" HEAD)
passed=$((passed + 1))

for kind in missing prefix fenced nested-fence indented duplicate; do
  fixture; bump
  case "$kind" in
    missing) rm "$dir/plugins/alpha/CHANGELOG.md" ;;
    prefix) printf '## 1.2.40 — 2026-09-24\n' > "$dir/plugins/alpha/CHANGELOG.md" ;;
    fenced)
      # shellcheck disable=SC2016 # Literal Markdown fence, not shell expansion.
      printf '```markdown\n## 1.2.4 — 2026-09-24\n```\n' > "$dir/plugins/alpha/CHANGELOG.md" ;;
    nested-fence)
      # shellcheck disable=SC2016 # The shorter fence is example content, not a closing fence.
      printf '````markdown\n```\n## 1.2.4 — 2026-09-24\n````\n' > "$dir/plugins/alpha/CHANGELOG.md" ;;
    indented) printf '    ## 1.2.4 — 2026-09-24\n' > "$dir/plugins/alpha/CHANGELOG.md" ;;
    duplicate) printf '## 1.2.4 — 2026-09-24\n\n## 1.2.4 — 2026-09-24\n' > "$dir/plugins/alpha/CHANGELOG.md" ;;
  esac
  commit; refuse check "$base" HEAD
 done
fixture; bump
sed '/github-ref:/d' "$dir/plugins/alpha/skills/example/SKILL.md" > "$dir/new"
mv "$dir/new" "$dir/plugins/alpha/skills/example/SKILL.md"
cp "$dir/plugins/alpha/CHANGELOG.md" "$work/before"
refuse write "$base" 2026-09-24
cmp "$work/before" "$dir/plugins/alpha/CHANGELOG.md"
refuse write absent-ref 2026-09-24
refuse check absent-ref HEAD
refuse write "$base" not-a-date

fixture; bump
rm "$dir/plugins/alpha/CHANGELOG.md"
(cd "$dir" && bash "$script" write "$base" 2026-09-24)
commit
(cd "$dir" && bash "$script" check "$base" HEAD)
passed=$((passed + 1))

# A version-heading example in the introduction must remain fenced, with the real entry outside it.
fixture; bump
cat > "$dir/plugins/alpha/CHANGELOG.md" <<'MD'
# Alpha history

Example:
```markdown
## 0.0.0 — YYYY-MM-DD
```

## 1.2.3 — 2026-01-01

Human history.
MD
(cd "$dir" && bash "$script" write "$base" 2026-09-24)
commit
(cd "$dir" && bash "$script" check "$base" HEAD)
passed=$((passed + 1))
printf 'plugin changelog: PASS (%s cases)\n' "$passed"
