#!/usr/bin/env bash
# Guard complete, independent, fail-closed script-test sharding in CI.
# Shell and workflow fragments below are intentionally matched literally.
# shellcheck disable=SC2016
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKFLOW=${1:-$HERE/../.github/workflows/ci.yaml}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Print one named top-level workflow job without consuming the next job.
job_block() {
  local job=$1 workflow=$2
  awk -v job="$job" '
    $0 == "  " job ":" { inside=1 }
    inside && $0 ~ /^  [a-zA-Z0-9_-]+:$/ && $0 != "  " job ":" { exit }
    inside { print }
  ' "$workflow"
}

# Verify that every script-test command is assigned once to an independent required shard.
check_workflow() {
  local workflow=$1 lint marketplace packages required combined failures=0
  lint=$(job_block lint-scripts "$workflow")
  marketplace=$(job_block test-marketplace "$workflow")
  packages=$(job_block test-packages "$workflow")
  required=$(job_block ci-required-checks "$workflow")
  combined="$lint"$'\n'"$marketplace"$'\n'"$packages"

  # Record a failure when a fixed string occurs a different number of times than required.
  require_count() {
    local description=$1 pattern=$2 expected=$3 text=$4 actual
    actual=$(grep -Fc -- "$pattern" <<<"$text" || true)
    if [ "$actual" -ne "$expected" ]; then
      echo "FAIL: $description (expected $expected, found $actual)" >&2
      failures=$((failures + 1))
    fi
  }
  # Record a failure when a forbidden fixed string occurs in the selected text.
  reject() {
    local description=$1 pattern=$2 text=$3
    if grep -Fq -- "$pattern" <<<"$text"; then
      echo "FAIL: $description" >&2
      failures=$((failures + 1))
    fi
  }

  require_count 'static/core job exists once' '  lint-scripts:' 1 "$lint"
  require_count 'marketplace job exists once' '  test-marketplace:' 1 "$marketplace"
  require_count 'package job exists once' '  test-packages:' 1 "$packages"
  require_count 'each shard checks out independently' 'uses: actions/checkout@' 3 "$combined"
  require_count 'each shard installs the locked parser independently' \
    'run: npm ci --ignore-scripts --no-audit --no-fund' 3 "$combined"
  require_count 'each shard provisions Node independently' 'uses: actions/setup-node@' 3 "$combined"
  require_count 'each shard provisions Go independently' 'uses: actions/setup-go@' 3 "$combined"
  require_count 'each shard has read-only repository permission' 'contents: read' 3 "$combined"
  require_count 'marketplace shard is required and aggregated' 'test-marketplace' 2 "$required"
  require_count 'package shard is required and aggregated' 'test-packages' 2 "$required"

  local expected_commands=(
    'shellcheck "${files[@]}"'
    'go test plugins/agentic-engineering/scripts/autonomy-contract-go/main.go'
    'bash plugins/agentic-engineering/scripts/assess-autonomy.test.sh'
    'go test scripts/gh-json-go/main.go scripts/gh-json-go/main_test.go'
    'go test scripts/mcp-url-go/main.go scripts/mcp-url-go/main_test.go'
    './scripts/check-plugin-version-bump.test.sh || result=1'
    './scripts/bump-plugin-version.test.sh || result=1'
    'bash scripts/plugin-version-boundaries.test.sh || result=1'
    './scripts/check-instruction-size.sh || result=1'
    'bash scripts/check-instruction-size.test.sh || result=1'
    'bash scripts/install-skills-ref.test.sh'
    'bash scripts/ci-skill-validation-workflow.test.sh'
    'bash scripts/ci-script-test-sharding-workflow.test.sh'
    'bash scripts/marketplace-caller-context.test.sh'
    'bash scripts/prepare-marketplace-release.test.sh'
    'bash scripts/release-observation-boundaries.test.sh'
    'bash scripts/verify-marketplace-release.test.sh'
    'bash scripts/inspect-marketplace-release.test.sh'
    'bash scripts/marketplace-observation-completeness.test.sh'
    'bash scripts/check-marketplace-version.test.sh'
    'bash scripts/check-marketplace-release-remote.test.sh'
    'bash scripts/publish-marketplace-release.test.sh'
    'bash scripts/prepare-merged-marketplace-release.test.sh'
    'bash scripts/marketplace-publication-workflow.test.sh'
    'bash scripts/marketplace-publication-identity.test.sh'
    'bash scripts/propose-marketplace-release.test.sh'
    'bash scripts/marketplace-proposal-workflow.test.sh'
    'jq -e '\''.data.viewer.login == "github-actions[bot]"'\'''
    './scripts/recheck-open-prs.test.sh'
    'bash scripts/recheck-open-prs-observations.test.sh'
    'uses: actions/upload-artifact@'
    'bash scripts/recheck-open-prs-base-refresh.test.sh'
    'bash scripts/plugin-changelog.test.sh'
    'bash scripts/plugin-changelog-boundaries.test.sh'
    'bash scripts/plugin-changelog-release-boundaries.test.sh'
    'bash scripts/skill-update-scope.test.sh'
    './scripts/validate-manifests.test.sh'
    'bash scripts/mcp-boundaries.test.sh'
    'bash scripts/package-boundaries.test.sh'
    'bash scripts/package-discovery.test.sh'
    'bash scripts/desired-state-boundaries.test.sh'
    './scripts/refresh-desired-state-digests.test.sh || result=1'
    'bash scripts/digest-declarations.test.sh || result=1'
    'bash scripts/generated-write-safety.test.sh'
    './scripts/guard-bundled-skill-edits.test.sh'
    './scripts/guard-gh-json-fields.test.sh'
    './scripts/guard-gh-json-fields.sh'
    'bash "$t"'
  )
  local command
  for command in "${expected_commands[@]}"; do
    require_count "command remains present exactly once: $command" "$command" 1 "$combined"
  done

  reject 'test shards must not serialize behind each other' '    needs:' "$combined"
  reject 'test failures must not be tolerated' '|| true' "$combined"
  reject 'test failures must not use continue-on-error' 'continue-on-error:' "$combined"

  [ "$failures" -eq 0 ]
}

# Prove that a deliberately damaged workflow is rejected by the contract.
expect_rejected() {
  local label=$1 workflow=$2
  if check_workflow "$workflow" >"$WORK/$label.log" 2>&1; then
    echo "FAIL: negative control was accepted: $label" >&2
    return 1
  fi
  echo "PASS: rejected $label"
}

check_workflow "$WORKFLOW"

sed 's/bash scripts\/package-discovery.test.sh/echo skipped-package-discovery/' \
  "$WORKFLOW" >"$WORK/dropped-command.yaml"
expect_rejected dropped-command "$WORK/dropped-command.yaml"

sed 's/bash scripts\/package-boundaries.test.sh/bash scripts\/package-discovery.test.sh/' \
  "$WORKFLOW" >"$WORK/duplicate-command.yaml"
expect_rejected duplicate-command "$WORK/duplicate-command.yaml"

sed 's/bash scripts\/marketplace-caller-context.test.sh/bash scripts\/marketplace-caller-context.test.sh || true/' \
  "$WORKFLOW" >"$WORK/tolerated-failure.yaml"
expect_rejected tolerated-failure "$WORK/tolerated-failure.yaml"

sed '/needs.test-packages.result/d' "$WORKFLOW" >"$WORK/missing-aggregate.yaml"
expect_rejected missing-aggregate "$WORK/missing-aggregate.yaml"

echo 'PASS: script-test shards are complete, independent, and required'
