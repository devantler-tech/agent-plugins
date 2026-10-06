#!/usr/bin/env bash
# Guard the fail-closed, single-runner skill-spec validation contract.
# Shell fragments below are intentionally matched and mutated literally.
# shellcheck disable=SC2016
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKFLOW=${1:-$HERE/../.github/workflows/ci.yaml}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

job_block() {
  local job=$1 workflow=$2
  awk -v job="$job" '
    $0 == "  " job ":" { inside=1 }
    inside && $0 ~ /^  [a-zA-Z0-9_-]+:$/ && $0 != "  " job ":" { exit }
    inside { print }
  ' "$workflow"
}

check_workflow() {
  local workflow=$1 validate required failures=0
  validate=$(job_block validate-spec "$workflow")
  required=$(job_block ci-required-checks "$workflow")

  require() {
    local description=$1 pattern=$2 text=$3
    if ! grep -Fq -- "$pattern" <<<"$text"; then
      echo "FAIL: $description" >&2
      failures=$((failures + 1))
    fi
  }
  reject() {
    local description=$1 pattern=$2 text=$3
    if grep -Fq -- "$pattern" <<<"$text"; then
      echo "FAIL: $description" >&2
      failures=$((failures + 1))
    fi
  }

  require 'validate-spec job is present' '  validate-spec:' "$validate"
  require 'complete depth-bounded skill discovery is retained' \
    "find plugins -mindepth 4 -maxdepth 4 -name SKILL.md -print0" "$validate"
  require 'discovery is sorted without corrupting filenames' 'sort -z' "$validate"
  require 'empty discovery is refused' 'if [ "${#skills[@]}" -eq 0 ]; then' "$validate"
  require 'validator installer runs once in the consolidated job' \
    'run: bash scripts/install-skills-ref.sh' "$validate"
  require 'each discovered path is validated' 'skills-ref validate "$skill"' "$validate"
  require 'validation failures stop the job' 'set -euo pipefail' "$validate"
  require 'required aggregate waits for validation' 'validate-spec]' "$required"
  require 'required aggregate consumes the validation result' \
    '${{ needs.validate-spec.result }}' "$required"

  reject 'dynamic per-skill matrix must not return' 'matrix:' "$validate"
  reject 'validation must not tolerate command failure' '|| true' "$validate"
  reject 'validation must not use continue-on-error' 'continue-on-error:' "$validate"
  reject 'obsolete discovery job must not return' '  discover-skills:' "$(cat "$workflow")"

  if [ "$(grep -Fc 'skills-ref validate' <<<"$validate")" -ne 1 ]; then
    echo 'FAIL: consolidated job must contain exactly one validator command' >&2
    failures=$((failures + 1))
  fi

  [ "$failures" -eq 0 ]
}

expect_rejected() {
  local label=$1 workflow=$2
  if check_workflow "$workflow" >"$WORK/$label.log" 2>&1; then
    echo "FAIL: negative control was accepted: $label" >&2
    return 1
  fi
  echo "PASS: rejected $label"
}

check_workflow "$WORKFLOW"

sed 's/-mindepth 4/-mindepth 5/' "$WORKFLOW" >"$WORK/dropped-skill.yaml"
expect_rejected dropped-skill "$WORK/dropped-skill.yaml"

sed 's/skills-ref validate "$skill"/echo "$skill"/' "$WORKFLOW" >"$WORK/replaced-validator.yaml"
expect_rejected replaced-validator "$WORK/replaced-validator.yaml"

sed 's/skills-ref validate "$skill"/skills-ref validate "$skill" || true/' \
  "$WORKFLOW" >"$WORK/tolerated-failure.yaml"
expect_rejected tolerated-failure "$WORK/tolerated-failure.yaml"

sed 's/, validate-spec]/]/' "$WORKFLOW" >"$WORK/missing-aggregate.yaml"
expect_rejected missing-aggregate "$WORK/missing-aggregate.yaml"

echo 'PASS: consolidated skill validation is complete, fail-closed, and required'
