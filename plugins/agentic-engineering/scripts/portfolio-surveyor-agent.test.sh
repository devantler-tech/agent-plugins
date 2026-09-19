#!/usr/bin/env bash
#
# Contract test for the portfolio-surveyor agent definition.
#
# GitHub's issueDependenciesSummary exposes open and total blocker counts
# without fetching blocker nodes. Pin that boundary-safe shape and exercise its
# fail-closed projection before the surveyor can classify a candidate.
#
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SURVEYOR="$HERE/../agents/portfolio-surveyor.agent.md"
GUARD="$HERE/forge-readonly-guard.sh"

fail() {
  printf 'portfolio-surveyor agent contract: FAIL — %s\n' "$*" >&2
  exit 1
}

grep -Fq 'issueDependenciesSummary{blockedBy totalBlockedBy}' "$SURVEYOR" ||
  fail 'dependency reads must request the boundary-safe open and total blocker summary'
if grep -Fq -- '--json issueType,blockedBy,assignees' "$SURVEYOR"; then
  fail 'dependency reads must not enumerate blocker nodes through gh issue view'
fi

CI_STEP=$(sed -n \
  '/^### 4\. CI red on the default branch/,/^### 5\. Triage, stale, and advance signals/p' \
  "$SURVEYOR" | tr '\n' ' ' | tr -s '[:space:]' ' ')
[ -n "$CI_STEP" ] || fail 'could not extract the default-branch CI step'
# shellcheck disable=SC2016 # The asserted agent text contains a literal shell idiom.
grep -Fq 'Read the verdict from the helper'"'"'s native tool result, never by appending the guard-denied `; echo "EXIT=$?"` idiom.' \
  <<<"$CI_STEP" ||
  fail 'default-branch CI must prescribe the native tool result instead of denied shell exit capture'
grep -Fq '| observed native process status 0 and completely empty output | no red runs → that branch is **green** |' \
  <<<"$CI_STEP" ||
  fail 'green must require both observed native process status 0 and completely empty classifier output'
# shellcheck disable=SC2016 # Backticks belong to the asserted Markdown contract.
grep -Fq '| observed native process status 0 and **well-formed TSV rows** — exactly eight tab-separated fields in helper order: numeric `workflow_id`, red `conclusion` (`failure`, `timed_out`, or `startup_failure`), `html_url`, `name`, supported `event`, `path`, valid `created_at`, numeric `run_id` | those are the **red runs** |' \
  <<<"$CI_STEP" ||
  fail 'the complete eight-field TSV predicate must map to the red verdict as one table row'
# shellcheck disable=SC2016 # Backticks belong to the asserted Markdown contract.
grep -Fq '| any nonzero or unavailable native process status; or any other output, including mixed valid and malformed rows | the helper FAILED → **`QUERY-UNKNOWN`**; never `nothing_on_fire: true` |' \
  <<<"$CI_STEP" ||
  fail 'nonzero or unavailable status and malformed or mixed output must fail closed as QUERY-UNKNOWN'

JQ_FILTER=$(sed -n \
  "/issueDependenciesSummary{blockedBy totalBlockedBy}/{n;s/^[[:space:]]*--jq '\\(.*\\)'$/\\1/p;}" \
  "$SURVEYOR")
[ -n "$JQ_FILTER" ] || fail 'could not extract the prescribed dependency jq filter'

expect_output() {
  local label=$1 input=$2 expected=$3 actual
  actual=$(jq -c "$JQ_FILTER" <<<"$input") ||
    fail "$label: valid dependency summary was rejected"
  [ "$actual" = "$expected" ] ||
    fail "$label: expected $expected, got $actual"
}

expect_unknown() {
  local label=$1 input=$2 output
  if output=$(jq -c "$JQ_FILTER" <<<"$input" 2>&1); then
    fail "$label: malformed dependency summary produced actionable output: $output"
  fi
}

expect_output 'open and closed blockers' \
  '{"data":{"repository":{"issue":{"number":3196,"issueDependenciesSummary":{"blockedBy":2,"totalBlockedBy":3}}}}}' \
  '{"number":3196,"openBlockedBy":2,"totalBlockedBy":3}'
expect_output 'closed blockers only' \
  '{"data":{"repository":{"issue":{"number":3261,"issueDependenciesSummary":{"blockedBy":0,"totalBlockedBy":1}}}}}' \
  '{"number":3261,"openBlockedBy":0,"totalBlockedBy":1}'
expect_output 'no blockers' \
  '{"data":{"repository":{"issue":{"number":5948,"issueDependenciesSummary":{"blockedBy":0,"totalBlockedBy":0}}}}}' \
  '{"number":5948,"openBlockedBy":0,"totalBlockedBy":0}'

expect_unknown 'missing issue' \
  '{"data":{"repository":{"issue":null}}}'
expect_unknown 'missing summary' \
  '{"data":{"repository":{"issue":{"number":3196}}}}'
expect_unknown 'null summary' \
  '{"data":{"repository":{"issue":{"number":3196,"issueDependenciesSummary":null}}}}'
expect_unknown 'wrong-shaped open count' \
  '{"data":{"repository":{"issue":{"number":3196,"issueDependenciesSummary":{"blockedBy":"2","totalBlockedBy":3}}}}}'
expect_unknown 'open count exceeds total' \
  '{"data":{"repository":{"issue":{"number":3196,"issueDependenciesSummary":{"blockedBy":2,"totalBlockedBy":1}}}}}'

# shellcheck disable=SC2016 # GraphQL variables are literal, not shell expansions.
GRAPHQL_QUERY='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){number issueDependenciesSummary{blockedBy totalBlockedBy}}}}'
GH_TELEMETRY=0 "$GUARD" --command \
  "gh api graphql -F owner=devantler-tech -F name=platform -F number=3196 -f query='$GRAPHQL_QUERY' --jq '$JQ_FILTER'" \
  >/dev/null || fail 'the prescribed dependency read is not admitted by the forge guard'

printf 'portfolio-surveyor agent contract: PASS\n'
