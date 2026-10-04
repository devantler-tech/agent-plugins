#!/usr/bin/env bash
# Replace a validated NUL-paired (destination, staged source) batch without
# truncating live files. Helpers share one checkout-root lock through snapshots,
# replacement and recovery. Uncontended originals are restored; a conflict or
# failed recovery keeps its backup beside the destination for the operator.
# The optional second argument, true, permits creating previously absent destinations.
atomic_write_batch() (
  local lock=.agent-plugin-write.lock lock_rc=0
  if ! mkdir "$lock" 2>/dev/null; then
    echo '::error::Generated writes are already locked; inspect the existing writer before retrying.' >&2
    return 1
  fi
  # The subshell keeps this cleanup independent of each caller's staging trap.
  trap 'lock_rc=$?; if ! rmdir "$lock"; then echo "::error::Recovery required; generated-write lock retained." >&2; lock_rc=1; fi; exit "$lock_rc"' EXIT
  local plan=$1 allow_new=${2:-false} destination='' staged='' next original i failed=0
  local destinations=() replacements=() originals=() sources=()
  while IFS= read -r -d '' destination; do
    if ! IFS= read -r -d '' staged; then failed=1; break; fi
    if [ -L "$destination" ] || [ ! -f "$staged" ] ||
       { [ ! -f "$destination" ] && { [ "$allow_new" != true ] || [ -e "$destination" ]; }; }; then failed=1; break; fi
    original=''
    if [ -f "$destination" ]; then
      original=$(mktemp "$destination.original.XXXXXX") || { failed=1; break; }
    fi
    originals+=("$original")
    destinations+=("$destination")
    sources+=("$staged")
    next=$(mktemp "$destination.next.XXXXXX") || { failed=1; break; }
    replacements+=("$next")
    if { [ -n "$original" ] && { ! cp -p "$destination" "$original" || ! cp -p "$destination" "$next"; }; } ||
       ! cp "$staged" "$next"; then
      failed=1; break
    fi
  done < "$plan"
  [ -z "$destination" ] || failed=1
  if [ "$failed" -eq 0 ]; then
    # Refuse a moved target before the first replacement.
    for i in "${!destinations[@]}"; do
      if [ -L "${destinations[$i]}" ] ||
         { [ -n "${originals[$i]}" ] && ! cmp -s "${destinations[$i]}" "${originals[$i]}"; } ||
         { [ -z "${originals[$i]}" ] && [ -e "${destinations[$i]}" ]; }; then failed=1; break; fi
    done
  fi
  if [ "$failed" -eq 0 ]; then
    for i in "${!destinations[@]}"; do
      if ! mv -f "${replacements[$i]}" "${destinations[$i]}"; then
        failed=1
        local j
        for j in "${!destinations[@]}"; do
          [ "$j" -le "$i" ] || continue
          # Supported helpers cannot interleave while this lock is held. Preserve
          # any outside edit already visible before restoring our staged bytes.
          if [ -z "${originals[$j]}" ]; then
            # Remove only a new file whose bytes still match this batch's staged source.
            if [ ! -e "${destinations[$j]}" ] && [ ! -L "${destinations[$j]}" ]; then continue; fi
            if [ -L "${destinations[$j]}" ] || ! cmp -s "${destinations[$j]}" "${sources[$j]}" ||
               ! rm -f "${destinations[$j]}"; then
              printf '::error::Recovery required; new destination retained at %s\n' "${destinations[$j]}" >&2
            fi
          elif [ ! -L "${destinations[$j]}" ] && cmp -s "${destinations[$j]}" "${originals[$j]}"; then
            continue
          elif [ -L "${destinations[$j]}" ] || ! cmp -s "${destinations[$j]}" "${sources[$j]}"; then
            printf '::error::Recovery required; conflicting destination preserved at %s; original retained at %s\n' "${destinations[$j]}" "${originals[$j]}" >&2
            originals[j]=''
          elif ! mv -f "${originals[$j]}" "${destinations[$j]}"; then
            printf '::error::Recovery required; original retained at %s\n' "${originals[$j]}" >&2
            originals[j]=''
          fi
        done
        break
      fi
    done
  fi
  for next in ${replacements[@]+"${replacements[@]}"}; do rm -f "$next"; done
  for original in ${originals[@]+"${originals[@]}"}; do [ -z "$original" ] || rm -f "$original"; done
  [ "$failed" -eq 0 ] || { echo '::error::Batch replacement failed.' >&2; return 1; }
)
