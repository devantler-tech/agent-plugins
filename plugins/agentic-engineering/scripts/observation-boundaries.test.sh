#!/usr/bin/env bash
# Exercise installed readers without network or inspected source execution.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
cat "$THREAD_INPUT"
STUB
chmod +x "$work/bin/gh"
failed=0
# Refused observations may emit UNKNOWN, never a successful count.
refuse_reader() {
 local status=0
 if [[ $1 == thread ]]; then
  THREAD_INPUT="$work/input" PATH="$work/bin:$PATH" bash "$here/count-unresolved-review-threads.sh" --repo devantler-tech/example --pr 42 > "$work/out" 2> "$work/err" || status=$?
  [[ $status == 2 && $(cat "$work/out") == UNKNOWN* ]] && return
 else
  bash "$here/classify-default-branch-ci-runs.sh" --input "$work/input" > "$work/out" 2> "$work/err" || status=$?
  [[ $status == 2 && ! -s $work/out ]] && return
 fi
 printf 'FAIL: %s ambiguity was accepted\n' "$1" >&2; failed=$((failed+1))
}
thread='{"data":{"repository":{"nameWithOwner":"devantler-tech/example","pullRequest":{"number":42,"reviewThreads":{"totalCount":1,"nodes":[{"id":"t1","isResolved":false}],"pageInfo":{"hasNextPage":false,"endCursor":"c1"}}}}}}'
printf '%s\n' "$thread" > "$work/input"
status=0
THREAD_INPUT="$work/input" PATH="$work/bin:$PATH" bash "$here/count-unresolved-review-threads.sh" --repo devantler-tech/example --pr 42 > "$work/out" || status=$?
[[ $status == 1 && $(cat "$work/out") == 'unresolved=1 total=1' ]]
for replacement in '"isResolved":false,"isResolved":true' '"isResolved":false,"is\u0052esolved":true'; do
 printf '%s\n' "${thread/\"isResolved\":false/$replacement}" > "$work/input"
 refuse_reader thread
done
first=${thread/\"hasNextPage\":false/\"hasNextPage\":true}
first=${first/\"totalCount\":1/\"totalCount\":2}
last=${thread/\"totalCount\":1/\"totalCount\":2}
last=${last/\"t1\"/\"t2\"}; last=${last/\"c1\"/\"c2\"}
printf '%s\n%s\n' "$first" "$last" > "$work/input"
status=0
THREAD_INPUT="$work/input" PATH="$work/bin:$PATH" bash "$here/count-unresolved-review-threads.sh" --repo devantler-tech/example --pr 42 > "$work/out" || status=$?
[[ $status == 1 && $(cat "$work/out") == 'unresolved=2 total=2' ]]
printf '%s\n%s\n' "$first" "${last/\"isResolved\":false/\"isResolved\":false,\"isResolved\":true}" > "$work/input"
refuse_reader thread
run='{"id":10,"run_attempt":1,"workflow_id":11,"event":"push","status":"completed","conclusion":"failure","created_at":"2026-10-04T09:00:00Z","name":"CI"}'
printf '[%s]\n' "$run" > "$work/input"
bash "$here/classify-default-branch-ci-runs.sh" --input "$work/input" > "$work/out"
[[ $(cat "$work/out") == *$'\tfailure\t'* ]]
for replacement in '"conclusion":"failure","conclusion":"success"' '"conclusion":"failure","conclu\u0073ion":"success"'; do
 printf '[%s]\n' "${run/\"conclusion\":\"failure\"/$replacement}" > "$work/input"
 refuse_reader ci
done
printf '{"workflow_runs":[%s]}\n{"workflow_runs":[],"workflow_runs":[]}\n' "$run" > "$work/input"
refuse_reader ci
[[ $failed == 0 ]] || exit 1
printf 'PASS: complete unambiguous retained review observations\n'
