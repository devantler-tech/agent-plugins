#!/usr/bin/env bash
# Run the publication workflow's actual assessment shell against an advanced checkout.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
awk '
  /^  assess:/ {assessment=1}
  /^  publish:/ {assessment=0}
  assessment && /^        id: prepare$/ {selected=1}
  selected && /^        run: \|$/ {reading=1; next}
  reading && /^          / {sub(/^          /,""); print; next}
  reading {exit}
' "$root/.github/workflows/publish-marketplace-release.yaml" > "$work/step"
[[ -s $work/step ]] || { echo 'FAIL: assessment step is unavailable' >&2; exit 1; }
git init -q "$work/repo"
git -C "$work/repo" config user.name 'Publication identity fixture'
git -C "$work/repo" config user.email fixture@example.invalid
git -C "$work/repo" config commit.gpgsign false
git -C "$work/repo" commit --allow-empty -qm baseline
dispatch=$(git -C "$work/repo" rev-parse HEAD)
git -C "$work/repo" commit --allow-empty -qm current
current=$(git -C "$work/repo" rev-parse HEAD)
mkdir "$work/repo/scripts" "$work/bin"
cat > "$work/repo/scripts/prepare-merged-marketplace-release.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'called\n' >> "$CALLED"
release= ci=
while (($#)); do
  case $1 in
    --release) release=$2; shift 2 ;;
    --ci-run) ci=$2; shift 2 ;;
    --repo|--output) shift 2 ;;
    *) exit 91 ;;
  esac
done
[[ $release == "$CURRENT" && $ci == latest ]] || exit 92
jq -n --arg release "$release" '{status:"NO_VERSION_CHANGE",releaseCommit:$release,ciRunId:42}'
STUB
cat > "$work/bin/git" <<'STUB'
#!/usr/bin/env bash
if [[ ${FAIL_HEAD:-false} == true && " $* " == *' rev-parse '* ]]; then
  printf '%s\n' "$CURRENT"
  exit 73
fi
exec "$REAL_GIT" "$@"
STUB
chmod +x "$work/bin/git"
real_git=$(command -v git)
pass=0 fail=0
for mode in ordinary queued wrong-ci failed-head; do
  : > "$work/called"; : > "$work/outputs"; : > "$work/summary"
  selected=$current; [[ $mode != queued ]] || selected=$dispatch
  ci=latest; [[ $mode != wrong-ci ]] || ci=41
  failed=false; [[ $mode != failed-head ]] || failed=true
  status=0
  (cd "$work/repo" && CALLED="$work/called" CURRENT="$current" REAL_GIT="$real_git" \
    FAIL_HEAD=$failed PATH="$work/bin:$PATH" RELEASE_COMMIT="$selected" CI_RUN=$ci \
    REPOSITORY=example/catalogue RUNNER_TEMP="$work" GITHUB_OUTPUT="$work/outputs" \
    GITHUB_STEP_SUMMARY="$work/summary" bash -euo pipefail "$work/step") \
    > "$work/out" 2> "$work/error" || status=$?
  ok=false
  case $mode in
    ordinary|queued)
      if [[ $status == 0 ]] && grep -qx "release=$current" "$work/outputs"; then ok=true; fi ;;
    wrong-ci) [[ $status != 0 && ! -s $work/outputs ]] && ok=true ;;
    failed-head) [[ $status != 0 && ! -s $work/called && ! -s $work/outputs ]] && ok=true ;;
  esac
  if [[ $ok == true ]]; then printf 'PASS: publication identity %s\n' "$mode"; pass=$((pass+1))
  else printf 'FAIL: publication identity %s (exit %s)\n' "$mode" "$status"; fail=$((fail+1)); fi
done
printf 'Publication identity controls: %s pass, %s fail\n' "$pass" "$fail"
[[ $fail == 0 ]]
