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

for kind in missing prefix fenced nested-fence tilde-info indented duplicate; do
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
    tilde-info)
      # shellcheck disable=SC2016 # Tilde-fence info strings may contain literal backticks.
      printf '~~~language`name\n## 1.2.4 — 2026-09-24\n~~~\n' > "$dir/plugins/alpha/CHANGELOG.md" ;;
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

# Backticks inside the opener's info string make it ordinary inline content, not a fence.
fixture; bump
cat > "$dir/plugins/alpha/CHANGELOG.md" <<'MD'
# Alpha history

```code``` is inline

## 1.2.3 — 2026-01-01

Human history.
MD
(cd "$dir" && bash "$script" write "$base" 2026-09-24)
commit
(cd "$dir" && bash "$script" check "$base" HEAD)
passed=$((passed + 1))

# Hidden templates cannot satisfy the gate or suppress generation of a visible release entry.
for kind in comment comment-fence comment-indented-close; do
  fixture; bump
  case "$kind" in
    comment) printf '<!--\n## 1.2.4 — YYYY-MM-DD\n-->\n' > "$work/template" ;;
    comment-fence)
      # shellcheck disable=SC2016 # A Markdown fence inside an HTML comment is hidden text.
      printf '<!--\n```markdown\n## 1.2.4 — YYYY-MM-DD\n-->\n' > "$work/template" ;;
    comment-indented-close) printf '<!--\n## 1.2.4 — YYYY-MM-DD\n    -->\n' > "$work/template" ;;
  esac
  cat "$work/template" "$dir/plugins/alpha/CHANGELOG.md" > "$work/log"
  cp "$work/log" "$dir/plugins/alpha/CHANGELOG.md"
  commit; refuse check "$base" HEAD
  (cd "$dir" && bash "$script" write "$base" 2026-09-24)
  sed '/^## 1.2.4 — 2026-09-24/,/^## 1.2.3/{ /^## 1.2.3/!d; }' "$dir/plugins/alpha/CHANGELOG.md" > "$work/preserved"
  cmp "$work/log" "$work/preserved"
  commit
  (cd "$dir" && bash "$script" check "$base" HEAD)
  passed=$((passed + 1))
done

# GitHub renders these headings: a heading interrupts a paragraph, so its preceding inline
# comment opener is unmatched literal text. Only a block opener can hide subsequent headings.
for kind in inline-comment inline-backticks-comment; do
  fixture; bump
  case "$kind" in
    inline-comment) printf 'Template <!--\n## 1.2.4 — 2026-09-24\n-->\n\n' > "$work/template" ;;
    inline-backticks-comment)
      # shellcheck disable=SC2016 # Literal inline code before an unmatched comment opener.
      printf '```code``` <!--\n## 1.2.4 — 2026-09-24\n-->\n\n' > "$work/template" ;;
  esac
  cat "$work/template" "$dir/plugins/alpha/CHANGELOG.md" > "$work/log"
  cp "$work/log" "$dir/plugins/alpha/CHANGELOG.md"
  commit
  (cd "$dir" && bash "$script" check "$base" HEAD)
  (cd "$dir" && bash "$script" write "$base" 2026-09-24)
  cmp "$work/log" "$dir/plugins/alpha/CHANGELOG.md"
  passed=$((passed + 1))
done

# A literal comment opener in a code example must not hide subsequent real headings.
for kind in fenced-comment inline-code-comment longer-inline-code-comment escaped-comment; do
  fixture; bump
  case "$kind" in
    fenced-comment)
      # shellcheck disable=SC2016 # Literal fenced Markdown example.
      printf '```html\n<!--\n```\n\n' > "$work/template" ;;
    inline-code-comment)
      # shellcheck disable=SC2016 # A comment opener inside inline code is literal content.
      printf 'Use `<!--` for comments.\n\n' > "$work/template" ;;
    longer-inline-code-comment)
      # shellcheck disable=SC2016 # A single backtick cannot close a two-backtick code span.
      printf 'Use ``a`<!--`` for examples.\n\n' > "$work/template" ;;
    escaped-comment) printf 'Use \\<!-- for comments.\n\n' > "$work/template" ;;
  esac
  cat "$work/template" "$dir/plugins/alpha/CHANGELOG.md" > "$work/log"
  cp "$work/log" "$dir/plugins/alpha/CHANGELOG.md"
  (cd "$dir" && bash "$script" write "$base" 2026-09-24)
  commit
  (cd "$dir" && bash "$script" check "$base" HEAD)
  passed=$((passed + 1))
done

# An unterminated hidden template must fail before the writer changes any history.
fixture; bump
printf '<!--\n## 1.2.4 — YYYY-MM-DD\n' > "$dir/plugins/alpha/CHANGELOG.md"
cp "$dir/plugins/alpha/CHANGELOG.md" "$work/before"
refuse write "$base" 2026-09-24
cmp "$work/before" "$dir/plugins/alpha/CHANGELOG.md"

# Advancing main must not turn another plugin's unchanged legacy version into a new release.
fixture
git -C "$dir" checkout -qb feature
git -C "$dir" checkout -qb advanced "$base"
printf '{"version":"1.2.4"}\n' > "$dir/plugins/beta/plugin.json"
commit
advanced=$(git -C "$dir" rev-parse HEAD)
git -C "$dir" checkout -q feature
(cd "$dir" && bash "$script" check "$advanced" HEAD)
passed=$((passed + 1))
# A release made on the feature branch still requires its own entry after that divergence.
bump; commit
refuse check "$advanced" HEAD
(cd "$dir" && bash "$script" write "$advanced" 2026-09-24)
[ ! -e "$dir/plugins/beta/CHANGELOG.md" ]
commit
(cd "$dir" && bash "$script" check "$advanced" HEAD)
passed=$((passed + 1))

# Both modes refuse histories with no common ancestor, even when their trees happen to match.
fixture
unrelated=$(printf 'Unrelated history\n' | git -C "$dir" commit-tree "$(git -C "$dir" rev-parse 'HEAD^{tree}')")
refuse check "$unrelated" HEAD
refuse write "$unrelated" 2026-09-24

# Retiring a complete skill records its previous provenance and is not described as a sync.
fixture; bump
git -C "$dir" rm -qr -- plugins/alpha/skills/example
commit
(cd "$dir" && bash "$script" write "$base" 2026-09-24)
# shellcheck disable=SC2016 # Literal Markdown code spans.
grep -Fq '**Removed** — `example`, previously from `https://github.com/example/skills` at `refs/tags/v1.0.0`.' "$dir/plugins/alpha/CHANGELOG.md"
if grep -Fq '**Changed**' "$dir/plugins/alpha/CHANGELOG.md"; then exit 1; fi
commit
(cd "$dir" && bash "$script" check "$base" HEAD)
passed=$((passed + 1))

# Removing only SKILL.md leaves a malformed skill, not a complete retirement.
fixture; bump
git -C "$dir" rm -q -- plugins/alpha/skills/example/SKILL.md
mkdir -p "$dir/plugins/alpha/skills/example"
printf 'Remaining resource\n' > "$dir/plugins/alpha/skills/example/resource.txt"
commit
cp "$dir/plugins/alpha/CHANGELOG.md" "$work/before"
refuse write "$base" 2026-09-24
cmp "$work/before" "$dir/plugins/alpha/CHANGELOG.md"

# Removing a support file while retaining SKILL.md is still an ordinary skill update.
fixture
printf 'Old resource\n' > "$dir/plugins/alpha/skills/example/resource.txt"
commit
base=$(git -C "$dir" rev-parse HEAD)
git -C "$dir" rm -q -- plugins/alpha/skills/example/resource.txt
bump; commit
(cd "$dir" && bash "$script" write "$base" 2026-09-24)
# shellcheck disable=SC2016 # Literal Markdown code spans.
grep -Fq '**Changed** — sync `example` from `https://github.com/example/skills` at `refs/tags/v2.0.0`.' "$dir/plugins/alpha/CHANGELOG.md"
commit
(cd "$dir" && bash "$script" check "$base" HEAD)
passed=$((passed + 1))
printf 'plugin changelog: PASS (%s cases)\n' "$passed"
