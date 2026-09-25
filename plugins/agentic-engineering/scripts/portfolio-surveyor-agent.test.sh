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
# shellcheck disable=SC2016 # Backticks are literal Markdown contract text.
for log_scope_fragment in \
  'Never read a workflow log body from this survey.' \
  '`--log-failed`, `--log` and `--job`' \
  '`repos/<owner>/<repo>/actions/runs/<run_id>/attempts/<run_attempt>/jobs`' \
  '["failure","timed_out","startup_failure"]' \
  '[.id,.check_run_url]' \
  '`repos/<owner>/<repo>/actions/jobs/<job_id>`' \
  '`repos/<owner>/<repo>/check-runs/<check_run_id>/annotations`' \
  'select(.annotation_level=="failure")' \
  '**with `--paginate`**' \
  'the orchestrator reads the log itself'; do
  grep -Fq "$log_scope_fragment" <<<"$CI_STEP" ||
    fail "default-branch CI must preserve the workflow-log scope contract: $log_scope_fragment"
done
# shellcheck disable=SC2016 # The asserted agent text contains a literal shell idiom.
grep -Fq 'Read the verdict from the helper'"'"'s native tool result, never by appending the guard-denied `; echo "EXIT=$?"` idiom.' \
  <<<"$CI_STEP" ||
  fail 'default-branch CI must prescribe the native tool result instead of denied shell exit capture'
grep -Fq '| observed native process status 0 and completely empty output | no red runs → that branch is **green** |' \
  <<<"$CI_STEP" ||
  fail 'green must require both observed native process status 0 and completely empty classifier output'
# shellcheck disable=SC2016 # Backticks belong to the asserted Markdown contract.
grep -Fq '| observed native process status 0 and **well-formed TSV rows** — exactly nine tab-separated fields in helper order: numeric `workflow_id`, red `conclusion` (`failure`, `timed_out`, or `startup_failure`), `html_url`, `name`, supported `event`, `path`, valid `created_at`, numeric `run_id`, positive numeric `run_attempt` | those are the **red runs** |' \
  <<<"$CI_STEP" ||
  fail 'the complete nine-field TSV predicate must map to the red verdict as one table row'
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

GH_TELEMETRY=0 "$GUARD" --command \
  "gh api repos/example/product/actions/runs/789/attempts/2/jobs --paginate --jq '.jobs[]|select(.conclusion as \$c|[\"failure\",\"timed_out\",\"startup_failure\"]|index(\$c))|[.id,.check_run_url]|@tsv'" \
  >/dev/null || fail 'the prescribed paginated attempt-to-job correlation read is not admitted by the forge guard'
GH_TELEMETRY=0 "$GUARD" --command \
  "gh api repos/example/product/actions/jobs/123 --jq '[.steps[]|select(.conclusion as \$c|[\"failure\",\"timed_out\",\"startup_failure\"]|index(\$c))|.name]'" \
  >/dev/null || fail 'the prescribed workflow-job read is not admitted by the forge guard'
GH_TELEMETRY=0 "$GUARD" --command \
  "gh api repos/example/product/check-runs/456/annotations --paginate --jq '.[]|select(.annotation_level==\"failure\")|[.annotation_level,.path,.message]|@tsv'" \
  >/dev/null || fail 'the prescribed paginated annotation read is not admitted by the forge guard'

# Pentad field (b) is the bundled counter's verdict, never an inline count. Pin the prescribed
# invocation and prove the guard admits exactly it — resolved to the installed sibling — while a
# piped form, which would replace the helper's exit status with a filter's, stays denied.
THREAD_COUNTER_FORM='<installed plugin>/scripts/count-unresolved-review-threads.sh --repo OWNER/REPO --pr NUMBER'
grep -Fq "\`$THREAD_COUNTER_FORM\`" "$SURVEYOR" ||
  fail 'pentad field (b) must prescribe the bundled unresolved-thread counter in its flag form'
# A quoted pattern containing `/` is mis-split by bash 3.2 (macOS), so hold it in a variable.
INSTALLED_SCRIPTS='<installed plugin>/scripts'
THREAD_COUNTER_COMMAND=${THREAD_COUNTER_FORM/"$INSTALLED_SCRIPTS"/$HERE}
THREAD_COUNTER_COMMAND=${THREAD_COUNTER_COMMAND/OWNER\/REPO/example/product}
THREAD_COUNTER_COMMAND=${THREAD_COUNTER_COMMAND/NUMBER/7}
GH_TELEMETRY=0 "$GUARD" --command "$THREAD_COUNTER_COMMAND" >/dev/null ||
  fail 'the prescribed unresolved-thread counter is not admitted by the forge guard'
if GH_TELEMETRY=0 "$GUARD" --command "$THREAD_COUNTER_COMMAND | cat" >/dev/null; then
  fail 'the unresolved-thread counter was admitted inside a pipeline'
fi

ISSUE_AGGREGATION_COMMAND=$(grep -F \
  'gh api graphql --paginate --slurp -f owner=<owner> -f name=<repo>' \
  "$SURVEYOR" || true)
[ -n "$ISSUE_AGGREGATION_COMMAND" ] ||
  fail 'could not extract the prescribed issue aggregation command'
grep -Fq " | jq -ce '" <<<"$ISSUE_AGGREGATION_COMMAND" ||
  fail 'the paginated slurp must be reduced by exit-status-enforcing jq, not unsupported gh --jq'
ISSUE_AGGREGATION_FILTER=$(printf '%s\n' "$ISSUE_AGGREGATION_COMMAND" |
  sed "s/^.* | jq -ce '\(.*\)'$/\1/")
[ -n "$ISSUE_AGGREGATION_FILTER" ] ||
  fail 'could not extract the prescribed issue aggregation jq filter'

ISSUE_PAGES='[{"data":{"repository":{"issues":{"totalCount":4,"nodes":[{"number":1,"issueType":{"name":"Bug"}},{"number":2,"issueType":null}]}}}},{"data":{"repository":{"issues":{"totalCount":4,"nodes":[{"number":3,"issueType":{"name":"Task"}},{"number":4,"issueType":{"name":"untyped"}}]}}}}]'
ISSUE_SUMMARY=$(jq -c "$ISSUE_AGGREGATION_FILTER" <<<"$ISSUE_PAGES") ||
  fail 'the prescribed issue aggregation rejected valid issue rows'
[ "$ISSUE_SUMMARY" = '{"total":4,"types":[{"type":null,"count":1},{"type":"Bug","count":1},{"type":"Task","count":1},{"type":"untyped","count":1}]}' ] ||
  fail "the prescribed issue aggregation returned the wrong summary: $ISSUE_SUMMARY"
if (set +o pipefail; { false; } | jq -ce "$ISSUE_AGGREGATION_FILTER" >/dev/null 2>&1); then
  fail 'an upstream failure with no response pages was masked as a successful empty summary'
fi
if jq -c "$ISSUE_AGGREGATION_FILTER" \
  <<<'[{"data":{"repository":{"issues":{"totalCount":1,"nodes":[{"number":0,"issueType":{"name":"Bug"}}]}}}}]' >/dev/null 2>&1; then
  fail 'the prescribed issue aggregation accepted a malformed issue row'
fi
if jq -c "$ISSUE_AGGREGATION_FILTER" \
  <<<'[{"data":{"repository":{"issues":{"totalCount":2,"nodes":[{"number":1,"issueType":{"name":"Bug"}}]}}}}]' >/dev/null 2>&1; then
  fail 'the prescribed issue aggregation accepted a capped or partial issue census'
fi
# An absent issueType key reads as null in jq, so without a has() check a malformed row would be
# counted as untyped instead of failing closed.
if jq -c "$ISSUE_AGGREGATION_FILTER" \
  <<<'[{"data":{"repository":{"issues":{"totalCount":1,"nodes":[{"number":1}]}}}}]' >/dev/null 2>&1; then
  fail 'the prescribed issue aggregation counted a row with no issueType key as untyped'
fi
if jq -c "$ISSUE_AGGREGATION_FILTER" \
  <<<'[{"data":{"repository":{"issues":{"totalCount":1,"nodes":[{"number":1,"issueType":"Bug"}]}}}}]' >/dev/null 2>&1; then
  fail 'the prescribed issue aggregation accepted an issueType that is not an object'
fi
if jq -c "$ISSUE_AGGREGATION_FILTER" \
  <<<'[{"data":{"repository":{"issues":{"totalCount":1,"nodes":[7]}}}}]' >/dev/null 2>&1; then
  fail 'the prescribed issue aggregation accepted an issue row that is not an object'
fi

GUARDED_ISSUE_AGGREGATION=${ISSUE_AGGREGATION_COMMAND/'<owner>'/example}
GUARDED_ISSUE_AGGREGATION=${GUARDED_ISSUE_AGGREGATION/'<repo>'/product}
GH_TELEMETRY=0 "$GUARD" --command "$GUARDED_ISSUE_AGGREGATION" >/dev/null ||
  fail 'the prescribed issue aggregation is not admitted by the forge guard'

AWK_DENIAL=$(GH_TELEMETRY=0 "$GUARD" --command \
  "gh issue list --repo example/product --state open --limit 1000 --json number,issueType --jq '.[]|[.number,(.issueType.name // \"untyped\")]|@tsv' | awk -F'\\t' '{count[\$2]++} END{for(type in count) print type,count[type]}'" || true)
[ "$AWK_DENIAL" = "deny: 'awk' is not on the read-only allowlist" ] ||
  fail "the observed awk aggregation did not fail for the intended guard reason: $AWK_DENIAL"

DIGEST_RULES=$(sed -n '/^### Digest rules$/,$p' "$SURVEYOR" | tr '\n' ' ' | tr -s '[:space:]' ' ')
[ -n "$DIGEST_RULES" ] || fail 'could not extract the digest rules section'
# shellcheck disable=SC2016 # Backticks are literal Markdown contract text.
for identifier_fragment in \
  '**Copy identifiers from what you read; never construct them.**' \
  'reproduced from the `headRefName` or `headRefOid` you read for that PR' \
  'When you did not read it, write `unknown`.' \
  'Never build a branch name from the consumer'"'"'s naming convention'; do
  grep -Fq "$identifier_fragment" <<<"$DIGEST_RULES" ||
    fail "digest rules must forbid constructed identifiers: $identifier_fragment"
done

# An inline review comment carries no disclosure of its own — a review round puts it on the review
# body — so classifying it by its own body reads the engineer's self-review as maintainer direction
# (devantler-tech/monorepo#2835). Pin parent-review attribution and its one-way asymmetry inside 3f.
MAINTAINER_COMMENTS=$(sed -n \
  '/^### 3f\. Candidate maintainer comments/,/^### 4\. CI red on the default branch/p' \
  "$SURVEYOR" | tr '\n' ' ' | tr -s '[:space:]' ' ')
[ -n "$MAINTAINER_COMMENTS" ] || fail 'could not extract the candidate maintainer comments step'
# shellcheck disable=SC2016 # Backticks are literal Markdown contract text.
for parent_review_fragment in \
  'Pull comments, review-thread replies, and the reviews those replies belong to.' \
  '**An inline review comment is attributed by its parent review, not by its own body.**' \
  'names its parent in `pull_request_review_id`' \
  'when that review is by the same login and its body carries the structural disclosure prefix' \
  'An absent or undisclosed parent review leaves the comment to the other checks in this list' \
  'this can only move a comment from maintainer to agent, never the reverse.'; do
  grep -Fq "$parent_review_fragment" <<<"$MAINTAINER_COMMENTS" ||
    fail "candidate maintainer comments must attribute inline comments by their parent review: $parent_review_fragment"
done

printf 'portfolio-surveyor agent contract: PASS\n'
