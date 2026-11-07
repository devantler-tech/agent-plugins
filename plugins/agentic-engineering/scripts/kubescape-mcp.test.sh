#!/usr/bin/env bash
# Hermetic contract for kubescape-mcp.sh: a stub `kubescape` stands in for the server, so no cluster
# and no real kubeconfig is used. The launcher runs under `sh`, as both MCP files start it.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin_root=$(cd "$here/.." && pwd)
launcher="$here/kubescape-mcp.sh"
bash_bin=$(command -v bash)
sh_bin=$(command -v sh)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/empty" "$work/home"

fail() { echo "FAIL: $*" >&2; exit 1; }

# The stub records its arguments, the KUBECONFIG and the KS_SKIP_UPDATE_CHECK it received, then
# echoes stdin to stdout the way a stdio MCP server answers, so a test can prove the launcher passes
# the protocol streams through untouched. It uses bash builtins only: the hermetic PATH holds
# nothing but the stub. It runs as `bash -p`, which reads no BASH_ENV file, so anything that file
# prints came from the launcher.
cat > "$work/bin/kubescape" <<STUB
#!$bash_bin -p
printf '%s\n' "\$*" > "$work/args"
printf '%s' "\${KUBECONFIG-<unset>}" > "$work/kubeconfig"
printf '%s' "\${KS_SKIP_UPDATE_CHECK-<unset>}" > "$work/skip"
while IFS= read -r line || [ -n "\$line" ]; do printf '%s\n' "\$line"; done
STUB
chmod +x "$work/bin/kubescape"

run() { # expected-exit launcher-args... -- env-assignments...
  local expected=$1 status=0 args=()
  shift
  while [ $# -gt 0 ] && [ "$1" != -- ]; do args+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  rm -f "$work/args" "$work/kubeconfig" "$work/skip"
  printf '{"jsonrpc":"2.0","id":1,"method":"ping"}\n' |
    env -i "$@" "$sh_bin" "$launcher" ${args[@]+"${args[@]}"} > "$work/out" 2> "$work/err" ||
    status=$?
  [ "$status" -eq "$expected" ] || fail "exit $status, expected $expected: $(cat "$work/err")"
}

expect_server() { # kubeconfig skip-update-check description
  [ "$(cat "$work/args")" = "mcpserver" ] ||
    fail "$3: the server did not start with exactly 'mcpserver': $(cat "$work/args")"
  [ "$(cat "$work/kubeconfig")" = "$1" ] || fail "$3: KUBECONFIG was $(cat "$work/kubeconfig"), expected $1"
  [ "$(cat "$work/skip")" = "$2" ] || fail "$3: KS_SKIP_UPDATE_CHECK was $(cat "$work/skip"), expected $2"
  [ "$(cat "$work/out")" = '{"jsonrpc":"2.0","id":1,"method":"ping"}' ] ||
    fail "$3: stdout carried more than the server's own output: $(cat "$work/out")"
  [ ! -s "$work/err" ] || fail "$3: wrote to stderr: $(cat "$work/err")"
}

# 1. With KUBECONFIG unset, the server reads $HOME/.kube/config, and sends no version check.
run 0 -- PATH="$work/bin" HOME="$work/home"
expect_server "$work/home/.kube/config" true "unset KUBECONFIG"

# 2. An empty KUBECONFIG counts as unset, as the Flux server's launcher treats it.
run 0 -- PATH="$work/bin" HOME="$work/home" KUBECONFIG=
expect_server "$work/home/.kube/config" true "empty KUBECONFIG"

# 3. A non-empty KUBECONFIG, including a list of files, passes through unchanged.
run 0 -- PATH="$work/bin" HOME="$work/home" KUBECONFIG="$work/a.yaml:$work/b yaml"
expect_server "$work/a.yaml:$work/b yaml" true "explicit KUBECONFIG"

# 4. A user's own KS_SKIP_UPDATE_CHECK wins; an empty one counts as unset.
run 0 -- PATH="$work/bin" HOME="$work/home" KS_SKIP_UPDATE_CHECK=false
expect_server "$work/home/.kube/config" false "explicit KS_SKIP_UPDATE_CHECK"
run 0 -- PATH="$work/bin" HOME="$work/home" KS_SKIP_UPDATE_CHECK=
expect_server "$work/home/.kube/config" true "empty KS_SKIP_UPDATE_CHECK"

# 5. Neither KUBECONFIG nor HOME: refuse, name the fix, and never start the server.
run 1 -- PATH="$work/bin"
[ ! -e "$work/args" ] || fail "started the server without KUBECONFIG or HOME"
[ ! -s "$work/out" ] || fail "wrote to stdout without KUBECONFIG or HOME"
grep -q 'set KUBECONFIG or HOME' "$work/err" || fail "the refusal does not name the fix: $(cat "$work/err")"

# 6. Arguments are a usage error, so nothing can change what the server is started with.
run 2 --verbose -- PATH="$work/bin" HOME="$work/home"
[ ! -e "$work/args" ] || fail "started the server despite a usage error"
[ ! -s "$work/out" ] || fail "wrote to stdout for a usage error"

# 7. A missing server binary fails with the shell's not-found status and no stdout.
run 127 -- PATH="$work/empty" HOME="$work/home"
[ ! -s "$work/out" ] || fail "wrote to stdout without a server binary"

# 8. A BASH_ENV file that prints must not reach the protocol stream: `sh` never reads it.
printf '%s\n' 'echo from-bash-env' > "$work/bash-env"
run 0 -- PATH="$work/bin" HOME="$work/home" BASH_ENV="$work/bash-env"
expect_server "$work/home/.kube/config" true "BASH_ENV set"

# 9. Both MCP files start this launcher with `sh`: Claude Code and VS Code by its
#    ${CLAUDE_PLUGIN_ROOT} path, Codex by its plugin-relative path from cwd ".", which Codex joins
#    onto the plugin root. Each spelling must name this file.
jq -e '.mcpServers.kubescape == {command: "sh", args: ["${CLAUDE_PLUGIN_ROOT}/scripts/kubescape-mcp.sh"]}' \
  "$plugin_root/.mcp.json" > /dev/null || fail ".mcp.json does not start kubescape through this launcher"
jq -e '.mcpServers.kubescape == {command: "sh", args: ["scripts/kubescape-mcp.sh"], cwd: "."}' \
  "$plugin_root/.codex-plugin/mcp.json" > /dev/null || fail ".codex-plugin/mcp.json does not start kubescape through this launcher"
[ "$plugin_root/scripts/kubescape-mcp.sh" -ef "$launcher" ] || fail "the configured path is not this launcher"
rm -f "$work/args"
(cd "$plugin_root" && printf '\n' | env -i PATH="$work/bin" HOME="$work/home" "$sh_bin" scripts/kubescape-mcp.sh) \
  > /dev/null 2>&1 || fail "the Codex spelling does not start the server from the plugin root"
[ "$(cat "$work/args")" = "mcpserver" ] || fail "the Codex spelling started something else"

printf 'kubescape-mcp: PASS\n'
