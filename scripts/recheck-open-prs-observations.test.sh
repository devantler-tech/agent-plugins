#!/usr/bin/env bash
# Exercise real recheck control flow; the only forge is an offline stateful gh.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT=${RECHECK_SCRIPT:-$HERE/recheck-open-prs.sh}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0
# Create an isolated, stateful forge fixture for one observation or recovery case.
make_case() {
  local dir=$1 mode=$2
  mkdir -p "$dir/bin" "$dir/db" "$dir/temp"
  printf '%s' "$mode" > "$dir/mode"
  jq -nc '[{number:11,title:"first",state:"open",base:{ref:"main",repo:{full_name:"owner/name"}}}]' > "$dir/list.json"
  jq -nc '{number:11,state:"OPEN",baseRefName:"main",headRefOid:("1"*40),baseRefOid:("2"*40),author:{login:"devantler"},isCrossRepository:true,autoMergeRequest:{mergeMethod:"SQUASH",commitHeadline:"Chosen subject",commitBody:"Chosen body"}}' > "$dir/db/pr.json"
  cat > "$dir/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
dir=${RECHECK_FIXTURE:?}
mode=$(cat "$dir/mode")
printf '%s\n' "${GH_HOST:-unset} $*" >> "$dir/calls"
filter=""; previous=""; slurp=false; paginate=false
for arg in "$@"; do
  [ "$previous" != --jq ] || filter=$arg
  [ "$arg" != --slurp ] || slurp=true
  [ "$arg" != --paginate ] || paginate=true
  previous=$arg
done
if "$slurp" && ! "$paginate"; then exit 2; fi
# Return the same raw or projected response shape requested from the fixture.
emit() {
  if [ -n "$filter" ]; then jq -r "$filter"; elif "$slurp"; then jq -s .; else cat; fi
}
if [ "$1" = api ]; then
  case "$*" in
    *actions/*runs*)
      if [ "$mode" = paginated-runs ]; then
        total=101; [ ! -f "$dir/db/reopened" ] || total=102
        jq -nc --argjson total "$total" \
          '[range(1;$total+1)|{id:.,event:"pull_request",head_sha:("1"*40),path:".github/workflows/ci.yaml",repository:{full_name:"owner/name"}}] as $runs |
           range(0;($total/100|ceil)) as $page | {total_count:$total,workflow_runs:$runs[$page*100:($page+1)*100]}' | emit
        exit 0
      fi
      fresh=false; [ ! -f "$dir/db/reopened" ] || fresh=true
      count=0; id=10; path=.github/workflows/ci.yaml; head=$(printf '%040d' 0 | tr 0 1)
      if "$fresh"; then count=1; id=20; fi
      if "$fresh" && [ "$mode" = wrong-workflow ]; then path=.github/workflows/other.yaml; fi
      if "$fresh" && [ "$mode" = workflow-ref ]; then path=.github/workflows/ci.yaml@refs/pull/11/merge; fi
      if "$fresh" && [ "$mode" = wrong-workflow-ref ]; then path=.github/workflows/other.yaml@main; fi
      if "$fresh" && [ "$mode" = empty-workflow-ref ]; then path=.github/workflows/ci.yaml@; fi
      if "$fresh" && [ "$mode" = newline-workflow ]; then path=$'.github/workflows/ci.yaml\n'; fi
      if "$fresh" && [ "$mode" = newline-workflow-ref ]; then path=$'.github/workflows/ci.yaml@main\n'; fi
      if "$fresh" && [ "$mode" = wrong-head ]; then head=$(printf '%040d' 0 | tr 0 3); fi
      if "$fresh" && [ "$mode" = incomplete-runs ]; then count=2; fi
      if "$fresh" && [ "$mode" = fractional-count ]; then count=1.000000000000000001; fi
      if "$fresh"; then
        jq -nc --arg path "$path" --arg head "$head" --argjson id "$id" --argjson count "$count" \
          '{total_count:$count,workflow_runs:[{id:$id,event:"pull_request",head_sha:$head,path:$path,repository:{full_name:"owner/name"}}]}' | emit
      else jq -nc '{total_count:0,workflow_runs:[]}' | emit; fi
      exit 0 ;;
    *branches/*) jq -nc '{commit:{sha:("2"*40)}}' | emit; exit 0 ;;
    *pulls*) cat "$dir/list.json" | emit; exit 0 ;;
  esac
fi
if [ "$1" = pr ]; then
  case "$2" in
    view) cat "$dir/db/pr.json" | emit ;;
    close)
      printf '%s\n' close >> "$dir/mutations"
      jq '.state="CLOSED" | .autoMergeRequest=null' "$dir/db/pr.json" > "$dir/db/next"
      mv "$dir/db/next" "$dir/db/pr.json" ;;
    reopen)
      printf '%s\n' reopen >> "$dir/mutations"
      if [ "$mode" = recovery-noop ]; then
        if [ ! -f "$dir/db/reopen-attempted" ]; then : > "$dir/db/reopen-attempted"; exit 1; fi
        exit 0
      fi
      jq '.state="OPEN"' "$dir/db/pr.json" > "$dir/db/next"
      mv "$dir/db/next" "$dir/db/pr.json"
      : > "$dir/db/reopened" ;;
    merge)
      printf '%s\n' merge >> "$dir/mutations"
      subject=""; body=""; method=SQUASH; prev=""
      for arg in "$@"; do
        case "$prev" in --subject) subject=$arg ;; --body) body=$arg ;; --body-file) body=$(cat "$arg"; printf x); body=${body%x} ;; esac
        case "$arg" in --merge) method=MERGE ;; --rebase) method=REBASE ;; esac
        prev=$arg
      done
      jq --arg subject "$subject" --arg body "$body" --arg method "$method" \
        '.autoMergeRequest={mergeMethod:$method,commitHeadline:$subject,commitBody:$body}' "$dir/db/pr.json" > "$dir/db/next"
      mv "$dir/db/next" "$dir/db/pr.json" ;;
    *) exit 2 ;;
  esac
  exit 0
fi
exit 2
STUB
  chmod +x "$dir/bin/gh"
}
# Run the production entrypoint with fixture-only dependencies and capture its status.
run_case() {
  local dir=$1
  shift
  rc=0
  out=$(env PATH="$dir/bin:$PATH" TMPDIR="$dir/temp" RECHECK_FIXTURE="$dir" GH_HOST=enterprise.invalid \
    RECHECK_REAL_MKDIR="$(command -v mkdir)" RECHECK_CHECK_WAIT_SECONDS=1 RECHECK_CHECK_POLL_SECONDS=1 \
    bash "$SCRIPT" --repo owner/name "$@" 2>&1) || rc=$?
}
# Record each behavioral assertion without stopping later independent cases.
check() {
  local name=$1
  shift
  if "$@"; then printf 'PASS %s\n' "$name"; else printf 'FAIL %s (exit=%s)\n%s\n' "$name" "$rc" "$out"; fail=$((fail+1)); fi
}
# Prove an invalid observation caused no forge mutations.
no_mutations() { [ ! -s "$1/mutations" ]; }
# Prove every request used this automation's designated forge.
github_host_only() { ! grep -v '^github.com ' "$1/calls"; }
# Prove an uncertain run observation refused to restore auto-merge.
held_without_rearm() { [ "$rc" -ne 0 ] && ! jq -e '.autoMergeRequest!=null' "$1/db/pr.json" >/dev/null; }

d="$WORK/imprecise-jq"; make_case "$d" good
cat > "$d/bin/jq" <<'STUB'
#!/usr/bin/env bash
# Model a valid jq executable whose numeric parser rounds fractional counts.
case "$*" in *1.000000000000000001*) printf 'false\n'; exit 1 ;; esac
exec "$RECHECK_REAL_JQ" "$@"
STUB
chmod +x "$d/bin/jq"
RECHECK_REAL_JQ=$(command -v jq); export RECHECK_REAL_JQ
run_case "$d" --dry-run
check 'imprecise jq is rejected before any forge request' test "$rc" -eq 2
check 'imprecise jq cannot read or mutate any PR' test ! -e "$d/calls"

d="$WORK/host"; make_case "$d" good; run_case "$d" --dry-run
check 'github.com is the explicit forge for every request' github_host_only "$d"

d="$WORK/inventory"; make_case "$d" good
jq '. + [{number:"invalid",title:"later",state:"open",base:{ref:"main",repo:{full_name:"owner/name"}}}]' "$d/list.json" > "$d/next"
mv "$d/next" "$d/list.json"; run_case "$d"
check 'malformed later PR prevents all earlier PR mutations' no_mutations "$d"

d="$WORK/duplicate"; make_case "$d" good
jq '. + .' "$d/list.json" > "$d/next"; mv "$d/next" "$d/list.json"; run_case "$d"
check 'duplicate PR identities prevent all mutations' no_mutations "$d"

for mode in wrong-repository wrong-base nonpositive-number; do
  d="$WORK/$mode"; make_case "$d" good
  case "$mode" in
    wrong-repository) filter='.[0].base.repo.full_name="other/name"' ;;
    wrong-base) filter='.[0].base.ref="other"' ;;
    *) filter='.[0].number=0' ;;
  esac
  jq "$filter" "$d/list.json" > "$d/next"; mv "$d/next" "$d/list.json"; run_case "$d"
  check "$mode inventory prevents all PR mutations" no_mutations "$d"
done

for mode in wrong-workflow wrong-workflow-ref empty-workflow-ref newline-workflow newline-workflow-ref wrong-head incomplete-runs fractional-count; do
  d="$WORK/$mode"; make_case "$d" "$mode"; run_case "$d"
  check "$mode cannot authorize auto-merge" held_without_rearm "$d"
done

d="$WORK/workflow-ref"; make_case "$d" workflow-ref; run_case "$d"
check 'documented workflow path with a ref suffix can certify a fresh CI event' test "$rc" -eq 0

d="$WORK/pagination"; make_case "$d" paginated-runs; run_case "$d"
check 'fresh CI on a complete multi-page run inventory succeeds' test "$rc" -eq 0
check 'fresh-run requests select the native CI workflow' grep -q '/actions/workflows/ci.yaml/runs' "$d/calls"

d="$WORK/metadata"; make_case "$d" good
jq '.autoMergeRequest.commitHeadline="Chosen subject\n\n" | .autoMergeRequest.commitBody="Chosen body\n\n"' "$d/db/pr.json" > "$d/next"
mv "$d/next" "$d/db/pr.json"; run_case "$d"
check 'commit metadata retains every trailing newline' jq -e '.autoMergeRequest.commitHeadline=="Chosen subject\n\n" and .autoMergeRequest.commitBody=="Chosen body\n\n"' "$d/db/pr.json"

d="$WORK/journal"; make_case "$d" good
cat > "$d/bin/mkdir" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do case "$arg" in */rearm/11) exit 1 ;; esac; done
exec "$RECHECK_REAL_MKDIR" "$@"
STUB
chmod +x "$d/bin/mkdir"; run_case "$d"
check 'failed recovery journal prevents closing the PR' no_mutations "$d"

d="$WORK/recovery"; make_case "$d" recovery-noop; run_case "$d"
check 'acknowledged recovery reopen is read back before reporting recovery' awk \
  '/pr reopen/ {seen=1; verified=0} seen && /pr view .*--json state/ {verified=1} END {exit !verified}' "$d/calls"
# Verify unresolved recovery keeps the operator's original settings on disk.
retained_recovery() {
  local before
  before=$(find "${2:-$1/temp}" -name before -type f) || return 1
  [ -n "$before" ] && jq -e '.autoMergeRequest.commitBody=="Chosen body"' "$before" >/dev/null
}
check 'unresolved recovery retains the original merge settings for the operator' retained_recovery "$d"
check 'incomplete CI observations retain the original merge settings for the operator' retained_recovery "$WORK/incomplete-runs"

d="$WORK/collection"; make_case "$d" incomplete-runs
collection=${RECHECK_OBSERVATION_ARTIFACT_DIR:-$WORK/collected-records}
RECHECK_RECOVERY_ROOT="$collection" run_case "$d"
check 'held settings survive the process in the caller-designated artifact directory' retained_recovery "$d" "$collection"

d="$WORK/collection-failure"; make_case "$d" good
: > "$d/not-a-directory"
RECHECK_RECOVERY_ROOT="$d/not-a-directory" run_case "$d"
check 'unwritable recovery collection rejects the sweep before any forge request' test ! -e "$d/calls"

printf 'recheck observations: %s failure(s)\n' "$fail"
[ "$fail" -eq 0 ]
