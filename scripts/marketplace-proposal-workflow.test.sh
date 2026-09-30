#!/usr/bin/env bash
# Test the actual workflow's guards and permissions; no provider or host mutations.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workflow=${1:-"$root/.github/workflows/propose-marketplace-release.yaml"}
passed=0
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
[ -f "$workflow" ] || fail 'proposal workflow is not implemented'
guard() {
  awk -v wanted="$1" '/^  [a-z]+:/ {job=$1;sub(/:$/,"",job)} job==wanted && /^    if: >-$/ {reading=1;next} reading && /^      / {sub(/^      /,"");printf "%s ",$0;next} reading {exit}' "$workflow"
}
assess=$(guard assess) propose=$(guard propose) recheck=$(guard recheck)
if [ -z "$assess" ] || [ -z "$propose" ] || [ -z "$recheck" ]; then fail 'missing explicit job guards'; fi
evaluate() {
  local expression
  expression=$(printf '%s' "$1" | sed -E "s/'/\"/g;s/&&/and/g;s/\|\|/or/g;s/(github|inputs|vars|needs)\./\$context.\1./g")
  jq -nr --argjson context "$2" "$expression"
}
check() {
  local event=$1 ref=$2 armed=$3 flag=$4 assessment=$5 creation=$6 expected=$7 context actual
  context=$(jq -nc --arg event "$event" --arg ref "$ref" --argjson armed "$armed" --arg flag "$flag" --arg assessment "$assessment" --arg creation "$creation" '{github:{event_name:$event,ref:$ref},inputs:{propose:$armed},vars:{MARKETPLACE_AUTOPROPOSE:$flag},needs:{assess:{outputs:{status:$assessment}},propose:{outputs:{status:$creation}}}}')
  actual="$(evaluate "$assess" "$context") $(evaluate "$propose" "$context") $(evaluate "$recheck" "$context")"
  [ "$actual" = "$expected" ] || fail "$event/$ref/$armed/$flag/$assessment/$creation: $actual"
  passed=$((passed+1))
}
check workflow_dispatch refs/heads/main false '' PREPARED '' 'true false false'
check workflow_dispatch refs/heads/main false true PREPARED '' 'true false false'
check workflow_dispatch refs/heads/main true '' PREPARED CREATED 'true true true'
for status in '' NO_CHANGE REFUSED prepared; do
  check workflow_dispatch refs/heads/main true '' "$status" '' 'true false false'
done
for flag in '' false TRUE 1 enabled; do
  check schedule refs/heads/main false "$flag" PREPARED '' 'false false false'
done
check schedule refs/heads/main false true PREPARED CREATED 'true true true'
for status in '' NO_CHANGE REFUSED prepared; do
  check schedule refs/heads/main false true "$status" '' 'true false false'
done
for status in '' PREPARED NO_CHANGE REFUSED created; do
  check workflow_dispatch refs/heads/main true '' PREPARED "$status" 'true true false'
done
for ref in refs/heads/feature refs/tags/v1.0.0; do
  check workflow_dispatch "$ref" true true PREPARED CREATED 'false false false'
done
for event in push pull_request pull_request_target workflow_run; do
  check "$event" refs/heads/main true true PREPARED CREATED 'false false false'
done
awk '
 /^permissions: \{\}$/ {root++}
 /^  assess:/ {job="assess"}
 /^  propose:/ {job="propose"}
 /^  recheck:/ {job="recheck"}
 /^    permissions:$/ {permissions=job;next}
 permissions && /^      (contents|actions|pull-requests):/ {p[permissions,$1]=$2;next}
 permissions && !/^      / {permissions=""}
 /^          ref: main$/ {main++}
 /^          fetch-depth: 0$/ {history++}
 /^          persist-credentials: false$/ {credentials++}
 /^        default: false$/ {off++}
 /^    needs: assess$/ {create_needs++}
 /^    needs: propose$/ {recheck_needs++}
 END {exit !(root==1 && p["assess","contents:"]=="read" && p["assess","actions:"]=="read" && p["assess","pull-requests:"]=="read" &&
 p["propose","contents:"]=="write" && p["propose","pull-requests:"]=="write" && p["propose","actions:"]=="read" &&
 p["recheck","actions:"]=="write" && !p["recheck","contents:"] && !p["recheck","pull-requests:"] &&
 main==2 && history==2 && credentials==2 && off==1 && create_needs==1 && recheck_needs==1)}
' "$workflow" || fail 'permission, dependency, checkout or default-off boundary'
passed=$((passed+1))
# shellcheck disable=SC2016 # Match the literal variable reference used by the actual workflow.
grep -Fq 'gh workflow run recheck-open-prs.yaml --repo "$GH_REPO" --ref main -F dry-run=false' "$workflow" || fail 'CI must use the existing canonical recheck'
! grep -Eq 'workflow_run:|pull_request_target:|download-artifact|APP_PRIVATE_KEY|gh pr (merge|ready)' "$workflow" || fail 'unexpected authority or artifact consumer'
passed=$((passed+1))
printf 'PASS marketplace proposal workflow (%s cases)\n' "$passed"
