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
    # Object KEYS are scanned as well as values, and an all-string array (an argv list such as
    # ["pr","view","--json","state,merged"]) is ALSO emitted joined, as the one command it is.
    *.json) jq -r '.. | if type == "object" then keys_unsorted[]
                        elif type == "array" and length > 0 and all(type == "string") then join(" ")
                        elif type == "string" then .
                        else empty end | ., "%"' "$1" 2>/dev/null || true ;;
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
# (`--json` then a line break), which CLOSES the span rather than opening an argument.
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
    | sed -E -e "s/--json[\`\"']/--json%/g" \
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

[ -d "${root}/plugins" ] || unknown "no plugins/ directory under ${root}"

# Every file an agent may read is a surface: Markdown, plain-text references and assets, and JSON.
# Scripts are skipped (see the header). Any OTHER file type is UNKNOWN rather than skipped, so a new
# kind of definition cannot ship unscanned while this check stays green — extend the list instead.
# NUL-delimited, so a file name containing a newline stays one surface instead of two that do not exist.
# Symbolic links are surfaces too (read through to their target); a dangling one fails the -r check.
surfaces=()
while IFS= read -r -d '' f; do
  case "$f" in
    *.md|*.txt|*.json) surfaces+=("$f") ;;
    *.sh) ;;
    *) unknown "${f#"${root}/"} is a file type this guard does not scan, so any field it prescribes would go unseen" ;;
  esac
done < <(find "${root}/plugins" \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
[ "${#surfaces[@]}" -gt 0 ] || unknown "found no *.md, *.txt or *.json under ${root}/plugins"

scanned=0
lists=0
offenders=""
for surface in "${surfaces[@]}"; do
  # An unreadable surface would decode to nothing and read as clean, so it is UNKNOWN instead.
  [ -r "${surface}" ] || unknown "${surface#"${root}/"} cannot be read, so any field it prescribes would go unseen"
  case "${surface}" in
    *.json) jq empty "${surface}" >/dev/null 2>&1 ||
              unknown "${surface#"${root}/"} does not parse, so any field it prescribes would go unseen" ;;
  esac
  scanned=$((scanned + 1))
  lists=$((lists + $(extract_lists "${surface}" | grep -c . || true)))
  while IFS= read -r bad; do
    [ -n "${bad}" ] && offenders="${offenders}  ${surface#"${root}/"}: ${bad}"$'\n'
  done < <(bad_lists_in "${surface}")
done

[ "${lists}" -gt 0 ] ||
  unknown "extracted no \`--json\` list from ${scanned} surfaces — the extractor is probably broken"

if [ -n "${offenders}" ]; then
  printf '%s\n%s' 'guard-gh-json-fields: FAIL — a bundled definition requests the nonexistent "merged" field:' "${offenders}" >&2
  echo "  One unknown field voids the whole gh request. Use state, mergedAt or mergeCommit instead." >&2
  exit 1
fi

echo "guard-gh-json-fields: OK — no invalid \`merged\` field in ${lists} --json list(s) across ${scanned} surfaces"
