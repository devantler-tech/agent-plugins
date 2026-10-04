#!/usr/bin/env bash
# Hermetic contract tests for count-unresolved-review-threads.sh.
#
# A stub `gh` on PATH serves canned GraphQL pages, so no token or network is needed. The
# stub prints only the first page unless --paginate was passed, which is the observable
# difference the real CLI makes. Each safety property is paired with an ablated copy of the
# helper that must FAIL the same case, so a refactor that silently drops the property is
# caught here rather than by a survey that reports zero over an open finding.
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
COUNTER="$HERE/count-unresolved-review-threads.sh"
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/count-unresolved-review-threads.test.XXXXXX")
completed=0
# bash 3.2 can report a set -e abort inside an EXIT trap as exit 0, so require completion.
on_exit() {
  local status=$?
  rm -rf "$TEST_TMP"
  if [ "$completed" != 1 ] && [ "$status" = 0 ]; then exit 1; fi
}
trap on_exit EXIT

pass=0
fail=0

record_failure() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1" >&2
}

# page <total> <has-next> <cursor> <resolved-flags...> — one GraphQL page as gh prints it.
page() {
  local total=$1 next=$2 cursor=$3 nodes='' flag index=0
  shift 3
  for flag in "$@"; do
    index=$((index + 1))
    nodes="${nodes:+${nodes},}{\"id\":\"thread-${cursor}-${index}\",\"isResolved\":${flag}}"
  done
  printf '{"data":{"repository":{"nameWithOwner":"devantler-tech/monorepo","pullRequest":{"number":2436,"reviewThreads":{"totalCount":%s,"nodes":[%s],"pageInfo":{"hasNextPage":%s,"endCursor":"%s"}}}}}}\n' \
    "$total" "$nodes" "$next" "$cursor"
}

mkdir -p "$TEST_TMP/bin" "$TEST_TMP/pages"
# The stub refuses a call that did not disable telemetry or that asks anything other than
# the one GraphQL read, so an argument or environment regression fails every remote case.
cat >"$TEST_TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
dir="${STUB_PAGES:?}"
[ "${GH_TELEMETRY:-}" = 0 ] || exit 3
if [ "${CHECK_HOST:-}" = 1 ]; then [ "${GH_HOST:-}" = github.com ] || exit 3; fi
[ "$1" = api ] && [ "$2" = graphql ] || exit 3
case " $* " in *' -f owner=devantler-tech -f name=monorepo -F number=2436 '*) ;; *) exit 3 ;; esac
paginate=0
for a in "$@"; do [ "$a" = --paginate ] && paginate=1; done
if [ "$paginate" = 1 ]; then cat "$dir"/page-*; else cat "$dir/page-1"; fi
[ ! -e "$dir/fail" ]
STUB
chmod +x "$TEST_TMP/bin/gh"

# scenario <name>, then one page per stdin line.
scenario() {
  local d="$TEST_TMP/pages/$1" i=0 line
  mkdir -p "$d"
  while IFS= read -r line; do
    i=$((i + 1))
    printf '%s\n' "$line" >"$d/page-$i"
  done
}

# expect <label> <helper> <scenario> <want-status> <want-stdout>
expect() {
  local label=$1 tool=$2 s=$3 want_status=$4 want=$5 got status=0
  got=$(STUB_PAGES="$TEST_TMP/pages/$s" PATH="$TEST_TMP/bin:$PATH" \
    bash "$tool" --repo devantler-tech/monorepo --pr 2436 2>/dev/null) || status=$?
  if [ "$status" = "$want_status" ] && [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    record_failure "$label"
    printf '      want status %s and "%s", got status %s and "%s"\n' \
      "$want_status" "$want" "$status" "$got" >&2
  fi
}

page 0 false '' | scenario zero
page 1 false c1 false | scenario unresolved
page 2 false c1 true true | scenario resolved-only
# 103 threads: 100 resolved on page 1, three on page 2 of which one is unresolved.
{
  flags=()
  for _ in $(seq 1 100); do flags+=(true); done
  page 103 true c1 "${flags[@]}"
  page 103 false c2 true false true
} | scenario paginated
# A later page fails after the first one printed: the partial output must not count.
{
  flags=()
  for _ in $(seq 1 100); do flags+=(true); done
  page 103 true c1 "${flags[@]}"
} | scenario later-page-failed
: >"$TEST_TMP/pages/later-page-failed/fail"
printf '%s\n' '' | scenario empty
printf '%s\n' '{"errors":[{"message":"Could not resolve to a PullRequest"}],"data":{"repository":{"pullRequest":null}}}' |
  scenario missing-pr
page 2 false c1 true true | jq -c 'del(.data.repository.pullRequest.reviewThreads.nodes[1].isResolved)' | scenario missing-flag
printf '%s\n' '{"data":{"repository":{"pullRequest":{"reviewThreads":{"totalCount":"1","nodes":[{"isResolved":false}],"pageInfo":{"hasNextPage":false,"endCursor":"c1"}}}}}}' |
  scenario string-total
{
  page 2 true c1 true
  page 3 false c2 false
} | scenario inconsistent

expect 'zero-thread PR' "$COUNTER" zero 0 'unresolved=0 total=0'
expect 'one unresolved thread' "$COUNTER" unresolved 1 'unresolved=1 total=1'
expect 'resolved threads only' "$COUNTER" resolved-only 0 'unresolved=0 total=2'
expect '103 threads across two pages' "$COUNTER" paginated 1 'unresolved=1 total=103'
expect 'a later-page failure is UNKNOWN, not the first page zero' "$COUNTER" later-page-failed 2 'UNKNOWN read-failed'
expect 'an empty read is UNKNOWN' "$COUNTER" empty 2 'UNKNOWN read-failed'
expect 'a missing pull request is UNKNOWN' "$COUNTER" missing-pr 2 'UNKNOWN malformed'
expect 'a node without isResolved is UNKNOWN, never resolved' "$COUNTER" missing-flag 2 'UNKNOWN malformed'
expect 'a non-numeric total is UNKNOWN' "$COUNTER" string-total 2 'UNKNOWN malformed'
expect 'totals that change between pages are UNKNOWN' "$COUNTER" inconsistent 2 'UNKNOWN inconsistent'

# Counts alone cannot establish complete, unique, target-bound pagination.
page 1 true c1 true | scenario unfinished
page 1 false c1 true | jq -c 'del(.data.repository.pullRequest.reviewThreads.pageInfo)' | scenario no-page-info
page 1 false c1 true | jq -c '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage="false"' | scenario bad-page-info
{
  page 2 false c1 true
  page 2 false c2 true
} | scenario early-terminal
{
  page 2 true c1 true
  page 2 false c1 true | jq -c '.data.repository.pullRequest.reviewThreads.nodes[0].id="thread-c2-1"'
} | scenario repeated-cursor
page 2 false c1 true true | jq -c '.data.repository.pullRequest.reviewThreads.nodes[1].id=.data.repository.pullRequest.reviewThreads.nodes[0].id' | scenario repeated-thread
page 1 false c1 true | jq -c 'del(.data.repository.pullRequest.reviewThreads.nodes[0].id)' | scenario no-thread-id
page 1 false c1 true | jq -c '.data.repository.nameWithOwner="devantler-tech/agent-skills"' | scenario wrong-repo
page 1 false c1 true | jq -c '.data.repository.pullRequest.number=1' | scenario wrong-pr
page 1 false c1 true | jq -c '.data.repository.nameWithOwner="DEVANTLER-TECH/MONOREPO"' | scenario repo-alias
for s in unfinished no-page-info bad-page-info early-terminal repeated-cursor; do
  expect "$s cannot clear unresolved threads" "$COUNTER" "$s" 2 'UNKNOWN pagination'
done
for s in repeated-thread no-thread-id; do
  expect "$s cannot substitute for a complete unique inventory" "$COUNTER" "$s" 2 'UNKNOWN identity'
done
for s in wrong-repo wrong-pr; do
  expect "$s cannot count another target" "$COUNTER" "$s" 2 'UNKNOWN target'
done
expect 'repository casing aliases retain the same target' "$COUNTER" repo-alias 0 'unresolved=0 total=1'
page 3 false c1 true true | scenario truncated-terminal
expect 'a terminal page cannot hide missing nodes' "$COUNTER" truncated-terminal 2 'UNKNOWN truncated fetched=2 total=3'
CHECK_HOST=1 GH_HOST=enterprise.invalid expect 'an inherited host cannot retarget the collector' "$COUNTER" zero 0 'unresolved=0 total=0'

# A gh that fails outright, with no output at all.
mkdir -p "$TEST_TMP/pages/failed"
page 1 false c1 false >"$TEST_TMP/pages/failed/page-1"
: >"$TEST_TMP/pages/failed/fail"
expect 'a failed read is UNKNOWN, not zero' "$COUNTER" failed 2 'UNKNOWN read-failed'

# GraphQL partial data never overrides its error envelope, on any page.
for position in first later; do
  mkdir -p "$TEST_TMP/pages/graphql-errors-$position"
  total=0
  if [ "$position" = later ]; then total=1; page 1 true first true > "$TEST_TMP/pages/graphql-errors-$position/page-1"; fi
  page "$total" false last | jq '.errors=[{message:"Review thread field failed"}]' > "$TEST_TMP/pages/graphql-errors-$position/page-2"
  if [ "$position" = first ]; then mv "$TEST_TMP/pages/graphql-errors-$position/page-2" "$TEST_TMP/pages/graphql-errors-$position/page-1"; fi
  expect "$position-page GraphQL errors cannot clear threads" "$COUNTER" "graphql-errors-$position" 2 'UNKNOWN malformed'
done

# Ablation 1: without --paginate the helper sees 100 of 103, and the truncation check must
cp "$HERE/json-stream.lib.sh" "$TEST_TMP/json-stream.lib.sh"
# catch it rather than report the first page's zero.
sed 's/ --paginate//' "$COUNTER" >"$TEST_TMP/no-paginate.sh"
expect 'ablation: no --paginate is caught as unfinished pagination' "$TEST_TMP/no-paginate.sh" paginated 2 \
  'UNKNOWN pagination'
# Even without the count check, unfinished pagination remains independently unknown.
# shellcheck disable=SC2016 # a literal pattern for sed, not a shell expansion
sed 's/ --paginate//; s/"\$fetched" != "\$total"/"x" = "y"/' "$COUNTER" >"$TEST_TMP/no-guard.sh"
expect 'ablation: terminal-page validation still refuses incomplete reads' "$TEST_TMP/no-guard.sh" paginated 2 \
  'UNKNOWN pagination'

# Ablation 2: without the per-node boolean check, a node that lost its isResolved field drops
# out of the unresolved count unseen and the read turns into a clean zero.
# shellcheck disable=SC2016 # a literal pattern for sed, not a shell expansion
sed 's/or any(.nodes\[\]; (type != "object") or ((.isResolved | type) != "boolean"))//' \
  "$COUNTER" >"$TEST_TMP/no-node-check.sh"
if cmp -s "$COUNTER" "$TEST_TMP/no-node-check.sh"; then
  record_failure 'ablation 2 did not change the helper; its pattern is stale'
else
  expect 'ablation: no node check reads a malformed node as resolved' "$TEST_TMP/no-node-check.sh" \
    missing-flag 0 'unresolved=0 total=2'
fi

# Usage errors are UNKNOWN too, and never contact the forge.
for args in \
  'devantler-tech/monorepo 2436' \
  '--repo devantler-tech/monorepo' \
  '--pr 2436' \
  '--repo devantler-tech/monorepo --pr 0' \
  '--repo devantler-tech/monorepo --pr 1x' \
  '--repo devantler-tech/monorepo --pr 02436' \
  '--repo example.com/devantler-tech/monorepo --pr 2436' \
  '--repo devantler-tech/monorepo --repo devantler-tech/other --pr 2436' \
  '--repo devantler-tech/monorepo --pr 2436 --pr 1' \
  '--repo devantler-tech/monorepo --pr 2436 --input -' \
  '--repo devantler-tech/monorepo --pr'; do
  status=0
  # shellcheck disable=SC2086 # word-splitting the canned argument list is the point
  got=$(STUB_PAGES="$TEST_TMP/pages/unresolved" PATH="$TEST_TMP/bin:$PATH" \
    bash "$COUNTER" $args 2>/dev/null) || status=$?
  if [ "$status" = 2 ] && [ "$got" = 'UNKNOWN usage' ]; then
    pass=$((pass + 1))
  else
    record_failure "usage refused: $args (status $status, stdout \"$got\")"
  fi
done

# Missing tooling is UNKNOWN, never a count.
mkdir -p "$TEST_TMP/no-gh-bin"
for tool in jq bash sed; do ln -s "$(command -v "$tool")" "$TEST_TMP/no-gh-bin/$tool"; done
status=0
got=$(PATH="$TEST_TMP/no-gh-bin" "$TEST_TMP/no-gh-bin/bash" "$COUNTER" \
  --repo devantler-tech/monorepo --pr 2436 2>/dev/null) || status=$?
if [ "$status" = 2 ] && [ "$got" = 'UNKNOWN tool-unavailable' ]; then
  pass=$((pass + 1))
else
  record_failure "a missing gh must be UNKNOWN (status $status, stdout \"$got\")"
fi

completed=1
printf 'count-unresolved-review-threads: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
