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

GH_TELEMETRY=0 "$GUARD" --command \
  "gh issue view 3196 --repo devantler-tech/platform --json issueType,blockedBy,assignees --jq '{issueType:.issueType,assignees:[.assignees[].login],blockedByTotal:.blockedBy.totalCount,blockedByNumbers:[.blockedBy.nodes[]?.number]}'" \
  >/dev/null || fail 'the prescribed dependency read is not admitted by the forge guard'

printf 'portfolio-surveyor agent contract: PASS\n'
