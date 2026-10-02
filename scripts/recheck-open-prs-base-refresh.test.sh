#!/usr/bin/env bash
# Exercise the production sweep against real local commit ancestry and a hermetic forge.
set -euo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
here=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
git init -q "$work/repo"
git -C "$work/repo" config user.name Fixture
git -C "$work/repo" config user.email fixture@example.invalid
git -C "$work/repo" commit -qm initial --allow-empty
original=$(git -C "$work/repo" rev-parse HEAD)
git -C "$work/repo" checkout -qb base
printf 'gate\n' > "$work/repo/gate"
git -C "$work/repo" add gate
git -C "$work/repo" commit -qm gate
base=$(git -C "$work/repo" rev-parse HEAD)
git -C "$work/repo" checkout -qb candidate "$original"
printf 'adaptation\n' > "$work/repo/adaptation"
git -C "$work/repo" add adaptation
git -C "$work/repo" commit -qm adaptation
head=$(git -C "$work/repo" rev-parse HEAD)
git -C "$work/repo" merge -qm refresh base
updated=$(git -C "$work/repo" rev-parse HEAD)
git -C "$work/repo" checkout -qb later base
printf 'later gate\n' > "$work/repo/gate"
git -C "$work/repo" add gate
git -C "$work/repo" commit -qm later
later=$(git -C "$work/repo" rev-parse HEAD)
mkdir "$work/bin"
cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FIXTURE/calls"
if [[ "$*" == *'/actions/runs'* ]]; then
  [[ "$MODE" != no-check ]] || { printf '0\n'; exit; }
  if [[ "$MODE" == late-movement ]]; then printf '%s' "$LATER" > "$FIXTURE/current"; fi
  if [[ "$MODE" == late-base ]]; then : > "$FIXTURE/later-base"; fi
  if [ -f "$FIXTURE/reopened" ]; then printf '92\n'; else printf '91\n'; fi
  exit
fi
if [[ "$*" == *'/branches/'* ]]; then
  [[ "$MODE" != branch-read-fails ]] || exit 1
  if [[ "$MODE" == dropped-base && -f "$FIXTURE/current" ]] || [ -f "$FIXTURE/later-base" ]; then
    printf '%s\n' "$LATER"
  elif [[ "$MODE" == invalid-base ]]; then printf 'unknown\n'
  else printf '%s\n' "$BASE"; fi
  exit
fi
if [[ "$*" == *'/compare/'* ]]; then
  [[ "$MODE" != compare-fails ]] || exit 1
  pair=${2##*/}; left=${pair%...*}; right=${pair#*...}
  git -C "$FIXTURE/repo" cat-file -e "$left^{commit}"
  git -C "$FIXTURE/repo" cat-file -e "$right^{commit}"
  if [ "$left" = "$right" ]; then printf 'identical\n'
  elif git -C "$FIXTURE/repo" merge-base --is-ancestor "$left" "$right"; then printf 'ahead\n'
  elif git -C "$FIXTURE/repo" merge-base --is-ancestor "$right" "$left"; then printf 'behind\n'
  else printf 'diverged\n'; fi
  exit
fi
if [[ "$*" == *'/update-branch'* ]]; then
  [[ "$*" == *'--method PUT'* && "$*" == *"expected_head_sha=$HEAD"* ]] || exit 3
  [[ "$MODE" != update-fails ]] || exit 1
  [[ "$MODE" != unchanged ]] || exit
  printf '%s' "$UPDATED" > "$FIXTURE/current"
  exit
fi
if [[ "$*" == *'api --paginate'* ]]; then printf '11\twanted update\n'; exit; fi
if [[ "$*" == *'pr view'* ]]; then
  [[ "$MODE" != unreadable-after-update || ! -f "$FIXTURE/current" ]] || exit 1
  current=$(cat "$FIXTURE/current" 2>/dev/null || printf '%s' "$HEAD")
  [[ "$MODE" != missing-author ]] && author='app/dependabot' || author=''
  if [[ "$MODE" == human || "$MODE" == current-human ]]; then author=devantler; fi
  [[ "$MODE" != missing-boundary ]] && fork=false || fork=null
  if [[ "$MODE" == dropped-adaptation && -f "$FIXTURE/current" ]]; then current=$BASE; fi
  current_base=$BASE
  if [[ "$MODE" == dropped-base && -f "$FIXTURE/current" ]]; then current_base=$LATER; fi
  jq -n --arg head "$current" --arg base "$BASE" --arg author "$author" --argjson fork "$fork" \
    '{number:11,baseRefName:"main",state:"OPEN",headRefOid:$head,baseRefOid:$base,author:{login:$author},isCrossRepository:$fork,
      autoMergeRequest:{mergeMethod:"SQUASH",commitHeadline:"original title",commitBody:"original body"}}' |
    jq --arg mode "$MODE" --arg base "$current_base" --arg original "$ORIGINAL" --argjson after "$(test -f "$FIXTURE/current" && echo true || echo false)" \
      --argjson reopened "$(test -f "$FIXTURE/reopened" && echo true || echo false)" --argjson rearmed "$(test -f "$FIXTURE/rearmed" && echo true || echo false)" \
      'if $mode=="missing-merge-state" then del(.autoMergeRequest)
       elif $mode=="unarmed" then .autoMergeRequest=null
       elif $mode=="missing-merge-after" then if $after then del(.autoMergeRequest) else .autoMergeRequest=null end
       elif $mode=="changed-merge-state" and $after then .autoMergeRequest=null
       elif $mode=="changed-boundary" and $after then .isCrossRepository=true
       elif $mode=="changed-author" and $after then .author.login="another-author"
       elif $mode=="wrong-pr" then .number=12
       elif $mode=="retargeted" then .baseRefName="different-base"
       else . end | .baseRefOid=(if $mode=="stale-pr-base" then $original else $base end)
       | if $reopened and ($rearmed | not) then .autoMergeRequest=null else . end'
  exit
fi
case "$1 $2" in
  'pr close') : > "$FIXTURE/closed"; exit ;;
  'pr reopen') rm -f "$FIXTURE/closed"; : > "$FIXTURE/reopened"; exit ;;
  'pr merge') : > "$FIXTURE/rearmed"; exit ;;
esac
printf 'unexpected mutation\n' >&2
exit 3
EOF
chmod +x "$work/bin/gh"
export FIXTURE="$work" BASE="$base" HEAD="$head" UPDATED="$updated" LATER="$later" ORIGINAL="$original"
run_case() {
  local mode=$1 expected=$2 rc=0
  export MODE="$mode"
  rm -f "$work/current" "$work/later-base"
  : > "$work/calls"
  PATH="$work/bin:$PATH" RECHECK_CHECK_WAIT_SECONDS=1 RECHECK_CHECK_POLL_SECONDS=1 \
    bash "$here/recheck-open-prs.sh" --repo owner/name > "$work/output" 2>&1 || rc=$?
  [ "$rc" -eq "$expected" ] || { cat "$work/output"; echo "FAIL $mode: exit $rc"; exit 1; }
  ! grep -Eq '^pr (close|reopen|merge)' "$work/calls" || { echo "FAIL $mode: changed open/merge state"; exit 1; }
  if [ "$expected" -eq 0 ]; then
    grep -q '/update-branch' "$work/calls"
    grep -q '/actions/runs' "$work/calls"
    test "$(git -C "$work/repo" show "$UPDATED:adaptation")" = adaptation
  else
    if grep -q '1 of 1 current-base refreshes completed' "$work/output"; then
      echo "FAIL $mode: falsely reported completion"; exit 1
    fi
  fi
  echo "PASS same-repository $mode"
}
run_case normal 0
run_case human 0
run_case unarmed 0
run_case stale-pr-base 0
run_case update-fails 1
run_case unchanged 1
run_case unreadable-after-update 1
run_case missing-merge-after 1
run_case dropped-adaptation 1
run_case dropped-base 1
run_case no-check 1
run_case compare-fails 1
run_case branch-read-fails 1
run_case invalid-base 1
run_case missing-author 1
run_case missing-boundary 1
run_case missing-merge-state 1
run_case changed-merge-state 1
run_case changed-boundary 1
run_case changed-author 1
run_case wrong-pr 1
run_case retargeted 1
run_case late-movement 1
run_case late-base 1
# A current Dependabot branch stays open, but its observed run certifies only that exact head/base.
export HEAD="$updated"
for mode in normal no-check late-movement late-base; do
  export MODE="$mode"
  rm -f "$work/current" "$work/later-base"
  : > "$work/calls"
  rc=0
  PATH="$work/bin:$PATH" RECHECK_CHECK_WAIT_SECONDS=1 RECHECK_CHECK_POLL_SECONDS=1 \
    bash "$here/recheck-open-prs.sh" --repo owner/name > "$work/output" 2>&1 || rc=$?
  expected=1
  [ "$mode" != normal ] || expected=0
  if [ "$rc" -ne "$expected" ] || grep -Eq '/update-branch|^pr (close|reopen|merge)' "$work/calls"; then
    cat "$work/output"; echo "FAIL current Dependabot $mode: exit $rc"; exit 1
  fi
  echo "PASS current Dependabot $mode"
done
# An existing run cannot certify a gate added later: the same head no longer contains the base.
export MODE=unchanged BASE="$later"
rm -f "$work/current" "$work/later-base"
: > "$work/calls"
rc=0
PATH="$work/bin:$PATH" RECHECK_CHECK_WAIT_SECONDS=1 RECHECK_CHECK_POLL_SECONDS=1 \
  bash "$here/recheck-open-prs.sh" --repo owner/name > "$work/output" 2>&1 || rc=$?
test "$rc" -eq 1
grep -q '/update-branch' "$work/calls"
if grep -Eq '^pr (close|reopen|merge)' "$work/calls"; then
  echo 'FAIL advanced gate: closed a wanted update'; exit 1
fi
echo 'PASS existing run cannot certify an advanced base at the unchanged head'
export BASE="$base"
# Native proposal drafts are created with GITHUB_TOKEN and need the App's reopened event.
export MODE=current-human
rm -f "$work/reopened" "$work/rearmed" "$work/current" "$work/later-base"
: > "$work/calls"
PATH="$work/bin:$PATH" RECHECK_CHECK_WAIT_SECONDS=1 RECHECK_CHECK_POLL_SECONDS=1 \
  bash "$here/recheck-open-prs.sh" --repo owner/name > "$work/output" 2>&1
test -f "$work/reopened"
test -f "$work/rearmed"
if grep -q '/update-branch' "$work/calls"; then echo 'FAIL current draft: unnecessary head movement'; exit 1; fi
echo 'PASS current non-Dependabot draft still receives a fresh reopen event'
