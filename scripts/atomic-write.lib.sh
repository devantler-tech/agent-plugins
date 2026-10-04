#!/usr/bin/env bash
# Replace a validated NUL-paired (destination, staged source) batch without
# truncating live files. Helpers share one checkout-root lock through snapshots,
# replacement and recovery. Uncontended originals are restored; a conflict or
# failed recovery keeps its backup beside the destination for the operator.
# The optional second argument, true, permits creating previously absent destinations.
atomic_write_batch() (
  local atomic_root atomic_tool_dir atomic_tool atomic_here
  atomic_root=$(pwd -P) || return 1
  atomic_here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || return 1
  atomic_tool_dir=$(mktemp -d) || return 1
  atomic_tool="$atomic_tool_dir/anchor"
  if ! GOENV=off GOWORK=off GO111MODULE=off GOTOOLCHAIN=local go build -o "$atomic_tool" "$atomic_here/atomic-parent-go/main.go"; then
    rm -rf "$atomic_tool_dir"; return 1
  fi
  # Every path-bearing command uses leaf operands in a directory pinned by the
  # observer. Checks, staging, replacement, rollback and cleanup share the bind.
  atomic_at() {
    local target=$1 parent arg
    shift
    parent=${target%/*}; [ "$parent" != "$target" ] || parent=.
    local command_args=()
    for arg in "$@"; do
      if [ "$parent" != . ] && [[ "$arg" == "$parent/"* ]]; then
        command_args+=("${arg#"$parent/"}")
      else command_args+=("$arg"); fi
    done
    ATOMIC_DESTINATION="$target" "$atomic_tool" "$atomic_root" "$parent" -- "${command_args[@]}"
  }
  atomic_temp() {
    local target=$1 leaf
    leaf=$(atomic_at "$target" mktemp "$target") || return 1
    if [[ $target == */* ]]; then printf '%s/%s\n' "${target%/*}" "$leaf"
    else printf '%s\n' "$leaf"; fi
  }
  local lock=.agent-plugin-write.lock lock_rc=0
  if ! mkdir "$lock" 2>/dev/null; then
    echo '::error::Generated writes are already locked; inspect the existing writer before retrying.' >&2
    rm -rf "$atomic_tool_dir"
    return 1
  fi
  # The subshell keeps this cleanup independent of each caller's staging trap.
  trap 'lock_rc=$?; rm -rf "$atomic_tool_dir"; if ! rmdir "$lock"; then echo "::error::Recovery required; generated-write lock retained." >&2; lock_rc=1; fi; exit "$lock_rc"' EXIT
  local plan=$1 allow_new=${2:-false} destination='' staged='' next original i failed=0
  local destinations=() replacements=() originals=() sources=()
  while IFS= read -r -d '' destination; do
    if ! IFS= read -r -d '' staged; then failed=1; break; fi
    # Staged operands are relative to the caller, before entering any parent.
    case "$staged" in /*) ;; *) staged="$atomic_root/$staged" ;; esac
    if atomic_at "$destination" test -L "$destination" || [ ! -f "$staged" ] ||
       { [ ! -f "$destination" ] && { [ "$allow_new" != true ] || [ -e "$destination" ]; }; }; then failed=1; break; fi
    original=''
    if [ -f "$destination" ]; then
      original=$(atomic_temp "$destination.original.XXXXXX") || { failed=1; break; }
    fi
    originals+=("$original")
    destinations+=("$destination")
    sources+=("$staged")
    next=$(atomic_temp "$destination.next.XXXXXX") || { failed=1; break; }
    replacements+=("$next")
    if { [ -n "$original" ] && { ! atomic_at "$destination" cp -p "$destination" "$original" || ! atomic_at "$destination" cp -p "$destination" "$next"; }; } ||
       ! atomic_at "$destination" cp "$staged" "$next"; then
      failed=1; break
    fi
  done < "$plan"
  [ -z "$destination" ] || failed=1
  if [ "$failed" -eq 0 ]; then
    # Refuse a moved target before the first replacement.
    for i in "${!destinations[@]}"; do
      if [ -L "${destinations[$i]}" ] ||
         { [ -n "${originals[$i]}" ] && ! atomic_at "${destinations[$i]}" cmp -s "${destinations[$i]}" "${originals[$i]}"; } ||
         { [ -z "${originals[$i]}" ] && [ -e "${destinations[$i]}" ]; }; then failed=1; break; fi
    done
  fi
  if [ "$failed" -eq 0 ]; then
    for i in "${!destinations[@]}"; do
      # Linux -T and macOS -h prevent a last-component directory symlink from
      # becoming mv's destination directory after the validation above.
      local nofollow=-T
      [ "$(uname -s)" != Darwin ] || nofollow=-h
      if ! atomic_at "${destinations[$i]}" mv -f "$nofollow" "${replacements[$i]}" "${destinations[$i]}"; then
        failed=1
        local j
        for j in "${!destinations[@]}"; do
          [ "$j" -le "$i" ] || continue
          # Supported helpers cannot interleave while this lock is held. Preserve
          # any outside edit already visible before restoring our staged bytes.
          if [ -z "${originals[$j]}" ]; then
            # Remove only a new file whose bytes still match this batch's staged source.
            if [ ! -e "${destinations[$j]}" ] && [ ! -L "${destinations[$j]}" ]; then continue; fi
            if [ -L "${destinations[$j]}" ] || ! atomic_at "${destinations[$j]}" cmp -s "${destinations[$j]}" "${sources[$j]}" ||
               ! atomic_at "${destinations[$j]}" rm -f "${destinations[$j]}"; then
              printf '::error::Recovery required; new destination retained at %s\n' "${destinations[$j]}" >&2
            fi
          elif [ ! -L "${destinations[$j]}" ] && atomic_at "${destinations[$j]}" cmp -s "${destinations[$j]}" "${originals[$j]}"; then
            continue
          elif [ -L "${destinations[$j]}" ] || ! atomic_at "${destinations[$j]}" cmp -s "${destinations[$j]}" "${sources[$j]}"; then
            printf '::error::Recovery required; conflicting destination preserved at %s; original retained at %s\n' "${destinations[$j]}" "${originals[$j]}" >&2
            originals[j]=''
          elif ! atomic_at "${destinations[$j]}" mv -f "$nofollow" "${originals[$j]}" "${destinations[$j]}"; then
            printf '::error::Recovery required; original retained at %s\n' "${originals[$j]}" >&2
            originals[j]=''
          fi
        done
        break
      fi
    done
  fi
  for next in ${replacements[@]+"${replacements[@]}"}; do atomic_at "$next" rm -f "$next" || failed=1; done
  for original in ${originals[@]+"${originals[@]}"}; do [ -z "$original" ] || atomic_at "$original" rm -f "$original" || failed=1; done
  [ "$failed" -eq 0 ] || { echo '::error::Batch replacement failed.' >&2; return 1; }
)
