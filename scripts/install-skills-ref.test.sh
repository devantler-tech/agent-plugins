#!/usr/bin/env bash
# Exercise the installer with an offline package manager and observable backoff.
# An optional script path supports running the same cases against a regression mutant.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INSTALLER=${1:-$HERE/install-skills-ref.sh}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

cat > "$WORK/bin/python" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'install\n' >> "$CASE_DIR/calls"
expected="skills-ref @ git+https://github.com/agentskills/agentskills.git@8d8fcbc69e0c42e05922c2ffc287a3bbdef7b0a3#subdirectory=skills-ref"
if [ "$#" -ne 5 ] || [ "$1" != -m ] || [ "$2" != pip ] ||
   [ "$3" != install ] || [ "$4" != --disable-pip-version-check ] || [ "$5" != "$expected" ]; then
  echo 'unexpected package-manager arguments' >&2
  exit 91
fi
attempt=$(wc -l < "$CASE_DIR/calls" | tr -d ' ')
if [ "$attempt" -lt "$SUCCESS_AT" ]; then
  echo 'fatal: unable to access pinned upstream: HTTP 403' >&2
  exit 42
fi
STUB
cat > "$WORK/bin/sleep" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CASE_DIR/waits"
STUB
chmod +x "$WORK/bin/python" "$WORK/bin/sleep"
export PATH="$WORK/bin:$PATH"
export AGENTSKILLS_REF=8d8fcbc69e0c42e05922c2ffc287a3bbdef7b0a3

failures=0
# Run an isolated installer scenario and compare exit status, install attempts, and backoff.
# Arguments: label, first successful attempt, expected exit, expected attempts, comma-separated waits.
run_case() {
  local name=$1 success_at=$2 expected_status=$3 expected_calls=$4 expected_waits=$5
  local status=0 calls waits
  CASE_DIR="$WORK/$name"
  export CASE_DIR SUCCESS_AT=$success_at
  mkdir -p "$CASE_DIR"
  : > "$CASE_DIR/calls"
  : > "$CASE_DIR/waits"
  bash "$INSTALLER" > "$CASE_DIR/output" 2>&1 || status=$?
  calls=$(wc -l < "$CASE_DIR/calls" | tr -d ' ')
  waits=$(paste -sd, "$CASE_DIR/waits")
  if [ "$status" = "$expected_status" ] && [ "$calls" = "$expected_calls" ] &&
     [ "$waits" = "$expected_waits" ]; then
    echo "PASS $name"
  else
    echo "FAIL $name: status=$status calls=$calls waits=$waits"
    cat "$CASE_DIR/output"
    failures=$((failures + 1))
  fi
}

run_case first-attempt 1 0 1 ''
run_case transient-failure 2 0 2 5
run_case two-failures 3 0 3 5,10
run_case persistent-failure 99 42 3 5,10
AGENTSKILLS_REF=main run_case floating-ref 1 2 0 ''
AGENTSKILLS_REF='' run_case missing-ref 1 2 0 ''

if [ "$failures" -ne 0 ]; then
  echo "$failures installer cases failed"
  exit 1
fi
echo 'All installer cases passed'
