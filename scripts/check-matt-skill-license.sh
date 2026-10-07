#!/usr/bin/env bash
# Bind Matt Pocock's distributed notice to the same upstream commit and skill tree.
# Fetch public Git objects only; never check out or execute upstream code.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/frontmatter.lib.sh
source "$here/frontmatter.lib.sh"
unknown() { printf 'Matt Pocock license: incomplete observation\n' >&2; exit 2; }
reject() { printf 'Matt Pocock license: %s\n' "$1" >&2; exit 1; }
[[ $# == 1 && -f $1 && ! -L $1 ]] || unknown
skill=$1
work=$(mktemp -d) || unknown
trap 'rm -rf "$work"' EXIT
head -c 8388609 "$skill" > "$work/SKILL.md" || unknown
[[ $(wc -c < "$work/SKILL.md") -le 8388608 ]] || unknown
owner=$(frontmatter_repository < "$work/SKILL.md") || unknown
[[ $owner == https://github.com/mattpocock/skills ]] || exit 0
plugin=${skill%/skills/*}
notice=$plugin/resources/matt-pocock-LICENSE.txt
[[ -f $notice && ! -L $notice ]] || reject 'the distributed notice is missing'
cp "$notice" "$work/distributed" || unknown
ref=$(frontmatter_metadata "$work/SKILL.md" github-ref) || unknown
path=$(frontmatter_metadata "$work/SKILL.md" github-path) || unknown
expected_tree=$(frontmatter_metadata "$work/SKILL.md" github-tree-sha) || unknown
[[ $path =~ ^skills/(engineering|productivity)/[a-z0-9-]+$ &&
   $expected_tree =~ ^[0-9a-f]{40}$ ]] || unknown
if [[ ! $ref =~ ^[0-9a-f]{40}$ ]]; then
  [[ $ref == refs/heads/* || $ref == refs/tags/* ]] || unknown
  git check-ref-format "$ref" > /dev/null 2>&1 || unknown
fi
# Inherited selectors, config includes, URL rewrites and askpass helpers cannot
# redirect this fixed public read or execute a host-side helper.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CONFIG_PARAMETERS GIT_CONFIG GIT_TEMPLATE_DIR GIT_ASKPASS SSH_ASKPASS
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_TERMINAL_PROMPT=0
git -c core.hooksPath=/dev/null init --quiet --bare "$work/source.git" || unknown
if ! git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=30 -C "$work/source.git" \
  fetch --quiet --depth=1 --no-tags https://github.com/mattpocock/skills.git "$ref" \
  > "$work/fetch.log" 2>&1; then
  unknown
fi
revision=$(git -C "$work/source.git" rev-parse --verify 'FETCH_HEAD^{commit}') || unknown
observed_tree=$(git -C "$work/source.git" rev-parse --verify "$revision:$path") || unknown
[[ $observed_tree == "$expected_tree" ]] || unknown
[[ $(git -C "$work/source.git" cat-file -t "$observed_tree") == tree ]] || unknown
git -C "$work/source.git" show "$revision:LICENSE" > "$work/upstream" 2> "$work/read.log" || unknown
status=0
cmp -s "$work/upstream" "$work/distributed" || status=$?
case $status in
  0) printf 'Matt Pocock license: verified notice and upstream tree at %s\n' "$revision" ;;
  1) reject 'the notice differs from the skill source; review licensing before updating it' ;;
  *) unknown ;;
esac
