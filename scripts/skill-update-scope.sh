#!/usr/bin/env bash
# Resolve only declared updater scopes before any reusable updater is called.
set -euo pipefail
refuse() { printf 'skill update scope: unsupported dispatch\n' >&2; exit 2; }
[[ $# -ge 1 && $# -le 2 ]] || refuse
# Hold Context7 at the current revision until hosted query-docs accepts version (#745).
# Both scopes include this skill. After removing the hold, dispatch once with unpin
# to release the installed skill's pinned metadata.
pin='plugins/agentic-engineering/skills/context7-mcp 7fe6e09cfa8ad9aba5768da2e37823ccd3837abb'
case "$1:${2:-all}" in
  schedule:all|workflow_dispatch:all) printf 'dir=plugins\nbranch=deps/agent-skills-update\npins=%s\n' "$pin" ;;
  workflow_dispatch:agentic-engineering) printf 'dir=plugins/agentic-engineering/skills\nbranch=deps/agent-skills-update-agentic-engineering-skills\npins=%s\n' "$pin" ;;
  *) refuse ;;
esac
