#!/usr/bin/env bash
# Exercise the actual scope resolver used before the programmed updater.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for event in schedule workflow_dispatch; do
  bash "$here/skill-update-scope.sh" "$event" > "$work/out"
  [[ $(cat "$work/out") == dir=plugins ]]
done
bash "$here/skill-update-scope.sh" workflow_dispatch all > "$work/out"
[[ $(cat "$work/out") == dir=plugins ]]
bash "$here/skill-update-scope.sh" workflow_dispatch agentic-engineering > "$work/out"
[[ $(cat "$work/out") == dir=plugins/agentic-engineering/skills ]]
for scope in unknown ../outside $'agentic-engineering\ndir=plugins'; do
  rc=0
  bash "$here/skill-update-scope.sh" workflow_dispatch "$scope" > "$work/out" 2> "$work/err" || rc=$?
  [[ $rc == 2 && ! -s $work/out && -s $work/err ]]
done
rc=0
bash "$here/skill-update-scope.sh" schedule agentic-engineering > "$work/out" 2> "$work/err" || rc=$?
[[ $rc == 2 && ! -s $work/out ]]
rc=0
bash "$here/skill-update-scope.sh" pull_request all > "$work/out" 2> "$work/err" || rc=$?
[[ $rc == 2 && ! -s $work/out ]]
printf 'skill update scopes: PASS (9 cases)\n'
