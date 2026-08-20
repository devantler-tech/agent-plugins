#!/usr/bin/env bash
# Hermetic pin: the github plugin ships a quoting overlay outside skills/
# so it survives update-agent-skills. Does not fail merely because the
# synced github-issues copy still shows the upstream quoting pattern.
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PLUGIN_DIR=$(CDPATH='' cd -- "${HERE}/.." && pwd -P)
README="${PLUGIN_DIR}/README.md"
SKILLS_DIR="${PLUGIN_DIR}/skills"
MILESTONES="${SKILLS_DIR}/github-issues/references/milestones.md"

pass=0
fail=0

assert_file() {
  local path="$1"
  local label="$2"
  if [ -f "${path}" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL: ${label} missing: ${path}" >&2
    fail=$((fail + 1))
  fi
}

assert_contains() {
  local path="$1"
  local needle="$2"
  local label="$3"
  if grep -F -- "${needle}" "${path}" >/dev/null 2>&1; then
    pass=$((pass + 1))
  else
    echo "FAIL: ${label} — ${path} does not contain: ${needle}" >&2
    fail=$((fail + 1))
  fi
}

assert_file "${README}" "plugin-authored quoting overlay README"
assert_file "${MILESTONES}" "synced github-issues milestones reference still present"

if [ -f "${README}" ]; then
  assert_contains "${README}" "--input" "safe --input JSON alternative"
  assert_contains "${README}" "github-issues" "names the synced skill"
  assert_contains "${README}" "milestones" "names the milestones reference"
  assert_contains "${README}" "skills/" "states the overlay stays outside skills/"
  case "${README}" in
    */skills/*)
      echo "FAIL: overlay README lives under skills/ and would be overwritten by update-agent-skills" >&2
      fail=$((fail + 1))
      ;;
    *)
      pass=$((pass + 1))
      ;;
  esac
fi

if [ -d "${SKILLS_DIR}" ]; then
  overlay_under_skills=0
  while IFS= read -r -d '' f; do
    case "${f}" in
      *README.md)
        overlay_under_skills=1
        echo "FAIL: plugin overlay README found under skills/: ${f}" >&2
        ;;
    esac
  done < <(find "${SKILLS_DIR}" -type f -name 'README.md' -print0 2>/dev/null || true)
  if [ "${overlay_under_skills}" -eq 0 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
  fi
fi

echo "github-issues-quoting-overlay: ${pass} passed, ${fail} failed"
if [ "${fail}" -ne 0 ]; then
  exit 1
fi
exit 0
