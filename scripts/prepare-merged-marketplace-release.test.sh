#!/usr/bin/env bash
# Real Git proposals and a narrow offline HTTP boundary; no repository writes.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tool="$root/scripts/prepare-merged-marketplace-release.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
export FORGE="$work/forge" CALLS="$work/calls" FAULT=none
mkdir "$work/bin" "$FORGE"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$#" -eq 4 ] && [ "$1" = api ] && [ "$2" = --hostname ] && [ "$3" = github.com ] || exit 90
endpoint=$4
printf '%s\n' "$endpoint" >> "$CALLS"
case "$endpoint" in
  repos/example/catalogue) file=repo ;;
  repos/example/catalogue/git/ref/heads/main) file=ref ;;
  repos/example/catalogue/actions/runs/42) file=run ;;
  "repos/example/catalogue/actions/workflows/ci.yaml/runs?branch=main&event=push&head_sha=$FIXTURE_RELEASE&per_page=1") file=latest ;;
  *) exit 91 ;;
esac
count=$(awk -v endpoint="$endpoint" '$0==endpoint {n++} END {print n+0}' "$CALLS")
[ "$FAULT" != transport ] || exit 92
if [ "$file" = latest ]; then
  case "$FAULT:$count" in
    latest-empty:*) printf '{"total_count":0,"workflow_runs":[]}\n' ;;
    latest-malformed:*) printf '{}\n' ;;
    latest-trailing:*) printf '{}\n{}\n' ;;
    latest-invalid-id:*) printf '{"total_count":1,"workflow_runs":[{"id":"evil"}]}\n' ;;
    latest-moved:2) printf '{"total_count":1,"workflow_runs":[{"id":43}]}\n' ;;
    *) jq -n --slurpfile run "$FORGE/run" '{total_count:1,workflow_runs:$run}' ;;
  esac
  exit 0
fi
change=.
case "$FAULT:$file:$count" in
  wrong-ci:run:*|ci-after:run:2) change='.head_sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' ;;
  running:run:*|running-after:run:2) change='.status="in_progress" | .conclusion=null' ;;
  failed:run:*) change='.conclusion="failure"' ;;
  neutral:run:*) change='.conclusion="neutral"' ;;
  pr:run:*) change='.event="pull_request"' ;;
  branch:run:*) change='.head_branch="feature"' ;;
  workflow:run:*) change='.path=".github/workflows/other.yaml"' ;;
  run-id:run:*) change='.id=43' ;;
  foreign-run:run:*) change='.repository.full_name="other/catalogue"' ;;
  fork-run:run:*) change='.head_repository.full_name="other/catalogue"' ;;
  missing-run:run:*) change='del(.head_repository)' ;;
  moved:ref:*|moved-after:ref:2) change='.object.sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' ;;
  tag-ref:ref:*) change='.object.type="tag"' ;;
  wrong-ref:ref:*) change='.ref="refs/heads/feature"' ;;
  foreign-repo:repo:*) change='.full_name="other/catalogue"' ;;
  archived:repo:*) change='.archived=true' ;;
  default-branch:repo:*) change='.default_branch="trunk"' ;;
  malformed:*:*) printf 'not json\n'; exit 0 ;;
  empty:*:*) exit 0 ;;
esac
jq "$change" "$FORGE/$file"
[ "$FAULT" != trailing ] || printf '{}\n'
STUB
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"
passed=0
# Fail when an observable safety or output contract is violated.
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
# Use independent version and history fixtures with real preparation and commits.
fixture() {
  repo=$(mktemp -d "$work/repo.XXXXXX")
  git -C "$repo" init -q
  git -C "$repo" config user.name Test
  git -C "$repo" config user.email test@example.invalid
  mkdir -p "$repo/.github/plugin" "$repo/.claude-plugin"
  printf '%s\n' '{"name":"test","metadata":{"version":"1.2.3"},"plugins":[{"name":"example","version":"4.5.6","source":"./plugins/example"}]}' > "$repo/.github/plugin/marketplace.json"
  cp "$repo/.github/plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
  git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json
  git -C "$repo" commit -qm 'Initial import'
  git -C "$repo" tag v1.2.3
  git -C "$repo" commit --allow-empty -qm 'feat: capability'
  source=$(git -C "$repo" rev-parse HEAD)
  candidate=$(mktemp -d "$work/holder.XXXXXX")/candidate
  (cd "$repo" && bash "$root/scripts/prepare-marketplace-release.sh" --base-tag v1.2.3 --head "$source" --output "$candidate") >/dev/null
  cp "$candidate/.github/plugin/marketplace.json" "$repo/.github/plugin/marketplace.json"
  cp "$candidate/.claude-plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
  git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json
  git -C "$repo" commit -qm 'chore(release): prepare marketplace 1.3.0'
  release=$(git -C "$repo" rev-parse HEAD)
  refresh
}
# Bind the offline forge to the actual committed fixture, with a fixed successful CI identity.
refresh() {
  FAULT=none; : > "$CALLS"
  export FIXTURE_RELEASE="$release"
  CI_SELECTION=42
  jq -n '{full_name:"example/catalogue",default_branch:"main",archived:false}' > "$FORGE/repo"
  jq -n --arg head "$release" '{ref:"refs/heads/main",object:{type:"commit",sha:$head}}' > "$FORGE/ref"
  jq -n --arg head "$release" '{id:42,path:".github/workflows/ci.yaml",event:"push",status:"completed",conclusion:"success",head_branch:"main",head_sha:$head,repository:{full_name:"example/catalogue"},head_repository:{full_name:"example/catalogue"}}' > "$FORGE/run"
  output=$(mktemp -d "$work/output.XXXXXX")/candidate
}
# Execute the real orchestrator, keeping only the forge HTTP boundary replaced.
run() { (cd "$repo" && bash "$tool" --repo example/catalogue --release "$release" --ci-run "$CI_SELECTION" --output "$output"); }
# Refusals must produce neither success output nor a usable candidate.
reject() {
  local name=$1
  if run > "$work/result" 2> "$work/error"; then fail "$name accepted"; fi
  [ ! -s "$work/result" ] || fail "$name emitted success"
  [ ! -e "$output" ] || fail "$name left a candidate"
  passed=$((passed+1))
}
# A ready result must bind both commits and the named CI; it never grants publication.
accept() {
  local name=$1 status=$2
  run > "$work/result" 2> "$work/error" || { cat "$work/error"; fail "$name rejected"; }
  jq -e --arg status "$status" --arg head "$release" '.status==$status and .releaseCommit==$head and .ciRunId==42 and .publication=="NOT_AUTHORIZED"' "$work/result" >/dev/null || fail "$name result"
  if [ "$status" = VERIFIED ]; then
    jq -e --arg source "$source" '.sourceCommit==$source and .version=="1.3.0"' "$work/result" >/dev/null || fail "$name proposal"
    cmp "$candidate/.github/plugin/marketplace.json" "$output/.github/plugin/marketplace.json"
    cmp "$candidate/.claude-plugin/marketplace.json" "$output/.claude-plugin/marketplace.json"
  else
    [ ! -e "$output" ] || fail "$name emitted a candidate"
  fi
  passed=$((passed+1))
}
fixture; FAULT=wrong-ci; reject 'green CI at an unrelated commit'
fixture; accept 'exact merged proposal' VERIFIED
for fault in running failed neutral pr branch workflow run-id foreign-run fork-run missing-run moved tag-ref wrong-ref foreign-repo archived default-branch malformed empty trailing transport ci-after running-after moved-after; do
  fixture; FAULT=$fault; reject "$fault"
done
fixture
git -C "$repo" status --porcelain > "$work/status-before"
git -C "$repo" show-ref > "$work/refs-before"
accept 'read-only repository state' VERIFIED
git -C "$repo" status --porcelain > "$work/status-after"
git -C "$repo" show-ref > "$work/refs-after"
cmp "$work/status-before" "$work/status-after"; cmp "$work/refs-before" "$work/refs-after"
fixture; release=$source; git -C "$repo" checkout -q "$source"; refresh; accept 'ordinary commit' NO_VERSION_CHANGE
fixture; printf 'unrelated\n' > "$repo/extra"; git -C "$repo" add extra; git -C "$repo" commit --amend --no-edit -q; release=$(git -C "$repo" rev-parse HEAD); refresh; reject 'extra content in proposal'
fixture; git -C "$repo" tag v1.3.0 "$release"; reject 'occupied release tag'
fixture; release=HEAD; reject 'symbolic release'
fixture; release=$(git -C "$repo" rev-parse 'HEAD^{tree}'); refresh; reject 'tree instead of commit'
fixture; git -C "$repo" rev-parse HEAD > "$repo/.git/shallow"; reject 'shallow history'
fixture; git -C "$repo" config remote.origin.promisor true; reject 'partial history'
fixture; release=$(printf 'merge\n' | git -C "$repo" commit-tree "$release^{tree}" -p "$source" -p "$(git -C "$repo" rev-parse v1.2.3)"); refresh; reject 'multiple parents'
fixture; git -C "$repo" checkout -q "$source"; reject 'checkout differs from selected release'
fixture; mkdir "$output"; printf 'preserve\n' > "$output/owned"
if run > "$work/result" 2> "$work/error"; then fail 'pre-existing candidate directory accepted'; fi
if [ -s "$work/result" ] || [ "$(cat "$output/owned")" != preserve ]; then fail 'pre-existing output changed'; fi
passed=$((passed+1))
fixture; CI_SELECTION=latest; accept 'latest exact main CI' VERIFIED
for fault in latest-empty latest-malformed latest-trailing latest-invalid-id latest-moved; do
  fixture; CI_SELECTION=latest; FAULT=$fault; reject "$fault"
done
fixture; CI_SELECTION=latest; FAULT=running; reject 'latest CI is pending'
fixture; CI_SELECTION=latest; FAULT=wrong-ci; reject 'latest list cannot bless unrelated CI'
printf 'PASS %s merged marketplace preparation cases\n' "$passed"
