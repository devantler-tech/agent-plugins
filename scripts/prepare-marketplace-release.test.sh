#!/usr/bin/env bash
# Real Git histories catch incorrect version selection, baseline drift, and accidental writes.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tool="$root/scripts/prepare-marketplace-release.sh"
release_test_path=$PATH
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
passed=0
# Stop the suite when an observable preparation contract fails.
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
# Initialize an independent real Git history with matching marketplace manifests.
new_repo() {
  repo=$(mktemp -d "$work/repo.XXXXXX")
  git -C "$repo" init -q
  git -C "$repo" config user.name Test
  git -C "$repo" config user.email test@example.invalid
  mkdir -p "$repo/.github/plugin" "$repo/.claude-plugin"
  printf '%s\n' '{"name":"test-marketplace","metadata":{"version":"1.2.3","description":"Kept"},"plugins":[{"name":"example","version":"4.5.6","source":"./plugins/example","description":"Kept"}],"extra":{"keep":true}}' > "$repo/.github/plugin/marketplace.json"
  cp "$repo/.github/plugin/marketplace.json" "$repo/.claude-plugin/marketplace.json"
  git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json
  git -C "$repo" commit -qm 'Initial legacy import'
}
# Append the selected Conventional Commit to the independent fixture history.
commit() { git -C "$repo" commit --allow-empty -qm "$1"; }
# Invoke production preparation from the fixture's actual Git context.
run() { (cd "$repo" && bash "$tool" --base-tag "$1" --output "$2"); }
# Require the prepared artifact to carry the expected marketplace version.
expect_version() {
  local name=$1 want=$2 base=${3:-v1.2.3} out
  out=$(mktemp -u "$work/out.XXXXXX")
  run "$base" "$out" > "$work/stdout" 2> "$work/stderr" || { cat "$work/stderr"; fail "$name did not prepare"; }
  jq -e --arg want "$want" '.status=="CANDIDATE" and .version==$want and .tag==("v"+$want) and .publication=="NOT_AUTHORIZED"' "$out/release.json" >/dev/null || fail "$name version"
  for manifest in .github/plugin/marketplace.json .claude-plugin/marketplace.json; do
    jq -e --arg want "$want" '.metadata.version==$want and .metadata.description=="Kept" and .extra.keep and .plugins[0].version=="4.5.6"' "$out/$manifest" >/dev/null || fail "$name preserved plugin"
  done
  cmp "$out/.github/plugin/marketplace.json" "$out/.claude-plugin/marketplace.json"
  test "$(git -C "$repo" status --porcelain | wc -l | tr -d ' ')" = 0 || fail "$name changed checkout"
  passed=$((passed + 1))
}
# Require malformed input to fail without creating a candidate output.
reject() {
  local name=$1 base=${2:-v1.2.3} out
  out=$(mktemp -u "$work/rejected.XXXXXX")
  if run "$base" "$out" > "$work/stdout" 2> "$work/stderr"; then fail "$name accepted"; fi
  test ! -e "$out" || fail "$name left partial candidate"
  test ! -s "$work/stdout" || fail "$name emitted success output"
  passed=$((passed + 1))
}
new_repo
expect_version 'explicit first release' 1.2.3 initial
git -C "$repo" tag v1.2.3
for pair in 'fix: repair|1.2.4' 'feat(api): add|1.3.0' 'perf: speed|1.2.4' 'refactor!: remove|2.0.0' 'FEAT(API): add|1.3.0'; do
  new_repo; git -C "$repo" tag v1.2.3
  commit "${pair%|*}"; expect_version "${pair%|*}" "${pair#*|}"
done
for footer in 'BREAKING CHANGE: remove old option' 'BREAKING-CHANGE: remove old option'; do
  new_repo; git -C "$repo" tag v1.2.3
  commit "$(printf 'chore: adjust\n\n%s' "$footer")"; expect_version "$footer" 2.0.0
done
# A signature is not part of the message, so log.showSignature must not change what is classified.
# The commit carries a gpgsig header and a stub verifier prints the line git would prepend.
new_repo; git -C "$repo" tag v1.2.3
printf '#!/usr/bin/env bash\necho "Good signature from stub" >&2\n' > "$work/stub-gpg"; chmod +x "$work/stub-gpg"
signed=$(printf 'tree %s\nparent %s\nauthor Test <test@example.invalid> 1700000000 +0000\ncommitter Test <test@example.invalid> 1700000000 +0000\ngpgsig -----BEGIN PGP SIGNATURE-----\n \n stub\n -----END PGP SIGNATURE-----\n\nfix: signed\n' \
  "$(git -C "$repo" rev-parse 'HEAD^{tree}')" "$(git -C "$repo" rev-parse HEAD)" | git -C "$repo" hash-object -t commit -w --stdin)
git -C "$repo" update-ref HEAD "$signed"
git -C "$repo" config log.showSignature true; git -C "$repo" config gpg.program "$work/stub-gpg"
out="$work/signed"; run v1.2.3 "$out" > "$work/stdout" 2> "$work/stderr" || { cat "$work/stderr"; fail 'signed commit did not prepare'; }
jq -e '.version=="1.2.4" and .commits[0].subject=="fix: signed"' "$out/release.json" >/dev/null || fail 'signature output was read as the commit message'
passed=$((passed + 1))
# column.tag must not put several tags on one line, where no line reads as a stable tag.
new_repo; git -C "$repo" tag v1.2.1; git -C "$repo" tag v1.2.2; git -C "$repo" config column.tag always
reject 'column-formatted tags still block an initial release' initial
git -C "$repo" tag v1.2.3; commit 'fix: repair'; expect_version 'column-formatted tags still find the baseline' 1.2.4
# Messages are read as UTF-8 whatever output encoding the maintainer configured.
new_repo; git -C "$repo" tag v1.2.3
git -C "$repo" -c i18n.commitEncoding=ISO-8859-1 commit --allow-empty -qm "$(printf 'fix: caf\351')"
git -C "$repo" config i18n.logOutputEncoding ISO-8859-1
out="$work/latin1"; run v1.2.3 "$out" > "$work/stdout" 2> "$work/stderr" || { cat "$work/stderr"; fail 'Latin-1 commit did not prepare'; }
jq -e '.version=="1.2.4" and .commits[0].subject=="fix: café"' "$out/release.json" >/dev/null || fail 'commit message was not read as UTF-8'
passed=$((passed + 1))
new_repo; git -C "$repo" tag -a v1.2.3 -m baseline
commit 'fix: repair'; commit 'feat: add'; expect_version 'largest bump and annotated tag' 1.3.0
new_repo; git -C "$repo" tag v1.2.3; commit 'docs: explain'
out="$work/no-release"; run v1.2.3 "$out" >/dev/null
jq -e '.status=="NO_RELEASE" and .version==null and .tag==null' "$out/release.json" >/dev/null
test ! -e "$out/.github/plugin/marketplace.json" || fail 'no-release wrote update'
passed=$((passed + 1))
new_repo; git -C "$repo" tag v1.2.3; reject 'initial would reset published history' initial
commit 'Make it better'; reject 'ambiguous commit'
new_repo; git -C "$repo" tag v1.2.3; commit 'revert: undo feature'; reject 'revert requires assessment'
new_repo; git -C "$repo" tag v1.2.3
# Verbatim keeps the trailing spaces that git's default cleanup would strip.
git -C "$repo" commit --allow-empty --cleanup=verbatim -qm 'fix:  '; reject 'blank change description'
new_repo; git -C "$repo" tag v1000000000.0.0; reject 'unsupported stable tag cannot disappear' initial
new_repo; git -C "$repo" tag v1.2.3; commit 'fix: change'; git -C "$repo" tag v1.2.4; reject 'stale baseline'
new_repo; git -C "$repo" tag v1.2.3; reject 'missing tag' v9.9.9
reject 'option-like tag' --help
for mutation in '.metadata.version="01.2.3"' '.metadata.version="1.2.3-rc.1"' '.metadata.version=4' 'del(.metadata.version)' '.plugins=[]' '.plugins += [.plugins[0]]'; do
  new_repo
  jq "$mutation" "$repo/.github/plugin/marketplace.json" > "$work/bad.json"
  cp "$work/bad.json" "$repo/.github/plugin/marketplace.json"; cp "$work/bad.json" "$repo/.claude-plugin/marketplace.json"
  git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json; commit 'fix: malformed'
  reject "bad manifest $mutation" initial
done
new_repo; git -C "$repo" tag v1.2.3
jq '.metadata.version="1.2.4"' "$repo/.github/plugin/marketplace.json" > "$work/changed.json"
cp "$work/changed.json" "$repo/.github/plugin/marketplace.json"
git -C "$repo" add .github/plugin/marketplace.json; commit 'fix: one manifest changed'; reject 'manifest drift'
cp "$work/changed.json" "$repo/.claude-plugin/marketplace.json"
git -C "$repo" add .claude-plugin/marketplace.json; commit 'fix: both changed'; reject 'source version diverged from tag'
new_repo; git -C "$repo" tag v1.2.3; commit 'fix: keep selected source'
head=$(git -C "$repo" rev-parse HEAD)
printf 'dirty input ignored\n' > "$repo/.github/plugin/marketplace.json"
out="$work/immutable"; run v1.2.3 "$out" >/dev/null
jq -e --arg head "$head" '.sourceCommit==$head and .version=="1.2.4"' "$out/release.json" >/dev/null
grep -q 'dirty input ignored' "$repo/.github/plugin/marketplace.json"
passed=$((passed + 1))
out2="$work/repeated"; run v1.2.3 "$out2" >/dev/null; diff -r "$out" "$out2" >/dev/null
passed=$((passed + 1))
if run v1.2.3 "$out" > "$work/stdout" 2> "$work/stderr"; then fail 'existing output replaced'; fi
diff -r "$out" "$out2" >/dev/null; passed=$((passed + 1))

# Full history and an explicit source commit prevent accidental comparison to another branch.
new_repo; git -C "$repo" tag v1.2.3; commit 'fix: first'
selected=$(git -C "$repo" rev-parse HEAD); commit 'feat: later'
out="$work/selected-head"
(cd "$repo" && bash "$tool" --base-tag v1.2.3 --head "$selected" --output "$out") >/dev/null
jq -e --arg head "$selected" '.sourceCommit==$head and .version=="1.2.4" and (.commits|length)==1' "$out/release.json" >/dev/null
passed=$((passed + 1))
if (cd "$repo" && bash "$tool" --base-tag v1.2.3 --head main --output "$work/non-sha") > "$work/stdout" 2> "$work/stderr"; then fail 'non-immutable head accepted'; fi
test ! -e "$work/non-sha"; passed=$((passed + 1))
shallow="$work/shallow"
git clone -q --depth 1 "file://$repo" "$shallow"
repo=$shallow; reject 'shallow history' initial
# A filtered clone would lazily fetch missing objects, so the offline preparation must refuse it.
new_repo; git -C "$repo" config uploadpack.allowFilter true
partial="$work/partial"
git clone -q --filter=blob:none --no-checkout "file://$repo" "$partial"
repo=$partial; reject 'partial clone' initial
# The candidate must never land in the checkout it describes, relative or absolute.
new_repo
for inside in candidate "$repo/.github/candidate"; do
  if run initial "$inside" > "$work/stdout" 2> "$work/stderr"; then fail "output inside worktree accepted: $inside"; fi
  test "$(git -C "$repo" status --porcelain --ignored | wc -l | tr -d ' ')" = 0 || fail "output inside worktree changed checkout: $inside"
  test ! -s "$work/stdout" || fail "output inside worktree emitted success output: $inside"
  passed=$((passed + 1))
done
# A linked worktree is a checkout of the same repository too.
git -C "$repo" worktree add -q --detach "$work/linked"
if run initial "$work/linked/candidate" > "$work/stdout" 2> "$work/stderr"; then fail "output inside a linked worktree accepted"; fi
test ! -e "$work/linked/candidate" || fail "output inside a linked worktree was written"
test ! -s "$work/stdout" || fail "output inside a linked worktree emitted success output"
passed=$((passed + 1))
new_repo; first=$(git -C "$repo" rev-parse HEAD)
commit 'feat: branch-only'; git -C "$repo" tag v1.2.3
git -C "$repo" checkout -q --detach "$first"; commit 'fix: independent'
reject 'non-ancestor baseline'
new_repo; git -C "$repo" tag v1.2.3
commit 'fix: future'; git -C "$repo" tag v1.2.4
git -C "$repo" checkout -q --detach v1.2.3; commit 'fix: alternative'
reject 'candidate tag already exists on another branch'
new_repo; git -C "$repo" tag v1.2.2; commit 'fix: wrong tagged metadata'; reject 'tag disagrees with baseline metadata' v1.2.2
new_repo; git -C "$repo" tag v1.2.3
out="$work/empty-range"; run v1.2.3 "$out" >/dev/null
jq -e '.status=="NO_RELEASE" and (.commits|length)==0' "$out/release.json" >/dev/null
passed=$((passed + 1))
new_repo
jq '.metadata.version="1.2.999999999"' "$repo/.github/plugin/marketplace.json" > "$work/overflow.json"
cp "$work/overflow.json" "$repo/.github/plugin/marketplace.json"; cp "$work/overflow.json" "$repo/.claude-plugin/marketplace.json"
git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json; commit 'chore: baseline'; git -C "$repo" tag v1.2.999999999
commit 'fix: overflow'; reject 'version overflow' v1.2.999999999
new_repo
cat "$repo/.github/plugin/marketplace.json" "$repo/.github/plugin/marketplace.json" > "$work/multiple.json"
cp "$work/multiple.json" "$repo/.github/plugin/marketplace.json"; cp "$work/multiple.json" "$repo/.claude-plugin/marketplace.json"
git -C "$repo" add .github/plugin/marketplace.json .claude-plugin/marketplace.json; commit 'fix: duplicate documents'
reject 'multiple JSON documents' initial
new_repo
rm "$repo/.claude-plugin/marketplace.json"; ln -s ../.github/plugin/marketplace.json "$repo/.claude-plugin/marketplace.json"
git -C "$repo" add .claude-plugin/marketplace.json; commit 'fix: symlink'
reject 'manifest symlink' initial
new_repo; git -C "$repo" tag v1.2.3
commit 'fix: [spoof](https://example.invalid) <script> & text'
out="$work/escaped"; run v1.2.3 "$out" >/dev/null
grep -Fq '\[spoof\]\(https://example\.invalid\) &lt;script&gt; &amp; text' "$out/RELEASE_NOTES.md"
passed=$((passed + 1))
# A disk/copy failure may not leave a directory that appears to be a complete candidate.
mkdir "$work/bin"
# The generated stub must expand its own invocation arguments, not this test's.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nif [ "$1" = -R ]; then exit 23; fi\nexec %q "$@"\n' "$(command -v cp)" > "$work/bin/cp"
chmod +x "$work/bin/cp"
if (cd "$repo" && env PATH="$work/bin:$release_test_path" bash "$tool" --base-tag v1.2.3 --output "$work/copy-failure") > "$work/stdout" 2> "$work/stderr"; then fail 'copy failure passed'; fi
test ! -e "$work/copy-failure"; test ! -s "$work/stdout"; passed=$((passed + 1))

# A successful probe followed by a failed listing is not one complete census.
# Keep the real first listing, then fail before/after a valid prefix on a second
# call. The old process-substitution loop loses that second producer's status.
real_git=$(command -v git)
export RELEASE_REAL_GIT="$real_git"
mkdir -p "$work/git-fault"
cat > "$work/git-fault/git" <<'STUB'
#!/usr/bin/env bash
if [[ $1 == worktree && $2 == list ]]; then
  count=0
  [[ ! -f $RELEASE_GIT_CALLS ]] || read -r count < "$RELEASE_GIT_CALLS"
  count=$((count + 1))
  printf '%s\n' "$count" > "$RELEASE_GIT_CALLS"
  if [[ $RELEASE_GIT_FAULT == early || $count -gt 1 ]]; then
    [[ $RELEASE_GIT_FAULT != partial ]] || printf 'worktree %s\0\0' "$RELEASE_FIRST_WORKTREE"
    printf 'injected worktree census failure\n' >&2
    exit 71
  fi
fi
exec "$RELEASE_REAL_GIT" "$@"
STUB
chmod +x "$work/git-fault/git"
census_failed=0
for fault in early empty partial; do
  new_repo
  linked="$work/linked-$fault"
  git -C "$repo" worktree add -q --detach "$linked"
  calls="$work/calls-$fault"
  out="$linked/.github/candidate"
  if (cd "$repo" && env PATH="$work/git-fault:$release_test_path" RELEASE_GIT_FAULT="$fault" \
      RELEASE_GIT_CALLS="$calls" RELEASE_FIRST_WORKTREE="$repo" \
      bash "$tool" --base-tag initial --output "$out") > "$work/stdout" 2> "$work/stderr"; then
    printf 'FAIL %s worktree observation accepted output in a linked checkout\n' "$fault" >&2
    census_failed=$((census_failed + 1))
  fi
  if [[ -e $out || -s $work/stdout || -n $(git -C "$linked" status --porcelain --ignored) ]]; then
    printf 'FAIL %s worktree observation wrote into a linked checkout or emitted success\n' "$fault" >&2
    census_failed=$((census_failed + 1))
  fi
  passed=$((passed + 1))
done

# NUL records must keep newline-containing paths, including a trailing newline
# that command substitution would otherwise trim from pwd's output.
for suffix in $'space and\nnewline' $'trailing\n'; do
  new_repo
  linked="$work/linked-$suffix"
  git -C "$repo" worktree add -q --detach "$linked"
  out="$linked/.github/candidate"
  if run initial "$out" > "$work/stdout" 2> "$work/stderr"; then
    printf 'FAIL newline-containing linked checkout accepted\n' >&2
    census_failed=$((census_failed + 1))
  fi
  if [[ -e $out || -s $work/stdout || -n $(git -C "$linked" status --porcelain --ignored) ]]; then
    printf 'FAIL newline-containing linked checkout was changed\n' >&2
    census_failed=$((census_failed + 1))
  fi
  passed=$((passed + 1))
done
# Canonicalization must preserve legitimate outside parents and output names.
# A decoy without the final newline catches silently redirected output.
new_repo
outside="$work/outside"$'\n'
mkdir "$outside" "$work/outside"
out="$outside/candidate"$'\n'
if ! run initial "$out" > "$work/stdout" 2> "$work/stderr"; then
  printf 'FAIL newline-ending outside path refused\n' >&2
  census_failed=$((census_failed + 1))
fi
if [[ ! -f $out/release.json || -e $work/outside/candidate || -e $outside/candidate ]]; then
  printf 'FAIL newline-ending outside path redirected\n' >&2
  census_failed=$((census_failed + 1))
fi
passed=$((passed + 1))
[[ $census_failed == 0 ]] || fail "$census_failed worktree boundary regressions"
# Empty/prefix failures are not a successful no-match config observation.
real_git=$(command -v git)
mkdir "$work/config-fault"
cat > "$work/config-fault/git" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = config ] && [[ "$*" == *"$CONFIG_QUERY"* ]]; then
  if [ "$CONFIG_OUTPUT" = partial ]; then
    if [ "$CONFIG_QUERY" = extensions.partialClone ]; then printf 'origin\n'; else printf 'remote.origin.promisor false\n'; fi
  fi
  exit 2
fi
exec "$REAL_GIT" "$@"
STUB
chmod +x "$work/config-fault/git"
for query in extensions.partialClone promisor; do
  for output in empty partial; do
    new_repo; git -C "$repo" tag v1.2.3; commit "fix: complete history"
    out="$work/config-candidate-$query-$output"
    if PATH="$work/config-fault:$PATH" REAL_GIT="$real_git" CONFIG_QUERY="$query" CONFIG_OUTPUT="$output" run v1.2.3 "$out" > "$work/result" 2> "$work/error"; then
      fail "failed $query $output configuration was accepted"
    fi
    grep -q 'unreadable partial-clone configuration' "$work/error" || fail "failed configuration misdiagnosed"
    test ! -e "$out" || fail "failed configuration left a candidate"
    passed=$((passed+1))
  done
done
new_repo
jq -c . "$repo/.github/plugin/marketplace.json" | sed 's/"version":/"version":"9.9.9","version":/' > "$work/duplicate"
cp "$work/duplicate" "$repo/.github/plugin/marketplace.json"; cp "$work/duplicate" "$repo/.claude-plugin/marketplace.json"
git -C "$repo" add -- .github/plugin/marketplace.json .claude-plugin/marketplace.json
git -C "$repo" commit -qm 'chore: ambiguous manifest'
reject 'repeated manifest version is ambiguous' initial
for version in $'1.2.3\n' $'1.2.3\r\n'; do
  new_repo
  jq --arg version "$version" '.metadata.version=$version' "$repo/.github/plugin/marketplace.json" > "$work/change"
  cp "$work/change" "$repo/.github/plugin/marketplace.json"; cp "$work/change" "$repo/.claude-plugin/marketplace.json"
  git -C "$repo" add -- .github/plugin/marketplace.json .claude-plugin/marketplace.json
  git -C "$repo" commit -qm 'chore: malformed cache version'
  reject 'release version contains line terminator' initial
done
printf 'marketplace release preparation: PASS (%s cases)\n' "$passed"
