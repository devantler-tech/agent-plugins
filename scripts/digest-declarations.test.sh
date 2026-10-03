#!/usr/bin/env bash
# Drive the shipped generator against complete and incomplete declarations.
set -Eeuo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
refresh="$here/refresh-desired-state-digests.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0
# Accumulate behavioral failures so every independent refusal is exercised.
check() { if "$@"; then printf 'PASS %s\n' "$label"; else printf 'FAIL %s\n' "$label"; fail=$((fail+1)); fi; }
# A valid resource gives each refusal case a writable sibling to preserve.
fixture() {
  root=$(mktemp -d "$work/case.XXXXXX")
  mkdir -p "$root/plugins/alpha/agents" "$root/plugins/alpha/scripts" "$root/plugins/alpha/resources" "$root/bin"
  printf 'definition\n' > "$root/plugins/alpha/agents/alpha.agent.md"
  printf '#!/bin/sh\nexit 0\n' > "$root/plugins/alpha/scripts/asset.sh"
  chmod +x "$root/plugins/alpha/scripts/asset.sh"
  resource="$root/plugins/alpha/resources/a.desired-state.json"
  printf '%s\n' '{"spec":{"source":{"entrypoint":"alpha","entrypointSha256":"stale","requiredRuntimeAssets":[{"path":"scripts/asset.sh","sha256":"stale","executable":true}]},"roles":{}}}' > "$resource"
  cp -R "$root/plugins/alpha" "$root/plugins/beta"
}
# Capture the actual generator's result without terminating the remaining cases.
run() { rc=0; (cd "$root" && PATH="$root/bin:$PATH" bash "$refresh" "$@") > "$root/out" 2>&1 || rc=$?; }
# Mutate only a declaration; retain independent original bytes for both resources.
mutate() { jq "$1" "$resource" > "$root/new"; cp "$root/new" "$resource"; }
# Snapshot both the defective resource and its writable sibling independently.
save() { cp "$resource" "$root/alpha-before"; cp "$root/plugins/beta/resources/a.desired-state.json" "$root/beta-before"; }
# Verify that refusal protected the entire batch, including a linked backing file.
preserved() { cmp -s "$resource" "$root/alpha-before" && cmp -s "$root/plugins/beta/resources/a.desired-state.json" "$root/beta-before"; }
for mode in write check; do
  args=(); [[ $mode != check ]] || args=(--check)
  for fault in prefix linked-root repeated-leaf repeated-container shape repeated-asset executable; do
    fixture
    case $fault in
      prefix)
        cat > "$root/bin/find" <<'EOF'
#!/bin/sh
printf 'plugins/alpha/resources/a.desired-state.json\000'
EOF
        chmod +x "$root/bin/find" ;;
      linked-root)
        mv "$root/plugins/alpha" "$root/outside"
        ln -s "$root/outside" "$root/plugins/alpha" ;;
      repeated-leaf)
        printf '%s\n' '{"spec":{"source":{"entrypoint":"missing","entrypoint":"alpha","entrypointSha256":"stale"},"roles":{}}}' > "$resource" ;;
      repeated-container)
        printf '%s\n' '{"spec":{"source":{"requiredRuntimeAssets":[{"path":"missing","sha256":"stale","executable":true}]},"source":{"entrypoint":"alpha","entrypointSha256":"stale"},"roles":{}}}' > "$resource" ;;
      shape) mutate '.spec.source.requiredRuntimeAssets = "not-an-inventory"' ;;
      repeated-asset) mutate '.spec.source.requiredRuntimeAssets += .spec.source.requiredRuntimeAssets' ;;
      executable) chmod -x "$root/plugins/alpha/scripts/asset.sh" ;;
    esac
    save
    run ${args[@]+"${args[@]}"}
    label="$fault $mode refuses incomplete declarations"; check test "$rc" -ne 0
    label="$fault $mode preserves every resource"; check preserved
    # A check-mode failure must identify invalid evidence, rather than ordinary stale digests.
    label="$fault $mode reports an invalid observation"; check grep -Eq 'inventory|linked|declaration|executable|duplicate' "$root/out"
  done
done
fixture
run
label='ordinary refresh succeeds'; check test "$rc" -eq 0
expected=$(printf 'definition\n' | shasum -a 256 | awk '{print $1}')
label='ordinary refresh pins the actual definition'; check test "$(jq -r '.spec.source.entrypointSha256' "$resource")" = "$expected"
save; run --check
label='complete current inventory reports current'; check test "$rc" -eq 0
label='current check preserves resources'; check preserved
printf 'digest declarations: %s failure(s)\n' "$fail"
test "$fail" -eq 0
