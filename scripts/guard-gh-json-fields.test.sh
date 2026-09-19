#!/usr/bin/env bash
#
# Self-test for guard-gh-json-fields.sh. Every known-bad formatting must FAIL, every valid one must
# PASS, and each fail-closed path must report UNKNOWN rather than a clean result. Hermetic: throwaway
# fixture trees only.

# Fixtures are literal Markdown, so their backticks must NOT expand.
# shellcheck disable=SC2016

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guard="${here}/guard-gh-json-fields.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

passed=0
failed=0

# expect <want-exit> <description> <fixture-root>
expect() {
  local want="$1" what="$2" fixture="$3" got=0
  bash "${guard}" "${fixture}" >"${work}/out" 2>&1 || got=$?
  if [ "${got}" -eq "${want}" ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL: ${what} — expected exit ${want}, got ${got}" >&2
    sed 's/^/    /' "${work}/out" >&2
  fi
}

# fixture <name> — a fresh tree holding one always-valid list, so the "no lists found" floor is met
# and every case isolates the one surface under test.
fixture() {
  local dir="${work}/$1"
  mkdir -p "${dir}/plugins/p/agents"
  printf '%s\n' '`gh pr view <n> --json state,mergedAt`' > "${dir}/plugins/p/agents/baseline.md"
  printf '%s' "${dir}"
}

# One bad formatting per fixture, so each case proves the extractor catches THAT shape on its own.
i=0
while IFS= read -r -d '' bad; do
  i=$((i + 1))
  dir="$(fixture "bad-md-${i}")"
  printf '%s\n' "${bad}" > "${dir}/plugins/p/agents/case.md"
  expect 1 "markdown bad form ${i}: ${bad%%$'\n'*}" "${dir}"
done < <(printf '%s\0' \
  '`gh pr view <n> --json state,merged,mergedAt`' \
  '`gh pr view <n> --json=merged,additions`' \
  '`gh pr view <n> --json "merged,assignees"`' \
  "\`gh pr view <n> --json='merged,author'\`" \
  '`gh pr view <n> --json  =  merged,body`' \
  '`gh pr view <n> --json …mergeStateStatus,merged,closed`' \
  $'`gh pr view <n> --json state,\nmerged,comments`' \
  $'gh pr view <n> --json \\\n  merged,commits' \
  $'`gh pr view <n> --json\nstate,merged,body`' \
  '`gh pr list --json number,merged`')

i=0
while IFS= read -r -d '' good; do
  i=$((i + 1))
  dir="$(fixture "good-md-${i}")"
  printf '%s\n' "${good}" > "${dir}/plugins/p/agents/case.md"
  expect 0 "markdown valid form ${i}: ${good%%$'\n'*}" "${dir}"
done < <(printf '%s\0' \
  '`gh pr view <n> --json state,mergedAt,mergedBy,mergeCommit`' \
  '`gh pr view <n> --json "mergedAt,mergeCommit"`' \
  '`gh pr view <n> --json …mergeStateStatus,reviewDecision`' \
  $'`gh pr view <n> --json state,\nmergedAt,mergeCommit`' \
  'prose: run it, then confirm the merged state separately' \
  'boundary: see `gh pr view <n> --json comments`, merged PRs need no polling' \
  'boundary: `gh pr view <n> --json state`, and merged ones are done')

# JSON surfaces are decoded: a \u-escaped letter is still that letter, so an escaped field name is caught.
dir="$(fixture bad-json-escaped-name)"
printf '{"prompt":"gh pr view <n> --json state,\x5cu006derged,mergedAt"}\n' > "${dir}/plugins/p/plugin.json"
expect 1 "JSON with an escaped field name" "${dir}"

dir="$(fixture bad-json-escaped-space)"
printf '{"prompt":"gh pr view <n> --json\x5cu0020state,merged,closed"}\n' > "${dir}/plugins/p/plugin.json"
expect 1 "JSON with an escaped separator" "${dir}"

# Two unrelated values must not join into `--json merged`.
dir="$(fixture good-json-boundary)"
printf '%s\n' '{"label":"CLI option --json","description":"merged is not a valid field"}' > "${dir}/plugins/p/plugin.json"
expect 0 "JSON values stay separate" "${dir}"

dir="$(fixture good-json-prose-comma)"
printf '%s\n' '{"prompt":"Run gh pr view <n> --json state, merged PRs need no polling."}' > "${dir}/plugins/p/plugin.json"
expect 0 "JSON comma-then-space is prose" "${dir}"

# A skill file deep in the tree is scanned too — synced skills are the likeliest source.
dir="$(fixture bad-nested-skill)"
mkdir -p "${dir}/plugins/p/skills/s/references"
printf '%s\n' '`gh pr view <n> --json state,merged`' > "${dir}/plugins/p/skills/s/references/r.md"
expect 1 "a nested skill reference file" "${dir}"

# A file name containing a newline is still ONE surface: split in two, neither half exists and the
# bad request inside would go unread.
dir="$(fixture bad-newline-name)"
printf '%s\n' '`gh pr view <n> --json state,merged`' > "${dir}/plugins/p/agents/odd"$'\n'"name.md"
expect 1 "a bad request in a file whose name contains a newline" "${dir}"

dir="$(fixture good-newline-name)"
printf '%s\n' '`gh pr view <n> --json state,mergedAt`' > "${dir}/plugins/p/agents/odd"$'\n'"name.md"
expect 0 "a valid request in a file whose name contains a newline" "${dir}"

# Fail closed: an unreadable surface, an unparseable JSON surface, no plugins directory, no
# surfaces, no lists. (The unreadable case is skipped when running as root, which can read anything.)
if [ "$(id -u)" -ne 0 ]; then
  dir="$(fixture unknown-unreadable)"
  printf '%s\n' '`gh pr view <n> --json state,merged`' > "${dir}/plugins/p/agents/locked.md"
  chmod 000 "${dir}/plugins/p/agents/locked.md"
  expect 2 "an unreadable surface is UNKNOWN, not clean" "${dir}"
  chmod 600 "${dir}/plugins/p/agents/locked.md"
fi

dir="$(fixture unknown-bad-json)"
printf '%s\n' '{"prompt": "gh pr view --json state,merged"' > "${dir}/plugins/p/plugin.json"
expect 2 "unparseable JSON is UNKNOWN, not clean" "${dir}"

mkdir -p "${work}/unknown-no-plugins"
expect 2 "missing plugins/ is UNKNOWN" "${work}/unknown-no-plugins"

mkdir -p "${work}/unknown-empty/plugins/p"
expect 2 "no surfaces is UNKNOWN" "${work}/unknown-empty"

mkdir -p "${work}/unknown-no-lists/plugins/p"
printf '%s\n' 'no commands here' > "${work}/unknown-no-lists/plugins/p/README.md"
expect 2 "no --json lists is UNKNOWN" "${work}/unknown-no-lists"

echo "guard-gh-json-fields.test: ${passed} passed, ${failed} failed"
[ "${failed}" -eq 0 ]
