#!/usr/bin/env bash
# Bound original-byte validation on ordinary large, paginated Actions responses.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if command -v timeout >/dev/null 2>&1; then deadline=timeout
elif command -v gtimeout >/dev/null 2>&1; then deadline=gtimeout
else echo 'json-stream performance test requires timeout or gtimeout' >&2; exit 1; fi

for size in 262144 524288 4194304; do
  # A long string exercises the scan; trailing LFs must survive byte for byte.
  LC_ALL=C awk -v size="$size" 'BEGIN {
    printf "{\"padding\":\""; for (i=0; i<size; i++) printf "x"; printf "\"}\n\n"
  }' > "$work/input"
  budget=10
  # Multi-megabyte retention includes two iconv passes and shell pipe transfers.
  if [[ $size -gt 524288 ]]; then budget=30; fi
  # shellcheck disable=SC2016 # The child shell expands its own positional argument.
  "$deadline" "$budget" bash -c '. "$1"; json_stream_retain_raw' _ "$here/json-stream.lib.sh" \
    < "$work/input" > "$work/output" || {
      echo "raw validation exceeded its deadline or failed at $size bytes" >&2; exit 1;
    }
  cmp "$work/input" "$work/output"
  if [[ $size == 524288 ]]; then cp "$work/input" "$work/observer-input"; fi
done

# The real observer must keep a large remote page complete, not merely finish
# the raw guard. A failed producer and an incomplete census still stay UNKNOWN.
mkdir "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
cat "$FORGE_BYTES"
exit "${FORGE_EXIT:-0}"
STUB
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" FORGE_BYTES="$work/pages"
jq -n --rawfile padding "$work/observer-input" '[
  {total_count:2,workflow_runs:[{id:1,run_attempt:1,workflow_id:3,event:"push",status:"completed",conclusion:"success",created_at:"2026-10-04T00:00:00Z",head_sha:"1111111111111111111111111111111111111111",head_branch:"main",name:$padding}]},
  {total_count:2,workflow_runs:[{id:2,run_attempt:1,workflow_id:4,event:"push",status:"completed",conclusion:"failure",created_at:"2026-10-04T00:00:00Z",head_sha:"1111111111111111111111111111111111111111",head_branch:"main",name:"check",html_url:"https://github.com/devantler-tech/example/actions/runs/2"}]}
]' > "$work/pages"
observe() {
  "$deadline" 30 bash "$here/classify-default-branch-ci-runs.sh" --repo devantler-tech/example \
    --branch main --head-sha 1111111111111111111111111111111111111111 > "$work/out" 2> "$work/err"
}
observe
[[ $(wc -l < "$work/out") -eq 1 && $(cut -f1,2 "$work/out") == $'4\tfailure' ]]
export FORGE_EXIT=17
rc=0; observe || rc=$?
[[ $rc == 2 && ! -s $work/out ]]
export FORGE_EXIT=0
jq '.[1].workflow_runs=[]' "$work/pages" > "$work/incomplete"
export FORGE_BYTES="$work/incomplete"
rc=0; observe || rc=$?
[[ $rc == 2 && ! -s $work/out ]]
echo 'json-stream performance: PASS (bounded large bytes and complete observer results)'
