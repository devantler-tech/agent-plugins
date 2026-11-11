#!/usr/bin/env bash
# Fetch and classify the health of one GitHub repository default-branch head.
#
# Remote mode owns pagination in memory so an API failure can never be hidden by a successful
# consumer and the read-only surveyor never writes a response file:
#   classify-default-branch-ci-runs.sh --repo OWNER/REPO --branch BRANCH --head-sha FULL_SHA
#
# Remote mode also reads scheduled runs that are no longer on the current head. A scheduled
# workflow runs against whatever head the branch had at its cron time, so the next merge would
# otherwise hide its failure. Three complete reads list the branch's failed, timed-out and
# startup-failed scheduled runs of the last SCHEDULE_WINDOW_DAYS days; for each workflow found
# there, one first-page read fetches its newest successful scheduled run. Those runs join the
# current-head runs, so a scheduled workflow stays red until a later run of it succeeds.
# Cost per repository: the head pages + 3 + one per workflow with a red scheduled run.
# Blind spots: a scheduled workflow whose latest red run is older than the window, and
# non-push events other than schedule (workflow_dispatch, dynamic), which keep current-head
# semantics.
#
# Fixture/offline mode accepts a flat run array, raw page-envelope stream, or --slurp envelope array:
#   classify-default-branch-ci-runs.sh --input PATH
# Offline mode classifies only the runs it is given; it reads no scheduled-run evidence.
#
# Stdout: one TSV line per current red identity —
#   workflow_id conclusion html_url name event path created_at run_id run_attempt
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
      if [ "$#" -lt 2 ] || [ -n "$repo" ] || [ -z "$2" ]; then usage; fi
      repo=$2
      shift 2
      ;;
    --branch)
      if [ "$#" -lt 2 ] || [ -n "$branch" ] || [ -z "$2" ]; then usage; fi
      branch=$2
      shift 2
      ;;
    --head-sha)
      if [ "$#" -lt 2 ] || [ -n "$head_sha" ] || [ -z "$2" ]; then usage; fi
      head_sha=$2
      shift 2
      ;;
    --input)
      if [ "$#" -lt 2 ] || [ -n "$input_path" ] || [ -z "$2" ]; then usage; fi
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

observer_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || exit 2
# shellcheck source=plugins/agentic-engineering/scripts/json-stream.lib.sh
. "$observer_dir/json-stream.lib.sh" || exit 2
payload_path=""
payload=""
schedule_runs='[]'
readonly SCHEDULE_WINDOW_DAYS=31

# shellcheck disable=SC2016  # jq program; dollar-prefixed names belong to jq
jq_defs='
  def identifier: type == "number" and isfinite and . >= 1
    and . <= 9007199254740991 and floor == .;

  def valid_github_timestamp:
    . as $timestamp
    | type == "string"
      and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
      and (try ((fromdateiso8601 | strftime("%Y-%m-%dT%H:%M:%SZ")) == $timestamp)
           catch false);

  def valid_run_shape:
    type == "object"
    and (.workflow_id | identifier)
    and (.id | identifier)
    and (.run_attempt | identifier)
    and (.created_at | valid_github_timestamp)
    and ((.run_started_at // null) == null or (.run_started_at | valid_github_timestamp));

  # Keep only the fields the classifier reads, so evidence stays small on argv.
  def evidence_record:
    {id, run_attempt, workflow_id, event, status, conclusion, created_at,
     run_started_at, html_url, name, path, head_branch, head_sha};

  # A complete paginated read: every page is an envelope, all pages agree on total_count,
  # and together they hold exactly that many runs. A capped result never satisfies this.
  def complete_envelope_runs:
    if length == 0 then error("empty scheduled runs input") else . end
    | [.[] | if type == "object" then . elif type == "array" then .[]
             else error("invalid scheduled runs payload") end]
    | if length == 0 then error("scheduled runs result requires page envelopes")
      elif any(.[]; type != "object" or (has("workflow_runs") | not)
                    or (.workflow_runs | type != "array")) then
        error("invalid scheduled runs page")
      elif any(.[]; .total_count | type != "number" or . < 0 or floor != .) then
        error("scheduled runs page is missing a valid total_count")
      elif (map(.total_count) | unique | length) != 1 then
        error("scheduled runs pages disagree on total_count")
      elif ([.[].workflow_runs[]] | length) != .[0].total_count then
        error("scheduled runs result is incomplete or capped")
      else [.[].workflow_runs[]] end;
'

# Input: every page of one red-conclusion scheduled read. Output: its validated runs.
# shellcheck disable=SC2016  # jq program; dollar-prefixed names belong to jq
red_schedule_filter='
  complete_envelope_runs
  | if any(.[]; (valid_run_shape | not)
          or .event != "schedule"
          or .head_branch != $expected_branch
          or .status != "completed"
          or .conclusion != $expected_conclusion
          or ((.created_at | fromdateiso8601) < ($since | fromdateiso8601)))
    then error("scheduled red run does not match the requested branch, conclusion or window")
    elif (map([.id, .run_attempt]) | unique | length) != length then
      error("duplicate scheduled run identity")
    else map(evidence_record) end
'

# Input: the first page of one workflow newest successful scheduled runs (one run at most).
# shellcheck disable=SC2016  # jq program; dollar-prefixed names belong to jq
success_schedule_filter='
  if length != 1 or (.[0] | type != "object")
     or (.[0] | has("workflow_runs") | not) or (.[0].workflow_runs | type != "array")
     or (.[0].total_count | type != "number" or . < 0 or floor != .)
  then error("invalid newest scheduled success page")
  else .[0] end
  | if (.workflow_runs | length) != ([.total_count, 1] | min) then
      error("newest scheduled success page is incomplete")
    else .workflow_runs end
  | if any(.[]; (valid_run_shape | not)
          or .workflow_id != $expected_workflow_id
          or .event != "schedule"
          or .head_branch != $expected_branch
          or .status != "completed"
          or .conclusion != "success")
    then error("newest scheduled success does not match the requested workflow")
    else map(evidence_record) end
'

# Read one GitHub API result into memory, refusing undecodable or ambiguous bytes.
retained_read() {
  local raw
  raw=$(gh api "$@" | json_stream_retain_raw) || return 2
  printf '%s\n' "$raw" | json_stream_unique || return 2
  printf '%s\n' "$raw"
}

collect_schedule_evidence() {
  local since conclusion page found reds='[]' successes='[]' workflow_ids workflow_id
  since=$(jq -nr --argjson days "$SCHEDULE_WINDOW_DAYS" 'now | floor - ($days * 86400) | todate') ||
    return 2
  for conclusion in failure timed_out startup_failure; do
    page=$(retained_read --paginate --slurp --method GET "repos/${repo}/actions/runs" \
      -f branch="$branch" \
      -f event=schedule \
      -f status="$conclusion" \
      -f created=">=$since" \
      -F per_page=100) || return 2
    found=$(printf '%s\n' "$page" | jq -cs \
      --arg expected_branch "$branch" \
      --arg expected_conclusion "$conclusion" \
      --arg since "$since" \
      "$jq_defs $red_schedule_filter") || return 2
    reds=$(jq -cn --argjson a "$reds" --argjson b "$found" '$a + $b') || return 2
  done
  workflow_ids=$(jq -rn --argjson runs "$reds" '$runs | map(.workflow_id) | unique | .[]') ||
    return 2
  while IFS= read -r workflow_id; do
    [ -n "$workflow_id" ] || continue
    [[ "$workflow_id" =~ ^[1-9][0-9]*$ ]] || return 2
    page=$(retained_read --method GET "repos/${repo}/actions/workflows/${workflow_id}/runs" \
      -f branch="$branch" \
      -f event=schedule \
      -f status=success \
      -F per_page=1) || return 2
    found=$(printf '%s\n' "$page" | jq -cs \
      --arg expected_branch "$branch" \
      --argjson expected_workflow_id "$workflow_id" \
      "$jq_defs $success_schedule_filter") || return 2
    successes=$(jq -cn --argjson a "$successes" --argjson b "$found" '$a + $b') || return 2
  done <<<"$workflow_ids"
  jq -cn --argjson a "$reds" --argjson b "$successes" '$a + $b'
}

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
  head_sha=$(printf '%s' "$head_sha" | tr 'A-F' 'a-f')
  command -v gh >/dev/null 2>&1 || {
    echo "classify-default-branch-ci-runs: gh is required in remote mode" >&2
    exit 2
  }
  # Default gh telemetry writes gh/device-id before the API result exists.
  # The forge-readonly guard requires this in the process environment; argv
  # cannot carry it (an env-prefixed command is denied).
  export GH_TELEMETRY=0
  export GH_HOST=github.com

  if ! payload=$(gh api --paginate --slurp --method GET "repos/${repo}/actions/runs" \
    -f head_sha="$head_sha" \
    -f branch="$branch" \
    -F per_page=100 | json_stream_retain_raw); then
    echo "classify-default-branch-ci-runs: GitHub Actions pagination failed; health is unknown" >&2
    exit 2
  fi
  if ! schedule_runs=$(collect_schedule_evidence); then
    echo "classify-default-branch-ci-runs: scheduled-run evidence is incomplete or malformed; health is unknown" >&2
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

  def valid_outcome:
    has("conclusion") and
    (if .conclusion == null then
       .status as $status | ["queued","in_progress","requested","waiting","pending"] | index($status) != null
     else
       .conclusion as $conclusion |
       ["success","failure","timed_out","startup_failure","cancelled","neutral","skipped","stale","action_required"]
       | index($conclusion) != null
     end)
    and (if has("status") then
      (if .conclusion == null then .status != "completed" else .status == "completed" end)
      else true end);

  if length == 0 then error("empty input") else . end
  | [.[] | page_envelopes[]] as $envelopes
  | [.[] | page_runs[]] as $runs
  | if $expected_head_sha != "" and ($envelopes | length) == 0 then
      error("remote runs result requires page envelopes")
    else . end
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
  | (if $expected_head_sha != "" and any($counted_runs[];
       .head_sha != $expected_head_sha or .head_branch != $expected_branch)
     then error("filtered runs include a different branch head")
     else $counted_runs
     end) as $head_runs
  | (if any($head_runs[]; (.event | type != "string") or (.event | length == 0))
     then error("run is missing its event discriminator")
     else $head_runs
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
      ((.workflow_id | identifier) | not)
      or ((.id | identifier) | not)
      or ((.created_at | valid_github_timestamp) | not)
      or ((.run_started_at // null) != null
          and ((.run_started_at | valid_github_timestamp) | not))
      or ((.run_attempt | identifier) | not))
    then error("branch run is missing workflow_id, id, run_attempt, or execution time")
    else $branch_runs
    end
  | if (map([.id,.run_attempt]) | unique | length) != length then
      error("duplicate workflow run identity")
    elif any(.[]; (valid_outcome | not)) then
      error("invalid workflow run outcome")
    else . end
  # Scheduled runs off the current head join here. A run seen by both reads must agree.
  | (. + $schedule_runs)
  | group_by([.id, .run_attempt])
  | map(if (map([.status, .conclusion]) | unique | length) != 1 then
          error("contradictory observations of one workflow run attempt")
        else .[0] end)
  | group_by(run_identity)
  | map(
      sort_by([(.run_started_at // .created_at), .id, .run_attempt])
      | map(select(.conclusion == "success" or red))
      | last
    )
  | map(select(. != null and red))
  | sort_by([.workflow_id, (.name // "")])
  | .[]
  | [.workflow_id, .conclusion, (.html_url // ""), (.name // ""),
     (.event // ""), (.path // ""), .created_at, .id, .run_attempt]
  | @tsv
' 

classification=""
if [ -n "$payload_path" ]; then
  # PATH names a file; cat's special '-' operand must never substitute stdin.
  [[ $payload_path == /* ]] || payload_path="./$payload_path"
  payload=$(cat -- "$payload_path" | json_stream_retain_raw) || exit 2
  payload_path=""
fi
if ! printf '%s\n' "$payload" | json_stream_unique; then
  echo 'classify-default-branch-ci-runs: ambiguous or incomplete raw observation; health is unknown' >&2
  exit 2
fi
if ! classification=$(printf '%s\n' "$payload" | jq -rs \
  --arg expected_head_sha "$head_sha" \
  --arg expected_branch "$branch" \
  --argjson schedule_runs "$schedule_runs" \
  "$jq_defs $jq_filter"); then
  echo "classify-default-branch-ci-runs: malformed or incomplete runs payload; health is unknown" >&2
  exit 2
fi

if [ -n "$classification" ]; then
  printf '%s\n' "$classification"
fi
