#!/usr/bin/env bash
# Hermetic contract tests for classify-default-branch-ci-runs.sh.
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
CLASSIFIER="$HERE/classify-default-branch-ci-runs.sh"
SURVEYOR="$HERE/../agents/portfolio-surveyor.agent.md"
DESIRED_STATE="$HERE/../resources/provider-neutral.desired-state.json"
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

expect_error() {
  local label=$1 payload=$2 fixture="$TEST_TMP/input.json" out status=0
  printf '%s\n' "$payload" >"$fixture"
  out=$("$CLASSIFIER" --input "$fixture" 2>"$TEST_TMP/stderr") || status=$?
  if [ "$status" -eq 2 ] && [ -z "$out" ]; then
    pass=$((pass + 1))
  else
    record_failure "$label"
    printf '      expected exit 2 and empty output, got exit %s and output: %s\n' \
      "$status" "$out" >&2
  fi
}

expect_remote_failure() {
  local stub_dir="$TEST_TMP/failing-bin" out status=0
  mkdir -p "$stub_dir"
  cat >"$stub_dir/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' '{"workflow_runs":[{"id":10,"run_attempt":1,"workflow_id":11,"event":"push","conclusion":"success","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/ok","name":"CI"}]}'
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

expect_remote_head_mismatch() {
  local stub_dir="$TEST_TMP/mismatched-head-bin" out status=0
  mkdir -p "$stub_dir"
  cat >"$stub_dir/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' '{"total_count":1,"workflow_runs":[{"id":10,"run_attempt":1,"workflow_id":11,"event":"push","head_branch":"main","head_sha":"abcdefabcdefabcdefabcdefabcdefabcdefabcd","conclusion":"failure","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/stale-fail","name":"CI"}]}'
STUB
  chmod +x "$stub_dir/gh"
  out=$(PATH="$stub_dir:$PATH" "$CLASSIFIER" \
    --repo devantler-tech/example \
    --branch main \
    --head-sha 0123456789abcdef0123456789abcdef01234567 \
    2>"$TEST_TMP/stderr") || status=$?
  if [ "$status" -eq 2 ] && [ -z "$out" ] &&
    ! grep -Fq 'CI red' <<<"$out" &&
    ! grep -Fq 'nothing_on_fire: false' <<<"$out"; then
    pass=$((pass + 1))
  else
    record_failure 'a superseded-head fixture yields no CI red row or negative fire verdict'
    printf '      expected exit 2 and empty stdout, got exit %s and output: %s\n' \
      "$status" "$out" >&2
  fi
}

expect_remote_branch_mismatch() {
  local stub_dir="$TEST_TMP/mismatched-branch-bin" out status=0
  mkdir -p "$stub_dir"
  cat >"$stub_dir/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' '{"total_count":1,"workflow_runs":[{"id":10,"run_attempt":1,"workflow_id":11,"event":"push","head_branch":"release","head_sha":"0123456789abcdef0123456789abcdef01234567","conclusion":"failure","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/wrong-branch-fail","name":"CI"}]}'
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
    record_failure 'a remote run from a different branch cannot be reported as current breakage'
    printf '      expected exit 2 and empty stdout, got exit %s and output: %s\n' \
      "$status" "$out" >&2
  fi
}

expect_remote_mixed_case_head() {
  local stub_dir="$TEST_TMP/mixed-case-head-bin" out status=0
  local expected=$'11\tfailure\thttps://example.test/current-fail\tCI\tpush\t\t2026-07-14T09:00:00Z\t10\t1'
  mkdir -p "$stub_dir"
  cat >"$stub_dir/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' '{"total_count":1,"workflow_runs":[{"id":10,"run_attempt":1,"workflow_id":11,"event":"push","head_branch":"main","head_sha":"abcdefabcdefabcdefabcdefabcdefabcdefabcd","conclusion":"failure","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/current-fail","name":"CI"}]}'
STUB
  chmod +x "$stub_dir/gh"
  out=$(PATH="$stub_dir:$PATH" "$CLASSIFIER" \
    --repo devantler-tech/example \
    --branch main \
    --head-sha ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD \
    2>"$TEST_TMP/stderr") || status=$?
  if [ "$status" -eq 0 ] && [ "$out" = "$expected" ]; then
    pass=$((pass + 1))
  else
    record_failure 'an accepted mixed-case SHA matches GitHub canonical lowercase output'
    printf '      expected exit 0 and output: %s; got exit %s and output: %s\n' \
      "$expected" "$status" "$out" >&2
  fi
}

check_surveyor_fail_closed_contract() {
  local source=$1 section requirement missing=0
  section=$(awk '
    /^### 4\. CI red on the default branch/ { inside = 1 }
    /^### 5\./ { inside = 0 }
    inside { print }
  ' "$source")
  [ -n "$section" ] || return 1

  while IFS= read -r requirement; do
    if ! grep -Fq -- "$requirement" <<<"$section"; then
      missing=1
    fi
  done <<'REQUIREMENTS'
emit only `QUERY-UNKNOWN step-4-classifier`
do not issue substitute in-band forge reads
do not derive `nothing_on_fire: false` from that unknown result
REQUIREMENTS
  return "$missing"
}

expect_surveyor_contract_ablation() {
  local requirement mutant="$TEST_TMP/pre-fix-agent.md"
  if check_surveyor_fail_closed_contract "$SURVEYOR"; then
    pass=$((pass + 1))
  else
    record_failure 'classifier failure yields only query-unknown and no substitute CI verdict'
  fi

  while IFS= read -r requirement; do
    awk -v requirement="$requirement" '
      { line = $0; sub(requirement, "", line); print line }
      END { print "\n## Non-operative example\n" requirement }
    ' "$SURVEYOR" >"$mutant"
    if check_surveyor_fail_closed_contract "$mutant"; then
      record_failure "pre-fix agent text without contract was accepted: $requirement"
    else
      pass=$((pass + 1))
    fi
  done <<'REQUIREMENTS'
emit only `QUERY-UNKNOWN step-4-classifier`
do not issue substitute in-band forge reads
do not derive `nothing_on_fire: false` from that unknown result
REQUIREMENTS
}

if [ ! -x "$CLASSIFIER" ]; then
  printf 'FAIL  classifier is missing or not executable: %s\n' "$CLASSIFIER" >&2
  exit 1
fi

expect_output \
  'a later success clears an earlier failure for the same workflow' \
  '[
    {"id":10,"run_attempt":1,"workflow_id":11,"event":"schedule","conclusion":"failure","created_at":"2026-07-13T10:00:00Z","html_url":"https://example.test/fail","name":"Template Sync"},
    {"id":11,"run_attempt":1,"workflow_id":11,"event":"workflow_dispatch","conclusion":"success","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/ok","name":"Template Sync"}
  ]' \
  ''

expect_output \
  'pending and cancelled retries do not clear a known failure' \
  '[
    {"id":10,"run_attempt":1,"workflow_id":11,"event":"push","conclusion":"failure","created_at":"2026-07-13T10:00:00Z","html_url":"https://example.test/fail","name":"Template Sync"},
    {"id":11,"run_attempt":1,"workflow_id":11,"event":"workflow_dispatch","conclusion":"cancelled","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/cancelled","name":"Template Sync"},
    {"id":12,"run_attempt":1,"workflow_id":11,"event":"workflow_dispatch","conclusion":null,"status":"in_progress","created_at":"2026-07-14T10:00:00Z","html_url":"https://example.test/pending","name":"Template Sync"}
  ]' \
  $'11\tfailure\thttps://example.test/fail\tTemplate Sync\tpush\t\t2026-07-13T10:00:00Z\t10\t1'

expect_output \
  'managed jobs sharing one workflow id retain independent state' \
  '[
    {"id":20,"run_attempt":1,"workflow_id":107623015,"event":"dynamic","path":"dynamic/dependabot/dependabot-updates","conclusion":"failure","created_at":"2026-07-13T10:00:00Z","html_url":"https://example.test/helm-fail","name":"helm in /pkg/svc/installer/kyverno - Update #1510869626"},
    {"id":21,"run_attempt":1,"workflow_id":107623015,"event":"dynamic","path":"dynamic/dependabot/dependabot-updates","conclusion":"success","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/docker-ok","name":"docker in /pkg/svc/installer/kyverno - Update #1510869627"}
  ]' \
  $'107623015\tfailure\thttps://example.test/helm-fail\thelm in /pkg/svc/installer/kyverno - Update #1510869626\tdynamic\tdynamic/dependabot/dependabot-updates\t2026-07-13T10:00:00Z\t20\t1'

expect_output \
  'raw pagination documents are flattened before latest-state selection' \
  '{"total_count":2,"workflow_runs":[
    {"id":11,"run_attempt":1,"workflow_id":11,"event":"workflow_dispatch","conclusion":"success","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/ok","name":"Template Sync"}
  ]}
  {"total_count":2,"workflow_runs":[
    {"id":10,"run_attempt":1,"workflow_id":11,"event":"schedule","conclusion":"failure","created_at":"2026-07-13T10:00:00Z","html_url":"https://example.test/fail","name":"Template Sync"}
  ]}' \
  ''

expect_output \
  'slurped pagination envelopes are flattened before classification' \
  '[
    {"total_count":2,"workflow_runs":[
      {"id":11,"run_attempt":1,"workflow_id":11,"event":"push","conclusion":"failure","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/fail","name":"Template Sync"}
    ]},
    {"total_count":2,"workflow_runs":[
      {"id":10,"run_attempt":1,"workflow_id":11,"event":"push","conclusion":"success","created_at":"2026-07-13T10:00:00Z","html_url":"https://example.test/ok","name":"Template Sync"}
    ]}
  ]' \
  $'11\tfailure\thttps://example.test/fail\tTemplate Sync\tpush\t\t2026-07-14T09:00:00Z\t11\t1'

expect_output \
  'run id deterministically breaks equal created-at timestamps' \
  '[
    {"id":102,"run_attempt":1,"workflow_id":11,"event":"push","conclusion":"failure","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/new-fail","name":"CI"},
    {"id":101,"run_attempt":1,"workflow_id":11,"event":"push","conclusion":"success","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/old-ok","name":"CI"}
  ]' \
  $'11\tfailure\thttps://example.test/new-fail\tCI\tpush\t\t2026-07-14T09:00:00Z\t102\t1'

expect_output \
  'a later rerun attempt is ordered by its execution time' \
  '[
    {"id":10,"run_attempt":2,"workflow_id":11,"event":"push","conclusion":"failure","created_at":"2026-07-14T09:00:00Z","run_started_at":"2026-07-14T11:00:00Z","html_url":"https://example.test/rerun-fail","name":"CI"},
    {"id":11,"run_attempt":1,"workflow_id":11,"event":"push","conclusion":"success","created_at":"2026-07-14T10:00:00Z","run_started_at":"2026-07-14T10:00:00Z","html_url":"https://example.test/ok","name":"CI"}
  ]' \
  $'11\tfailure\thttps://example.test/rerun-fail\tCI\tpush\t\t2026-07-14T09:00:00Z\t10\t2'

expect_error \
  'a non-positive run attempt makes the classification unknown' \
  '[
    {"id":10,"run_attempt":0,"workflow_id":11,"event":"push","conclusion":"failure","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/fail","name":"CI"}
  ]'

expect_error \
  'a missing run attempt makes the classification unknown' \
  '[
    {"id":10,"workflow_id":11,"event":"push","conclusion":"failure","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/fail","name":"CI"}
  ]'

expect_error \
  'a run without an event discriminator makes the classification unknown' \
  '[
    {"id":10,"run_attempt":1,"workflow_id":11,"conclusion":"failure","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/fail","name":"CI"}
  ]'

expect_error \
  'an invalid execution timestamp makes the classification unknown' \
  '[
    {"id":10,"run_attempt":1,"workflow_id":11,"event":"push","conclusion":"failure","created_at":"not-a-timestamp","html_url":"https://example.test/fail","name":"CI"}
  ]'

expect_error \
  'a calendar-normalized timestamp makes the classification unknown' \
  '[
    {"id":10,"run_attempt":1,"workflow_id":11,"event":"push","conclusion":"failure","created_at":"2026-02-31T10:00:00Z","html_url":"https://example.test/fail","name":"CI"}
  ]'

expect_error \
  'a dynamic run without a complete managed identity makes health unknown' \
  '[
    {"id":20,"run_attempt":1,"workflow_id":107623015,"event":"dynamic","conclusion":"failure","created_at":"2026-07-13T10:00:00Z","html_url":"https://example.test/managed-fail","name":"helm in /pkg/svc"}
  ]'

expect_output \
  'run id precedes attempt when distinct runs start in the same second' \
  '[
    {"id":101,"run_attempt":2,"workflow_id":11,"event":"push","conclusion":"success","created_at":"2026-07-14T08:00:00Z","run_started_at":"2026-07-14T10:00:00Z","html_url":"https://example.test/old-rerun-ok","name":"CI"},
    {"id":102,"run_attempt":1,"workflow_id":11,"event":"push","conclusion":"failure","created_at":"2026-07-14T09:00:00Z","run_started_at":"2026-07-14T10:00:00Z","html_url":"https://example.test/new-fail","name":"CI"}
  ]' \
  $'11\tfailure\thttps://example.test/new-fail\tCI\tpush\t\t2026-07-14T09:00:00Z\t102\t1'

expect_error \
  'a filtered result cap makes the classification unknown' \
  '{"total_count":1001,"workflow_runs":[
    {"id":10,"run_attempt":1,"workflow_id":11,"event":"push","conclusion":"success","created_at":"2026-07-14T09:00:00Z","html_url":"https://example.test/ok","name":"CI"}
  ]}'

expect_remote_failure
expect_remote_head_mismatch
expect_remote_branch_mismatch
expect_remote_mixed_case_head

if grep -Fq '../scripts/classify-default-branch-ci-runs.sh' "$SURVEYOR" &&
  grep -Fq 'Do not reimplement the helper' "$SURVEYOR" &&
  grep -Fq 'exit 2 means' "$SURVEYOR" &&
  grep -Fq 'never green' "$SURVEYOR"; then
  pass=$((pass + 1))
else
  record_failure 'generic surveyor delegates fail-closed classification to the shipped helper'
fi

expect_surveyor_contract_ablation

if grep -Fq 'event=<event>, path=<path>, created=<created_at>, run=<run_id>, attempt=<run_attempt>' "$SURVEYOR"; then
  pass=$((pass + 1))
else
  record_failure 'generic survey digest preserves managed-run routing fields'
fi

if grep -q 'export GH_TELEMETRY=0' "$CLASSIFIER"; then
  pass=$((pass + 1))
else
  record_failure 'classifier helper exports GH_TELEMETRY=0 before any gh invocation'
fi

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
classifier_sha=$(hash_file "$CLASSIFIER")
counter_sha=$(hash_file "$HERE/count-unresolved-review-threads.sh")
guard_sha=$(hash_file "$HERE/forge-readonly-guard.sh")
wrapper_sha=$(hash_file "$HERE/surveyor-forge-readonly.sh")
routing_sha=$(hash_file "$HERE/evaluate-inference-routing.sh")
json_stream_sha=$(hash_file "$HERE/json-stream.lib.sh")
if grep -Fq 'referenced runtime assets' "$DESIRED_STATE" &&
  jq -e \
    --arg classifier_sha "$classifier_sha" \
    --arg counter_sha "$counter_sha" \
    --arg guard_sha "$guard_sha" \
    --arg wrapper_sha "$wrapper_sha" \
    --arg json_stream_sha "$json_stream_sha" \
    --arg routing_sha "$routing_sha" '
    # The routing helper is independent of the surveyor, but shares the runtime asset pin set.
    .spec.source.requiredRuntimeAssets == [
      {
        path: "scripts/json-stream.lib.sh",
        sha256: $json_stream_sha,
        executable: true
      },
      {
        path: "scripts/classify-default-branch-ci-runs.sh",
        sha256: $classifier_sha,
        executable: true
      },
      {
        path: "scripts/count-unresolved-review-threads.sh",
        sha256: $counter_sha,
        executable: true
      },
      {
        path: "scripts/forge-readonly-guard.sh",
        sha256: $guard_sha,
        executable: true
      },
      {
        path: "scripts/surveyor-forge-readonly.sh",
        sha256: $wrapper_sha,
        executable: true
      },
      {
        path: "scripts/evaluate-inference-routing.sh",
        sha256: $routing_sha,
        executable: true
      }
    ]
  ' "$DESIRED_STATE" > /dev/null; then
  pass=$((pass + 1))
else
  record_failure 'agent-only onboarding pins the surveyor classifier runtime asset bytes'
fi

# Every required runtime asset is installed unconditionally. Onboarding may make the WIRING of
# the stdin adapter conditional, never its installation: a consumer that omits a required
# asset can never report its definitions current (#161). Both halves are asserted: the install
# step names every surveyor asset, and no step makes one of them optional.
install_step=$(jq -r '.spec.onboarding.steps[] | select(contains("referenced runtime assets"))' "$DESIRED_STATE")
missing=''
for asset in scripts/classify-default-branch-ci-runs.sh scripts/count-unresolved-review-threads.sh \
  scripts/json-stream.lib.sh \
  scripts/forge-readonly-guard.sh scripts/surveyor-forge-readonly.sh; do
  case "$install_step" in
  *"$asset"*) ;;
  *) missing="$missing $asset" ;;
  esac
done
if [ -z "$install_step" ]; then
  record_failure 'onboarding has no step that installs the referenced runtime assets'
elif [ -n "$missing" ]; then
  record_failure "onboarding does not install every surveyor runtime asset; missing:$missing"
else
  pass=$((pass + 1))
fi
if jq -r '.spec.onboarding.steps[]' "$DESIRED_STATE" | grep -Fq 'surveyor-forge-readonly.sh only where'; then
  record_failure 'onboarding makes a required runtime asset optional'
else
  pass=$((pass + 1))
fi

# The classifier must not turn contradictory or malformed records into clear health.
base_run='[{"id":10,"run_attempt":1,"workflow_id":11,"event":"push","status":"completed","conclusion":"success","created_at":"2026-10-02T00:00:00Z","html_url":"https://example.test/run-10","name":"CI"}]'
for mutation in \
  '.[0].conclusion="unrecognized"' \
  'del(.[0].conclusion)' \
  '.[0].conclusion=null' \
  '.[0].status="in_progress"' \
  '.[0].status="unrecognized"' \
  '.[0].conclusion="failure" | . += [.[0] | .conclusion="success"]' \
  '. += [.[0]]' \
  '.[0].id=0' \
  '.[0].id=-1' \
  '.[0].id=1.5' \
  '.[0].id=9007199254740992' \
  '.[0].workflow_id=0' \
  '.[0].workflow_id=-1' \
  '.[0].workflow_id=1.5' \
  '.[0].workflow_id=9007199254740992' \
  '.[0].run_attempt=9007199254740992'; do
  payload=$(printf '%s\n' "$base_run" | jq -c "$mutation")
  expect_error "invalid run record: $mutation" "$payload"
done
payload=$(printf '%s\n' "$base_run" | jq -c '.[0].conclusion="failure" | . += [.[0] | .run_attempt=2 | .conclusion="success"]')
expect_output 'distinct attempts of the same run remain separately observable' "$payload" ''
for status in queued in_progress requested waiting pending; do
  payload=$(printf '%s\n' "$base_run" | jq -c --arg status "$status" '.[0].status=$status | .[0].conclusion=null')
  expect_output "recognized unsettled run: $status" "$payload" ''
done
for conclusion in cancelled neutral skipped stale action_required; do
  payload=$(printf '%s\n' "$base_run" | jq -c --arg conclusion "$conclusion" '.[0].conclusion=$conclusion')
  expect_output "recognized non-clearing conclusion: $conclusion" "$payload" ''
done
stub_dir="$TEST_TMP/host-bound-bin"
mkdir -p "$stub_dir"
printf '%s\n' "$base_run" | jq -c \
  '.[0].head_sha="0123456789abcdef0123456789abcdef01234567" | .[0].head_branch="main" | {total_count:1,workflow_runs:.}' > "$TEST_TMP/host-response"
cat > "$stub_dir/gh" <<'STUB'
#!/usr/bin/env bash
[ "${GH_HOST:-}" = github.com ] && [ "${GH_TELEMETRY:-}" = 0 ] || exit 77
cat "$STUB_CI_RESPONSE"
STUB
chmod +x "$stub_dir/gh"
out='' status=0
out=$(GH_HOST=enterprise.invalid STUB_CI_RESPONSE="$TEST_TMP/host-response" PATH="$stub_dir:$PATH" \
  "$CLASSIFIER" --repo devantler-tech/example --branch main \
  --head-sha 0123456789abcdef0123456789abcdef01234567 2>"$TEST_TMP/stderr") || status=$?
if [ "$status" = 0 ] && [ -z "$out" ]; then
  pass=$((pass + 1))
else
  record_failure 'an inherited host cannot retarget the CI collector'
fi

# Flat arrays remain an explicit offline format, never a remote endpoint result.
remote_flat=$(printf '%s\n' "$base_run" | jq -c '.[0].head_sha="0123456789abcdef0123456789abcdef01234567" | .[0].head_branch="main"')
for payload in '[]' "$remote_flat"; do
  printf '%s\n' "$payload" > "$TEST_TMP/host-response"
  out='' status=0
  out=$(STUB_CI_RESPONSE="$TEST_TMP/host-response" PATH="$stub_dir:$PATH" "$CLASSIFIER" \
    --repo devantler-tech/example --branch main --head-sha 0123456789abcdef0123456789abcdef01234567 2>"$TEST_TMP/stderr") || status=$?
  if [ "$status" -eq 2 ] && [ -z "$out" ]; then pass=$((pass+1)); else record_failure 'remote flat run arrays cannot establish completeness'; fi
done
expect_output 'offline empty flat array remains supported' '[]' ''

selector_bin="$TEST_TMP/selector-bin"
mkdir -p "$selector_bin"
cat > "$selector_bin/gh" <<'STUB'
#!/usr/bin/env bash
printf 'called\n' >> "$STUB_SELECTOR_CALLS"
printf '{"total_count":0,"workflow_runs":[]}\n'
STUB
chmod +x "$selector_bin/gh"
printf 'not-json\n' > "$TEST_TMP/invalid-first.json"
printf '[]\n' > "$TEST_TMP/valid-second.json"
for selector in input repo branch head-sha; do
  for first_kind in valid empty; do
    case "$selector" in
      input) first_value="$TEST_TMP/invalid-first.json"; second_value="$TEST_TMP/valid-second.json"
        args=(--input "$first_value" --input "$second_value") ;;
      repo) first_value=devantler-tech/example; second_value=$first_value
        args=(--repo "$first_value" --repo "$second_value" --branch main --head-sha 0123456789abcdef0123456789abcdef01234567) ;;
      branch) first_value=main; second_value=$first_value
        args=(--branch "$first_value" --branch "$second_value" --repo devantler-tech/example --head-sha 0123456789abcdef0123456789abcdef01234567) ;;
      head-sha) first_value=0123456789abcdef0123456789abcdef01234567; second_value=$first_value
        args=(--head-sha "$first_value" --head-sha "$second_value" --repo devantler-tech/example --branch main) ;;
    esac
    if [ "$first_kind" = empty ]; then args[1]=''; fi
    rm -f "$TEST_TMP/selector-calls"
    out='' status=0
    out=$(PATH="$selector_bin:$PATH" STUB_SELECTOR_CALLS="$TEST_TMP/selector-calls" \
      "$CLASSIFIER" "${args[@]}" 2>"$TEST_TMP/stderr") || status=$?
    if [ "$status" -eq 2 ] && [ -z "$out" ] && [ ! -e "$TEST_TMP/selector-calls" ]; then
      pass=$((pass + 1))
    else
      record_failure "repeated $selector with $first_kind first value refuses before collection"
    fi
  done
done

if [ "$fail" -ne 0 ]; then
  printf '%s passed, %s failed\n' "$pass" "$fail" >&2
  exit 1
fi

printf '%s passed, 0 failed\n' "$pass"
