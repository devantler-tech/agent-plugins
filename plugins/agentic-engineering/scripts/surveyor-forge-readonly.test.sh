#!/usr/bin/env bash
# Hermetic contract for surveyor-forge-readonly.sh: the wrapper must invoke
# forge-readonly-guard.sh --command and map exit 0 to allow / 1|2 to deny JSON.
# It does not re-prove the classifier's full matrix.
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
WRAPPER="${HERE}/surveyor-forge-readonly.sh"
GUARD="${HERE}/forge-readonly-guard.sh"
# Capture bash before any PATH strip. Invoking the wrapper as an executable
# under a jq-less PATH fails at the `#!/usr/bin/env bash` shebang (exit 127)
# before the wrapper can emit its jq-missing deny JSON.
BASH_BIN=$(command -v bash)
[ -n "${BASH_BIN}" ] || {
  echo "FAIL: bash not on PATH"
  exit 1
}

pass=0
fail=0
pass() { pass=$((pass + 1)); }
fail() { echo "FAIL: $*" >&2; fail=$((fail + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

hook_stdin() {
  local cmd="$1"
  jq -nc --arg cmd "$cmd" '{tool_name:"Bash",tool_input:{command:$cmd}}'
}

run_wrapper() {
  local stdin="$1"
  shift
  printf '%s\n' "$stdin" | "$@"
}

# --- missing jq fails closed without consulting the guard ---
missing_jq_bin="$TMP/bin"
mkdir -p "$missing_jq_bin"
# PATH with no jq: keep the wrapper and a no-op guard, but not system jq.
cat >"$TMP/noop-guard" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/noop-guard"
out="$(
  PATH="$missing_jq_bin" SURVEYOR_FORGE_READONLY_GUARD="$TMP/noop-guard" \
    run_wrapper "$(hook_stdin 'gh pr view 1')" "$BASH_BIN" "$WRAPPER" 2>/dev/null
  true
)" || true
st="$(
  set +e
  PATH="$missing_jq_bin" SURVEYOR_FORGE_READONLY_GUARD="$TMP/noop-guard" \
    run_wrapper "$(hook_stdin 'gh pr view 1')" "$BASH_BIN" "$WRAPPER" >/dev/null 2>&1
  echo $?
)"
if [ "$st" -ne 0 ] && printf '%s\n' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass
else
  fail "missing jq must deny (st=$st out=$out)"
fi

# --- invalid hook input fails closed WITH the structured deny payload ---
#
# Exit status alone is not the contract. The runtime renders
# hookSpecificOutput.permissionDecision to show the operator WHY a command was
# refused, so a wrapper that exited 2 while printing nothing would satisfy an
# exit-status-only assertion and leave every refusal unexplained. Assert both,
# the same way the missing-jq case above already does.
assert_deny_payload() {
  local label="$1" input="$2" out st
  out="$(printf '%s' "$input" | "$WRAPPER" 2>/dev/null || true)"
  st="$(
    set +e
    printf '%s' "$input" | "$WRAPPER" >/dev/null 2>&1
    echo $?
  )"
  if [ "$st" -ne 0 ] && printf '%s\n' "$out" | grep -q '"permissionDecision":"deny"'; then
    pass
  else
    fail "$label (st=$st out=$out)"
  fi
}

assert_deny_payload "empty stdin must deny" ''
assert_deny_payload "malformed JSON must deny" '{not-json'
assert_deny_payload "missing tool_input.command must deny" '{"tool_name":"Bash","tool_input":{}}'

# --- stub guard: the wrapper must pass --command and map 0 / 1 / 2 ---
cat >"$TMP/stub-guard" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != "--command" ]; then
  echo "deny: stub expected --command, got ${1:-}" >&2
  exit 1
fi
cmd="${2:-}"
case "$cmd" in
  allow-me) exit 0 ;;
  deny-me)
    echo "deny: stub refused deny-me"
    exit 1
    ;;
  usage-me)
    echo "usage: stub usage"
    exit 2
    ;;
  *)
    echo "deny: stub unexpected command"
    exit 1
    ;;
esac
EOF
chmod +x "$TMP/stub-guard"

st="$(
  set +e
  SURVEYOR_FORGE_READONLY_GUARD="$TMP/stub-guard" \
    run_wrapper "$(hook_stdin 'allow-me')" "$WRAPPER" >/dev/null 2>&1
  echo $?
)"
if [ "$st" -eq 0 ]; then
  pass
else
  fail "stub allow must exit 0 (st=$st)"
fi

out="$(
  SURVEYOR_FORGE_READONLY_GUARD="$TMP/stub-guard" \
    run_wrapper "$(hook_stdin 'deny-me')" "$WRAPPER" 2>/dev/null
  true
)" || true
st="$(
  set +e
  SURVEYOR_FORGE_READONLY_GUARD="$TMP/stub-guard" \
    run_wrapper "$(hook_stdin 'deny-me')" "$WRAPPER" >/dev/null 2>&1
  echo $?
)"
if [ "$st" -ne 0 ] &&
  printf '%s\n' "$out" | grep -q '"permissionDecision":"deny"' &&
  printf '%s\n' "$out" | grep -q 'stub refused deny-me'; then
  pass
else
  fail "stub deny must emit deny JSON carrying the guard reason (st=$st out=$out)"
fi

out="$(
  SURVEYOR_FORGE_READONLY_GUARD="$TMP/stub-guard" \
    run_wrapper "$(hook_stdin 'usage-me')" "$WRAPPER" 2>/dev/null
  true
)" || true
st="$(
  set +e
  SURVEYOR_FORGE_READONLY_GUARD="$TMP/stub-guard" \
    run_wrapper "$(hook_stdin 'usage-me')" "$WRAPPER" >/dev/null 2>&1
  echo $?
)"
if [ "$st" -ne 0 ] && printf '%s\n' "$out" | grep -q '"permissionDecision":"deny"'; then
  pass
else
  fail "stub usage (exit 2) must deny (st=$st out=$out)"
fi

# --- a deny states its reason on stderr as well as in the JSON payload ---
#
# Exit 2 blocks the command regardless of the payload, so the JSON alone is not
# what guarantees the operator learns WHY. A runtime that derives its blocking
# message from stderr would render an unexplained refusal if the wrapper spoke
# only on stdout. Assert the reason reaches stderr, and that it is the guard's
# own reason rather than a generic placeholder.
err="$(
  set +e
  SURVEYOR_FORGE_READONLY_GUARD="$TMP/stub-guard" \
    run_wrapper "$(hook_stdin 'deny-me')" "$WRAPPER" 2>&1 >/dev/null
  true
)"
if printf '%s\n' "$err" | grep -q 'stub refused deny-me'; then
  pass
else
  fail "deny must write the guard reason to stderr (err=$err)"
fi

# The same must hold for a malformed payload, where there is no guard reason to
# forward and the wrapper supplies its own.
err="$(
  set +e
  printf '%s' '{not-json' | "$WRAPPER" 2>&1 >/dev/null
  true
)"
if printf '%s\n' "$err" | grep -q 'deny:'; then
  pass
else
  fail "malformed stdin must write a deny reason to stderr (err=$err)"
fi

# --- real guard: one admitted read and one refused mutation ---
if [ ! -x "$GUARD" ]; then
  fail "forge-readonly-guard.sh missing next to the wrapper"
else
  st="$(
    set +e
    run_wrapper "$(hook_stdin 'gh pr view 2786 --repo devantler-tech/monorepo --json number,state,headRefOid')" \
      "$WRAPPER" >/dev/null 2>&1
    echo $?
  )"
  if [ "$st" -eq 0 ]; then
    pass
  else
    fail "real guard must allow gh pr view (st=$st)"
  fi

  out="$(
    run_wrapper "$(hook_stdin 'gh pr create --title x')" "$WRAPPER" 2>/dev/null
    true
  )" || true
  st="$(
    set +e
    run_wrapper "$(hook_stdin 'gh pr create --title x')" "$WRAPPER" >/dev/null 2>&1
    echo $?
  )"
  if [ "$st" -ne 0 ] && printf '%s\n' "$out" | grep -q '"permissionDecision":"deny"'; then
    pass
  else
    fail "real guard must deny gh pr create (st=$st out=$out)"
  fi
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
