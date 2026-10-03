#!/usr/bin/env bash
# Replace a validated NUL-paired (destination, staged source) batch without
# truncating live files. Failed commits restore originals; failed recovery keeps
# its backup beside the destination for the operator rather than deleting it.
atomic_write_batch() {
  local plan=$1 destination='' staged='' next original i failed=0
  local destinations=() replacements=() originals=()
  while IFS= read -r -d '' destination; do
    if ! IFS= read -r -d '' staged; then failed=1; break; fi
    if [ ! -f "$destination" ] || [ -L "$destination" ] || [ ! -f "$staged" ]; then failed=1; break; fi
    original=$(mktemp "$destination.original.XXXXXX") || { failed=1; break; }
    originals+=("$original")
    destinations+=("$destination")
    next=$(mktemp "$destination.next.XXXXXX") || { failed=1; break; }
    replacements+=("$next")
    if ! cp -p "$destination" "$original" || ! cp -p "$destination" "$next" || ! cp "$staged" "$next"; then
      failed=1; break
    fi
  done < "$plan"
  [ -z "$destination" ] || failed=1
  if [ "$failed" -eq 0 ]; then
    # Refuse a moved target before the first replacement.
    for i in "${!destinations[@]}"; do
      if ! cmp -s "${destinations[$i]}" "${originals[$i]}"; then failed=1; break; fi
    done
  fi
  if [ "$failed" -eq 0 ]; then
    for i in "${!destinations[@]}"; do
      if ! mv -f "${replacements[$i]}" "${destinations[$i]}"; then
        failed=1
        local j
        for j in "${!destinations[@]}"; do
          # Restore even the failing destination: a producer may have changed it
          # before returning failure. A backup survives any failed restoration.
          if ! mv -f "${originals[$j]}" "${destinations[$j]}"; then
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
}
