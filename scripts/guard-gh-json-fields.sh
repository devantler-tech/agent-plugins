#!/usr/bin/env bash
#
# Refuses a bundled definition that tells an agent to request a `gh` JSON field that does not exist.
#
# The field this guards is `merged`. It exists on none of `gh pr view`, `gh pr list` or
# `gh search prs`, yet it is what an agent reaches for when confirming a merge — and `gh` rejects the
# WHOLE `--json` request when any single field is unknown, so `--json state,merged,mergedAt` returns
# nothing and the agent cannot tell whether its own merge landed. `mergedAt`, `mergedBy` and
# `mergeCommit` are valid and are never reported.
#
# A consumer can only catch a bad prescription after it has already been pinned. Checking here, where
# the definitions are authored (and where synced skills arrive), stops it before it ships.
#
# Usage: guard-gh-json-fields.sh [ROOT]      (ROOT defaults to this repository)
# Scans every *.md, *.txt and *.json under ROOT/plugins; any other non-script file is UNKNOWN. Shell
# scripts are not scanned: a script with a bad field fails loudly the first time it runs, whereas prose
# silently misleads every agent that reads it.
#
# A surface that legitimately contains the request (a skill warning against it) is exempted by a
# reviewed line in scripts/gh-json-fields-allowlist.tsv — path, TAB, the exact `--json …` text, TAB,
# the reason. An exemption that stops matching is UNKNOWN, so it cannot cover a later sync.
#
# Exit: 0 clean · 1 an invalid field is prescribed · 2 UNKNOWN (nothing scanned, a surface cannot be
# read, a JSON surface does not parse, a file type is not scanned, or no `--json` list was found — any of
# which would make a 0 meaningless).

set -euo pipefail

root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

unknown() {
  echo "guard-gh-json-fields: UNKNOWN — $*" >&2
  exit 2
}

# Emit a surface as plain text. JSON is DECODED, never pattern-matched: a \u escape of a letter IS
# that letter, so an escaped `merged` is still `merged`. Each decoded string is followed by `%`, which ends a field
# list, so two unrelated values cannot join into `--json merged`.
decode_surface() {
  case "$1" in
    # Object KEYS are scanned as well as values. An argv list (an all-string array under an `args`,
    # `argv`, `cmd` or `command` key, e.g. ["pr","view","--json","state,merged"]) is ALSO emitted
    # joined, as the one command it is; any other array keeps its elements apart.
    *.json) jq -r '( .. | if type == "object" then keys_unsorted[] elif type == "string" then . else empty end ),
                     ( .. | objects | to_entries[] | select(.key | test("^(args|argv|cmd|command)$"; "i"))
                          | .value | select(type == "array" and length > 0 and all(type == "string"))
                          | join(" ") )
                   | ., "%"' "$1" 2>/dev/null || true ;;
    *)      cat "$1" ;;
  esac
}

# Emit one `--json <fields>` per line, whatever formatting the prescription used: plain, `=`, quoted,
# wrapped after a comma, backslash continuation, an ellipsis elision, wrapped straight after the flag,
# or a JSON `\n` escape. A backslash at the end of a line is removed and the next line joined with no
# space, exactly as the shell does, so `state,mer\` + `ged` still reads as `merged`.
# A comma joins what follows it only across a line break — a comma and a space on the same line is
# prose, which `gh` could never receive as one argument. A backtick or quote ends a list, so Markdown
# prose after an inline command is never read as more fields — including a quote hugging the flag
# (`--json` then a line break), which CLOSES the span rather than opening an argument. A flag wrapped
# in SHELL quotes ('--json') is unwrapped first — that is one argument to the shell — while a
# backtick-wrapped one stays a Markdown code span.
extract_lists() {
  decode_surface "$1" \
    | tr -d '\000' \
    | awk '{ if (sub(/\\$/, "")) { printf "%s", $0 } else { print } }' \
    | sed -E -e 's/\\[nrt]/ /g' -e 's/\\/ /g' \
    | awk '{
        line = $0; sub(/[[:space:]]+$/, "", line)
        if (NR > 1 && buf ~ /,$/) { sub(/^[[:space:]]+/, "", line); buf = buf line }
        else { if (NR > 1) print buf; buf = line }
      } END { if (NR > 0) print buf }' \
    | tr '\n' ' ' \
    | sed -E -e "s/[\"']--json[\"']/--json/g" \
             -e "s/--json[\`\"']/--json%/g" \
             -e 's/…/,/g' -e 's/\.\.\./,/g' \
             -e 's/[[:space:]]+/ /g' \
             -e 's/--json[[:space:]]*[=,]*[[:space:]]*[`"'"'"']?[[:space:]]*/--json /g' \
    | grep -a -o -- '--json [A-Za-z,]*' | sort -u || true   # NULs are deleted above and -a keeps text mode anyway: GNU grep would otherwise print "binary file matches" and no list
}

# Every list in $1 that names a bare `merged`, one per line.
bad_lists_in() {
  local list fields
  while IFS= read -r list; do
    fields="${list#--json }"
    case ",${fields}," in
      *,merged,*) printf -- '--json %s\n' "${fields}" ;;
    esac
  done < <(extract_lists "$1")
}

# A surface may legitimately CONTAIN the bad request — a skill that WARNS against it, for instance.
# A synced skill cannot be corrected here, so the escape hatch is a reviewed list in this repository
# rather than a marker inside the file the upstream owns.
#
# An exemption names the EXACT request it covers, not just the file: a later sync replaces the file
# while this list stays, so a path-wide exemption would quietly cover a genuinely bad request that
# arrived afterwards. Each line is: path, TAB, the exact `--json <fields>` text, TAB, the reason.
# `#` starts a comment. An exemption that no longer matches anything is UNKNOWN — a stale line must
# be removed deliberately rather than sitting there covering whatever appears next.
allowlist="${root}/scripts/gh-json-fields-allowlist.tsv"
tab="$(printf '\t')"
allowed_entries=""
if [ -e "${allowlist}" ]; then
  if ! { [ -f "${allowlist}" ] && [ -r "${allowlist}" ]; }; then
    unknown "${allowlist#"${root}/"} exists but cannot be read, so its exemptions are unknown"
  fi
  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in ''|'#'*) continue ;; esac
    entry_path="${line%%"${tab}"*}"
    entry_rest="${line#*"${tab}"}"
    entry_list="${entry_rest%%"${tab}"*}"
    entry_reason="${entry_rest#*"${tab}"}"
    { [ -n "${entry_path}" ] && [ -n "${entry_list}" ] && [ -n "${entry_reason}" ] &&
      [ "${entry_rest}" != "${line}" ] && [ "${entry_reason}" != "${entry_rest}" ]; } ||
      unknown "${allowlist#"${root}/"} needs a path, the exact \`--json …\` text and a reason, tab-separated: ${line}"
    allowed_entries="${allowed_entries}${entry_path}${tab}${entry_list}"$'\n'
  done < "${allowlist}"
fi

is_allowed() {                      # $1 = path relative to the root, $2 = the extracted list
  case $'\n'"${allowed_entries}" in
    *$'\n'"$1${tab}$2"$'\n'*) return 0 ;;
  esac
  return 1
}
allowed_seen=""
allowed_used=""

[ -d "${root}/plugins" ] || unknown "no plugins/ directory under ${root}"

# Every file an agent may read is a surface: Markdown, plain-text references and assets, and JSON.
# Scripts are skipped (see the header). Any OTHER file type is UNKNOWN rather than skipped, so a new
# kind of definition cannot ship unscanned while this check stays green — extend the list instead.
# NUL-delimited, so a file name containing a newline stays one surface instead of two that do not exist.
# Everything that is not a directory is discovered — symlinks included, and anything unusual too, so
# the regular-file check below reports it rather than the scan silently missing it.
#
# Discovery is MATERIALISED first and its exit status checked. Read straight from the pipeline, a
# `find` that dies part way through would deliver a short list and the scan would report OK over
# whatever it happened to see.
discovered="$(mktemp)"
trap 'rm -f "${discovered}"' EXIT
find "${root}/plugins" ! -type d -print0 2>/dev/null | LC_ALL=C sort -z > "${discovered}" ||
  unknown "could not list the files under ${root}/plugins, so the scan would cover an unknown subset"

surfaces=()
while IFS= read -r -d '' f; do
  case "$f" in
    *.md|*.txt|*.json) surfaces+=("$f") ;;
    *.sh) ;;
    *) unknown "${f#"${root}/"} is a file type this guard does not scan, so any field it prescribes would go unseen" ;;
  esac
done < <(cat "${discovered}")
[ "${#surfaces[@]}" -gt 0 ] || unknown "found no *.md, *.txt or *.json under ${root}/plugins"

scanned=0
lists=0
offenders=""
for surface in "${surfaces[@]}"; do
  # An unreadable surface would decode to nothing and read as clean, so it is UNKNOWN instead. A
  # surface that is not a REGULAR file after resolution — a device, a named pipe, a dangling link —
  # is UNKNOWN too: reading one can never finish, and a check that hangs is worse than one that fails.
  [ -f "${surface}" ] || unknown "${surface#"${root}/"} is not a regular file (a device, a pipe, or a dangling link), so it cannot be scanned"
  [ -r "${surface}" ] || unknown "${surface#"${root}/"} cannot be read, so any field it prescribes would go unseen"
  case "${surface}" in
    *.json) jq empty "${surface}" >/dev/null 2>&1 ||
              unknown "${surface#"${root}/"} does not parse, so any field it prescribes would go unseen" ;;
  esac
  scanned=$((scanned + 1))
  lists=$((lists + $(extract_lists "${surface}" | grep -c . || true)))
  rel="${surface#"${root}/"}"
  while IFS= read -r bad; do
    [ -n "${bad}" ] || continue
    if is_allowed "${rel}" "${bad}"; then
      allowed_seen="${allowed_seen}  ${rel}: ${bad}"$'\n'
      allowed_used="${allowed_used}${rel}${tab}${bad}"$'\n'
      continue
    fi
    offenders="${offenders}  ${rel}: ${bad}"$'\n'
  done < <(bad_lists_in "${surface}")
done

[ "${lists}" -gt 0 ] ||
  unknown "extracted no \`--json\` list from ${scanned} surfaces — the extractor is probably broken"

if [ -n "${allowed_seen}" ]; then
  printf 'guard-gh-json-fields: allowed by %s:\n%s' "${allowlist#"${root}/"}" "${allowed_seen}" >&2
fi

if [ -n "${offenders}" ]; then
  printf '%s\n%s' 'guard-gh-json-fields: FAIL — a bundled definition requests the nonexistent "merged" field:' "${offenders}" >&2
  echo "  One unknown field voids the whole gh request. Use state, mergedAt or mergeCommit instead." >&2
  exit 1
fi

# An exemption that matched nothing is STALE: the file it covered has changed, so the line is now
# standing guard over whatever the next sync brings. Say so rather than carrying it silently.
stale=""
while IFS= read -r entry; do
  [ -n "${entry}" ] || continue
  case $'\n'"${allowed_used}" in
    *$'\n'"${entry}"$'\n'*) ;;
    *) stale="${stale}  ${entry}"$'\n' ;;
  esac
done <<EOF
${allowed_entries}
EOF
[ -z "${stale}" ] ||
  unknown "these exemptions in ${allowlist#"${root}/"} no longer match anything and must be removed:
${stale}"

echo "guard-gh-json-fields: OK — no invalid \`merged\` field in ${lists} --json list(s) across ${scanned} surfaces"
