#!/usr/bin/env bash
# Native local-object behavior under the guard's required process environment.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
root="$work/repo"
git init -q -b main "$root"
git -C "$root" config user.name Fixture
git -C "$root" config user.email fixture@example.invalid
printf 'local bytes\n' > "$root/data.txt"
git -C "$root" add data.txt
git -C "$root" -c commit.gpgsign=false commit -qm baseline
blob=$(git -C "$root" rev-parse HEAD:data.txt)
export GIT_NO_LAZY_FETCH=1
command="git -C $root show --no-ext-diff --no-textconv HEAD:data.txt"
bash "$here/forge-readonly-guard.sh" --command "$command" > "$work/guard"
git -C "$root" show --no-ext-diff --no-textconv HEAD:data.txt > "$work/read"
cmp -s "$root/data.txt" "$work/read"
# All transport code is an owned fixture; no network access is involved.
cat > "$work/transport" <<'STUB'
#!/usr/bin/env bash
printf called > "$FIXTURE_TRANSPORT_MARKER"
exit 1
STUB
chmod +x "$work/transport"
git -C "$root" config extensions.partialClone origin
git -C "$root" config remote.origin.promisor true
git -C "$root" config remote.origin.partialclonefilter blob:none
git -C "$root" config remote.origin.url "ext::$work/transport"
git -C "$root" config protocol.ext.allow always
rm "$root/.git/objects/${blob:0:2}/${blob:2}"
export FIXTURE_TRANSPORT_MARKER="$work/transport-called"
# Prove this missing object would invoke the owned fixture transport without
# protection, then clear that evidence before the guarded observation.
probe_rc=0
(
  unset GIT_NO_LAZY_FETCH
  git -C "$root" show --no-ext-diff --no-textconv HEAD:data.txt > "$work/probe-read" 2> "$work/probe-error"
) || probe_rc=$?
test "$probe_rc" -ne 0
test -e "$FIXTURE_TRANSPORT_MARKER"
rm "$FIXTURE_TRANSPORT_MARKER"
test ! -e "$root/.git/objects/${blob:0:2}/${blob:2}"
bash "$here/forge-readonly-guard.sh" --command "$command" > "$work/guard"
rc=0
git -C "$root" show --no-ext-diff --no-textconv HEAD:data.txt > "$work/read" 2> "$work/error" || rc=$?
test "$rc" -ne 0
test ! -e "$FIXTURE_TRANSPORT_MARKER"
test ! -s "$work/read"
printf 'PASS complete objects read locally; missing objects fail without transport execution\n'
