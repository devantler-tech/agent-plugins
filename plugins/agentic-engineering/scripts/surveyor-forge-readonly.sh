#!/usr/bin/env bash
# Surveyor-scoped PreToolUse wrapper around forge-readonly-guard.sh.
#
# This is the Claude Code command-hook implementation of the surveyor's
# read-only forge contract. It is NOT a second classifier: it extracts the
# tool command from hook stdin and delegates to forge-readonly-guard.sh.
#
# Stdin: Claude Code PreToolUse JSON (tool_input.command, or .command).
# Exit 0: allow (the guard admitted the command, or the call is out of scope).
# Exit 2: deny (guard refused, usage error, missing jq, or malformed stdin).
# A deny emits hookSpecificOutput.permissionDecision=deny JSON on stdout AND
# the bare reason on stderr. Exit 2 is deliberate: it blocks the command
# whether or not the JSON parses, so a malformed payload can never fail open.
# The reason is written to both streams because the runtime derives the
# blocking message from the JSON decision when it reads one and from stderr
# otherwise -- emitting both means the operator sees the reason either way.
#
# SCOPING. A PreToolUse `matcher` filters on tool name only, so a `Bash`
# matcher fires for every agent, including the engineer's own lane whose
# writes are legitimate. Attaching this wrapper to a bare `Bash` matcher with
# no scope would therefore refuse `gh pr create`, `git push` and test runs
# everywhere. The runtime does carry the agent identity in the same stdin this
# wrapper already parses: `agent_type` (the agent's name) and `agent_id`
# (present only inside a subagent call).
#
# Set SURVEYOR_FORGE_READONLY_SCOPE to the surveyor's agent name to enforce
# only for that agent. The gate is OPT-IN and strictly additive: with the
# variable unset this wrapper behaves exactly as it always has.
#
# The two failure directions are deliberately NOT symmetric:
#   * command classification fails CLOSED -- an unreadable or unclassifiable
#     command still denies. That is the property this guard exists for.
#   * agent scoping normally fails OPEN -- a positively identified different
#     agent exits 0. A valid payload with no agent_type is the exception: when
#     a scope is configured that combination can never match and would silently
#     disable the guard for every call, so it is refused as a broken install.
#
# Override the guard path with SURVEYOR_FORGE_READONLY_GUARD (tests).
set -euo pipefail

HERE=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
GUARD="${SURVEYOR_FORGE_READONLY_GUARD:-${HERE}/forge-readonly-guard.sh}"
SCOPE="${SURVEYOR_FORGE_READONLY_SCOPE:-}"

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
  # Also on stderr: a runtime that takes its blocking message from stderr
  # rather than from the JSON decision would otherwise refuse with no reason.
  printf '%s\n' "$reason" >&2
}

# Out of scope: not this wrapper's call to refuse.
#
# SILENT by design. Once installed on a `Bash` matcher this path is taken by
# every main-thread call in every lane, so anything written here is emitted on
# essentially every command the engineer runs. A guard that narrates each of
# its own no-ops is a tax on the everyday path, and the useful signal (a DENY)
# would be the one lost in it. Set SURVEYOR_FORGE_READONLY_DEBUG=1 to trace an
# install, where distinguishing "allowed, out of scope" from "allowed, guard
# admitted it" is exactly the question being asked.
out_of_scope() {
  if [ -n "${SURVEYOR_FORGE_READONLY_DEBUG:-}" ]; then
    printf 'surveyor-forge-readonly: out of scope (%s), allowing\n' "$1" >&2
  fi
  exit 0
}

if ! command -v jq >/dev/null 2>&1; then
  # Without jq the agent cannot be identified, so a scoped install cannot know
  # this call is the surveyor's. Denying would block every lane's Bash.
  [ -z "$SCOPE" ] || out_of_scope "jq unavailable, agent unidentifiable"
  emit_deny "deny: jq is required to parse PreToolUse stdin"
  exit 2
fi

if ! payload="$(cat)"; then
  [ -z "$SCOPE" ] || out_of_scope "stdin unreadable, agent unidentifiable"
  emit_deny "deny: failed to read PreToolUse stdin"
  exit 2
fi

# Scope gate, evaluated before any command handling: an out-of-scope call is
# none of this wrapper's business regardless of what it is asking to run.
if [ -n "$SCOPE" ]; then
  agent="$(printf '%s\n' "$payload" | jq -r '.agent_type // ""' 2>/dev/null)" ||
    out_of_scope "malformed stdin, agent unidentifiable"
  if [ -z "$agent" ]; then
    emit_deny "deny: identity scope is configured but agent_type is missing"
    exit 2
  fi
  [ "$agent" = "$SCOPE" ] || out_of_scope "agent_type='${agent}' != '${SCOPE}'"
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
