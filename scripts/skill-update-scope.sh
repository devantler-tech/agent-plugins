#!/usr/bin/env bash
# Resolve only declared updater scopes before any reusable updater is called.
set -euo pipefail
refuse() { printf 'skill update scope: unsupported dispatch\n' >&2; exit 2; }
[[ $# -ge 1 && $# -le 2 ]] || refuse
# A skill held at a reviewed upstream commit, as `<skill-dir> <40-character commit>`,
# naming its tracking issue. None is held: the git-commit hold (#598) ended when
# upstream repaired the skill. A hold suits only scopes containing the skill, since
# the updater refuses a pin outside its dir. Emptying it does not release the
# installed skill, which keeps its pinned metadata: dispatch once with `unpin`.
pin=''
case "$1:${2:-all}" in
  schedule:all|workflow_dispatch:all) printf 'dir=plugins\nbranch=deps/agent-skills-update\npins=%s\n' "$pin" ;;
  workflow_dispatch:agentic-engineering) printf 'dir=plugins/agentic-engineering/skills\nbranch=deps/agent-skills-update-agentic-engineering-skills\npins=%s\n' "$pin" ;;
  *) refuse ;;
esac
