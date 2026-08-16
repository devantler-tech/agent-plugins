#!/usr/bin/env bash
# Hermetic contract tests for classify-default-branch-ci-runs.sh.
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
CLASSIFIER="$HERE/classify-default-branch-ci-runs.sh"
SURVEYOR="$HERE/../agents/portfolio-surveyor.agent.md"
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/classify-default-branch-ci-runs.test.XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT

pass=0
fail=0

record_failure() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1" >&2
}

expect_output() {
  local label=$1 payload=$2 expected=$3 fixture="$TEST_TMP/input.json" out status=0
  printf '%s\n' "$payload" >"$fixture"
  out=$("$CLASSIFIER" --input "$fixture" 2>"$TEST_TMP/stderr") || status=$?
  if [ "$status" -eq 0 ] && [ "$out" = "$expected" ]; then
    pass=$((pass + 1))
  else
    record_failure "$label"
    printf '      expected exit 0 and output:\n%s\n      got exit %s and output:\n%s\n' \
      "$expected" "$status" "$out" >&2
    sed 's/^/      stderr: /' "$TEST_TMP/stderr" >&2
  fi
}

expect_remote_failure() {
  local stub_dir="$TEST_TMP/failing-bin" out status=0
  mkdir -p "$stub_dir"
  cat >"$stub_dir/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' '{"workflow_runs":[{"id":10,"workflow_id":11,"event":"push","conclusion":"success","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/ok","name":"CI"}]}'
exit 1
STUB
  chmod +x "$stub_dir/gh"
  out=$(PATH="$stub_dir:$PATH" "$CLASSIFIER" \
    --repo devantler-tech/example \
    --branch main \
    --head-sha 0123456789abcdef0123456789abcdef01234567 \
    2>"$TEST_TMP/stderr") || status=$?
  if [ "$status" -eq 2 ] && [ -z "$out" ]; then
    pass=$((pass + 1))
  else
    record_failure 'a later pagination failure cannot classify partial pages as green'
    printf '      expected exit 2 and empty stdout, got exit %s and output: %s\n' \
      "$status" "$out" >&2
  fi
}

if [ ! -x "$CLASSIFIER" ]; then
  printf 'FAIL  classifier is missing or not executable: %s\n' "$CLASSIFIER" >&2
  exit 1
fi

expect_output \
  'a later success clears an earlier failure for the same workflow' \
  '[
    {"id":10,"workflow_id":11,"event":"schedule","conclusion":"failure","created_at":"2026-07-13T10:00:00Z","html_url":"https://example.test/fail","name":"Template Sync"},
    {"id":11,"workflow_id":11,"event":"workflow_dispatch","conclusion":"success","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/ok","name":"Template Sync"}
  ]' \
  ''

expect_output \
  'pending and cancelled retries do not clear a known failure' \
  '[
    {"id":10,"workflow_id":11,"event":"push","conclusion":"failure","created_at":"2026-07-13T10:00:00Z","html_url":"https://example.test/fail","name":"Template Sync"},
    {"id":11,"workflow_id":11,"event":"workflow_dispatch","conclusion":"cancelled","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/cancelled","name":"Template Sync"},
    {"id":12,"workflow_id":11,"event":"workflow_dispatch","conclusion":null,"status":"in_progress","created_at":"2026-07-14T10:00:00Z","html_url":"https://example.test/pending","name":"Template Sync"}
  ]' \
  $'11\tfailure\thttps://example.test/fail\tTemplate Sync\tpush\t\t2026-07-13T10:00:00Z\t10'

expect_output \
  'managed jobs sharing one workflow id retain independent state' \
  '[
    {"id":20,"workflow_id":107623015,"event":"dynamic","path":"dynamic/dependabot/dependabot-updates","conclusion":"failure","created_at":"2026-07-13T10:00:00Z","html_url":"https://example.test/helm-fail","name":"helm in /pkg/svc/installer/kyverno - Update #1510869626"},
    {"id":21,"workflow_id":107623015,"event":"dynamic","path":"dynamic/dependabot/dependabot-updates","conclusion":"success","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/docker-ok","name":"docker in /pkg/svc/installer/kyverno - Update #1510869627"}
  ]' \
  $'107623015\tfailure\thttps://example.test/helm-fail\thelm in /pkg/svc/installer/kyverno - Update #1510869626\tdynamic\tdynamic/dependabot/dependabot-updates\t2026-07-13T10:00:00Z\t20'

expect_output \
  'raw pagination documents are flattened before latest-state selection' \
  '{"workflow_runs":[
    {"id":11,"workflow_id":11,"event":"workflow_dispatch","conclusion":"success","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/ok","name":"Template Sync"}
  ]}
  {"workflow_runs":[
    {"id":10,"workflow_id":11,"event":"schedule","conclusion":"failure","created_at":"2026-07-13T10:00:00Z","html_url":"https://example.test/fail","name":"Template Sync"}
  ]}' \
  ''

expect_output \
  'slurped pagination envelopes are flattened before classification' \
  '[
    {"workflow_runs":[
      {"id":11,"workflow_id":11,"event":"push","conclusion":"failure","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/fail","name":"Template Sync"}
    ]},
    {"workflow_runs":[
      {"id":10,"workflow_id":11,"event":"push","conclusion":"success","created_at":"2026-07-13T10:00:00Z","html_url":"https://example.test/ok","name":"Template Sync"}
    ]}
  ]' \
  $'11\tfailure\thttps://example.test/fail\tTemplate Sync\tpush\t\t2026-07-14T09:00:00Z\t11'

expect_output \
  'run id deterministically breaks equal created-at timestamps' \
  '[
    {"id":102,"workflow_id":11,"event":"push","conclusion":"failure","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/new-fail","name":"CI"},
    {"id":101,"workflow_id":11,"event":"push","conclusion":"success","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/old-ok","name":"CI"}
  ]' \
  $'11\tfailure\thttps://example.test/new-fail\tCI\tpush\t\t2026-07-14T09:00:00Z\t102'

expect_remote_failure

if grep -Fq '../scripts/classify-default-branch-ci-runs.sh' "$SURVEYOR" &&
  grep -Fq 'Do not reimplement the helper' "$SURVEYOR" &&
  grep -Fq 'exit 2 means' "$SURVEYOR" &&
  grep -Fq 'never green' "$SURVEYOR"; then
  pass=$((pass + 1))
else
  record_failure 'generic surveyor delegates fail-closed classification to the shipped helper'
fi

if [ "$fail" -ne 0 ]; then
  printf '%s passed, %s failed\n' "$pass" "$fail" >&2
  exit 1
fi

printf '%s passed, 0 failed\n' "$pass"
