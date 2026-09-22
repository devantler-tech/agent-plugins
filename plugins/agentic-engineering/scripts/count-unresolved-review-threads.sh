#!/usr/bin/env bash
# Count one pull request's unresolved review threads, or say UNKNOWN.
#
#   count-unresolved-review-threads.sh --repo OWNER/REPO --pr NUMBER
#
# Unresolved threads gate promotion and merge, yet no `gh pr view --json` field carries
# them, so every survey used to count them with an inline paginated GraphQL read. That count
# is silent when wrong: a failed read, a first-page-only read and a genuine zero all printed
# `0`, and a surveyor once reported `unresolved=0` while a Major finding was open. This
# helper makes the count one tested command whose only zero is a complete, successful read.
#
# It owns the paginated read in memory, the same way classify-default-branch-ci-runs.sh
# does: a later-page failure cannot be hidden by a consumer that already saw earlier pages,
# and the read-only surveyor never writes an intermediate file. Every thread counts,
# whatever its author and whether or not it is outdated, because an outdated unresolved
# thread still blocks a branch rule that requires conversation resolution.
#
# Stdout: exactly one line.
#   unresolved=<n> total=<t>    a complete read: every thread was fetched and parsed
#   UNKNOWN <reason>            usage | tool-unavailable | read-failed | malformed |
#                               inconsistent | truncated fetched=<f> total=<t>
#
# Exit status (the same split a consumer merge gate keys on, so swapping helpers cannot
# turn a nonzero count into a pass):
#   0  complete read, zero unresolved threads
#   1  complete read, at least one unresolved thread
#   2  UNKNOWN — never read this as zero
set -euo pipefail

unknown() {
  printf 'UNKNOWN %s\n' "$1"
  exit 2
}

usage() {
  echo 'usage: count-unresolved-review-threads.sh --repo OWNER/REPO --pr NUMBER' >&2
  unknown usage
}

repo=""
pr=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      if [ "$#" -lt 2 ] || [ -n "$repo" ]; then usage; fi
      repo=$2
      shift 2
      ;;
    --pr)
      if [ "$#" -lt 2 ] || [ -n "$pr" ]; then usage; fi
      pr=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage
[[ "$pr" =~ ^[1-9][0-9]*$ ]] || usage

command -v jq >/dev/null 2>&1 || unknown tool-unavailable
command -v gh >/dev/null 2>&1 || unknown tool-unavailable

# Default gh telemetry writes gh/device-id before the API result exists. The forge-readonly
# guard requires this in the process environment; argv cannot carry it (an env-prefixed
# command is denied).
export GH_TELEMETRY=0

# shellcheck disable=SC2016 # GraphQL variables, not shell expansions
query='query($owner:String!,$name:String!,$number:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      reviewThreads(first:100,after:$endCursor){
        totalCount
        nodes{isResolved}
        pageInfo{hasNextPage endCursor}
      }}}}'

# Capture before parsing: piped straight into jq, a failed read yields an empty stream that
# `jq -s` turns into a zero.
if ! pages=$(gh api graphql --paginate \
  -f owner="${repo%%/*}" \
  -f name="${repo#*/}" \
  -F number="$pr" \
  -f query="$query" 2>/dev/null); then
  unknown read-failed
fi
[ -n "$pages" ] || unknown read-failed

# Every page must carry a reviewThreads object with an integer totalCount and a node array
# whose every node has a boolean isResolved. A missing field is malformed, never "resolved":
# a node without isResolved would otherwise drop out of the unresolved count unseen.
# shellcheck disable=SC2016 # jq program; dollar-prefixed names belong to jq
if ! counts=$(printf '%s\n' "$pages" | jq -s -r '
  [.[] | .data.repository.pullRequest.reviewThreads] as $t
  | if ($t | length) == 0
      or any($t[];
          (type != "object")
          or ((.totalCount | type) != "number")
          or (.totalCount < 0)
          or (.totalCount != (.totalCount | floor))
          or ((.nodes | type) != "array")
          or any(.nodes[]; (type != "object") or ((.isResolved | type) != "boolean")))
    then error("malformed")
    else . end
  | if ([$t[].totalCount] | unique | length) != 1 then "inconsistent"
    else "\([$t[].nodes[]] | length) \($t[0].totalCount) \([$t[].nodes[] | select(.isResolved == false)] | length)"
    end
' 2>/dev/null); then
  unknown malformed
fi
[ "$counts" != inconsistent ] || unknown inconsistent

fetched=${counts%% *}
rest=${counts#* }
total=${rest%% *}
unresolved=${rest##* }

if [ "$fetched" != "$total" ]; then
  unknown "truncated fetched=${fetched} total=${total}"
fi

printf 'unresolved=%s total=%s\n' "$unresolved" "$total"
[ "$unresolved" -eq 0 ] || exit 1
