#!/usr/bin/env bash
# Pin the selection obligations in their operative section, with removal controls.
# These are definition-drift checks; model behavior is evaluated separately using
# fixtures/surveyor-selection.json (with its expected outcomes hidden from the evaluator).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SURVEYOR="$HERE/../agents/portfolio-surveyor.agent.md"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Verify selection obligations occur inside the operative section of the supplied agent file.
check_contract() {
  local source=$1 section
  section=$(awk '
    /^#### Advance selection evidence$/ {inside=1; next}
    inside && /^#{1,4} / {exit}
    inside {print}
  ' "$source")
  [ -n "$section" ] || { echo 'missing operative selection section'; return 1; }

  local requirement missing=0
  # shellcheck disable=SC2016 # Markdown backticks are literal contract text.
  for requirement in \
    'Rank the complete issue universe by the consuming contract' \
    'When the consumer declares no selection order, retain the default oldest-actionable-first rule' \
    'Include creation timestamps and every field needed to apply that order' \
    'For every candidate skipped before the nominated issue, retain a permitted skip reason' \
    'Verify all applicable actionability joins for the nominated candidate itself' \
    'Missing ranking or a missing, stale, or failed actionability join is candidate-scoped `QUERY-UNKNOWN`' \
    'Report no actionable Advance work only when every candidate has a current, evidenced non-actionable reason' \
    'Incomplete selection evidence makes the full survey ineligible for a freshness-cursor advance' \
    'Preserve successful Operate and unrelated candidate results'; do
    if ! grep -F -- "$requirement" <<< "$section" > /dev/null; then
      printf 'missing selection obligation: %s\n' "$requirement"
      missing=1
    fi
  done
  return "$missing"
}

check_contract "$SURVEYOR"

# Removing any obligation must fail even when its exact words remain elsewhere.
# This also proves each mutation actually changed the source before judging it.
for prefix in \
  'Rank the complete issue universe' \
  'When the consumer declares no selection order' \
  'Include creation timestamps' \
  'For every candidate skipped' \
  'Verify all applicable actionability joins' \
  'Missing ranking or a missing' \
  'Report no actionable Advance work' \
  'Incomplete selection evidence' \
  'Preserve successful Operate'; do
  awk -v prefix="$prefix" '
    /^#### Advance selection evidence$/ {inside=1}
    inside && index($0,prefix)==1 {removed=$0; count++; next}
    inside && /^### / {inside=0}
    {print}
    END {
      if (count != 1) exit 1
      print "\n### Non-operative example\n" removed
    }
  ' "$SURVEYOR" > "$WORK/mutant.md" || {
    echo "FAIL: removal control did not fire: $prefix" >&2
    exit 1
  }
  if check_contract "$WORK/mutant.md" > "$WORK/output"; then
    echo "FAIL: out-of-section wording rescued a removed obligation: $prefix" >&2
    exit 1
  fi
done

echo 'surveyor selection contract: PASS (9 independently removed obligations rejected)'
