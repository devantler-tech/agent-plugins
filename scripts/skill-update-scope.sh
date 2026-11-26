#!/usr/bin/env bash
# Resolve only declared updater scopes before any reusable updater is called.
set -euo pipefail
refuse() { printf 'skill update scope: unsupported dispatch\n' >&2; exit 2; }
[[ $# -ge 1 && $# -le 2 ]] || refuse
# A temporary pin is a skill directory and an upstream commit. To release pinned
# metadata on an installed skill, clear the pin and dispatch once with unpin.
pin=''
case "$1:${2:-all}" in
  schedule:all|workflow_dispatch:all) printf 'dir=plugins\nbranch=deps/agent-skills-update\npins=%s\n' "$pin" ;;
  workflow_dispatch:agentic-engineering) printf 'dir=plugins/agentic-engineering/skills\nbranch=deps/agent-skills-update-agentic-engineering-skills\npins=%s\n' "$pin" ;;
  *) refuse ;;
esac
