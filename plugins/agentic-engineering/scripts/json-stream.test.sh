#!/usr/bin/env bash
# Exercise original-byte retention and EOF uniqueness through installed observers.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=plugins/agentic-engineering/scripts/json-stream.lib.sh
. "$here/json-stream.lib.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for source in '{"a":1,"a":2,"b":1}' '{"a":{"b":1},"a":null}' '{"":1,"":2}' '{"a":{},"a":{}}'; do
  if printf '%s' "$source" | json_stream_unique; then
    echo 'duplicate field admitted at EOF' >&2; exit 1
  fi
  if printf '%s\n' "$source" | json_stream_unique; then
    echo 'duplicate field admitted with newline' >&2; exit 1
  fi
done
for source in '{"a":1}' '{"a":"東京 café �"}' $'{"a":1}\n{"a":2}' '{"a":"escaped\u0000text"}'; do
  printf '%s' "$source" | json_stream_unique
  printf '%s\n' "$source" | json_stream_unique
done
mkdir "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
cat "$FORGE_BYTES"
exit "${FORGE_EXIT:-0}"
STUB
chmod +x "$work/bin/gh"
export FORGE_BYTES="$work/bytes"
export PATH="$work/bin:$PATH"
ci_prefix='{"total_count":1,"workflow_runs":[{"id":1,"run_attempt":1,"workflow_id":2,"event":"push","status":"completed","conclusion":"success","created_at":"2026-10-04T00:00:00Z","head_sha":"1111111111111111111111111111111111111111","head_branch":"main","name":"'
ci_suffix='"}]}'
thread_prefix='{"data":{"repository":{"nameWithOwner":"devantler-tech/example","pullRequest":{"number":1,"reviewThreads":{"totalCount":1,"nodes":[{"isResolved":true,"id":"'
thread_suffix='"}],"pageInfo":{"hasNextPage":false,"endCursor":"cursor"}}}}}}'
for kind in valid valid-max invalid truncated range surrogate overlong five-byte six-byte nul-middle nul-start nul-end failed-producer; do
  for observer in ci threads; do
    case "$observer" in ci) prefix=$ci_prefix; suffix=$ci_suffix ;; *) prefix=$thread_prefix; suffix=$thread_suffix ;; esac
    export FORGE_EXIT=0
    case "$kind" in
      valid) printf '%s東京 café �%s' "$prefix" "$suffix" > "$work/bytes" ;;
      valid-max) printf '%s\364\217\277\277%s' "$prefix" "$suffix" > "$work/bytes" ;;
      invalid) printf '%sbad\377text%s' "$prefix" "$suffix" > "$work/bytes" ;;
      truncated) printf '%sbad\302%s' "$prefix" "$suffix" > "$work/bytes" ;;
      range) printf '%s\364\220\200\200%s' "$prefix" "$suffix" > "$work/bytes" ;;
      surrogate) printf '%s\355\240\200%s' "$prefix" "$suffix" > "$work/bytes" ;;
      overlong) printf '%s\360\200\200\200%s' "$prefix" "$suffix" > "$work/bytes" ;;
      five-byte) printf '%s\370\210\200\200\200%s' "$prefix" "$suffix" > "$work/bytes" ;;
      six-byte) printf '%s\374\204\200\200\200\200%s' "$prefix" "$suffix" > "$work/bytes" ;;
      nul-middle) printf '%sbad\000text%s' "$prefix" "$suffix" > "$work/bytes" ;;
      nul-start) printf '\000%svalid%s' "$prefix" "$suffix" > "$work/bytes" ;;
      nul-end) printf '%svalid%s\000' "$prefix" "$suffix" > "$work/bytes" ;;
      failed-producer) printf '%svalid%s' "$prefix" "$suffix" > "$work/bytes"; export FORGE_EXIT=17 ;;
    esac
    rc=0
    if [[ $observer == ci ]]; then
      bash "$here/classify-default-branch-ci-runs.sh" --repo devantler-tech/example --branch main \
        --head-sha 1111111111111111111111111111111111111111 > "$work/out" 2> "$work/err" || rc=$?
      if [[ $kind == valid* ]]; then [[ $rc == 0 && ! -s $work/out ]];
      else [[ $rc == 2 && ! -s $work/out ]]; fi
      # The local path must inspect the same bytes, independent of gh.
      if [[ $kind != failed-producer ]]; then
        rc=0
        bash "$here/classify-default-branch-ci-runs.sh" --input "$work/bytes" > "$work/out" 2> "$work/err" || rc=$?
        if [[ $kind == valid* ]]; then [[ $rc == 0 && ! -s $work/out ]];
        else [[ $rc == 2 && ! -s $work/out ]]; fi
      fi
    else
      bash "$here/count-unresolved-review-threads.sh" --repo devantler-tech/example --pr 1 > "$work/out" 2> "$work/err" || rc=$?
      if [[ $kind == valid* ]]; then [[ $rc == 0 && $(cat "$work/out") == 'unresolved=0 total=1' ]];
      else [[ $rc == 2 && $(cat "$work/out") == UNKNOWN* && $(cat "$work/out") != *unresolved=* ]]; fi
    fi
  done
done
# A literal filename '-' remains a named file, never a substitute stdin producer.
mkdir "$work/dash"
printf '%snamed file%s' "$ci_prefix" "$ci_suffix" | jq '.workflow_runs[0].conclusion="failure"' > "$work/dash/-"
printf '%sstdin%s' "$ci_prefix" "$ci_suffix" > "$work/stdin"
(cd "$work/dash" && bash "$here/classify-default-branch-ci-runs.sh" --input - < "$work/stdin") > "$work/out"
IFS=$'\t' read -r workflow conclusion _rest < "$work/out"
[[ $workflow == 2 && $conclusion == failure ]] || { echo 'named dash input was substituted by stdin' >&2; exit 1; }
echo 'json-stream: PASS (raw bytes, producer status and EOF uniqueness)'
