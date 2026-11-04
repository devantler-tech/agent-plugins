#!/usr/bin/env bash
# Hermetic self-test for coroot-mcp-headers.sh: the helper prints exactly one Authorization header
# from the API key in the plugin data directory, and refuses every other state without printing a
# header or the key. It has no fallback: a Coroot service-account key comes only from that file.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
helper=$here/coroot-mcp-headers.sh
work=$(mktemp -d)
trap 'chmod -R u+rwx "$work" 2>/dev/null; rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

run() { # expected-status data-dir [extra-arg]
  local want=$1 status=0; shift
  bash "$helper" "$@" > "$work/out" 2> "$work/err" || status=$?
  [ "$status" -eq "$want" ] || fail "exit $status, want $want for: $* ($(cat "$work/err"))"
  if grep -q 'k3y' "$work/err"; then fail "printed the key on stderr for: $*"; fi
}
expect_header() { # data-dir key
  run 0 "$1"
  jq -se --arg k "$2" 'length == 1 and .[0] == {Authorization: ("Bearer " + $k)}' "$work/out" > /dev/null ||
    fail "unexpected output: $(cat "$work/out")"
}
refused() { # description data-dir
  run 1 "$2"
  [ ! -s "$work/out" ] || fail "printed output for $1"
}

mkdir -p "$work/data"
printf 'Abc_k3y-0123456789.XYZ~\n' > "$work/data/coroot-api-key"
chmod 600 "$work/data/coroot-api-key"
expect_header "$work/data" 'Abc_k3y-0123456789.XYZ~'

# A key in the environment is never used, whatever it is called.
COROOT_API_KEY=env_k3y expect_header "$work/data" 'Abc_k3y-0123456789.XYZ~'

refused 'no data directory argument' ''
mkdir -p "$work/empty"
refused 'a missing key file' "$work/empty"
printf '' > "$work/empty/coroot-api-key"
refused 'an empty key file' "$work/empty"
printf 'two words k3y\n' > "$work/empty/coroot-api-key"
refused 'a key with spaces' "$work/empty"
printf 'k3y"}{\n' > "$work/empty/coroot-api-key"
refused 'a key that would break the JSON' "$work/empty"
printf 'k3y\nsecond-line\n' > "$work/empty/coroot-api-key"
refused 'a key file with a second line' "$work/empty"
rm "$work/empty/coroot-api-key"
ln -s "$work/nowhere" "$work/empty/coroot-api-key"
refused 'a dangling key link' "$work/empty"
rm "$work/empty/coroot-api-key"
mkdir "$work/empty/coroot-api-key"
refused 'a key path that is a directory' "$work/empty"
printf 'not a directory\n' > "$work/file"
refused 'a data path that is a file' "$work/file"
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$work/locked"
  printf 'k3y\n' > "$work/locked/coroot-api-key"
  chmod 000 "$work/locked/coroot-api-key"
  refused 'an unreadable key file' "$work/locked"
  chmod 600 "$work/locked/coroot-api-key"
  chmod 600 "$work/locked"
  refused 'an unsearchable data directory' "$work/locked"
  chmod 700 "$work/locked"
fi

run 2 "$work/data" extra
[ ! -s "$work/out" ] || fail 'printed output for a usage error'

printf 'coroot-mcp-headers: PASS\n'
