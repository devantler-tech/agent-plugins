#!/usr/bin/env bash
# Exercise the agent's prescribed count-only open-PR query and fail-closed projection.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SURVEYOR="$HERE/../agents/portfolio-surveyor.agent.md"

fail() {
  printf 'surveyor open PR links: FAIL — %s\n' "$*" >&2
  exit 1
}

QUERY=$(sed -n "/closedByPullRequestsReferences(includeClosedPrs:false,userLinkedOnly:false,first:1){totalCount}/s/^[[:space:]]*-f query='\(.*\)' \\\\$/\1/p" "$SURVEYOR")
FILTER=$(sed -n "/closedByPullRequestsReferences(includeClosedPrs:false,userLinkedOnly:false,first:1){totalCount}/{n;s/^[[:space:]]*--jq '\(.*\)'$/\1/p;}" "$SURVEYOR")
[ -n "$QUERY" ] && [ -n "$FILTER" ] || fail 'missing prescribed query or projection'

VALID='{"data":{"repository":{"issue":{"number":165,"closedByPullRequestsReferences":{"totalCount":0}}}}}'
for count in 0 1 3; do
  input=$(jq --argjson count "$count" '.data.repository.issue.closedByPullRequestsReferences.totalCount=$count' <<< "$VALID")
  actual=$(jq -c "$FILTER" <<< "$input") || fail "valid count $count rejected"
  [ "$actual" = "{\"number\":165,\"openLinkedPRs\":$count}" ] || fail "incorrect count: $actual"
done

# Counts describe the entire filtered connection, not the first page's node count.
# Nulls, malformed values, and partial GraphQL errors cannot turn into a zero.
for mutation in \
  'del(.data.repository.issue)' \
  '.data.repository.issue=null' \
  'del(.data.repository.issue.number)' \
  '.data.repository.issue.number=0' \
  '.data.repository.issue.number=1.5' \
  'del(.data.repository.issue.closedByPullRequestsReferences)' \
  '.data.repository.issue.closedByPullRequestsReferences=null' \
  'del(.data.repository.issue.closedByPullRequestsReferences.totalCount)' \
  '.data.repository.issue.closedByPullRequestsReferences.totalCount="0"' \
  '.data.repository.issue.closedByPullRequestsReferences.totalCount=-1' \
  '.data.repository.issue.closedByPullRequestsReferences.totalCount=0.5' \
  '.errors=[{"message":"partial failure"}]' \
  '{errors:[{message:"query failure"}]}'; do
  input=$(jq "$mutation" <<< "$VALID")
  if actual=$(jq -c "$FILTER" <<< "$input" 2>&1); then
    fail "malformed response became actionable: $mutation: $actual"
  fi
done

GH_TELEMETRY=0 "$HERE/forge-readonly-guard.sh" --command \
  "gh api graphql -F owner=devantler-tech -F name=agent-plugins -F number=165 -f query='$QUERY' --jq '$FILTER'" \
  >/dev/null || fail 'prescribed read denied by the forge guard'

echo 'surveyor open PR links: PASS (3 counts, 13 invalid responses, guard admission)'
