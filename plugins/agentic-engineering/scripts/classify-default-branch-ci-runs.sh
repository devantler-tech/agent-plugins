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

  def run_identity:
    if .event == "dynamic" and ((.path // "") | startswith("dynamic/")) then
      ["managed", .workflow_id, ((.name // "") | sub("( - Update)? #[0-9]+$"; ""))]
    else
      ["workflow", .workflow_id]
    end;

  def red:
    .conclusion == "failure"
    or .conclusion == "timed_out"
    or .conclusion == "startup_failure";

  if length == 0 then error("empty input") else . end
  | [.[] | page_runs[]] as $runs
  | (if any($runs[]; (.event | type != "string") or (.event | length == 0))
     then error("run is missing its event discriminator")
     else $runs
     end) as $complete_runs
  | ["push", "schedule", "merge_group", "workflow_dispatch", "dynamic"] as $branch_events
  | ($complete_runs
      | map(select((.event as $event | $branch_events | index($event)) != null))) as $branch_runs
  | if any($branch_runs[];
      (.workflow_id | type != "number")
      or (.id | type != "number")
      or (.created_at | type != "string")
      or (.created_at | length == 0)
      or ((.run_started_at // null) != null
          and ((.run_started_at | type != "string") or (.run_started_at | length == 0)))
      or ((.run_attempt // null) != null and (.run_attempt | type != "number")))
    then error("branch run is missing workflow_id, id, or execution time")
    else $branch_runs
    end
  | group_by(run_identity)
  | map(
      sort_by([(.run_started_at // .created_at), (.run_attempt // 1), .id])
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
