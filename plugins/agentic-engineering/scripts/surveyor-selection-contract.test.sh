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
    'When the consumer declares no selection order, use the role' \
    'Join state, documented priority/outcome' \
    'Include creation timestamps and every field needed to apply the order' \
    'For every candidate skipped before the nominated issue, retain a permitted skip reason' \
    'Evaluate claim skips using the declared consumer lease policy and its authoritative timestamps' \
    'Collect linked-open-PR evidence for every candidate needed to establish selection' \
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
  'Join state, documented priority/outcome' \
  'Include creation timestamps' \
  'For every candidate skipped' \
  'Evaluate claim skips' \
  'Collect linked-open-PR evidence' \
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

echo 'surveyor selection contract: PASS (12 independently removed obligations rejected)'

# #599: native issue types and consumer-required metadata establish triage debt;
# optional label absence does not. Pin this in the operative section, not examples.
check_triage_contract() {
  local source=$1 section requirement
  section=$(awk '
    /^### 5[.] Triage, stale, and advance signals$/ {inside=1; next}
    inside && /^### / {exit}
    inside {print}
  ' "$source")
  [ -n "$section" ] || { echo 'missing operative triage section'; return 1; }
  if grep -Fq 'label-less issues/PRs (untriaged)' <<< "$section"; then
    echo 'optional label absence still establishes missing triage'; return 1
  fi
  # shellcheck disable=SC2016 # Markdown contract text, not command substitution.
  for requirement in \
    'Missing optional labels alone never establishes incomplete triage.' \
    'Where native issue types exist, use the untyped residual and other consumer-required metadata.' \
    'For PRs, judge missing metadata against the consuming contract; issue types do not classify PRs.' \
    'Without native issue types, use the triage scheme declared by the consuming contract.'; do
    grep -Fq -- "$requirement" <<< "$section" || {
      printf 'missing triage obligation: %s\n' "$requirement"; return 1
    }
  done
}

check_triage_contract "$SURVEYOR"

for prefix in \
  'Missing optional labels alone' \
  'Where native issue types exist' \
  'For PRs, judge missing metadata' \
  'Without native issue types'; do
  awk -v prefix="$prefix" '
    /^### 5[.] Triage, stale, and advance signals$/ {inside=1}
    inside && index($0,prefix)==1 {removed=$0; count++; next}
    inside && /^### / && $0 !~ /^### 5[.] / {inside=0}
    {print}
    END {
      if (count != 1) exit 1
      print "\n### Non-operative example\n" removed
    }
  ' "$SURVEYOR" > "$WORK/triage-mutant.md" || {
    echo "FAIL: triage removal control did not fire: $prefix" >&2; exit 1
  }
  if check_triage_contract "$WORK/triage-mutant.md" > "$WORK/output"; then
    echo "FAIL: out-of-section wording rescued a removed triage obligation: $prefix" >&2; exit 1
  fi
done

awk '/^### 5[.] Triage, stale, and advance signals$/ {
  print; print "From the enumeration: label-less issues/PRs (untriaged);"; next
} {print}' "$SURVEYOR" > "$WORK/triage-label-mutant.md"
if check_triage_contract "$WORK/triage-label-mutant.md" > "$WORK/output"; then
  echo 'FAIL: contradictory label-based triage was accepted' >&2; exit 1
fi
echo 'surveyor triage contract: PASS (four removal controls and label-based regression rejected)'
