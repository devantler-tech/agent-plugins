#!/usr/bin/env bash
# Resolve only declared updater scopes before any reusable updater is called.
set -euo pipefail
refuse() { printf 'skill update scope: unsupported dispatch\n' >&2; exit 2; }
[[ $# -ge 1 && $# -le 2 ]] || refuse
# Temporary upstream hold tracked by devantler-tech/platform#5224. Emit it only
# for scopes containing the skill: the updater refuses a pin outside its dir.
pin='plugins/engineering-practices/skills/git-commit e24be77e6f203409cf99ab7d5a67e1540cb386d3'
case "$1:${2:-all}" in
  schedule:all|workflow_dispatch:all) printf 'dir=plugins\nbranch=deps/agent-skills-update\npins=%s\n' "$pin" ;;
  workflow_dispatch:agentic-engineering) printf 'dir=plugins/agentic-engineering/skills\nbranch=deps/agent-skills-update-agentic-engineering-skills\npins=\n' ;;
  workflow_dispatch:engineering-practices) printf 'dir=plugins/engineering-practices/skills\nbranch=deps/agent-skills-update-engineering-practices-skills\npins=%s\n' "$pin" ;;
  *) refuse ;;
esac
