#!/usr/bin/env bash
# Exercise the actual scope resolver used before the programmed updater.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for event in schedule workflow_dispatch; do
  bash "$here/skill-update-scope.sh" "$event" >"$work/out"
  [[ $(cat "$work/out") == $'dir=plugins\nbranch=deps/agent-skills-update\npins=plugins/engineering-practices/skills/git-commit e24be77e6f203409cf99ab7d5a67e1540cb386d3' ]] || {
    printf 'FAIL: full-catalogue update must retain the reviewed git-commit pin\n' >&2
    exit 1
  }
done
bash "$here/skill-update-scope.sh" workflow_dispatch all >"$work/out"
[[ $(cat "$work/out") == $'dir=plugins\nbranch=deps/agent-skills-update\npins=plugins/engineering-practices/skills/git-commit e24be77e6f203409cf99ab7d5a67e1540cb386d3' ]]
bash "$here/skill-update-scope.sh" workflow_dispatch agentic-engineering >"$work/out"
[[ $(cat "$work/out") == $'dir=plugins/agentic-engineering/skills\nbranch=deps/agent-skills-update-agentic-engineering-skills\npins=' ]]
bash "$here/skill-update-scope.sh" workflow_dispatch engineering-practices >"$work/out"
[[ $(cat "$work/out") == $'dir=plugins/engineering-practices/skills\nbranch=deps/agent-skills-update-engineering-practices-skills\npins=plugins/engineering-practices/skills/git-commit e24be77e6f203409cf99ab7d5a67e1540cb386d3' ]]
# A scoped producer must still create the canonical per-skill branch accepted
# by the existing actor-and-one-skill guard, not a broader exemption.
branch=$(sed -n 's/^branch=//p' "$work/out")
[[ "$branch-ways-of-working" == deps/agent-skills-update-engineering-practices-skills-ways-of-working ]]
for scope in unknown ../outside $'agentic-engineering\ndir=plugins' $'engineering-practices\nbranch=other'; do
  rc=0
  bash "$here/skill-update-scope.sh" workflow_dispatch "$scope" >"$work/out" 2>"$work/err" || rc=$?
  [[ $rc == 2 && ! -s $work/out && -s $work/err ]]
done
rc=0
for scope in agentic-engineering engineering-practices; do
  rc=0
  bash "$here/skill-update-scope.sh" schedule "$scope" >"$work/out" 2>"$work/err" || rc=$?
  [[ $rc == 2 && ! -s $work/out ]]
done
rc=0
bash "$here/skill-update-scope.sh" pull_request all >"$work/out" 2>"$work/err" || rc=$?
[[ $rc == 2 && ! -s $work/out ]]
options=$(yq -o=json '.on.workflow_dispatch.inputs.scope' "$here/../.github/workflows/update-agent-skills.yaml")
printf '%s\n' "$options" | jq -se 'length == 1 and (.[0] | .type == "choice" and .default == "all" and
  (.options | sort) == ["agentic-engineering","all","engineering-practices"])' >/dev/null
workflow=$(yq -o=json '.' "$here/../.github/workflows/update-agent-skills.yaml")
if ! printf '%s\n' "$workflow" | jq -se 'length == 1 and (.[0].concurrency == {
  group:"agent-plugins-skill-sync-${{ github.repository }}",
  "cancel-in-progress":false, queue:"max"})' >/dev/null; then
  printf 'skill update scopes: require one non-cancelling queue across all scopes and follow-up jobs\n' >&2
  exit 1
fi
printf '%s\n' "$workflow" | jq -se 'length == 1 and (.[0] |
  .permissions == {} and .jobs.scope.permissions == {contents:"read"} and
  .jobs.scope.outputs.pins == "${{ steps.scope.outputs.pins }}" and
  .jobs.update.with.pins == "${{ needs.scope.outputs.pins }}" and
  .jobs.update.permissions == {contents:"write","pull-requests":"write"} and
  .jobs."bump-versions".permissions == {contents:"read"})' >/dev/null
# Inspect the declared Git calls; this is a regression guard, not an arbitrary shell parser.
has_local_git_write() {
  jq -e '[.jobs."bump-versions".steps[] | .run // ""]
    | any(test("git([[:space:]]+[^\\n]*)?[[:space:]]+(commit|push)([[:space:]]|$)"))' >/dev/null
}
if printf '%s\n' "$workflow" | has_local_git_write; then
  printf 'FAIL: skill metadata follow-ups still publish unsigned local commits\n' >&2
  exit 1
fi
for command in 'git commit -m metadata' 'git push origin HEAD' \
  'git -C update commit -m metadata' 'git -C update push origin HEAD' \
  'git -c user.name=bot commit -m metadata'; do
  if ! jq --arg command "$command" '.jobs."bump-versions".steps += [{run:$command}]' <<<"$workflow" | has_local_git_write; then
    printf 'FAIL: workflow guard misses local write: %s\n' "$command" >&2
    exit 1
  fi
done
if jq --arg command 'git -C update fetch origin main' '.jobs."bump-versions".steps += [{run:$command}]' <<<"$workflow" | has_local_git_write; then
  printf 'FAIL: workflow guard rejects a read-only fetch\n' >&2
  exit 1
fi
printf '%s\n' "$workflow" | jq -e '
  [.jobs."bump-versions".steps[] | select(.id == "publish-metadata")] as $writers
  | ($writers|length)==1 and
    $writers[0].env.GH_TOKEN == "${{ steps.app-token.outputs.token }}" and
    ($writers[0].run|contains("publish-skill-metadata.sh")) and
    ([.jobs."bump-versions".steps[] | select(.id == "trusted-tools")]
      | length==1 and .[0].with.ref == "${{ github.sha }}" and
        .[0].with."persist-credentials" == false)
' >/dev/null || {
  printf 'FAIL: signed metadata publisher lacks reviewed tools or the existing App token\n' >&2
  exit 1
}
printf 'skill update scopes: PASS (declared selections, canonical branch and fail-closed dispatch)\n'
