#!/usr/bin/env bash
# Hermetic contract for kubescape-mcp.sh: a stub `kubescape` stands in for the server,
# so no cluster and no real kubeconfig is used.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
launcher="$here/kubescape-mcp.sh"
bash_bin=$(command -v bash)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/empty" "$work/home"

fail() { echo "FAIL: $*" >&2; exit 1; }

# The stub records its arguments and the KUBECONFIG it received, then echoes stdin to stdout the
# way a stdio MCP server answers, so a test can prove the launcher passes the protocol streams
# through untouched. It uses bash builtins only: the hermetic PATH holds nothing but the stub.
cat > "$work/bin/kubescape" <<STUB
#!$bash_bin
printf '%s\n' "\$*" > "$work/args"
printf '%s' "\${KUBECONFIG-<unset>}" > "$work/kubeconfig"
while IFS= read -r line || [ -n "\$line" ]; do printf '%s\n' "\$line"; done
STUB
chmod +x "$work/bin/kubescape"

run() { # expected-exit launcher-args... -- env-assignments...
  local expected=$1 status=0 args=()
  shift
  while [ $# -gt 0 ] && [ "$1" != -- ]; do args+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  rm -f "$work/args" "$work/kubeconfig"
  printf '{"jsonrpc":"2.0","id":1,"method":"ping"}\n' |
    env -i "$@" "$bash_bin" "$launcher" ${args[@]+"${args[@]}"} > "$work/out" 2> "$work/err" ||
    status=$?
  [ "$status" -eq "$expected" ] || fail "exit $status, expected $expected: $(cat "$work/err")"
}

expect_server() { # kubeconfig description
  [ "$(cat "$work/args")" = "mcpserver" ] ||
    fail "$2: the server did not start with exactly 'mcpserver': $(cat "$work/args")"
  [ "$(cat "$work/kubeconfig")" = "$1" ] || fail "$2: KUBECONFIG was $(cat "$work/kubeconfig"), expected $1"
  [ "$(cat "$work/out")" = '{"jsonrpc":"2.0","id":1,"method":"ping"}' ] ||
    fail "$2: stdout carried more than the server's own output: $(cat "$work/out")"
  [ ! -s "$work/err" ] || fail "$2: wrote to stderr: $(cat "$work/err")"
}

# 1. With KUBECONFIG unset, the server reads $HOME/.kube/config.
run 0 -- PATH="$work/bin" HOME="$work/home"
expect_server "$work/home/.kube/config" "unset KUBECONFIG"

# 2. An empty KUBECONFIG counts as unset, as the server itself would refuse it.
run 0 -- PATH="$work/bin" HOME="$work/home" KUBECONFIG=
expect_server "$work/home/.kube/config" "empty KUBECONFIG"

# 3. A non-empty KUBECONFIG, including a list of files, passes through unchanged.
run 0 -- PATH="$work/bin" HOME="$work/home" KUBECONFIG="$work/a.yaml:$work/b yaml"
expect_server "$work/a.yaml:$work/b yaml" "explicit KUBECONFIG"

# 4. Neither KUBECONFIG nor HOME: refuse, name the fix, and never start the server.
run 1 -- PATH="$work/bin"
[ ! -e "$work/args" ] || fail "started the server without KUBECONFIG or HOME"
[ ! -s "$work/out" ] || fail "wrote to stdout without KUBECONFIG or HOME"
grep -q 'set KUBECONFIG or HOME' "$work/err" || fail "the refusal does not name the fix: $(cat "$work/err")"

# 5. Arguments are a usage error, so nothing can change what the server is started with.
run 2 --verbose -- PATH="$work/bin" HOME="$work/home"
[ ! -e "$work/args" ] || fail "started the server despite a usage error"
[ ! -s "$work/out" ] || fail "wrote to stdout for a usage error"

# 6. A missing server binary fails with the shell's not-found status and no stdout.
run 127 -- PATH="$work/empty" HOME="$work/home"
[ ! -s "$work/out" ] || fail "wrote to stdout without a server binary"

printf 'kubescape-mcp: PASS\n'
