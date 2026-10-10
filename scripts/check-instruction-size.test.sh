#!/usr/bin/env bash
# Self-test for check-instruction-size.sh: it must PASS a small file with a complete
# guide table, and FAIL every way the always-loaded file can stop fitting in one read
# or lose a guide. Hermetic: fixtures live in a temporary directory.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHECK="$HERE/check-instruction-size.sh"
WORK=$(mktemp -d)

# Bash 3.2 can report an aborted script to an EXIT trap as status 0, and the trap's
# own successful cleanup then becomes the exit status. Completion is recorded
# explicitly so a run that stops early can never read as a pass.
finished=0
cleanup() {
  local status=$?
  rm -rf "$WORK"
  if [ "$finished" -ne 1 ] && [ "$status" -eq 0 ]; then
    echo 'FAIL: the self-test stopped before finishing' >&2
    status=1
  fi
  exit "$status"
}
trap cleanup EXIT

failures=0
cases=0

# Write a fixture repository: an AGENTS.md of exactly <bytes> bytes whose guide
# table links <guide>, and that guide on disk unless <create> is "no".
fixture() {
  local dir=$1 bytes=$2 guide=${3:-docs/guide.md} create=${4:-yes} head pad
  mkdir -p "$dir/docs"
  head=$(printf '# Fixture\n\n## Agent guides\n\n| Guide | Read it before |\n|---|---|\n| [%s](%s) | doing the thing |\n\n## Notes\n\n' "$guide" "$guide")
  printf '%s\n\n' "$head" >"$dir/AGENTS.md"
  pad=$((bytes - $(wc -c <"$dir/AGENTS.md")))
  [ "$pad" -ge 0 ] || { echo "fixture: $bytes bytes is smaller than the header" >&2; return 1; }
  head -c "$pad" /dev/zero | tr '\0' 'x' >>"$dir/AGENTS.md"
  [ "$(wc -c <"$dir/AGENTS.md" | tr -d '[:space:]')" = "$bytes" ] || { echo 'fixture: wrong size' >&2; return 1; }
  if [ "$create" = yes ]; then
    mkdir -p "$dir/$(dirname "$guide")"
    echo '# Guide' >"$dir/$guide"
  fi
}

# Run the check against a fixture and require an exact exit status and a message.
expect() {
  local label=$1 want=$2 needle=$3 status=0
  shift 3
  cases=$((cases + 1))
  "$CHECK" "$@" >"$WORK/out.log" 2>&1 || status=$?
  if [ "$status" -ne "$want" ]; then
    echo "FAIL: $label — exit $status, wanted $want" >&2
    sed 's/^/      /' "$WORK/out.log" >&2
    failures=$((failures + 1))
    return 0
  fi
  if ! grep -Fq -- "$needle" "$WORK/out.log"; then
    echo "FAIL: $label — output does not mention: $needle" >&2
    sed 's/^/      /' "$WORK/out.log" >&2
    failures=$((failures + 1))
    return 0
  fi
  echo "PASS: $label"
}

fixture "$WORK/small" 2000
expect 'a small file with its guide passes' 0 'PASS: AGENTS.md is 2000 bytes' --root "$WORK/small"

fixture "$WORK/under" 32767
expect 'one byte under the limit passes' 0 'PASS: AGENTS.md is 32767 bytes' --root "$WORK/under"

fixture "$WORK/at" 32768
expect 'exactly the limit fails' 1 'AGENTS.md is 32768 bytes; it must stay under 32768' --root "$WORK/at"

fixture "$WORK/over" 43151
expect 'a file past the limit fails and names the fix' 1 'Move topic detail into a guide under docs/' --root "$WORK/over"

fixture "$WORK/missing-guide" 2000 docs/absent.md no
expect 'a linked guide that does not exist fails' 1 'links a guide that does not exist: docs/absent.md' --root "$WORK/missing-guide"

fixture "$WORK/escaping" 2000 ../outside.md no
expect 'a guide link that leaves the repository fails' 1 'not a plain path inside the repository: ../outside.md' --root "$WORK/escaping"

fixture "$WORK/no-table" 2000
grep -v '^| \[' "$WORK/no-table/AGENTS.md" >"$WORK/no-table/AGENTS.md.new"
mv "$WORK/no-table/AGENTS.md.new" "$WORK/no-table/AGENTS.md"
expect 'a guide table with no linked row fails' 1 'has no "Agent guides" table' --root "$WORK/no-table"

fixture "$WORK/no-heading" 2000
sed 's/^## Agent guides$/## Something else/' "$WORK/no-heading/AGENTS.md" >"$WORK/no-heading/AGENTS.md.new"
mv "$WORK/no-heading/AGENTS.md.new" "$WORK/no-heading/AGENTS.md"
expect 'a table outside the index heading does not count' 1 'has no "Agent guides" table' --root "$WORK/no-heading"

fixture "$WORK/broken-row" 2000
printf '\n## Agent guides\n\n| [docs/guide.md](docs/guide.md) | ok |\n| [unclosed link | broken |\n' >>"$WORK/broken-row/AGENTS.md"
expect 'a row whose link cannot be read fails' 1 'readable link(s)' --root "$WORK/broken-row"

mkdir -p "$WORK/empty"
expect 'a missing AGENTS.md is unknown, never a pass' 2 'cannot read' --root "$WORK/empty"

expect 'an unknown argument is a usage error' 2 'unknown argument' --frobnicate

expect 'a --root with no value is a usage error' 2 'missing value for --root' --root

# The real repository must pass: this is the gate CI applies to every change.
expect 'the repository itself is within the limit' 0 'PASS: AGENTS.md is'

finished=1
if [ "$failures" -ne 0 ]; then
  echo "FAIL: $failures of $cases case(s) failed" >&2
  exit 1
fi
echo "PASS: check-instruction-size.sh holds across $cases case(s)"
