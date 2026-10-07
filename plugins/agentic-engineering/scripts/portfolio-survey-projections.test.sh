#!/usr/bin/env bash
# Execute the jq programs from the shipped agent examples, not mirrored implementations.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
node - "$here/../agents/portfolio-surveyor.agent.md" "$work" <<'NODE'
const fs = require("fs");
const source = fs.readFileSync(process.argv[2], "utf8");
const destination = process.argv[3];
const lines = source.split("\n");
const census = lines.find(line => line.includes("gh api graphql --paginate --slurp") && line.includes("nodes{number issueType"));
const censusMatch = census && census.match(/\| jq -ce '(.*)'$/);
if (!censusMatch) throw Error("actual census projection unavailable");
fs.writeFileSync(destination + "/census.jq", censusMatch[1]);
for (const [name, marker] of [["association","closedByPullRequestsReferences(includeClosedPrs"], ["dependency","issueDependenciesSummary{blockedBy"]]) {
 const start = lines.findIndex(line => line.includes(marker) && line.includes("-f query="));
 const match = start >= 0 && lines[start+1].match(/--jq '(.*)'$/);
 if (!match) throw Error("actual " + name + " projection unavailable");
 fs.writeFileSync(destination + "/" + name + ".jq", match[1].replaceAll("<number>", "42"));
}
NODE
failed=0
# Assert a complete verdict or a failed read with no apparently successful output.
check() {
 local filter=$1 change=$2 expected=$3 fixture=$4 status=0
 jq "$change" "$fixture" > "$work/input"
 jq -ce -f "$work/$filter.jq" "$work/input" > "$work/out" 2> "$work/err" || status=$?
 if [[ $expected == refuse ]]; then
  if [[ $status == 0 || -s $work/out ]]; then printf 'FAIL: %s accepted %s\n' "$filter" "$change" >&2; failed=$((failed+1)); fi
 elif [[ $status != 0 || $(cat "$work/out") != "$expected" ]]; then
  printf 'FAIL: %s positive control: %s\n' "$filter" "$change" >&2; failed=$((failed+1))
 fi
}
printf '%s\n' '[{"data":{"repository":{"issues":{"totalCount":0,"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}]' > "$work/census.json"
printf '%s\n' '{"data":{"repository":{"issue":{"number":42,"closedByPullRequestsReferences":{"totalCount":0},"issueDependenciesSummary":{"blockedBy":0,"totalBlockedBy":0},"subIssuesSummary":{"total":0,"completed":0},"labels":{"totalCount":0,"nodes":[]}}}}}' > "$work/issue.json"
check census '.' '{"total":0,"types":[]}' "$work/census.json"
for change in '.[0].errors=null' '.[0].errors=["partial"]' '.[0].errors=0' '.[0]=null' 'del(.[0].data.repository.issues.pageInfo)' '.[0].data.repository.issues.pageInfo.hasNextPage=true' '.[0].data.repository.issues.pageInfo.endCursor="unfetched"' '.[0].data.repository.issues.totalCount=0.5' '.=[]'; do
 check census "$change" refuse "$work/census.json"
done
for filter in association dependency; do
 if [[ $filter == association ]]; then expected='{"number":42,"openLinkedPRs":0}'; else expected='{"number":42,"openBlockedBy":0,"totalBlockedBy":0,"completedSubIssues":0,"totalSubIssues":0,"labels":[]}'; fi
 check "$filter" '.' "$expected" "$work/issue.json"
 check "$filter" '.errors=[]' "$expected" "$work/issue.json"
 for change in '.errors=null' '.errors=["partial"]' '.errors=0' '.=null' '.data.repository.issue.number=43' '.data.repository.issue.number=42.5' '.data.repository.issue.number=0' '.data.repository.issue.number="42"'; do
  check "$filter" "$change" refuse "$work/issue.json"
 done
done
for change in '.data.repository.issue.closedByPullRequestsReferences.totalCount=0.5' '.data.repository.issue.closedByPullRequestsReferences.totalCount=-1' '.data.repository.issue.closedByPullRequestsReferences.totalCount="0"'; do
 check association "$change" refuse "$work/issue.json"
done
for change in '.data.repository.issue.issueDependenciesSummary.blockedBy=0.5' '.data.repository.issue.issueDependenciesSummary.totalBlockedBy=0.5' '.data.repository.issue.subIssuesSummary.total=0.5' '.data.repository.issue.subIssuesSummary.completed=0.5' '.data.repository.issue.issueDependenciesSummary.blockedBy=1' '.data.repository.issue.subIssuesSummary.completed=1' 'del(.data.repository.issue.labels)' '.data.repository.issue.labels=null' '.data.repository.issue.labels.totalCount=1' '.data.repository.issue.labels.totalCount=0.5' '.data.repository.issue.labels.nodes=[{"name":"blocked"}]' '.data.repository.issue.labels.nodes=null'; do
 check dependency "$change" refuse "$work/issue.json"
done
check dependency '.data.repository.issue.labels={"totalCount":1,"nodes":[{"name":"blocked"}]}' '{"number":42,"openBlockedBy":0,"totalBlockedBy":0,"completedSubIssues":0,"totalSubIssues":0,"labels":["blocked"]}' "$work/issue.json"
printf '%s\n' '[{"data":{"repository":{"issues":{"totalCount":2,"nodes":[{"number":1,"issueType":{"name":"Bug"}}],"pageInfo":{"hasNextPage":true,"endCursor":"c1"}}}}},{"data":{"repository":{"issues":{"totalCount":2,"nodes":[{"number":2,"issueType":null}],"pageInfo":{"hasNextPage":false,"endCursor":"c2"}}}}}]' > "$work/pages.json"
check census '.' '{"total":2,"types":[{"type":null,"count":1},{"type":"Bug","count":1}]}' "$work/pages.json"
check census 'map(.errors=[])' '{"total":2,"types":[{"type":null,"count":1},{"type":"Bug","count":1}]}' "$work/pages.json"
for change in '.[0].data.repository.issues.pageInfo.hasNextPage=false' '.[1].data.repository.issues.pageInfo.hasNextPage=true' '.[1].data.repository.issues.pageInfo.endCursor="c1"' '.[1].data.repository.issues.nodes[0].number=1' '.[1].data.repository.issues.totalCount=3' '.[1].data.repository.issues.nodes=[]' '.[0].data.repository.issues.pageInfo.hasNextPage="true"' '.[1].data.repository.issues.pageInfo.endCursor=null' '.[1].data.repository.issues.nodes[0].number=2.5' '.[1].data.repository.issues.nodes[0].issueType={}' '.[1].errors=null'; do
 check census "$change" refuse "$work/pages.json"
done
[[ $failed == 0 ]] || exit 1
printf 'PASS: actual survey envelopes, exact identities, integer counts and terminal pagination\n'
