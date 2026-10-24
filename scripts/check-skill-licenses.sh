#!/usr/bin/env bash
# Check that every bundled skill's license is recorded where readers and redistributors look.
#
# Bundled skills keep their own licenses. A third-party skill (any upstream outside
# devantler-tech) needs, in plugins/<plugin>/resources/THIRD-PARTY-NOTICES.md, one table row
#   | `<skill>` | <owner>/<repo> | <license> |
# and a `## <owner>/<repo>` section carrying the copyright notice and license text. Every bundled
# skill, first-party or not, needs one row in the docs/plugins.md skill-license table:
#   | `<skill>` | `<plugin>` | <owner>/<repo> | <license> |
# Both records live outside the synced skill directories, so a skill update cannot remove them.
# When a skill's own frontmatter declares an SPDX license, every record must agree with it.
# Rows naming a skill that is not bundled fail too, so a removed skill leaves nothing behind.
#
# Reads local files only. Usage: check-skill-licenses.sh [repository-root]
# Exit codes: 0 every record is present and consistent, 1 a record is missing or wrong, 2 the
# skills could not be enumerated.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/frontmatter.lib.sh
source "$here/frontmatter.lib.sh"
cd "${1:-$here/..}"

catalogue=docs/plugins.md
notice_name=THIRD-PARTY-NOTICES.md
first_party=https://github.com/devantler-tech/

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT
if ! find plugins -type f -path '*/skills/*/SKILL.md' -print0 > "$work/skills"; then
  echo '::error::could not enumerate bundled skills; no license record was checked'
  exit 2
fi

# The top-level `license:` value of a SKILL.md frontmatter, or nothing.
declared_license() {
  awk '/^---[[:space:]]*$/ { n++; next } n == 1 && /^license:/ { sub(/^license:[[:space:]]*/, ""); print; exit }' "$1"
}

# Every `| `<skill>` | ... |` row of a file whose first column is a backticked skill name, as
# tab-separated cells without the backticks.
skill_rows() {
  [ -f "$1" ] || return 0
  awk -F'|' '/^\| `[a-z0-9-]+` \|/ {
    out = ""
    for (i = 2; i < NF; i++) { c = $i; gsub(/^[[:space:]]+|[[:space:]]+$/, "", c); gsub(/`/, "", c); out = out (i > 2 ? "\t" : "") c }
    print out
  }' "$1"
}

skill_rows "$catalogue" > "$work/catalogue"
failed=0
checked=0
: > "$work/bundled"
while IFS= read -r -d '' skill; do
  checked=$((checked + 1))
  name=${skill%/SKILL.md}; name=${name##*/}
  plugin=${skill#plugins/}; plugin=${plugin%%/*}
  printf '%s\t%s\n' "$plugin" "$name" >> "$work/bundled"
  if ! repository=$(frontmatter_repository < "$skill") || [ -z "$repository" ]; then
    echo "::error file=$skill::$name has no metadata.github-repo, so its license cannot be attributed"
    failed=1
    continue
  fi
  upstream=${repository#https://github.com/}
  declared=$(declared_license "$skill")
  [[ $declared =~ ^[A-Za-z0-9.+-]+$ ]] || declared=

  rows=$(awk -F'\t' -v s="$name" -v p="$plugin" '$1 == s && $2 == p' "$work/catalogue")
  if [ "$(grep -c . <<<"$rows" || true)" -ne 1 ]; then
    echo "::error file=$catalogue::$catalogue needs exactly one skill-license row for $name: | \`$name\` | \`$plugin\` | $upstream | <SPDX license> |"
    failed=1
    catalogue_license=
  else
    IFS=$'\t' read -r _ _ row_upstream catalogue_license <<<"$rows"
    if [ "$row_upstream" != "$upstream" ]; then
      echo "::error file=$catalogue::$catalogue lists $name from $row_upstream, but the skill comes from $upstream"
      failed=1
    fi
  fi
  if [ -n "$declared" ] && [ -n "$catalogue_license" ] && [ "$declared" != "$catalogue_license" ]; then
    echo "::error file=$catalogue::$name declares $declared, but $catalogue lists $catalogue_license"
    failed=1
  fi

  [[ $repository == "$first_party"* ]] && continue

  notice=plugins/$plugin/resources/$notice_name
  if [ ! -f "$notice" ] || [ -L "$notice" ]; then
    echo "::error file=$skill::$name comes from $upstream; record its license in $notice: a row | \`$name\` | $upstream | <SPDX license> | and a ## $upstream section with its copyright notice and license text"
    failed=1
    continue
  fi
  rows=$(skill_rows "$notice" | awk -F'\t' -v s="$name" '$1 == s')
  if [ "$(grep -c . <<<"$rows" || true)" -ne 1 ]; then
    echo "::error file=$notice::$notice needs exactly one row for $name: | \`$name\` | $upstream | <SPDX license> |"
    failed=1
    continue
  fi
  IFS=$'\t' read -r _ notice_upstream notice_license <<<"$rows"
  if [ "$notice_upstream" != "$upstream" ]; then
    echo "::error file=$notice::$notice lists $name from $notice_upstream, but the skill comes from $upstream"
    failed=1
  fi
  if ! grep -qxF "## $upstream" "$notice"; then
    echo "::error file=$notice::$notice has no '## $upstream' section with the copyright notice and license text for $name"
    failed=1
  fi
  if [ -n "$declared" ] && [ "$declared" != "$notice_license" ]; then
    echo "::error file=$notice::$name declares $declared, but $notice lists $notice_license"
    failed=1
  fi
  if [ -n "$catalogue_license" ] && [ "$catalogue_license" != "$notice_license" ]; then
    echo "::error file=$catalogue::$catalogue lists $name as $catalogue_license, but $notice lists $notice_license"
    failed=1
  fi
done < "$work/skills"

if [ "$checked" -eq 0 ]; then
  echo '::error::no bundled skill was found, so no license record was checked'
  exit 2
fi

# Rows for skills that are not bundled.
while IFS=$'\t' read -r name plugin _; do
  if ! grep -qxF "$plugin"$'\t'"$name" "$work/bundled"; then
    echo "::error file=$catalogue::$catalogue has a license row for $name in $plugin, which bundles no such skill"
    failed=1
  fi
done < "$work/catalogue"
for notice in plugins/*/resources/"$notice_name"; do
  [ -f "$notice" ] || continue
  plugin=${notice#plugins/}; plugin=${plugin%%/*}
  while IFS=$'\t' read -r name _; do
    if ! grep -qxF "$plugin"$'\t'"$name" "$work/bundled"; then
      echo "::error file=$notice::$notice has a row for $name, which $plugin does not bundle"
      failed=1
    fi
  done < <(skill_rows "$notice")
done

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "✓ license records for $checked bundled skills"
