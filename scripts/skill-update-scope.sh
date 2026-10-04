#!/usr/bin/env bash
# Resolve only declared updater scopes before any reusable updater is called.
set -euo pipefail
refuse() { printf 'skill update scope: unsupported dispatch\n' >&2; exit 2; }
[[ $# -ge 1 && $# -le 2 ]] || refuse
case "$1:${2:-all}" in
  schedule:all|workflow_dispatch:all) printf 'dir=plugins\n' ;;
  workflow_dispatch:agentic-engineering) printf 'dir=plugins/agentic-engineering/skills\n' ;;
  *) refuse ;;
esac
