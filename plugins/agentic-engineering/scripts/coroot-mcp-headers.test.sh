#!/usr/bin/env bash
# Hermetic self-test for coroot-mcp-headers.sh: the helper prints exactly one Authorization header
# from the API key in the plugin data directory, only when Claude Code connects to the address
# pinned in coroot-url followed by /mcp, and refuses every other state without printing a header
# or the key. It has no fallback: a Coroot service-account key comes only from that file.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
helper=$here/coroot-mcp-headers.sh
work=$(mktemp -d)
trap 'chmod -R u+rwx "$work" 2>/dev/null; rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

pinned=https://coroot.example.test
export CLAUDE_CODE_MCP_SERVER_URL=$pinned/mcp

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
setup() { # dir url key: a data directory holding the two files, written verbatim
  rm -rf "$1"; mkdir -p "$1"
  printf '%b' "$2" > "$1/coroot-url"
  printf '%b' "$3" > "$1/coroot-api-key"
  chmod 600 "$1/coroot-api-key"
}

key='Abc_k3y-0123456789.XYZ~'
setup "$work/data" "$pinned\n" "$key\n"
expect_header "$work/data" "$key"

# A key in the environment is never used, whatever it is called.
COROOT_API_KEY=env_k3y expect_header "$work/data" "$key"

# Both files may end without a newline, and the key file may be a link to a readable key.
setup "$work/bare" "$pinned" "$key"
expect_header "$work/bare" "$key"
printf '%s\n' "$key" > "$work/real-key"
rm "$work/bare/coroot-api-key"; ln -s "$work/real-key" "$work/bare/coroot-api-key"
expect_header "$work/bare" "$key"

# Plain http only to the loopback interface, and an address may carry a path.
for url in http://localhost:8080 http://127.0.0.1:8080 'http://[::1]:8080' https://example.test/coroot; do
  setup "$work/url" "$url\n" "$key\n"
  CLAUDE_CODE_MCP_SERVER_URL=$url/mcp expect_header "$work/url" "$key"
done

# The key goes nowhere but the pinned address followed by /mcp.
CLAUDE_CODE_MCP_SERVER_URL='' refused 'an empty server URL' "$work/data"
(unset CLAUDE_CODE_MCP_SERVER_URL; refused 'an unset server URL' "$work/data")
for url in https://attacker.example.test/mcp http://coroot.example.test/mcp "$pinned//mcp" \
  "$pinned/mcp/" "$pinned/mcp?x=1" "$pinned" https://coroot.example.test.attacker.test/mcp; do
  CLAUDE_CODE_MCP_SERVER_URL=$url refused "the server URL $url" "$work/data"
done

# A pinned address that is not a single https:// (or loopback http://) origin and path.
for url in '' 'http://coroot.example.test' 'http://localhost.attacker.test' "$pinned/" \
  'https://user@coroot.example.test' "$pinned?x=1" "$pinned#f" 'ftp://coroot.example.test' \
  "$pinned\n$pinned" "$pinned\n\n" "$pinned\r\n" "https://coro\0ot.example.test" ' '"$pinned"; do
  setup "$work/bad-url" "$url" "$key\n"
  CLAUDE_CODE_MCP_SERVER_URL=$(printf '%b' "$url" | tr -d '\0')/mcp refused "the pinned address $url" "$work/bad-url"
done
setup "$work/no-url" "$pinned\n" "$key\n"; rm "$work/no-url/coroot-url"
refused 'a missing coroot-url' "$work/no-url"

refused 'no data directory argument' ''
for bad in '' 'two words k3y\n' 'k3y"}{\n' 'k3y\nsecond-line\n' 'k3y\n\n' 'k3y\r\n' 'k3\0y\n' ' k3y\n'; do
  setup "$work/bad-key" "$pinned\n" "$bad"
  refused "the key file $bad" "$work/bad-key"
done
setup "$work/link" "$pinned\n" "$key\n"
rm "$work/link/coroot-api-key"
refused 'a missing key file' "$work/link"
ln -s "$work/nowhere" "$work/link/coroot-api-key"
refused 'a dangling key link' "$work/link"
rm "$work/link/coroot-api-key"
mkdir "$work/link/coroot-api-key"
refused 'a key path that is a directory' "$work/link"
printf 'not a directory\n' > "$work/file"
refused 'a data path that is a file' "$work/file"
if [ "$(id -u)" -ne 0 ]; then
  setup "$work/locked" "$pinned\n" "$key\n"
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
