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

# A command stored as an object KEY is scanned too.
dir="$(fixture bad-json-key)"
printf '%s\n' '{"gh pr view --json state,merged":"example to run"}' > "${dir}/plugins/p/plugin.json"
expect 1 "JSON with the request as an object key" "${dir}"

# An argv array is one command, so `--json` and its next element are read together.
dir="$(fixture bad-json-argv)"
printf '%s\n' '{"command":"gh","args":["pr","view","--json","state,merged"]}' > "${dir}/plugins/p/.mcp.json"
expect 1 "JSON argv array naming merged" "${dir}"

dir="$(fixture good-json-argv)"
printf '%s\n' '{"command":"gh","args":["pr","view","--json","state,mergedAt"]}' > "${dir}/plugins/p/.mcp.json"
expect 0 "JSON argv array with valid fields" "${dir}"

# Any OTHER array keeps its elements apart: two notes do not form a command.
dir="$(fixture good-json-notes-array)"
printf '%s\n' '{"notes":["The option is --json","merged is unavailable"]}' > "${dir}/plugins/p/plugin.json"
expect 0 "a non-argv string array is not joined" "${dir}"

# A decoded NUL anywhere in the file must not make grep treat it as binary and print nothing.
dir="$(fixture bad-json-nul)"
printf '{"note":"a\x5cu0000b","prompt":"gh pr view <n> --json state,merged"}\n' > "${dir}/plugins/p/plugin.json"
expect 1 "JSON containing a NUL still has its request scanned" "${dir}"

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

# A closing backtick hugging the flag ends the span: wrapped prose that mentions `--json` and then
# starts the next line with "merged" names no field.
dir="$(fixture good-closing-backtick)"
printf '%s\n' 'The flag is `--json`' 'merged pull requests need no polling.' > "${dir}/plugins/p/agents/case.md"
expect 0 "a closing backtick after --json, then 'merged' on the next line" "${dir}"

# A flag wrapped in shell quotes is still the flag: `gh pr view 42 '--json' state,merged`.
dir="$(fixture bad-quoted-flag)"
printf '%s\n' "gh pr view 42 '--json' state,merged" > "${dir}/plugins/p/agents/case.md"
expect 1 "a shell-quoted --json flag" "${dir}"

dir="$(fixture bad-dquoted-flag)"
printf '%s\n' 'gh pr view 42 "--json" state,merged' > "${dir}/plugins/p/agents/case.md"
expect 1 "a double-quoted --json flag" "${dir}"

# Discovery that fails part way through must not read as a short, clean list.
if [ "$(id -u)" -ne 0 ]; then
  dir="$(fixture unknown-unlistable-dir)"
  mkdir -p "${dir}/plugins/p/skills/locked"
  chmod 000 "${dir}/plugins/p/skills/locked"
  expect 2 "an unlistable directory is UNKNOWN" "${dir}"
  chmod 700 "${dir}/plugins/p/skills/locked"
fi

# A backslash-newline INSIDE a field name is removed by the shell, so it must not split the name.
dir="$(fixture bad-continuation-mid-word)"
printf '%s\n%s\n' "gh pr view 42 --json state,mer\\" 'ged,mergedAt' > "${dir}/plugins/p/agents/case.md"
expect 1 "a backslash-newline splitting 'merged'" "${dir}"

# A symbolic link is a surface: skipping it would ship whatever its target says.
dir="$(fixture bad-symlink)"
printf '%s\n' '`gh pr view <n> --json state,merged`' > "${dir}/target.md"
ln -s "${dir}/target.md" "${dir}/plugins/p/agents/linked.md"
expect 1 "a symlinked surface is scanned through to its target" "${dir}"

# A link to a device or a pipe can never be read to the end, so it is UNKNOWN rather than a hang.
dir="$(fixture unknown-device-symlink)"
ln -s /dev/zero "${dir}/plugins/p/agents/device.md"
expect 2 "a symlink to a device is UNKNOWN, not a hang" "${dir}"

dir="$(fixture unknown-fifo)"
mkfifo "${dir}/plugins/p/agents/pipe.md"
expect 2 "a named pipe is UNKNOWN, not a hang" "${dir}"

# A surface may legitimately contain the request — a skill that warns against it. A reviewed
# allow-list line exempts the exact file content it was reviewed against.
sha_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

dir="$(fixture good-allowlisted)"
mkdir -p "${dir}/scripts"
printf '%s\n' 'Never run `gh pr view <n> --json state,merged`; use mergedAt instead.' > "${dir}/plugins/p/agents/warn.md"
printf 'plugins/p/agents/warn.md\t%s\tteaches the mistake on purpose\n' "$(sha_of "${dir}/plugins/p/agents/warn.md")" > "${dir}/scripts/gh-json-fields-allowlist.tsv"
expect 0 "an allow-listed file content does not fail" "${dir}"

dir="$(fixture bad-not-allowlisted)"
mkdir -p "${dir}/scripts"
printf '%s\n' 'Never run `gh pr view <n> --json state,merged`; use mergedAt instead.' > "${dir}/plugins/p/agents/warn.md"
cp "${dir}/plugins/p/agents/warn.md" "${dir}/plugins/p/agents/other.md"
printf 'plugins/p/agents/other.md\t%s\tonly this copy is exempt\n' "$(sha_of "${dir}/plugins/p/agents/other.md")" > "${dir}/scripts/gh-json-fields-allowlist.tsv"
expect 1 "an exemption covers only its own path" "${dir}"

# The exemption is bound to the reviewed CONTENT, so a later sync that adds a real prescription —
# even one that reads exactly like the warning — is no longer covered.
dir="$(fixture bad-content-changed)"
mkdir -p "${dir}/scripts"
printf '%s\n' 'Never run `gh pr view <n> --json state,merged`.' > "${dir}/plugins/p/agents/warn.md"
printf 'plugins/p/agents/warn.md\t%s\tteaches the mistake on purpose\n' "$(sha_of "${dir}/plugins/p/agents/warn.md")" > "${dir}/scripts/gh-json-fields-allowlist.tsv"
printf '%s\n' 'Now run `gh pr view <n> --json state,merged`.' >> "${dir}/plugins/p/agents/warn.md"
expect 1 "a later change to an allow-listed file is no longer covered" "${dir}"

# An exemption that matches nothing any more is UNKNOWN, so it cannot sit there covering the future.
dir="$(fixture unknown-stale-exemption)"
mkdir -p "${dir}/scripts"
printf '%s\n' 'This file no longer mentions the field.' > "${dir}/plugins/p/agents/warn.md"
printf 'plugins/p/agents/warn.md\t%s\tthe warning was removed upstream\n' 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' > "${dir}/scripts/gh-json-fields-allowlist.tsv"
expect 2 "a stale exemption is UNKNOWN" "${dir}"

dir="$(fixture unknown-allowlist-no-reason)"
mkdir -p "${dir}/scripts"
printf 'plugins/p/agents/warn.md\tdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' > "${dir}/scripts/gh-json-fields-allowlist.tsv"
expect 2 "an allow-list line with no reason is UNKNOWN" "${dir}"

dir="$(fixture unknown-allowlist-not-a-digest)"
mkdir -p "${dir}/scripts"
printf 'plugins/p/agents/warn.md\t--json state,merged\tthe old path-and-list form\n' > "${dir}/scripts/gh-json-fields-allowlist.tsv"
expect 2 "an allow-list second field that is not a digest is UNKNOWN" "${dir}"

dir="$(fixture unknown-allowlist-short-digest)"
mkdir -p "${dir}/scripts"
printf '%s\n' 'Never run `gh pr view <n> --json state,merged`; use mergedAt instead.' > "${dir}/plugins/p/agents/warn.md"
printf 'plugins/p/agents/warn.md\tdeadbeef\tan abbreviated digest is not a sha256\n' > "${dir}/scripts/gh-json-fields-allowlist.tsv"
expect 2 "an abbreviated allow-list digest is UNKNOWN" "${dir}"

dir="$(fixture unknown-dangling-symlink)"
ln -s "${dir}/missing.md" "${dir}/plugins/p/agents/dangling.md"
expect 2 "a dangling symlinked surface is UNKNOWN" "${dir}"

# Plain-text references and assets ship with skills and are read by agents, so they are scanned.
dir="$(fixture bad-txt-reference)"
mkdir -p "${dir}/plugins/p/skills/s/references"
printf '%s\n' 'gh pr view 42 --json state,merged' > "${dir}/plugins/p/skills/s/references/r.txt"
expect 1 "a bad request in a .txt reference" "${dir}"

# A file type the guard does not scan is UNKNOWN, never silently skipped. Scripts are exempt.
dir="$(fixture unknown-unscanned-type)"
printf '%s\n' 'cmd: gh pr view 42 --json state,merged' > "${dir}/plugins/p/agents/case.yaml"
expect 2 "an unscanned file type is UNKNOWN" "${dir}"

dir="$(fixture good-script-skipped)"
mkdir -p "${dir}/plugins/p/scripts"
printf '%s\n' 'gh pr view 42 --json state,merged' > "${dir}/plugins/p/scripts/helper.sh"
expect 0 "a script is not a scanned surface" "${dir}"

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
