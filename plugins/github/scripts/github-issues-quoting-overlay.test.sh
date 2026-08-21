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

# The overlay identifies itself by this heading. Both the presence check and the
# stays-outside-skills check key on it, so the marker cannot drift unnoticed.
OVERLAY_HEADING="## Quoting overlay for github-issues"

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
  assert_contains "${README}" "-f \"title=\${title}\"" "safe shell-held -f alternative"
  assert_contains "${README}" "github-issues" "names the synced skill"
  assert_contains "${README}" "milestones" "names the milestones reference"
  assert_contains "${README}" "skills/" "states the overlay stays outside skills/"
  assert_contains "${README}" "${OVERLAY_HEADING}" "overlay heading present"
fi

# The overlay must not live under skills/, where an update-agent-skills pull
# would revert it. Identify the overlay by its own heading rather than by
# filename: a synced skill may legitimately ship a README of its own, and
# failing on that would block CI while blaming this overlay for a file it does
# not own.
if [ -d "${SKILLS_DIR}" ]; then
  overlay_under_skills=0
  while IFS= read -r -d '' f; do
    if grep -F -- "${OVERLAY_HEADING}" "${f}" >/dev/null 2>&1; then
      overlay_under_skills=1
      echo "FAIL: quoting overlay found under skills/, where update-agent-skills would revert it: ${f}" >&2
    fi
  done < <(find "${SKILLS_DIR}" -type f -name '*.md' -print0 2>/dev/null || true)
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
