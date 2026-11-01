#!/usr/bin/env bash
# The approved source merger transfers only this suite's former skill owner (#618).
# Exercise the real edit guard against committed before/after trees, including
# an external source and a prefix lookalike that must remain protected.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for scenario in transferred external lookalike undeclared; do
  repo=$work/$scenario
  case $scenario in
    transferred) owner=https://github.com/devantler-tech/agent-skills; expected=0 ;;
    external) owner=https://github.com/example/skills; expected=1 ;;
    lookalike) owner=https://github.com/devantler-tech/agent-skills-extra; expected=1 ;;
    undeclared) owner=https://github.com/devantler-tech/agent-skills; expected=1 ;;
  esac
  file=plugins/agentic-engineering/skills/agent-improvement/SKILL.md
  [ "$scenario" != undeclared ] || file=plugins/example/skills/example/SKILL.md
  mkdir -p "$repo/$(dirname "$file")"
  git -C "$repo" init -q
  git -C "$repo" config user.name fixture
  git -C "$repo" config user.email fixture@example.invalid
  git -C "$repo" config commit.gpgsign false
  printf '%s\n' '---' 'name: example' 'description: Example.' 'metadata:' "  github-repo: $owner" '---' 'Before.' > "$repo/$file"
  git -C "$repo" add "$file"
  git -C "$repo" commit -qm before
  base=$(git -C "$repo" rev-parse HEAD)
  printf '%s\n' '---' 'name: example' 'description: Example.' '---' 'After.' > "$repo/$file"
  git -C "$repo" add "$file"
  git -C "$repo" commit -qm after
  head=$(git -C "$repo" rev-parse HEAD)
  rc=0
  printf '%s\n' "$file" | BASE_SHA="$base" HEAD_SHA="$head" PR_ACTOR=devantler PR_HEAD_BRANCH=codex/consolidate-skills-618 GUARD_REPO_DIR="$repo" bash "$root/scripts/guard-bundled-skill-edits.sh" > "$work/output" 2>&1 || rc=$?
  if [ "$rc" -ne "$expected" ]; then
    printf 'FAIL %s: expected %s, got %s\n' "$scenario" "$expected" "$rc"
    cat "$work/output"
    exit 1
  fi
  if [ "$expected" -eq 1 ]; then
    grep -qF "$owner" "$work/output"
  fi
done
echo 'PASS: transferred source is local; external sources remain protected'

# The installed distil procedure must not forbid its new canonical authoring surface.
route="$root/plugins/agentic-engineering/skills/self-improvement/SKILL.md"
if grep -qF "never a bundled copy inside a plugin or deployment" "$route"; then
  echo "FAIL: distil procedure still forbids plugin-authored skill changes" >&2
  exit 1
fi
grep -qF "locally authored skill" "$route"
grep -qF "external synchronized skill" "$route"
