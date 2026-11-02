#!/usr/bin/env bash
# Authored skills are local; recorded provenance remains protected even when
# an edit removes it. Exercise the real guard against committed before/after trees.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for scenario in local external recorded-self lookalike different-path; do
  repo=$work/$scenario
  case $scenario in
    local) owner=''; expected=0 ;;
    external) owner=https://github.com/example/skills; expected=1 ;;
    recorded-self) owner=https://github.com/devantler-tech/agent-plugins; expected=1 ;;
    lookalike) owner=https://github.com/devantler-tech/agent-plugins-extra; expected=1 ;;
    different-path) owner=https://github.com/example/skills; expected=1 ;;
  esac
  file=plugins/agentic-engineering/skills/agent-improvement/SKILL.md
  [ "$scenario" != different-path ] || file=plugins/example/skills/example/SKILL.md
  mkdir -p "$repo/$(dirname "$file")"
  git -C "$repo" init -q
  git -C "$repo" config user.name fixture
  git -C "$repo" config user.email fixture@example.invalid
  git -C "$repo" config commit.gpgsign false
  {
    printf '%s\n' '---' 'name: example' 'description: Example.'
    if [ -n "$owner" ]; then printf '%s\n' 'metadata:' "  github-repo: $owner"; fi
    printf '%s\n' '---' 'Before.'
  } > "$repo/$file"
  git -C "$repo" add "$file"
  git -C "$repo" commit -qm before
  base=$(git -C "$repo" rev-parse HEAD)
  printf '%s\n' '---' 'name: example' 'description: Example.' '---' 'After.' > "$repo/$file"
  git -C "$repo" add "$file"
  git -C "$repo" commit -qm after
  head=$(git -C "$repo" rev-parse HEAD)
  rc=0
  printf '%s\n' "$file" | BASE_SHA="$base" HEAD_SHA="$head" PR_ACTOR=devantler PR_HEAD_BRANCH=codex/ownership-check GUARD_REPO_DIR="$repo" bash "$root/scripts/guard-bundled-skill-edits.sh" > "$work/output" 2>&1 || rc=$?
  if [ "$rc" -ne "$expected" ]; then
    printf 'FAIL %s: expected %s, got %s\n' "$scenario" "$expected" "$rc"
    cat "$work/output"
    exit 1
  fi
  if [ "$expected" -eq 1 ]; then
    grep -qF "$owner" "$work/output"
  fi
done
echo 'PASS: authored sources are local; every recorded upstream remains protected'

# The installed distil procedure must not forbid its new canonical authoring surface.
route="$root/plugins/agentic-engineering/skills/self-improvement/SKILL.md"
if grep -qF "never a bundled copy inside a plugin or deployment" "$route"; then
  echo "FAIL: distil procedure still forbids plugin-authored skill changes" >&2
  exit 1
fi
grep -qF "locally authored skill" "$route"
grep -qF "external synchronized skill" "$route"
