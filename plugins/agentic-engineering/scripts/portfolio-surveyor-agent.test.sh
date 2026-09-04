#!/usr/bin/env bash
#
# Contract test for the portfolio-surveyor agent definition.
#
# A GitHub issue's `blockedBy` field is a connection object, not an array.
# Pin the executable read shape here because an array-shaped prescription made
# every dependency lookup fail before the surveyor could classify a candidate.
#
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SURVEYOR="$HERE/../agents/portfolio-surveyor.agent.md"
GUARD="$HERE/forge-readonly-guard.sh"

fail() {
  printf 'portfolio-surveyor agent contract: FAIL — %s\n' "$*" >&2
  exit 1
}

grep -Fq '.blockedBy.nodes[]?.number' "$SURVEYOR" ||
  fail 'dependency reads must traverse blockedBy.nodes before selecting issue numbers'
grep -Fq '.blockedBy.totalCount' "$SURVEYOR" ||
  fail 'dependency reads must preserve the blockedBy connection total'

JQ_FILTER=$(sed -n \
  "/--json issueType,blockedBy,assignees/{n;s/^[[:space:]]*--jq '\\(.*\\)'$/\\1/p;}" \
  "$SURVEYOR")
[ -n "$JQ_FILTER" ] || fail 'could not extract the prescribed dependency jq filter'

expect_output() {
  local label=$1 input=$2 expected=$3 actual
  actual=$(jq -c "$JQ_FILTER" <<<"$input") ||
    fail "$label: complete connection was rejected"
  [ "$actual" = "$expected" ] ||
    fail "$label: expected $expected, got $actual"
}

expect_unknown() {
  local label=$1 input=$2 output
  if output=$(jq -c "$JQ_FILTER" <<<"$input" 2>&1); then
    fail "$label: malformed or incomplete connection produced actionable output: $output"
  fi
}

expect_output 'complete mixed-state connection' \
  '{"issueType":null,"assignees":[],"blockedBy":{"nodes":[{"number":10,"state":"OPEN"},{"number":11,"state":"CLOSED"}],"totalCount":2}}' \
  '{"issueType":null,"assignees":[],"blockedByTotal":2,"blockedByNumbers":[10,11],"openBlockedByNumbers":[10]}'
expect_output 'complete empty connection' \
  '{"issueType":null,"assignees":[],"blockedBy":{"nodes":[],"totalCount":0}}' \
  '{"issueType":null,"assignees":[],"blockedByTotal":0,"blockedByNumbers":[],"openBlockedByNumbers":[]}'

expect_unknown 'missing connection' \
  '{"issueType":null,"assignees":[]}'
expect_unknown 'null connection' \
  '{"issueType":null,"assignees":[],"blockedBy":null}'
expect_unknown 'array-shaped connection' \
  '{"issueType":null,"assignees":[],"blockedBy":[]}'
expect_unknown 'null nodes' \
  '{"issueType":null,"assignees":[],"blockedBy":{"nodes":null,"totalCount":0}}'
expect_unknown 'wrong-shaped total' \
  '{"issueType":null,"assignees":[],"blockedBy":{"nodes":[],"totalCount":"0"}}'
expect_unknown 'truncated connection' \
  '{"issueType":null,"assignees":[],"blockedBy":{"nodes":[],"totalCount":1}}'

GH_TELEMETRY=0 "$GUARD" --command \
  "gh issue view 3196 --repo devantler-tech/platform --json issueType,blockedBy,assignees --jq '$JQ_FILTER'" \
  >/dev/null || fail 'the prescribed dependency read is not admitted by the forge guard'

printf 'portfolio-surveyor agent contract: PASS\n'
