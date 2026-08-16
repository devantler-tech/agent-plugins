#!/usr/bin/env bash
# Fetch and classify the health of one GitHub repository default-branch head.
#
# Remote mode owns pagination in memory so an API failure can never be hidden by a successful
# consumer and the read-only surveyor never writes a response file:
#   classify-default-branch-ci-runs.sh --repo OWNER/REPO --branch BRANCH --head-sha FULL_SHA
#
# Fixture/offline mode accepts a flat run array, raw page-envelope stream, or --slurp envelope array:
#   classify-default-branch-ci-runs.sh --input PATH
#
# Stdout: one TSV line per current red identity —
#   workflow_id conclusion html_url name event path created_at run_id
# Exit 0 after a complete, valid classification; exit 2 on usage, producer, or payload failure.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  classify-default-branch-ci-runs.sh --repo OWNER/REPO --branch BRANCH --head-sha FULL_SHA
  classify-default-branch-ci-runs.sh --input PATH
EOF
  exit 2
}

repo=""
branch=""
head_sha=""
input_path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || usage
      repo=$2
      shift 2
      ;;
    --branch)
      [ "$#" -ge 2 ] || usage
      branch=$2
      shift 2
      ;;
    --head-sha)
      [ "$#" -ge 2 ] || usage
      head_sha=$2
      shift 2
      ;;
    --input)
      [ "$#" -ge 2 ] || usage
      input_path=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  echo "classify-default-branch-ci-runs: jq is required" >&2
  exit 2
}

payload_path=""
payload=""

if [ -n "$input_path" ]; then
  if [ -n "$repo" ] || [ -n "$branch" ] || [ -n "$head_sha" ]; then
    usage
  fi
  [ -r "$input_path" ] || {
    echo "classify-default-branch-ci-runs: input is not readable: $input_path" >&2
    exit 2
  }
  payload_path=$input_path
else
  if [ -z "$repo" ] || [ -z "$branch" ] || [ -z "$head_sha" ]; then
    usage
  fi
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage
  [[ "$head_sha" =~ ^[0-9a-fA-F]{40}$ ]] || usage
  command -v gh >/dev/null 2>&1 || {
    echo "classify-default-branch-ci-runs: gh is required in remote mode" >&2
    exit 2
  }

  if ! payload=$(gh api --paginate --slurp --method GET "repos/${repo}/actions/runs" \
    -f head_sha="$head_sha" \
    -f branch="$branch" \
    -F per_page=100); then
    echo "classify-default-branch-ci-runs: GitHub Actions pagination failed; health is unknown" >&2
    exit 2
  fi
fi

# shellcheck disable=SC2016  # jq program; dollar-prefixed names belong to jq
jq_filter='
  def page_runs:
    if type == "object" and has("workflow_runs") and (.workflow_runs | type == "array") then
      .workflow_runs
    elif type == "array" then
      if length == 0 then
        []
      elif all(.[]; type == "object"
                       and has("workflow_runs")
                       and (.workflow_runs | type == "array")) then
        [.[] | .workflow_runs[]]
      elif all(.[]; type == "object" and (has("workflow_runs") | not)) then
        .
      else
        error("invalid runs page collection")
      end
    else
      error("invalid runs payload")
    end;

  def page_envelopes:
    if type == "object" and has("workflow_runs") and (.workflow_runs | type == "array") then
      [.]
    elif type == "array" then
      if length == 0 then
        []
      elif all(.[]; type == "object"
                       and has("workflow_runs")
                       and (.workflow_runs | type == "array")) then
        .
      elif all(.[]; type == "object" and (has("workflow_runs") | not)) then
        []
      else
        error("invalid runs page collection")
      end
    else
      error("invalid runs payload")
    end;

  def run_identity:
    if .event == "dynamic" then
      ["managed", .workflow_id, (.name | sub("( - Update)? #[0-9]+$"; ""))]
    else
      ["workflow", .workflow_id]
    end;

  def red:
    .conclusion == "failure"
    or .conclusion == "timed_out"
    or .conclusion == "startup_failure";

  def valid_github_timestamp:
    . as $timestamp
    | type == "string"
      and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
      and (try ((fromdateiso8601 | strftime("%Y-%m-%dT%H:%M:%SZ")) == $timestamp)
           catch false);

  if length == 0 then error("empty input") else . end
  | [.[] | page_envelopes[]] as $envelopes
  | [.[] | page_runs[]] as $runs
  | (if ($envelopes | length) == 0 then
       $runs
     elif any($envelopes[];
       (.total_count | type != "number" or . < 0 or floor != .)) then
       error("runs page is missing a valid total_count")
     elif ($envelopes | map(.total_count) | unique | length) != 1 then
       error("runs pages disagree on total_count")
     elif ($runs | length) != $envelopes[0].total_count then
       error("filtered runs result is incomplete or capped")
     else
       $runs
     end) as $counted_runs
  | (if any($counted_runs[]; (.event | type != "string") or (.event | length == 0))
     then error("run is missing its event discriminator")
     else $counted_runs
     end) as $complete_runs
  | (if any($complete_runs[];
       .event == "dynamic"
       and ((.path | type != "string")
            or ((.path | startswith("dynamic/")) | not)
            or (.name | type != "string")
            or (.name | length == 0)))
     then error("dynamic run is missing its managed identity")
     else $complete_runs
     end) as $identified_runs
  | ["push", "schedule", "merge_group", "workflow_dispatch", "dynamic"] as $branch_events
  | ($identified_runs
      | map(select((.event as $event | $branch_events | index($event)) != null))) as $branch_runs
  | if any($branch_runs[];
      (.workflow_id | type != "number")
      or (.id | type != "number")
      or ((.created_at | valid_github_timestamp) | not)
      or ((.run_started_at // null) != null
          and ((.run_started_at | valid_github_timestamp) | not))
      or ((.run_attempt // null) != null and (.run_attempt | type != "number")))
    then error("branch run is missing workflow_id, id, or execution time")
    else $branch_runs
    end
  | group_by(run_identity)
  | map(
      sort_by([(.run_started_at // .created_at), .id, (.run_attempt // 1)])
      | map(select(.conclusion == "success" or red))
      | last
    )
  | map(select(. != null and red))
  | sort_by([.workflow_id, (.name // "")])
  | .[]
  | [.workflow_id, .conclusion, (.html_url // ""), (.name // ""),
     (.event // ""), (.path // ""), .created_at, .id]
  | @tsv
' 

classification=""
if [ -n "$payload_path" ]; then
  if ! classification=$(jq -rs "$jq_filter" "$payload_path"); then
    echo "classify-default-branch-ci-runs: malformed or incomplete runs payload; health is unknown" >&2
    exit 2
  fi
elif ! classification=$(printf '%s\n' "$payload" | jq -rs "$jq_filter"); then
  echo "classify-default-branch-ci-runs: malformed or incomplete runs payload; health is unknown" >&2
  exit 2
fi

if [ -n "$classification" ]; then
  printf '%s\n' "$classification"
fi
