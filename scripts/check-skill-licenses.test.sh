#!/usr/bin/env bash
# Self-test for check-skill-licenses.sh: run the real check against fixture repositories and
# assert its exit status and the message that says where the missing record goes.
# Markdown table cells below are matched literally, backticks included.
# shellcheck disable=SC2016
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

skill() { # root plugin name repository [license]
  local dir=$1/plugins/$2/skills/$3
  mkdir -p "$dir"
  {
    printf -- '---\nname: %s\ndescription: Fixture skill.\n' "$3"
    [ -n "${5:-}" ] && printf 'license: %s\n' "$5"
    printf 'metadata:\n    github-repo: https://github.com/%s\n---\n# %s\n' "$4" "$3"
  } > "$dir/SKILL.md"
}

# A consistent repository: one first-party skill and two third-party skills from one upstream.
fixture() {
  local root=$work/$1
  rm -rf "$root"
  mkdir -p "$root/scripts" "$root/docs" "$root/plugins/alpha/resources"
  cp "$here/check-skill-licenses.sh" "$here/frontmatter.lib.sh" "$here/frontmatter.awk" "$root/scripts/"
  skill "$root" alpha ours devantler-tech/agent-skills Apache-2.0
  skill "$root" alpha theirs example/skills MIT
  skill "$root" alpha other example/skills
  cat > "$root/docs/plugins.md" <<'EOF'
| Plugin | Resources | Description |
|---|---|---|
| [`alpha`](../plugins/alpha/) | `ours`, `theirs`, `other` | Alpha |

| Skill | Plugin | Upstream | License |
|-------|--------|----------|---------|
| `ours` | `alpha` | devantler-tech/agent-skills | Apache-2.0 |
| `theirs` | `alpha` | example/skills | MIT |
| `other` | `alpha` | example/skills | MIT |
EOF
  cat > "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md" <<'EOF'
# Third-party notices

| Skill | Upstream | License |
|-------|----------|---------|
| `theirs` | example/skills | MIT |
| `other` | example/skills | MIT |

## example/skills

Skills: `theirs`, `other`.

```text
MIT License

Copyright (c) 2026 Example

Permission is hereby granted, free of charge.
```
EOF
  printf '%s\n' "$root"
}

expect() { # description expected-status root [message]
  local status=0 output
  output=$(bash "$3/scripts/check-skill-licenses.sh" "$3" 2>&1) || status=$?
  if [ "$status" -ne "$2" ]; then
    printf 'FAIL: %s (exit %s, want %s)\n%s\n' "$1" "$status" "$2" "$output" >&2
    failures=$((failures + 1))
  elif [ -n "${4:-}" ] && ! grep -qF -- "$4" <<<"$output"; then
    printf 'FAIL: %s (output lacks %q)\n%s\n' "$1" "$4" "$output" >&2
    failures=$((failures + 1))
  else
    printf 'ok   %s\n' "$1"
  fi
}

root=$(fixture consistent)
expect 'consistent records pass' 0 "$root" 'license records for 3 bundled skills'

root=$(fixture no-notice)
rm "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md"
expect 'a third-party skill without a notice file fails and says where to add it' 1 "$root" \
  'record its license in plugins/alpha/resources/THIRD-PARTY-NOTICES.md'

root=$(fixture no-notice-row)
sed -i.bak '/^| `other` /d' "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md"
expect 'a third-party skill missing from its notice table fails' 1 "$root" \
  'needs exactly one row for other: | `other` | example/skills | <SPDX license> |'

root=$(fixture no-section)
sed -i.bak 's/^## example\/skills$/## example\/elsewhere/' "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md"
expect 'a notice without the upstream section fails' 1 "$root" "has no '## example/skills' section"

root=$(fixture wrong-upstream)
sed -i.bak 's/^| `theirs` | example\/skills |/| `theirs` | example\/other |/' "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md"
expect 'a notice row naming another upstream fails' 1 "$root" 'lists theirs from example/other'

root=$(fixture frontmatter-disagrees)
sed -i.bak 's/^| `theirs` | example\/skills | MIT |/| `theirs` | example\/skills | BSD-3-Clause |/' "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md"
expect 'a notice that contradicts the skill frontmatter fails' 1 "$root" 'theirs declares MIT, but'

root=$(fixture catalogue-disagrees)
sed -i.bak 's/^| `other` | `alpha` | example\/skills | MIT |/| `other` | `alpha` | example\/skills | ISC |/' "$root/docs/plugins.md"
expect 'a catalogue license that contradicts the notice fails' 1 "$root" 'lists other as ISC'

root=$(fixture no-catalogue-row)
sed -i.bak '/^| `ours` | `alpha`/d' "$root/docs/plugins.md"
expect 'a first-party skill missing from the catalogue fails' 1 "$root" \
  'needs exactly one skill-license row for ours'

root=$(fixture stale-catalogue-row)
printf '| `gone` | `alpha` | example/skills | MIT |\n' >> "$root/docs/plugins.md"
expect 'a catalogue row for a skill that is not bundled fails' 1 "$root" 'bundles no such skill'

root=$(fixture stale-notice-row)
printf '| `gone` | example/skills | MIT |\n' >> "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md"
expect 'a notice row for a skill that is not bundled fails' 1 "$root" 'has a row for gone, which alpha does not bundle'

# The frontmatter scalar is compared unquoted, so quoting cannot hide a contradiction.
root=$(fixture quoted-frontmatter)
sed -i.bak 's/^license: MIT$/license: "Apache-2.0"/' "$root/plugins/alpha/skills/theirs/SKILL.md"
expect 'a quoted frontmatter license that contradicts the records fails' 1 "$root" 'theirs declares Apache-2.0, but'

root=$(fixture quoted-frontmatter-agrees)
sed -i.bak "s/^license: MIT\$/license: 'MIT'/" "$root/plugins/alpha/skills/theirs/SKILL.md"
expect 'a quoted frontmatter license that agrees passes' 0 "$root"

# A declaration that is not an identifier must be backed by a license file beside the skill.
root=$(fixture prose-declaration)
sed -i.bak 's/^license: MIT$/license: Complete terms in LICENSE.txt/' "$root/plugins/alpha/skills/theirs/SKILL.md"
expect 'a prose license declaration without a license file fails' 1 "$root" 'neither an SPDX identifier nor backed by a LICENSE file'
printf 'Terms.\n' > "$root/plugins/alpha/skills/theirs/LICENSE.txt"
expect 'a prose license declaration with a license file passes' 0 "$root"

# Blank license cells cannot agree with each other.
root=$(fixture blank-licenses)
sed -i.bak 's/^| `other` | example\/skills | MIT |/| `other` | example\/skills |  |/' "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md"
sed -i.bak 's/^| `other` | `alpha` | example\/skills | MIT |/| `other` | `alpha` | example\/skills |  |/' "$root/docs/plugins.md"
expect 'blank license cells fail' 1 "$root" 'lists no SPDX license for other'

# A section must keep its records, not only its heading.
root=$(fixture heading-only)
awk '/^## example\/skills$/ { print; exit } { print }' "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md" > "$root/n" && mv "$root/n" "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md"
expect 'a heading-only notice section fails' 1 "$root" 'needs its copyright notice'

root=$(fixture no-license-text)
printf '## example/skills\n\nCopyright (c) 2026 Example.\n' > "$root/section"
awk '/^## example\/skills$/ { exit } { print }' "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md" > "$root/n" && cat "$root/n" "$root/section" > "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md"
expect 'a section with a copyright notice but no license text fails' 1 "$root" 'needs the license text'
printf 'See [the license](missing-LICENSE.txt).\n' >> "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md"
expect 'a link to a missing license file fails' 1 "$root" 'needs the license text'
printf 'MIT terms.\n' > "$root/plugins/alpha/resources/missing-LICENSE.txt"
expect 'a link to a shipped license file passes' 0 "$root"

root=$(fixture symlinked-notice)
mv "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md" "$root/notice.md"
ln -s ../../../notice.md "$root/plugins/alpha/resources/THIRD-PARTY-NOTICES.md"
expect 'a symlinked notice does not count' 1 "$root" 'record its license in'

root=$(fixture no-skills)
rm -rf "$root/plugins/alpha/skills"
expect 'a repository with no skills checks nothing and fails' 2 "$root" 'no bundled skill was found'

if [ "$failures" -ne 0 ]; then
  echo "check-skill-licenses self-test: $failures failure(s)" >&2
  exit 1
fi
echo 'check-skill-licenses self-test passed'
