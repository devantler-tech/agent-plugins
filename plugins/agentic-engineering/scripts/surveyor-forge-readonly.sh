#!/usr/bin/env bash
# Surveyor-scoped PreToolUse wrapper around forge-readonly-guard.sh.
#
# This is the Claude Code command-hook implementation of the surveyor's
# read-only forge contract. It is NOT a second classifier: it extracts the
# tool command from hook stdin and delegates to forge-readonly-guard.sh.
#
# Attach this wrapper ONLY to the portfolio-surveyor agent's Bash PreToolUse
# path. A plugin-wide Bash matcher would refuse the engineer agent's
# legitimate writes (gh pr create, git push, tests).
#
# Stdin: Claude Code PreToolUse JSON (tool_input.command, or .command).
# Exit 0: allow (guard admitted the command).
# Exit 2: deny (guard refused, usage error, missing jq, or malformed stdin).
# A deny always emits hookSpecificOutput.permissionDecision=deny JSON on
# stdout so the runtime can show the reason.
#
# Override the guard path with SURVEYOR_FORGE_READONLY_GUARD (tests).
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
GUARD="${SURVEYOR_FORGE_READONLY_GUARD:-${HERE}/forge-readonly-guard.sh}"

# Static deny payload used when jq is unavailable. The reason is a fixed
# ASCII string so this JSON needs no escaping.
STATIC_JQ_MISSING='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"deny: jq is required to parse PreToolUse stdin"}}'

emit_deny() {
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg reason "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  else
    printf '%s\n' "$STATIC_JQ_MISSING"
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  emit_deny "deny: jq is required to parse PreToolUse stdin"
  exit 2
fi

if ! payload="$(cat)"; then
  emit_deny "deny: failed to read PreToolUse stdin"
  exit 2
fi

if [ -z "$payload" ]; then
  emit_deny "deny: empty PreToolUse stdin"
  exit 2
fi

cmd="$(printf '%s\n' "$payload" | jq -er '.tool_input.command // .command // empty' 2>/dev/null)" || cmd=""
if [ -z "$cmd" ]; then
  emit_deny "deny: PreToolUse stdin missing tool_input.command"
  exit 2
fi

if [ ! -x "$GUARD" ]; then
  emit_deny "deny: forge-readonly-guard is missing or not executable"
  exit 2
fi

set +e
guard_out="$("$GUARD" --command "$cmd" 2>&1)"
guard_st=$?
set -e

case "$guard_st" in
  0)
    exit 0
    ;;
  1|2)
    reason="$guard_out"
    [ -n "$reason" ] || reason="deny: forge-readonly-guard refused the command"
    emit_deny "$reason"
    exit 2
    ;;
  *)
    emit_deny "deny: forge-readonly-guard exited ${guard_st}"
    exit 2
    ;;
esac
