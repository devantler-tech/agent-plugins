#!/usr/bin/env bash
# Exercise the complete package gate before any linked onboarding bytes are read.
set -euo pipefail
here=${PACKAGE_SOURCE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git -C "$here/.." archive HEAD > "$work/package.tar"
fail=0
for scenario in healthy empty-resources canonical-internal canonical-external canonical-malformed \
  canonical-dangling canonical-directory canonical-fifo canonical-parent \
  optional-internal optional-external optional-dangling optional-directory optional-fifo \
  optional-parent optional-parent-empty resources-file; do
  root="$work/$scenario"; mkdir -p "$root"
  tar -xf "$work/package.tar" -C "$root"
  canonical="$root/plugins/agentic-engineering/resources/provider-neutral.desired-state.json"
  candidate="$root/plugins/agentic-engineering/resources/other.desired-state.json"
  diagnostic='regular packaged desired-state file'
  expected=reject
  case "$scenario" in
    healthy) expected=pass ;;
    empty-resources) mkdir -p "$root/plugins/go/resources"; expected=pass ;;
    canonical-internal)
      mv "$canonical" "$root/plugins/agentic-engineering/original.json"
      ln -s ../original.json "$canonical" ;;
    canonical-external|canonical-malformed)
      cp "$canonical" "$work/$scenario.json"
      if [ "$scenario" = canonical-malformed ]; then
        printf '%s\n' '{"kind":"AgenticEngineeringDesiredState","spec":null}' > "$work/$scenario.json"
      fi
      rm "$canonical"; ln -s "$work/$scenario.json" "$canonical" ;;
    canonical-dangling) rm "$canonical"; ln -s absent.json "$canonical" ;;
    canonical-directory) rm "$canonical"; mkdir "$canonical" ;;
    canonical-fifo) rm "$canonical"; mkfifo "$canonical" ;;
    canonical-parent)
      mv "$root/plugins/agentic-engineering/resources" "$root/original-resources"
      ln -s "$root/original-resources" "$root/plugins/agentic-engineering/resources"
      diagnostic='regular packaged resources directory' ;;
    optional-internal) ln -s provider-neutral.desired-state.json "$candidate" ;;
    optional-external) cp "$canonical" "$work/$scenario.json"; ln -s "$work/$scenario.json" "$candidate" ;;
    optional-dangling) ln -s absent.json "$candidate" ;;
    optional-directory) mkdir "$candidate" ;;
    optional-fifo) mkfifo "$candidate" ;;
    optional-parent|optional-parent-empty)
      mkdir -p "$root/original-resources"
      if [ "$scenario" = optional-parent ]; then cp "$canonical" "$root/original-resources/other.desired-state.json"; fi
      ln -s "$root/original-resources" "$root/plugins/go/resources"
      diagnostic='regular packaged resources directory' ;;
    resources-file)
      printf 'not a directory\n' > "$root/plugins/go/resources"
      diagnostic='regular packaged resources directory' ;;
  esac
  rc=0
  (cd "$root" && bash "$here/validate-manifests.sh") > "$root/out" 2>&1 || rc=$?
  if { [ "$expected" = pass ] && [ "$rc" -eq 0 ] && grep -Fq '✓ desired state plugins/agentic-engineering/resources/provider-neutral.desired-state.json' "$root/out"; } ||
     { [ "$expected" = reject ] && [ "$rc" -ne 0 ] && grep -Fq "$diagnostic" "$root/out"; }; then
    printf 'PASS desired-state-%s\n' "$scenario"
  else
    printf 'FAIL desired-state-%s exit=%s\n' "$scenario" "$rc"
    cat "$root/out"; fail=$((fail+1))
  fi
done
# Producer completion is part of the direct resources-parent census. Plausible
# first records cannot hide a second parent or an unterminated final record.
real_find=$(command -v find)
mkdir -p "$work/bin"
cat > "$work/bin/find" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "$*" = "plugins -path */resources/*.desired-state.json -print0" ]; then
  case "$RESOURCE_FIND_MODE" in
    files-empty) exit 0 ;;
    files-omitted) printf 'plugins/agentic-engineering/resources/other.desired-state.json\0'; exit 0 ;;
  esac
fi
if [ "$*" != 'plugins -mindepth 2 -maxdepth 2 -name resources -print0' ]; then exec "$RESOURCE_FIND_REAL" "$@"; fi
case "$RESOURCE_FIND_MODE" in files-*) exec "$RESOURCE_FIND_REAL" "$@" ;; esac
"$RESOURCE_FIND_REAL" "$@" > "$RESOURCE_FIND_WORK/parents"
case "$RESOURCE_FIND_MODE" in
  partial-failure)
    IFS= read -r -d '' first < "$RESOURCE_FIND_WORK/parents"
    printf '%s\0' "$first"; exit 1 ;;
  truncated)
    while IFS= read -r -d '' record; do printf '%s\0' "$record"; done < "$RESOURCE_FIND_WORK/parents"
    printf 'plugins/absent/resources' ;;
  empty-record) cat "$RESOURCE_FIND_WORK/parents"; printf '\0' ;;
esac
STUB
chmod +x "$work/bin/find"
for mode in partial-failure truncated empty-record; do
  root="$work/parents-$mode"; mkdir -p "$root"
  tar -xf "$work/package.tar" -C "$root"
  mkdir -p "$root/plugins/go/resources"
  case "$mode" in
    partial-failure) diagnostic='Could not enumerate desired-state resource parents' ;;
    truncated) diagnostic='Incomplete record in desired-state resource parents' ;;
    empty-record) diagnostic='Empty record in desired-state resource parents' ;;
  esac
  rc=0
  (cd "$root" && env PATH="$work/bin:$PATH" RESOURCE_FIND_REAL="$real_find" \
    RESOURCE_FIND_WORK="$work" RESOURCE_FIND_MODE="$mode" bash "$here/validate-manifests.sh") > "$root/out" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] && grep -Fq "$diagnostic" "$root/out"; then printf 'PASS desired-state-parents-%s\n' "$mode"
  else printf 'FAIL desired-state-parents-%s exit=%s\n' "$mode" "$rc"; cat "$root/out"; fail=$((fail+1)); fi
done
for mode in files-empty files-omitted; do
  root="$work/$mode"; mkdir -p "$root"
  tar -xf "$work/package.tar" -C "$root"
  canonical="$root/plugins/agentic-engineering/resources/provider-neutral.desired-state.json"
  if [ "$mode" = files-empty ]; then
    printf '%s\n' '{"kind":"AgenticEngineeringDesiredState","spec":null}' > "$canonical"
  else
    cp "$canonical" "$root/plugins/agentic-engineering/resources/other.desired-state.json"
    printf '\n[Other desired state](resources/other.desired-state.json)\n' >> "$root/plugins/agentic-engineering/README.md"
  fi
  rc=0
  (cd "$root" && env PATH="$work/bin:$PATH" RESOURCE_FIND_REAL="$real_find" \
    RESOURCE_FIND_WORK="$work" RESOURCE_FIND_MODE="$mode" bash "$here/validate-manifests.sh") > "$root/out" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] && grep -Fq 'canonical desired-state resource was not enumerated' "$root/out"; then printf 'PASS desired-state-%s\n' "$mode"
  else printf 'FAIL desired-state-%s exit=%s\n' "$mode" "$rc"; cat "$root/out"; fail=$((fail+1)); fi
done
printf 'desired-state boundaries: %s failure(s)\n' "$fail"
test "$fail" -eq 0
