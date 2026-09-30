#!/usr/bin/env bash
# Exercise the actual workflow's boolean guards with independent event and output fixtures.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workflow=${1:-"$root/.github/workflows/publish-marketplace-release.yaml"}
passed=0
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

# Job guards use only typed boolean inputs, explicit string comparisons, and &&/||.
# Read the expressions from YAML; adding syntax outside this subset must fail this test.
guard() {
  awk -v wanted="$1" '
    /^  [a-z]+:/ {job=$1; sub(/:$/, "", job)}
    job==wanted && /^    if: >-$/ {reading=1; next}
    reading && /^      / {sub(/^      /, ""); printf "%s ", $0; next}
    reading {exit}
  ' "$workflow"
}
assess=$(guard assess)
publish=$(guard publish)
if [ -z "$assess" ] || [ -z "$publish" ]; then fail 'missing workflow guards'; fi

evaluate() {
  local expression
  expression=$(printf '%s' "$1" | sed -E "s/'/\"/g; s/&&/and/g; s/\|\|/or/g; s/(github|inputs|vars|needs)\./\$context.\1./g")
  jq -n -r --argjson context "$2" "$expression"
}
case_check() {
  local name=$1 event=$2 ref=$3 armed=$4 variable=$5 status=$6 expected_assess=$7 expected_publish=$8
  local context actual_assess actual_publish
  context=$(jq -nc --arg event "$event" --arg ref "$ref" --argjson armed "$armed" \
    --arg variable "$variable" --arg status "$status" \
    '{github:{event_name:$event,ref:$ref},inputs:{publish:$armed},vars:{MARKETPLACE_AUTOPUBLISH:$variable},needs:{assess:{outputs:{status:$status}}}}')
  actual_assess=$(evaluate "$assess" "$context")
  actual_publish=$(evaluate "$publish" "$context")
  # Actions implicitly requires the assessment dependency to run successfully.
  if [ "$actual_assess" = false ]; then actual_publish=false; fi
  if [ "$actual_assess" != "$expected_assess" ] || [ "$actual_publish" != "$expected_publish" ]; then
    fail "$name: assessment=$actual_assess publication=$actual_publish"
  fi
  passed=$((passed + 1))
}

case_check 'manual defaults to read-only' workflow_dispatch refs/heads/main false '' VERIFIED true false
case_check 'manual input overrides enabled schedule variable' workflow_dispatch refs/heads/main false true VERIFIED true false
case_check 'manual publication explicitly armed' workflow_dispatch refs/heads/main true '' VERIFIED true true
case_check 'manual assessment accepts no version change' workflow_dispatch refs/heads/main false '' NO_VERSION_CHANGE true false
for status in '' NO_VERSION_CHANGE REJECTED verified; do
  case_check "manual refuses unverified output $status" workflow_dispatch refs/heads/main true '' "$status" true false
  case_check "schedule refuses unverified output $status" schedule refs/heads/main false true "$status" true false
done
case_check 'manual branch cannot assess or publish' workflow_dispatch refs/heads/feature true true VERIFIED false false
case_check 'manual tag cannot assess or publish' workflow_dispatch refs/tags/v1.2.0 true true VERIFIED false false
for variable in '' false TRUE 1 enabled; do
  case_check "schedule refuses variable $variable" schedule refs/heads/main false "$variable" VERIFIED false false
done
case_check 'schedule explicitly enabled' schedule refs/heads/main false true VERIFIED true true
for event in pull_request pull_request_target workflow_run push; do
  case_check "unsupported event $event" "$event" refs/heads/main true true VERIFIED false false
done

# Verify the permissions and checkout boundary used by these tested branches.
awk '
  /^permissions: \{\}$/ {root++}
  /^  assess:/ {job="assess"}
  /^  publish:/ {job="publish"}
  /^    permissions:$/ {permissions=job; next}
  permissions && /^      contents:/ {contents[permissions]=$2; next}
  permissions && /^      actions:/ {actions[permissions]=$2; next}
  permissions && !/^      / {permissions=""}
  /^    needs: assess$/ {dependency++}
  /^          ref: main$/ {main++}
  /^          fetch-depth: 0$/ {history++}
  /^          persist-credentials: false$/ {credentials++}
  /^        default: false$/ {default_off++}
  END {exit !(root==1 && contents["assess"]=="read" && actions["assess"]=="read" &&
    contents["publish"]=="write" && actions["publish"]=="read" && dependency==1 &&
    main==2 && history==2 && credentials==2 && default_off==1)}
' "$workflow" || fail 'permission, dependency, checkout or default input boundary'
passed=$((passed + 1))
printf 'PASS marketplace publication workflow (%s cases)\n' "$passed"
