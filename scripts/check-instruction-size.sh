#!/usr/bin/env bash
# check-instruction-size.sh — keep the always-loaded instruction file within one read.
#
# WHY THIS EXISTS
#   Every agent session loads AGENTS.md. Codex reads at most 32 KiB of project
#   instructions and drops the rest without a warning, so a file past that size
#   loses its tail for one tool while the others still see all of it. Nothing
#   reports the loss. This gate fails before the file gets there.
#
#   The file stays small by keeping topic detail in guides that its "Agent guides"
#   table links. A row that points at a missing guide is a rule nobody can reach,
#   so the gate also checks that every linked guide exists.
#
# USAGE
#   ./scripts/check-instruction-size.sh [--root <repository-root>]
#
# EXIT CODES
#   0  AGENTS.md is under the limit and every guide in its table exists
#   1  the file has reached the limit, the table is missing or empty, or a guide is missing
#   2  usage error, or AGENTS.md could not be read (unknown, never a pass)

set -euo pipefail

# Codex's default project_doc_max_bytes. The file must stay strictly under it.
readonly LIMIT=32768
readonly INDEX_HEADING='## Agent guides'

die() { printf 'check-instruction-size: %s\n' "$1" >&2; exit 2; }

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || die 'missing value for --root'
      root=$2
      shift 2
      ;;
    *) die "unknown argument: $1 (usage: check-instruction-size.sh [--root <repository-root>])" ;;
  esac
done

file="$root/AGENTS.md"
if [ ! -f "$file" ] || [ ! -r "$file" ]; then
  die "cannot read $file"
fi

size=$(wc -c <"$file") || die "cannot measure $file"
size=${size//[[:space:]]/}
case "$size" in
  '' | *[!0-9]*) die "unexpected size for $file: '$size'" ;;
esac

failures=0

if [ "$size" -ge "$LIMIT" ]; then
  printf 'FAIL: AGENTS.md is %s bytes; it must stay under %s, the most Codex reads.\n' "$size" "$LIMIT" >&2
  printf '      Move topic detail into a guide under docs/ and add a row to the "Agent guides" table.\n' >&2
  failures=$((failures + 1))
fi

# Table rows under the index heading that open with a Markdown link, then the link
# target of each. Only that section is read. A row whose target cannot be extracted
# is a failure, never a row that is quietly skipped.
rows=$(
  awk -v heading="$INDEX_HEADING" '
    /^## / { inside = ($0 == heading); next }
    inside && /^\| \[/ { print }
  ' "$file"
) || die "cannot read the guide table in $file"
guides=$(sed -n 's/^| \[[^]]*](\([^)]*\)).*$/\1/p' <<<"$rows") || die "cannot read the guide links in $file"

row_count=0
guide_count=0
[ -z "$rows" ] || row_count=$(grep -c '' <<<"$rows")
[ -z "$guides" ] || guide_count=$(grep -c '' <<<"$guides")
if [ "$row_count" -ne "$guide_count" ]; then
  printf 'FAIL: %s row(s) in the "%s" table but only %s readable link(s).\n' \
    "$row_count" "${INDEX_HEADING#\#\# }" "$guide_count" >&2
  failures=$((failures + 1))
fi

count=0
if [ -z "$guides" ]; then
  printf 'FAIL: AGENTS.md has no "%s" table with a linked guide.\n' "${INDEX_HEADING#\#\# }" >&2
  printf '      Restore the table: it is how detail moved out of this file stays reachable.\n' >&2
  failures=$((failures + 1))
else
  while IFS= read -r guide; do
    count=$((count + 1))
    case "$guide" in
      /* | ../* | */../* | *'#'* | *://*)
        printf 'FAIL: guide link is not a plain path inside the repository: %s\n' "$guide" >&2
        failures=$((failures + 1))
        continue
        ;;
    esac
    if [ ! -f "$root/$guide" ]; then
      printf 'FAIL: AGENTS.md links a guide that does not exist: %s\n' "$guide" >&2
      printf '      Add the file, or remove its row from the "Agent guides" table.\n' >&2
      failures=$((failures + 1))
    fi
  done <<<"$guides"
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi

printf 'PASS: AGENTS.md is %s bytes (limit %s) and all %s linked guide(s) exist.\n' "$size" "$LIMIT" "$count"
