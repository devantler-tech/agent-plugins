#!/usr/bin/env bash
# A successful no-match is distinct from an unreadable config query.
clone_config_observation() {
  local result status=0
  result=$(git config "$@") || status=$?
  case "$status" in
    0) printf '%s\n' "$result"; return 0 ;;
    1) [ -z "$result" ] && return 1 ;;
  esac
  printf 'unreadable partial-clone configuration\n' >&2
  return 2
}

assert_complete_clone_config() {
  local promisors status promisor
  if clone_config_observation --get extensions.partialClone >/dev/null; then
    printf 'partial clones are unsupported\n' >&2
    return 1
  else
    status=$?
    [ "$status" = 1 ] || return 2
  fi
  if promisors=$(clone_config_observation --type=bool --get-regexp '^remote\..*\.promisor$'); then
    while IFS= read -r promisor; do
      if [ "${promisor##* }" = true ]; then
        printf 'partial clones are unsupported\n' >&2
        return 1
      fi
    done <<< "$promisors"
  else
    status=$?
    [ "$status" = 1 ] || return 2
  fi
}
